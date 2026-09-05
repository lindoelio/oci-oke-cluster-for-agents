################################################################################
# OCI Native Ingress Controller + shared public Load Balancer
################################################################################

locals {
  paperclip_public = var.enable_paperclip && var.paperclip_exposure == "public"

  # OCI Native Ingress does not implement ingress-nginx regex rewrites. Each
  # additional application therefore needs its own hostname.
  opencode_public = var.enable_opencode && var.opencode_exposure == "public" && var.opencode_custom_domain != ""
  openclaw_public = var.enable_openclaw && var.openclaw_custom_domain != ""
  qwen_public     = var.enable_qwen && var.qwen_custom_domain != ""

  ingress_enabled = local.paperclip_public || local.opencode_public || local.openclaw_public || local.qwen_public
  ingress_class   = "oci-native"

  paperclip_tls     = local.paperclip_public && var.paperclip_custom_domain != "" && var.letsencrypt_email != ""
  opencode_tls      = local.opencode_public && var.letsencrypt_email != ""
  openclaw_tls      = local.openclaw_public && var.letsencrypt_email != ""
  qwen_tls          = local.qwen_public && var.letsencrypt_email != ""
  tls_enabled = local.paperclip_tls || local.opencode_tls || local.openclaw_tls || local.qwen_tls
  tls_hosts = compact([
    local.paperclip_tls ? var.paperclip_custom_domain : "",
    local.opencode_tls ? var.opencode_custom_domain : "",
    local.openclaw_tls ? var.openclaw_custom_domain : "",
    local.qwen_tls ? var.qwen_custom_domain : "",
  ])
  shared_listener_tls = length(local.tls_hosts) > 1
}

resource "terraform_data" "validate_public_ingress" {
  lifecycle {
    precondition {
      condition     = !(var.enable_opencode && var.opencode_exposure == "public") || var.opencode_custom_domain != ""
      error_message = "opencode_custom_domain is required when opencode_exposure is public because OCI Native Ingress does not support the former regex path rewrite."
    }
    precondition {
      condition     = !local.shared_listener_tls || (local.paperclip_tls && var.oci_native_shared_certificate_ocid != "")
      error_message = "Multiple HTTPS applications require Paperclip as the shared certificate owner and oci_native_shared_certificate_ocid. First issue/import agents-tls with only Paperclip public, then set its OCI certificate OCID and enable the other applications."
    }
  }
}

################################################################################
# Instance-principal IAM for Basic OKE clusters
################################################################################

resource "oci_identity_dynamic_group" "native_ingress_workers" {
  provider = oci.home
  count    = local.ingress_enabled ? 1 : 0

  compartment_id = var.oci_tenancy_id
  name           = "${var.project_prefix}-native-ingress-workers"
  description    = "OKE workers allowed to operate the OCI Native Ingress Controller"
  matching_rule  = "ALL {instance.compartment.id = '${data.oci_identity_compartment.project.id}'}"
}

resource "oci_identity_policy" "native_ingress" {
  provider = oci.home
  count    = local.ingress_enabled ? 1 : 0

  compartment_id = var.oci_tenancy_id
  name           = "${var.project_prefix}-native-ingress"
  description    = "Service permissions required by OCI Native Ingress"
  statements = [
    "Allow dynamic-group id ${oci_identity_dynamic_group.native_ingress_workers[0].id} to manage load-balancers in compartment id ${data.oci_identity_compartment.project.id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.native_ingress_workers[0].id} to use virtual-network-family in compartment id ${data.oci_identity_compartment.project.id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.native_ingress_workers[0].id} to manage cabundles in compartment id ${data.oci_identity_compartment.project.id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.native_ingress_workers[0].id} to manage cabundle-associations in compartment id ${data.oci_identity_compartment.project.id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.native_ingress_workers[0].id} to manage leaf-certificates in compartment id ${data.oci_identity_compartment.project.id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.native_ingress_workers[0].id} to manage leaf-certificate-versions in compartment id ${data.oci_identity_compartment.project.id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.native_ingress_workers[0].id} to read leaf-certificate-bundles in compartment id ${data.oci_identity_compartment.project.id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.native_ingress_workers[0].id} to manage certificate-associations in compartment id ${data.oci_identity_compartment.project.id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.native_ingress_workers[0].id} to read certificate-authorities in compartment id ${data.oci_identity_compartment.project.id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.native_ingress_workers[0].id} to manage certificate-authority-associations in compartment id ${data.oci_identity_compartment.project.id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.native_ingress_workers[0].id} to read certificate-authority-bundles in compartment id ${data.oci_identity_compartment.project.id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.native_ingress_workers[0].id} to read public-ips in tenancy",
    "Allow dynamic-group id ${oci_identity_dynamic_group.native_ingress_workers[0].id} to manage floating-ips in tenancy",
    "Allow dynamic-group id ${oci_identity_dynamic_group.native_ingress_workers[0].id} to manage waf-family in compartment id ${data.oci_identity_compartment.project.id}",
    "Allow dynamic-group id ${oci_identity_dynamic_group.native_ingress_workers[0].id} to read cluster-family in compartment id ${data.oci_identity_compartment.project.id}",
  ]
}

resource "time_sleep" "wait_for_native_ingress_iam" {
  count = local.ingress_enabled ? 1 : 0

  depends_on      = [oci_identity_policy.native_ingress]
  create_duration = "30s"
}

################################################################################
# Standalone controller and free-tier-sized Load Balancer
################################################################################

resource "helm_release" "native_ingress" {
  count = local.ingress_enabled ? 1 : 0

  depends_on = [
    time_sleep.wait_for_cert_manager,
    time_sleep.wait_for_native_ingress_iam,
  ]

  name      = "oci-native-ingress-controller"
  namespace = "native-ingress-controller-system"
  chart     = "${path.module}/charts/oci-native-ingress-controller"
  version   = var.oci_native_ingress_version

  # The upstream chart includes its own Namespace manifest. Asking Helm to
  # create the release namespace separately races that manifest.
  create_namespace = false
  wait             = true

  values = [yamlencode({
    authType       = "instance"
    cluster_id     = local.cluster_id
    compartment_id = data.oci_identity_compartment.project.id
    subnet_id      = module.oke.pub_lb_subnet_id
    region         = var.oci_region
    replicaCount   = 1
    image = {
      repository = "ghcr.io/oracle/oci-native-ingress-controller"
      tag        = "v${var.oci_native_ingress_version}"
      pullPolicy = "IfNotPresent"
    }
    resources = {
      requests = {
        cpu    = "100m"
        memory = "128Mi"
      }
      limits = {
        cpu    = "300m"
        memory = "256Mi"
      }
    }
    useLbCompartmentForCertificates = true
    emitEvents                      = true
    certDeletionGracePeriodInDays   = 7
  })]

  timeout = 1800
}

resource "time_sleep" "wait_for_native_ingress" {
  count = local.ingress_enabled ? 1 : 0

  depends_on      = [helm_release.native_ingress]
  create_duration = "60s"
}

resource "kubectl_manifest" "native_ingress_namespace" {
  count = local.ingress_enabled ? 1 : 0

  depends_on = [time_sleep.wait_for_native_ingress]

  manifest = {
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = "oci-native-ingress"
      labels = {
        "managed-by" = "terraform"
      }
    }
  }
}

resource "kubectl_manifest" "native_ingress_parameters" {
  count = local.ingress_enabled ? 1 : 0

  depends_on = [kubectl_manifest.native_ingress_namespace]

  manifest = {
    apiVersion = "ingress.oraclecloud.com/v1beta1"
    kind       = "IngressClassParameters"
    metadata = {
      name      = "agents"
      namespace = "oci-native-ingress"
    }
    spec = {
      compartmentId    = data.oci_identity_compartment.project.id
      subnetId         = module.oke.pub_lb_subnet_id
      loadBalancerName = "${var.project_prefix}-native-ingress"
      isPrivate        = false
      minBandwidthMbps = 10
      maxBandwidthMbps = 10
    }
  }
}

resource "kubectl_manifest" "native_ingress_class" {
  count = local.ingress_enabled ? 1 : 0

  depends_on = [kubectl_manifest.native_ingress_parameters]

  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "IngressClass"
    metadata = {
      name = local.ingress_class
      annotations = {
        # The module already permits NodePort traffic from this NSG to workers.
        # Attaching it to the Native LB completes that rule for Flannel CNI.
        "oci-native-ingress.oraclecloud.com/network-security-group-ids" = module.oke.pub_lb_nsg_id
      }
    }
    spec = {
      controller = "oci.oraclecloud.com/native-ingress-controller"
      parameters = {
        scope     = "Namespace"
        namespace = "oci-native-ingress"
        apiGroup  = "ingress.oraclecloud.com"
        kind      = "ingressclassparameters"
        name      = "agents"
      }
    }
  }
}

resource "time_sleep" "wait_for_ingress_lb" {
  count = local.ingress_enabled ? 1 : 0

  depends_on      = [kubectl_manifest.native_ingress_class]
  create_duration = "120s"
}

resource "kubectl_manifest" "paperclip_ingress" {
  count = local.paperclip_public ? 1 : 0

  depends_on = [
    time_sleep.wait_for_ingress_lb,
    kubectl_manifest.paperclip_service,
    kubectl_manifest.letsencrypt_issuer,
  ]

  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "paperclip"
      namespace = "paperclip"
      annotations = merge(
        {
          "oci-native-ingress.oraclecloud.com/backend-tls-enabled" = "false"
        },
        local.paperclip_tls ? merge({
          "oci-native-ingress.oraclecloud.com/https-listener-port" = "443"
          }, local.shared_listener_tls ? {} : {
          "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
          }) : {
          "oci-native-ingress.oraclecloud.com/http-listener-port" = "80"
        }
      )
    }
    spec = {
      rules = [
        {
          host = var.paperclip_custom_domain != "" ? var.paperclip_custom_domain : null
          http = {
            paths = [
              {
                path     = "/"
                pathType = "Prefix"
                backend = {
                  service = {
                    name = "paperclip"
                    port = {
                      number = 80
                    }
                  }
                }
              }
            ]
          }
        }
      ]
      ingressClassName = local.ingress_class
      tls = local.paperclip_tls ? [
        {
          hosts      = local.shared_listener_tls ? local.tls_hosts : [var.paperclip_custom_domain]
          secretName = local.shared_listener_tls ? "agents-tls" : "paperclip-tls"
        }
      ] : []
    }
  }
}

data "external" "ingress_ip" {
  count = local.ingress_enabled ? 1 : 0

  depends_on = [
    kubectl_manifest.paperclip_ingress,
    kubectl_manifest.opencode_ingress,
    kubectl_manifest.openclaw_ingress,
    kubectl_manifest.qwen_ingress,
  ]

  program = ["python3", "${path.module}/scripts/detect_ingress_ip.py"]
}
