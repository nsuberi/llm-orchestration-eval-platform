## Troubleshooting Kubernetes rollout timeouts (0 replicas Ready)

This guide helps debug Terraform errors like:
- Waiting for rollout to finish: N replicas wanted; 0 replicas Ready

### Preconditions
- You can authenticate to the cluster used by Terraform.
```bash
# Ensure kubectl context points to the EKS cluster
aws eks update-kubeconfig --name $(terraform output -raw cluster_name) --region ${AWS_REGION:-us-east-1}
```

### Quick triage
- Check objects and pod status:
```bash
kubectl -n dev get deploy,po
kubectl -n prod get deploy,po
```
- Describe the deployment and pods for hints (events, conditions):
```bash
kubectl -n dev describe deploy api
kubectl -n dev get events --sort-by=.lastTimestamp | tail -n 30
kubectl -n dev describe pod -l app=api
kubectl -n dev logs -l app=api --tail=200 --all-containers
```
Repeat for `frontend` and for the `prod` namespace.

## Common causes and fixes

### ImagePullBackOff / ErrImagePull
- **Symptoms**: Pods stuck in `ImagePullBackOff` / `ErrImagePull`.
- **Likely causes**:
  - Image tag does not exist in ECR (e.g., `:latest` not pushed yet).
  - Wrong ECR repository/region or cross-account repo.
  - Nodes lack permission to pull from ECR.
  - No internet/NAT or ECR/S3 VPC endpoints from private subnets.
- **Checks**:
  - Inspect pod state and events:
    ```bash
    kubectl -n dev get po
    kubectl -n dev describe pod <pod-name>
    ```
  - Confirm ECR images exist for expected tag:
    ```bash
    API_REPO=$(terraform output -raw ecr_api_repo_url)
    FRONT_REPO=$(terraform output -raw ecr_frontend_repo_url)
    aws ecr describe-images --repository-name ${API_REPO##*/} \
      --query 'imageDetails[].imageTags' --output table
    aws ecr describe-images --repository-name ${FRONT_REPO##*/} \
      --query 'imageDetails[].imageTags' --output table
    ```
  - Verify node IAM role has ECR pull policy (`AmazonEC2ContainerRegistryReadOnly`).
  - If nodes are in private subnets, verify NAT gateway or ECR/S3 interface endpoints exist.
- **Fixes**:
  - Build and push images to the Terraform-created repos (assumes `:latest`):
    ```bash
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    REGION=${AWS_REGION:-us-east-1}
    API_REPO=$(terraform output -raw ecr_api_repo_url)
    FRONT_REPO=$(terraform output -raw ecr_frontend_repo_url)

    aws ecr get-login-password --region $REGION | \
      docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

    # Build and push API
    docker build -t $API_REPO:latest -f services/api/Dockerfile .
    docker push $API_REPO:latest

    # Build and push Frontend
    docker build -t $FRONT_REPO:latest -f apps/frontend/Dockerfile .
    docker push $FRONT_REPO:latest
    ```
  - Or update the deployment images to a specific tag/digest that exists:
    ```bash
    kubectl -n dev set image deploy/api api=$API_REPO:<tag>
    kubectl -n dev set image deploy/frontend frontend=$FRONT_REPO:<tag>
    ```

### CrashLoopBackOff
- **Symptoms**: Pod repeatedly restarts with `CrashLoopBackOff`.
- **Likely causes**: App startup errors, missing env/config/secrets, wrong command/port.
- **Checks**:
  - Logs and last exit code:
    ```bash
    kubectl -n dev logs -l app=api --tail=200 --all-containers
    kubectl -n dev describe pod -l app=api | sed -n '/Last State/,+8p'
    ```
  - Validate container ports and probes match the app:
    - API expects port `8000` and `/healthz` readiness/liveness.
    - Frontend expects port `3000`.
- **Fixes**:
  - Correct environment variables, command/args, or health checks.
  - Temporarily relax probes to confirm the app starts, then tighten.

### Readiness/liveness probe failures
- **Symptoms**: Pod stays `Running` but never `Ready`; events show probe failures.
- **Checks**:
  - Endpoint paths and ports exist and respond within probe timeouts.
  - Probe initial delays are sufficient for cold starts.
- **Fixes**:
  - Update probe paths/ports/delays in the deployment; re-apply.

### Pending pods (0/… nodes available)
- **Symptoms**: Pods `Pending` with scheduler messages.
- **Likely causes**: Insufficient CPU/memory, node group not ready, taints/tolerations missing, CNI issues.
- **Checks**:
  ```bash
  kubectl get nodes -o wide
  kubectl -n kube-system get po
  kubectl -n dev describe pod <pod-name>
  ```
  - Look for: `Insufficient cpu/memory`, `node(s) had taints`, CNI (`aws-node`) or DNS (`coredns`) failures.
- **Fixes**:
  - Increase node group size or instance type; remove taints or add tolerations.
  - Ensure VPC/CNI is healthy; re-create nodes if needed.

### RBAC/authorization
- **Symptoms**: Terraform or `kubectl` get `Unauthorized` when creating resources.
- **Fixes**:
  - Ensure EKS access entries include the Terraform caller (enabled in this repo).
  - Re-run Terraform to reconcile access entries.

## Terraform-specific considerations
- Deployments in this repo are wired to ECR repos with the `:latest` tag:
  - `api_image = "${module.ecr.api_repo_url}:latest"`
  - `frontend_image = "${module.ecr.frontend_repo_url}:latest"`
- **Order of operations**:
  - Create infra (ECR, EKS), push images, then apply Kubernetes resources.
  - Alternatively, change images to known tags/digests produced by CI.
- **Re-trigger rollout after a fix**:
```bash
kubectl -n dev rollout status deploy/api
kubectl -n dev rollout restart deploy/api
kubectl -n dev rollout status deploy/frontend
```

## Networking checks (private subnets)
- Nodes in private subnets must reach ECR endpoints:
  - Ensure NAT gateway routes or create VPC interface endpoints for `ecr.api`, `ecr.dkr`, and `s3`.
  - Verify security groups and NACLs allow egress to required services.

## When in doubt
- Capture the last 50 events in the namespace and logs of failing pods; 90% of rollout stalls are due to image pulls, app crashes, or probe misconfig.
```bash
kubectl -n dev get events --sort-by=.lastTimestamp | tail -n 50
kubectl -n dev logs -l app=api --tail=200 --all-containers
kubectl -n dev logs -l app=frontend --tail=200 --all-containers
```