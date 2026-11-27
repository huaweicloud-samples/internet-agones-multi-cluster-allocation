terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.11.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
  }
}

# metrics-server — required by the dashboard to render CPU/memory graphs.
# https://github.com/kubernetes-sigs/metrics-server
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  # Vendored locally (src/charts). The upstream GH-Pages repo only publishes up
  # to 3.10.0; 3.11.0 is fetched from the GitHub release and vendored here.
  chart      = "${path.module}/../../../src/charts/metrics-server-3.11.0.tgz"
  create_namespace = false
  cleanup_on_fail  = true
  wait       = false

  # No public-NAT: redirect metrics-server from registry.k8s.io to SWR.
  # Chart's image.repository default is the FULL path `registry.k8s.io/metrics-server/metrics-server`,
  # so we must point at the nested SWR repo `agones/metrics-server/metrics-server` (public).
  set = [
    {
      name  = "args[0]"
      value = "--kubelet-insecure-tls"
    },
    {
      name  = "image.repository"
      value = "${var.swr_addr}/${var.swr_org}/metrics-server/metrics-server"
    },
  ]
}

# Kubernetes Dashboard (classic v2.7 line that supports SA-token login).
# https://artifacthub.io/packages/helm/kubernetes-dashboard/kubernetes-dashboard
resource "helm_release" "dashboard" {
  depends_on = [helm_release.metrics_server]

  name       = "kubernetes-dashboard"
  namespace  = "kubernetes-dashboard"
  # Vendored locally (src/charts). The upstream kubernetes.github.io/dashboard
  # helm repo was taken down (404), so we vendor the official chart source
  # (dashboard v2.7.0 tag) as 5.10.0 and dropped its metrics-server subchart
  # dependency (we deploy metrics-server 3.11.0 separately).
  chart      = "${path.module}/../../../src/charts/kubernetes-dashboard-5.10.0.tgz"
  create_namespace = true
  cleanup_on_fail  = true
  wait       = false

  # No public-NAT: redirect the dashboard image from kubernetesui/dashboard to
  # the SWR mirror. The vendored chart is 5.10.0 (default tag v2.6.1); the
  # upstream kubernetes.github.io/dashboard repo was taken down, and 5.10.0 does
  # not deploy metrics-scraper as a subchart, so that image is not needed.
  # Chart image.repository default is the FULL path `kubernetesui/dashboard`,
  # so we point at the SWR repo `agones/dashboard` (image pushed + public).
  set = [
    {
      name  = "service.type"
      value = "ClusterIP"
    },
    {
      name  = "image.repository"
      value = "${var.swr_addr}/${var.swr_org}/dashboard"
    },
  ]
}

# admin-user ServiceAccount + cluster-admin ClusterRoleBinding (from manifest.yaml).
# Document count is computed at plan time via templatefile()+split (manifest.yaml
# has no template vars) so `count` is known before apply.
locals {
  dashboard_docs = [
    for d in split("\n---\n", replace(templatefile("${path.module}/manifests/manifest.yaml", {}), "\r\n", "\n")) : d if trimspace(d) != ""
  ]
}

resource "kubectl_manifest" "this" {
  count      = length(local.dashboard_docs)
  depends_on = [helm_release.dashboard]
  yaml_body  = element(local.dashboard_docs, count.index)
  wait_for_rollout = false
}

# Login token for the admin-user ServiceAccount. The dashboard reads this
# Secret's `.data.token` for the "Token" login method.
resource "kubernetes_secret" "admin_user_token" {
  depends_on = [kubectl_manifest.this]

  metadata {
    name      = "admin-user-token"
    namespace = "kubernetes-dashboard"
    annotations = {
      "kubernetes.io/service-account.name" = "admin-user"
    }
  }

  type = "kubernetes.io/service-account-token"
}
