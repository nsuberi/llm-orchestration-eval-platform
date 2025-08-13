#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Config
CLUSTER_NAME="ctb-local"
API_IMAGE_LOCAL="ctb-api:local"
FE_IMAGE_LOCAL="ctb-frontend:local"
DEV_NS="dev"
PROD_NS="prod"
PORT_FORWARD="yes"

while [[ ${1:-} == --* ]]; do
  case "$1" in
    --no-port-forward) PORT_FORWARD="no" ;; 
    *) echo "Unknown flag: $1"; exit 1;;
  esac
  shift || true
done

have() { command -v "$1" >/dev/null 2>&1; }
need() { if ! have "$1"; then return 1; else return 0; fi }

# Helper to wait until Docker daemon is ready
wait_for_docker() {
  local retries="${1:-60}"
  local delay="${2:-2}"
  local i=0
  until docker info >/dev/null 2>&1; do
    i=$((i+1))
    if [ "$i" -ge "$retries" ]; then
      echo "Docker daemon not ready after $((retries*delay))s."
      return 1
    fi
    sleep "$delay"
  done
  return 0
}

# Basic prereqs (install if possible)
if ! have docker; then
  if [[ "$OSTYPE" == darwin* ]] && have brew; then
    echo "Installing Docker Desktop via Homebrew cask..."
    brew install --cask docker || true
    echo "Launching Docker Desktop (first launch may require user interaction)..."
    open -a Docker || true
    echo "Waiting for Docker to start..."
    if ! wait_for_docker 120 2; then
      echo "Please complete Docker Desktop setup and re-run this script." >&2
      exit 1
    fi
  else
    echo "Docker not found. Please install Docker and re-run this script." >&2
    exit 1
  fi
fi

if ! docker info >/dev/null 2>&1; then
  if [[ "$OSTYPE" == darwin* ]]; then
    echo "Docker is installed but not running. Attempting to start Docker Desktop..."
    open -a Docker || true
    if ! wait_for_docker 120 2; then
      echo "Docker is not ready. Please ensure Docker Desktop is running and re-run this script." >&2
      exit 1
    fi
  else
    echo "Docker is installed but not running. Please start the Docker daemon and re-run this script." >&2
    exit 1
  fi
fi

# Install kind/kubectl via Homebrew if missing (macOS assumed)
if ! have kind; then
  echo "Installing kind via Homebrew..."
  brew install kind || { echo "Failed to install kind via Homebrew." >&2; exit 1; }
fi
if ! have kubectl; then
  echo "Installing kubectl via Homebrew..."
  brew install kubectl || { echo "Failed to install kubectl via Homebrew." >&2; exit 1; }
fi

# Python env via conda (optional but recommended for tests)
if have conda; then
  if ! conda env list | awk '{print $1}' | grep -q '^ctb$'; then
    echo "Creating conda env ctb..."
    conda env create -f environment.yml || conda env update -f environment.yml -n ctb
  else
    echo "Updating conda env ctb..."
    conda env update -f environment.yml -n ctb || true
  fi
else
  echo "conda not found; skipping Python env creation. Install Miniconda/Mambaforge for full tooling." >&2
fi

# Node.js
if have node; then
  NODE_V=$(node -v | sed 's/^v//')
  REQ_V="18.17.0"
  # naive semver compare
  verlt() { [ "$1" = "$(echo -e "$1\n$2" | sort -V | head -n1)" ] && [ "$1" != "$2" ]; }
  if verlt "$NODE_V" "$REQ_V"; then
    echo "Node $NODE_V detected (< $REQ_V)."
    if have brew; then
      echo "Installing Node 20 via Homebrew..."
      brew install node@20 || true
      echo "You may need to add node@20 to your PATH (e.g., echo 'export PATH=\"/opt/homebrew/opt/node@20/bin:$PATH\"' >> ~/.bashrc)"
    else
      echo "Please install Node >= $REQ_V (e.g., via nvm or installer)." >&2
    fi
  fi
else
  if have brew; then
    echo "Installing Node 20 via Homebrew..."
    brew install node@20 || true
  else
    echo "Node not found; please install Node >= 18.17.0." >&2
  fi
fi

# JS deps
echo "Installing npm workspaces dependencies..."
npm install

# Build local images
echo "Building local Docker images..."
docker build -t "$API_IMAGE_LOCAL" -f services/api/Dockerfile .
docker build -t "$FE_IMAGE_LOCAL" \
  --build-arg NEXT_PUBLIC_API_BASE="http://api.${DEV_NS}.svc.cluster.local" \
  -f apps/frontend/Dockerfile .

# Create kind cluster if needed
if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  echo "Creating kind cluster ${CLUSTER_NAME}..."
  kind create cluster --config infra/k8s/local/kind-config.yaml
else
  echo "kind cluster ${CLUSTER_NAME} already exists"
fi

# Namespaces
kubectl create namespace "$DEV_NS" >/dev/null 2>&1 || true
kubectl create namespace "$PROD_NS" >/dev/null 2>&1 || true

# Load images into kind
echo "Loading images into kind..."
kind load docker-image "$API_IMAGE_LOCAL" --name "$CLUSTER_NAME"
kind load docker-image "$FE_IMAGE_LOCAL" --name "$CLUSTER_NAME"

# Apply manifests and set images
echo "Applying dev manifests..."
kubectl -n "$DEV_NS" apply -f infra/k8s/local/dev.yaml
kubectl -n "$DEV_NS" set image deploy/api api="$API_IMAGE_LOCAL"
kubectl -n "$DEV_NS" set image deploy/frontend frontend="$FE_IMAGE_LOCAL"

echo "Waiting for dev deployments to be ready..."
kubectl -n "$DEV_NS" rollout status deploy/api --timeout=120s
kubectl -n "$DEV_NS" rollout status deploy/frontend --timeout=120s

echo "Local environment is ready."
echo "- Frontend service: namespace=$DEV_NS svc/frontend port 80"
echo "- API service:      namespace=$DEV_NS svc/api port 80 (target 8000)"

if [[ "$PORT_FORWARD" == "yes" ]]; then
  echo "Starting port-forwards (Ctrl+C to stop):"
  echo "- Frontend: http://localhost:3000 -> svc/frontend:80"
  echo "- API:      http://localhost:8000 -> svc/api:80"

  PF_PIDS=()

  # Start frontend port-forward in background
  kubectl -n "$DEV_NS" port-forward svc/frontend 3000:80 >/dev/null 2>&1 &
  PF_PIDS+=("$!")

  # Start API port-forward in background
  kubectl -n "$DEV_NS" port-forward svc/api 8000:80 >/dev/null 2>&1 &
  PF_PIDS+=("$!")

  # Cleanup on exit
  cleanup_pf() {
    echo
    echo "Stopping port-forwards..."
    for pid in "${PF_PIDS[@]}"; do
      if kill -0 "$pid" >/dev/null 2>&1; then
        kill "$pid" >/dev/null 2>&1 || true
      fi
    done
    # Give kubectl a moment to terminate gracefully
    sleep 0.5 || true
  }
  trap cleanup_pf INT TERM EXIT

  # Optional: wait until ports respond
  wait_until_ready() {
    local url="$1"; local name="$2"; local attempts=40; local delay=0.25
    if command -v curl >/dev/null 2>&1; then
      for i in $(seq 1 "$attempts"); do
        if curl -fsS "$url" >/dev/null 2>&1; then
          echo "$name is ready at $url"
          return 0
        fi
        sleep "$delay"
      done
      echo "Warning: $name did not respond at $url yet, continuing..."
    fi
  }

  wait_until_ready "http://localhost:3000" "Frontend"
  wait_until_ready "http://localhost:8000/healthz" "API"

  # Keep the script running while port-forwards are active
  wait
else
  echo "Run to access UI: kubectl -n $DEV_NS port-forward svc/frontend 3000:80"
  echo "Run to access API: kubectl -n $DEV_NS port-forward svc/api 8000:80"
fi
