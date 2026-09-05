# Repository promotion plan

Prepared on September 3, 2026. Status: step 1 complete; step 2 pending.

## Objective and positioning

Help relevant people discover, try, and contribute to this repository, and
increase GitHub stars through useful technical content and participation.

Position the project as a reproducible remote AI agent lab on OCI Kubernetes
Engine (OKE), with persistent workspaces, browser access, and configurable
infrastructure. Use the lab to introduce OCI and OKE as options for builders
evaluating infrastructure costs.

Present OKE as managed Kubernetes. Explain the distinction between hosting
agent runtimes and tools, and running model inference. Describe enterprise
relevance through architectural questions and future requirements. Keep the
current development/testing scope explicit.

Use a personal, practical voice: motivation, working examples, measured
results, trade-offs, and unresolved questions. Credit upstream projects.
Cost optimization is a design objective; avoid blanket claims of free
operation, superior pricing, production readiness, or unlimited scaling.

## Audience hypotheses

Prioritize situations of use rather than job titles:

1. People already using coding agents who want persistent remote environments
   and are comfortable operating containers and infrastructure.
2. Platform, infrastructure, and DevOps practitioners exploring agent runtime
   provisioning and operations.
3. Builders evaluating OCI/OKE for cost-conscious projects, including people
   familiar with Kubernetes on other providers.
4. Automation developers experimenting with code execution, browser tools,
   and supporting services.
5. People learning cloud and Kubernetes through a concrete agent workload.

Record which needs appear in actual questions and reproduction reports.
Treat this ordering as a hypothesis, not established audience research.

## Schedule and ownership

T0 is the actual publication time of the original article, recorded with
its timezone and URL. Republishing does not restart the clock. Preparation
has no fixed deadline; resolve material publication issues before setting T0.

The maintainer publishes and replies through their accounts. Codex can
prepare and review local artifacts. This document plans future actions; it
does not execute publications, create reminders, or authorize infrastructure
mutations. Any required cluster mutation needs the operator's exact action
authorization under AGENTS.md. Keep feature validation local.

| Order | Timing | Work | Completion criterion |
| --- | --- | --- | --- |
| 1 | Before launch | Check technical and cost claims | Claims have evidence or an explicit limitation; material issues are resolved |
| 2 | Before launch | Prepare the repository entry point | A visitor can understand the use case, see a demonstration, and find the first experiment |
| 3 | Before launch | Draft and review the original article | Accurate, useful article with inspectable sources and a reproducible example |
| 4 | Before launch | Prepare channel-specific posts and baseline | Drafts, destination rules, media, links, and measurement sheet are ready |
| 5 | T0 to T+6h | Publish and begin focused distribution | Original URL and timestamp recorded; DEV copy links to the canonical original |
| 6 | T0 to T+24h | Participate and correct | Questions and reproduction failures are triaged; material corrections are reflected in both copies |
| 7 | T+24h to T+48h | Publish on LinkedIn | At least 24 elapsed hours since T0, initial circulation completed, and no unresolved misleading claims |
| 8 | Days 3 to 7 | Expand distribution using new material | Each additional post has an audience-specific lesson or substantive update |
| 9 | Days 7 and 14 | Review outcomes | Results and next priorities recorded without unsupported causal attribution |

## 1. Verify the claims that support the launch

- [x] Review README claims against the Terraform configuration, especially
  deployment steps, TLS, database management, backups, and resource budgets.
- [x] Reconcile the README's 4 OCPU / 24 GB Always Free claim with current
  official documentation and the allowance applicable to the account type.
  The documentation inspected on September 3 lists 1,500 OCPU-hours and
  9,000 GB-hours monthly. Do not infer another account's allowance from a
  single existing deployment.
- [x] Separate OKE Basic cluster charges, workers, volumes, networking,
  backups, model APIs, and optional services. Check effective volume sizes,
  shared tenancy allowances, regional availability, and ARM compatibility.
- [x] Resolve the use of the retired community ingress-nginx controller
  before recommending this deployment path for Internet-facing access.
  Validate any replacement locally; live deployment requires separate,
  exact operator authorization.
- [x] Make HTTPS and access restrictions clear in the published walkthrough.
- [x] Select one real demonstration and distinguish observed behavior from
  configured features. If fresh deployment evidence is unavailable, say so.

Output: necessary focused repository changes and a claim/evidence list for
the article. Keep unrelated improvements outside this launch preparation.

## 2. Make the repository useful on first visit

- [ ] Rewrite the opening around the user's outcome and OCI/OKE exploration.
- [ ] Add a simple architecture diagram and one short demonstration
  (approximately 60-90 seconds, or an equivalent screenshot sequence).
- [ ] Document one first experiment: open a remote workspace, run a bounded
  agent task, and return to the saved workspace/session.
- [ ] Explain the prerequisites, cost boundaries, and when operating
  Kubernetes is a useful part of the exercise.
- [ ] Review repository description, relevant topics, and contribution paths.
- [ ] Add one restrained invitation to star the repository and share usage
  reports. Give readers a concrete question they can help answer.

Output: a clear README and reusable demonstration assets. Exclude secrets,
account identifiers, and private project data from all public media.

## 3. Write the article

Working title: **Building a Remote AI Agent Lab on OCI Kubernetes Engine**.

Publish the original in English on Hashnode. Prepare an English DEV.to copy
with canonical_url pointing to the original. Use Portuguese for the initial
LinkedIn post and Portuguese-speaking communities; adapt if the maintainer
chooses another language.

Outline:

1. The personal motivation: remote agent experiments and attention to cost.
2. A demonstrated outcome before the infrastructure details.
3. How the runtimes, tools, persistence, and access fit together.
4. Why OCI and OKE were chosen, and the relevant trade-offs.
5. The first experiment and a link to maintained setup instructions.
6. The cost breakdown, separating measured spend from estimates and limits.
7. Lessons, constraints, and what a larger platform would need.
8. Repository link, a specific feedback question, and a brief star invitation.

Output: a reviewed article and a cross-publication copy. Link the repository
near the first concrete example and again at the end. Do not invent results,
bill totals, user adoption, or comparative savings.

## 4. Prepare distribution before publication

Create a draft for each selected destination, with its intended audience,
technical takeaway, feedback question, and article/repository links.

| Destination | Reason to participate | Publication approach |
| --- | --- | --- |
| Paperclip and OpenCode communities | Existing users may need a remote deployment | Show the relevant runtime experience in an appropriate community channel |
| OCI community / r/oraclecloud | Builders evaluating OCI infrastructure and costs | Explain a concrete OKE/ARM/networking decision and its limits |
| r/kubernetes | Practitioners interested in runtime operations | Use the current project-sharing thread where appropriate; share technical lessons |
| r/devops | Infrastructure practitioners | Use the current weekly self-promotion thread |
| CNCF local groups | Hands-on cloud-native learning | Offer a short walkthrough through the group's normal contribution process |
| LinkedIn | The maintainer's professional network | Publish after the 24-hour minimum, with the personal motivation and architectural lessons |

Check current rules and permitted channels immediately before posting.
State authorship. Choose two high-affinity communities for the first wave;
prepare others for later. Avoid identical mass posts and repeated link drops.

Prepare a lightweight local measurement sheet: timestamp, channel, published
URL, repository stars, available traffic/clones, article views, questions,
attempted deployments, and reported successful use. Record a baseline just
before T0. Use source tags on article links where supported. Do not equate
blog views with unique readers across platforms or claim precise star
attribution without evidence.

## 5-7. Launch, participate, then publish on LinkedIn

- [ ] Record the baseline and publish the Hashnode original; record T0.
- [ ] Publish the DEV.to copy after checking the canonical URL.
- [ ] Begin circulation in two selected communities during the first six
  hours and remain available for replies.
- [ ] Through the first 24 hours, answer questions, record friction, and
  correct the article and repository when warranted.
- [ ] At or after T+24h, review readiness for LinkedIn. A T+24h to T+48h window
  provides flexibility; no claim is made that it optimizes an algorithm.
- [ ] Publish a native LinkedIn post with the personal motivation, a visual,
  two or three technical lessons, the article link, and a discussion prompt.
  Include early community feedback only if it actually occurred.

The LinkedIn post must never precede T0 + 24 hours. If the first wave did not
happen or a material correction remains unresolved, postpone it. Lack of
comments alone is not a reason to delay or invent social proof. A native
LinkedIn article is optional later; the initial plan uses a post linking to
the original article.

## 8-9. Extend useful discussion and review results

Between days 3 and 7, reach the remaining appropriate communities using a
different demonstrated lesson, an answer to a recurring question, or a
substantive improvement. Consider Show HN only when the repository is easy
to try; submit the runnable project rather than presenting a blog post as a
Show HN. Do not solicit coordinated votes.

Capture results at T+24h, T+72h, day 7, and day 14 when available. These are
planned manual checkpoints, not scheduled automation.

Evaluate stars gained alongside repository visits, available clones,
attempted/successful reproductions, useful questions, issues, and
contributions. Treat forks and clones as interest signals, not proof of use.
Avoid a numeric star promise before collecting a baseline.

Use the evidence to choose the next step:

- Reproduction failures: improve setup and documentation first.
- Cost questions: prepare a follow-up using observed OCI billing data.
- Remote-workspace interest: improve that demonstration and walkthrough.
- Platform-engineering interest: explain the additional requirements for
  isolation, identity, observability, and operational governance.

## Sources and publication references

Recheck time-sensitive facts and community rules before publication.

- [OCI Always Free resources](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)
- [OKE pricing](https://www.oracle.com/dk/cloud/cloud-native/kubernetes-engine/pricing/)
- [OKE Basic and Enhanced comparison](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengcomparingenhancedwithbasicclusters_topic.htm)
- [Community ingress-nginx retirement](https://kubernetes.github.io/ingress-nginx/)
- [DEV editor and canonical URL](https://dev.to/p/editor_guide)
- [Paperclip community](https://github.com/paperclipai/paperclip#community)
- [OpenCode community entry point](https://opencode.ai/)
- [Example Kubernetes project-sharing thread](https://www.reddit.com/r/kubernetes/comments/1vg306r/weekly_show_off_your_new_tools_and_projects_thread/)
- [DevOps weekly thread, August 31, 2026](https://www.reddit.com/r/devops/comments/1w35jph/weekly_self_promotion_thread/)
- [CNCF Cloud Native Campinas](https://community.cncf.io/cloud-native-campinas/)
- [Show HN guidelines](https://news.ycombinator.com/showhn.html)

## Execution checkpoint

- Completed: ordered plan, positioning, deliverables, and timing rule.
- Completed: step 1 claim review and focused corrections; see
  `docs/launch-readiness.md` for evidence and migration limits.
- Verification: Terraform format/validate and eight provider-mocked plan
  scenarios covering OCI Native Ingress, OKE CertManager, IAM, TLS, and the
  application exposure rules. Live controller behavior remains pending.
- Current: no cluster, registry, or publication mutation was performed.
- Next: step 2, prepare the repository entry point and real demonstration.
- Pending: all launch preparation, public posts, and outcome measurements.
