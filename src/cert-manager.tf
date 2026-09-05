################################################################################
# cert-manager
#
# OCI Native Ingress uses cert-manager for its admission webhooks. When an ACME
# email is set, the same installation issues application certificates. OKE
# add-on management requires an Enhanced cluster, so Basic clusters use the
# upstream Helm chart to avoid the Enhanced control-plane charge.
################################################################################

resource "helm_release" "cert_manager" {
  count = local.ingress_enabled ? 1 : 0

  depends_on = [module.oke, time_sleep.after_cluster]

  name       = "cert-manager"
  namespace  = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.cert_manager_version

  create_namespace = true
  wait             = true

  values = [yamlencode({
    crds = {
      enabled = true
    }
  })]

  timeout = 1800
}

resource "time_sleep" "wait_for_cert_manager" {
  count = local.ingress_enabled ? 1 : 0

  depends_on      = [helm_release.cert_manager]
  create_duration = "60s"
}

resource "kubectl_manifest" "letsencrypt_issuer" {
  count = local.tls_enabled ? 1 : 0

  depends_on = [time_sleep.wait_for_cert_manager]

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = var.letsencrypt_email
        privateKeySecretRef = {
          name = "letsencrypt-prod"
        }
        solvers = [
          {
            http01 = {
              ingress = {
                ingressClassName = local.ingress_class
                ingressTemplate = {
                  metadata = {
                    annotations = {
                      "oci-native-ingress.oraclecloud.com/http-listener-port" = "80"
                    }
                  }
                }
              }
            }
          }
        ]
      }
    }
  }
}

# A single SAN certificate is required in OCI regions where an HTTPS listener
# accepts only one certificate. Paperclip keeps the Kubernetes secret attached
# so OCI Native imports renewals; Qwen references that same OCI certificate.
resource "kubectl_manifest" "agents_certificate" {
  count = local.shared_listener_tls ? 1 : 0

  depends_on = [kubectl_manifest.letsencrypt_issuer]

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "agents-tls"
      namespace = "paperclip"
    }
    spec = {
      secretName = "agents-tls"
      issuerRef = {
        name = "letsencrypt-prod"
        kind = "ClusterIssuer"
      }
      dnsNames = local.tls_hosts
      usages   = ["digital signature", "key encipherment"]
    }
  }
}
