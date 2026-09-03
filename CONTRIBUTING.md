# Contributing

This infrastructure repository uses a local-first, release-tag workflow.

- Short feature branches target `main`.
- `main` is the integrated next version and may be ahead of the deployed state.
- Branch pushes, pull requests, and updates to `main` do not create remote
  pipelines, cloud previews, Terraform applies, or cluster changes.
- Run formatting, validation, tests, policy checks, and Terraform planning
  locally. Attach the relevant evidence to review.
- Reviewers return PASS or FAIL for the current SHA. Merge is integration, not
  deployment.
- The latest immutable stable SemVer tag is the source version corresponding to
  production. A release-candidate tag may run bounded remote validation only
  when local evidence cannot provide the required confidence.
- Any future release automation must build or validate once, promote immutable
  inputs, require explicit production approval, and report time and cloud cost.
- Infrastructure apply, destroy, rollback, credential rotation, or cluster
  mutation remains a separate founder-authorized action.

The critical question for any remote job is: what release confidence does it
buy that the local environment cannot provide? If none, remove it.
