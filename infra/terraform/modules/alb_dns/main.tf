variable "hosted_zone_id" { type = string }
variable "subdomain" { type = string }
variable "environment" { type = string }
variable "lb_hostname" { type = string }

data "aws_route53_zone" "main" {
  zone_id = var.hosted_zone_id
}

resource "aws_acm_certificate" "cert" {
  domain_name       = "${var.subdomain}.cookinupideas.com"
  validation_method = "DNS"
  lifecycle { create_before_destroy = true }
  tags = { Name = "${var.subdomain}-cookinupideas-com", Environment = var.environment }
}

resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  allow_overwrite = true
  name    = each.value.name
  records = [each.value.record]
  ttl     = 60
  type    = each.value.type
  zone_id = data.aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}

resource "aws_route53_record" "a_record" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "${var.subdomain}.cookinupideas.com"
  type    = "A"
  alias {
    name                   = var.lb_hostname
    zone_id                = "Z35SXDOTRQ7X7K" # NLB hosted zone ID (us-east-1). Consider data lookup for portability
    evaluate_target_health = false
  }
}
