## EKS one-cluster, two-namespaces deployment

### Usage
```bash
cd infra/terraform
terraform init
terraform apply -auto-approve \
  -var admin_user_arn=arn:aws:iam::671388079324:user/nsuberi \
  -var aws_region=us-east-1
```

This will provision:
- VPC and subnets
- EKS cluster with IRSA enabled
- Namespaces: `dev` and `prod`
- IAM roles:
  - dev namespace access: `${cluster_name}-dev-k8s-access`
  - prod namespace deployer: `${cluster_name}-prod-k8s-access`
  - CI deployer (AdministratorAccess for prototype): `${cluster_name}-ci-deployer`

The roles trust the provided IAM user ARN by default. Replace `admin_user_arn` as needed.

### GitHub Actions
Set secret `AWS_CI_DEPLOY_ROLE_ARN` to the CI deployer role ARN output by Terraform.

Dev deploy runs on pushes to `main` (dev namespace only). Prod deploy runs on tags `v*` with a manual approval gate.
