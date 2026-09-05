# Contributing

Thank you for considering a contribution.

## Workflow

1. Open a short-lived feature branch from `main`.
2. Keep one logical change per pull request.
3. Validate locally (`terraform fmt`, `terraform validate`, and
   `python3 tests/run-local.py`). The test runner uses mocked providers and
   isolates personal state and variables. Live plans and deployment checks
   are operator activities; keep feature validation local.
4. Describe what you changed, how you checked it, and any residual risk.
5. A merge updates `main`. It does not apply infrastructure.

Do not run `terraform apply` or `terraform destroy` against someone else's
tenancy. Cluster mutation is an operator action on their own account.

## What belongs here

This repository is public infrastructure code for an OCI OKE cluster and
optional agent runtimes. Keep it generic:

- No private company identity, product stacks, or proprietary harnesses.
- No secrets, real OCIDs, API keys, or Telegram user IDs.
- All user-facing docs and comments in English.

## Language and style

- Terraform: `terraform fmt -recursive src`
- Local setup: `terraform -chdir=src init -backend=false` downloads the
  required modules/providers; it does not apply infrastructure.
- Tests: `python3 tests/run-local.py` (Python 3 and initialized providers).
- Add-on versions: check `oci ce addon-option list` for the selected Kubernetes
  version before changing the pinned NativeIngressController or CertManager
  versions. This is read-only; add-on installation is an operator action.
- Docs: GitHub-flavored Markdown, complete sentences
- Prefer official CLIs and upstream images
