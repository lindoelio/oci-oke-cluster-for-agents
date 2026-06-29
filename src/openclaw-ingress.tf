################################################################################
# OpenClaw Ingress
# Exposes the OpenClaw operator Service via NGINX Ingress for API access.
################################################################################

resource "kubectl_manifest" "openclaw_ingress" {
  count = var.enable_openclaw ? 1 : 0

  depends_on = [
    helm_release.nginx_ingress,
    time_sleep.wait_for_ingress_lb,
    kubectl_manifest.openclaw_instance,
  ]

  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "openclaw"
      namespace = "openclaw"
      annotations = merge(
        {
          "kubernetes.io/ingress.class" = "nginx"
        },
        var.openclaw_custom_domain != "" ? {
          "cert-manager.io/cluster-issuer"           = "letsencrypt-prod"
          "nginx.ingress.kubernetes.io/ssl-redirect" = "true"
        } : {}
      )
    }
    spec = {
      rules = [
        {
          host = var.openclaw_custom_domain != "" ? var.openclaw_custom_domain : ""
          http = {
            paths = [
              {
                path     = "/"
                pathType = "Prefix"
                backend = {
                  service = {
                    name = "${var.project_prefix}-openclaw"
                    port = {
                      number = 18789
                    }
                  }
                }
              }
            ]
          }
        }
      ]
      tls = var.openclaw_custom_domain != "" && var.letsencrypt_email != "" ? [
        {
          hosts      = [var.openclaw_custom_domain]
          secretName = "openclaw-tls"
        }
      ] : []
    }
  }
}

resource "time_sleep" "after_openclaw_ingress" {
  count = var.enable_openclaw ? 1 : 0

  depends_on      = [kubectl_manifest.openclaw_ingress]
  create_duration = "30s"
}
