variable "cluster_name" {
  description = "EKS cluster name used for tagging/naming"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
}
