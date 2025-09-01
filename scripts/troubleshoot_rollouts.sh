#!/usr/bin/env bash
set -euo pipefail

# Troubleshoot stalled rollouts and aggregate logs from Kubernetes and CloudWatch.
#
# Usage:
#   bash scripts/troubleshoot_rollouts.sh \
#     [-c <cluster_name>] [-r <aws_region>] [-n "dev,prod"] [-d <minutes>] [-o <out_dir>] [--profile <aws_profile>]
#
# Defaults:
#   - cluster_name: terraform output from infra/terraform
#   - aws_region:   us-east-1
#   - namespaces:   dev,prod
#   - minutes:      60 (lookback window for CloudWatch)
#   - out_dir:      artifacts/rollout-debug-<cluster>-<timestamp>
#
# Requirements: aws, kubectl, terraform, jq, docker (optional for image tests)

PROFILE_FLAG=""
CLUSTER_NAME=""
REGION="us-east-1"
NAMESPACES="dev,prod"
LOOKBACK_MINUTES=60
OUT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--cluster)
      CLUSTER_NAME="$2"; shift 2 ;;
    -r|--region)
      REGION="$2"; shift 2 ;;
    -n|--namespaces)
      NAMESPACES="$2"; shift 2 ;;
    -d|--minutes)
      LOOKBACK_MINUTES="$2"; shift 2 ;;
    -o|--out)
      OUT_DIR="$2"; shift 2 ;;
    --profile)
      PROFILE_FLAG="--profile $2"; shift 2 ;;
    -h|--help)
      sed -n '1,50p' "$0"; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 127; }
}

need_cmd aws
need_cmd kubectl
need_cmd terraform
need_cmd jq

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
TF_DIR="$REPO_ROOT/infra/terraform"

# Resolve cluster name from Terraform if not provided
if [[ -z "$CLUSTER_NAME" ]]; then
  if [[ -d "$TF_DIR" ]]; then
    pushd "$TF_DIR" >/dev/null
    if terraform output -raw cluster_name >/dev/null 2>&1; then
      CLUSTER_NAME=$(terraform output -raw cluster_name)
    else
      echo "Error: Could not read cluster_name from Terraform outputs. Provide -c <cluster_name>." >&2
      exit 1
    fi
    popd >/dev/null
  else
    echo "Error: Terraform directory not found and cluster not provided. Use -c <cluster_name>." >&2
    exit 1
  fi
fi

TS=$(date +%Y%m%d-%H%M%S)
OUT_DIR_DEFAULT="$REPO_ROOT/debug-artifacts/rollout-debug-${CLUSTER_NAME}-${TS}"
OUT_DIR=${OUT_DIR:-$OUT_DIR_DEFAULT}
mkdir -p "$OUT_DIR"

log() { echo "[$(date +%H:%M:%S)] $*"; }
run() { echo "+ $*"; eval "$*"; }

log "Cluster: $CLUSTER_NAME | Region: $REGION | Namespaces: $NAMESPACES | Window: ${LOOKBACK_MINUTES}m"

# Update kubeconfig
run "aws $PROFILE_FLAG eks update-kubeconfig --name '$CLUSTER_NAME' --region '$REGION'" || true

# Capture cluster-wide basics
run "kubectl version --short" | tee "$OUT_DIR/kubectl_version.txt" || true
run "kubectl get nodes -o wide" | tee "$OUT_DIR/nodes.txt" || true
run "kubectl -n kube-system get po" | tee "$OUT_DIR/kube-system_pods.txt" || true

# Try to fetch Terraform ECR outputs (best-effort)
API_REPO=""; FRONT_REPO=""
pushd "$TF_DIR" >/dev/null || true
if terraform output -raw ecr_api_repo_url >/dev/null 2>&1; then
  API_REPO=$(terraform output -raw ecr_api_repo_url)
fi
if terraform output -raw ecr_frontend_repo_url >/dev/null 2>&1; then
  FRONT_REPO=$(terraform output -raw ecr_frontend_repo_url)
fi
popd >/dev/null || true

echo "$API_REPO" > "$OUT_DIR/ecr_api_repo_url.txt" || true
echo "$FRONT_REPO" > "$OUT_DIR/ecr_frontend_repo_url.txt" || true

if [[ -n "$API_REPO" ]]; then
  run "aws $PROFILE_FLAG ecr describe-images --repository-name ${API_REPO##*/} --region $REGION --output json" \
    > "$OUT_DIR/ecr_api_describe_images.json" || true
fi
if [[ -n "$FRONT_REPO" ]]; then
  run "aws $PROFILE_FLAG ecr describe-images --repository-name ${FRONT_REPO##*/} --region $REGION --output json" \
    > "$OUT_DIR/ecr_frontend_describe_images.json" || true
fi

# Iterate namespaces and apps
IFS=',' read -ra NS_ARR <<< "$NAMESPACES"
APPS=(api frontend)
for NS in "${NS_ARR[@]}"; do
  NS_DIR="$OUT_DIR/ns-$NS"
  mkdir -p "$NS_DIR"

  log "Collecting objects in namespace: $NS"
  run "kubectl -n $NS get deploy,po,svc -o wide" | tee "$NS_DIR/get_objects.txt" || true
  # Capture full events in JSON and a tail view for quick reading
  kubectl -n "$NS" get events --sort-by=.lastTimestamp -o json > "$NS_DIR/events.json" 2>/dev/null || true
  kubectl -n "$NS" get events --sort-by=.lastTimestamp > "$NS_DIR/events.txt" 2>/dev/null || true
  tail -n 200 "$NS_DIR/events.txt" > "$NS_DIR/events_tail.txt" 2>/dev/null || true

  for APP in "${APPS[@]}"; do
    APP_DIR="$NS_DIR/$APP"
    mkdir -p "$APP_DIR"

    log "Describe deployment $APP in $NS (if exists)"
    kubectl -n "$NS" describe deploy "$APP" > "$APP_DIR/deploy_describe.txt" 2>/dev/null || true

    log "Rollout status for $APP in $NS (60s timeout)"
    kubectl -n "$NS" rollout status deploy/"$APP" --timeout=60s \
      > "$APP_DIR/rollout_status.txt" 2>&1 || true

    log "Describe pods for $APP in $NS"
    kubectl -n "$NS" describe pod -l app="$APP" > "$APP_DIR/pods_describe.txt" 2>/dev/null || true

    log "Logs for $APP in $NS (all containers, full logs)"
    # Collect logs per pod/container to avoid truncation
    kubectl -n "$NS" get po -l app="$APP" -o json | jq -r '.items[].metadata.name' | while read -r POD; do
      kubectl -n "$NS" get pod "$POD" -o json > "$APP_DIR/${POD}.json" 2>/dev/null || true
      # Standard containers
      for C in $(kubectl -n "$NS" get pod "$POD" -o json | jq -r '.spec.containers[].name'); do
        kubectl -n "$NS" logs "$POD" -c "$C" > "$APP_DIR/${POD}__${C}.log" 2>/dev/null || true
        # Previous logs if crashed
        kubectl -n "$NS" logs "$POD" -c "$C" --previous > "$APP_DIR/${POD}__${C}__previous.log" 2>/dev/null || true
      done
      # Init containers (if any)
      for IC in $(kubectl -n "$NS" get pod "$POD" -o json | jq -r '.spec.initContainers[]?.name'); do
        kubectl -n "$NS" logs "$POD" -c "$IC" > "$APP_DIR/${POD}__init__${IC}.log" 2>/dev/null || true
      done
    done

    # Capture pod list json for deeper analysis
    kubectl -n "$NS" get po -l app="$APP" -o json > "$APP_DIR/pods.json" 2>/dev/null || true
  done

done

# CloudWatch control plane logs
log "Collecting CloudWatch control plane logs"
START_MS=$(( ( $(date +%s) - LOOKBACK_MINUTES*60 ) * 1000 ))
END_MS=$(( $(date +%s) * 1000 ))

LOG_GROUP_PREFIX="/aws/eks/${CLUSTER_NAME}"
run "aws $PROFILE_FLAG logs describe-log-groups --log-group-name-prefix '$LOG_GROUP_PREFIX' --region $REGION --output json" \
  > "$OUT_DIR/cw_log_groups.json" || true

if jq -e '.logGroups | length > 0' "$OUT_DIR/cw_log_groups.json" >/dev/null 2>&1; then
  jq -r '.logGroups[].logGroupName' "$OUT_DIR/cw_log_groups.json" | while read -r LG; do
    SAFE_LG=$(echo "$LG" | tr '/' '_')
    log "Fetching CloudWatch events for $LG (last ${LOOKBACK_MINUTES}m)"
    aws $PROFILE_FLAG logs filter-log-events \
      --log-group-name "$LG" \
      --start-time "$START_MS" \
      --end-time   "$END_MS" \
      --region "$REGION" \
      --output json \
      > "$OUT_DIR/cw_${SAFE_LG}_events.json" || true
  done
else
  log "No CloudWatch log groups found for prefix $LOG_GROUP_PREFIX"
fi

# EKS node group IAM role inspection (best-effort)
log "Inspecting EKS nodegroups and IAM policies (best-effort)"
run "aws $PROFILE_FLAG eks list-nodegroups --cluster-name '$CLUSTER_NAME' --region '$REGION' --output json" \
  > "$OUT_DIR/eks_nodegroups.json" || true

if jq -e '.nodegroups | length > 0' "$OUT_DIR/eks_nodegroups.json" >/dev/null 2>&1; then
  for NG in $(jq -r '.nodegroups[]' "$OUT_DIR/eks_nodegroups.json"); do
    NG_SAFE=$(echo "$NG" | tr '/' '_')
    run "aws $PROFILE_FLAG eks describe-nodegroup --cluster-name '$CLUSTER_NAME' --nodegroup-name '$NG' --region '$REGION' --output json" \
      > "$OUT_DIR/eks_nodegroup_${NG_SAFE}.json" || true
    ROLE_ARN=$(jq -r '.nodegroup.nodeRole' "$OUT_DIR/eks_nodegroup_${NG_SAFE}.json" 2>/dev/null || echo "")
    if [[ "$ROLE_ARN" != "null" && -n "$ROLE_ARN" ]]; then
      ROLE_NAME=${ROLE_ARN##*/}
      run "aws $PROFILE_FLAG iam list-attached-role-policies --role-name '$ROLE_NAME' --output json" \
        > "$OUT_DIR/iam_${ROLE_NAME}_attached_policies.json" || true
    fi
  done
fi

log "Done. Collected artifacts in: $OUT_DIR"
