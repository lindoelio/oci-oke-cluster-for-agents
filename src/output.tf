output "oci_region" {
  description = "OCI region"
  value       = var.oci_region
}

output "cluster_id" {
  description = "OKE cluster ID"
  value       = local.cluster_id
}

output "cluster_endpoint" {
  description = "OKE cluster endpoint"
  value       = local.cluster_endpoint
}

output "kubeconfig_command" {
  description = "Command to configure kubectl locally"
  value       = "oci ce cluster create-kubeconfig --cluster-id ${local.cluster_id} --file $HOME/.kube/config --region ${var.oci_region} --token-version 2.0.0 --kube-endpoint PUBLIC_ENDPOINT"
}

output "kubeconfig_content" {
  description = "Kubeconfig content"
  value       = data.oci_containerengine_cluster_kube_config.oke_cluster_kube_config.content
  sensitive   = true
}

output "project_compartment_id" {
  description = "Project compartment ID"
  value       = data.oci_identity_compartment.project.id
}

output "project_compartment_name" {
  description = "Project compartment name"
  value       = data.oci_identity_compartment.project.name
}

output "opencode_admin_password" {
  description = "Admin password for OpenCode Web HTTP Basic Auth"
  value       = var.enable_opencode ? random_password.opencode_admin[0].result : null
  sensitive   = true
}

output "opencode_public_url" {
  description = "Current OpenCode Web access URL"
  value = var.enable_opencode && var.opencode_exposure == "public" ? (
    var.opencode_custom_domain != "" ? "https://${var.opencode_custom_domain}" : (
      length(data.external.ingress_ip) > 0 ? "http://${data.external.ingress_ip[0].result["ip"]}${var.opencode_path_prefix}" : null
    )
  ) : null
}

output "paperclip_public_ip" {
  description = "Public IP of the NGINX Ingress LoadBalancer (use this for DNS A records)"
  value       = var.enable_paperclip && var.paperclip_exposure == "public" && length(data.external.ingress_ip) > 0 ? data.external.ingress_ip[0].result["ip"] : null
}

output "paperclip_url" {
  description = "Current Paperclip access URL"
  value = var.enable_paperclip && var.paperclip_exposure == "public" ? (
    var.paperclip_custom_domain != "" ? "https://${var.paperclip_custom_domain}" : (
      var.paperclip_public_url != "" ? var.paperclip_public_url : (
        length(data.external.ingress_ip) > 0 ? "http://${data.external.ingress_ip[0].result["ip"]}" : null
      )
    )
  ) : null
}

output "post_deploy_instructions" {
  description = "Steps to complete after terraform apply"
  value = join("\n", [
    "=== Post-Deploy Setup ===",
    "1. Configure kubectl:",
    "   oci ce cluster create-kubeconfig --cluster-id <cluster_id> --file $HOME/.kube/config --region ${var.oci_region} --token-version 2.0.0 --kube-endpoint PUBLIC_ENDPOINT",
    "",
    "2. Paperclip is accessible at:",
    "   ${var.paperclip_custom_domain != "" && var.enable_paperclip && var.paperclip_exposure == "public" ? "https://${var.paperclip_custom_domain}" : (
      var.paperclip_public_url != "" && var.enable_paperclip && var.paperclip_exposure == "public" ? var.paperclip_public_url : (
        var.enable_paperclip && var.paperclip_exposure == "public" && length(data.external.ingress_ip) > 0 ? "http://${data.external.ingress_ip[0].result["ip"]}" : "Paperclip is not publicly exposed."
      )
    )}",
    "",
    "3. Paperclip auto-onboarding runs on first start (initContainer).",
    "   Wait for the pod to be Ready, then bootstrap the first admin:",
    "   kubectl exec -n paperclip deployment/paperclip -- pnpm paperclipai auth bootstrap-ceo",
    "   Open the printed invite URL in your browser (mobile or desktop) to create the admin.",
    "",
    "4. Custom domain (optional):",
    "   - Create an A record: ${var.paperclip_custom_domain != "" && var.enable_paperclip && var.paperclip_exposure == "public" ? var.paperclip_custom_domain : "your-domain.example.com"} → ${var.enable_paperclip && var.paperclip_exposure == "public" && length(data.external.ingress_ip) > 0 ? data.external.ingress_ip[0].result["ip"] : "<IP_from_step_2>"}",
    "   - Update terraform.tfvars: paperclip_custom_domain = \"${var.paperclip_custom_domain != "" ? var.paperclip_custom_domain : "your-domain.example.com"}\"",
    "   - terraform apply (enables HTTPS with Let's Encrypt)",
    "",
    "5. OpenClaw:",
    "   - Paste the invite prompt into OpenClaw via Telegram or direct access",
    "   - Agents will appear in Paperclip dashboard",
    "",
    "6. OpenCode Web:",
    "   ${var.enable_opencode && var.opencode_exposure == "public" ? (
      var.opencode_custom_domain != "" ? "   - OpenCode Web is accessible at: https://${var.opencode_custom_domain}" : (
        length(data.external.ingress_ip) > 0 ? "   - OpenCode Web is accessible at: http://${data.external.ingress_ip[0].result["ip"]}${var.opencode_path_prefix}" : "   - OpenCode Web public URL is pending (Ingress IP not yet assigned)."
      )
    ) : "   - OpenCode Web is not publicly exposed (set opencode_exposure = \"public\" to enable)."}",
    "   - Password: (run `terraform output -raw opencode_admin_password` to capture it once)",
    "   - Wait for the pod to be Ready: kubectl get pods -n opencode",
    "   - OpenCode Web auto-starts the `opencode web` server on first boot.",
    "   - When `opencode_custom_domain` is set but `letsencrypt_email` is empty, OpenCode serves over HTTP (no TLS). Set `letsencrypt_email` to enable Let's Encrypt for the custom domain.",
  ])
}

