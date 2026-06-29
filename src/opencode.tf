################################################################################
# OpenCode — AI Coding Assistant (Web)
# Deploys OpenCode Web from a locally-built container image pushed to an
# external registry. Exposed via the shared NGINX Ingress Controller.
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

# Image already built and pushed to docker.io/lindoelio/opencode:1.17.11
# docker_registry_image resource removed — push completed manually due to provider digest bug

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

  lifecycle {
    prevent_destroy = true
  }
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
      OPENCODE_SERVER_PASSWORD = random_password.opencode_admin[count.index].result
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
    kubectl_manifest.opencode_pvc,
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
          containers = [
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
                  mountPath = "/root/.local/share/opencode"
                }
              ]
            }
          ]
          volumes = [
            {
              name = "opencode-data"
              persistentVolumeClaim = {
                claimName = "opencode-data"
              }
            }
          ]
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
      type = "ClusterIP"
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
  count = var.enable_opencode ? 1 : 0

  depends_on = [
    helm_release.nginx_ingress,
    time_sleep.wait_for_ingress_lb,
    kubectl_manifest.opencode_service,
  ]

  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "opencode"
      namespace = "opencode"
      annotations = merge(
        {
          "kubernetes.io/ingress.class" = "nginx"
        },
        var.opencode_custom_domain != "" ? {
          "cert-manager.io/cluster-issuer"           = "letsencrypt-prod"
          "nginx.ingress.kubernetes.io/ssl-redirect" = "true"
        } : {},
        var.opencode_custom_domain == "" ? {
          "nginx.ingress.kubernetes.io/rewrite-target" = "/$2"
        } : {}
      )
    }
    spec = {
      rules = [
        {
          host = var.opencode_custom_domain != "" ? var.opencode_custom_domain : ""
          http = {
            paths = [
              {
                path     = var.opencode_custom_domain != "" ? "/" : "${var.opencode_path_prefix}(/|$)(.*)"
                pathType = var.opencode_custom_domain != "" ? "Prefix" : "ImplementationSpecific"
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
      tls = var.opencode_custom_domain != "" && var.letsencrypt_email != "" ? [
        {
          hosts      = [var.opencode_custom_domain]
          secretName = "opencode-tls"
        }
      ] : []
    }
  }

  lifecycle {
    precondition {
      condition     = var.enable_opencode && var.opencode_exposure == "public"
      error_message = "OpenCode public exposure is required: set `opencode_exposure = \"public\"` or set `enable_opencode = false`."
    }
  }
}

resource "time_sleep" "after_opencode_ingress" {
  count = var.enable_opencode ? 1 : 0

  depends_on      = [kubectl_manifest.opencode_ingress]
  create_duration = "30s"
}