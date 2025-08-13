variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "clintestbench"
}

variable "cluster_version" {
  description = "EKS cluster version"
  type        = string
  default     = "1.29"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "admin_user_arn" {
  description = "IAM user ARN to trust for role assumption"
  type        = string
  default     = "arn:aws:iam::671388079324:user/nsuberi"
}

variable "enable_dev" {
  description = "Whether to create dev namespace and bindings"
  type        = bool
  default     = true
}

variable "enable_prod" {
  description = "Whether to create prod namespace and bindings"
  type        = bool
  default     = true
}

variable "api_image" {
  description = "Container image for API"
  type        = string
  default     = ""
}

variable "frontend_image" {
  description = "Container image for frontend"
  type        = string
  default     = ""
}
