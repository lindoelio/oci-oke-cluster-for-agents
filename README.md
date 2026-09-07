# OCI OKE Cluster for Remote AI Agents

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.14-623CE4?logo=terraform)](https://www.terraform.io)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.36-326CE5?logo=kubernetes)](https://kubernetes.io)

One `terraform apply` stands up an **Always Free–sized OKE cluster** on Oracle Cloud for remote AI agents: **Paperclip** (orchestration UI + PostgreSQL), **OpenClaw** (agent runtime), **OpenCode Web** (coding UI), optional **Qwen Code**, NGINX Ingress, cert-manager, daily Object Storage backups, and a shared headless Chromium (CDP).

Deep dive (architecture, budgets, ops): **[docs/hashnode-draft.md](docs/hashnode-draft.md)**.

## Who this is for

Operators who want a personal/lab Kubernetes home for AI agents on OCI’s **Always Free ARM** quota (`VM.Standard.A1.Flex`), without assembling Ingress, TLS, and runtimes by hand.

## What you get

| Piece | Role |
|---|---|
| OKE (`oracle-terraform-modules/oke/oci` **5.4.3**) | Kubernetes **v1.36**, Flannel, basic cluster |
| 2× `VM.Standard.A1.Flex` | **2 OCPU / 12 GB** each → **4 OCPU / 24 GB** total (Always Free ARM cap) |
| Paperclip | Orchestration UI + Postgres 17; optional qmd + Firebase CLI on PVC |
| OpenClaw | Operator Helm chart + `OpenClawInstance` CR; optional Telegram |
| OpenCode Web | Locally built ARM64 image from upstream release; HTTP basic auth |
| Shared browser | Playwright Chromium + CDP proxy in `paperclip` |
| Ingress + TLS | NGINX (flexible **10 Mbps** LB) + cert-manager / Let’s Encrypt |
| Backups | Private Object Storage bucket + daily CronJobs |

Qwen Code is **off** by default (`enable_qwen = false`).

## Prerequisites

- Terraform **≥ 1.14**
- OCI CLI (`oci setup config`), kubectl, Python 3
- Docker (if you build OpenCode / Qwen images locally)
- An OCI tenancy with Always Free ARM capacity in your region

## Quick start (preferred: local AI harness)

Paste the prompt below into a **local** coding agent (Cursor, Claude Code, etc.) that can edit files and run shell commands on your machine. Prefer this over hand-editing every variable.

<details>
<summary><strong>Copy-paste harness prompt</strong></summary>

```text
You are helping me deploy https://github.com/lindoelio/oci-oke-cluster-for-agents
on MY OCI tenancy. Read AGENTS.md and SECURITY.md first.

Rules:
- Never invent features; ground every change in this repo’s Terraform under src/.
- Never commit src/terraform.tfvars, state, or secrets.
- Do not apply/destroy until I explicitly say so for each command.
- Keep docs/comments in English. No private company identity.

Steps:
1) Ensure Terraform >= 1.14, OCI CLI, kubectl, Python 3, and Docker are available.
2) Clone the repo if needed. Copy src/terraform.tfvars.example → src/terraform.tfvars.
3) Ask me for: project_prefix, oci_tenancy_id, oci_compartment_id, oci_region,
   oci_home_region, at least one LLM key for Paperclip, openclaw_llm_api_key,
   and (if enable_opencode) registry username/token/namespace for the OpenCode image.
4) Set oci_oke_* defaults for Always Free: shape VM.Standard.A1.Flex, pool size 2,
   2 OCPUs / 12 GB per node. Prefer oci_public_workers=true only if I accept public node IPs
   (example file does; variables.tf default is false).
5) Leave enable_qwen=false unless I ask. If I enable Qwen, run
   sh scripts/gen_qwen_htpasswd.sh '<password>' from src/ first.
6) Show me a short plan of tfvars keys you will set (redact secrets), then wait.
7) On my explicit OK: cd src && terraform init && terraform plan, summarize risk, then
   terraform apply only after a second explicit OK.
8) After apply: print terraform output post_deploy_instructions and help me run
   kubeconfig + Paperclip bootstrap-ceo + OpenCode URL/password.
```

</details>

### Manual path

```bash
git clone https://github.com/lindoelio/oci-oke-cluster-for-agents.git
cd oci-oke-cluster-for-agents
cp src/terraform.tfvars.example src/terraform.tfvars
# edit OCIDs, region, LLM keys, OpenCode registry …
cd src && terraform init && terraform apply
```

Then follow `terraform output post_deploy_instructions` (kubeconfig, Paperclip `bootstrap-ceo`, OpenClaw invite, OpenCode URL + `opencode_admin_password`).

## Always Free facts (accurate to this repo)

- **Compute:** defaults use **2× A1.Flex @ 2 OCPU / 12 GB** = **4 OCPU / 24 GB** (Always Free ARM envelope).
- **Boot disks:** **50 GB** per node (**100 GB** for the default pool).
- **Block volumes:** app PVCs (Postgres, Paperclip, OpenClaw, OpenCode, …) count toward the **~200 GB** Always Free block budget—keep sizes modest (defaults are mostly 5–10 Gi).
- **Load balancer:** Ingress uses OCI **flexible** shape **min=max=10 Mbps** (Always Free–friendly; fixed “10Mbps” shape is billable—see `src/ingress.tf`).
- **Object Storage:** backup bucket + PARs; Always Free includes a small Object Storage allowance (CronJobs upload daily dumps).
- **Images:** ARM64 everywhere (OpenCode/Qwen Dockerfiles are `linux/arm64`).

Turning on **Qwen** or raising memory limits can push you over the free envelope—see the Hashnode draft for the component table.

## Layout

```
src/                 Terraform root (main, oke, paperclip, openclaw, opencode, qwen, …)
src/scripts/         Dockerfiles, onboard/CDP helpers, htpasswd generator
AGENTS.md            Rules for coding agents touching this repo
SECURITY.md          Lab defaults & known risks
docs/hashnode-draft.md
```

## Before you treat it as production

Defaults favor a personal lab (`control_plane_allowed_cidrs = ["0.0.0.0/0"]` in `oke.tf`, optional public workers, HTTP until custom domains + `letsencrypt_email`). See [SECURITY.md](SECURITY.md).

## Cleanup

```bash
cd src && terraform plan -destroy && terraform destroy
```

Confirm Block Volumes and the Ingress LB are gone in the OCI console.

## License

MIT — see [LICENSE](LICENSE).
