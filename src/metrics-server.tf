################################################################################
# metrics-server — node/pod resource metrics for kubectl top and scheduling
# visibility on the configured node pool.
################################################################################

resource "helm_release" "metrics_server" {
  count = var.enable_metrics_server ? 1 : 0

  depends_on = [module.oke, time_sleep.after_cluster]

  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server"
  chart      = "metrics-server"
  version    = var.metrics_server_chart_version

  values = [
    <<-EOF
    args:
      # OKE kubelet serving certs aren't wired to the aggregated API CA
      - --kubelet-insecure-tls
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
      limits:
        memory: 256Mi
    EOF
  ]
}
