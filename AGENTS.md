# AGENTS.md — AI Agent Guidelines

<!-- BEGIN managed:agents-overview -->
## Overview

This document provides context and rules for AI coding agents (Qwen Code, Copilot, Cursor, Codex, etc.) working on this Terraform repository.

**Repository:** `oci-oke-cluster-for-agents`
**Purpose:** Deploy an OCI Free Tier OKE cluster with Paperclip (AI agent orchestration) and OpenClaw (AI agent runtime) via Kubernetes operators.
**Stack:** Terraform ≥ 1.14, OCI provider 8.9.0, Helm 3.1.1, kubectl provider 0.1.13, Python 3 (external data sources).
<!-- END managed:agents-overview -->

<!-- BEGIN managed:agents-repo-structure -->
## Repository Structure

| File | Responsibility |
|---|---|
| `main.tf` | Provider configs, compartment, cluster discovery, kubeconfig generation |
| `oke.tf` | OKE cluster module invocation + CRI-O short-name fix DaemonSet |
| `paperclip.tf` | Paperclip Deployment, PostgreSQL StatefulSet, secrets (no operator) |
| `openclaw.tf` | OpenClaw operator Helm release, OpenClawInstance CRD, secrets |
| `variables.tf` | All input variable definitions with validation rules |
| `output.tf` | Terraform outputs and post-deploy instructions |
| `terraform.tfvars.example` | Example configuration template (copy to `terraform.tfvars`) |
| `specs/` | Design specifications (git-ignored) |
<!-- END managed:agents-repo-structure -->

<!-- BEGIN managed:agents-conventions -->
## Conventions

### Terraform Style

- Use `snake_case` for all resource names, variables, and locals.
- Pin provider versions with exact `=` constraints in `main.tf`.
- Use `count` with boolean toggle variables (`enable_*`) for conditional resource deployment.
- Use `time_sleep` resources after operator Helm releases to wait for CRD readiness (30s default).
- Use `kubectl_manifest` (hashicorp-oss/kubectl) for all Kubernetes resources — **never** use the `hashicorp/kubernetes` provider (hangs on K8s 1.36.x).
- Mark sensitive variables with `sensitive = true`.
- Add a `description` to every variable and output.

### File Organization

- One `.tf` file per logical concern (cluster, app, provider setup).
- Group resources within a file using `########` comment block separators with section titles.
- Keep all variables in `variables.tf` and all outputs in `output.tf`.

### Naming

- Cluster name: `${var.project_prefix}-oke-cluster`
- VCN name: `${var.project_prefix}-vcn`
- Kubernetes resources: `${var.project_prefix}-<app>` (e.g., `myproject-paperclip`)
- Namespaces: lowercase app name (`paperclip`, `openclaw`) for instances, `<app>-system` for operators

### Provider Configuration

- OCI provider uses API key auth with `DEFAULT` profile from OCI CLI config.
- Two OCI provider aliases: default (regional) and `home` (tenancy-scoped operations).
- Helm has two instances: `helm.oke` (for the OKE module's internal extensions) and default (for app deployments).
- The `helm.oke` alias is critical — removing it causes a provider cycle and `terraform init` hangs.
<!-- END managed:agents-conventions -->

<!-- BEGIN managed:agents-safety-rules -->
## Safety Rules

1. **Never commit `terraform.tfvars`** — it contains secrets. It is git-ignored.
2. **Never hardcode OCIDs, API keys, or tokens** — use variables or data sources.
3. **Do not remove the `helm.oke` alias** — it prevents a provider dependency cycle.
4. **Do not switch to `hashicorp/kubernetes`** — it hangs on K8s 1.36.x. Use `hashicorp-oss/kubectl`.
5. **Do not remove `time_sleep` resources** — they prevent CRD-not-ready race conditions.
6. **Single apply** — `terraform apply` handles everything. The compartment is created conditionally (if `oci_project_compartment_id` is empty).
7. **Validate before apply** — always run `terraform validate` and `terraform plan` first.
<!-- END managed:agents-safety-rules -->

<!-- BEGIN managed:agents-dependencies -->
## External Dependencies

- **OCI CLI** must be installed and configured (`oci setup config`) — used by `data.external` scripts for cluster discovery and token generation.
- **Python 3** — required for inline scripts in `main.tf` (`cluster_lookup_script`, `token_script`).
- **kubectl** — needed for post-deploy verification and kubeconfig setup.
<!-- END managed:agents-dependencies -->

<!-- BEGIN managed:agents-common-tasks -->
## Common Tasks

### Validate changes
```bash
cd src && terraform fmt -check -recursive && terraform validate
```

### Plan changes
```bash
cd src && terraform plan -out=tfplan && terraform show tfplan
```

### Add a new Kubernetes workload
1. Create `<workload>.tf` with operator Helm release, `time_sleep`, namespace, secrets, and CRD instance.
2. Follow the pattern in `paperclip.tf` or `openclaw.tf`.
3. Add toggle variable (`enable_<workload>`) and config variables to `variables.tf`.
4. Add relevant outputs to `output.tf`.
5. Update `terraform.tfvars.example`.

### Update a provider version
1. Change the `version` constraint in `src/main.tf`.
2. Run `cd src && terraform init -upgrade`.
3. Run `cd src && terraform plan` and review changes.
4. Commit the updated `.terraform.lock.hcl`.
<!-- END managed:agents-common-tasks -->

<!-- BEGIN managed:agents-related-docs -->
## Related Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) — System architecture and component layout
- [SECURITY.md](SECURITY.md) — Security model and hardening checklist
- [CONTRIBUTING.md](CONTRIBUTING.md) — Contribution workflow and commit conventions
- [STYLEGUIDE.md](STYLEGUIDE.md) — Terraform formatting and naming rules
- [README.md](README.md) — User-facing documentation and quick start
<!-- END managed:agents-related-docs -->
