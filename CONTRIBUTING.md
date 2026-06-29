# CONTRIBUTING.md — Contribution Guidelines

<!-- BEGIN managed:contributing-overview -->
## Overview

This project deploys an OCI Free Tier OKE cluster with Paperclip, OpenClaw, and OpenCode Web. Contributions should preserve the Free Tier resource budget and the single-command deployment model.
<!-- END managed:contributing-overview -->

<!-- BEGIN managed:contributing-workflow -->
## Contribution Workflow

### Branching

- Use feature branches off `main`: `feat/<description>`, `fix/<description>`, `chore/<description>`.
- Keep branches short-lived and squash-merge when complete.

### Commit Messages

Use imperative, lowercase subject lines:

```
feat: add monitoring stack with Prometheus and Grafana
fix: increase CRD readiness sleep to 60s for paperclip
chore: bump OKE module to 5.4.4
```

Include a body when the *why* is non-obvious. Reference the problem being solved, not just the change.

### Pull Requests

1. Run `terraform fmt -recursive` and `terraform validate` before opening a PR.
2. Include `terraform plan` output in the PR description for any resource changes.
3. Call out Free Tier budget impact (CPU, memory, storage) if adding workloads.
4. Update `terraform.tfvars.example` if adding new variables.
5. Update `README.md` if changing architecture, variables, or deployment steps.
<!-- END managed:contributing-workflow -->

<!-- BEGIN managed:contributing-development-setup -->
## Development Setup

### Prerequisites

- [Terraform](https://www.terraform.io/downloads) ≥ 1.14
- [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm) configured with valid credentials
- [Python 3](https://www.python.org/) (for external data source scripts)
- [kubectl](https://kubernetes.io/docs/tasks-tools/) for cluster management
- [Docker](https://docs.docker.com/engine/install/) for building and pushing images (e.g., OpenCode Web)

### Local Configuration

```bash
cp terraform.tfvars.example src/terraform.tfvars
# Edit src/terraform.tfvars with your OCI tenancy details
cd src
terraform init
```

### Deployment

```bash
cd src
terraform apply
```

A single apply handles the entire deployment including compartment creation.
<!-- END managed:contributing-development-setup -->

<!-- BEGIN managed:contributing-adding-workloads -->
## Adding New Kubernetes Workloads

For operator-based workloads, follow this pattern:

1. **Create `<workload>.tf`** with these sections (in order):
   - Operator Helm release (`helm_release`)
   - CRD readiness delay (`time_sleep`, 30s minimum)
   - Namespace (`kubectl_manifest`)
   - Secrets (`kubectl_manifest` with `stringData`)
   - Instance CRD (`kubectl_manifest`)

For direct deployments (no operator), follow the `paperclip.tf` or `opencode.tf` pattern:
   - Namespace, secrets, Deployment/StatefulSet, Service, Ingress
   - For Docker-built images (like OpenCode), also include `docker_image` + `docker_registry_image` resources

For infrastructure components (ingress, TLS, monitoring), follow these patterns:
   - `ingress.tf` — NGINX Ingress Controller Helm release, wait-for-LB time_sleep, Ingress resource, IP detection data source
   - `cert-manager.tf` — Helm release, CRD readiness sleep, ClusterIssuer CRD

2. **Add variables** to `variables.tf`:
   - `enable_<workload>` toggle (bool, default `true`)
   - Config variables with descriptions and sensible defaults

3. **Add outputs** to `output.tf` (namespace, relevant endpoints).

4. **Update** `terraform.tfvars.example` with commented-out entries.

5. **Verify** the full plan: `terraform plan` should show no unexpected changes.

See `openclaw.tf` (operator pattern) and `paperclip.tf` (direct deployment) as reference implementations.
<!-- END managed:contributing-adding-workloads -->

<!-- BEGIN managed:contributing-resource-budget -->
## Free Tier Resource Budget

All contributions must stay within OCI Free Tier limits:

| Resource | Limit |
|---|---|
| ARM Compute (A1.Flex) | 4 OCPUs, 24 GB RAM |
| Block Volume | 200 GB |
| Load Balancers | 1 free (via OKE) |

Run `kubectl top nodes` and `kubectl top pods -A` after deployment to verify headroom.
<!-- END managed:contributing-resource-budget -->

<!-- BEGIN managed:contributing-related-docs -->
## Related Documentation

- [AGENTS.md](AGENTS.md) — AI agent context and safety rules
- [STYLEGUIDE.md](STYLEGUIDE.md) — Terraform formatting and naming rules
- [TESTING.md](TESTING.md) — Validation and testing strategy
- [SECURITY.md](SECURITY.md) — Security model and hardening checklist
- [ARCHITECTURE.md](ARCHITECTURE.md) — System architecture and component layout
<!-- END managed:contributing-related-docs -->
