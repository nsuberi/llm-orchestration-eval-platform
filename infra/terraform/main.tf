terraform {
  required_version = ">= 1.5.0"
  backend "s3" {
    bucket  = "cooking-up-ideas-tf-state"
    key     = "kubernetes-experiment-platform/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
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
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# VPC for EKS
module "vpc" {
  source       = "./modules/vpc"
  cluster_name = var.cluster_name
  vpc_cidr     = var.vpc_cidr
}

// removed unused root data sources; modules manage their own

# EKS Cluster
module "eks" {
  source               = "./modules/eks"
  cluster_name         = var.cluster_name
  cluster_version      = var.cluster_version
  vpc_id               = module.vpc.vpc_id
  subnet_ids           = module.vpc.private_subnets
  enable_dev           = var.enable_dev
  enable_prod          = var.enable_prod
  dev_access_role_arn  = module.iam.dev_role_arn
  prod_access_role_arn = module.iam.prod_role_arn
  # Ensure the EKS public endpoint is available so local Terraform can reach it
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]
}

module "iam" {
  source       = "./modules/iam"
  cluster_name = var.cluster_name
}

## Kubernetes provider lives in root, consuming EKS module outputs
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

module "k8s" {
  source         = "./modules/k8s"
  depends_on     = [module.eks]
  enable_dev     = var.enable_dev
  enable_prod    = var.enable_prod
  # Pin deployments to the ECR repos created by this stack
  api_image      = "${module.ecr.api_repo_url}:latest"
  frontend_image = "${module.ecr.frontend_repo_url}:latest"
}

locals {
  frontend_lb_hostname = module.k8s.frontend_prod_lb_hostname != "" ? module.k8s.frontend_prod_lb_hostname : module.k8s.frontend_dev_lb_hostname
}
output "cluster_name" {
  value = module.eks.cluster_name
}

output "dev_role_arn" {
  value = module.iam.dev_role_arn
}

output "prod_role_arn" {
  value = module.iam.prod_role_arn
}

output "ci_deployer_role_arn" {
  value = module.iam.ci_deployer_role_arn
}

module "state_bucket_hardening" {
  source      = "./modules/state"
  bucket_name = "cooking-up-ideas-tf-state"
}

module "ecr" {
  source       = "./modules/ecr"
  cluster_name = var.cluster_name
}

output "ecr_api_repo_url" {
  value = module.ecr.api_repo_url
}

output "ecr_frontend_repo_url" {
  value = module.ecr.frontend_repo_url
}

output "frontend_dev_lb_hostname" {
  value = module.k8s.frontend_dev_lb_hostname
}

output "frontend_prod_lb_hostname" {
  value = module.k8s.frontend_prod_lb_hostname
}

module "dns_frontend" {
  count          = (!var.enable_cloudflare && local.frontend_lb_hostname != "") ? 1 : 0
  source         = "./modules/alb_dns"
  hosted_zone_id = var.route53_zone_id
  subdomain      = "evals"
  environment    = "${var.enable_prod ? "prod" : "dev"}"
  lb_hostname    = local.frontend_lb_hostname
}

module "cloudflare_frontend" {
  count            = (var.enable_cloudflare && local.frontend_lb_hostname != "") ? 1 : 0
  source           = "./modules/cloudflare_dns"
  zone_id          = var.cloudflare_zone_id
  subdomain        = "evals"
  target_hostname  = local.frontend_lb_hostname
  proxied          = true
}

// Kubernetes workloads moved to modules/k8s
