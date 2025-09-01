output "dev_role_arn" {
  value = aws_iam_role.dev_k8s_access.arn
}

output "prod_role_arn" {
  value = aws_iam_role.prod_k8s_access.arn
}

output "ci_deployer_role_arn" {
  value = aws_iam_role.ci_deployer.arn
}
