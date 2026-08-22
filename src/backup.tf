################################################################################
# Free-tier backups — Object Storage (10 GB Always Free) + daily CronJobs
# Backs up Paperclip's PostgreSQL, paperclip-data and opencode-data so all
# persistent data survives node replacements and accidental volume deletion.
# PVCs are namespace-scoped, so each CronJob runs in its own namespace.
# Restore: curl the read PAR (output backup_read_url), then kubectl cp files
# back into the pods/volumes.
################################################################################

data "oci_objectstorage_namespace" "project" {
  compartment_id = data.oci_identity_compartment.project.id
}

resource "oci_objectstorage_bucket" "backups" {
  compartment_id = data.oci_identity_compartment.project.id
  namespace      = data.oci_objectstorage_namespace.project.namespace
  name           = "${var.project_prefix}-backups"
  access_type    = "NoPublicAccess"
}

# Pre-authenticated requests so cluster pods can upload/download without
# OCI credentials. Expires in 5 years; recreate with `terraform apply` if rotated.
resource "oci_objectstorage_preauthrequest" "backup_write" {
  namespace   = data.oci_objectstorage_namespace.project.namespace
  bucket      = oci_objectstorage_bucket.backups.name
  name        = "backup-write"
  access_type = "AnyObjectWrite"
  # Fixed date (not timestamp(), which would force replacement on every apply)
  time_expires = "2031-08-09T22:29:01Z"
}

resource "oci_objectstorage_preauthrequest" "backup_read" {
  namespace   = data.oci_objectstorage_namespace.project.namespace
  bucket      = oci_objectstorage_bucket.backups.name
  name        = "backup-read"
  access_type = "AnyObjectRead"
  # Fixed date (not timestamp(), which would force replacement on every apply)
  time_expires = "2031-08-09T22:29:01Z"
}

locals {
  # PAR URLs must use the native objectstorage host (the S3-compat host rejects /p/ paths)
  object_storage_endpoint = "https://objectstorage.${var.oci_region}.oraclecloud.com"
}

resource "kubectl_manifest" "backup_par_secret" {
  count = var.enable_paperclip ? 1 : 0

  depends_on = [kubectl_manifest.paperclip_namespace]

  manifest = {
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "oci-backup-par"
      namespace = "paperclip"
      labels = {
        managed-by = "terraform"
      }
    }
    type = "Opaque"
    stringData = {
      WRITE_URL = "${local.object_storage_endpoint}${oci_objectstorage_preauthrequest.backup_write.access_uri}"
      READ_URL  = "${local.object_storage_endpoint}${oci_objectstorage_preauthrequest.backup_read.access_uri}"
    }
  }
}

resource "kubectl_manifest" "backup_par_secret_opencode" {
  count = var.enable_opencode ? 1 : 0

  depends_on = [kubectl_manifest.opencode_namespace]

  manifest = {
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "oci-backup-par"
      namespace = "opencode"
      labels = {
        managed-by = "terraform"
      }
    }
    type = "Opaque"
    stringData = {
      WRITE_URL = "${local.object_storage_endpoint}${oci_objectstorage_preauthrequest.backup_write.access_uri}"
      READ_URL  = "${local.object_storage_endpoint}${oci_objectstorage_preauthrequest.backup_read.access_uri}"
    }
  }
}

# NOTE: the backup pods mount RWO PVCs, which only works while the cluster runs
# on a single node. If scaling back to 2+ nodes, switch to volume snapshots.
resource "kubectl_manifest" "backup_cronjob" {
  count = var.enable_paperclip ? 1 : 0

  depends_on = [
    kubectl_manifest.paperclip_db_statefulset,
    kubectl_manifest.paperclip_pvc,
    kubectl_manifest.backup_par_secret,
  ]

  manifest = {
    apiVersion = "batch/v1"
    kind       = "CronJob"
    metadata = {
      name      = "${var.project_prefix}-backups"
      namespace = "paperclip"
      labels = {
        managed-by = "terraform"
      }
    }
    spec = {
      schedule                   = "30 3 * * *"
      concurrencyPolicy          = "Forbid"
      successfulJobsHistoryLimit = 1
      failedJobsHistoryLimit     = 2
      jobTemplate = {
        spec = {
          backoffLimit = 2
          template = {
            spec = {
              restartPolicy = "OnFailure"
              initContainers = [
                {
                  name  = "dump"
                  image = "docker.io/library/postgres:17-alpine"
                  command = ["sh", "-c", trimspace(<<-EOT
                    set -e
                    D=$(date -u +%Y-%m-%d)
                    pg_dump --dbname="$DATABASE_URL" --format=custom --file=/backup/paperclip-db-$D.dump
                    tar czf /backup/paperclip-data-$D.tgz -C /data/paperclip .
                    ls -lh /backup
                  EOT
                  )]
                  env = [
                    {
                      name = "DATABASE_URL"
                      valueFrom = {
                        secretKeyRef = {
                          name = "paperclip-db"
                          key  = "DATABASE_URL"
                        }
                      }
                    }
                  ]
                  volumeMounts = [
                    {
                      name      = "paperclip-data"
                      mountPath = "/data/paperclip"
                      readOnly  = true
                    },
                    {
                      name      = "backup-scratch"
                      mountPath = "/backup"
                    }
                  ]
                  resources = {
                    requests = {
                      cpu    = "50m"
                      memory = "128Mi"
                    }
                    limits = {
                      cpu    = "200m"
                      memory = "256Mi"
                    }
                  }
                }
              ]
              containers = [
                {
                  name  = "upload"
                  image = "docker.io/curlimages/curl:8.14.1"
                  command = ["sh", "-c", trimspace(<<-EOT
                    set -e
                    for f in /backup/*; do
                      name=$(basename "$f")
                      echo "uploading $name"
                      curl --silent --show-error --fail --upload-file "$f" "$WRITE_URL$name"
                    done
                    echo "backup upload complete"
                  EOT
                  )]
                  env = [
                    {
                      name = "WRITE_URL"
                      valueFrom = {
                        secretKeyRef = {
                          name = "oci-backup-par"
                          key  = "WRITE_URL"
                        }
                      }
                    }
                  ]
                  volumeMounts = [
                    {
                      name      = "backup-scratch"
                      mountPath = "/backup"
                      readOnly  = true
                    }
                  ]
                  resources = {
                    requests = {
                      cpu    = "10m"
                      memory = "32Mi"
                    }
                    limits = {
                      cpu    = "100m"
                      memory = "64Mi"
                    }
                  }
                }
              ]
              volumes = [
                {
                  name = "paperclip-data"
                  persistentVolumeClaim = {
                    claimName = "paperclip-data"
                  }
                },
                {
                  name     = "backup-scratch"
                  emptyDir = {}
                }
              ]
            }
          }
        }
      }
    }
  }
}

resource "kubectl_manifest" "backup_cronjob_opencode" {
  count = var.enable_opencode ? 1 : 0

  depends_on = [
    kubectl_manifest.opencode_pvc,
    kubectl_manifest.backup_par_secret_opencode,
  ]

  manifest = {
    apiVersion = "batch/v1"
    kind       = "CronJob"
    metadata = {
      name      = "${var.project_prefix}-backups"
      namespace = "opencode"
      labels = {
        managed-by = "terraform"
      }
    }
    spec = {
      schedule                   = "35 3 * * *"
      concurrencyPolicy          = "Forbid"
      successfulJobsHistoryLimit = 1
      failedJobsHistoryLimit     = 2
      jobTemplate = {
        spec = {
          backoffLimit = 2
          template = {
            spec = {
              restartPolicy = "OnFailure"
              initContainers = [
                {
                  name  = "dump"
                  image = "docker.io/library/busybox:1.37"
                  command = ["sh", "-c", trimspace(<<-EOT
                    set -e
                    D=$(date -u +%Y-%m-%d)
                    tar czf /backup/opencode-data-$D.tgz -C /data/opencode .
                    ls -lh /backup
                  EOT
                  )]
                  volumeMounts = [
                    {
                      name      = "opencode-data"
                      mountPath = "/data/opencode"
                      readOnly  = true
                    },
                    {
                      name      = "backup-scratch"
                      mountPath = "/backup"
                    }
                  ]
                  resources = {
                    requests = {
                      cpu    = "10m"
                      memory = "32Mi"
                    }
                    limits = {
                      cpu    = "100m"
                      memory = "64Mi"
                    }
                  }
                }
              ]
              containers = [
                {
                  name  = "upload"
                  image = "docker.io/curlimages/curl:8.14.1"
                  command = ["sh", "-c", trimspace(<<-EOT
                    set -e
                    for f in /backup/*; do
                      name=$(basename "$f")
                      echo "uploading $name"
                      curl --silent --show-error --fail --upload-file "$f" "$WRITE_URL$name"
                    done
                    echo "backup upload complete"
                  EOT
                  )]
                  env = [
                    {
                      name = "WRITE_URL"
                      valueFrom = {
                        secretKeyRef = {
                          name = "oci-backup-par"
                          key  = "WRITE_URL"
                        }
                      }
                    }
                  ]
                  volumeMounts = [
                    {
                      name      = "backup-scratch"
                      mountPath = "/backup"
                      readOnly  = true
                    }
                  ]
                  resources = {
                    requests = {
                      cpu    = "10m"
                      memory = "32Mi"
                    }
                    limits = {
                      cpu    = "100m"
                      memory = "64Mi"
                    }
                  }
                }
              ]
              volumes = [
                {
                  name = "opencode-data"
                  persistentVolumeClaim = {
                    claimName = "opencode-data"
                  }
                },
                {
                  name     = "backup-scratch"
                  emptyDir = {}
                }
              ]
            }
          }
        }
      }
    }
  }
}

output "backup_read_url" {
  description = "Pre-authenticated read URL for restoring backups from Object Storage (sensitive — grants read access to all backup objects)"
  value       = "${local.object_storage_endpoint}${oci_objectstorage_preauthrequest.backup_read.access_uri}"
  sensitive   = true
}
