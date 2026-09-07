# One `terraform apply`: Always Free OKE for Paperclip, OpenClaw, and OpenCode

*A technical walkthrough of [lindoelio/oci-oke-cluster-for-agents](https://github.com/lindoelio/oci-oke-cluster-for-agents). Claims below map to files in that repository (see Sources). Lab-oriented stack — not a hardened production blueprint.*

## What you get from one apply

Fill `src/terraform.tfvars`, run apply, and you land a child compartment, an Always Free–sized OKE cluster on Oracle ARM, and a working agent lab on top: Paperclip (orchestration UI + Postgres), OpenClaw (operator + instance), OpenCode Web (ARM64 image you build), shared headless Chromium over CDP, Ingress + optional TLS, metrics, and nightly Object Storage backups.

The public README stays intentionally slim. This article is the depth pass: architecture, free-tier math, the non-obvious wiring that makes the stack actually apply on Kubernetes 1.36 / CRI-O, and where to fork next.

## Architecture at a glance

```
OCI Tenancy
└── Child compartment (Terraform-managed, named from project_prefix)
    ├── OKE basic cluster (K8s v1.36, Flannel, public control plane)
    │   ├── 2x VM.Standard.A1.Flex workers (2 OCPU / 12 GB each by default)
    │   ├── kube-system: crio-shortname-fix DaemonSet, metrics-server
    │   ├── ingress-nginx: NGINX + OCI flexible LB (10/10 Mbps)
    │   ├── cert-manager + optional Lets Encrypt ClusterIssuer
    │   ├── paperclip/: UI + Postgres StatefulSet + shared CDP browser
    │   ├── openclaw-system/: openclaw-operator (Helm)
    │   ├── openclaw/: OpenClawInstance + data PVC
    │   ├── opencode/: OpenCode Web Deployment + PVC (+ Ingress)
    │   └── qwen/: optional Qwen Code Web (default off)
    └── Object Storage bucket {prefix}-backups + write/read PARs
```

OKE comes from `oracle-terraform-modules/oke/oci` **v5.4.3** (`src/oke.tf`). App objects use **`hashicorp-oss/kubectl`** — not `hashicorp/kubernetes` — because the latter hangs on Kubernetes 1.36 (`README.md`, `src/main.tf`). That provider choice is the difference between a clean apply and a stuck one.

## Free-tier budget and trade-offs

Defaults with Paperclip + OpenClaw + OpenCode + browser (Qwen off), from the upstream README table and Terraform defaults:

| Layer | Default sizing |
|---|---|
| Nodes | 2x A1.Flex → **4000m / 24Gi**, **50 GB** boot each |
| Paperclip + Postgres | limits **1000m / 4Gi**; storage **5Gi + 10Gi** |
| Shared browser | limits **1000m / 2Gi** |
| OpenClaw | limits **500m / 2Gi**; PVC **5Gi** |
| OpenCode | limits **500m / 8Gi**; PVC **5Gi** |

Storage sketch (defaults, Qwen off):

- Boots: 2 × 50 GB = 100 GB (`worker_shape.boot_volume_size` in `src/oke.tf`)
- App PVCs: Paperclip 5Gi + DB 10Gi + OpenClaw 5Gi + OpenCode 5Gi ≈ 25 Gi
- Fits a ~200 GB Always Free block narrative with headroom; Qwen adds another 5Gi PVC
- Object Storage backups are separate (`src/backup.tf` bucket + PARs)

Always Free ARM is commonly **4 OCPU + 24 GB** and roughly **200 GB** block. This repo sizes to fit that envelope — not for HA.

Trade-offs worth knowing before you apply:

1. Example tfvars sets `oci_public_workers = true`; `variables.tf` default is `false`.
2. OpenCode’s **8Gi** memory limit is a large slice of 24Gi — intentional for coding sessions, tight if you turn Qwen on.
3. Qwen stays off by default to protect the envelope.
4. HTTP until custom domains + ACME email.
5. Provider tokens land in Kubernetes Secrets (lab posture).
6. The CRI-O DaemonSet and kubectl provider choice are pragmatic hacks, called out as such.

## Craft that makes the apply work

These are the details that separate “looks like a blog demo” from “actually provisions on Always Free OKE.”

### kubectl provider, not kubernetes — and a dummy Helm alias

`hashicorp/kubernetes` hangs against this OKE 1.36 control plane. The stack pins `hashicorp-oss/kubectl` **0.1.13** for manifests. A dummy `helm.oke` provider breaks a dependency cycle with the OKE module so `terraform init` does not hang (`src/main.tf`). Two OCI providers are declared (default region + `alias = home`) for home-region compartment work.

### CRI-O short-name fix

OKE’s CRI-O enforces short-name mode. Without a fix, images like `postgres:17-alpine` fail with ImageInspectError — a failure mode OpenClaw hits in the upstream troubleshooting list. Privileged DaemonSet `crio-shortname-fix` appends `unqualified-search-registries = ["docker.io"]` and restarts CRI-O (`src/oke.tf`). Lab convenience, not production hardening.

`control_plane_allowed_cidrs` is open to the world in `oke.tf` — restrict before anything resembling production (`SECURITY.md`).

### Flexible load balancer at 10 Mbps

NGINX Ingress chart **4.12.0** sits on an OCI flexible LB with **min=max=10** Mbps (`src/ingress.tf`). That keeps the LB inside Always Free–friendly bandwidth while still giving a stable public IP for Paperclip, OpenClaw, and OpenCode Ingresses.

### ARM64 image builds for OpenCode (and optional Qwen)

Workers are A1.Flex (ARM). OpenCode is not a stock multi-arch pull: `src/opencode.tf` builds via Docker from `scripts/opencode.Dockerfile` — downloads the `anomalyco/opencode` **linux-arm64** tarball (default tag **1.17.13**), Ubuntu 24.04 + Node 24 + gh / gcloud / Firebase / glab / neonctl / eas-cli. Entrypoint: `opencode web` on port **4096**. Permission default `allow` in baked `opencode.json`.

Comment in Terraform: `docker_registry_image` was removed due to a provider digest bug — push to GHCR/Docker Hub may be manual. Ingress path default **`/opencode`**, basic auth user **`opencode`**.

Qwen (`enable_qwen`, default **false**) mirrors the pattern with `scripts/qwen.Dockerfile` (`@qwen-code/qwen-code`, default **0.22.2**) — another Always Free budget consumer, hence off by default.

## Component deep dive

### OKE module

`module "oke"` creates a **basic** cluster, Flannel CNI, public control plane, and a worker pool from variables. Bastion and operator hosts are off. When `oci_public_workers` is true, NAT is `"never"`.

### Paperclip — orchestration UI + Postgres

Deployed **directly** (no operator) in namespace `paperclip`:

- Random Better Auth + Postgres credentials (`prevent_destroy` on the random resources)
- Postgres **17** Alpine StatefulSet; `PGDATA` is a subdirectory (avoids InitDB on `lost+found`)
- Init containers: `paperclip-onboard` (`scripts/paperclip_onboard.sh` runs onboard and patches public auth URL modes), `company-auth-writer` (`scripts/company_auth_writer.js`), optional `qmd-setup` (`@tobilu/qmd@2.5.3`), optional `firebase-setup`
- Volumes on storage class **`oci-bv`**
- Model-discovery Secret can carry OpenRouter / Ollama Cloud / Alibaba / DeepInfra values for UI model listing

Public URL order: custom domain, then `paperclip_public_url`, then Ingress IP from `scripts/detect_ingress_ip.py`.

Post-deploy admin bootstrap is the `paperclipai auth bootstrap-ceo` flow documented in `src/output.tf` and the upstream README.

### Shared headless browser (CDP)

`src/browser.tf` runs Playwright Chromium (`mcr.microsoft.com/playwright:v{version}-noble`, default **1.62.1**). Chrome CDP binds loopback; `scripts/cdp_proxy.js` exposes `0.0.0.0:9222`. Service: `paperclip-browser.paperclip.svc.cluster.local:9222`.

OpenCode/Qwen install the Playwright **client** on their PVC and run a **`cdp-forward`** sidecar to `localhost:9222` (see `src/opencode.tf` and OpenCode Dockerfile `AGENTS.md` instructions).

Terraform browser resources: requests **250m/512Mi**, limits **1000m/2Gi** (upstream README approximates ~500m/~1Gi).

### OpenClaw — operator + instance

Helm chart `openclaw-operator` **0.36.5** from `oci://ghcr.io/paperclipinc/charts` into `openclaw-system`. Then namespace `openclaw`, LLM Secret, optional Telegram Secret, ConfigMap with `gateway.bind = "lan"`, defaults provider **openrouter** and model **`nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free`**, CR `OpenClawInstance` (`openclaw.rocks/v1alpha1`), explicit data PVC for Always Free reclaim, Ingress on port **18789**, plus a `null_resource` local-exec that copies models/auth JSON into the pod after ready.

### Ingress, TLS, metrics, backups

- cert-manager **1.16.2**; ClusterIssuer only if `letsencrypt_email` set
- metrics-server **3.13.1** with `--kubelet-insecure-tls`
- `src/backup.tf`: private Object Storage bucket, long-lived write/read PARs (fixed expiry 2031-08-09), CronJobs `30 3 * * *` (Paperclip pg_dump + data tar) and `35 3 * * *` (OpenCode data tar). RWO mount caveat noted in-file for multi-node.

## How the pieces fit (runtime story)

1. Fill `src/terraform.tfvars` from the example (OCIDs, region, keys, registry).
2. Terraform creates compartment → OKE → waits → configures Helm/kubectl with a generated token (`src/main.tf` Python via `external` data).
3. Ingress LB IP feeds Paperclip’s public URL.
4. Paperclip onboards; operator runs bootstrap-ceo.
5. OpenClaw joins via invite (Telegram or direct); agents appear in Paperclip.
6. OpenCode Web serves coding sessions; agents use the cluster CDP.
7. Nightly CronJobs upload dumps to Object Storage.

## Local AI harness + IaC workflow

**In-repo evidence:** There is **no** proprietary CI harness or company identity pack in the public tree. `AGENTS.md` and `CONTRIBUTING.md` forbid private harnesses and forbid merges from mutating infrastructure. Validation is local.

Supported workflow: paste the **local AI harness prompt** from the slim README into a laptop coding agent so it drafts tfvars, runs init/plan, and applies **only** with explicit human OK. That matches the contribution rules.

The Terraform style is consistent with iterative human+AI editing; the repo does not document a specific generator — this article does not invent one. Use the copy-paste block under **Quick start (preferred: local AI harness)** in `README.md`. Constraints: ground changes in `src/`, never commit secrets/state, never apply without explicit approval, leave `enable_qwen` false unless asked, Always Free node defaults as above.

## Provider and pin map

From `src/main.tf` `required_providers`:

| Provider | Version |
|---|---|
| `hashicorp/cloudinit` | 2.3.7 |
| `kreuzwerker/docker` | 4.5.0 |
| `hashicorp/external` | 2.3.5 |
| `hashicorp/helm` | 3.1.1 |
| `hashicorp-oss/kubectl` | 0.1.13 |
| `hashicorp/local` | 2.8.0 |
| `hashicorp/null` | 3.2.4 |
| `oracle/oci` | 8.9.0 |
| `hashicorp/random` | 3.8.1 |
| `hashicorp/time` | 0.13.1 |

Terraform `required_version` >= 1.14.0. OKE module **5.4.3** in `src/oke.tf`. Dummy `helm.oke` alias avoids provider-cycle hangs.

## Compartment and kube auth plumbing

If `oci_project_compartment_id` is empty, Terraform creates a child compartment named `project_prefix`, sleeps 30s, then builds `{prefix}-oke-cluster`. Cluster ID lookup and exec token generation use inline Python via `data.external` calling the OCI CLI (`src/main.tf`), feeding Helm and kubectl providers without fragile module-output wiring.

## Paperclip runtime environment (selected)

From `src/paperclip.tf` and `scripts/paperclip_onboard.sh`:

- Onboard only runs when marker or config.json is missing; patches deploymentMode authenticated, exposure public, bind lan, host 0.0.0.0, port 3100, and sets auth.baseUrlMode explicit with publicBaseUrl.
- Public URL–related env on the main container avoids the auth.baseUrlMode CrashLoop called out in upstream troubleshooting.
- `PAPERCLIP_BROWSER_CDP` points agents at the shared browser service when `enable_paperclip_browser` is true.
- Cheap/budget model default for recovery retries: `openrouter/nvidia/nemotron-3.5-lightning:free` (`paperclip_cheap_model`).
- qmd and firebase-tools installers use `node:24-slim`; stamp files under the PVC keep restarts idempotent.

## OpenCode image contents worth knowing

`src/scripts/opencode.Dockerfile` builds an ARM64 Ubuntu 24.04 image with Node 24, GitHub CLI, Google Cloud SDK, Firebase tools, glab, neonctl, eas-cli, and common TypeScript/Python tooling. It bakes OpenCode config with permission set to allow and ships browser CDP guidance in an image-level `AGENTS.md`. Default OpenCode memory limit in `variables.tf` is **8Gi** — the largest app limit in the stack.

## OpenClaw auth post-step

`null_resource.openclaw_fix_stale_auth` in `src/openclaw.tf` waits for the OpenClaw pod, copies models/auth JSON into the agent directory, then rolls the StatefulSet. Triggers include hashes of the LLM credential and model/provider so rotations re-run the fix. The apply host needs working kubectl to the cluster.

## Configuration surface

Authoritative defaults: `src/variables.tf`. Lab example: `src/terraform.tfvars.example`.

Enable toggles in `variables.tf`: `enable_paperclip`, `enable_paperclip_qmd`, `enable_paperclip_firebase_cli`, `enable_metrics_server`, `enable_paperclip_browser`, `enable_openclaw`, `enable_opencode`, `enable_opencode_browser`, `enable_qwen`, `enable_qwen_browser`.

Exposure enums are `public` | `private` for Paperclip and OpenCode. Optional developer credentials inject only when non-empty; none are required to bring the cluster up.

## Security and contribution notes

`SECURITY.md` documents lab defaults: open API CIDR until edited in `oke.tf`, public workers in the example file, HTTP until custom domains.

`AGENTS.md` / `CONTRIBUTING.md`: no private company identity or proprietary harnesses; merges do not apply infra; English docs; never mutate a cluster without explicit operator authorization.

## Ops notes

Post-deploy (also `output.post_deploy_instructions`): configure kubeconfig; wait for Paperclip Ready then bootstrap-ceo; wire OpenClaw invite; open OpenCode URL + admin password output; optional DNS + domains + Lets Encrypt; verify nodes/pods/ingress/certificates.

Known failure modes (upstream README troubleshooting, still matched by Terraform): Paperclip `auth.baseUrlMode`, Postgres `lost+found`/`PGDATA`, OpenClaw short-name ImageInspectError, OpenClaw Invalid `--bind`, `terraform init` hang without `helm.oke` alias, kubectl provider hang if `hashicorp/kubernetes` is added, stale null volume fields needing state rm.

Destroy deletes PVCs/Block Volumes; confirm LB gone in console. Backup PARs outlive the cluster until expiry.

## What to evolve next

- Tighten API CIDRs; prefer private workers with documented NAT cost
- Remote state + Vault/external secrets instead of tfvars → cluster Secrets
- Qualify images upstream and retire the privileged CRI-O DaemonSet
- CSI snapshots instead of RWO CronJob mounts
- Restore automated registry push (or a documented one-shot push script)
- NetworkPolicies isolating CDP and Postgres
- Keep the GitHub README slim; keep this article as the depth layer

If you fork this for a tighter security posture, a smaller memory envelope, or another agent runtime on the same Always Free shape — PRs and experiments that stay inside `src/` and the contribution rules are welcome. The interesting work is the next hard constraint you remove without breaking the free-tier math.

## Sources

| Path | Supports |
|---|---|
| `README.md` | Features, resource table, troubleshooting, layout |
| `AGENTS.md`, `CONTRIBUTING.md`, `SECURITY.md` | Agent rules, no private harnesses, lab risks |
| `src/main.tf` | Providers, compartment, kube auth |
| `src/oke.tf` | OKE 5.4.3, CIDRs, CRI-O DaemonSet |
| `src/variables.tf`, `src/terraform.tfvars.example` | Defaults and example sizing |
| `src/paperclip.tf` | Direct deploy, Postgres 17, initContainers |
| `src/browser.tf`, `src/scripts/cdp_proxy.js` | Shared CDP |
| `src/openclaw.tf`, `src/openclaw-ingress.tf` | Operator, CR, Telegram, auth fix |
| `src/opencode.tf`, `src/scripts/opencode.Dockerfile` | Image build, Ingress, CDP sidecar |
| `src/qwen.tf`, `src/scripts/qwen.Dockerfile` | Optional Qwen |
| `src/ingress.tf`, `src/cert-manager.tf`, `src/metrics-server.tf` | LB, ACME, metrics |
| `src/backup.tf` | Bucket, PARs, CronJobs |
| `src/output.tf` | Post-deploy instructions |
| `src/scripts/paperclip_onboard.sh` | First-boot public config patch |
| `LICENSE` | MIT (Copyright 2026 lindoelio) |

*Researched from public `main` via GitHub API / raw fetches (no git clone).*
