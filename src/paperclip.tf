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

################################################################################
# Model-catalog discovery secret. The Paperclip server lists available models
# by spawning `opencode models` with its own process env, so provider keys must
# exist at server level for the UI catalog. Cross-company leakage into agent
# RUNS is prevented because every agent's run env explicitly overrides (or
# blank-blocks) these same keys via per-company secret bindings.
################################################################################

resource "kubectl_manifest" "paperclip_model_discovery_secret" {
  count = var.enable_paperclip && (var.openrouter_api_key != "" || var.ollama_cloud_api_key != "" || var.alibaba_token_plan_api_key != "") ? 1 : 0

  depends_on = [kubectl_manifest.paperclip_namespace]

  manifest = {
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "paperclip-model-discovery"
      namespace = "paperclip"
      labels = {
        managed-by = "terraform"
      }
    }
    type = "Opaque"
    stringData = merge(
      var.openrouter_api_key != "" ? {
        OPENROUTER_API_KEY  = var.openrouter_api_key
        OPENROUTER_BASE_URL = "https://openrouter.ai/api/v1"
      } : {},
      var.ollama_cloud_api_key != "" ? {
        OLLAMA_CLOUD_API_KEY = var.ollama_cloud_api_key
        OLLAMA_BASE_URL      = "https://api.ollama.com"
      } : {},
      var.alibaba_token_plan_api_key != "" ? { ALIBABA_TOKEN_PLAN_API_KEY = var.alibaba_token_plan_api_key } : {},
      var.deepinfra_api_key != "" ? { DEEPINFRA_API_KEY = var.deepinfra_api_key } : {},
    )
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
    kubectl_manifest.paperclip_model_discovery_secret,
    kubectl_manifest.paperclip_db_service,
    kubectl_manifest.paperclip_browser_service,
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
            ], [
            {
              # Writes per-company opencode auth.json homes by decrypting the
              # opencode_go_api_key company secrets (local_encrypted) from the
              # DB; replaces the old cluster-global auth.json.
              name    = "company-auth-writer"
              image   = "${var.paperclip_image_repository}:${var.paperclip_image_tag}"
              command = ["node", "-e", file("${path.module}/scripts/company_auth_writer.js")]
              env = [
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
                  name  = "AUTH_UID"
                  value = "1000"
                },
                {
                  name  = "AUTH_GID"
                  value = "1000"
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
                  cpu    = "10m"
                  memory = "64Mi"
                }
                limits = {
                  cpu    = "200m"
                  memory = "256Mi"
                }
              }
            }
            ], var.enable_paperclip_qmd ? [
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
            ] : [], var.enable_paperclip_firebase_cli ? [
            {
              # Provisions firebase-tools onto the PVC once per version
              # (stamp-guarded); same pattern and installer image as qmd-setup.
              name    = "firebase-setup"
              image   = var.paperclip_qmd_installer_image
              command = ["sh", "-c"]
              args = [
                <<-EOT
                set -e
                if [ "$(cat /paperclip/.firebase/.version 2>/dev/null)" = "${var.paperclip_firebase_tools_version}" ]; then
                  echo "firebase-tools ${var.paperclip_firebase_tools_version} already installed"
                  exit 0
                fi
                npm_config_cache=/tmp/npm-cache npm install --no-update-notifier --prefix /paperclip/.firebase "firebase-tools@${var.paperclip_firebase_tools_version}"
                npm exec --prefix /paperclip/.firebase -- firebase --version
                echo "${var.paperclip_firebase_tools_version}" > /paperclip/.firebase/.version
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
            ] : [], var.enable_paperclip_browser ? [
            {
              # Playwright client library on the PVC (browsers live in the
              # paperclip-browser service; client connects over CDP).
              name    = "browser-setup"
              image   = "${var.paperclip_image_repository}:${var.paperclip_image_tag}"
              command = ["sh", "-c"]
              args = [
                <<-EOT
                set -e
                if [ "$(cat /paperclip/.playwright/.version 2>/dev/null)" = "${var.paperclip_browser_version}" ]; then
                  echo "playwright ${var.paperclip_browser_version} already installed"
                  exit 0
                fi
                PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm_config_cache=/tmp/npm-cache npm install --no-update-notifier --prefix /paperclip/.playwright "playwright@${var.paperclip_browser_version}"
                echo "${var.paperclip_browser_version}" > /paperclip/.playwright/.version
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
                  cpu    = "100m"
                  memory = "256Mi"
                }
                limits = {
                  cpu    = "500m"
                  memory = "512Mi"
                }
              }
            }
          ] : [])
          containers = [
            {
              # Shares the pod netns: tools inside the main container that
              # expect a LOCAL Chrome CDP endpoint
              # find it at 127.0.0.1:9222, forwarded to the browser service.
              name    = "cdp-forward"
              image   = "${var.paperclip_image_repository}:${var.paperclip_image_tag}"
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
            },
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
                # Server-level provider keys for the UI model catalog only;
                # agent runs override or blank-block these per company.
                {
                  name = "OPENROUTER_API_KEY"
                  valueFrom = {
                    secretKeyRef = {
                      name     = "paperclip-model-discovery"
                      key      = "OPENROUTER_API_KEY"
                      optional = true
                    }
                  }
                },
                {
                  name = "OPENROUTER_BASE_URL"
                  valueFrom = {
                    secretKeyRef = {
                      name     = "paperclip-model-discovery"
                      key      = "OPENROUTER_BASE_URL"
                      optional = true
                    }
                  }
                },
                {
                  name = "OLLAMA_CLOUD_API_KEY"
                  valueFrom = {
                    secretKeyRef = {
                      name     = "paperclip-model-discovery"
                      key      = "OLLAMA_CLOUD_API_KEY"
                      optional = true
                    }
                  }
                },
                {
                  name = "OLLAMA_BASE_URL"
                  valueFrom = {
                    secretKeyRef = {
                      name     = "paperclip-model-discovery"
                      key      = "OLLAMA_BASE_URL"
                      optional = true
                    }
                  }
                },
                {
                  name = "ALIBABA_TOKEN_PLAN_API_KEY"
                  valueFrom = {
                    secretKeyRef = {
                      name     = "paperclip-model-discovery"
                      key      = "ALIBABA_TOKEN_PLAN_API_KEY"
                      optional = true
                    }
                  }
                },
                {
                  name = "DEEPINFRA_API_KEY"
                  valueFrom = {
                    secretKeyRef = {
                      name     = "paperclip-model-discovery"
                      key      = "DEEPINFRA_API_KEY"
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
                ], var.enable_paperclip_qmd || var.enable_paperclip_firebase_cli || var.enable_paperclip_browser ? [
                {
                  # qmd / firebase-tools are installed on the PVC by the
                  # qmd-setup / firebase-setup initContainers (npm --prefix
                  # layout: bins live in node_modules/.bin).
                  name  = "PATH"
                  value = "/paperclip/.qmd/node_modules/.bin:/paperclip/.firebase/node_modules/.bin:/paperclip/.playwright/node_modules/.bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
                },
                {
                  # Lets agent scripts require("playwright") resolve the
                  # PVC-installed client library.
                  name  = "NODE_PATH"
                  value = "/paperclip/.playwright/node_modules"
                },
                {
                  name  = "PAPERCLIP_BROWSER_CDP"
                  value = "http://paperclip-browser.paperclip.svc.cluster.local:9222"
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
                  path = "/api/health"
                  port = 3100
                }
                # Generous timing: agent run spikes can saturate the node
                # briefly; a tight probe kill-loops the pod under load.
                initialDelaySeconds = 60
                periodSeconds       = 15
                timeoutSeconds      = 5
                failureThreshold    = 6
              }
              readinessProbe = {
                httpGet = {
                  path = "/api/health"
                  port = 3100
                }
                initialDelaySeconds = 15
                periodSeconds       = 10
                timeoutSeconds      = 5
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
