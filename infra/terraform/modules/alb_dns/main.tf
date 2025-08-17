variable "hosted_zone_id" { type = string }
variable "subdomain" { type = string }
variable "environment" { type = string }
variable "lb_hostname" { type = string }

data "aws_route53_zone" "main" {
  zone_id = var.hosted_zone_id
}

locals {
  enabled = length(trimspace(var.lb_hostname)) > 0
}

// ACM cert is provisioned separately in k8s module and referenced by the Ingress

resource "aws_route53_record" "a_record" {
  count   = local.enabled ? 1 : 0
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "${var.subdomain}.cookinupideas.com"
  type    = "A"
  alias {
    name                   = var.lb_hostname
    zone_id                = "Z35SXDOTRQ7X7K" # ALB hosted zone ID (us-east-1)
    evaluate_target_health = false
  }
}
