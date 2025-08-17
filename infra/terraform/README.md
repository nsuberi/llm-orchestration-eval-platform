## EKS one-cluster, two-namespaces deployment

### Usage
```bash
cd infra/terraform
# 1) Assume the bootstrap role using your admin IAM user credentials
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ROLE_NAME=${ROLE_NAME:-github-actions-terraform-bootstrap}
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

# Obtain short-lived credentials
CREDS=$(aws sts assume-role --role-arn "$ROLE_ARN" --role-session-name tf-admin --duration-seconds 3600)
export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | jq -r .Credentials.AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | jq -r .Credentials.SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo "$CREDS" | jq -r .Credentials.SessionToken)

# 2) Run Terraform with the assumed role
terraform init
terraform apply -auto-approve -var aws_region=us-east-1 \
  -var enable_cloudflare=true \
  -var cloudflare_zone_id=<CLOUDFLARE_ZONE_ID> \
  -var cloudflare_api_token=$CLOUDFLARE_API_TOKEN
```

This will provision:
- VPC and subnets
- EKS cluster with IRSA enabled
- Namespaces: `dev` and `prod`
- IAM roles:
  - dev namespace access: `${cluster_name}-dev-k8s-access`
  - prod namespace deployer: `${cluster_name}-prod-k8s-access`
  - CI deployer (AdministratorAccess for prototype): `${cluster_name}-ci-deployer`

Terraform is expected to run under the assumed bootstrap role.

### GitHub Actions
Set secret `AWS_CI_DEPLOY_ROLE_ARN` to the CI deployer role ARN output by Terraform.

Dev deploy runs on pushes to `main` (dev namespace only). Prod deploy runs on tags `v*` with a manual approval gate.
