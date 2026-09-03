# Agent notes

This repository provisions an OCI OKE cluster and optional agent runtimes
(Paperclip, OpenClaw, OpenCode Web, Qwen Code). It is public infrastructure
code.

- Treat Terraform and OCI configuration as production-sensitive.
- Never apply, destroy, or mutate a cluster unless the operator explicitly
  authorizes that exact action.
- Keep feature validation local. A branch, pull request, or `main` update
  must not create remote builds or infrastructure previews.
- Do not add private company identity, product stacks, or proprietary
  harnesses.
- Write docs and comments in English.
