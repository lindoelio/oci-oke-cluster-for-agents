# STYLEGUIDE.md — Terraform Style Guide

<!-- BEGIN managed:styleguide-overview -->
## Overview

This style guide enforces consistency across all Terraform files in `src/`. Run `terraform fmt -recursive` from the `src/` directory before every commit.
<!-- END managed:styleguide-overview -->

<!-- BEGIN managed:styleguide-formatting -->
## Formatting

### Automated Formatting

```bash
terraform fmt -recursive
```

This handles indentation (2 spaces), alignment, and line wrapping. Never manually format Terraform code.

### File Layout

Each `.tf` file follows this internal order:

1. `########` comment block separator with section title
2. Resources grouped by logical purpose
3. Blank line between resource blocks

```hcl
################################################################################
# Section Title
# One-line description of what this section deploys.
################################################################################

resource "helm_release" "example" {
  ...
}

resource "time_sleep" "after_example" {
  ...
}
```
<!-- END managed:styleguide-formatting -->

<!-- BEGIN managed:styleguide-naming -->
## Naming Conventions

### Terraform Identifiers

| Element | Convention | Example |
|---|---|---|
| Resources | `snake_case` | `helm_release.openclaw_operator` |
| Data sources | `snake_case` | `data.external.oke_cluster` |
| Variables | `snake_case` | `var.oci_oke_node_shape` |
| Locals | `snake_case` | `local.cluster_name` |
| Outputs | `snake_case` | `output.cluster_endpoint` |

### Variable Prefixes

- `oci_` — OCI infrastructure variables (region, tenancy, compartment)
- `oci_oke_` — OKE cluster-specific variables
- `paperclip_` — Paperclip workload variables
- `openclaw_` — OpenClaw workload variables
- `enable_` — Boolean toggle for conditional deployments

### Resource Naming

- Helm releases: `<app>-operator` (e.g., `openclaw-operator`)
- Namespaces: `<app>` for instances, `<app>-system` for operators
- Kubernetes resources in manifests: `<project_prefix>-<app>` (e.g., `myproject-paperclip`)
- Sleep resources: `after_<what_they_wait_for>` (e.g., `after_openclaw_operator`)

### OCI Resource Naming

- Cluster: `${var.project_prefix}-oke-cluster`
- VCN: `${var.project_prefix}-vcn`
- Compartment: `${var.project_prefix}`
- DNS label: `substr(var.project_prefix, 0, 15)`
<!-- END managed:styleguide-naming -->

<!-- BEGIN managed:styleguide-variables -->
## Variables

### Declaration Rules

- Every variable **must** have a `description`.
- Provide a `default` unless the value is tenancy-specific (e.g., OCIDs).
- Add `validation` blocks for variables with constrained values.
- Mark secrets with `sensitive = true`.

```hcl
variable "paperclip_exposure" {
  description = "Paperclip service exposure: 'public' (LoadBalancer) or 'private' (ClusterIP)"
  type        = string
  default     = "public"

  validation {
    condition     = contains(["public", "private"], var.paperclip_exposure)
    error_message = "paperclip_exposure must be 'public' or 'private'."
  }
}
```

### Grouping

Group variables in `variables.tf` with `###` comment headers:

```hcl
### Project Prefix
### OCI General
### OKE
### Paperclip (Agent Orchestration Platform)
### OpenClaw (Agent Runtime)
```
<!-- END managed:styleguide-variables -->

<!-- BEGIN managed:styleguide-outputs -->
## Outputs

- Every output **must** have a `description`.
- Mark sensitive outputs with `sensitive = true`.
- Use outputs for values the operator needs post-deploy (endpoints, commands, IDs).
- The `post_deploy_instructions` output provides a human-readable setup guide.
<!-- END managed:styleguide-outputs -->

<!-- BEGIN managed:styleguide-providers -->
## Provider Configuration

- Pin all provider versions with `=` constraints in `main.tf`.
- Document intentional exclusions (e.g., `hashicorp/kubernetes` is excluded due to K8s 1.36.x hangs).
- Use provider aliases only when necessary (e.g., `oci.home`, `helm.oke`).
- Never remove existing aliases — they may prevent provider cycles.
<!-- END managed:styleguide-providers -->

<!-- BEGIN managed:styleguide-related-docs -->
## Related Documentation

- [AGENTS.md](AGENTS.md) — AI agent safety rules and conventions
- [CONTRIBUTING.md](CONTRIBUTING.md) — Contribution workflow
- [ARCHITECTURE.md](ARCHITECTURE.md) — System architecture
<!-- END managed:styleguide-related-docs -->
