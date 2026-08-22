################################################################################
# Browser-as-a-service for Paperclip agents
# Headless Chromium (official Playwright image, ARM64) exposing CDP so agents
# can navigate, screenshot and test web UIs without depending on the operator.
# Agents connect with playwright.chromium.connectOverCDP(PAPERCLIP_BROWSER_CDP).
################################################################################

################################################################################
# Deployment
################################################################################

resource "kubectl_manifest" "paperclip_browser" {
  count = var.enable_paperclip ? (var.enable_paperclip_browser ? 1 : 0) : 0

  depends_on = [kubectl_manifest.paperclip_namespace]

  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "paperclip-browser"
      namespace = "paperclip"
      labels = {
        app        = "paperclip-browser"
        managed-by = "terraform"
      }
    }
    spec = {
      replicas = 1
      selector = {
        matchLabels = {
          app = "paperclip-browser"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "paperclip-browser"
          }
        }
        spec = {
          containers = [
            {
              name    = "chromium"
              image   = "mcr.microsoft.com/playwright:v${var.paperclip_browser_version}-noble"
              command = ["sh", "-c"]
              args = [
                <<-EOT
                # Chrome only binds CDP to loopback nowadays; cdp_proxy.js
                # exposes it on 0.0.0.0:9222 rewriting the Host header.
                /ms-playwright/chromium-*/chrome-linux/chrome \
                  --headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage \
                  --remote-debugging-address=127.0.0.1 --remote-debugging-port=9223 \
                  --remote-allow-origins=* \
                  --user-data-dir=/tmp/chrome-profile about:blank &
                exec node -e "$CDP_PROXY_JS"
                EOT
              ]
              env = [
                {
                  name  = "CDP_PROXY_JS"
                  value = file("${path.module}/scripts/cdp_proxy.js")
                }
              ]
              ports = [
                {
                  containerPort = 9222
                  name          = "cdp"
                }
              ]
              resources = {
                requests = {
                  cpu    = "250m"
                  memory = "512Mi"
                }
                limits = {
                  cpu    = "1000m"
                  memory = "2Gi"
                }
              }
              livenessProbe = {
                tcpSocket = {
                  port = 9222
                }
                initialDelaySeconds = 15
                periodSeconds       = 15
              }
              readinessProbe = {
                tcpSocket = {
                  port = 9222
                }
                initialDelaySeconds = 5
                periodSeconds       = 5
              }
            }
          ]
        }
      }
    }
  }
}

################################################################################
# Service
################################################################################

resource "kubectl_manifest" "paperclip_browser_service" {
  count = var.enable_paperclip ? (var.enable_paperclip_browser ? 1 : 0) : 0

  depends_on = [kubectl_manifest.paperclip_browser]

  manifest = {
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "paperclip-browser"
      namespace = "paperclip"
      labels = {
        app        = "paperclip-browser"
        managed-by = "terraform"
      }
    }
    spec = {
      type = "ClusterIP"
      ports = [
        {
          port       = 9222
          targetPort = 9222
          protocol   = "TCP"
          name       = "cdp"
        }
      ]
      selector = {
        app = "paperclip-browser"
      }
    }
  }
}
