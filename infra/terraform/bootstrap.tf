variable "bootstrap_role_name" {
  description = "Name of the bootstrap role to attach base permissions to"
  type        = string
  default     = "github-actions-terraform-bootstrap"
}

# Root-level data sources used by locals and ARNs below
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id     = data.aws_caller_identity.current.account_id
  partition      = data.aws_partition.current.partition
  region         = var.aws_region
  cluster_prefix = var.cluster_name
}

data "aws_iam_role" "bootstrap" {
  name = var.bootstrap_role_name
}

// Removed: direct admin user linkage; use bootstrap role assumption instead

# Base policy allowing Terraform to provision current infra (EKS, VPC/networking, ECR)
# and manage IAM roles/policies needed for this repository's deployments.
resource "aws_iam_policy" "bootstrap_base" {
  name        = "${var.cluster_name}-bootstrap-base"
  description = "Base privileges for Terraform bootstrap to manage EKS, networking, ECR, and IAM roles/policies for ${var.cluster_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # IAM role/policy management limited to our cluster prefix
      {
        Sid    = "IamManageClusterPrefixedRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:GetRole",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies"
        ]
        Resource = [
          "arn:${local.partition}:iam::${local.account_id}:role/${local.cluster_prefix}*"
        ]
      },
      {
        Sid    = "IamCreateManageClusterPolicies"
        Effect = "Allow"
        Action = [
          "iam:CreatePolicy",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:DeletePolicy",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions"
        ]
        Resource = [
          "arn:${local.partition}:iam::${local.account_id}:policy/${local.cluster_prefix}*"
        ]
      },
      {
        Sid    = "IamPassClusterRolesToServices"
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = [
          "arn:${local.partition}:iam::${local.account_id}:role/${local.cluster_prefix}*"
        ]
        Condition = {
          StringEquals = {
            "iam:PassedToService" = [
              "eks.amazonaws.com",
              "ec2.amazonaws.com",
              "autoscaling.amazonaws.com"
            ]
          }
        }
      },

      # EKS cluster and nodegroup lifecycle
      {
        Sid      = "EksManage"
        Effect   = "Allow"
        Action   = ["eks:*"]
        Resource = "*"
      },

      # EC2 networking for VPC, subnets, routes, IGW, NAT, SGs, EIPs
      {
        Sid    = "Ec2Networking"
        Effect = "Allow"
        Action = [
          "ec2:Create*",
          "ec2:Delete*",
          "ec2:Modify*",
          "ec2:Associate*",
          "ec2:Disassociate*",
          "ec2:Attach*",
          "ec2:Detach*",
          "ec2:Describe*",
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = "*"
      },

      # ECR repositories for images used by this repo
      {
        Sid    = "EcrManageClusterRepos"
        Effect = "Allow"
        Action = [
          "ecr:CreateRepository",
          "ecr:DeleteRepository",
          "ecr:Describe*",
          "ecr:Get*",
          "ecr:List*",
          "ecr:PutLifecyclePolicy",
          "ecr:SetRepositoryPolicy",
          "ecr:TagResource",
          "ecr:UntagResource"
        ]
        Resource = [
          "arn:${local.partition}:ecr:${local.region}:${local.account_id}:repository/${local.cluster_prefix}-*"
        ]
      },
      # ECR push/pull for our repositories and auth token
      {
        Sid      = "EcrGetAuthToken"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "EcrPushPullClusterRepos"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = [
          "arn:${local.partition}:ecr:${local.region}:${local.account_id}:repository/${local.cluster_prefix}-*"
        ]
      },

      # CloudWatch Logs for EKS control plane logging
      {
        Sid    = "LogsManage"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:PutRetentionPolicy",
          "logs:DescribeLogGroups",
          "logs:TagLogGroup"
        ]
        Resource = "*"
      },

      # Autoscaling read/manage for nodegroups (defensive)
      {
        Sid      = "AutoscalingManage"
        Effect   = "Allow"
        Action   = ["autoscaling:*"]
        Resource = "*"
      },

      # Manage IAM OIDC providers (for IRSA and GitHub OIDC where needed)
      {
        Sid    = "IamManageOidcProviders"
        Effect = "Allow"
        Action = [
          "iam:CreateOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider",
          "iam:UpdateOpenIDConnectProviderThumbprint",
          "iam:GetOpenIDConnectProvider",
          "iam:ListOpenIDConnectProviders"
        ]
        Resource = "*"
      },

      # Allow creating service-linked roles required by AWS services we use
      {
        Sid      = "IamCreateServiceLinkedRole"
        Effect   = "Allow"
        Action   = ["iam:CreateServiceLinkedRole"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = [
              "eks.amazonaws.com",
              "eks-nodegroup.amazonaws.com",
              "eks-fargate.amazonaws.com",
              "autoscaling.amazonaws.com",
              "elasticloadbalancing.amazonaws.com"
            ]
          }
        }
      },

      # S3 access for Terraform remote state backend key
      {
        Sid    = "S3StateBucketList"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = "arn:${local.partition}:s3:::cooking-up-ideas-tf-state"
        Condition = {
          StringLike = {
            "s3:prefix" = [
              "kubernetes-experiment-platform/*",
              "kubernetes-experiment-platform"
            ]
          }
        }
      },
      {
        Sid    = "S3StateObjectCRUD"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:${local.partition}:s3:::cooking-up-ideas-tf-state/kubernetes-experiment-platform/*"
      },
      {
        Sid    = "S3StateBucketConfig"
        Effect = "Allow"
        Action = [
          "s3:PutBucketVersioning",
          "s3:GetBucketVersioning",
          "s3:PutEncryptionConfiguration",
          "s3:GetEncryptionConfiguration",
          "s3:PutBucketPublicAccessBlock",
          "s3:GetBucketPublicAccessBlock"
        ]
        Resource = "arn:${local.partition}:s3:::cooking-up-ideas-tf-state"
      },

      # No DynamoDB needed; S3 backend uses object lockfile

      # Basic STS to introspect account
      {
        Sid      = "StsRead"
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
        Resource = "*"
      }
    ]
  })
}

# Attach the base policy to the bootstrap role (OIDC-assumed in CI)
resource "aws_iam_role_policy_attachment" "bootstrap_role_base" {
  role       = data.aws_iam_role.bootstrap.name
  policy_arn = aws_iam_policy.bootstrap_base.arn
}

# Admin users should assume the bootstrap role rather than having this policy directly
