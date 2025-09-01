data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

# Trust policy allowing principals in this AWS account to assume roles
data "aws_iam_policy_document" "trust_account_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_iam_role" "dev_k8s_access" {
  name               = "${var.cluster_name}-dev-k8s-access"
  assume_role_policy = data.aws_iam_policy_document.trust_account_assume_role.json
}

resource "aws_iam_role_policy" "dev_eks_describe" {
  name = "${var.cluster_name}-dev-eks-describe"
  role = aws_iam_role.dev_k8s_access.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["eks:DescribeCluster"],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "prod_k8s_access" {
  name               = "${var.cluster_name}-prod-k8s-access"
  assume_role_policy = data.aws_iam_policy_document.trust_account_assume_role.json
}

resource "aws_iam_role_policy" "prod_eks_describe" {
  name = "${var.cluster_name}-prod-eks-describe"
  role = aws_iam_role.prod_k8s_access.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["eks:DescribeCluster"],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "ci_deployer" {
  name               = "${var.cluster_name}-ci-deployer"
  assume_role_policy = data.aws_iam_policy_document.trust_account_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ci_admin" {
  role       = aws_iam_role.ci_deployer.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AdministratorAccess"
}
