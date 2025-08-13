output "eks_cluster_endpoint" {
  value = data.aws_eks_cluster.this.endpoint
}

output "eks_cluster_ca" {
  value     = data.aws_eks_cluster.this.certificate_authority[0].data
  sensitive = true
}
