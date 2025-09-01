variable "cluster_name" {
  description = "Cluster name used to prefix ECR repos"
  type        = string
}

resource "aws_ecr_repository" "api" {
  name = "${var.cluster_name}-api"
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_repository" "frontend" {
  name = "${var.cluster_name}-frontend"
  image_scanning_configuration { scan_on_push = true }
}

output "api_repo_url" {
  value = aws_ecr_repository.api.repository_url
}

output "frontend_repo_url" {
  value = aws_ecr_repository.frontend.repository_url
}
