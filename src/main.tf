terraform {
  required_version = ">= 1.14.0"

  required_providers {
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "= 2.3.7"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "= 4.5.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "= 2.3.5"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "= 3.1.1"
    }
    kubectl = {
      source  = "hashicorp-oss/kubectl"
      version = "= 0.1.13"
    }
    local = {
      source  = "hashicorp/local"
      version = "= 2.8.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "= 3.2.4"
    }
    oci = {
      source  = "oracle/oci"
      version = "= 8.9.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "= 3.8.1"
    }
    time = {
      source  = "hashicorp/time"
      version = "= 0.13.1"
    }
  }
}

provider "oci" {
  config_file_profile = "DEFAULT"
  region              = var.oci_region
}

provider "oci" {
  alias               = "home"
  config_file_profile = "DEFAULT"
  region              = var.oci_home_region
}

resource "oci_identity_compartment" "project" {
  count = var.oci_project_compartment_id == "" ? 1 : 0

  compartment_id = var.oci_compartment_id
  name           = var.project_prefix
  description    = "Project compartment for ${var.project_prefix}"
}

data "oci_identity_compartment" "project" {
  id = var.oci_project_compartment_id != "" ? var.oci_project_compartment_id : oci_identity_compartment.project[0].id
}

resource "time_sleep" "after_project_compartment" {
  count           = var.oci_project_compartment_id == "" ? 1 : 0
  depends_on      = [oci_identity_compartment.project]
  create_duration = "30s"
}

locals {
  cluster_name = "${var.project_prefix}-oke-cluster"
  vcn_name     = "${var.project_prefix}-vcn"
  cluster_lookup_script = trimspace(
    <<-EOT
import json
import os
import subprocess
import sys

compartment_id, region, name = sys.argv[1:4]
env = dict(os.environ, SUPPRESS_LABEL_WARNING="True", PYTHONWARNINGS="ignore")
result = subprocess.run(
    [
        "oci",
        "ce",
        "cluster",
        "list",
        "--compartment-id",
        compartment_id,
        "--region",
        region,
        "--all",
    ],
    env=env,
    capture_output=True,
    text=True,
)
if result.returncode != 0:
    raise SystemExit(result.stderr or "cluster list failed")
data = json.loads(result.stdout).get("data", [])

for item in data:
    if item["name"] == name and item["lifecycle-state"] == "ACTIVE":
        print(json.dumps({"cluster_id": item["id"]}))
        raise SystemExit(0)

raise SystemExit("cluster not found")
    EOT
  )
  token_script = trimspace(
    <<-EOT
import json
import os
import subprocess
import sys

cluster_id, region = sys.argv[1:3]
env = dict(os.environ, SUPPRESS_LABEL_WARNING="True", PYTHONWARNINGS="ignore")
result = subprocess.run(
    [
        "oci",
        "ce",
        "cluster",
        "generate-token",
        "--cluster-id",
        cluster_id,
        "--region",
        region,
    ],
    env=env,
    capture_output=True,
    text=True,
)
if result.returncode != 0:
    raise SystemExit(result.stderr or "token generation failed")
token = json.loads(result.stdout)["status"]["token"]
print(json.dumps({"token": token}))
    EOT
  )
}

data "external" "oke_cluster" {
  depends_on = [module.oke, time_sleep.after_project_compartment]

  program = [
    "python3",
    "-c",
    local.cluster_lookup_script,
    data.oci_identity_compartment.project.id,
    var.oci_region,
    local.cluster_name,
  ]
}

resource "time_sleep" "after_cluster" {
  depends_on      = [data.external.oke_cluster]
  create_duration = "60s"
}

data "oci_containerengine_cluster_kube_config" "oke_cluster_kube_config" {
  depends_on = [time_sleep.after_cluster]
  cluster_id = data.external.oke_cluster.result["cluster_id"]
}

data "external" "oke_token" {
  depends_on = [time_sleep.after_cluster]

  program = [
    "python3",
    "-c",
    local.token_script,
    data.external.oke_cluster.result["cluster_id"],
    var.oci_region,
  ]
}

locals {
  kubeconfig       = yamldecode(data.oci_containerengine_cluster_kube_config.oke_cluster_kube_config.content)
  cluster_id       = data.external.oke_cluster.result["cluster_id"]
  cluster_endpoint = local.kubeconfig["clusters"][0]["cluster"]["server"]
  cluster_ca_cert  = base64decode(local.kubeconfig["clusters"][0]["cluster"]["certificate-authority-data"])
  cluster_token    = data.external.oke_token.result["token"]
}

provider "kubectl" {
  host                   = local.cluster_endpoint
  cluster_ca_certificate = local.cluster_ca_cert
  token                  = local.cluster_token
  load_config_file       = false
  apply_retry_count      = 10
}

provider "helm" {
  alias = "oke"

  kubernetes = {
    host     = "https://127.0.0.1:65535"
    insecure = true
  }
}

provider "helm" {
  kubernetes = {
    host                   = local.cluster_endpoint
    cluster_ca_certificate = local.cluster_ca_cert
    token                  = local.cluster_token
  }
}
