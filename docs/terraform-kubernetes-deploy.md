## Terraform + Kubernetes deployment plan

### Goals
- Reproducible infra for API, workers, and Postgres/Redis
- Horizontal scale for batch runs
- Clear separation between dev and prod

### High-level architecture
- Kubernetes (EKS/GKE/AKS, or self-managed)
- In-cluster:
  - API (FastAPI) Deployment + Service + Ingress
  - Runner workers (Job/HorizontalPodAutoscaler or K8s Job + KEDA)
  - Postgres (managed preferred) and Redis (managed or in-cluster)
  - S3-compatible object storage (managed)
  - Secrets via External Secrets Operator

### Terraform structure
- `infra/terraform/` with modules:
  - `modules/cluster` (EKS/GKE cluster, node groups)
  - `modules/postgres` (RDS/CloudSQL)
  - `modules/redis` (Elasticache/Memorystore)
  - `modules/network` (VPC, subnets, NAT, security groups)
  - `modules/app` (Helm releases/manifests for api, workers, ext-secrets)
- Environments:
  - `envs/dev` and `envs/prod` with per-env `tfvars`

### CI pipeline (GitHub Actions)
- On merge to `main`:
  - Build and push images to registry
  - `terraform plan` (dev) and `terraform apply` (dev)
  - Prod is NOT deployed by default
- On tagged release (`v*`):
  - Build with pinned SHAs/tags
  - `terraform plan` (prod)
  - `terraform apply` (prod) requires manual approval and protected environment

### Cost profile and defaults
- EKS control plane: ~$73/month per cluster in us-east-1 (always-on).
- Node groups (EC2): varies by instance size and count.
  - Dev default: `t3.small`, desired=1, min=1, max=2 (approx ~$16–$20/mo per node on-demand + EBS)
  - Prod default: `t3.large`, desired=2, min=2, max=4 (approx ~$70–$80/mo per node on-demand + EBS)
- NAT Gateway (enabled, single): ~$32/month + data processing ($0.045/GB). This is often a major hidden cost if there is egress.
- Load Balancer (ALB for frontend Ingress): ~$16+/month + LCUs depending on traffic.

Defaults chosen in this repo:
- Prod is disabled by default (`enable_prod=false`).
- Dev nodes are smaller and cheaper than prod.
- You can further reduce costs by switching dev capacity to SPOT and/or scaling min to 0 with Cluster Autoscaler/Karpenter.

To change sizes:
- Edit `infra/terraform/modules/eks/variables.tf` to adjust:
  - `dev_instance_types`, `dev_desired_size`, `dev_min_size`, `dev_max_size`, `dev_capacity_type`
  - `prod_instance_types`, `prod_desired_size`, `prod_min_size`, `prod_max_size`, `prod_capacity_type`

To deploy prod manually in CI:
- In GitHub Actions → Deploy workflow → Run workflow, set `deploy_prod=true`.
- Or tag a release (`vX.Y.Z`) which triggers the prod job with approval.

### Kubernetes resources (Helm chart or kustomize)
- API:
  - Deployment with liveness/readiness probes
  - Service (ClusterIP) + Ingress (TLS)
  - HorizontalPodAutoscaler based on CPU/RPS
- Workers:
  - Job/Queue consumer Deployment (RQ/Celery)
  - Optionally KEDA for queue-driven autoscaling
- Batch runs:
  - K8s Job or `batch/v1` `Job` templates (or `HorizontalRunner` pattern)
- Config:
  - ConfigMaps for prompts, DSL graphs (or pull from object store)
  - Secrets via External Secrets Operator

### State & storage
- Postgres: managed (RDS/Cloud SQL) with automated backups and PITR
- Redis: managed (ElastiCache/Memorystore)
- Object storage: S3/GCS bucket with lifecycle rules

### Example workflow
1) Dev merges code; CI builds images and deploys to dev
2) QA/tests run against dev cluster using small dataset
3) Tag release; CI deploys to prod with change approvals

### Observability
- Logs: Cloud provider logs or EFK
- Metrics: Prometheus + Grafana
- Traces: OpenTelemetry collector to provider (e.g., Tempo, X-Ray)
