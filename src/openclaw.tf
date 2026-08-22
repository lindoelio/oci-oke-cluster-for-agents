################################################################################
# OpenClaw Operator + Instance
# Deploys the OpenClaw AI agent runtime via its Kubernetes operator.
# Chart: oci://ghcr.io/paperclipinc/charts/openclaw-operator
################################################################################

resource "helm_release" "openclaw_operator" {
  count = var.enable_openclaw ? 1 : 0

  depends_on = [module.oke, time_sleep.after_cluster]

  name             = "openclaw-operator"
  repository       = "oci://ghcr.io/paperclipinc/charts"
  chart            = "openclaw-operator"
  version          = var.openclaw_chart_version
  namespace        = "openclaw-system"
  create_namespace = true

  cleanup_on_fail = true
  wait            = true
  wait_for_jobs   = true
}

resource "time_sleep" "after_openclaw_operator" {
  count = var.enable_openclaw ? 1 : 0

  depends_on      = [helm_release.openclaw_operator]
  create_duration = "30s"
}

################################################################################
# OpenClaw Namespace
################################################################################

resource "kubectl_manifest" "openclaw_namespace" {
  count = var.enable_openclaw ? 1 : 0

  depends_on = [time_sleep.after_openclaw_operator]

  manifest = {
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = "openclaw"
      labels = {
        managed-by = "terraform"
      }
    }
  }
}

################################################################################
# Secrets
################################################################################

resource "kubectl_manifest" "openclaw_llm_secret" {
  count = var.enable_openclaw ? 1 : 0

  depends_on = [kubectl_manifest.openclaw_namespace]

  manifest = {
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "openclaw-llm-keys"
      namespace = "openclaw"
    }
    type = "Opaque"
    stringData = {
      LLM_API_KEY = var.openclaw_llm_api_key
    }
  }
}

resource "kubectl_manifest" "openclaw_telegram_secret" {
  count = var.enable_openclaw && var.openclaw_telegram_enabled && var.openclaw_telegram_bot_token != "" ? 1 : 0

  depends_on = [kubectl_manifest.openclaw_namespace]

  manifest = {
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "openclaw-telegram"
      namespace = "openclaw"
    }
    type = "Opaque"
    stringData = {
      TELEGRAM_BOT_TOKEN = var.openclaw_telegram_bot_token
    }
  }
}

################################################################################
# OpenClaw ConfigMap — openclaw.json with full model + auth config
################################################################################

resource "kubectl_manifest" "openclaw_config" {
  count = var.enable_openclaw ? 1 : 0

  depends_on = [kubectl_manifest.openclaw_namespace]

  manifest = {
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "openclaw-config"
      namespace = "openclaw"
    }
    data = {
      "openclaw.json" = jsonencode(merge(
        {
          gateway = {
            bind = "lan"
          }
        },
        var.openclaw_telegram_owner_id != "" ? {
          commands = {
            ownerAllowFrom = ["telegram:${var.openclaw_telegram_owner_id}"]
          }
        } : {},
        # Agents defaults with proper model configuration
        {
          agents = {
            defaults = {
              model = {
                primary = var.openclaw_llm_model
              }
              models = {
                "${var.openclaw_llm_model}" = {}
              }
            }
          }
        },
        # Auth profiles reference (without actual keys — keys injected via kubectl cp post-deploy)
        {
          auth = {
            profiles = {
              "openrouter:manual" = {
                provider = "openrouter"
                mode     = "api_key"
              }
            }
          }
        }
      ))
    }
  }
}

################################################################################
# OpenClaw Instance CRD
################################################################################

resource "kubectl_manifest" "openclaw_instance" {
  count = var.enable_openclaw ? 1 : 0

  depends_on = [
    kubectl_manifest.openclaw_llm_secret,
    kubectl_manifest.openclaw_config,
  ]

  manifest = {
    apiVersion = "openclaw.rocks/v1alpha1"
    kind       = "OpenClawInstance"
    metadata = {
      name      = "${var.project_prefix}-openclaw"
      namespace = "openclaw"
    }
    spec = {
      image = {
        repository = var.openclaw_image_repository
        tag        = var.openclaw_image_tag
      }
      config = {
        configMapRef = {
          name = "openclaw-config"
          key  = "openclaw.json"
        }
      }
      env = concat(
        [
          {
            name  = "LLM_PROVIDER"
            value = var.openclaw_llm_provider
          },
          {
            name  = "LLM_MODEL"
            value = var.openclaw_llm_model
          },
          {
            name = "LLM_API_KEY"
            valueFrom = {
              secretKeyRef = {
                name = "openclaw-llm-keys"
                key  = "LLM_API_KEY"
              }
            }
          }
        ],
        var.openclaw_telegram_enabled && var.openclaw_telegram_bot_token != "" ? [
          {
            name = "TELEGRAM_BOT_TOKEN"
            valueFrom = {
              secretKeyRef = {
                name = "openclaw-telegram"
                key  = "TELEGRAM_BOT_TOKEN"
              }
            }
          }
        ] : []
      )
      storage = {
        persistence = {
          enabled      = true
          size         = var.openclaw_storage_size
          storageClass = "oci-bv"
        }
      }
      gateway = {
        enabled = false
      }
      observability = {
        metrics = {
          enabled = false
        }
      }
      resources = {
        requests = {
          cpu    = "100m"
          memory = "256Mi"
        }
        limits = {
          cpu    = var.openclaw_cpu_limit
          memory = var.openclaw_memory_limit
        }
      }
    }
  }
}

################################################################################
# OpenClaw data PVC (created by the operator)
# Declared here so that disabling OpenClaw also destroys the PVC and releases
# its 50 GB block volume back to the Always Free storage quota. The operator
# defaults to persistence.orphan=true, so it leaves the PVC alone on CR delete.
# Imported once with:
#   terraform import 'kubectl_manifest.openclaw_data_pvc[0]' \
#     'v1//PersistentVolumeClaim//<prefix>-openclaw-data//openclaw'
################################################################################

resource "kubectl_manifest" "openclaw_data_pvc" {
  count = var.enable_openclaw ? 1 : 0

  depends_on = [kubectl_manifest.openclaw_namespace]

  manifest = {
    apiVersion = "v1"
    kind       = "PersistentVolumeClaim"
    metadata = {
      name      = "${var.project_prefix}-openclaw-data"
      namespace = "openclaw"
      labels = {
        managed-by = "terraform"
      }
    }
    spec = {
      accessModes      = ["ReadWriteOnce"]
      storageClassName = "oci-bv"
      resources = {
        requests = {
          storage = var.openclaw_storage_size
        }
      }
    }
  }
}

################################################################################
# Post-deploy fix for stale OpenAI Codex auth routes
# Runs via local-exec to configure models.json + auth-profiles.json in the pod
################################################################################

resource "null_resource" "openclaw_fix_stale_auth" {
  count = var.enable_openclaw ? 1 : 0

  depends_on = [
    kubectl_manifest.openclaw_instance,
  ]

  # Only re-run when the LLM config changes
  triggers = {
    llm_api_key_hash = sha256(var.openclaw_llm_api_key)
    llm_model        = var.openclaw_llm_model
    llm_provider     = var.openclaw_llm_provider
  }

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e
      
      POD_NAME="${var.project_prefix}-openclaw-0"
      NAMESPACE="openclaw"
      
      echo "=== OpenClaw Auth Fix ==="
      echo "Waiting for pod $POD_NAME to be ready..."
      kubectl wait --for=condition=ready pod -n "$NAMESPACE" "$POD_NAME" --timeout=120s
      
      sleep 10
      
      # Create models.json with OpenRouter provider only (no stale codex)
      cat > /tmp/openclaw_models.json << 'JSONEOF'
      {
        "providers": {
          "openrouter": {
            "baseUrl": "https://openrouter.ai/api/v1",
            "auth": "apiKey",
            "api": "openai-chat",
            "models": [
              {
                "id": "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free",
                "name": "Nemotron 3 Nano Omni 30B",
                "api": "openai-chat",
                "reasoning": true,
                "input": ["text"],
                "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
                "contextWindow": 128000,
                "maxTokens": 4096,
                "compat": {"supportsReasoningEffort": true, "supportsUsageInStreaming": true}
              }
            ]
          }
        }
      }
      JSONEOF
      
      # Create auth-profiles.json with the API key
      cat > /tmp/openclaw_auth.json << 'JSONEOF'
      {
        "profiles": [
          {
            "id": "openrouter:manual",
            "provider": "openrouter",
            "kind": "apiKey",
            "key": "${var.openclaw_llm_api_key}",
            "createdAt": "${timestamp()}"
          }
        ]
      }
      JSONEOF
      
      # Copy files to pod
      echo "Copying models.json..."
      kubectl cp /tmp/openclaw_models.json "$NAMESPACE/$POD_NAME:/home/openclaw/.openclaw/agents/main/agent/models.json"
      
      echo "Copying auth-profiles.json..."
      kubectl cp /tmp/openclaw_auth.json "$NAMESPACE/$POD_NAME:/home/openclaw/.openclaw/agents/main/agent/auth-profiles.json"
      
      echo "Restarting OpenClaw pod..."
      kubectl rollout restart -n "$NAMESPACE" statefulset/${var.project_prefix}-openclaw
      
      sleep 30
      
      echo "=== OpenClaw auth fix completed ==="
      echo "Run 'kubectl logs -n openclaw pod/$POD_NAME' to verify the model loads correctly"
    EOT
  }
}
