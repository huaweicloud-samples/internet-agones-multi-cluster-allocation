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

# https://artifacthub.io/packages/helm/cert-manager/cert-manager
resource "helm_release" "this" {
  name             = "cert-manager"
  namespace        = "cert-manager"
  # Vendored locally (src/charts) so terraform never fetches from
  # charts.jetstack.io at plan/apply time — this eliminates the Windows
  # temp-dir "rename: Access is denied" failure seen when pulling the chart
  # over HTTPS on the build host.
  chart            = "${path.module}/../../../src/charts/cert-manager-v1.8.1.tgz"
  create_namespace = true
  cleanup_on_fail  = true

  # No public-NAT on cluster nodes: redirect every cert-manager image from
  # quay.io/jetstack/* to the SWR mirror (see src/mirror/sync-images.sh).
  # Tags stay at the chart default (v1.8.1).
  set = [
    {
      name  = "installCRDs"
      value = "true"
    },
    {
      name  = "prometheus.enabled"
      value = "false"
    },
    {
      name  = "image.repository"
      value = "${var.swr_addr}/${var.swr_org}/cert-manager"
    },
    {
      name  = "webhook.image.repository"
      value = "${var.swr_addr}/${var.swr_org}/cert-manager-webhook"
    },
    {
      name  = "cainjector.image.repository"
      value = "${var.swr_addr}/${var.swr_org}/cert-manager-cainjector"
    },
    {
      name  = "ctl.image.repository"
      value = "${var.swr_addr}/${var.swr_org}/cert-manager-ctl"
    },
  ]
}
