# Security

This project targets **development and testing** of remote AI agents on the
OCI Always Free tier. Defaults favor simplicity and cost over a hardened
production posture.

## Do not commit

- `src/terraform.tfvars` (gitignored)
- Terraform state files
- API keys, OCIDs, Telegram user IDs, kubeconfigs, cookie jars

Copy `src/terraform.tfvars.example` and fill values locally.

## Known default risks

- The Kubernetes API server allowlist is `0.0.0.0/0` unless you change
  `control_plane_allowed_cidrs` in `oke.tf`.
- `oci_public_workers = true` in the example places nodes on public IPs.
- Ingress can expose Paperclip, OpenCode Web, and Qwen Code on HTTP until
  you set custom domains and `letsencrypt_email`.
- LLM and registry tokens are stored as Kubernetes Secrets.

## Reporting

Please open a private GitHub security advisory on this repository rather
than a public issue if you find a vulnerability that could expose running
clusters.
