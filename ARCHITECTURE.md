# ARCHITECTURE.md — System Architecture

<!-- BEGIN managed:architecture-overview -->
## Overview

This project provisions an OCI Free Tier Kubernetes cluster (OKE) with two AI agent workloads — Paperclip (direct deployment) and OpenClaw (via operator). All infrastructure is managed by Terraform and contained within a child OCI compartment.

**Design priorities:** Simplicity, cost-effectiveness (Free Tier), and single-command deployment.
<!-- END managed:architecture-overview -->

<!-- BEGIN managed:architecture-high-level -->
## High-Level Architecture

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
│  │  │    └─ NGINX Ingress Controller (Helm, OCI LB)          │  │   │
│  │  │                                                        │  │   │
│  │  │  cert-manager/                                         │  │   │
│  │  │    └─ cert-manager (Helm) + Let's Encrypt Issuer       │  │   │
│  │  │                                                        │  │   │
│  │  │  paperclip/                 openclaw-system/           │  │   │
│  │  │    ├─ Paperclip Deployment    └─ openclaw-operator     │  │   │
│  │  │    ├─ PostgreSQL StatefulSet     (Helm, v0.34.5)       │  │   │
│  │  │    ├─ Ingress (NGINX, :80)                             │  │   │
│  │  │    └─ TLS (cert-manager)                               │  │   │
│  │  │                             openclaw/                  │  │   │
│  │  │                               ├─ OpenClawInstance CRD  │  │   │
│  │  │                               └─ ClusterIP (:18789)    │  │   │
│  │  └────────────────────────────────────────────────────────┘  │   │
│  │                                                               │   │
│  │  ┌── VCN (public subnets, internet gateway) ──────────────┐  │   │
│  │  └────────────────────────────────────────────────────────┘  │   │
│  └───────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────┘
```
<!-- END managed:architecture-high-level -->

<!-- BEGIN managed:architecture-components -->
## Components

### OCI Infrastructure (via OKE module v5.4.3)

| Component | Details |
|---|---|
| **Compartment** | Child compartment created by Terraform, or pre-existing (via `oci_project_compartment_id`) |
| **VCN** | Module-managed with public subnets, internet gateway |
| **NAT Gateway** | Created only when `oci_public_workers = false` |
| **OKE Cluster** | Basic type, Flannel CNI, public control plane |
| **Node Pool** | ARM-based `VM.Standard.A1.Flex`, configurable size/OCPUs/memory |
| **Load Balancer** | OCI free-tier 10Mbps LB via NGINX Ingress Controller Service |
| **CRI-O Fix** | DaemonSet configuring `docker.io` as default registry on all nodes |

### Kubernetes Infrastructure

#### NGINX Ingress Controller
- **Helm chart:** `ingress-nginx` (v4.12.0) from `https://kubernetes.github.io/ingress-nginx`
- **Namespace:** `ingress-nginx`
- **Exposure:** LoadBalancer (OCI free 10Mbps shape) — single entry point for all HTTP/HTTPS traffic
- **Purpose:** Unified ingress point replacing per-app LoadBalancers

#### cert-manager + Let's Encrypt
- **Helm chart:** `cert-manager` (v1.16.2) from `https://charts.jetstack.io`
- **Namespace:** `cert-manager`
- **Issuer:** `ClusterIssuer` with Let's Encrypt production ACME, HTTP-01 challenge via NGINX Ingress
- **Conditional:** Created only when `letsencrypt_email` is set and a `paperclip_custom_domain` is configured
- **Purpose:** Automatic TLS certificate issuance for custom domains

### Kubernetes Workloads

#### Paperclip (Agent Orchestration)
- **Deployment:** Direct Kubernetes Deployment (no operator — the Paperclip operator Helm chart is not published on GHCR)
- **Image:** `ghcr.io/paperclipai/paperclip` (ARM64 confirmed)
- **Database:** PostgreSQL 17-alpine StatefulSet with `oci-bv` storage class, `PGDATA` subdirectory for OCI Block Volumes
- **Exposure:** ClusterIP service behind NGINX Ingress Controller, with optional cert-manager TLS for custom domains
- **Auth:** Auto-generated `BETTER_AUTH_SECRET` via `random_password`, `PAPERCLIP_AUTH_BASE_URL_MODE=explicit`
- **API Keys:** Injected from `paperclip-api-keys` secret (Anthropic, OpenAI, OpenRouter, Ollama)

#### OpenClaw (Agent Runtime)
- **Operator:** Deployed via Helm from `oci://ghcr.io/paperclipinc/charts/openclaw-operator` (v0.34.5)
- **Image:** `ghcr.io/openclaw/openclaw` (ARM64 confirmed)
- **Instance CRD:** `OpenClawInstance` (`openclaw.rocks/v1alpha1`)
- **Config:** ConfigMap with `openclaw.json` (`gateway.bind = "lan"`)
- **LLM Provider:** Configurable (default: OpenRouter)
- **Storage:** PVC with `oci-bv` storage class
- **Integration:** Optional Telegram bot via secret injection
- **Gateway/Observability sidecars:** Disabled to avoid CRI-O short-name issues
<!-- END managed:architecture-components -->

<!-- BEGIN managed:architecture-deployment-flow -->
## Deployment Flow

A single `terraform apply` handles the entire deployment. The compartment is created conditionally (if `oci_project_compartment_id` is empty) with a 30s propagation delay.

```
terraform apply
```

Execution order:

```
OKE Module (VCN + Cluster + Nodes)
  → data.external.oke_cluster (Python: cluster discovery)
  → time_sleep.after_cluster (60s)
  → data.oci_containerengine_cluster_kube_config
  → data.external.oke_token (Python: token generation)
  → Provider configuration (kubectl, helm)
    → kubectl_manifest.crio_shortname_fix (DaemonSet)
    → helm_release.nginx_ingress ──┐
    → helm_release.cert_manager ───┤
                                   ↓
                          time_sleep.wait_for_ingress_lb (120s)
                                   ↓
                          data.external.ingress_ip (Python: IP detection)
                                   ↓
    → kubectl_manifest.paperclip_* ──────┐
    → helm_release.openclaw_operator ────┤
                                          ↓
                                 time_sleep (30s)
                                          ↓
                                 kubectl_manifest.openclaw_* (namespace, secrets, CRD)
```
<!-- END managed:architecture-deployment-flow -->

<!-- BEGIN managed:architecture-providers -->
## Provider Architecture

| Provider | Version | Purpose |
|---|---|---|
| `oracle/oci` | 8.9.0 | OCI resource management (compartment, cluster lookup) |
| `oracle/oci` (alias: `home`) | 8.9.0 | Tenancy-scoped operations (home region) |
| `hashicorp/helm` | 3.1.1 | Operator Helm chart deployments |
| `hashicorp/helm` (alias: `oke`) | 3.1.1 | OKE module internal provider alias (prevents provider cycle) |
| `hashicorp-oss/kubectl` | 0.1.13 | Kubernetes manifest management (namespaces, secrets, CRDs) |
| `hashicorp/external` | 2.3.5 | Cluster discovery and token generation via Python |
| `hashicorp/time` | 0.13.1 | Readiness delays between dependent resources |
| `hashicorp/random` | 3.8.1 | Auth secret generation |
| `hashicorp/cloudinit` | 2.3.7 | Required by OKE module |
| `hashicorp/local` | 2.8.0 | Required by OKE module |
| `hashicorp/null` | 3.2.4 | Required by OKE module |

### Critical Design Decisions

1. **No `hashicorp/kubernetes` provider** — It hangs on K8s 1.36.x. All K8s resources use `hashicorp-oss/kubectl`.
2. **Dual Helm providers** — `helm.oke` alias prevents a provider cycle between the root module and the OKE module's extension submodule.
3. **Python external data sources** — OCI CLI wrappers for cluster ID discovery and token generation, avoiding the `kubernetes` provider dependency.
<!-- END managed:architecture-providers -->

<!-- BEGIN managed:architecture-data-flow -->
## Data Flow

### Cluster Discovery
```
module.oke (creates cluster)
  → data.external.oke_cluster (Python script calls `oci ce cluster list`)
  → returns cluster_id
  → data.oci_containerengine_cluster_kube_config (fetches kubeconfig YAML)
  → data.external.oke_token (Python script calls `oci ce cluster generate-token`)
  → locals: cluster_endpoint, cluster_ca_cert, cluster_token
  → configures kubectl and helm providers
```

### Secret Injection
```
Terraform variables (sensitive)
  → kubectl_manifest.*_secret (creates K8s Secret with stringData)
  → CRD spec references secret by name + key
  → Operator mounts secret into pod
```
<!-- END managed:architecture-data-flow -->

<!-- BEGIN managed:architecture-resource-budget -->
## Free Tier Resource Budget

| Component | CPU | Memory | Storage |
|---|---|---|---|
| OKE Nodes (2x A1.Flex) | 4000m | 24Gi | 100GB (50GB boot each) |
| NGINX Ingress Controller | ~50m | ~128Mi | — |
| cert-manager | ~30m | ~128Mi | — |
| Paperclip + PostgreSQL | ~750m | ~1Gi | 15Gi |
| OpenClaw | ~250m | ~512Mi | 5Gi |
| CRI-O fix DaemonSet | ~4m | ~32Mi | — |
| **Total Used** | **~1.1Gi** | **~1.8Gi** | **~20Gi** |
| **Free Tier Limit** | **4000m** | **24Gi** | **200Gi** |
<!-- END managed:architecture-resource-budget -->

<!-- BEGIN managed:architecture-related-docs -->
## Related Documentation

- [AGENTS.md](AGENTS.md) — AI agent context and safety rules
- [SECURITY.md](SECURITY.md) — Security model and hardening checklist
- [CONTRIBUTING.md](CONTRIBUTING.md) — How to add new workloads
- [README.md](README.md) — Quick start and troubleshooting
<!-- END managed:architecture-related-docs -->
