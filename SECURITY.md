# SECURITY.md — Security Model and Hardening

<!-- BEGIN managed:security-overview -->
## Overview

This project is designed for **development, learning, and experimentation** on OCI Free Tier. The defaults prioritize simplicity and cost over security. This document describes the current security posture and provides a checklist for production hardening.

**Rule of thumb:** If you're exposing this cluster to the internet or real users, complete every item in the [Production Hardening Checklist](#production-hardening-checklist) first.
<!-- END managed:security-overview -->

<!-- BEGIN managed:security-secrets -->
## Secrets Management

### Current State

| Secret | Source | Storage |
|---|---|---|
| `anthropic_api_key` | Terraform variable (sensitive) | K8s Secret `paperclip-api-keys` |
| `openai_api_key` | Terraform variable (sensitive) | K8s Secret `paperclip-api-keys` |
| `openrouter_api_key` | Terraform variable (sensitive) | K8s Secret `paperclip-api-keys` |
| `ollama_cloud_api_key` | Terraform variable (sensitive) | K8s Secret `paperclip-api-keys` |
| `openclaw_llm_api_key` | Terraform variable (sensitive) | K8s Secret `openclaw-llm-keys` |
| `openclaw_telegram_bot_token` | Terraform variable (sensitive) | K8s Secret `openclaw-telegram` |
| `OPENCODE_SERVER_PASSWORD` | `random_password` resource | K8s Secret `opencode-auth` |
| `opencode_registry_token` | Terraform variable (sensitive) | Docker registry auth (Terraform only, not K8s) |
| `github_token` | Terraform variable (sensitive) | K8s Secret `opencode-dev-credentials` |
| `gcp_service_account_key` | Terraform variable (sensitive) | K8s Secret `opencode-dev-credentials` |
| `BETTER_AUTH_SECRET` | `random_password` resource | K8s Secret `paperclip-auth` |
| `POSTGRES_PASSWORD` | `random_password` resource | K8s Secret `paperclip-db` |
| OCI auth | OCI CLI API key (`DEFAULT` profile) | Local OCI CLI config (not in Terraform) |

### Risks

- **Terraform state contains secrets** — `terraform.tfstate` stores all variable values, including sensitive ones, in plaintext. State files are local-only and git-ignored, but must be protected.
- **`random_password` regenerates on state loss** — If the state file is deleted, `BETTER_AUTH_SECRET` will be regenerated, invalidating existing Paperclip sessions.
- **K8s Secrets are base64-encoded, not encrypted** — Without etcd encryption at rest, secrets are readable by anyone with cluster access.
<!-- END managed:security-secrets -->

<!-- BEGIN managed:security-network -->
## Network Security

### Current State

| Component | Exposure | Notes |
|---|---|---|---|
| OKE Control Plane | Public (`0.0.0.0/0`) | API server accessible from any IP |
| Worker Nodes | Public or Private | Controlled by `oci_public_workers` (default: `false`) |
| NGINX Ingress LB | Public (OCI 10Mbps) | Single entry point; forwards to ClusterIP services |
| Paperclip Service | ClusterIP | Internal only, accessed through NGINX Ingress |
| OpenClaw Service | ClusterIP | Internal only |
| OpenCode Service | ClusterIP | Internal only, accessed through NGINX Ingress |

### Risks

- **Control plane open to the internet** — `control_plane_allowed_cidrs = ["0.0.0.0/0"]` allows API server access from any IP. Acceptable for development; dangerous for production.
- **No NetworkPolicies enforced** — While Paperclip's CRD enables `networkPolicy: true`, cluster-wide network policies are not defined.
- **No default TLS** — Without a custom domain configured, Paperclip and OpenCode serve over HTTP. TLS is available via cert-manager + Let's Encrypt when `paperclip_custom_domain` / `opencode_custom_domain` and `letsencrypt_email` are set.
- **NGINX Ingress is the single entry point** — A compromise of the ingress controller could expose all internal services.
<!-- END managed:security-network -->

<!-- BEGIN managed:security-auth -->
## Authentication and Access

### OCI Level
- Authentication uses OCI CLI API key with the `DEFAULT` profile.
- No IAM policies are managed by Terraform — the OCI CLI user must have sufficient permissions (typically `manage` on the compartment).

### Kubernetes Level
- Cluster access uses token-based authentication generated via `oci ce cluster generate-token`.
- No RBAC customization beyond what the OKE module and operators create.
- Paperclip generates its own auth secret (`BETTER_AUTH_SECRET`) for user account management.

### Application Level
- Paperclip: Users create accounts via the web UI, authenticated by the auto-generated secret.
- OpenClaw: Telegram bot token for bot access; no additional user auth layer.
- OpenCode Web: HTTP Basic Auth with auto-generated `OPENCODE_SERVER_PASSWORD`; username is `opencode`.
<!-- END managed:security-auth -->

<!-- BEGIN managed:security-production-checklist -->
## Production Hardening Checklist

Complete these items before exposing the cluster to real workloads or users.

### Networking

- [ ] **Restrict API server CIDRs** — Change `control_plane_allowed_cidrs` in `oke.tf` to your IP or VPN CIDR.
- [ ] **Private worker nodes** — Set `oci_public_workers = false` to place nodes behind NAT.
- [ ] **Private control plane** — Set `control_plane_is_public = false` (requires VPN or bastion).
- [ ] **TLS for Paperclip** — Set `paperclip_custom_domain` and `letsencrypt_email` in `terraform.tfvars` to enable cert-manager + Let's Encrypt TLS (built-in, just needs configuration).
- [ ] **TLS for OpenCode** — Set `opencode_custom_domain` and `letsencrypt_email` in `terraform.tfvars` to enable HTTPS for OpenCode Web.
- [ ] **Network policies** — Define cluster-wide NetworkPolicies to restrict pod-to-pod traffic.

### Secrets

- [ ] **External secret management** — Move secrets to OCI Vault and inject via OCI Secrets Manager or External Secrets Operator.
- [ ] **etcd encryption** — Enable OCI KMS envelope encryption for Kubernetes secrets at rest.
- [ ] **Rotate API keys** — Rotate LLM API keys periodically; never commit them to version control.
- [ ] **Protect state file** — Move to OCI Object Storage remote backend with encryption and access control.

### Operational

- [ ] **Remote state with locking** — Configure OCI Object Storage backend for state storage and DynamoDB-equivalent locking.
- [ ] **Monitoring and alerting** — Deploy Prometheus + Grafana or OCI Monitoring for cluster health.
- [ ] **Audit logging** — Enable OCI Cloud Guard and VCN Flow Logs.
- [ ] **Backup strategy** — Back up Paperclip's PostgreSQL data and persistent volumes before upgrades.
- [ ] **Provider version review** — Audit pinned provider versions in `main.tf` for known CVEs.
- [ ] **RBAC policies** — Define Kubernetes RBAC for team members with least-privilege access.
<!-- END managed:security-production-checklist -->

<!-- BEGIN managed:security-known-issues -->
## Known Security Considerations

### `data.external` Scripts
The Python scripts in `main.tf` invoke `oci` CLI commands via `subprocess.run`. They suppress Python warnings (`PYTHONWARNINGS=ignore`) and OCI label warnings (`SUPPRESS_LABEL_WARNING=True`). These scripts run only during `plan`/`apply` and do not expose data externally.

### `kubectl_manifest` Provider
The `hashicorp-oss/kubectl` provider applies manifests via the Kubernetes API. It does not validate manifests against admission controllers — invalid manifests will fail at apply time, not plan time.

### Free Tier Constraints
OCI Free Tier does not include:
- OCI Vault (KMS) for managed key storage
- Web Application Firewall (WAF)
- Advanced Cloud Guard features

Production deployments should evaluate paid-tier security services.
<!-- END managed:security-known-issues -->

<!-- BEGIN managed:security-incident-response -->
## Incident Response

If credentials are compromised:

1. **OCI CLI credentials** — Rotate the API signing key in OCI Console → Identity → Users → API Keys.
2. **LLM API keys** — Rotate immediately at the provider (Anthropic, OpenAI, OpenRouter). Update `terraform.tfvars` and run `terraform apply`.
3. **Telegram bot token** — Revoke via @BotFather and generate a new token. Update `terraform.tfvars` and run `terraform apply`.
4. **GitHub PAT** — Revoke at https://github.com/settings/tokens. Generate a new token with equivalent scopes. Update `terraform.tfvars` and run `terraform apply`.
5. **GCP service account key** — Delete the key in GCP Console → IAM & Admin → Service Accounts → opencode. Create a new key and update `terraform.tfvars`.
6. **`BETTER_AUTH_SECRET`** — If the Terraform state is compromised, regenerate by tainting:
   ```bash
   terraform taint random_password.paperclip_auth[0]
   terraform apply
   ```
   This invalidates all existing Paperclip user sessions.
7. **`OPENCODE_SERVER_PASSWORD`** — If compromised, regenerate by tainting:
   ```bash
   terraform taint random_password.opencode_admin[0]
   terraform apply
   ```
   This invalidates existing OpenCode Web sessions.
<!-- END managed:security-incident-response -->

<!-- BEGIN managed:security-related-docs -->
## Related Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) — System architecture and component layout
- [AGENTS.md](AGENTS.md) — AI agent safety rules
- [TESTING.md](TESTING.md) — Security scanning in the validation strategy
- [README.md](README.md) — "Before Going to Production" section
<!-- END managed:security-related-docs -->
