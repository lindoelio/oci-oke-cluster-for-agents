module "oke" {
  source  = "oracle-terraform-modules/oke/oci"
  version = "5.4.3"

  providers = {
    oci.home = oci.home
    helm     = helm.oke
  }

  depends_on = [time_sleep.after_project_compartment]

  tenancy_id     = var.oci_tenancy_id
  compartment_id = data.oci_identity_compartment.project.id

  state_id      = var.project_prefix
  cluster_name  = local.cluster_name
  vcn_name      = local.vcn_name
  vcn_dns_label = substr(var.project_prefix, 0, 15)

  create_bastion  = false
  create_operator = false

  cluster_type                      = "basic"
  cni_type                          = "flannel"
  kubernetes_version                = var.oci_oke_kubernetes_version
  control_plane_is_public           = true
  assign_public_ip_to_control_plane = true
  control_plane_allowed_cidrs       = ["0.0.0.0/0"]

  load_balancers          = "public"
  preferred_load_balancer = "public"

  vcn_create_nat_gateway = var.oci_public_workers ? "never" : "auto"

  worker_is_public             = var.oci_public_workers
  allow_worker_internet_access = true
  allow_worker_ssh_access      = false

  worker_pool_size = var.oci_oke_node_pool_size
  worker_shape = {
    shape            = var.oci_oke_node_shape
    ocpus            = var.oci_oke_node_shape_ocpus
    memory           = var.oci_oke_node_shape_memory_in_gbs
    boot_volume_size = 50
  }
  worker_image_type       = "oke"
  worker_image_os         = "Oracle Linux"
  worker_image_os_version = "8"
  worker_pools = {
    "${var.project_prefix}-pool" = {}
  }

  metrics_server_install = false

  output_detail = true
}

################################################################################
# CRI-O short-name fix for OKE
# OKE enforces short-name-mode = "enforcing" which rejects unqualified image
# names. Some operators (e.g., OpenClaw) deploy sidecars with short names like
# "nginx:1.27-alpine". This DaemonSet adds docker.io aliases on every node.
################################################################################

resource "kubectl_manifest" "crio_shortname_fix" {
  depends_on = [module.oke, time_sleep.after_cluster]

  manifest = {
    apiVersion = "apps/v1"
    kind       = "DaemonSet"
    metadata = {
      name      = "crio-shortname-fix"
      namespace = "kube-system"
      labels = {
        managed-by = "terraform"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          app = "crio-shortname-fix"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "crio-shortname-fix"
          }
        }
        spec = {
          hostPID = true
          tolerations = [
            {
              operator = "Exists"
            }
          ]
          initContainers = [
            {
              name    = "fix-registries"
              image   = "docker.io/library/busybox:1.37"
              command = ["/bin/sh", "-c"]
              args = [
                "CONF=/host/etc/containers/registries.conf; grep -q 'unqualified-search-registries' \"$CONF\" || printf '\\nunqualified-search-registries = [\"docker.io\"]\\n' >> \"$CONF\"; nsenter -t 1 -m systemctl restart crio 2>/dev/null || true"
              ]
              securityContext = {
                privileged = true
              }
              volumeMounts = [
                {
                  name      = "host-etc"
                  mountPath = "/host/etc"
                }
              ]
            }
          ]
          containers = [
            {
              name    = "pause"
              image   = "docker.io/library/busybox:1.37"
              command = ["sleep", "infinity"]
              resources = {
                requests = {
                  cpu    = "1m"
                  memory = "8Mi"
                }
                limits = {
                  cpu    = "10m"
                  memory = "16Mi"
                }
              }
            }
          ]
          volumes = [
            {
              name = "host-etc"
              hostPath = {
                path = "/etc"
              }
            }
          ]
        }
      }
    }
  }
}
