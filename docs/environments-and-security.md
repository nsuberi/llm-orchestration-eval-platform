## Environments, cluster topology, and security controls

### Docker Compose locally vs. Kubernetes in prod
**Benefits of Docker Compose locally**
- Fast iteration: fewer moving parts and simpler networking
- Lower resource usage on developer laptops
- Easy to run DB/Redis alongside app without cluster overhead

**Tradeoffs**
- Drift risk: Compose is not a perfect mirror of Kubernetes manifests
- Networking, DNS, and service discovery differ; bugs can hide until K8s
- Autoscaling, resource limits/requests, and probes are not exercised
- Secrets management differs (env files vs. K8s Secrets/External Secrets)

Recommendation: Use Compose sparingly for local convenience but validate critical flows in a dev Kubernetes environment.

### Two clusters vs. one cluster with namespaces
**Two clusters (dev, prod)**
- Isolation: strong blast-radius reduction; separate control planes
- Security: cluster-level IAM, separate VPCs, distinct node groups
- Cost: higher baseline cost, duplicated infra
- Ops: more to manage; drift risk between clusters

**One cluster, two namespaces (dev, prod)**
- Cost: cheaper, shared control plane and nodes
- Simpler operations; fewer moving parts
- Weaker isolation: noisy-neighbor effects, shared cluster IAM
- Risk: misconfiguration could cross-impact environments

Recommendation: For HIPAA-oriented workloads, prefer two clusters. If cost-constrained, start with namespaces and plan a migration path to dual clusters.

### Locking down production changes via GitHub Actions
- Use protected branches and required reviews for `main` (or `release/*`)
- Require PR approvals to run `terraform apply` to prod (manual approval job)
- Configure OpenID Connect (OIDC) from GitHub to cloud provider for short-lived credentials
- Production cluster:
  - Disable direct `kubectl` access for humans; read-only logs only
  - Enforce admission policies (OPA/Gatekeeper or Kyverno) for resource limits, images from approved registries, and required labels/annotations
  - Use `ImagePullPolicy: IfNotPresent` with immutable image tags (digest pins)
  - External Secrets Operator with access scoped to prod secrets only
- Dev cluster:
  - Allow limited `kubectl` access for developers via group IAM
  - Enable sandbox namespaces for experiments

### Promotion strategy
- Dev deploys on merge to `main`
- Run smoke tests and small-batch runs
- Tag a release when ready; prod deployment only from tags
- Use the same Helm chart/kustomize overlays with explicit values for prod (resource requests/limits, autoscaling, PDBs, topology spread)

### EKS API endpoint access (public vs private)
The EKS control plane exposes an API endpoint that can be reachable privately (inside your VPC), publicly (internet), or both. Our Terraform wrapper exposes:

- `cluster_endpoint_private_access` (default: true)
- `cluster_endpoint_public_access` (default: true in this repo to simplify bootstrap)
- `cluster_endpoint_public_access_cidrs` (default: ["0.0.0.0/0"], recommended to restrict)

Considerations by deployment context:

- Local development machine (outside VPC)
  - Necessity: Requires the public endpoint unless your laptop has a private network path into the VPC (VPN/Direct Connect) or you run Terraform from within the VPC.
  - More secure options:
    - Temporarily enable public endpoint with a narrow allowlist (e.g., your current public IP `/32`), then disable after bootstrapping.
    - Run Terraform from a self-hosted runner or workstation inside the VPC (e.g., EC2 with SSM Session Manager access). Keep endpoint private-only.

- Public GitHub-hosted runners
  - Necessity: They do not have VPC access, so they require the public endpoint to use the Terraform Kubernetes provider.
  - Risks: GitHub egress IP ranges are broad and change; allowlisting those ranges is brittle and widens exposure.
  - More secure options:
    - Use self-hosted GitHub Actions runners inside your VPC/subnets. Keep endpoint private-only.
    - Split responsibilities: run Terraform for AWS infra from public runners (no K8s provider), and run Kubernetes changes from a private runner or in-cluster job.

Security implications of enabling the public endpoint:
- Increased attack surface: the control plane is reachable over the internet at limited IP ranges.
- Mitigations:
  - Restrict `cluster_endpoint_public_access_cidrs` to the smallest set possible (ideally specific `/32` egress IPs you control).
  - Use short-lived AWS credentials (OIDC/STSes) and least-privilege IAM; pair with least-privilege Kubernetes RBAC.
  - Enable EKS control plane audit logs and monitor for anomalous authZ failures.
  - Disable the public endpoint after initial setup if ongoing internet access is unnecessary.

Recommended patterns:
- For local bootstrap: enable public endpoint briefly with a `/32` allowlist; complete setup; then either restrict further or disable.
- For CI/CD: prefer self-hosted runners in the VPC with a private-only endpoint. If you must use public runners, restrict public CIDRs tightly, and consider moving Kubernetes mutations to a private context.
