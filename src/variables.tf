### Project Prefix

variable "project_prefix" {
  description = "Project prefix for all resource naming (lowercase alphanumeric, 3-15 characters)"
  type        = string
  default     = "myproject" # Change this with your desired project name

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,14}$", var.project_prefix))
    error_message = "The project_prefix must be lowercase alphanumeric, start with a letter, and be between 3 and 15 characters."
  }
}

### OCI General

variable "oci_tenancy_id" {
  description = "OCI Tenancy ID"
  type        = string
}

variable "oci_region" {
  description = "OCI Region"
  type        = string
  default     = "sa-saopaulo-1"
}

variable "oci_home_region" {
  description = "OCI home region for tenancy-scoped operations"
  type        = string
  default     = "sa-saopaulo-1"
}

variable "oci_compartment_id" {
  description = "Parent OCI compartment ID under which the project child compartment will be created (used only if oci_project_compartment_id is empty)"
  type        = string
}

variable "oci_project_compartment_id" {
  description = "Existing project compartment OCID. If set, this compartment will be used directly instead of creating a new one. Leave empty to create a new compartment named after project_prefix."
  type        = string
  default     = ""
}

variable "oci_public_workers" {
  description = "Place worker nodes in a public subnet and disable NAT Gateway creation; exposes nodes with public IPs. Review network pricing and access rules."
  type        = bool
  default     = false
}

variable "oci_control_plane_allowed_cidrs" {
  description = "CIDRs allowed to reach the Kubernetes API. Restrict to operator/VPN egress addresses before deployment."
  type        = list(string)

  validation {
    condition     = length(var.oci_control_plane_allowed_cidrs) > 0 && alltrue([for cidr in var.oci_control_plane_allowed_cidrs : can(cidrnetmask(cidr))])
    error_message = "Provide at least one valid IPv4 CIDR for Kubernetes API access."
  }
}


### OKE

variable "oci_oke_node_shape" {
  description = "OCI OKE Node Shape"
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "oci_oke_node_shape_ocpus" {
  description = "OCI OKE Node Shape OCPUs"
  type        = number
  default     = 2
}

variable "oci_oke_node_shape_memory_in_gbs" {
  description = "OCI OKE Node Shape Memory in GBs"
  type        = number
  default     = 12
}

variable "oci_oke_node_pool_size" {
  description = "OCI OKE Node Pool Size"
  type        = number
  default     = 2
}

variable "oci_oke_kubernetes_version" {
  description = "OCI OKE Kubernetes version"
  type        = string
  default     = "v1.36.1"
}

### Paperclip (Agent Orchestration Platform)

variable "enable_paperclip" {
  description = "Deploy Paperclip with a self-managed PostgreSQL StatefulSet"
  type        = bool
  default     = true
}

variable "paperclip_image_repository" {
  description = "Paperclip application image repository"
  type        = string
  default     = "ghcr.io/paperclipai/paperclip"
}

variable "paperclip_image_tag" {
  description = "Pinned Paperclip stable release image tag"
  type        = string
  default     = "2026.831.1"
}

variable "enable_paperclip_qmd" {
  description = "Provision qmd (local BM25 + vector + rerank search for agent memory recall) onto the Paperclip PVC via the qmd-setup initContainer"
  type        = bool
  default     = true
}

variable "paperclip_qmd_version" {
  description = "Version of the @tobilu/qmd npm package installed on the Paperclip PVC"
  type        = string
  default     = "2.5.3"
}

variable "paperclip_qmd_installer_image" {
  description = "Image used by the qmd-setup initContainer to install qmd; must be glibc-based Debian with the same Node major as the Paperclip image so native prebuilds apply"
  type        = string
  default     = "docker.io/library/node:24-slim"
}

variable "enable_paperclip_firebase_cli" {
  description = "Provision Firebase CLI onto the Paperclip PVC via the firebase-setup initContainer so agents can run firebase commands"
  type        = bool
  default     = true
}

variable "paperclip_firebase_tools_version" {
  description = "Version of the firebase-tools npm package installed on the Paperclip PVC"
  type        = string
  default     = "15.26.0"
}

variable "enable_metrics_server" {
  description = "Deploy metrics-server (kubectl top, resource visibility) into kube-system"
  type        = bool
  default     = true
}

variable "metrics_server_chart_version" {
  description = "Helm chart version of metrics-server"
  type        = string
  default     = "3.13.1"
}

variable "alibaba_token_plan_api_key" {
  description = "Alibaba Token Plan (International, ap-southeast-1) API key seeded as a company secret for the primary company; consumed by the built-in opencode 'alibaba-token-plan' provider via ALIBABA_TOKEN_PLAN_API_KEY. Company mapping lives in the git-ignored seeding script/spec"
  type        = string
  default     = ""
  sensitive   = true
}

variable "alibaba_token_plan_api_key_secondary" {
  description = "Optional independent Alibaba Token Plan API key copy for a second company (rotatable per company); empty disables seeding for that company"
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_paperclip_browser" {
  description = "Deploy a headless Chromium (CDP) service in the paperclip namespace for agent browser automation"
  type        = bool
  default     = true
}

variable "paperclip_browser_version" {
  description = "Playwright version for the browser service image and the agent-side client library (kept in sync)"
  type        = string
  default     = "1.62.1"
}

variable "deepinfra_api_key" {
  description = "DeepInfra API key (OpenAI-compatible, api.deepinfra.com/v1) for the primary company; seeded as a company secret and injected into the OpenCode Web server for the built-in deepinfra provider"
  type        = string
  default     = ""
  sensitive   = true
}

variable "deepinfra_api_key_secondary" {
  description = "Independent DeepInfra API key for a second company (rotatable per company); empty disables seeding for that company. Company mapping lives in the git-ignored seeding script"
  type        = string
  default     = ""
  sensitive   = true
}

variable "paperclip_exposure" {
  description = "Paperclip service exposure: 'public' (shared Ingress) or 'private' (ClusterIP)"
  type        = string
  default     = "private"

  validation {
    condition     = contains(["public", "private"], var.paperclip_exposure)
    error_message = "paperclip_exposure must be 'public' or 'private'."
  }
}

variable "paperclip_public_url" {
  description = "Public URL for Paperclip (used in invite links). If empty and no custom domain is set, auto-detected from the Ingress LoadBalancer IP. Set explicitly to override."
  type        = string
  default     = ""
}

variable "paperclip_custom_domain" {
  description = "Custom domain for Paperclip. HTTPS also requires letsencrypt_email, DNS, and successful certificate issuance."
  type        = string
  default     = ""
}

variable "oci_native_ingress_version" {
  description = "OCI Native Ingress Controller standalone Helm chart and image version"
  type        = string
  default     = "1.4.5"
}

variable "oci_native_shared_certificate_ocid" {
  description = "OCI Certificates OCID for the shared HTTPS listener when Paperclip and Qwen use the same OCI Native load balancer. Obtain it after the controller imports the agents-tls secret."
  type        = string
  default     = ""
}

variable "cert_manager_version" {
  description = "cert-manager Helm chart version compatible with the selected Kubernetes version"
  type        = string
  default     = "1.21.1"
}

variable "paperclip_db_storage_size" {
  description = "Storage request for Paperclip's self-managed PostgreSQL (OCI Block Volume minimum: 50 GB)"
  type        = string
  default     = "50Gi"
}

variable "paperclip_storage_size" {
  description = "Storage size for Paperclip data persistence"
  type        = string
  default     = "50Gi"
}

variable "paperclip_cpu_limit" {
  description = "CPU limit for Paperclip instance"
  type        = string
  default     = "1500m"
}

variable "paperclip_memory_limit" {
  description = "Memory limit for Paperclip instance"
  type        = string
  default     = "6Gi"
}

variable "paperclip_cheap_model" {
  description = "Fallback/budget-lane model for Paperclip's opencode_local adapter (recovery retries). Full provider/model id — any provider the deployment supports (OpenRouter, OpenCode Go, etc.), not tied to one gateway. The adapter's upstream default is an OpenAI model that our gateway does not serve."
  type        = string
  default     = "openrouter/nvidia/nemotron-3.5-lightning:free"
}

variable "ollama_cloud_api_key" {
  description = "Ollama Cloud API key for local/remote Ollama model access"
  type        = string
  default     = ""
  sensitive   = true
}

variable "openrouter_api_key" {
  description = "OpenRouter API key for multi-model LLM access (Pi, Hermes, OpenCode, etc.). Enables OpenRouter provider in Paperclip."
  type        = string
  default     = ""
  sensitive   = true
}

variable "anthropic_api_key" {
  description = "Anthropic API key for LLM access"
  type        = string
  default     = ""
  sensitive   = true
}

variable "openai_api_key" {
  description = "OpenAI API key for LLM access"
  type        = string
  default     = ""
  sensitive   = true
}

variable "letsencrypt_email" {
  description = "Email address for the optional Let's Encrypt ClusterIssuer managed through the OKE CertManager add-on"
  type        = string
  default     = ""
}

### OpenClaw (Agent Runtime)

variable "enable_openclaw" {
  description = "Deploy OpenClaw operator and instance"
  type        = bool
  default     = false
}

variable "openclaw_chart_version" {
  description = "OpenClaw operator Helm chart version (oci://ghcr.io/paperclipinc/charts/openclaw-operator)"
  type        = string
  default     = "0.36.5"
}

variable "openclaw_image_repository" {
  description = "OpenClaw application image repository"
  type        = string
  default     = "ghcr.io/openclaw/openclaw"
}

variable "openclaw_image_tag" {
  description = "OpenClaw application image tag (ARM64 build)"
  type        = string
  default     = "latest"
}

variable "openclaw_llm_provider" {
  description = "Default LLM provider for OpenClaw"
  type        = string
  default     = "openrouter"
}

variable "openclaw_llm_model" {
  description = "Default LLM model for OpenClaw"
  type        = string
  default     = "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free"
}

variable "openclaw_llm_api_key" {
  description = "LLM API key for OpenClaw"
  type        = string
  default     = ""
  sensitive   = true
}

variable "openclaw_storage_size" {
  description = "Storage size for OpenClaw workspace"
  type        = string
  default     = "50Gi"
}

variable "openclaw_cpu_limit" {
  description = "CPU limit for OpenClaw instance"
  type        = string
  default     = "500m"
}

variable "openclaw_memory_limit" {
  description = "Memory limit for OpenClaw instance"
  type        = string
  default     = "2Gi"
}

variable "openclaw_telegram_enabled" {
  description = "Enable Telegram bot integration for OpenClaw"
  type        = bool
  default     = true
}

variable "openclaw_telegram_bot_token" {
  description = "Telegram bot token for OpenClaw"
  type        = string
  default     = ""
  sensitive   = true
}

variable "openclaw_telegram_owner_id" {
  description = "Telegram numeric user ID for auto-approval (e.g., '8547618136'). If set, this user bypasses manual pairing approval."
  type        = string
  default     = ""
}

variable "openclaw_custom_domain" {
  description = "Custom domain for OpenClaw API access (e.g., 'openclaw.example.com'). Enables HTTPS + Let's Encrypt when set with letsencrypt_email."
  type        = string
  default     = ""
}

### OpenCode (AI Coding Assistant)

variable "enable_opencode" {
  description = "Deploy OpenCode Web with managed workspace persistence"
  type        = bool
  default     = false
}

variable "opencode_exposure" {
  description = "OpenCode service exposure: 'public' (Ingress, requires an ingress controller) or 'private' (ClusterIP only)"
  type        = string
  default     = "private"

  validation {
    condition     = contains(["public", "private"], var.opencode_exposure)
    error_message = "opencode_exposure must be 'public' or 'private'."
  }
}

variable "opencode_version" {
  description = "OpenCode application version (GitHub release tag, e.g., '1.17.11')"
  type        = string
  default     = "1.17.13"
}

variable "opencode_admin_password" {
  description = "Operator-chosen password for the OpenCode Web basic auth (username 'opencode'); empty falls back to the generated random_password"
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_opencode_browser" {
  description = "Give OpenCode Web agents browser automation: cdp-forward sidecar to the paperclip-browser service (requires enable_paperclip_browser) plus the playwright client library provisioned onto the PVC"
  type        = bool
  default     = true
}

variable "opencode_custom_domain" {
  description = "Custom domain for OpenCode Web (e.g., 'opencode.example.com'). If set, HTTPS + Let's Encrypt is enabled when letsencrypt_email is also set."
  type        = string
  default     = ""
}

variable "opencode_storage_size" {
  description = "Storage size for OpenCode workspace persistence"
  type        = string
  default     = "50Gi"
}

variable "opencode_cpu_limit" {
  description = "CPU limit for OpenCode instance"
  type        = string
  default     = "500m"
}

variable "opencode_memory_limit" {
  description = "Memory limit for OpenCode instance"
  type        = string
  default     = "8Gi"
}

variable "enable_qwen" {
  description = "Deploy QwenCode Web (qwen serve daemon + Web Shell UI) with managed workspace persistence"
  type        = bool
  default     = true
}

variable "qwen_version" {
  description = "Qwen Code CLI version (npm @qwen-code/qwen-code tag, e.g., '0.23.0')"
  type        = string
  default     = "0.23.0"
}

variable "qwen_admin_password" {
  description = "Operator-chosen password for QwenCode Web: ingress basic auth (username 'qwen') and the qwen serve bearer token; empty falls back to the generated random_password"
  type        = string
  default     = ""
  sensitive   = true
}

variable "qwen_custom_domain" {
  description = "Custom domain for QwenCode Web (e.g., 'qwen.example.com'). If set, HTTPS + Let's Encrypt is enabled when letsencrypt_email is also set."
  type        = string
  default     = ""
}

variable "qwen_storage_size" {
  description = "Storage size for QwenCode state and workspace persistence"
  type        = string
  default     = "50Gi"
}

variable "qwen_cpu_limit" {
  description = "CPU limit for the QwenCode daemon container"
  type        = string
  default     = "1500m"
}

variable "qwen_memory_limit" {
  description = "Memory limit for the QwenCode daemon container"
  type        = string
  default     = "6Gi"
}

variable "enable_qwen_browser" {
  description = "Give QwenCode agents browser automation: cdp-forward sidecar to the paperclip-browser service (requires enable_paperclip_browser) plus the playwright client library provisioned onto the PVC"
  type        = bool
  default     = true
}

variable "opencode_registry" {
  description = "Container registry for the locally built OpenCode image: 'ghcr' (GitHub Container Registry) or 'dockerhub' (Docker Hub)"
  type        = string
  default     = "ghcr"

  validation {
    condition     = contains(["ghcr", "dockerhub"], var.opencode_registry)
    error_message = "opencode_registry must be 'ghcr' or 'dockerhub'."
  }
}

variable "opencode_registry_namespace" {
  description = "Namespace or organization on the container registry (e.g., your GitHub username or Docker Hub ID)"
  type        = string
  default     = ""
}

variable "opencode_registry_username" {
  description = "Username for authenticating to the external container registry"
  type        = string
  default     = ""
}

variable "opencode_registry_token" {
  description = "Personal Access Token (PAT) with 'write:packages' scope for GHCR or equivalent for Docker Hub"
  type        = string
  default     = ""
  sensitive   = true
}

variable "opencode_go_api_key" {
  description = "OpenCode Go subscription API key (https://opencode.ai/go). When set, registers the built-in 'opencode-go' provider in both OpenCode Web and Paperclip's bundled opencode CLI."
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_token" {
  description = "GitHub Personal Access Token (classic) for GitHub CLI authentication in OpenCode. Scopes: repo, workflow."
  type        = string
  default     = ""
  sensitive   = true
}

variable "gcp_service_account_key" {
  description = "Google Cloud Platform service account key JSON for gcloud authentication in OpenCode. Download from GCP Console: IAM & Admin > Service Accounts > Keys."
  type        = string
  default     = ""
  sensitive   = true
}

variable "firebase_token" {
  description = "Firebase CLI token (optional). Can be generated via 'firebase login:ci'. Reuses GCP service account if empty."
  type        = string
  default     = ""
  sensitive   = true
}

variable "gitlab_token" {
  description = "GitLab personal access token for glab / GitLab API in OpenCode (scopes: api, write_repository, read_api)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "gitlab_preview_token" {
  description = "GitLab token used for MR preview environments in CI (masked GitLab CI variable source). Optional."
  type        = string
  default     = ""
  sensitive   = true
}

variable "neon_api_key" {
  description = "Neon API key for the neon/neonctl CLI in OpenCode."
  type        = string
  default     = ""
  sensitive   = true
}

variable "neon_org_id" {
  description = "Neon organization id (multi-org accounts)."
  type        = string
  default     = ""
}

variable "expo_token" {
  description = "Expo access token for eas / EAS CLI in OpenCode."
  type        = string
  default     = ""
  sensitive   = true
}

variable "paddle_sandbox_api_key" {
  description = "Paddle sandbox API key for the paddle-sandbox MCP used by billing agents."
  type        = string
  default     = ""
  sensitive   = true
}
