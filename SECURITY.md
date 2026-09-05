# Security

This project targets **development and testing** of remote AI agents on
OCI, with configurable ARM resources. Defaults favor simplicity over a hardened
production posture.

## Do not commit

- `src/terraform.tfvars` (gitignored)
- Terraform state files
- API keys, OCIDs, Telegram user IDs, kubeconfigs, cookie jars

Copy `src/terraform.tfvars.example` and fill values locally.

## Known default risks

- `oci_control_plane_allowed_cidrs` is required. Use operator/VPN egress
  addresses; do not use `0.0.0.0/0` for an Internet-reachable API server.
- `oci_public_workers = true` in the example places nodes on public IPs.
- Application exposure defaults to private. Ingress exposes apps switched to
  public on HTTP unless their domains and
  `letsencrypt_email` are configured. DNS and successful ACME issuance are
  also required. Do not send credentials over public HTTP. Use private
  exposure and localhost port-forwarding until HTTPS is ready.
- OpenClaw and Qwen only receive an ingress when their own domains are
  configured. OpenCode public mode also requires a dedicated domain.
  Check its runtime authentication before exposing that hostname.
- LLM and registry tokens are stored as Kubernetes Secrets and may be
  present in Terraform state; `sensitive` hides output, not stored values.
- Backup read/write pre-authenticated URLs grant bucket-wide object access
  for their operation and expire on August 9, 2031. No object-retention policy
  or automatic restore verification is configured.
- The shared browser CDP endpoint is an internal control interface; keep it
  private. Kubernetes namespaces alone are not an isolation boundary for
  untrusted agent code, and this lab does not configure tenant isolation.

Public routes use the OCI Native Ingress Controller with an instance-principal
dynamic group and policy. The project compartment should remain dedicated to
this cluster because the matching rule includes every compute instance in that
compartment. Review the IAM statements and the
[migration and validation limits](docs/launch-readiness.md) before updating an
existing cluster.

## Reporting

Please open a private GitHub security advisory on this repository rather
than a public issue if you find a vulnerability that could expose running
clusters.
