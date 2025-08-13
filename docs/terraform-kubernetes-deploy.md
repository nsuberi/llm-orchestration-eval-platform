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
  - `terraform plan` (dev)
  - `terraform apply` (dev) on approval
- On tagged release (`v*`):
  - Build with pinned SHAs/tags
  - `terraform plan` (prod)
  - `terraform apply` (prod) requires manual approval and protected environment

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
