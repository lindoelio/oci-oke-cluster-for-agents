################################################################################
# OpenClaw Ingress
# Exposes the OpenClaw operator Service through OCI Native Ingress.
################################################################################

resource "kubectl_manifest" "openclaw_ingress" {
  count = local.openclaw_public ? 1 : 0

  depends_on = [
    time_sleep.wait_for_ingress_lb,
    kubectl_manifest.openclaw_instance,
    kubectl_manifest.letsencrypt_issuer,
  ]

  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "openclaw"
      namespace = "openclaw"
      annotations = merge(
        {
          "oci-native-ingress.oraclecloud.com/backend-tls-enabled" = "false"
        },
        local.openclaw_tls ? merge({
          "oci-native-ingress.oraclecloud.com/https-listener-port" = "443"
          }, local.shared_listener_tls ? {
          "oci-native-ingress.oraclecloud.com/certificate-ocid" = var.oci_native_shared_certificate_ocid
          } : {
          "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
        }) : {
          "oci-native-ingress.oraclecloud.com/http-listener-port" = "80"
        }
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
      ingressClassName = local.ingress_class
      tls = local.openclaw_tls && !local.shared_listener_tls ? [
        {
          hosts      = [var.openclaw_custom_domain]
          secretName = "openclaw-tls"
        }
      ] : []
    }
  }
}

resource "time_sleep" "after_openclaw_ingress" {
  count = local.openclaw_public ? 1 : 0

  depends_on      = [kubectl_manifest.openclaw_ingress]
  create_duration = "30s"
}
