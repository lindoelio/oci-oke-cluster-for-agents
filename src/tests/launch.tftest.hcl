# All providers are mocked. The local runner copies tracked inputs into an
# isolated directory so personal tfvars, state, and credentials are absent.
mock_provider "oci" {}
mock_provider "oci" { alias = "home" }
mock_provider "helm" {}
mock_provider "helm" { alias = "oke" }
mock_provider "kubectl" {}
mock_provider "docker" {}
mock_provider "cloudinit" {}
mock_provider "local" {}
mock_provider "null" {}
mock_provider "time" {}
mock_provider "random" {}
mock_provider "external" {
  mock_data "external" {
    defaults = {
      result = {
        cluster_id = "test-cluster"
        token      = "test-token"
        ip         = "192.0.2.10"
      }
    }
  }
}

override_module {
  target = module.oke
  outputs = {
    pub_lb_subnet_id = "ocid1.subnet.oc1.test.native"
    pub_lb_nsg_id    = "ocid1.networksecuritygroup.oc1.test.native"
  }
}

variables {
  oci_tenancy_id                  = "ocid1.tenancy.oc1..test"
  oci_compartment_id              = "ocid1.compartment.oc1..test"
  oci_control_plane_allowed_cidrs = ["203.0.113.10/32"]
  opencode_registry_namespace     = "test-only"
  enable_openclaw                 = true
  enable_opencode                 = true
  paperclip_exposure              = "public"
  opencode_exposure               = "private"
}

run "public_ip_lab" {
  command = plan

  assert {
    condition     = length(helm_release.cert_manager) == 1 && length(helm_release.native_ingress) == 1
    error_message = "Public ingress on a Basic cluster must use cert-manager and OCI Native Ingress Helm releases."
  }
  assert {
    condition     = kubectl_manifest.native_ingress_class[0].manifest.spec.controller == "oci.oraclecloud.com/native-ingress-controller" && kubectl_manifest.native_ingress_parameters[0].manifest.spec.minBandwidthMbps == 10 && kubectl_manifest.native_ingress_parameters[0].manifest.spec.maxBandwidthMbps == 10
    error_message = "OCI Native Ingress must own the class and keep the Load Balancer at 10 Mbps."
  }
  assert {
    condition     = kubectl_manifest.paperclip_ingress[0].manifest.spec.ingressClassName == "oci-native" && length(kubectl_manifest.paperclip_ingress[0].manifest.spec.tls) == 0 && kubectl_manifest.paperclip_ingress[0].manifest.metadata.annotations["oci-native-ingress.oraclecloud.com/http-listener-port"] == "80"
    error_message = "The IP-only Paperclip route must use OCI Native Ingress without claiming TLS."
  }
  assert {
    condition     = length(kubectl_manifest.openclaw_ingress) == 0 && length(kubectl_manifest.opencode_ingress) == 0
    error_message = "Applications without hostnames must not compete for the hostless root route."
  }
  assert {
    condition     = kubectl_manifest.backup_cronjob[0].manifest.spec.jobTemplate.spec.template.spec.affinity.podAffinity.requiredDuringSchedulingIgnoredDuringExecution[0].labelSelector.matchLabels.app == "paperclip"
    error_message = "RWO backups must run on the same node as the PVC consumer."
  }
  assert {
    condition     = var.paperclip_db_storage_size == "50Gi" && var.paperclip_storage_size == "50Gi" && var.openclaw_storage_size == "50Gi" && var.opencode_storage_size == "50Gi" && var.qwen_storage_size == "50Gi"
    error_message = "Default PVC requests must meet the documented OCI minimum."
  }
}

run "private_apps" {
  command = plan
  variables {
    paperclip_exposure = "private"
    opencode_exposure  = "private"
  }
  assert {
    condition     = length(helm_release.cert_manager) == 0 && length(helm_release.native_ingress) == 0 && length(data.external.ingress_ip) == 0
    error_message = "Private applications must not install ingress controllers or create a public Load Balancer."
  }
  assert {
    condition     = output.opencode_public_url == null && output.paperclip_url == null
    error_message = "Private applications must not advertise public URLs."
  }
}

run "domains_without_email" {
  command = plan
  variables {
    paperclip_custom_domain = "paperclip.example.test"
    opencode_exposure       = "public"
    opencode_custom_domain  = "opencode.example.test"
    openclaw_custom_domain  = "openclaw.example.test"
    opencode_admin_password = "explicit-test-password"
    paperclip_public_url    = "http://proxy.example.test"
    enable_qwen             = true
    qwen_custom_domain      = "qwen.example.test"
  }
  assert {
    condition     = output.opencode_public_url == "http://opencode.example.test" && output.paperclip_url == "http://proxy.example.test"
    error_message = "Hostnames without an ACME account must advertise HTTP."
  }
  assert {
    condition     = length(kubectl_manifest.paperclip_ingress[0].manifest.spec.tls) == 0 && length(kubectl_manifest.opencode_ingress[0].manifest.spec.tls) == 0 && length(kubectl_manifest.openclaw_ingress[0].manifest.spec.tls) == 0 && !can(kubectl_manifest.qwen_ingress[0].manifest.spec.tls) && length(kubectl_manifest.letsencrypt_issuer) == 0
    error_message = "Ingresses must not request TLS when no ACME email is configured."
  }
  assert {
    condition     = output.opencode_admin_password == "explicit-test-password"
    error_message = "The output password must match the operator-supplied Secret value."
  }
}

run "https_all_apps" {
  command = plan
  variables {
    paperclip_custom_domain = "paperclip.example.test"
    opencode_exposure       = "public"
    opencode_custom_domain  = "opencode.example.test"
    openclaw_custom_domain  = "openclaw.example.test"
    enable_qwen             = true
    qwen_custom_domain      = "qwen.example.test"
    letsencrypt_email       = "operator@example.test"
    oci_native_shared_certificate_ocid = "ocid1.certificate.oc1.test.shared"
  }
  assert {
    condition     = length(helm_release.cert_manager) == 1 && length(kubectl_manifest.letsencrypt_issuer) == 1 && kubectl_manifest.letsencrypt_issuer[0].manifest.spec.acme.solvers[0].http01.ingress.ingressClassName == "oci-native" && kubectl_manifest.letsencrypt_issuer[0].manifest.spec.acme.solvers[0].http01.ingress.ingressTemplate.metadata.annotations["oci-native-ingress.oraclecloud.com/http-listener-port"] == "80"
    error_message = "cert-manager and its HTTP-01 solver must use OCI Native Ingress."
  }
  assert {
    condition = alltrue([
      for route in [kubectl_manifest.paperclip_ingress[0], kubectl_manifest.opencode_ingress[0], kubectl_manifest.openclaw_ingress[0], kubectl_manifest.qwen_ingress[0]] :
      route.manifest.spec.ingressClassName == "oci-native" &&
      route.manifest.metadata.annotations["oci-native-ingress.oraclecloud.com/backend-tls-enabled"] == "false" &&
      route.manifest.metadata.annotations["oci-native-ingress.oraclecloud.com/https-listener-port"] == "443" &&
      !contains(keys(route.manifest.metadata.annotations), "oci-native-ingress.oraclecloud.com/http-listener-port")
    ])
    error_message = "All HTTPS routes must share the OCI Native listener and terminate TLS at the Load Balancer."
  }
  assert {
    # tolist() because the provider returns manifest values with dynamic
    # collection types; a bare tuple literal compares unequal to them.
    # The qwen route omits the tls key entirely in shared-listener mode,
    # so a missing attribute also satisfies "no TLS of its own".
    condition     = length(kubectl_manifest.paperclip_ingress[0].manifest.spec.tls) == 1 && length(kubectl_manifest.opencode_ingress[0].manifest.spec.tls) == 0 && length(kubectl_manifest.openclaw_ingress[0].manifest.spec.tls) == 0 && (!can(length(kubectl_manifest.qwen_ingress[0].manifest.spec.tls)) || length(kubectl_manifest.qwen_ingress[0].manifest.spec.tls) == 0) && kubectl_manifest.agents_certificate[0].manifest.spec.dnsNames == tolist(["paperclip.example.test", "opencode.example.test", "openclaw.example.test", "qwen.example.test"]) && kubectl_manifest.qwen_ingress[0].manifest.metadata.annotations["oci-native-ingress.oraclecloud.com/certificate-ocid"] == "ocid1.certificate.oc1.test.shared"
    error_message = "All HTTPS hosts must use one SAN certificate on regions with a one-certificate listener limit."
  }
  assert {
    condition     = output.opencode_public_url == "https://opencode.example.test" && output.paperclip_url == "https://paperclip.example.test"
    error_message = "Configured ACME TLS must produce HTTPS URLs."
  }
  assert {
    condition = (
      [for container in kubectl_manifest.paperclip_deployment[0].manifest.spec.template.spec.containers : container if container.name == "paperclip"][0].resources ==
      [for container in kubectl_manifest.qwen_deployment[0].manifest.spec.template.spec.containers : container if container.name == "qwen"][0].resources
    )
    error_message = "Paperclip and Qwen main containers must receive equal requests and limits."
  }
}

run "qwen_only" {
  command = plan
  variables {
    enable_paperclip    = false
    enable_openclaw     = false
    enable_opencode     = false
    enable_qwen         = true
    enable_qwen_browser = false
    qwen_custom_domain  = "qwen.example.test"
    letsencrypt_email   = "operator@example.test"
  }
  assert {
    condition     = length(helm_release.native_ingress) == 1 && length(helm_release.cert_manager) == 1 && length(kubectl_manifest.qwen_ingress) == 1
    error_message = "Qwen must get OCI Native Ingress without depending on another application."
  }
  assert {
    condition     = length(kubectl_manifest.qwen_auth_deployment[0].manifest.spec.template.spec.containers) == 1 && strcontains(kubectl_manifest.qwen_auth_deployment[0].manifest.spec.template.spec.containers[0].args[0], "auth_basic $qwen_auth_realm") && strcontains(kubectl_manifest.qwen_auth_deployment[0].manifest.spec.template.spec.containers[0].args[0], "proxy_set_header Authorization $qwen_upstream_authorization")
    error_message = "Qwen authentication must remain enforced inside its gateway service."
  }
  assert {
    condition     = kubectl_manifest.qwen_deployment[0].manifest.spec.template.spec.containers[0].args[6] == "/home/qwen/projects/sandbox" && kubectl_manifest.qwen_deployment[0].manifest.spec.template.spec.containers[0].volumeMounts[1].mountPath == "/home/qwen/projects"
    error_message = "Qwen must use the sandbox fallback inside a PVC-backed sibling-workspace root."
  }
}

run "qwen_private_without_domain" {
  command = plan
  variables {
    enable_paperclip = false
    enable_openclaw  = false
    enable_opencode  = false
    enable_qwen      = true
  }
  assert {
    condition     = length(kubectl_manifest.qwen_service) == 1 && length(kubectl_manifest.qwen_ingress) == 0 && length(helm_release.native_ingress) == 0
    error_message = "Qwen without a hostname must remain reachable only inside the cluster."
  }
}

run "invalid_public_opencode_without_domain" {
  command = plan
  variables {
    paperclip_exposure = "private"
    opencode_exposure  = "public"
  }
  expect_failures = [terraform_data.validate_public_ingress]
}

run "invalid_api_cidr" {
  command = plan
  variables {
    oci_control_plane_allowed_cidrs = ["not-a-cidr"]
  }
  expect_failures = [var.oci_control_plane_allowed_cidrs]
}
