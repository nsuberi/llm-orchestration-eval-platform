terraform {
  required_version = ">= 1.5.0"
  backend "s3" {
    bucket = "cooking-up-ideas-tf-state"
    key    = "kubernetes-experiment-platform/terraform.tfstate"
    region = "us-east-1"
    encrypt = true
    dynamodb_table = "kubernetes-experiment-platform-tf-locks"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.24"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Table for Terraform state locking. Safe to keep here so the first apply creates the lock table.
resource "aws_dynamodb_table" "tf_locks" {
  name         = "kubernetes-experiment-platform-tf-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# VPC for EKS
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets  = [for i, az in slice(data.aws_availability_zones.available.names, 0, 2) : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnets = [for i, az in slice(data.aws_availability_zones.available.names, 0, 2) : cidrsubnet(var.vpc_cidr, 4, i + 8)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true
}

data "aws_availability_zones" "available" {}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# EKS Cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.8"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_irsa = true

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.large"]
      min_size       = 1
      max_size       = 4
      desired_size   = 2
    }
  }

  manage_aws_auth_configmap = true

  aws_auth_roles = concat(
    var.enable_dev ? [
      {
        rolearn  = aws_iam_role.dev_k8s_access.arn
        username = "dev-admin"
        groups   = ["dev-admin"]
      }
    ] : [],
    var.enable_prod ? [
      {
        rolearn  = aws_iam_role.prod_k8s_access.arn
        username = "prod-deployer"
        groups   = ["prod-deployer"]
      }
    ] : []
  )
}

# Minimal IAM roles
# Role for developers to administer dev namespace
resource "aws_iam_role" "dev_k8s_access" {
  name               = "${var.cluster_name}-dev-k8s-access"
  assume_role_policy = data.aws_iam_policy_document.trust_user_assume_role.json
}

resource "aws_iam_role_policy" "dev_eks_describe" {
  name = "${var.cluster_name}-dev-eks-describe"
  role = aws_iam_role.dev_k8s_access.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["eks:DescribeCluster"],
        Resource = "*"
      }
    ]
  })
}

# Role for production deploys with restricted k8s access in prod namespace
resource "aws_iam_role" "prod_k8s_access" {
  name               = "${var.cluster_name}-prod-k8s-access"
  assume_role_policy = data.aws_iam_policy_document.trust_user_assume_role.json
}

resource "aws_iam_role_policy" "prod_eks_describe" {
  name = "${var.cluster_name}-prod-eks-describe"
  role = aws_iam_role.prod_k8s_access.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["eks:DescribeCluster"],
        Resource = "*"
      }
    ]
  })
}

# CI deployer role (broad permissions for infra changes) - prototype only
resource "aws_iam_role" "ci_deployer" {
  name               = "${var.cluster_name}-ci-deployer"
  assume_role_policy = data.aws_iam_policy_document.trust_user_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ci_admin" {
  role       = aws_iam_role.ci_deployer.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AdministratorAccess"
}

# Trust policy allowing the specified IAM user to assume roles
data "aws_iam_policy_document" "trust_user_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [var.admin_user_arn]
    }
  }
}

# Access for Kubernetes provider
data "aws_eks_cluster" "this" {
  name = module.eks.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

# Namespaces
resource "kubernetes_namespace" "dev" {
  count = var.enable_dev ? 1 : 0
  metadata {
    name = "dev"
  }
}

resource "kubernetes_namespace" "prod" {
  count = var.enable_prod ? 1 : 0
  metadata {
    name = "prod"
  }
}

# Bind dev-admin group to admin role in dev namespace
resource "kubernetes_role_binding" "dev_admin" {
  count = var.enable_dev ? 1 : 0
  metadata {
    name      = "dev-admin-binding"
    namespace = kubernetes_namespace.dev[0].metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "admin"
  }
  subject {
    kind      = "Group"
    name      = "dev-admin"
    api_group = "rbac.authorization.k8s.io"
  }
}

# Bind prod-deployer group to admin in prod namespace (not cluster-wide)
resource "kubernetes_role_binding" "prod_deployer" {
  count = var.enable_prod ? 1 : 0
  metadata {
    name      = "prod-deployer-binding"
    namespace = kubernetes_namespace.prod[0].metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "admin"
  }
  subject {
    kind      = "Group"
    name      = "prod-deployer"
    api_group = "rbac.authorization.k8s.io"
  }
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "dev_role_arn" {
  value = aws_iam_role.dev_k8s_access.arn
}

output "prod_role_arn" {
  value = aws_iam_role.prod_k8s_access.arn
}

output "ci_deployer_role_arn" {
  value = aws_iam_role.ci_deployer.arn
}

# ECR repositories for api and frontend
resource "aws_ecr_repository" "api" {
  name = "${var.cluster_name}-api"
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_repository" "frontend" {
  name = "${var.cluster_name}-frontend"
  image_scanning_configuration { scan_on_push = true }
}

output "ecr_api_repo_url" {
  value = aws_ecr_repository.api.repository_url
}

output "ecr_frontend_repo_url" {
  value = aws_ecr_repository.frontend.repository_url
}

# Kubernetes Deployments/Services using images provided via variables
resource "kubernetes_deployment" "api_dev" {
  count = var.enable_dev ? 1 : 0
  metadata {
    name      = "api"
    namespace = kubernetes_namespace.dev[0].metadata[0].name
    labels = { app = "api" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "api" } }
    template {
      metadata { labels = { app = "api" } }
      spec {
        container {
          name  = "api"
          image = var.api_image
          port { container_port = 8000 }
          env { name = "ENV" value = "dev" }
          liveness_probe {
            http_get { path = "/healthz" port = 8000 }
            initial_delay_seconds = 5
            period_seconds = 10
          }
          readiness_probe {
            http_get { path = "/healthz" port = 8000 }
            initial_delay_seconds = 2
            period_seconds = 5
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "api_dev" {
  count = var.enable_dev ? 1 : 0
  metadata {
    name      = "api"
    namespace = kubernetes_namespace.dev[0].metadata[0].name
  }
  spec {
    selector = { app = "api" }
    port { port = 80 target_port = 8000 }
    type = "ClusterIP"
  }
}

resource "kubernetes_deployment" "frontend_dev" {
  count = var.enable_dev ? 1 : 0
  metadata {
    name      = "frontend"
    namespace = kubernetes_namespace.dev[0].metadata[0].name
    labels = { app = "frontend" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "frontend" } }
    template {
      metadata { labels = { app = "frontend" } }
      spec {
        container {
          name  = "frontend"
          image = var.frontend_image
          port { container_port = 3000 }
          env { name = "NEXT_PUBLIC_API_BASE" value = "http://api.dev.svc.cluster.local" }
        }
      }
    }
  }
}

resource "kubernetes_service" "frontend_dev" {
  count = var.enable_dev ? 1 : 0
  metadata {
    name      = "frontend"
    namespace = kubernetes_namespace.dev[0].metadata[0].name
  }
  spec {
    selector = { app = "frontend" }
    port { port = 80 target_port = 3000 }
    type = "ClusterIP"
  }
}

resource "kubernetes_deployment" "api_prod" {
  count = var.enable_prod ? 1 : 0
  metadata {
    name      = "api"
    namespace = kubernetes_namespace.prod[0].metadata[0].name
    labels = { app = "api" }
  }
  spec {
    replicas = 2
    selector { match_labels = { app = "api" } }
    template {
      metadata { labels = { app = "api" } }
      spec {
        container {
          name  = "api"
          image = var.api_image
          port { container_port = 8000 }
          env { name = "ENV" value = "prod" }
          liveness_probe { http_get { path = "/healthz" port = 8000 } initial_delay_seconds = 5 period_seconds = 10 }
          readiness_probe { http_get { path = "/healthz" port = 8000 } initial_delay_seconds = 2 period_seconds = 5 }
        }
      }
    }
  }
}

resource "kubernetes_service" "api_prod" {
  count = var.enable_prod ? 1 : 0
  metadata {
    name      = "api"
    namespace = kubernetes_namespace.prod[0].metadata[0].name
  }
  spec {
    selector = { app = "api" }
    port { port = 80 target_port = 8000 }
    type = "ClusterIP"
  }
}

resource "kubernetes_deployment" "frontend_prod" {
  count = var.enable_prod ? 1 : 0
  metadata {
    name      = "frontend"
    namespace = kubernetes_namespace.prod[0].metadata[0].name
    labels = { app = "frontend" }
  }
  spec {
    replicas = 2
    selector { match_labels = { app = "frontend" } }
    template {
      metadata { labels = { app = "frontend" } }
      spec {
        container {
          name  = "frontend"
          image = var.frontend_image
          port { container_port = 3000 }
          env { name = "NEXT_PUBLIC_API_BASE" value = "http://api.prod.svc.cluster.local" }
        }
      }
    }
  }
}

resource "kubernetes_service" "frontend_prod" {
  count = var.enable_prod ? 1 : 0
  metadata {
    name      = "frontend"
    namespace = kubernetes_namespace.prod[0].metadata[0].name
  }
  spec {
    selector = { app = "frontend" }
    port { port = 80 target_port = 3000 }
    type = "ClusterIP"
  }
}
