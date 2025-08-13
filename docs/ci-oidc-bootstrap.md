# GitHub Actions OIDC bootstrap for Terraform

This guide bootstraps AWS IAM OIDC auth for this repo so GitHub Actions can assume an AWS role without long‑lived keys. The bootstrap role is powerful so Terraform can create the rest of your least‑privilege roles and infra. After Terraform is in place, you can reduce this role's permissions.

## Prerequisites
- AWS CLI v2 installed and authenticated (`aws configure` or SSO). The caller must have IAM permissions to create an OIDC provider and roles.
- GitHub CLI (`gh`) authenticated for this repo (optional but recommended to automate adding the repo secret).
- Repo has a workflow that uses `aws-actions/configure-aws-credentials@v4` with `role-to-assume` (this repo's `deploy.yml` supports keys and OIDC).

## What this does
1. Ensures the AWS IAM OIDC provider for `token.actions.githubusercontent.com` exists in your account.
2. Creates a bootstrap role (default: `github-actions-terraform-bootstrap`) trusted by this repo on `main` and tags `v*`.
3. Attaches `AdministratorAccess` to the role so Terraform can provision all required resources. Replace with least‑privilege later.
4. Stores the role ARN in the repo secret `AWS_CI_DEPLOY_ROLE_ARN`.

## Quick start (one‑time)
You can run the following commands manually, or run the bootstrap script below.

Set variables:
```bash
# Required: your GitHub repo in OWNER/REPO form
OWNER_REPO="<owner>/<repo>"
# Optional: role name and region
ROLE_NAME=${ROLE_NAME:-github-actions-terraform-bootstrap}
AWS_REGION=${AWS_REGION:-us-east-1}
```

Discover your account ID:
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "ACCOUNT_ID=$ACCOUNT_ID"
```

Create OIDC provider (idempotent):
```bash
# Thumbprints recommended by GitHub (allow list supports multiple entries)
TP1=6938fd4d98bab03faadb97b34396831e3780aea1
TP2=a031c46782e6e6c662c2c87c76da9aa62ccabd8e
OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" >/dev/null 2>&1; then
  echo "OIDC provider already exists: $OIDC_ARN"
else
  aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list $TP1 $TP2 \
    >/dev/null
  echo "Created OIDC provider: $OIDC_ARN"
fi
```

Create trust policy restricted to this repo's refs:
```bash
cat > trust-policy.json <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com" },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": [
            "repo:OWNER_REPO:ref:refs/heads/main",
            "repo:OWNER_REPO:ref:refs/tags/v*"
          ]
        }
      }
    }
  ]
}
JSON

# Replace placeholders
sed -i.bak "s/ACCOUNT_ID/${ACCOUNT_ID}/g; s|OWNER_REPO|${OWNER_REPO}|g" trust-policy.json
```

Create role and attach AdministratorAccess (idempotent):
```bash
if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  echo "Role already exists: $ROLE_NAME"
else
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document file://trust-policy.json \
    >/dev/null
  echo "Created role: $ROLE_NAME"
fi

aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
  >/dev/null || true

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
echo "ROLE_ARN=$ROLE_ARN"
```

Add the role ARN as a repo secret (requires GitHub CLI):
```bash
# Optional: use gh to set the secret automatically
if command -v gh >/dev/null; then
  gh secret set AWS_CI_DEPLOY_ROLE_ARN -b "$ROLE_ARN"
  echo "Set GitHub secret AWS_CI_DEPLOY_ROLE_ARN"
else
  echo "Please add repo secret AWS_CI_DEPLOY_ROLE_ARN with value: $ROLE_ARN"
fi
```

## Update workflows
This repo's `deploy.yml` already supports both static keys and an optional `role-to-assume`. After the secret is set:
- Prefer OIDC: remove `aws-access-key-id` and `aws-secret-access-key` from the AWS credentials step so no static keys are used.
- Ensure the job has `permissions: id-token: write` (already present).

Example OIDC‑only snippet:
```yaml
- name: Configure AWS credentials (OIDC)
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ secrets.AWS_CI_DEPLOY_ROLE_ARN }}
    aws-region: ${{ vars.AWS_REGION || 'us-east-1' }}
```

## Test
- Trigger the workflow on `main` or tag `vX.Y.Z`.
- Verify the AWS credentials step succeeds and Terraform can run.

## Hardening and cleanup
- Replace `AdministratorAccess` with a least‑privilege policy once Terraform can provision dedicated roles.
- Remove static AWS key secrets from the repo after confirming OIDC works.
- Expand the trust policy `sub` patterns only as needed (e.g., add other branches or environments).
