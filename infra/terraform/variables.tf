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

variable "route53_zone_id" {
  description = "Hosted Zone ID for cookinupideas.com"
  type        = string
  default     = "Z0990573XMA6PHFKL82S"
}

variable "environment" {
  description = "Environment label for tagging (dev/prod)"
  type        = string
  default     = "dev"
}
