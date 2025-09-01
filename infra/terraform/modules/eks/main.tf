module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.8"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  enable_irsa = true

  # API endpoint accessibility so kubernetes provider can reach the cluster
  cluster_endpoint_private_access       = var.cluster_endpoint_private_access
  cluster_endpoint_public_access        = var.cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs  = var.cluster_endpoint_public_access_cidrs

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.large"]
      min_size       = 1
      max_size       = 4
      desired_size   = 2
    }
  }

  # Ensure keys are statically known at plan time so downstream for_each does not depend on unknowns
  access_entries = merge(
    var.enable_dev ? {
      dev_admin = {
        principal_arn     = var.dev_access_role_arn
        kubernetes_groups = ["dev-admin"]
        username          = "dev-admin"
      }
    } : {},
    var.enable_prod ? {
      prod_deployer = {
        principal_arn     = var.prod_access_role_arn
        kubernetes_groups = ["prod-deployer"]
        username          = "prod-deployer"
      }
    } : {}
  )

  # Ensure the Terraform caller gains cluster-admin via access entries
  enable_cluster_creator_admin_permissions = true
}
