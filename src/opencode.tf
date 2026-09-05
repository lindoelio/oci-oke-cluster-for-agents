################################################################################
# OpenCode — AI Coding Assistant (Web)
# Deploys OpenCode Web from a locally-built container image pushed to an
# external registry. Optionally exposed via OCI Native Ingress.
# Image: built from official anomalyco/opencode release (ARM64)
################################################################################

locals {
  opencode_enabled = var.enable_opencode
  registry_host    = var.opencode_registry == "ghcr" ? "ghcr.io" : "docker.io"
  image_name       = "${local.registry_host}/${var.opencode_registry_namespace}/opencode:${var.opencode_version}"
}

################################################################################
# Docker Image Build + External Registry Push
################################################################################

resource "docker_image" "opencode" {
  count = var.enable_opencode ? 1 : 0

  name = local.image_name

  build {
    context    = path.module
    dockerfile = "scripts/opencode.Dockerfile"
    build_args = {
      OPENCODE_VERSION = var.opencode_version
    }
  }
}

# Registry push is an operator step; Terraform only builds the local image.
# Publish the matching ARM64 tag before deploying the Kubernetes workload.

resource "time_sleep" "after_opencode_image" {
  count = var.enable_opencode ? 1 : 0

  depends_on      = [docker_image.opencode]
  create_duration = "30s"
}

################################################################################
# OpenCode Namespace
################################################################################

resource "kubectl_manifest" "opencode_namespace" {
  count = var.enable_opencode ? 1 : 0

  depends_on = [module.oke, time_sleep.after_cluster]

  manifest = {
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = "opencode"
      labels = {
        managed-by = "terraform"
      }
    }
  }
}

################################################################################
# Secrets
################################################################################

resource "random_password" "opencode_admin" {
  count   = var.enable_opencode ? 1 : 0
  length  = 32
  special = true

}

resource "kubectl_manifest" "opencode_auth_secret" {
  count = var.enable_opencode ? 1 : 0

  depends_on = [kubectl_manifest.opencode_namespace]

  manifest = {
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "opencode-auth"
      namespace = "opencode"
    }
    type = "Opaque"
    stringData = {
      OPENCODE_SERVER_PASSWORD = var.opencode_admin_password != "" ? var.opencode_admin_password : random_password.opencode_admin[count.index].result
    }
  }
}

resource "kubectl_manifest" "opencode_llm_keys_secret" {
  count = var.enable_opencode ? 1 : 0

  depends_on = [kubectl_manifest.opencode_namespace]

  manifest = {
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "opencode-llm-keys"
      namespace = "opencode"
    }
    type = "Opaque"
    stringData = merge(
      var.anthropic_api_key != "" ? { ANTHROPIC_API_KEY = var.anthropic_api_key } : {},
      var.openai_api_key != "" ? { OPENAI_API_KEY = var.openai_api_key } : {},
      var.openrouter_api_key != "" ? { OPENROUTER_API_KEY = var.openrouter_api_key } : {},
      var.ollama_cloud_api_key != "" ? { OLLAMA_CLOUD_API_KEY = var.ollama_cloud_api_key } : {},
      var.deepinfra_api_key != "" ? { DEEPINFRA_API_KEY = var.deepinfra_api_key } : {},
      var.alibaba_token_plan_api_key != "" ? { ALIBABA_TOKEN_PLAN_API_KEY = var.alibaba_token_plan_api_key } : {},
      var.alibaba_token_plan_api_key_secondary != "" ? { ALIBABA_TOKEN_PLAN_API_KEY_SECONDARY = var.alibaba_token_plan_api_key_secondary } : {},
    )
  }
}

################################################################################
# OpenCode Developer Credentials Secret (GitHub, GCP, Firebase)
################################################################################

resource "kubectl_manifest" "opencode_dev_credentials" {
  count = var.enable_opencode ? 1 : 0

  depends_on = [kubectl_manifest.opencode_namespace]

  manifest = {
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "opencode-dev-credentials"
      namespace = "opencode"
    }
    type = "Opaque"
    stringData = merge(
      var.github_token != "" ? { GITHUB_TOKEN = var.github_token } : {},
      var.gcp_service_account_key != "" ? { GOOGLE_APPLICATION_CREDENTIALS_JSON = var.gcp_service_account_key } : {},
      var.firebase_token != "" ? { FIREBASE_TOKEN = var.firebase_token } : {},
    )
  }
}
################################################################################
# OpenCode Tool Keys Secret (GitLab, Neon, Expo, Paddle)
################################################################################

resource "kubectl_manifest" "opencode_tool_keys" {
  count = var.enable_opencode ? 1 : 0

  depends_on = [kubectl_manifest.opencode_namespace]

  manifest = {
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "opencode-tool-keys"
      namespace = "opencode"
    }
    type = "Opaque"
    stringData = merge(
      var.gitlab_token != "" ? { GITLAB_TOKEN = var.gitlab_token } : {},
      var.gitlab_preview_token != "" ? { GITLAB_PREVIEW_TOKEN = var.gitlab_preview_token } : {},
      var.neon_api_key != "" ? { NEON_API_KEY = var.neon_api_key } : {},
      var.neon_org_id != "" ? { NEON_ORG_ID = var.neon_org_id } : {},
      var.expo_token != "" ? { EXPO_TOKEN = var.expo_token } : {},
      var.paddle_sandbox_api_key != "" ? { PADDLE_SANDBOX_API_KEY = var.paddle_sandbox_api_key } : {},
    )
  }
}


################################################################################
# OpenCode Go provider secret (only created when a key is provided)
################################################################################

resource "kubectl_manifest" "opencode_go_secret" {
  count = var.enable_opencode && var.opencode_go_api_key != "" ? 1 : 0

  depends_on = [kubectl_manifest.opencode_namespace]

  manifest = {
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "opencode-go-auth"
      namespace = "opencode"
      labels = {
        managed-by = "terraform"
      }
    }
    type = "Opaque"
    stringData = {
      OPENCODE_GO_API_KEY = var.opencode_go_api_key
    }
  }
}

################################################################################
# OpenCode PersistentVolumeClaim
################################################################################

resource "kubectl_manifest" "opencode_pvc" {
  count = var.enable_opencode ? 1 : 0

  depends_on = [kubectl_manifest.opencode_namespace]

  manifest = {
    apiVersion = "v1"
    kind       = "PersistentVolumeClaim"
    metadata = {
      name      = "opencode-data"
      namespace = "opencode"
      labels = {
        app        = "opencode"
        managed-by = "terraform"
      }
    }
    spec = {
      accessModes      = ["ReadWriteOnce"]
      storageClassName = "oci-bv"
      resources = {
        requests = {
          storage = var.opencode_storage_size
        }
      }
    }
  }
}

################################################################################
# OpenCode Deployment
################################################################################

resource "kubectl_manifest" "opencode_deployment" {
  count = var.enable_opencode ? 1 : 0

  depends_on = [
    docker_image.opencode,
    time_sleep.after_opencode_image,
    kubectl_manifest.opencode_auth_secret,
    kubectl_manifest.opencode_llm_keys_secret,
    kubectl_manifest.opencode_go_secret,
    kubectl_manifest.opencode_pvc,
    kubectl_manifest.opencode_tool_keys,
  ]

  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "opencode"
      namespace = "opencode"
      labels = {
        app        = "opencode"
        managed-by = "terraform"
      }
    }
    spec = {
      replicas = 1
      selector = {
        matchLabels = {
          app = "opencode"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "opencode"
          }
        }
        spec = {
          securityContext = {
            fsGroup = 1000
          }
          initContainers = concat(var.opencode_go_api_key != "" ? [
            {
              name    = "opencode-go-auth"
              image   = docker_image.opencode[count.index].name
              command = ["python3", "-c"]
              args    = [file("${path.module}/scripts/opencode_go_auth.py")]
              env = [
                {
                  name  = "AUTH_PATH"
                  value = "/home/opencode/.local/share/opencode/auth.json"
                },
                {
                  name  = "AUTH_UID"
                  value = "1000"
                },
                {
                  name  = "AUTH_GID"
                  value = "1000"
                },
                {
                  name = "OPENCODE_GO_API_KEY"
                  valueFrom = {
                    secretKeyRef = {
                      name = "opencode-go-auth"
                      key  = "OPENCODE_GO_API_KEY"
                    }
                  }
                }
              ]
              volumeMounts = [
                {
                  name      = "opencode-data"
                  mountPath = "/home/opencode/.local/share/opencode"
                }
              ]
              resources = {
                requests = {
                  cpu    = "10m"
                  memory = "32Mi"
                }
                limits = {
                  cpu    = "100m"
                  memory = "128Mi"
                }
              }
            }
            ] : [], var.enable_opencode_browser ? [
            {
              # Playwright client library on the PVC (the browsers live in the
              # shared paperclip-browser service; the client connects over CDP).
              # Version pinned to paperclip_browser_version for client/server match.
              name    = "browser-setup"
              image   = docker_image.opencode[count.index].name
              command = ["sh", "-c"]
              args = [
                <<-EOT
                set -e
                if [ "$(cat /home/opencode/.playwright/.version 2>/dev/null)" = "${var.paperclip_browser_version}" ]; then
                  echo "playwright ${var.paperclip_browser_version} already installed"
                  exit 0
                fi
                npm install --prefix /home/opencode/.playwright playwright@${var.paperclip_browser_version}
                echo "${var.paperclip_browser_version}" > /home/opencode/.playwright/.version
                EOT
              ]
              volumeMounts = [
                {
                  name      = "opencode-data"
                  mountPath = "/home/opencode/.playwright"
                  subPath   = "playwright"
                }
              ]
              resources = {
                requests = {
                  cpu    = "50m"
                  memory = "128Mi"
                }
                limits = {
                  cpu    = "500m"
                  memory = "512Mi"
                }
              }
            }
          ] : [])
          containers = concat([
            {
              name            = "opencode"
              image           = docker_image.opencode[count.index].name
              imagePullPolicy = "Always"
              ports = [
                {
                  containerPort = 4096
                  name          = "http"
                }
              ]
              env = concat(
                [
                  {
                    name = "OPENCODE_SERVER_PASSWORD"
                    valueFrom = {
                      secretKeyRef = {
                        name = "opencode-auth"
                        key  = "OPENCODE_SERVER_PASSWORD"
                      }
                    }
                  },
                  {
                    name  = "OPENCODE_SERVER_USERNAME"
                    value = "opencode"
                  },
                  {
                    # Headless container: stops opencode from trying to spawn
                    # xdg-open at startup (ENOENT crash on some releases).
                    name  = "BROWSER"
                    value = "none"
                  },
                  {
                    # Browser automation via the shared paperclip-browser
                    # service; the cdp-forward sidecar exposes it at
                    # localhost:9222 for tools that assume a local Chrome.
                    name  = "OPENCODE_BROWSER_CDP"
                    value = "http://localhost:9222"
                  },
                  {
                    # Playwright client installed on the PVC by browser-setup.
                    name  = "NODE_PATH"
                    value = "/home/opencode/.playwright/node_modules"
                  },
                  {
                    name  = "PATH"
                    value = "/home/opencode/.playwright/node_modules/.bin:/opt/google-cloud-sdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
                  },
                  {
                    # The kubelet creates the volume mount's intermediate dirs as root,
                    # so the app cannot mkdir ~/.local/state on the container FS.
                    # Route XDG state into the (fsGroup-writable) data volume instead.
                    name  = "XDG_STATE_HOME"
                    value = "/home/opencode/.local/share/opencode/state"
                  }
                ],
                var.anthropic_api_key != "" ? [
                  {
                    name = "ANTHROPIC_API_KEY"
                    valueFrom = {
                      secretKeyRef = {
                        name     = "opencode-llm-keys"
                        key      = "ANTHROPIC_API_KEY"
                        optional = true
                      }
                    }
                  }
                ] : [],
                var.openai_api_key != "" ? [
                  {
                    name = "OPENAI_API_KEY"
                    valueFrom = {
                      secretKeyRef = {
                        name     = "opencode-llm-keys"
                        key      = "OPENAI_API_KEY"
                        optional = true
                      }
                    }
                  }
                ] : [],
                var.openrouter_api_key != "" ? [
                  {
                    name = "OPENROUTER_API_KEY"
                    valueFrom = {
                      secretKeyRef = {
                        name     = "opencode-llm-keys"
                        key      = "OPENROUTER_API_KEY"
                        optional = true
                      }
                    }
                  }
                ] : [],
                var.ollama_cloud_api_key != "" ? [
                  {
                    name = "OLLAMA_CLOUD_API_KEY"
                    valueFrom = {
                      secretKeyRef = {
                        name     = "opencode-llm-keys"
                        key      = "OLLAMA_CLOUD_API_KEY"
                        optional = true
                      }
                    }
                  }
                ] : [],
                var.deepinfra_api_key != "" ? [
                  {
                    name = "DEEPINFRA_API_KEY"
                    valueFrom = {
                      secretKeyRef = {
                        name     = "opencode-llm-keys"
                        key      = "DEEPINFRA_API_KEY"
                        optional = true
                      }
                    }
                  }
                ] : [],
                var.alibaba_token_plan_api_key != "" ? [
                  {
                    name = "ALIBABA_TOKEN_PLAN_API_KEY"
                    valueFrom = {
                      secretKeyRef = {
                        name     = "opencode-llm-keys"
                        key      = "ALIBABA_TOKEN_PLAN_API_KEY"
                        optional = true
                      }
                    }
                  }
                ] : [],
                var.alibaba_token_plan_api_key_secondary != "" ? [
                  {
                    name = "ALIBABA_TOKEN_PLAN_API_KEY_SECONDARY"
                    valueFrom = {
                      secretKeyRef = {
                        name     = "opencode-llm-keys"
                        key      = "ALIBABA_TOKEN_PLAN_API_KEY_SECONDARY"
                        optional = true
                      }
                    }
                  }
                ] : [],
                var.github_token != "" ? [
                  {
                    name = "GITHUB_TOKEN"
                    valueFrom = {
                      secretKeyRef = {
                        name     = "opencode-dev-credentials"
                        key      = "GITHUB_TOKEN"
                        optional = true
                      }
                    }
                  }
                ] : [],
                var.gcp_service_account_key != "" ? [
                  {
                    name = "GOOGLE_APPLICATION_CREDENTIALS_JSON"
                    valueFrom = {
                      secretKeyRef = {
                        name     = "opencode-dev-credentials"
                        key      = "GOOGLE_APPLICATION_CREDENTIALS_JSON"
                        optional = true
                      }
                    }
                  }
                ] : [],
                var.firebase_token != "" ? [
                  {
                    name = "FIREBASE_TOKEN"
                    valueFrom = {
                      secretKeyRef = {
                        name     = "opencode-dev-credentials"
                        key      = "FIREBASE_TOKEN"
                        optional = true
                      }
                    }
                  }
                ] : [],
                var.gitlab_token != "" ? [
                  {
                    name = "GITLAB_TOKEN"
                    valueFrom = {
                      secretKeyRef = {
                        name     = "opencode-tool-keys"
                        key      = "GITLAB_TOKEN"
                        optional = true
                      }
                    }
                  }
                ] : [],
                var.gitlab_preview_token != "" ? [
                  {
                    name = "GITLAB_PREVIEW_TOKEN"
                    valueFrom = {
                      secretKeyRef = {
                        name     = "opencode-tool-keys"
                        key      = "GITLAB_PREVIEW_TOKEN"
                        optional = true
                      }
                    }
                  }
                ] : [],
                var.neon_api_key != "" ? [
                  {
                    name = "NEON_API_KEY"
                    valueFrom = {
                      secretKeyRef = {
                        name     = "opencode-tool-keys"
                        key      = "NEON_API_KEY"
                        optional = true
                      }
                    }
                  }
                ] : [],
                var.neon_org_id != "" ? [
                  {
                    name = "NEON_ORG_ID"
                    valueFrom = {
                      secretKeyRef = {
                        name     = "opencode-tool-keys"
                        key      = "NEON_ORG_ID"
                        optional = true
                      }
                    }
                  }
                ] : [],
                var.expo_token != "" ? [
                  {
                    name = "EXPO_TOKEN"
                    valueFrom = {
                      secretKeyRef = {
                        name     = "opencode-tool-keys"
                        key      = "EXPO_TOKEN"
                        optional = true
                      }
                    }
                  }
                ] : [],
                var.paddle_sandbox_api_key != "" ? [
                  {
                    name = "PADDLE_SANDBOX_API_KEY"
                    valueFrom = {
                      secretKeyRef = {
                        name     = "opencode-tool-keys"
                        key      = "PADDLE_SANDBOX_API_KEY"
                        optional = true
                      }
                    }
                  }
                ] : []
              )
              resources = {
                requests = {
                  cpu    = "100m"
                  memory = "256Mi"
                }
                limits = {
                  cpu    = var.opencode_cpu_limit
                  memory = var.opencode_memory_limit
                }
              }
              livenessProbe = {
                tcpSocket = {
                  port = 4096
                }
                initialDelaySeconds = 30
                periodSeconds       = 10
              }
              readinessProbe = {
                tcpSocket = {
                  port = 4096
                }
                initialDelaySeconds = 10
                periodSeconds       = 5
              }
              volumeMounts = [
                {
                  name      = "opencode-data"
                  mountPath = "/home/opencode/.local/share/opencode"
                },
                {
                  # Project workspaces live on the PVC so sessions survive
                  # image rebuilds (the image layer is ephemeral).
                  name      = "opencode-data"
                  mountPath = "/home/opencode/workspace"
                  subPath   = "workspaces"
                },
                {
                  name      = "opencode-data"
                  mountPath = "/home/opencode/.playwright"
                  subPath   = "playwright"
                }
              ]
            }
            ], var.enable_opencode_browser ? [
            {
              # Shares the pod netns: tools inside the main container that
              # expect a LOCAL Chrome CDP endpoint find it at 127.0.0.1:9222,
              # forwarded to the shared paperclip-browser service.
              name    = "cdp-forward"
              image   = docker_image.opencode[count.index].name
              command = ["node", "-e", file("${path.module}/scripts/cdp_proxy.js")]
              env = [
                {
                  name  = "CDP_TARGET_HOST"
                  value = "paperclip-browser.paperclip.svc.cluster.local"
                },
                {
                  name  = "CDP_TARGET_PORT"
                  value = "9222"
                },
                {
                  name  = "CDP_LISTEN_PORT"
                  value = "9222"
                }
              ]
              resources = {
                requests = {
                  cpu    = "10m"
                  memory = "32Mi"
                }
                limits = {
                  cpu    = "200m"
                  memory = "128Mi"
                }
              }
            }
          ] : [])
          volumes = [
            {
              name = "opencode-data"
              persistentVolumeClaim = {
                claimName = "opencode-data"
              }
            }
          ]
          affinity = {
            podAntiAffinity = {
              preferredDuringSchedulingIgnoredDuringExecution = [
                {
                  weight = 100
                  podAffinityTerm = {
                    labelSelector = {
                      matchExpressions = [
                        {
                          key      = "app"
                          operator = "In"
                          values   = ["paperclip", "paperclip-db"]
                        }
                      ]
                    }
                    topologyKey = "kubernetes.io/hostname"
                  }
                }
              ]
            }
          }
        }
      }
    }
  }
}

################################################################################
# OpenCode Service (ClusterIP)
################################################################################

resource "kubectl_manifest" "opencode_service" {
  count = var.enable_opencode ? 1 : 0

  depends_on = [kubectl_manifest.opencode_namespace]

  manifest = {
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "opencode"
      namespace = "opencode"
      labels = {
        app        = "opencode"
        managed-by = "terraform"
      }
    }
    spec = {
      type = local.opencode_public ? "NodePort" : "ClusterIP"
      ports = [
        {
          port       = 80
          targetPort = 4096
          protocol   = "TCP"
          name       = "http"
        }
      ]
      selector = {
        app = "opencode"
      }
    }
  }
}

################################################################################
# OpenCode Ingress
################################################################################

resource "kubectl_manifest" "opencode_ingress" {
  count = local.opencode_public ? 1 : 0

  depends_on = [
    time_sleep.wait_for_ingress_lb,
    kubectl_manifest.opencode_service,
    kubectl_manifest.letsencrypt_issuer,
  ]

  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "opencode"
      namespace = "opencode"
      annotations = merge(
        {
          "oci-native-ingress.oraclecloud.com/backend-tls-enabled" = "false"
        },
        local.opencode_tls ? merge({
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
          host = var.opencode_custom_domain
          http = {
            paths = [
              {
                path     = "/"
                pathType = "Prefix"
                backend = {
                  service = {
                    name = "opencode"
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
      ingressClassName = local.ingress_class
      tls = local.opencode_tls && !local.shared_listener_tls ? [
        {
          hosts      = [var.opencode_custom_domain]
          secretName = "opencode-tls"
        }
      ] : []
    }
  }

}

resource "time_sleep" "after_opencode_ingress" {
  count = local.opencode_public ? 1 : 0

  depends_on      = [kubectl_manifest.opencode_ingress]
  create_duration = "30s"
}
