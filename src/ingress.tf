################################################################################
# NGINX Ingress Controller + Paperclip Ingress
# Single entry point (OCI LoadBalancer) for all HTTP/HTTPS traffic.
# Paperclip PAPERCLIP_PUBLIC_URL is auto-set from the Ingress IP via data source.
################################################################################

################################################################################
# NGINX Ingress Controller Helm Release
################################################################################

resource "helm_release" "nginx_ingress" {
  count = (var.enable_paperclip && var.paperclip_exposure == "public") || (var.enable_opencode && var.opencode_exposure == "public") ? 1 : 0

  depends_on = [module.oke, time_sleep.after_cluster]

  name       = "nginx-ingress"
  namespace  = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = var.nginx_ingress_chart_version

  create_namespace = true

  values = [
    <<-EOF
    controller:
      service:
        annotations:
          # Always Free flexible LB (10 Mbps min/max) — the fixed "10Mbps" shape is billable
          service.beta.kubernetes.io/oci-load-balancer-shape: "flexible"
          service.beta.kubernetes.io/oci-load-balancer-shape-flex-min: "10"
          service.beta.kubernetes.io/oci-load-balancer-shape-flex-max: "10"
        type: LoadBalancer
      publishService:
        enabled: true
    EOF
  ]
}

################################################################################
# Wait for LoadBalancer IP assignment
################################################################################

resource "time_sleep" "wait_for_ingress_lb" {
  count = (var.enable_paperclip && var.paperclip_exposure == "public") || (var.enable_opencode && var.opencode_exposure == "public") ? 1 : 0

  depends_on      = [helm_release.nginx_ingress]
  create_duration = "120s"
}

################################################################################
# Paperclip Ingress
################################################################################

resource "kubectl_manifest" "paperclip_ingress" {
  count = var.enable_paperclip && var.paperclip_exposure == "public" ? 1 : 0

  depends_on = [
    helm_release.nginx_ingress,
    time_sleep.wait_for_ingress_lb,
    kubectl_manifest.paperclip_service,
  ]

  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "paperclip"
      namespace = "paperclip"
      annotations = merge(
        {
          "kubernetes.io/ingress.class" = "nginx"
        },
        var.paperclip_custom_domain != "" ? {
          "cert-manager.io/cluster-issuer"           = "letsencrypt-prod"
          "nginx.ingress.kubernetes.io/ssl-redirect" = "true"
        } : {}
      )
    }
    spec = {
      rules = [
        {
          host = var.paperclip_custom_domain != "" ? var.paperclip_custom_domain : ""
          http = {
            paths = [
              {
                path     = "/"
                pathType = "Prefix"
                backend = {
                  service = {
                    name = "paperclip"
                    port = {
                      number = 80
                    }
                  }
                }
              }
            ]
          }
        }
      ]
      tls = var.paperclip_custom_domain != "" ? [
        {
          hosts      = [var.paperclip_custom_domain]
          secretName = "paperclip-tls"
        }
      ] : []
    }
  }
}

################################################################################
# Data source: Ingress LoadBalancer IP (for Terraform outputs and deployment)
################################################################################

data "external" "ingress_ip" {
  count = (var.enable_paperclip && var.paperclip_exposure == "public") || (var.enable_opencode && var.opencode_exposure == "public") ? 1 : 0

  depends_on = [
    time_sleep.wait_for_ingress_lb,
    kubectl_manifest.paperclip_ingress,
  ]

  program = ["python3", "${path.module}/scripts/detect_ingress_ip.py"]
}
