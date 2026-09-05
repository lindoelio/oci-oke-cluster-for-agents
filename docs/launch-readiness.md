# Technical and cost claim review

Review date: September 4, 2026. Scope: promotion plan, step 1.
Baseline: commit `6e4bbe8`; reviewed changes are on
`codex/verify-launch-claims`.

## Evidence boundaries

This review covers repository configuration, current official documentation,
read-only inspection of the operator's existing OKE cluster, and
provider-mocked Terraform plans. It does not establish a fresh deployment,
the contents of an OCI bill, regional capacity, backup recovery, or production
readiness. No cluster apply, destroy, image publication, or public announcement
was performed.

The running cluster currently exposes the configured applications through an
older ingress-nginx Helm release and uses a Helm-installed cert-manager. The
code now describes OCI Native Ingress and the OKE CertManager add-on. That is a
pending migration, not the observed live state.

## Claims and corrections

| Claim | Evidence | Repository boundary |
| --- | --- | --- |
| One apply stands up the entire environment | OpenCode and Qwen images are built locally but have no registry-push resource | Registry publication and application onboarding remain explicit preparation steps. Fresh apply success is still unverified. |
| 4 OCPUs / 24 GB makes the stack free | OCI publishes account-specific A1 allowances, while storage, networking, backup, domains, and model APIs are separate | Describe this as a cost-oriented lab configuration, never as a guaranteed free stack. |
| The storage defaults fit Always Free | Two 50 GB boot volumes plus four 50 GB application volumes total at least 300 GB; Qwen adds another volume | Default PVC requests follow OCI's 50 GB minimum, but exceed the shared 200 GB boot/block allowance as a complete stack. |
| Kubernetes includes an ingress implementation | Kubernetes defines the Ingress API but requires a controller data plane | Use the OKE-managed OCI Native Ingress Controller add-on. No ingress-nginx or Traefik release remains in the code. |
| OCI Native Ingress requires OKE Enhanced | Basic clusters can use instance-principal authentication; workload identity requires Enhanced | Keep `cluster_type = "basic"`, create a worker dynamic group and policy, and set `authType = "instance"`. |
| Managed add-ons make ingress free | Oracle does not list a separate add-on meter; controller pods consume workers and managed OCI resources retain their normal pricing | Keep the flexible LB at 10 Mbps and account for shared tenancy allowances. Add-on management alone does not prove a zero bill. |
| A domain automatically enables HTTPS | DNS, ACME email, HTTP-01 reachability, certificate issuance, and listener reconciliation all have to succeed | Install the OKE CertManager add-on whenever public ingress is enabled; create the ClusterIssuer and TLS entries only when `letsencrypt_email` is set. |
| One HTTPS listener accepts all app certificates everywhere | Native Ingress v1.4.5 can aggregate multiple TLS secrets, but regions without multi-certificate listener support return a reconciliation error | Verify the target region. A single wildcard/SAN certificate is the safer fallback when several hosts share port 443. |
| Path prefixes work as they did with NGINX | OCI Native Ingress does not implement the former regex rewrite annotations | Paperclip can own the hostless root; OpenCode, OpenClaw, and Qwen public routes require dedicated domains. |
| Qwen authentication belongs in ingress annotations | OCI Native Ingress does not implement NGINX `auth-url` | Put Basic/Bearer handling in the Qwen gateway Service so the security boundary survives the controller change. |
| Daily backups protect all persistent data | Only PostgreSQL, Paperclip files, and OpenCode files have jobs; there is no retention or restore test | Publish exact scope and keep OpenClaw/Qwen recovery, consistency, and retention as open work. |
| The default resource table is a measured capacity result | It lists selected container limits and omits simultaneous peaks and system overhead | Treat it as configuration, measure real idle and active usage, and do not infer capacity for heavy agent workloads. |

## OCI Native Ingress design

The repository creates these resources only when at least one public route is
enabled:

1. An OKE `CertManager` add-on, pinned to `v1.20.3`.
2. A tenancy-level dynamic group matching compute instances in the dedicated
   project compartment, plus the service policy required by the controller.
3. An OKE `NativeIngressController` add-on, pinned to `v1.4.5`, using instance
   principal authentication.
4. An `IngressClassParameters` object with a public subnet and flexible Load
   Balancer bandwidth fixed at 10 Mbps.
5. The `oci-native` IngressClass and application routes.

HTTP application routes declare listener 80 only when TLS is not configured.
TLS application routes declare listener 443 and omit the HTTP listener. The
ClusterIssuer's temporary HTTP-01 solver Ingress explicitly owns listener 80,
so certificate validation does not depend on backend Service port defaults.

The add-on pins were returned as active options for OKE 1.36 by the OCI API on
the review date. They remain time-sensitive. Check supported options again
before planning a later deployment.

The policy includes tenancy-scoped read/manage permissions for public and
floating IPs because Oracle's controller prerequisites specify those scopes.
Other service permissions are limited to the project compartment. The dynamic
group matches all compute instances in that compartment, so the compartment
must remain dedicated to this OKE environment.

## Cost boundary

OKE Basic has no control-plane management charge. The add-ons have no separate
price item in the consulted Oracle price list, but their pods use the worker's
CPU and memory. The controller provisions an OCI Load Balancer and can create
OCI Certificates resources from Kubernetes TLS secrets.

Always Free currently lists one flexible Load Balancer at 10 Mbps, 150
certificates, and 5 certificate authorities. These are shared tenancy
allowances. A fresh deployment with no competing eligible resource can fit the
LB configuration within that allowance. The repository cannot confirm the
operator's remaining quota or future billing policy.

The complete default stack still exceeds the shared block-volume allowance.
Therefore, replacing the ingress controller reduces third-party maintenance;
it does not make the full repository free.

## Local validation

The local runner copies tracked Terraform sources into a temporary directory,
excludes personal tfvars and state, and mocks all providers plus the OKE module.
It does not call OCI, build images, run provisioners, or mutate Kubernetes.

```bash
terraform -chdir=src init -backend=false
terraform fmt -check -recursive src
terraform -chdir=src validate
python3 tests/run-local.py
```

Eight mocked plan scenarios cover public HTTP, private applications, domains
without ACME, all-app HTTPS, Qwen-only public and private modes, invalid public
OpenCode configuration, and invalid API CIDRs. Assertions cover both managed
add-ons, Basic-cluster IAM configuration, the 10 Mbps Load Balancer bounds,
OCI Native annotations, Qwen's in-service authentication, effective passwords,
RWO backup affinity, and storage defaults.

These checks establish Terraform structure under synthetic inputs. They do not
establish add-on readiness, IAM propagation, real Load Balancer reconciliation,
HTTP-01 issuance, application behavior, or region support for several
certificates on one listener.

## Existing deployment migration

Do not apply this branch as a one-step upgrade to the current cluster. The live
cluster has working ingress-nginx routes and a Helm-managed cert-manager that
would overlap with the OKE add-on.

A controlled migration needs a separately reviewed plan:

1. Export the current Ingress, Issuer, Certificate, Secret ownership, Helm
   release, DNS, and Load Balancer details. Record rollback inputs.
2. Resolve cert-manager ownership before enabling the OKE add-on. Do not let
   Helm and OKE manage the same CRDs, namespaces, or deployments concurrently.
3. Install and validate the add-ons and IAM, then create the OCI Native class.
4. Verify each hostname, HTTP-01 route, certificate, authentication flow,
   streaming request, and application health before changing DNS.
5. Move DNS and remove the previous controller only after the new endpoint is
   verified.

There is a direct cost/availability tradeoff. A low-downtime migration keeps
the old and new Load Balancers alive together and can temporarily exceed the
one-LB free allowance. Staying strictly within one LB requires a cutover window
and likely downtime while the old LB is removed and the new one receives its
public IP. The operator must choose that migration mode before any live action.

Other existing-deployment constraints still apply:

- Inspect the Kubernetes 1.36.1 control-plane and node-pool upgrade separately.
- Do not recreate PostgreSQL or PVC resources to align older claim sizes with
  current defaults. StatefulSet claim templates are not normally mutable.
- Set `oci_control_plane_allowed_cidrs` to operator or VPN egress CIDRs before
  planning.
- Preserve application-specific values and secrets; a fresh default plan is
  not a migration plan.

AGENTS.md requires exact operator authorization for apply, destroy, or any
cluster mutation. This work contains code and local evidence only.

## Demonstration selected for the article

Open an OpenCode remote workspace over trusted HTTPS, execute one bounded task
with synthetic project data, close the browser, reopen the workspace, and
confirm that files and session state remain. Capture image digests,
configuration, date, observed resource use, and limitations.

Status: selected, not yet executed against the OCI Native Ingress path. It
cannot be presented as migration or fresh-deployment evidence until that path
is authorized and observed.

## Sources

Official sources consulted on September 4, 2026:

- [Oracle Cloud price list](https://www.oracle.com/cloud/price-list/)
- [Always Free resources](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)
- [OCI Native Ingress add-on prerequisites](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengsettingupnativeingresscontroller-addon-prereqs.htm)
- [Configure the OCI Native Ingress add-on](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengsettingupnativeingresscontroller-configuring.htm)
- [Create OCI Native Ingress resources](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengsettingupnativeingresscontroller-createresources.htm)
- [OKE supported add-on versions](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengconfiguringclusteraddons-supportedversions.htm)
- [OCI Native Ingress controller reference](https://github.com/oracle/oci-native-ingress-controller/blob/main/GettingStarted.md)
- [OKE Block Volume PVC minimum](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengcreatingpersistentvolumeclaim_topic-Provisioning_PVCs_on_BV.htm)
- [OKE supported Kubernetes versions](https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengaboutk8sversions.htm)

## Execution checkpoint

- Completed: source and live read-only review, cost reconciliation, OCI Native
  Ingress and OKE CertManager Terraform implementation, and eight mocked plan
  scenarios.
- Current: step 1 code is revised; the new ingress path has not been applied or
  demonstrated on OCI.
- Pending external evidence: migration or fresh deployment, actual account
  billing, demonstration recording, and restore exercise.
