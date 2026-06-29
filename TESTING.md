# TESTING.md — Validation and Testing Strategy

<!-- BEGIN managed:testing-overview -->
## Overview

This Terraform project has no automated test suite. The strategy below follows the **Testing Trophy** model: integration tests (plan validation) as the primary confidence layer, end-to-end tests for critical deployment paths, and unit tests as selective and secondary.

For a Terraform infrastructure project, "tests" map to:
- **Static checks** — formatting, linting, security scanning (fast feedback)
- **Plan validation** — `terraform plan` as integration test (does the config produce expected resources?)
- **End-to-end** — full `terraform apply` + smoke tests against the live cluster
<!-- END managed:testing-overview -->

<!-- BEGIN managed:testing-static-checks -->
## Static Checks (Run Every Change)

These are fast, local, and should run before every commit.

### Format Check
```bash
cd src && terraform fmt -check -recursive
```
Verifies all `.tf` files follow canonical formatting. Fix with `cd src && terraform fmt -recursive`.

### Validation
```bash
cd src && terraform validate
```
Checks syntax, provider schema conformance, and variable references without contacting OCI.

### Recommended: TFLint
```bash
tflint --init
tflint
```
Catches deprecated attributes, invalid instance types, and provider-specific issues. Add a `.tflint.hcl` at the repo root:

```hcl
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
```

### Recommended: Security Scanning
```bash
# Checkov
checkov -d . --framework terraform

# tfsec
tfsec .
```
Scans for misconfigurations (open security groups, unencrypted resources, missing tags).
<!-- END managed:testing-static-checks -->

<!-- BEGIN managed:testing-plan-validation -->
## Plan Validation (Integration Layer)

Plan validation is the primary confidence layer for Terraform changes.

### Basic Plan Review
```bash
cd src && terraform plan -out=tfplan
terraform show -json tfplan | jq '.resource_changes[] | {address, change}'
```

### What to Verify in a Plan

1. **No unexpected destructions** — scan for `"delete"` or `"destroy"` actions on stateful resources.
2. **Resource count matches expectations** — conditional resources (`count = var.enable_*`) should appear or not based on toggle state.
3. **Variable validation fires** — test with invalid values to confirm `validation` blocks catch bad input:
   ```bash
   cd src && TF_VAR_project_prefix="BAD!" terraform plan  # Should fail validation
   ```
4. **Provider versions are correct** — verify lock file matches `src/main.tf` constraints.

### Targeted Plans for Isolated Changes
```bash
cd src && terraform plan -target=helm_release.openclaw_operator
```
Use targeted plans when modifying a single workload to reduce blast radius during review.
<!-- END managed:testing-plan-validation -->

<!-- BEGIN managed:testing-e2e -->
## End-to-End Validation (Critical Paths)

Run after a full `terraform apply` to verify the deployment is functional.

### Cluster Health
```bash
kubectl get nodes                    # All nodes Ready
kubectl get pods -A                  # No CrashLoopBackOff or ImagePullBackOff
kubectl top nodes                    # Within Free Tier budget
```

### NGINX Ingress + LoadBalancer
```bash
kubectl get svc -n ingress-nginx     # nginx-ingress-ingress-nginx-controller has external IP
curl -s http://<INGRESS_IP>/         # Returns 404 (no default backend) — Ingress is reachable
```

### cert-manager Verification
```bash
kubectl get pods -n cert-manager     # All pods Running
kubectl get clusterissuer            # letsencrypt-prod status is Ready (if letsencrypt_email is set)
```

### Paperclip Smoke Test
```bash
kubectl get svc -n paperclip          # paperclip is ClusterIP (behind NGINX Ingress)
kubectl get ingress -n paperclip      # paperclip Ingress exists, hostname set
kubectl get pods -n paperclip         # All pods Running (paperclip + paperclip-db-0)
curl -s -H "Host: <DOMAIN>" http://<INGRESS_IP>/ | head -20  # Returns HTML (Paperclip UI)
# Or if no custom domain, access via IP directly via Ingress
```

### TLS Certificate Verification (with custom domain)
```bash
kubectl get certificate -n paperclip  # paperclip-tls shows Ready=True
kubectl describe certificate paperclip-tls -n paperclip | grep "The certificate has been successfully issued"
curl -v https://<DOMAIN>/ 2>&1 | grep "SSL certificate verify ok"
```

### OpenClaw Smoke Test
```bash
kubectl get pods -n openclaw         # OpenClaw pod Running
kubectl logs -n openclaw -l app.kubernetes.io/name=openclaw --tail=20  # No fatal errors
```

### OpenCode Web Smoke Test
```bash
kubectl get pods -n opencode          # OpenCode pod Running
kubectl get pvc -n opencode             # OpenCode PVC Bound
kubectl get ingress -n opencode         # OpenCode Ingress exists, rules set
kubectl get svc -n opencode             # OpenCode service is ClusterIP (:80)
# When exposed publicly:
curl -s -H "Host: <DOMAIN>" http://<INGRESS_IP>/opencode/ | head -20  # Returns HTML (OpenCode Web UI)
# Or if no custom domain, access via IP directly via Ingress path
curl -s http://<INGRESS_IP>/opencode/ | head -20
# Basic Auth test
curl -s -u opencode:<PASSWORD> http://<INGRESS_IP>/opencode/ | head -20  # Returns HTML (password = terraform output -raw opencode_admin_password)
```

### Operator CRD Verification
```bash
kubectl get crd | grep openclaw      # OpenClaw CRDs registered
kubectl get openclawinstances.openclaw.rocks -n openclaw  # Instance CR created
```
<!-- END managed:testing-e2e -->

<!-- BEGIN managed:testing-common-scenarios -->
## Common Test Scenarios

### Adding a New Workload

1. Run `cd src && terraform validate` — config is syntactically correct.
2. Run `cd src && terraform plan` — new resources appear, nothing unexpected changes.
3. Run `cd src && terraform apply -target=<new_resource>` — workload deploys.
4. Run e2e smoke tests for the new workload.
5. Run full `cd src && terraform plan` — no drift from the targeted apply.

### Toggling a Workload Off

```bash
TF_VAR_enable_paperclip=false terraform plan
```
Verify:
- Paperclip resources show `"delete"` actions.
- No other resources are affected.
- OKE cluster and other workloads remain untouched.

### Provider Version Bump

1. Update version in `src/main.tf`.
2. Run `cd src && terraform init -upgrade`.
3. Run `cd src && terraform plan` — should show no resource changes (only provider metadata).
4. If plan shows resource changes, investigate before applying.
<!-- END managed:testing-common-scenarios -->

<!-- BEGIN managed:testing-known-limitations -->
## Known Limitations

- **No Terratest suite** — Go-based integration tests are not set up. Consider adding them for CI pipelines.
- **No state locking** — local state only. Remote backend (OCI Object Storage) is recommended for team use.
- **`kubectl_manifest` plan drift** — The kubectl provider's YAML round-trip adds K8s-managed fields to state. This is expected and stabilizes after one apply cycle. Do not treat it as a test failure.
<!-- END managed:testing-known-limitations -->

<!-- BEGIN managed:testing-related-docs -->
## Related Documentation

- [CONTRIBUTING.md](CONTRIBUTING.md) — Contribution workflow including validation steps
- [AGENTS.md](AGENTS.md) — Safety rules for AI agents
- [SECURITY.md](SECURITY.md) — Security scanning and hardening
<!-- END managed:testing-related-docs -->
