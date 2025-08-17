variable "zone_id" { type = string }
variable "subdomain" { type = string }
variable "target_hostname" { type = string }
variable "proxied" { type = bool }

# Create a CNAME evals -> ELB hostname, proxied by Cloudflare
resource "cloudflare_record" "frontend" {
  zone_id = var.zone_id
  name    = var.subdomain
  type    = "CNAME"
  value   = var.target_hostname
  proxied = var.proxied
  ttl     = 300
}
