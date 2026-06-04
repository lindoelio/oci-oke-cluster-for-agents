################################################################################
# cert-manager — Automatic TLS certificate management
# Deploys cert-manager via Helm and creates a Let's Encrypt ClusterIssuer.
################################################################################

################################################################################
# cert-manager Helm Release
################################################################################

resource "helm_release" "cert_manager" {
  count = var.enable_paperclip && var.paperclip_exposure == "public" ? 1 : 0

  depends_on = [module.oke, time_sleep.after_cluster]

  name       = "cert-manager"
  namespace  = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "1.16.2"

  create_namespace = true

  values = [
    <<-EOF
    installCRDs: true
    EOF
  ]
}

################################################################################
# Wait for cert-manager readiness
################################################################################

resource "time_sleep" "wait_for_cert_manager" {
  count = var.enable_paperclip && var.paperclip_exposure == "public" ? 1 : 0

  depends_on      = [helm_release.cert_manager]
  create_duration = "60s"
}

################################################################################
# Let's Encrypt ClusterIssuer
################################################################################

resource "kubectl_manifest" "letsencrypt_issuer" {
  count = var.enable_paperclip && var.paperclip_exposure == "public" && var.letsencrypt_email != "" ? 1 : 0

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
                class = "nginx"
              }
            }
          }
        ]
      }
    }
  }
}
