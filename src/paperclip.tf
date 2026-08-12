################################################################################
# Paperclip — AI Agent Orchestration Platform
# Deploys Paperclip directly (no operator) with a managed PostgreSQL sidecar.
# Image: ghcr.io/paperclipai/paperclip (ARM64 confirmed)
#
# qmd (local BM25 + vector + rerank search for agent memory recall) is
# provisioned by the qmd-setup initContainer onto the paperclip-data PVC
# (/paperclip/.qmd), version-stamped and idempotent — no custom image build
# or registry push required.
#
# Automated onboarding: an initContainer runs `paperclipai onboard` on first start
# and patches config.json for public internet access.
################################################################################

################################################################################
# Namespace
################################################################################

resource "kubectl_manifest" "paperclip_namespace" {
  count = var.enable_paperclip ? 1 : 0

  depends_on = [module.oke, time_sleep.after_cluster]

  manifest = {
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = "paperclip"
      labels = {
        managed-by = "terraform"
      }
    }
  }
}

################################################################################
# Secrets
################################################################################

resource "random_password" "paperclip_auth" {
  count   = var.enable_paperclip ? 1 : 0
  length  = 32
  special = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "random_password" "paperclip_db" {
  count   = var.enable_paperclip ? 1 : 0
  length  = 24
  special = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubectl_manifest" "paperclip_auth_secret" {
  count = var.enable_paperclip ? 1 : 0

  depends_on = [kubectl_manifest.paperclip_namespace]

  manifest = {
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "paperclip-auth"
      namespace = "paperclip"
    }
    type = "Opaque"
    stringData = {
      BETTER_AUTH_SECRET = random_password.paperclip_auth[0].result
    }
  }
}

resource "kubectl_manifest" "paperclip_db_secret" {
  count = var.enable_paperclip ? 1 : 0

  depends_on = [kubectl_manifest.paperclip_namespace]

  manifest = {
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "paperclip-db"
      namespace = "paperclip"
    }
    type = "Opaque"
    stringData = {
      POSTGRES_PASSWORD = random_password.paperclip_db[0].result
      DATABASE_URL      = "postgres://paperclip:${random_password.paperclip_db[0].result}@paperclip-db:5432/paperclip"
    }
  }
}

resource "kubectl_manifest" "paperclip_api_keys_secret" {
  count = var.enable_paperclip ? 1 : 0

  depends_on = [kubectl_manifest.paperclip_namespace]

  manifest = {
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "paperclip-api-keys"
      namespace = "paperclip"
    }
    type = "Opaque"
    stringData = merge(
      var.anthropic_api_key != "" ? { ANTHROPIC_API_KEY = var.anthropic_api_key } : {},
      var.openai_api_key != "" ? { OPENAI_API_KEY = var.openai_api_key } : {},
      var.openrouter_api_key != "" ? {
        OPENROUTER_API_KEY  = var.openrouter_api_key
        OPENROUTER_BASE_URL = "https://openrouter.ai/api/v1"
      } : {},
      var.ollama_cloud_api_key != "" ? {
        OLLAMA_CLOUD_API_KEY = var.ollama_cloud_api_key
        OLLAMA_BASE_URL      = "https://api.ollama.com"
      } : {},
    )
  }
}

################################################################################
# OpenCode Go provider secret (only created when a key is provided)
# Consumed by the opencode-go-auth initContainer to register the provider
# in the opencode CLI bundled with Paperclip.
################################################################################

resource "kubectl_manifest" "paperclip_opencode_go_secret" {
  count = var.enable_paperclip && var.opencode_go_api_key != "" ? 1 : 0

  depends_on = [kubectl_manifest.paperclip_namespace]

  manifest = {
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "opencode-go-auth"
      namespace = "paperclip"
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
# PostgreSQL StatefulSet
################################################################################

resource "kubectl_manifest" "paperclip_db_statefulset" {
  count = var.enable_paperclip ? 1 : 0

  depends_on = [kubectl_manifest.paperclip_db_secret]

  manifest = {
    apiVersion = "apps/v1"
    kind       = "StatefulSet"
    metadata = {
      name      = "paperclip-db"
      namespace = "paperclip"
      labels = {
        app        = "paperclip-db"
        managed-by = "terraform"
      }
    }
    spec = {
      serviceName = "paperclip-db"
      replicas    = 1
      selector = {
        matchLabels = {
          app = "paperclip-db"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "paperclip-db"
          }
        }
        spec = {
          securityContext = {
            fsGroup = 999
          }
          containers = [
            {
              name  = "postgres"
              image = "docker.io/library/postgres:17-alpine"
              ports = [
                {
                  containerPort = 5432
                  name          = "postgres"
                }
              ]
              env = [
                {
                  name  = "POSTGRES_USER"
                  value = "paperclip"
                },
                {
                  name  = "POSTGRES_DB"
                  value = "paperclip"
                },
                {
                  name  = "PGDATA"
                  value = "/var/lib/postgresql/data/pgdata"
                },
                {
                  name = "POSTGRES_PASSWORD"
                  valueFrom = {
                    secretKeyRef = {
                      name = "paperclip-db"
                      key  = "POSTGRES_PASSWORD"
                    }
                  }
                }
              ]
              volumeMounts = [
                {
                  name      = "pgdata"
                  mountPath = "/var/lib/postgresql/data"
                }
              ]
              resources = {
                requests = {
                  cpu    = "250m"
                  memory = "512Mi"
                }
                limits = {
                  cpu    = "750m"
                  memory = "2Gi"
                }
              }
              livenessProbe = {
                exec = {
                  command = ["pg_isready", "-U", "paperclip", "-d", "paperclip"]
                }
                initialDelaySeconds = 15
                periodSeconds       = 10
              }
              readinessProbe = {
                exec = {
                  command = ["pg_isready", "-U", "paperclip", "-d", "paperclip"]
                }
                initialDelaySeconds = 5
                periodSeconds       = 5
              }
            }
          ]
        }
      }
      volumeClaimTemplates = [
        {
          metadata = {
            name = "pgdata"
          }
          spec = {
            accessModes      = ["ReadWriteOnce"]
            storageClassName = "oci-bv"
            resources = {
              requests = {
                storage = var.paperclip_db_storage_size
              }
            }
          }
        }
      ]
    }
  }
}

resource "kubectl_manifest" "paperclip_db_service" {
  count = var.enable_paperclip ? 1 : 0

  depends_on = [kubectl_manifest.paperclip_db_statefulset]

  manifest = {
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "paperclip-db"
      namespace = "paperclip"
      labels = {
        app        = "paperclip-db"
        managed-by = "terraform"
      }
    }
    spec = {
      type = "ClusterIP"
      ports = [
        {
          port       = 5432
          targetPort = 5432
          protocol   = "TCP"
          name       = "postgres"
        }
      ]
      selector = {
        app = "paperclip-db"
      }
    }
  }
}

################################################################################
# Paperclip Deployment
################################################################################

resource "kubectl_manifest" "paperclip_deployment" {
  count = var.enable_paperclip ? 1 : 0

  depends_on = [
    kubectl_manifest.paperclip_auth_secret,
    kubectl_manifest.paperclip_api_keys_secret,
    kubectl_manifest.paperclip_opencode_go_secret,
    kubectl_manifest.paperclip_db_service,
    time_sleep.wait_for_ingress_lb,
    kubectl_manifest.paperclip_ingress,
  ]

  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "paperclip"
      namespace = "paperclip"
      labels = {
        app        = "paperclip"
        managed-by = "terraform"
      }
    }
    spec = {
      replicas = 1
      selector = {
        matchLabels = {
          app = "paperclip"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "paperclip"
          }
        }
        spec = {
          securityContext = {
            fsGroup = 1000
          }
          initContainers = concat([
            {
              name    = "paperclip-onboard"
              image   = "${var.paperclip_image_repository}:${var.paperclip_image_tag}"
              command = ["sh", "-c"]
              args    = [file("${path.module}/scripts/paperclip_onboard.sh")]
              env = [
                {
                  name  = "DATA_DIR"
                  value = "/paperclip"
                },
                {
                  name = "PAPERCLIP_PUBLIC_URL"
                  value = var.paperclip_public_url != "" ? var.paperclip_public_url : (
                    var.paperclip_custom_domain != "" ? "https://${var.paperclip_custom_domain}" : (
                      length(data.external.ingress_ip) > 0 ? "http://${data.external.ingress_ip[0].result["ip"]}" : "http://localhost:3100"
                    )
                  )
                },
                {
                  name  = "SUPPRESS_LABEL_WARNING"
                  value = "True"
                }
              ]
              volumeMounts = [
                {
                  name      = "paperclip-data"
                  mountPath = "/paperclip"
                }
              ]
              resources = {
                requests = {
                  cpu    = "100m"
                  memory = "256Mi"
                }
                limits = {
                  cpu    = "500m"
                  memory = "512Mi"
                }
              }
            }
            ], var.opencode_go_api_key != "" ? [
            {
              name    = "opencode-go-auth"
              image   = "${var.paperclip_image_repository}:${var.paperclip_image_tag}"
              command = ["python3", "-c"]
              args    = [file("${path.module}/scripts/opencode_go_auth.py")]
              env = [
                {
                  name  = "AUTH_PATH"
                  value = "/paperclip/.local/share/opencode/auth.json"
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
                  name      = "paperclip-data"
                  mountPath = "/paperclip"
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
            ] : [], var.enable_paperclip_qmd ? [
            {
              # Provisions qmd onto the PVC once per version (stamp-guarded);
              # glibc Debian like the app image, so native prebuilds apply.
              name    = "qmd-setup"
              image   = var.paperclip_qmd_installer_image
              command = ["sh", "-c"]
              args = [
                <<-EOT
                set -e
                if [ "$(cat /paperclip/.qmd/.version 2>/dev/null)" = "${var.paperclip_qmd_version}" ]; then
                  echo "qmd ${var.paperclip_qmd_version} already installed"
                  exit 0
                fi
                # Build tools for native tree-sitter grammars that compile from source.
                apt-get update
                apt-get install -y --no-install-recommends python3 make g++
                npm_config_cache=/tmp/npm-cache npm install --no-update-notifier --prefix /paperclip/.qmd "@tobilu/qmd@${var.paperclip_qmd_version}"
                npm exec --prefix /paperclip/.qmd -- qmd --version
                echo "${var.paperclip_qmd_version}" > /paperclip/.qmd/.version
                EOT
              ]
              env = [
                {
                  name  = "SUPPRESS_LABEL_WARNING"
                  value = "True"
                }
              ]
              volumeMounts = [
                {
                  name      = "paperclip-data"
                  mountPath = "/paperclip"
                }
              ]
              resources = {
                requests = {
                  cpu    = "250m"
                  memory = "512Mi"
                }
                limits = {
                  cpu    = "1000m"
                  memory = "1Gi"
                }
              }
            }
          ] : [])
          containers = [
            {
              name  = "paperclip"
              image = "${var.paperclip_image_repository}:${var.paperclip_image_tag}"
              ports = [
                {
                  containerPort = 3100
                  name          = "http"
                }
              ]
              env = concat([
                {
                  name  = "PORT"
                  value = "3100"
                },
                {
                  name  = "SERVE_UI"
                  value = "true"
                },
                {
                  name  = "PAPERCLIP_DEPLOYMENT_MODE"
                  value = "authenticated"
                },
                {
                  name  = "PAPERCLIP_DEPLOYMENT_EXPOSURE"
                  value = var.paperclip_exposure
                },
                {
                  name = "PAPERCLIP_PUBLIC_URL"
                  value = var.paperclip_public_url != "" ? var.paperclip_public_url : (
                    var.paperclip_custom_domain != "" ? "https://${var.paperclip_custom_domain}" : (
                      length(data.external.ingress_ip) > 0 ? "http://${data.external.ingress_ip[0].result["ip"]}" : "http://localhost:3100"
                    )
                  )
                },
                {
                  name  = "PAPERCLIP_AUTH_BASE_URL_MODE"
                  value = "explicit"
                },
                {
                  name = "DATABASE_URL"
                  valueFrom = {
                    secretKeyRef = {
                      name = "paperclip-db"
                      key  = "DATABASE_URL"
                    }
                  }
                },
                {
                  name = "BETTER_AUTH_SECRET"
                  valueFrom = {
                    secretKeyRef = {
                      name = "paperclip-auth"
                      key  = "BETTER_AUTH_SECRET"
                    }
                  }
                },
                {
                  name = "ANTHROPIC_API_KEY"
                  valueFrom = {
                    secretKeyRef = {
                      name     = "paperclip-api-keys"
                      key      = "ANTHROPIC_API_KEY"
                      optional = true
                    }
                  }
                },
                {
                  name = "OPENAI_API_KEY"
                  valueFrom = {
                    secretKeyRef = {
                      name     = "paperclip-api-keys"
                      key      = "OPENAI_API_KEY"
                      optional = true
                    }
                  }
                },
                {
                  name = "OPENROUTER_API_KEY"
                  valueFrom = {
                    secretKeyRef = {
                      name     = "paperclip-api-keys"
                      key      = "OPENROUTER_API_KEY"
                      optional = true
                    }
                  }
                },
                {
                  name = "OPENROUTER_BASE_URL"
                  valueFrom = {
                    secretKeyRef = {
                      name     = "paperclip-api-keys"
                      key      = "OPENROUTER_BASE_URL"
                      optional = true
                    }
                  }
                },
                {
                  name = "OLLAMA_CLOUD_API_KEY"
                  valueFrom = {
                    secretKeyRef = {
                      name     = "paperclip-api-keys"
                      key      = "OLLAMA_CLOUD_API_KEY"
                      optional = true
                    }
                  }
                },
                {
                  name = "OLLAMA_BASE_URL"
                  valueFrom = {
                    secretKeyRef = {
                      name     = "paperclip-api-keys"
                      key      = "OLLAMA_BASE_URL"
                      optional = true
                    }
                  }
                },
                {
                  # Budget lane (recovery retries) of the opencode_local adapter.
                  # Env name is fixed upstream by the adapter; the VALUE is a full
                  # provider/model id, free to target any configured provider.
                  name  = "PAPERCLIP_OPENCODE_CHEAP_MODEL"
                  value = var.paperclip_cheap_model
                }
                ], var.enable_paperclip_qmd ? [
                {
                  # qmd is installed on the PVC by the qmd-setup initContainer
                  # (npm --prefix layout: bin lives in node_modules/.bin).
                  name  = "PATH"
                  value = "/paperclip/.qmd/node_modules/.bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
                }
              ] : [])
              volumeMounts = [
                {
                  name      = "paperclip-data"
                  mountPath = "/paperclip"
                }
              ]
              resources = {
                requests = {
                  cpu    = "500m"
                  memory = "1Gi"
                }
                limits = {
                  cpu    = var.paperclip_cpu_limit
                  memory = var.paperclip_memory_limit
                }
              }
              livenessProbe = {
                httpGet = {
                  path = "/"
                  port = 3100
                }
                initialDelaySeconds = 30
                periodSeconds       = 10
              }
              readinessProbe = {
                httpGet = {
                  path = "/"
                  port = 3100
                }
                initialDelaySeconds = 10
                periodSeconds       = 5
              }
            }
          ]
          volumes = [
            {
              name = "paperclip-data"
              persistentVolumeClaim = {
                claimName = "paperclip-data"
              }
            }
          ]
        }
      }
    }
  }
}

resource "kubectl_manifest" "paperclip_pvc" {
  count = var.enable_paperclip ? 1 : 0

  depends_on = [kubectl_manifest.paperclip_namespace]

  manifest = {
    apiVersion = "v1"
    kind       = "PersistentVolumeClaim"
    metadata = {
      name      = "paperclip-data"
      namespace = "paperclip"
      labels = {
        app        = "paperclip"
        managed-by = "terraform"
      }
    }
    spec = {
      accessModes      = ["ReadWriteOnce"]
      storageClassName = "oci-bv"
      resources = {
        requests = {
          storage = var.paperclip_storage_size
        }
      }
    }
  }
}

################################################################################
# Paperclip Service
################################################################################

resource "kubectl_manifest" "paperclip_service" {
  count = var.enable_paperclip ? 1 : 0

  depends_on = [kubectl_manifest.paperclip_namespace]

  manifest = {
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "paperclip"
      namespace = "paperclip"
      labels = {
        app        = "paperclip"
        managed-by = "terraform"
      }
    }
    spec = {
      type = var.paperclip_exposure == "public" ? "ClusterIP" : "ClusterIP"
      ports = [
        {
          port       = 80
          targetPort = 3100
          protocol   = "TCP"
          name       = "http"
        }
      ]
      selector = {
        app = "paperclip"
      }
    }
  }
}
