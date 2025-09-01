## Local testing plan

### Prerequisites
- conda (Miniconda or Mambaforge)
- Node.js 18+ and npm
- Docker Desktop (optional, for local containers)

### Setup
1) Create and activate Python env
```bash
conda env create -f environment.yml
conda activate ctb
```

2) Install Node dependencies
```bash
npm install
```

### Run tests (fast feedback loop)
- Single command for both web and Python tests:
```bash
npm test
```
- Or run individually:
  - Python (pytest via conda): `conda run -n ctb pytest -q --maxfail=1 --disable-warnings`

### Run services locally (dev mode)
- API (FastAPI):
```bash
conda activate ctb
uvicorn services/api/app/main:app --reload --port 8000
```
- Worker unit tests (runner):
```bash
conda activate ctb
pytest workers/runner -q
```

### Optional: local containers with Docker Compose
This repo uses conda + bare processes for speed. If you prefer Docker locally, you can create a minimal Compose file (not committed) such as:
```yaml
version: "3.9"
services:
  api:
    build:
      context: .
      dockerfile: services/api/Dockerfile
    ports: ["8000:8000"]
    command: uvicorn app.main:app --host 0.0.0.0 --port 8000
  db:
    image: postgres:16
    environment:
      POSTGRES_PASSWORD: postgres
    ports: ["5432:5432"]
  redis:
    image: redis:7
    ports: ["6379:6379"]
```
Tradeoffs are discussed in docs/environments-and-security.md.

### Local Kubernetes with kind (recommended for parity)
1) Create cluster:
```bash
kind create cluster --config infra/k8s/local/kind-config.yaml
kubectl create namespace dev || true
kubectl create namespace prod || true
```
2) Build local images and load into kind:
```bash
docker build -t ctb-api:local -f services/api/Dockerfile .
docker build -t ctb-frontend:local --build-arg NEXT_PUBLIC_API_BASE=http://api.dev.svc.cluster.local -f apps/frontend/Dockerfile .
kind load docker-image ctb-api:local --name ctb-local
kind load docker-image ctb-frontend:local --name ctb-local
```
3) Apply dev manifests (they already reference local images `ctb-api:local` and `ctb-frontend:local`) and set images explicitly just in case:
```bash
kubectl -n dev apply -f infra/k8s/local/dev.yaml
kubectl -n dev set image deploy/api api=ctb-api:local
kubectl -n dev set image deploy/frontend frontend=ctb-frontend:local
```
4) Port-forward to access frontend:
```bash
kubectl -n dev port-forward svc/frontend 3000:80
# open http://localhost:3000
```

### Teardown AWS/EKS (stop cloud spend)

- Option A (recommended): via GitHub Actions
  - Go to GitHub → Actions → "Teardown (Destroy AWS + K8s)".
  - Click "Run workflow", pick the commit/branch, and type `DESTROY` to confirm.
  - This destroys the EKS cluster, ALBs, NAT Gateway, VPC, and ECR repos.

- Option B: locally with Terraform (requires AWS credentials)
  - Ensure your AWS CLI is authenticated (or you can assume the bootstrap role). Quick check:
    ```bash
    aws sts get-caller-identity
    ```
  - Dry-run first:
    ```bash
    cd infra/terraform
    terraform init -input=false
    terraform plan -destroy
    ```
  - Full destroy (irreversible):
    ```bash
    # Optional: purge ECR images to avoid RepositoryNotEmpty errors
    API_URL=$(terraform output -raw ecr_api_repo_url 2>/dev/null || echo "")
    FE_URL=$(terraform output -raw ecr_frontend_repo_url 2>/dev/null || echo "")
    for REPO_URL in "$API_URL" "$FE_URL"; do
      [[ -z "$REPO_URL" ]] && continue
      REPO_NAME="${REPO_URL##*/}"
      IDS=$(aws ecr list-images --repository-name "$REPO_NAME" --query 'imageIds' --output json || echo '[]')
      [[ "$(jq -r 'length' <<<"$IDS")" == "0" ]] || aws ecr batch-delete-image --repository-name "$REPO_NAME" --image-ids "$IDS" || true
    done
    terraform destroy -auto-approve
    ```

### Test data tiers (to mirror CI/CD)
- Tiny (50 encounters): PR checks under 2 min
- Standard (1,000): daily regression gate
- Stress (≥10,000): weekly scale run

### Linting and type checks (optional)
- Python format/lint (if adopted later): `ruff`, `black`, `mypy` (add to environment.yml when needed)
