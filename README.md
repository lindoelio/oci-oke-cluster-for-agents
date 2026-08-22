# OCI OKE Cluster for Remote AI Agents

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.14-623CE4?logo=terraform)](https://www.terraform.io)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.36-326CE5?logo=kubernetes)](https://kubernetes.io)

A single-command Terraform deployment that provisions a **private Kubernetes cluster on OCI for remote AI Agents**, for development and testing purposes. Ships with **Paperclip** (AI agent orchestration), **OpenClaw** (AI agent runtime), and **OpenCode Web** (AI agent interface). Batteries included — NGINX Ingress, cert-manager with Let's Encrypt, and managed PostgreSQL, all within the OCI free tier.

## Features

- **Single `terraform apply`** — Cluster, networking, apps, ingress, and TLS in one shot
- **OKE Cluster** — OCI-managed Kubernetes via `oracle-terraform-modules/oke/oci` v5.4.3
- **Free Tier** — 2x ARM-based `VM.Standard.A1.Flex` nodes (4 OCPUs, 24GB RAM total)
- **Paperclip** — Agent orchestration UI with managed PostgreSQL (direct deployment, no operator)
- **OpenClaw** — Agent runtime with Telegram integration, deployed via official operator (v0.34.5)
- **OpenCode Web** — AI agent interface built from upstream ARM64 release, with HTTP Basic Auth and persistent sessions
- **NGINX Ingress Controller** — Single OCI LoadBalancer entry point for all HTTP/HTTPS traffic
- **cert-manager + Let's Encrypt** — Automatic TLS certificates for custom domains
- **CRI-O Short-Name Fix** — DaemonSet configuring `docker.io` as default registry on all nodes
- **OCI Child Compartment** — All resources isolated in a Terraform-managed child compartment
- **No `hashicorp/kubernetes` provider** — Uses `hashicorp-oss/kubectl` to avoid known hangs on K8s 1.36.x

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                        OCI Tenancy (Free Tier)                       │
│  ┌───────────────────────────────────────────────────────────────┐   │
│  │              Child Compartment (tf-managed)                    │   │
│  │                                                               │   │
│  │  ┌── OKE Cluster (K8s v1.36.0, 2x A1.Flex ARM) ──────────┐  │   │
│  │  │                                                        │  │   │
│  │  │  kube-system/                                          │  │   │
│  │  │    └─ crio-shortname-fix (DaemonSet)                   │  │   │
│  │  │                                                        │  │   │
│  │  │  ingress-nginx/                                        │  │   │
│  │  │    └─ NGINX Ingress Controller (OCI LB, 10Mbps)        │  │   │
│  │  │                                                        │  │   │
│  │  │  cert-manager/                                         │  │   │
│  │  │    └─ cert-manager + Let's Encrypt ClusterIssuer       │  │   │
│  │  │                                                        │  │   │
│  │  │  paperclip/                                            │  │   │
│  │  │    ├─ Paperclip Deployment (:3100)                     │  │   │
│  │  │    ├─ PostgreSQL StatefulSet (17-alpine)               │  │   │
│  │  │    └─ Ingress (NGINX) + optional TLS (cert-manager)    │  │   │
│  │  │                                                        │  │   │
│  │  │  openclaw-system/                                      │  │   │
│  │  │    └─ openclaw-operator (Helm, v0.34.5)                │  │   │
│  │  │                                                        │  │   │
  │  │  │  openclaw/                                             │  │   │
  │  │  │    ├─ OpenClawInstance CRD → OpenClaw Runtime          │  │   │
  │  │  │    └─ Service: ClusterIP (:18789)                      │  │   │
  │  │  │                                                        │  │   │
  │  │  │  opencode/                                             │  │   │
  │  │  │    ├─ OpenCode Deployment (:4096)                      │  │   │
  │  │  │    ├─ OpenCode PVC (oci-bv, 5Gi)                     │  │   │
  │  │  │    └─ Ingress (NGINX) + optional TLS (cert-manager)   │  │   │
  │  │  └────────────────────────────────────────────────────────┘  │   │
│  │                                                               │   │
│  │  ┌── VCN + Public Subnets (OKE module) ─────────────────────┐  │   │
│  │  └──────────────────────────────────────────────────────────┘  │   │
│  └───────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────┘
```

## Resource Budget (Free Tier)

| Component | CPU | Memory | Storage |
|---|---|---|---|
| OKE Nodes (2x A1.Flex) | 4000m | 24Gi | 100GB (50GB boot each) |
| NGINX Ingress Controller | ~50m | ~128Mi | — |
| cert-manager | ~30m | ~128Mi | — |
| Paperclip + PostgreSQL | ~750m | ~1Gi | 15Gi (5Gi + 10Gi) |
| OpenClaw | ~250m | ~512Mi | 5Gi |
| OpenCode + OpenCode PVC | ~500m | ~1Gi | 5Gi |
| CRI-O fix DaemonSet | ~4m | ~32Mi | — |
| **Used** | **~1.58** | **~2.8Gi** | **~25Gi** |
| **Free Tier Limit** | 4000m | 24Gi | 200Gi |

All components fit comfortably within OCI free tier limits. The OCI Load Balancer (1 free 10Mbps per OKE cluster) is shared by the NGINX Ingress Controller. All images are confirmed ARM64-compatible.

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.14
- [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm) configured with API key credentials (`oci setup config`)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) for cluster management
- [Python 3](https://www.python.org/) (used by `data.external` for cluster discovery)

### OCI Account Setup

1. Configure OCI CLI:
   ```bash
   oci setup config
   ```

2. Get your Tenancy OCID:
   ```bash
   oci iam compartment list --compartment-id-in-subtree true
   ```

3. Identify your home region:
   ```bash
   oci iam region list
   ```

## Quick Start

### 1. Clone and Configure

```bash
git clone https://github.com/lindoelio/oci-oke-cluster-for-agents.git
cd oci-oke-cluster-for-agents
cp src/terraform.tfvars.example src/terraform.tfvars
```

Edit `src/terraform.tfvars` with your values:

```hcl
# Project
project_prefix = "myproject"

# OCI
oci_tenancy_id          = "ocid1.tenancy.oc1..aaaaaaa..."
oci_region              = "sa-saopaulo-1"
oci_home_region         = "sa-saopaulo-1"
oci_compartment_id      = "ocid1.tenancy.oc1..aaaaaaa..."
oci_public_workers      = true

# Node Pool
oci_oke_node_shape               = "VM.Standard.A1.Flex"
oci_oke_node_pool_size           = 2
oci_oke_node_shape_ocpus         = 2
oci_oke_node_shape_memory_in_gbs = 12

# Paperclip (agent orchestration UI)
paperclip_exposure = "public"

# LLM API keys for Paperclip (at least one required)
anthropic_api_key = "sk-ant-..."

# OpenClaw (agent runtime)
openclaw_llm_provider = "openrouter"
openclaw_llm_model    = "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free"
openclaw_llm_api_key  = "your-api-key-here"

# Telegram (optional)
openclaw_telegram_enabled   = true
openclaw_telegram_bot_token = "123456:ABC-DEF..."

# OpenCode Web (AI agent interface)
enable_opencode    = true
opencode_exposure  = "public"
# opencode_custom_domain = "opencode.example.com"
# opencode_path_prefix   = "/opencode"
# opencode_version       = "1.17.11"

# External registry for OpenCode image (GHCR, Docker Hub, etc.)
# opencode_registry_username    = "your-username"
# opencode_registry_token       = "ghp_..."
# opencode_registry_namespace   = "ghcr.io/your-namespace"

# Custom domain with HTTPS (optional)
# paperclip_custom_domain = "paperclip.example.com"
# letsencrypt_email       = "admin@example.com"
```

### 2. Deploy

```bash
cd src
terraform init
terraform apply
```

### 3. Post-Deploy Setup

After apply completes, follow the instructions from `terraform output post_deploy_instructions`:

1. **Configure kubectl** — the output shows the exact command
2. **Get the Paperclip URL** — check `terraform output paperclip_url` or the post-deploy instructions
3. **Open Paperclip** in your browser:
   - Create your admin account
   - Go to Company Settings > Agents > **Generate OpenClaw Invite Prompt**
4. **Connect OpenClaw** — paste the invite prompt into OpenClaw (via Telegram or direct access). Agents will appear in the Paperclip dashboard.
5. **Open OpenCode Web** — get the URL from `terraform output opencode_public_url` and the password from `terraform output -raw opencode_admin_password`:
   - Access the OpenCode Web UI in your browser
   - Log in with username `opencode` and the generated password
   - The password is printed once in the post-deploy instructions; save it to a password manager
6. **(Optional) Set up HTTPS** — if you configured `paperclip_custom_domain` and `letsencrypt_email`, cert-manager automatically provisions a Let's Encrypt certificate

### 4. Verify

```bash
kubectl get nodes
kubectl get pods -A
kubectl get ingress -n paperclip     # Paperclip Ingress with NGINX
kubectl get svc -n ingress-nginx     # LoadBalancer external IP
kubectl get pods -n openclaw         # OpenClaw pod running
kubectl get pods -n opencode         # OpenCode pod running
kubectl get certificate -n paperclip # TLS cert (if custom domain configured)
```

## Configuration Reference

### Core Variables

| Variable | Description | Default |
|---|---|---|
| `project_prefix` | Child compartment name and resource prefix | `"myproject"` |
| `oci_tenancy_id` | OCI Tenancy OCID | — |
| `oci_region` | Primary OCI region | `"sa-saopaulo-1"` |
| `oci_home_region` | OCI home region for tenancy-scoped operations | `"sa-saopaulo-1"` |
| `oci_compartment_id` | Parent compartment OCID | — |
| `oci_project_compartment_id` | Existing project compartment (optional, skip creation) | `""` |
| `oci_public_workers` | Place workers in public subnet with public IPs | `false` |

### Node Pool

| Variable | Description | Default |
|---|---|---|
| `oci_oke_node_shape` | Node shape (ARM free tier) | `"VM.Standard.A1.Flex"` |
| `oci_oke_node_pool_size` | Number of nodes | `2` |
| `oci_oke_node_shape_ocpus` | OCPUs per node | `2` |
| `oci_oke_node_shape_memory_in_gbs` | Memory per node (GB) | `12` |
| `oci_oke_kubernetes_version` | Kubernetes version | `"v1.36.0"` |

### App Toggles

| Variable | Description | Default |
|---|---|---|
| `enable_paperclip` | Deploy Paperclip with managed PostgreSQL | `true` |
| `enable_openclaw` | Deploy OpenClaw operator + instance | `true` |
| `enable_opencode` | Deploy OpenCode Web (built from upstream tarball) | `true` |

### Paperclip

| Variable | Description | Default |
|---|---|---|
| `paperclip_image_repository` | Application image repository | `"ghcr.io/paperclipai/paperclip"` |
| `paperclip_image_tag` | Application image tag | `"latest"` |
| `paperclip_exposure` | `"public"` (NGINX Ingress) or `"private"` (ClusterIP only) | `"public"` |
| `paperclip_public_url` | Explicit public URL (auto-detected from Ingress IP if empty) | `""` |
| `paperclip_custom_domain` | Custom domain for HTTPS + Let's Encrypt (e.g. `paperclip.example.com`) | `""` |
| `letsencrypt_email` | Email for Let's Encrypt ACME account | `""` |
| `nginx_ingress_chart_version` | NGINX Ingress Controller Helm chart version | `"4.12.0"` |
| `paperclip_db_storage_size` | PostgreSQL PVC size | `"10Gi"` |
| `paperclip_storage_size` | Data persistence PVC size | `"5Gi"` |
| `paperclip_cpu_limit` | CPU limit | `"1000m"` |
| `paperclip_memory_limit` | Memory limit | `"2Gi"` |
| `anthropic_api_key` | Anthropic API key (sensitive) | `""` |
| `openai_api_key` | OpenAI API key (sensitive) | `""` |
| `openrouter_api_key` | OpenRouter API key (sensitive) | `""` |
| `ollama_cloud_api_key` | Ollama Cloud API key (sensitive) | `""` |

### OpenClaw

| Variable | Description | Default |
|---|---|---|
| `openclaw_chart_version` | Operator Helm chart version | `"0.34.5"` |
| `openclaw_image_repository` | Application image repository | `"ghcr.io/openclaw/openclaw"` |
| `openclaw_image_tag` | Application image tag | `"latest"` |
| `openclaw_llm_provider` | LLM provider | `"openrouter"` |
| `openclaw_llm_model` | LLM model | `"nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free"` |
| `openclaw_llm_api_key` | LLM API key (sensitive) | `""` |
| `openclaw_storage_size` | Workspace PVC size | `"5Gi"` |
| `openclaw_cpu_limit` | CPU limit | `"500m"` |
| `openclaw_memory_limit` | Memory limit | `"1Gi"` |
| `openclaw_telegram_enabled` | Telegram bot integration | `true` |
| `openclaw_telegram_bot_token` | Telegram bot token (sensitive) | `""` |
| `openclaw_telegram_owner_id` | Telegram numeric user ID for auto-approval | `""` |

### OpenCode Web

| Variable | Description | Default |
|---|---|---|
| `opencode_exposure` | `"public"` (NGINX Ingress) or `"private"` (ClusterIP only) | `"public"` |
| `opencode_custom_domain` | Custom domain for HTTPS + Let's Encrypt | `""` |
| `opencode_path_prefix` | Ingress path prefix (e.g. `/opencode`) | `"/opencode"` |
| `opencode_version` | Upstream version to build from tarball | `"1.17.11"` |
| `opencode_storage_size` | Data persistence PVC size | `"5Gi"` |
| `opencode_cpu_limit` | CPU limit | `"500m"` |
| `opencode_memory_limit` | Memory limit | `"1Gi"` |
| `opencode_registry_username` | External registry username (sensitive) | `""` |
| `opencode_registry_token` | External registry token (sensitive) | `""` |
| `opencode_registry_namespace` | External registry namespace | `""` |

## Project Structure

```
.
├── README.md
├── LICENSE                         # MIT License
├── .gitignore
│
└── src/
    ├── main.tf                     # Providers, compartment, cluster discovery
    ├── oke.tf                      # OKE module + CRI-O fix DaemonSet
    ├── paperclip.tf                # Paperclip Deployment + PostgreSQL StatefulSet
    ├── openclaw.tf                 # OpenClaw operator + OpenClawInstance CRD
    ├── openclaw-ingress.tf         # OpenClaw Ingress resources
    ├── opencode.tf                 # OpenCode Web deployment + Docker build + registry push
    ├── browser.tf                  # Headless Chromium (CDP) browser service for agents
    ├── backup.tf                   # Free-tier backups (Object Storage + daily CronJobs)
    ├── cert-manager.tf             # cert-manager Helm release + Let's Encrypt ClusterIssuer
    ├── ingress.tf                  # NGINX Ingress Controller + shared Ingress resources
    ├── metrics-server.tf           # metrics-server Helm release
    ├── variables.tf                # All variable definitions
    ├── output.tf                   # Terraform outputs + post-deploy instructions
    ├── scripts/
    │   └── opencode.Dockerfile     # OpenCode Web ARM64 image build
    └── terraform.tfvars.example    # Example configuration (copy to terraform.tfvars)
```

## Provider Versions (Pinned)

| Provider | Version |
|---|---|
| `oracle/oci` | 8.9.0 |
| `hashicorp/helm` | 3.1.1 |
| `hashicorp-oss/kubectl` | 0.1.13 |
| `hashicorp/random` | 3.8.1 |
| `hashicorp/time` | 0.13.1 |
| `hashicorp/external` | 2.3.5 |
| `hashicorp/cloudinit` | 2.3.7 |
| `hashicorp/local` | 2.8.0 |
| `hashicorp/null` | 3.2.4 |
| `kreuzwerker/docker` | 4.5.0 |

> **Note**: The `hashicorp/kubernetes` provider is intentionally excluded — it hangs on K8s 1.36.x. All Kubernetes resources use `hashicorp-oss/kubectl` instead.

## Before Going to Production

This project is designed for **development and testing of remote AI agents in a private environment**. The defaults prioritize simplicity and cost-effectiveness over security. If you plan to run anything sensitive, harden it first. Key items:

### Networking & Access

- **Restrict API server access** — The control plane is open to `0.0.0.0/0`. Change `control_plane_allowed_cidrs` in `oke.tf` to your IP or VPN CIDR.
- **Use private worker nodes** — Set `oci_public_workers = false` to place nodes in a private subnet.
- **Private control plane** — Set `control_plane_is_public = false` in `oke.tf` (requires VPN or bastion).

### Secrets & Authentication

- **External secret management** — Move API keys to OCI Vault and inject via External Secrets Operator.
- **etcd encryption** — Enable OCI KMS envelope encryption for Kubernetes secrets at rest.
- **Rotate API keys** — Rotate LLM API keys periodically; never commit them to version control.

### Operational

- **Remote state** — Move Terraform state to OCI Object Storage backend for team collaboration and state locking.
- **Monitoring & alerting** — Add Prometheus/Grafana or OCI Monitoring.
- **Backup strategy** — Back up Paperclip's PostgreSQL data before upgrades.

## Cleanup

```bash
cd src

# Review what will be destroyed
terraform plan -destroy

# Destroy all resources
terraform destroy
```

> **Note**: PersistentVolumeClaims trigger OCI Block Volume deletion automatically. Verify in the OCI Console that all volumes are removed after destroy. The NGINX Ingress LoadBalancer service deletion also removes the OCI Load Balancer.

## Troubleshooting

### Paperclip Pod CrashLoopBackOff (auth.baseUrlMode)

If Paperclip crashes with `authenticated public exposure requires auth.baseUrlMode=explicit`, ensure the `PAPERCLIP_AUTH_BASE_URL_MODE=explicit` and `PAPERCLIP_PUBLIC_URL` environment variables are set in `paperclip.tf`. These are included by default.

### PostgreSQL InitDB Error (lost+found)

If the PostgreSQL pod fails with `directory exists but is not empty. It contains a lost+found directory`, the `PGDATA` env var must point to a subdirectory (`/var/lib/postgresql/data/pgdata`). This is configured by default.

### OpenClaw Pod ImageInspectError (short names)

OKE enforces `short-name-mode = "enforcing"` in CRI-O, which rejects unqualified image names like `nginx:1.27-alpine`. The `crio-shortname-fix` DaemonSet in `oke.tf` configures `docker.io` as the default search registry on all nodes.

### OpenClaw Pod CrashLoopBackOff (Invalid --bind)

If OpenClaw crashes with `Invalid --bind`, the `openclaw.json` config must include `gateway.bind = "lan"`. This is configured in the ConfigMap by default.

### Terraform Init Hangs

If `terraform init` hangs, check for a provider cycle. The root module uses a real Helm provider pointing to the cluster; the OKE module internally uses a Helm provider for its extension submodule. The fix is the `helm.oke` alias provider — do not remove it.

### kubectl Provider Hangs

The `hashicorp/kubernetes` provider hangs indefinitely on K8s 1.36.x. This project uses `hashicorp-oss/kubectl` instead. If you see hangs on provider operations, ensure you are not importing the `kubernetes` provider accidentally.

### kubectl_manifest Plan Drift

The kubectl provider's YAML-to-protobuf round-trip adds Kubernetes-managed fields to the stored state's `manifest` attribute. This is expected and should stabilize after one apply cycle.

### Terraform Apply Fails With "may not specify more than 1 volume type"

This happens when the Terraform state has null fields in volume entries. Run:

```bash
terraform state rm <failed-resource-address>
terraform apply
```

## License

MIT — see [LICENSE](LICENSE) for details.
