################################################################################
# Paperclip — AI Agent Orchestration Platform
# Deploys Paperclip directly (no operator) with a managed PostgreSQL sidecar.
# Image: ghcr.io/paperclipai/paperclip (ARM64 confirmed)
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
                  cpu    = "100m"
                  memory = "256Mi"
                }
                limits = {
                  cpu    = "500m"
                  memory = "1Gi"
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
          initContainers = [
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
          ]
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
              env = [
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
