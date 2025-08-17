# Namespaces
resource "kubernetes_namespace" "dev" {
  count = var.enable_dev ? 1 : 0
  metadata { name = "dev" }
}

resource "kubernetes_namespace" "prod" {
  count = var.enable_prod ? 1 : 0
  metadata { name = "prod" }
}

# Bind dev-admin group to admin role in dev namespace
resource "kubernetes_role_binding" "dev_admin" {
  count = var.enable_dev ? 1 : 0
  metadata {
    name      = "dev-admin-binding"
    namespace = kubernetes_namespace.dev[0].metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "admin"
  }
  subject {
    kind      = "Group"
    name      = "dev-admin"
    api_group = "rbac.authorization.k8s.io"
  }
}

# Bind prod-deployer group to admin in prod namespace (not cluster-wide)
resource "kubernetes_role_binding" "prod_deployer" {
  count = var.enable_prod ? 1 : 0
  metadata {
    name      = "prod-deployer-binding"
    namespace = kubernetes_namespace.prod[0].metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "admin"
  }
  subject {
    kind      = "Group"
    name      = "prod-deployer"
    api_group = "rbac.authorization.k8s.io"
  }
}

# Kubernetes Deployments/Services using images provided via variables
resource "kubernetes_deployment" "api_dev" {
  count = var.enable_dev && length(trimspace(var.api_image)) > 0 ? 1 : 0
  metadata {
    name      = "api"
    namespace = kubernetes_namespace.dev[0].metadata[0].name
    labels    = { app = "api" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "api" } }
    template {
      metadata { labels = { app = "api" } }
      spec {
        container {
          name  = "api"
          image = var.api_image
          port { container_port = 8000 }
          env {
            name  = "ENV"
            value = "dev"
          }
          liveness_probe {
            http_get {
              path = "/healthz"
              port = 8000
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
          readiness_probe {
            http_get {
              path = "/healthz"
              port = 8000
            }
            initial_delay_seconds = 2
            period_seconds        = 5
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "api_dev" {
  count = var.enable_dev && length(trimspace(var.api_image)) > 0 ? 1 : 0
  metadata {
    name      = "api"
    namespace = kubernetes_namespace.dev[0].metadata[0].name
  }
  spec {
    selector = { app = "api" }
    port {
      port        = 80
      target_port = 8000
    }
    type = "ClusterIP"
  }
}

resource "kubernetes_deployment" "frontend_dev" {
  count = var.enable_dev && length(trimspace(var.frontend_image)) > 0 ? 1 : 0
  metadata {
    name      = "frontend"
    namespace = kubernetes_namespace.dev[0].metadata[0].name
    labels    = { app = "frontend" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "frontend" } }
    template {
      metadata { labels = { app = "frontend" } }
      spec {
        container {
          name  = "frontend"
          image = var.frontend_image
          port { container_port = 3000 }
          env {
            name  = "NEXT_PUBLIC_API_BASE"
            value = "http://api.dev.svc.cluster.local"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "frontend_dev" {
  count = var.enable_dev && length(trimspace(var.frontend_image)) > 0 ? 1 : 0
  metadata {
    name      = "frontend"
    namespace = kubernetes_namespace.dev[0].metadata[0].name
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"   = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
    }
  }
  spec {
    selector = { app = "frontend" }
    port {
      port        = 80
      target_port = 3000
    }
    type = "LoadBalancer"
  }
}

resource "kubernetes_deployment" "api_prod" {
  count = var.enable_prod && length(trimspace(var.api_image)) > 0 ? 1 : 0
  metadata {
    name      = "api"
    namespace = kubernetes_namespace.prod[0].metadata[0].name
    labels    = { app = "api" }
  }
  spec {
    replicas = 2
    selector { match_labels = { app = "api" } }
    template {
      metadata { labels = { app = "api" } }
      spec {
        container {
          name  = "api"
          image = var.api_image
          port { container_port = 8000 }
          env {
            name  = "ENV"
            value = "prod"
          }
          liveness_probe {
            http_get {
              path = "/healthz"
              port = 8000
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
          readiness_probe {
            http_get {
              path = "/healthz"
              port = 8000
            }
            initial_delay_seconds = 2
            period_seconds        = 5
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "api_prod" {
  count = var.enable_prod && length(trimspace(var.api_image)) > 0 ? 1 : 0
  metadata {
    name      = "api"
    namespace = kubernetes_namespace.prod[0].metadata[0].name
  }
  spec {
    selector = { app = "api" }
    port {
      port        = 80
      target_port = 8000
    }
    type = "ClusterIP"
  }
}

resource "kubernetes_deployment" "frontend_prod" {
  count = var.enable_prod && length(trimspace(var.frontend_image)) > 0 ? 1 : 0
  metadata {
    name      = "frontend"
    namespace = kubernetes_namespace.prod[0].metadata[0].name
    labels    = { app = "frontend" }
  }
  spec {
    replicas = 2
    selector { match_labels = { app = "frontend" } }
    template {
      metadata { labels = { app = "frontend" } }
      spec {
        container {
          name  = "frontend"
          image = var.frontend_image
          port { container_port = 3000 }
          env {
            name  = "NEXT_PUBLIC_API_BASE"
            value = "http://api.prod.svc.cluster.local"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "frontend_prod" {
  count = var.enable_prod && length(trimspace(var.frontend_image)) > 0 ? 1 : 0
  metadata {
    name      = "frontend"
    namespace = kubernetes_namespace.prod[0].metadata[0].name
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"   = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
    }
  }
  spec {
    selector = { app = "frontend" }
    port {
      port        = 80
      target_port = 3000
    }
    type = "LoadBalancer"
  }
}
