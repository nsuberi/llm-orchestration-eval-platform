output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_cluster_ca" {
  value     = module.eks.cluster_certificate_authority_data
  sensitive = true
}
