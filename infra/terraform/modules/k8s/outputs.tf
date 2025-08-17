output "frontend_dev_lb_hostname" {
  value       = try(kubernetes_ingress_v1.frontend_dev[0].status[0].load_balancer[0].ingress[0].hostname, "")
  description = "External LB hostname for dev frontend"
}

output "frontend_prod_lb_hostname" {
  value       = try(kubernetes_ingress_v1.frontend_prod[0].status[0].load_balancer[0].ingress[0].hostname, "")
  description = "External LB hostname for prod frontend"
}
