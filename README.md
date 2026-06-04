# OKE Cluster With Paperclip + OpenClaw

A Terraform project for deploying an Oracle Kubernetes Engine (OKE) cluster on OCI Free Tier, with **Paperclip** (AI agent orchestration platform) and **OpenClaw** (AI agent runtime).

## Features

- **OKE Cluster** — OCI-managed Kubernetes via `oracle-terraform-modules/oke/oci` v5.4.3
- **Free Tier** — 2x ARM-based `VM.Standard.A1.Flex` nodes (4 OCPUs, 24GB RAM total)
- **Kubernetes v1.36.0** — Flannel CNI, public control plane, public workers
- **Paperclip** — Agent orchestration UI with managed PostgreSQL (direct deployment, no operator required)
- **OpenClaw** — Agent runtime with Telegram integration, deployed via official operator (`openclaw-operator` v0.34.5)
- **CRI-O Short-Name Fix** — DaemonSet that configures `docker.io` as default registry on all nodes
- **OCI Child Compartment** — All project resources isolated in a Terraform-managed child compartment
- **No `hashicorp/kubernetes` provider** — Uses `hashicorp-oss/kubectl` to avoid known hangs on K8s 1.36.x

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                          OCI Tenancy (Free Tier)                      │
│  ┌───────────────────────────────────────────────────────────────┐   │
│  │                Child Compartment (tf-managed)                   │   │
│  │                                                                │   │
│  │  ┌── OKE Cluster (K8s v1.36.0, 2x A1.Flex, ARM) ──────────┐  │   │
│  │  │  kube-system/                                            │  │   │
│  │  │    └─ crio-shortname-fix (DaemonSet)                     │  │   │
│  │  │                                                          │  │   │
│  │  │  paperclip/                                              │  │   │
│  │  │    ├─ Paperclip App Deployment (:3100)                   │  │   │
│  │  │    ├─ PostgreSQL StatefulSet (17-alpine)                 │  │   │
│  │  │    └─ Service: LoadBalancer (OCI free LB)                │  │   │
│  │  │                                                          │  │   │
│  │  │  openclaw-system/                                        │  │   │
│  │  │    └─ openclaw-operator (Helm, v0.34.5)                  │  │   │
│  │  │                                                          │  │   │
│  │  │  openclaw/                                               │  │   │
│  │  │    ├─ OpenClawInstance CRD → OpenClaw Runtime            │  │   │
│  │  │    └─ Service: ClusterIP (:18789)                        │  │   │
│  │  └──────────────────────────────────────────────────────────┘  │   │
│  │                                                                │   │
│  │  ┌── VCN + Public Subnets (OKE module) ─────────────────────┐  │   │
│  │  └──────────────────────────────────────────────────────────┘  │   │
│  └───────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────┘
```

## Resource Budget (Free Tier)

| Component | CPU | Memory | Storage |
|---|---|---|---|
| OKE Nodes (2x A1.Flex) | 4000m | 24Gi | 50GB boot each |
| Paperclip + PostgreSQL | ~750m | ~1Gi | 15Gi (5Gi + 10Gi) |
| OpenClaw | ~250m | ~512Mi | 5Gi |
| CRI-O fix DaemonSet | ~4m | ~32Mi | — |
| **Used** | **~1Gi** | **~1.5Gi** | **~20Gi** |
| **Free Tier Limit** | 4000m | 24Gi | 200Gi |

All components fit comfortably within OCI free tier limits. The OCI Load Balancer (1 free per OKE cluster) is used for Paperclip external access. Both Paperclip (`ghcr.io/paperclipai/paperclip`) and OpenClaw (`ghcr.io/openclaw/openclaw`) images are confirmed ARM64-compatible.

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
git clone <repo-url> && cd oci-oke-cluster
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

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

# LLM API keys for Paperclip
anthropic_api_key = "sk-ant-..."

# OpenClaw (agent runtime)
openclaw_llm_provider = "openrouter"
openclaw_llm_model    = "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free"
openclaw_llm_api_key  = "your-api-key-here"

# Telegram (optional)
openclaw_telegram_enabled   = true
openclaw_telegram_bot_token = "123456:ABC-DEF..."
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
2. **Get Paperclip URL** — use the `kubectl get svc` command to find the LoadBalancer IP
3. **Open Paperclip** at `http://<IP>:3100` in your browser:
   - Create your admin account
   - Go to Company Settings > Agents > **Generate OpenClaw Invite Prompt**
4. **Connect OpenClaw** — paste the invite prompt into OpenClaw (via Telegram or direct access). Agents will appear in the Paperclip dashboard.

### 4. Verify

```bash
kubectl get nodes
kubectl get pods -A
kubectl get svc -n paperclip    # Should show LoadBalancer with external IP
kubectl get pods -n openclaw    # Should show OpenClaw pod running
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

### Paperclip

| Variable | Description | Default |
|---|---|---|
| `paperclip_image_repository` | Application image repository | `"ghcr.io/paperclipai/paperclip"` |
| `paperclip_image_tag` | Application image tag | `"latest"` |
| `paperclip_exposure` | `"public"` (LoadBalancer) or `"private"` (ClusterIP) | `"public"` |
| `paperclip_db_storage_size` | PostgreSQL PVC size | `"10Gi"` |
| `paperclip_storage_size` | Data persistence PVC size | `"5Gi"` |
| `paperclip_cpu_limit` | CPU limit | `"1000m"` |
| `paperclip_memory_limit` | Memory limit | `"2Gi"` |
| `anthropic_api_key` | Anthropic API key (sensitive) | `""` |
| `openai_api_key` | OpenAI API key (sensitive) | `""` |

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

## Project Structure

```
.
├── README.md                   # This file — quick start and reference
├── AGENTS.md                   # AI agent guidelines
├── ARCHITECTURE.md             # System architecture and component layout
├── CONTRIBUTING.md             # Contribution workflow
├── SECURITY.md                 # Security model and hardening checklist
├── STYLEGUIDE.md              # Terraform formatting and naming rules
├── TESTING.md                  # Validation and testing strategy
├── LICENSE                     # MIT License
├── .gitignore                  # Git ignore rules
├── .terraform.lock.hcl         # Provider version lock file
├── terraform.tfvars.example    # Example configuration (copy to src/terraform.tfvars)
│
└── src/                        ← All Terraform source files
    ├── main.tf                 # Providers, compartment, cluster discovery
    ├── oke.tf                  # OKE module + CRI-O fix DaemonSet
    ├── paperclip.tf            # Paperclip Deployment + PostgreSQL StatefulSet
    ├── openclaw.tf             # OpenClaw operator + OpenClawInstance CRD
    ├── variables.tf            # All variable definitions
    └── output.tf               # Terraform outputs + post-deploy instructions
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

> **Note**: The `hashicorp/kubernetes` provider is intentionally excluded — it hangs on K8s 1.36.x. All Kubernetes resources use `hashicorp-oss/kubectl` instead.

## Before Going to Production

This project is designed for **development, learning, and experimentation**. The defaults prioritize simplicity and cost-effectiveness over security. Before exposing this cluster to real workloads or users, consider the following hardening steps:

### Networking & Access

- **Restrict API server access** — The control plane is open to `0.0.0.0/0` by default for ease of use. Change `control_plane_allowed_cidrs` in `oke.tf` to your IP or VPN CIDR.
- **Use private worker nodes** — Set `oci_public_workers = false` to place nodes in a private subnet with NAT/Service Gateway. Workers currently have public IPs.
- **Private control plane** — Set `control_plane_is_public = false` in `oke.tf` (requires VPN or bastion access to the API endpoint).
- **Restrict Paperclip exposure** — Set `paperclip_exposure = "private"` and put a reverse proxy or ingress controller with TLS in front of it.

### Secrets & Authentication

- **Rotate the auth secret** — The `random_password.paperclip_auth` resource regenerates on state loss. For production, manage this secret externally (e.g., OCI Vault) and inject it via `kubectl_manifest`.
- **Rotate API keys** — Change LLM API keys (`anthropic_api_key`, `openai_api_key`, `openclaw_llm_api_key`) periodically and never commit them to version control.
- **Use Kubernetes Secrets encryption** — Enable OCI KMS envelope encryption for etcd secrets at rest.

### Operational

- **Pin provider versions** — Provider versions are pinned in `main.tf`. Review and update them deliberately.
- **Remote state** — Move Terraform state to OCI Object Storage backend for team collaboration and state locking.
- **Monitoring & alerting** — Add Prometheus/Grafana or OCI Monitoring for cluster health, node utilization, and pod status.
- **Backup strategy** — Back up Paperclip's managed PostgreSQL data and any persistent volumes before major upgrades.
- **Resource limits** — Review and tune CPU/memory requests and limits based on actual workload profiles.

## Cleanup

```bash
cd src

# Review what will be destroyed
terraform plan -destroy

# Destroy all resources
terraform destroy
```

> **Note**: PersistentVolumeClaims trigger OCI Block Volume deletion automatically. Verify in the OCI Console that all volumes are removed after destroy. The LoadBalancer service deletion also removes the OCI Load Balancer.

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
