# OCI OKE Cluster for Remote AI Agents

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.14-623CE4?logo=terraform)](https://www.terraform.io)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.36-326CE5?logo=kubernetes)](https://kubernetes.io)

One `terraform apply` stands up a **Kubernetes cluster on Oracle Cloud
Infrastructure** for remote AI agents. It deploys **Paperclip** (orchestration
UI), **OpenClaw** (agent runtime), and **OpenCode Web** (coding interface),
with optional **Qwen Code**. Ingress, TLS, backups, and a shared headless
browser are included. Sized for the OCI Always Free ARM tier.

## Features

- **Single `terraform apply`** — cluster, networking, apps, ingress, and TLS
- **OKE** — managed Kubernetes via `oracle-terraform-modules/oke/oci` v5.4.3
- **Always Free fit** — 2× ARM `VM.Standard.A1.Flex` nodes (4 OCPUs, 24 GB RAM)
- **Paperclip** — agent orchestration UI with managed PostgreSQL (no operator)
- **OpenClaw** — agent runtime with optional Telegram, via the official operator
- **OpenCode Web** — ARM64 image from the upstream release, HTTP basic auth, persistent sessions
- **Qwen Code** — optional Web Shell (`enable_qwen`, default off)
- **Shared headless Chromium** — CDP for agent browser automation
- **Free-tier backups** — Object Storage bucket + daily CronJobs
- **NGINX Ingress** — one OCI Load Balancer (10 Mbps Always Free)
- **cert-manager + Let's Encrypt** — HTTPS when you set a custom domain
- **CRI-O short-name fix** — `docker.io` as the default registry on every node
- **Child compartment** — all resources isolated under a Terraform-managed compartment
- **No `hashicorp/kubernetes` provider** — `hashicorp-oss/kubectl` instead (avoids hangs on Kubernetes 1.36)

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                        OCI Tenancy (Always Free)                     │
│  ┌───────────────────────────────────────────────────────────────┐   │
│  │              Child compartment (Terraform-managed)             │   │
│  │                                                               │   │
│  │  ┌── OKE (Kubernetes v1.36, 2× A1.Flex ARM) ───────────────┐ │   │
│  │  │                                                         │ │   │
│  │  │  kube-system/     crio-shortname-fix, metrics-server    │ │   │
│  │  │  ingress-nginx/   NGINX Ingress (OCI LB, 10 Mbps)       │ │   │
│  │  │  cert-manager/    Let's Encrypt ClusterIssuer           │ │   │
│  │  │                                                         │ │   │
│  │  │  paperclip/       Paperclip + PostgreSQL + browser CDP  │ │   │
│  │  │  openclaw-system/ openclaw-operator                     │ │   │
│  │  │  openclaw/        OpenClawInstance runtime              │ │   │
│  │  │  opencode/        OpenCode Web + PVC                    │ │   │
│  │  │  qwen/            Qwen Code Web (optional)              │ │   │
│  │  └─────────────────────────────────────────────────────────┘ │   │
│  │  Object Storage bucket for daily PVC / Postgres backups      │   │
│  └───────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────┘
```

## Resource budget (Always Free)

Limits below match Terraform defaults with Paperclip, OpenClaw, OpenCode, and
the shared browser enabled. Qwen is off by default and is not counted.

| Component | CPU limit | Memory limit | Storage |
|---|---|---|---|
| OKE nodes (2× A1.Flex) | 4000m | 24Gi | 100 GB boot (50 GB each) |
| NGINX Ingress | ~50m | ~128Mi | — |
| cert-manager | ~30m | ~128Mi | — |
| metrics-server | ~50m | ~64Mi | — |
| Paperclip + PostgreSQL | 1000m | 4Gi | 15Gi (5Gi + 10Gi) |
| Paperclip browser (CDP) | ~500m | ~1Gi | — |
| OpenClaw | 500m | 2Gi | 5Gi |
| OpenCode Web | 500m | 8Gi | 5Gi |
| **Always Free cap** | **4000m** | **24Gi** | **200Gi** |

The shared OCI Load Balancer (one free 10 Mbps balancer per OKE cluster)
fronts Ingress. Images used here are ARM64.

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.14
- [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm) (`oci setup config`)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Python 3](https://www.python.org/) (cluster discovery and Ingress IP lookup)
- Docker, if you build the OpenCode or Qwen images locally

### OCI account

```bash
oci setup config
oci iam compartment list --compartment-id-in-subtree true   # tenancy OCID
oci iam region list                                         # home region
```

## Quick start

### 1. Clone and configure

```bash
git clone https://github.com/lindoelio/oci-oke-cluster-for-agents.git
cd oci-oke-cluster-for-agents
cp src/terraform.tfvars.example src/terraform.tfvars
```

Edit `src/terraform.tfvars`:

```hcl
project_prefix = "myproject"

oci_tenancy_id     = "ocid1.tenancy.oc1..aaaaaaa..."
oci_region         = "sa-saopaulo-1"
oci_home_region    = "sa-saopaulo-1"
oci_compartment_id = "ocid1.tenancy.oc1..aaaaaaa..."
oci_public_workers = true

oci_oke_node_shape               = "VM.Standard.A1.Flex"
oci_oke_node_pool_size           = 2
oci_oke_node_shape_ocpus         = 2
oci_oke_node_shape_memory_in_gbs = 12

paperclip_exposure = "public"
# At least one LLM key for Paperclip agents
anthropic_api_key  = "sk-ant-..."

openclaw_llm_provider = "openrouter"
openclaw_llm_model    = "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free"
openclaw_llm_api_key  = "your-api-key-here"

enable_opencode   = true
opencode_exposure = "public"
# Registry that will hold the locally built OpenCode image
# opencode_registry_username  = "your-username"
# opencode_registry_token     = "ghp_..."
# opencode_registry_namespace = "your-namespace"

# paperclip_custom_domain = "paperclip.example.com"
# letsencrypt_email       = "admin@example.com"
```

Never commit `src/terraform.tfvars`.

### 2. Deploy

```bash
cd src
terraform init
terraform apply
```

### 3. After apply

Follow `terraform output post_deploy_instructions`. In short:

1. Configure kubectl with the printed `oci ce cluster create-kubeconfig` command.
2. Wait until the Paperclip pod is Ready, then bootstrap the first admin:

   ```bash
   kubectl exec -n paperclip deployment/paperclip -- pnpm paperclipai auth bootstrap-ceo
   ```

   Open the printed invite URL and create the admin account.
3. In Paperclip, generate an OpenClaw invite and paste it into OpenClaw
   (Telegram or direct access).
4. OpenCode Web: `terraform output opencode_public_url` and
   `terraform output -raw opencode_admin_password`. Log in as `opencode`.
5. Optional HTTPS: set `paperclip_custom_domain` / `opencode_custom_domain`
   plus `letsencrypt_email`, point DNS at the Ingress IP, then apply again.

### 4. Verify

```bash
kubectl get nodes
kubectl get pods -A
kubectl get ingress -A
kubectl get svc -n ingress-nginx
kubectl get certificate -A
```

## Configuration reference

Defaults match `src/variables.tf`.

### Core

| Variable | Description | Default |
|---|---|---|
| `project_prefix` | Child compartment name and resource prefix | `"myproject"` |
| `oci_tenancy_id` | Tenancy OCID | — |
| `oci_region` | Primary region | `"sa-saopaulo-1"` |
| `oci_home_region` | Home region for tenancy-scoped APIs | `"sa-saopaulo-1"` |
| `oci_compartment_id` | Parent compartment OCID | — |
| `oci_project_compartment_id` | Existing project compartment (skip create) | `""` |
| `oci_public_workers` | Public subnet + public node IPs | `false` |

### Node pool

| Variable | Description | Default |
|---|---|---|
| `oci_oke_node_shape` | Node shape | `"VM.Standard.A1.Flex"` |
| `oci_oke_node_pool_size` | Node count | `2` |
| `oci_oke_node_shape_ocpus` | OCPUs per node | `2` |
| `oci_oke_node_shape_memory_in_gbs` | Memory per node (GB) | `12` |
| `oci_oke_kubernetes_version` | Kubernetes version | `"v1.36.0"` |

### Toggles

| Variable | Description | Default |
|---|---|---|
| `enable_paperclip` | Paperclip + PostgreSQL | `true` |
| `enable_paperclip_qmd` | qmd search on the Paperclip PVC | `true` |
| `enable_paperclip_browser` | Headless Chromium CDP | `true` |
| `enable_metrics_server` | metrics-server | `true` |
| `enable_openclaw` | OpenClaw operator + instance | `true` |
| `enable_opencode` | OpenCode Web | `true` |
| `enable_opencode_browser` | CDP sidecar on OpenCode | `true` |
| `enable_qwen` | Qwen Code Web | `false` |
| `enable_qwen_browser` | CDP sidecar on Qwen (if enabled) | `true` |

### Paperclip

| Variable | Description | Default |
|---|---|---|
| `paperclip_image_repository` | Image repository | `"ghcr.io/paperclipai/paperclip"` |
| `paperclip_image_tag` | Image tag | `"latest"` |
| `paperclip_exposure` | `"public"` (Ingress) or `"private"` | `"public"` |
| `paperclip_custom_domain` | HTTPS + Let's Encrypt | `""` |
| `letsencrypt_email` | ACME account email | `""` |
| `nginx_ingress_chart_version` | Ingress chart | `"4.12.0"` |
| `paperclip_db_storage_size` | PostgreSQL PVC | `"10Gi"` |
| `paperclip_storage_size` | Data PVC | `"5Gi"` |
| `paperclip_cpu_limit` | CPU limit | `"1000m"` |
| `paperclip_memory_limit` | Memory limit | `"4Gi"` |
| `paperclip_qmd_version` | `@tobilu/qmd` on the PVC | `"2.5.3"` |
| `paperclip_browser_version` | Playwright Chromium image tag | `"1.62.1"` |
| `anthropic_api_key` / `openai_api_key` / `openrouter_api_key` / `ollama_cloud_api_key` | LLM keys | `""` |

### OpenClaw

| Variable | Description | Default |
|---|---|---|
| `openclaw_chart_version` | Operator Helm chart | `"0.36.5"` |
| `openclaw_image_repository` | Runtime image | `"ghcr.io/openclaw/openclaw"` |
| `openclaw_llm_provider` | LLM provider | `"openrouter"` |
| `openclaw_llm_model` | LLM model | `"nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free"` |
| `openclaw_storage_size` | Workspace PVC | `"5Gi"` |
| `openclaw_cpu_limit` | CPU limit | `"500m"` |
| `openclaw_memory_limit` | Memory limit | `"2Gi"` |
| `openclaw_telegram_enabled` | Telegram bot | `true` |

### OpenCode Web

| Variable | Description | Default |
|---|---|---|
| `opencode_exposure` | `"public"` or `"private"` | `"public"` |
| `opencode_version` | Upstream release tag | `"1.17.13"` |
| `opencode_path_prefix` | Ingress path | `"/opencode"` |
| `opencode_storage_size` | Data PVC | `"5Gi"` |
| `opencode_cpu_limit` | CPU limit | `"500m"` |
| `opencode_memory_limit` | Memory limit | `"8Gi"` |
| `opencode_registry` | `"ghcr"` or `"dockerhub"` | `"ghcr"` |

Optional keys (`github_token`, `gitlab_token`, `neon_api_key`, `expo_token`,
`paddle_sandbox_api_key`, and similar) are injected into agent environments
when set. They are not required to bring the cluster up.

### Qwen Code (optional)

Set `enable_qwen = true` and, before apply, generate Ingress basic auth:

```bash
cd src
sh scripts/gen_qwen_htpasswd.sh 'your-password'
```

That writes gitignored `src/.tmp/qwen_htpasswd`. Default image tag is `0.22.2`.

## Project layout

```
.
├── README.md
├── LICENSE
├── CONTRIBUTING.md
├── SECURITY.md
├── AGENTS.md
└── src/
    ├── main.tf                      # Providers, compartment, cluster lookup
    ├── oke.tf                       # OKE module + CRI-O fix
    ├── paperclip.tf
    ├── openclaw.tf
    ├── openclaw-ingress.tf
    ├── opencode.tf
    ├── qwen.tf                      # Optional Qwen Code
    ├── browser.tf                   # Shared headless Chromium
    ├── backup.tf                    # Object Storage + CronJobs
    ├── cert-manager.tf
    ├── ingress.tf
    ├── metrics-server.tf
    ├── variables.tf
    ├── output.tf
    ├── terraform.tfvars.example
    └── scripts/
        ├── opencode.Dockerfile
        ├── qwen.Dockerfile
        ├── qwen-settings.json
        ├── detect_ingress_ip.py
        ├── cdp_proxy.js
        ├── paperclip_onboard.sh
        ├── company_auth_writer.js
        ├── opencode_go_auth.py
        └── gen_qwen_htpasswd.sh
```

## Provider versions (pinned)

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

The `hashicorp/kubernetes` provider is excluded on purpose: it hangs on
Kubernetes 1.36. All Kubernetes objects use `hashicorp-oss/kubectl`.

## Before production

Defaults optimize for a personal lab, not a locked-down production cluster.
See [SECURITY.md](SECURITY.md). At minimum:

- Restrict `control_plane_allowed_cidrs` in `oke.tf`
- Prefer `oci_public_workers = false`
- Move API keys to a vault
- Use a remote Terraform state backend
- Set custom domains and Let's Encrypt before putting real data on Ingress

## Cleanup

```bash
cd src
terraform plan -destroy
terraform destroy
```

PersistentVolumeClaims delete the backing OCI Block Volumes. Confirm in the
console that volumes and the Ingress Load Balancer are gone.

## Troubleshooting

**Paperclip CrashLoopBackOff (`auth.baseUrlMode`)** — public exposure needs
`PAPERCLIP_AUTH_BASE_URL_MODE=explicit` and `PAPERCLIP_PUBLIC_URL`. Both are
set by default in `paperclip.tf`.

**PostgreSQL InitDB (`lost+found`)** — `PGDATA` must be a subdirectory
(`/var/lib/postgresql/data/pgdata`). That is the default.

**OpenClaw ImageInspectError** — CRI-O short-name mode rejects `nginx:…`.
The `crio-shortname-fix` DaemonSet in `oke.tf` sets `docker.io` as the
default registry.

**OpenClaw `Invalid --bind`** — `gateway.bind = "lan"` in the ConfigMap
(configured by default).

**`terraform init` hangs** — keep the `helm.oke` alias provider; it breaks
a provider cycle with the OKE module.

**kubectl provider hangs** — do not add `hashicorp/kubernetes`.

**`may not specify more than 1 volume type`** — stale null volume fields in
state. `terraform state rm <address>` then `terraform apply`.

## License

MIT — see [LICENSE](LICENSE).
