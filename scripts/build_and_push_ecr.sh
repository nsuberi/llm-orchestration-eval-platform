#!/usr/bin/env bash
set -euo pipefail

# Build and push local images to Terraform-provisioned ECR repositories.
#
# Usage:
#   bash scripts/build_and_push_ecr.sh \
#     [-r <aws_region>] [--api-dockerfile <path>] [--frontend-dockerfile <path>] \
#     [--api-context <dir>] [--frontend-context <dir>] [--tag <tag>] [--profile <aws_profile>] \
#     [--platform <os/arch>] [--skip-frontend] [--skip-api]
#
# Defaults:
#   - region:            us-east-1
#   - api-dockerfile:    services/api/Dockerfile
#   - frontend-dockerfile: apps/frontend/Dockerfile
#   - api-context:       .
#   - frontend-context:  .
#   - tag:               latest
#   - platform:          linux/amd64
#
# Requires: aws, docker, terraform, jq

REGION="us-east-1"
API_DOCKERFILE="services/api/Dockerfile"
FRONT_DOCKERFILE="apps/frontend/Dockerfile"
API_CONTEXT="."
FRONT_CONTEXT="."
TAG="latest"
PROFILE_FLAG=""
SKIP_API=0
SKIP_FRONTEND=0
PLATFORM="linux/amd64"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--region) REGION="$2"; shift 2 ;;
    --api-dockerfile) API_DOCKERFILE="$2"; shift 2 ;;
    --frontend-dockerfile) FRONT_DOCKERFILE="$2"; shift 2 ;;
    --api-context) API_CONTEXT="$2"; shift 2 ;;
    --frontend-context) FRONT_CONTEXT="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    --profile) PROFILE_FLAG="--profile $2"; shift 2 ;;
    --platform) PLATFORM="$2"; shift 2 ;;
    --skip-api) SKIP_API=1; shift ;;
    --skip-frontend) SKIP_FRONTEND=1; shift ;;
    -h|--help) sed -n '1,80p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 127; }; }
need_cmd aws
need_cmd docker
need_cmd terraform
need_cmd jq

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
TF_DIR="$REPO_ROOT/infra/terraform"

if [[ ! -d "$TF_DIR" ]]; then
  echo "Terraform directory not found at $TF_DIR" >&2; exit 1
fi

pushd "$TF_DIR" >/dev/null
API_REPO=$(terraform output -raw ecr_api_repo_url)
FRONT_REPO=$(terraform output -raw ecr_frontend_repo_url)
popd >/dev/null

ACCOUNT_REGISTRY=$(echo "$API_REPO" | cut -d/ -f1)

echo "Logging into ECR: $ACCOUNT_REGISTRY (region: $REGION)"
aws $PROFILE_FLAG ecr get-login-password --region "$REGION" | \
  docker login --username AWS --password-stdin "$ACCOUNT_REGISTRY"

USE_BUILDX=0
if docker buildx version >/dev/null 2>&1; then
  USE_BUILDX=1
fi

build_and_push() {
  local image="$1"; shift
  local dockerfile="$1"; shift
  local context_dir="$1"; shift

  echo "Building $image (platform: $PLATFORM)"
  if [[ $USE_BUILDX -eq 1 ]]; then
    docker buildx build \
      --platform "$PLATFORM" \
      -t "$image:$TAG" \
      -f "$REPO_ROOT/$dockerfile" \
      "$REPO_ROOT/$context_dir" \
      --push
  else
    DOCKER_BUILDKIT=1 docker build \
      --platform "$PLATFORM" \
      -t "$image:$TAG" \
      -f "$REPO_ROOT/$dockerfile" \
      "$REPO_ROOT/$context_dir"
    echo "Pushing $image:$TAG"
    docker push "$image:$TAG"
  fi
}

if [[ $SKIP_API -eq 0 ]]; then
  build_and_push "$API_REPO" "$API_DOCKERFILE" "$API_CONTEXT"
fi

if [[ $SKIP_FRONTEND -eq 0 ]]; then
  build_and_push "$FRONT_REPO" "$FRONT_DOCKERFILE" "$FRONT_CONTEXT"
fi

echo "Done. Images pushed:"
[[ $SKIP_API -eq 0 ]] && echo "  $API_REPO:$TAG"
[[ $SKIP_FRONTEND -eq 0 ]] && echo "  $FRONT_REPO:$TAG"
