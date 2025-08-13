## Local Kubernetes (kind) setup

This lets you run all resources locally with a minimal K8s that mirrors core features of cloud clusters.

### Prereqs
- Docker Desktop
- kind (`go install sigs.k8s.io/kind@latest` or use binaries)
- kubectl

### Create cluster
```bash
kind create cluster --config infra/k8s/local/kind-config.yaml
kubectl cluster-info --context kind-ctb-local
```

### Namespaces
```bash
kubectl create namespace dev || true
kubectl create namespace prod || true
```

### Ingress (optional)
If you want real hostnames, install ingress-nginx.
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
```
This repo uses ClusterIP for services; the frontend talks to the API via cluster DNS, so ingress is optional.

### Deploy manifests
For local testing, apply minimal manifests that match Terraform’s resources.
```bash
kubectl -n dev apply -f infra/k8s/local/dev.yaml
kubectl -n prod apply -f infra/k8s/local/prod.yaml
```

### Access services
- Frontend (dev):
```bash
kubectl -n dev port-forward svc/frontend 3000:80
```
Open http://localhost:3000, which will call the API at `http://api.dev.svc.cluster.local`.

- API (dev) direct port-forward:
```bash
kubectl -n dev port-forward svc/api 8000:80
```

### Clean up
```bash
kind delete cluster --name ctb-local
```
