variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_version" {
  description = "EKS cluster version"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the EKS cluster"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the EKS cluster"
  type        = list(string)
}

variable "enable_dev" {
  description = "Whether to configure dev access entry"
  type        = bool
  default     = true
}

variable "enable_prod" {
  description = "Whether to configure prod access entry"
  type        = bool
  default     = true
}

variable "dev_access_role_arn" {
  description = "IAM role ARN for dev admin access entry"
  type        = string
  default     = null
}

variable "prod_access_role_arn" {
  description = "IAM role ARN for prod deployer access entry"
  type        = string
  default     = null
}

# EKS API endpoint access configuration
variable "cluster_endpoint_private_access" {
  description = "Enable the EKS private API server endpoint"
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access" {
  description = "Enable the EKS public API server endpoint"
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to access the public API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Grant the Terraform caller admin permissions in the cluster via access entries
variable "enable_cluster_creator_admin_permissions" {
  description = "Whether to add the Terraform caller as an EKS cluster admin via access entry"
  type        = bool
  default     = true
}
