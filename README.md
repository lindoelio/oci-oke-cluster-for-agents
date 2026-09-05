# OCI OKE Cluster for Remote AI Agents

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.14-623CE4?logo=terraform)](https://www.terraform.io)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.36-326CE5?logo=kubernetes)](https://kubernetes.io)

Terraform provisions a **Kubernetes cluster on Oracle Cloud Infrastructure**
for remote AI agents after account, image-registry, and access preparation.
It deploys **Paperclip** (orchestration UI) and **Qwen Code Web** (coding
interface). **OpenClaw** and **OpenCode Web** remain available as optional,
disabled workloads. It
configures ingress, conditional TLS, selected backup jobs, and a shared
headless browser. Defaults target an ARM lab with 4 OCPUs and 24 GB RAM;
**the complete stack is not guaranteed to be free**.
See [cost boundaries](#cost-boundaries) and the
[technical evidence review](docs/launch-readiness.md).

## Features

- **Terraform provisioning** — cluster, networking, apps, ingress, and optional TLS; image publication and onboarding are separate steps
- **OKE** — managed Kubernetes via `oracle-terraform-modules/oke/oci` v5.4.3
- **Configurable ARM workers** — 2× `VM.Standard.A1.Flex` by default (4 OCPUs, 24 GB RAM total)
- **Paperclip** — agent orchestration UI with a self-managed PostgreSQL StatefulSet
- **Qwen Code Web** — ARM64 Web Shell with Basic/Bearer authentication and persistent, per-repository workspaces
- **OpenClaw** — optional agent runtime with Telegram support, disabled by default
- **OpenCode Web** — optional coding interface, disabled by default
- **Shared headless Chromium** — CDP for agent browser automation
- **Backup jobs** — daily PostgreSQL dump and file archives for Paperclip/OpenCode; no automatic retention or tested restore guarantee
- **OCI Native Ingress** — Oracle's standalone controller for Basic OKE, instance-principal IAM, and one flexible OCI Load Balancer fixed at 10 Mbps
- **cert-manager + Let's Encrypt** — upstream Helm release and optional ACME certificates after configuring domains, email, DNS, and successful issuance
- **CRI-O short-name fix** — `docker.io` as the default registry on every node
- **Child compartment** — all resources isolated under a Terraform-managed compartment
- **Kubernetes manifests** — `hashicorp-oss/kubectl`; this repository does not configure `hashicorp/kubernetes`

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                         OCI Tenancy (check quotas)                    │
│  ┌───────────────────────────────────────────────────────────────┐   │
│  │              Child compartment (Terraform-managed)             │   │
│  │                                                               │   │
│  │  ┌── OKE (Kubernetes v1.36, 2× A1.Flex ARM) ───────────────┐ │   │
│  │  │                                                         │ │   │
│  │  │  kube-system/     crio-shortname-fix, metrics-server    │ │   │
│  │  │  controllers/     OCI Native Ingress + cert-manager     │ │   │
│  │  │  oci-native-*     IngressClass (OCI LB, 10 Mbps)        │ │   │
│  │  │                                                         │ │   │
│  │  │  paperclip/       Paperclip + PostgreSQL + browser CDP  │ │   │
│  │  │  qwen/            Qwen Code Web + PVC                   │ │   │
│  │  │  optional/        OpenClaw and OpenCode Web             │ │   │
│  │  └─────────────────────────────────────────────────────────┘ │   │
│  │  Object Storage bucket for daily PVC / Postgres backups      │   │
│  └───────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────┘
```

## Resource budget

The following are **configured main-container limits**, not measured usage or
an aggregate scheduling budget. CPU and memory requests differ from limits.
Leave room for the OS, Kubernetes, operators, sidecars, init containers, and
backup jobs; workloads can reach limits at different times.

| Main container | CPU limit | Memory limit | Persistent volume requests |
|---|---|---|---|
| Paperclip | 1500m | 6Gi | 50Gi |
| PostgreSQL | 750m | 2Gi | 50Gi |
| Shared Chromium | 1000m | 2Gi | — |
| Qwen daemon | 1500m | 6Gi | 50Gi |
| OpenClaw runtime (off by default) | 500m | 2Gi | 50Gi |
| OpenCode Web (off by default) | 500m | 8Gi | 50Gi |
| OCI Native Ingress controller | 300m | 256Mi | — |
| metrics-server | Not set | 256Mi | — |

The ingress and certificate controllers also consume worker capacity.
Paperclip and Qwen receive identical main-container requests (500m/1Gi) and
limits (1500m/6Gi). PostgreSQL and the browser are supporting services; the
browser is shared by both applications and is not charged to either half.
Paperclip has an auth-writer
sidecar; browser forwarding adds sidecars. The OpenClaw operator can add
containers with its own defaults. This table does not imply everything fits
at maximum utilization. Use `kubectl top` on an authorized deployment to
measure idle and active usage before resizing the node pool.

## Cost boundaries

Pricing sources checked on September 4, 2026. **Free compute does not mean a
free complete deployment.** Confirm the allowance applicable to your account,
region, other workloads, and billing agreement before provisioning.

| Component | What to budget |
|---|---|
| OKE control plane | OKE Basic has no cluster management charge; workers and supporting services are separate. |
| A1 workers | Defaults allocate 4 OCPUs and 24 GB total. The general Always Free page lists 1,500 OCPU-hours / 9,000 GB-hours monthly; the price list explicitly lists 3,000 / 18,000 for paid tenancies. Verify which applies. |
| Boot and data volumes | With the default two-node pool, two 50 GB boot volumes plus the three enabled Paperclip/Qwen data volumes total **at least 250 GB**, exceeding the 200 GB shared boot/block allowance. Optional workloads add volumes. A one-node 50 GB boot volume plus those three data volumes totals 200 GB. Inspect actual provisioned sizes and performance charges. |
| Ingress controllers | The standalone OCI Native Ingress Controller and cert-manager pods consume worker capacity. The resources they manage can be billable. OKE add-on management requires an Enhanced cluster and is not used by this Basic-cluster configuration. |
| Load balancer | One flexible LB, min/max 10 Mbps. Always Free includes one eligible 10 Mbps flexible LB shared by the tenancy. A migration that temporarily keeps the old and new LBs can exceed that allowance. |
| Certificates | Let's Encrypt itself is free. OCI Native Ingress imports Kubernetes TLS secrets into OCI Certificates; the Always Free allowance lists 150 certificates and 5 CAs, shared by the tenancy. |
| Network | Worker placement controls NAT creation; account for the selected network services and outbound data rather than assuming all traffic is free. |
| Backups | Object Storage bucket and API requests; dated objects accumulate without a retention policy. Quotas differ by account status and storage tier. |
| Models and tooling | Provider APIs/subscriptions, registry storage, and optional external services have separate costs. No GPU/model-serving cluster is provisioned. |

The OCI Block Volume documentation specifies a 50 GB minimum per PVC. Small
5-10Gi requests must not be used as a cloud storage cost estimate. New defaults
request 50Gi per PVC. For existing volumes and PostgreSQL claim templates,
read the [migration notes](docs/launch-readiness.md#existing-deployment-migration)
before planning any change; do not recreate data volumes just to align defaults.

Oracle's general Always Free page, Arm guide, and price list currently differ
in how they describe A1 allowances. The paid-tenancy price-list note supports
4 OCPUs / 24 GB within its monthly allowance, but does not establish a free
bill for this stack or every account. Capacity shortages and idle-resource
reclamation also limit Always Free suitability for persistent services.

Sources: [OKE and compute pricing](https://www.oracle.com/cloud/price-list/),
[Always Free resources](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm),
[Arm compute](https://docs.oracle.com/en-us/iaas/Content/Compute/References/arm.htm),
[OKE Block Volume PVCs](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengcreatingpersistentvolumeclaim_topic-Provisioning_PVCs_on_BV.htm),
[Native Ingress prerequisites](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengsettingupnativeingresscontroller-addon-prereqs.htm), and
[supported add-on versions](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengconfiguringclusteraddons-supportedversions.htm).

## Backup scope

The jobs dump Paperclip PostgreSQL and archive `paperclip-data`; they also
archive `opencode-data` when OpenCode is enabled. **OpenClaw and Qwen data are
not covered.** File archives are
made while workloads may be writing; they are not application-consistent
snapshots. Same-node pod affinity supports the RWO mounts on multi-node
clusters, but jobs can remain pending if the consuming workload is absent.
Monitor job success, object growth, scratch space, and restore procedures.

The private bucket is created even when both backup workloads are disabled.
No retention/deletion policy or automated restore test is configured.
The read/write pre-authenticated URLs expire on August 9, 2031 and grant
bucket-wide object access for their permitted operation. Keep them secret.
Successful uploads alone do not prove recoverability.

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.14
- [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm) (`oci setup config`)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Python 3](https://www.python.org/) (cluster discovery and Ingress IP lookup)
- Docker with ARM64 build support and a registry account for the default Qwen image build
- A domain and DNS control when enabling Internet access with trusted HTTPS

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
# Replace with your public operator/VPN egress CIDR before deploying.
oci_control_plane_allowed_cidrs = ["203.0.113.10/32"]

oci_oke_node_shape               = "VM.Standard.A1.Flex"
oci_oke_node_pool_size           = 2
oci_oke_node_shape_ocpus         = 2
oci_oke_node_shape_memory_in_gbs = 12

paperclip_exposure = "public"
# At least one LLM key for Paperclip agents
anthropic_api_key  = "sk-ant-..."

enable_openclaw = false
enable_opencode = false
enable_qwen     = true

paperclip_custom_domain = "paperclip.example.com"
qwen_custom_domain      = "qwen.example.com"
letsencrypt_email       = "admin@example.com"
```

Never commit `src/terraform.tfvars`.

Replace the example hostnames and email. Without domain + email, public
services use HTTP; use private access/port-forwarding instead of sending
credentials or project data over public HTTP. OpenClaw ingress is created
only when `openclaw_custom_domain` is set. OpenCode and Qwen also require
dedicated hostnames for public mode because OCI Native Ingress does not
support the regex prefix rewrites used by the former NGINX path fallback.
Once ACME TLS is configured, application routes use the 443 listener only;
port 80 is reserved for cert-manager's temporary HTTP-01 solver route.

### 2. Build and publish the enabled custom images

Terraform builds Qwen and any enabled OpenCode image locally but does **not**
push images.
Before deployment, authenticate to your registry and publish matching tags.
For example, from the repository root, after replacing `your-namespace`:

```bash
docker login ghcr.io
docker buildx build --platform linux/arm64 \
  -f src/scripts/qwen.Dockerfile --build-arg QWEN_VERSION=0.23.0 \
  -t ghcr.io/your-namespace/qwen:0.23.0 --push src
```

Use your configured registry and version values. Confirm enabled upstream
images and operator sidecars also support ARM64; moving tags are not pinned
by digest. The complete image set has not been rebuilt in this review.

To inspect private services before enabling Internet ingress:

```bash
kubectl port-forward -n paperclip service/paperclip 3100:80
kubectl port-forward -n opencode service/opencode 4096:80
```

Open `http://127.0.0.1:3100` or `http://127.0.0.1:4096`. Port-forwarding
ends when the command stops. Public access requires setting the exposure to
`public`, configuring domains/email, applying, pointing DNS, and confirming
certificate readiness.

### 3. Deploy

```bash
cd src
terraform init
terraform apply
```

### 4. After apply

Follow `terraform output post_deploy_instructions`. In short:

1. Configure kubectl with the printed `oci ce cluster create-kubeconfig` command.
2. Point the configured DNS A records at the OCI Native Ingress Load Balancer
   IP. Wait
   for the corresponding certificates to report `Ready=True` before login.
   An HTTPS output URL describes the configuration, not certificate readiness.
3. Wait until the Paperclip pod is Ready, then bootstrap the first admin:

   ```bash
   kubectl exec -n paperclip deployment/paperclip -- pnpm paperclipai auth bootstrap-ceo
   ```

   Open the printed invite URL and create the admin account.
4. In Paperclip, generate an OpenClaw invite and paste it into OpenClaw
   (Telegram or direct access).
5. OpenCode Web: `terraform output opencode_public_url` and
   `terraform output -raw opencode_admin_password`. Log in as `opencode`.

### 5. Verify

```bash
kubectl get nodes
kubectl get pods -A
kubectl get ingress -A
kubectl get ingressclass oci-native
oci ce cluster list-addons --cluster-id "$(terraform -chdir=src output -raw cluster_id)"
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
| `oci_control_plane_allowed_cidrs` | Kubernetes API allowlist; operator input required | — |

### Node pool

| Variable | Description | Default |
|---|---|---|
| `oci_oke_node_shape` | Node shape | `"VM.Standard.A1.Flex"` |
| `oci_oke_node_pool_size` | Node count | `2` |
| `oci_oke_node_shape_ocpus` | OCPUs per node | `2` |
| `oci_oke_node_shape_memory_in_gbs` | Memory per node (GB) | `12` |
| `oci_oke_kubernetes_version` | Kubernetes version (confirm regional availability) | `"v1.36.1"` |

### Toggles

| Variable | Description | Default |
|---|---|---|
| `enable_paperclip` | Paperclip + PostgreSQL | `true` |
| `enable_paperclip_qmd` | qmd search on the Paperclip PVC | `true` |
| `enable_paperclip_browser` | Headless Chromium CDP | `true` |
| `enable_metrics_server` | metrics-server | `true` |
| `enable_openclaw` | OpenClaw operator + instance | `false` |
| `enable_opencode` | OpenCode Web | `false` |
| `enable_opencode_browser` | CDP sidecar on OpenCode | `true` |
| `enable_qwen` | Qwen Code Web | `true` |
| `enable_qwen_browser` | CDP sidecar on Qwen (if enabled) | `true` |

### Paperclip

| Variable | Description | Default |
|---|---|---|
| `paperclip_image_repository` | Image repository | `"ghcr.io/paperclipai/paperclip"` |
| `paperclip_image_tag` | Pinned stable image tag | `"2026.831.1"` |
| `paperclip_exposure` | `"public"` (Ingress) or `"private"` | `"private"` |
| `paperclip_custom_domain` | HTTPS + Let's Encrypt | `""` |
| `letsencrypt_email` | ACME account email | `""` |
| `oci_native_ingress_version` | Standalone OCI Native Ingress Controller | `"1.4.5"` |
| `cert_manager_version` | Upstream cert-manager Helm chart | `"1.21.1"` |
| `paperclip_db_storage_size` | PostgreSQL PVC | `"50Gi"` |
| `paperclip_storage_size` | Data PVC | `"50Gi"` |
| `paperclip_cpu_limit` | CPU limit | `"1500m"` |
| `paperclip_memory_limit` | Memory limit | `"6Gi"` |
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
| `openclaw_storage_size` | Workspace PVC | `"50Gi"` |
| `openclaw_cpu_limit` | CPU limit | `"500m"` |
| `openclaw_memory_limit` | Memory limit | `"2Gi"` |
| `openclaw_telegram_enabled` | Telegram bot | `true` |

### OpenCode Web

| Variable | Description | Default |
|---|---|---|
| `opencode_exposure` | `"public"` or `"private"` | `"private"` |
| `opencode_version` | Upstream release tag | `"1.17.13"` |
| `opencode_custom_domain` | Hostname required for public mode | `""` |
| `opencode_storage_size` | Data PVC | `"50Gi"` |
| `opencode_cpu_limit` | CPU limit | `"500m"` |
| `opencode_memory_limit` | Memory limit | `"8Gi"` |
| `opencode_registry` | `"ghcr"` or `"dockerhub"` | `"ghcr"` |

Optional keys (`github_token`, `gitlab_token`, `neon_api_key`, `expo_token`,
`paddle_sandbox_api_key`, and similar) are injected into agent environments
when set. They are not required to bring the cluster up.

### Qwen Code Web

Set `enable_qwen = true` and, before apply, generate Ingress basic auth:

```bash
cd src
sh scripts/gen_qwen_htpasswd.sh 'your-password'
```

That writes gitignored `src/.tmp/qwen_htpasswd`. Default image tag is `0.23.0`.
The PVC is mounted at `/home/qwen/projects`, and the fallback workspace is
`/home/qwen/projects/sandbox`. Clone repositories into sibling directories,
such as `/home/qwen/projects/my-repo`, then register the repository through
Qwen's workspace API with persistence enabled. This keeps one workspace per
repository while leaving the sandbox empty for requests that omit a working
directory.

## Project layout

```
.
├── README.md
├── LICENSE
├── CONTRIBUTING.md
├── SECURITY.md
├── AGENTS.md
├── docs/                           # Evidence review and promotion plan
├── tests/                          # Isolated local test runner
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
    ├── cert-manager.tf              # OKE-managed CertManager add-on
    ├── ingress.tf                   # OCI Native add-on, IAM, LB class
    ├── tests/                       # Provider-mocked Terraform scenarios
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

This repository uses `hashicorp-oss/kubectl` for manifests. A prior provider
hang is a repository troubleshooting observation, not evidence that
`hashicorp/kubernetes` is generally incompatible with Kubernetes 1.36.

## Before production

Defaults optimize for a personal lab, not a locked-down production cluster.
See [SECURITY.md](SECURITY.md). Existing deployments must also review the
[controller, certificate, and storage migration notes](docs/launch-readiness.md#existing-deployment-migration). At minimum:

- Restrict `oci_control_plane_allowed_cidrs` to operator/VPN egress CIDRs
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

Inspect each PV reclaim policy and workload retention setting before cleanup.
Deleting a claim can delete its backing volume; retained/orphaned claims and
volumes may remain billable. Inspect PostgreSQL StatefulSet claims, OpenClaw
operator resources, the non-empty backup bucket, and the ingress load balancer
explicitly. Export data needed for recovery first.

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
