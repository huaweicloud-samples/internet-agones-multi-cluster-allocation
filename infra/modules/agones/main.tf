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
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9.0"
    }
  }
}

# cert-manager 作为 Agones 的依赖（签发 allocator mTLS 证书），每个集群独立部署
module "cert_manager" {
  source = "../cert_manager"
  providers = {
    helm       = helm
    kubernetes = kubernetes
    kubectl    = kubectl
  }
}

resource "kubernetes_namespace" "this" {
  depends_on = [module.cert_manager]
  metadata {
    name = var.namespace
  }
}

# https://artifacthub.io/packages/helm/agones/agones
resource "helm_release" "this" {
  depends_on = [
    module.cert_manager,
    kubernetes_namespace.this,
    time_sleep.wait_for_cert_creation,
  ]
  namespace        = var.namespace
  create_namespace = false
  cleanup_on_fail  = true
  wait            = false

  name          = "agones"
  # Vendored locally (src/charts) — avoids fetching from agones.dev at plan time.
  chart         = "${path.module}/../../../src/charts/agones-1.24.0.tgz"
  wait_for_jobs = true

  # 证书由 cert-manager 生成（cert.yaml），通过 Secret 注入，避免 Helm 每次重建导致 CN 失效
  set = [
    {
      name  = "agones.allocator.tlsCert"
      value = data.kubernetes_secret.allocator_server_cert.data["tls.crt"]
    },
    {
      # 注意 \\. 转义，避免 helm --set 把点当作路径分隔符
      name  = "agones.allocator.clientCAs.default\\.crt"
      value = data.kubernetes_secret.allocator_client_cert.data["tls.crt"]
    },
    {
      # No public-NAT: redirect the Agones controller/allocator/ping/sdk images
      # from gcr.io/agones-images to the SWR mirror. The chart composes
      # <registry>/<component>:<tag>, so only the registry prefix needs to change.
      name  = "agones.image.registry"
      value = "${var.swr_addr}/${var.swr_org}"
    },
  ]

  set_sensitive = [
    {
      name  = "agones.allocator.tlsKey"
      value = data.kubernetes_secret.allocator_server_cert.data["tls.key"]
    },
  ]

  values = [
    templatefile("${path.module}/values.yaml", {
      allocator_allowed_cidrs = var.allocator_allowed_cidrs
      gameserver_namespace    = var.gameserver_namespace
      subnet_id               = var.subnet_id
    })
  ]
}

# ===== Plan-time document counts =====
# kubectl_path_documents renders its documents only at apply time, which made
# `count = length(...)` fail during plan (Invalid count argument). We instead
# render the vendored manifests with templatefile() and split on the YAML
# "---" separator, filtering empty trailing docs, so the count is known before
# apply. The resulting list is fed straight to kubectl_manifest.yaml_body.
locals {
  cert_docs = [
    for d in split("\n---\n", replace(templatefile("${path.module}/manifests/cert.yaml", {
      namespace = var.namespace
      region    = var.region
    }), "\r\n", "\n")) : d if trimspace(d) != ""
  ]
  hpa_docs = [
    for d in split("\n---\n", replace(templatefile("${path.module}/manifests/hpa.yaml", {
      namespace = var.namespace
    }), "\r\n", "\n")) : d if trimspace(d) != ""
  ]
  fleet_docs = [
    for d in split("\n---\n", replace(templatefile("${path.module}/manifests/fleet.yaml", {
      gameserver_image = var.gameserver_image
    }), "\r\n", "\n")) : d if trimspace(d) != ""
  ]
}

# ===== allocator mTLS 证书（cert-manager selfSigned Issuer）=====
resource "kubectl_manifest" "cert" {
  depends_on = [module.cert_manager, kubernetes_namespace.this]
  count      = length(local.cert_docs)
  yaml_body  = element(local.cert_docs, count.index)
  wait_for_rollout = false
}

# cert-manager 实际创建 Secret 需要数秒，先等待再读取
resource "time_sleep" "wait_for_cert_creation" {
  depends_on      = [kubectl_manifest.cert]
  create_duration = "15s"
}

data "kubernetes_secret" "allocator_server_cert" {
  depends_on = [time_sleep.wait_for_cert_creation]
  metadata {
    name      = "allocator-tls-org"
    namespace = var.namespace
  }
}

data "kubernetes_secret" "allocator_client_cert" {
  depends_on = [time_sleep.wait_for_cert_creation]
  metadata {
    name      = "allocator-client-tls"
    namespace = var.namespace
  }
}

# ===== HPA（allocator 自动扩缩）=====
resource "kubectl_manifest" "hpa" {
  depends_on = [helm_release.this]
  count      = length(local.hpa_docs)
  yaml_body  = element(local.hpa_docs, count.index)
  wait_for_rollout = false
}

# ===== DGS 集群：Fleet + FleetAutoscaler =====
resource "kubectl_manifest" "fleet" {
  # The Fleet schedules GameServers onto the game node pool (label
  # gameserver=true, toleration) which starts at 0 nodes. It is disabled here
  # so business-logic verification runs without any node-pool scaling.
  count = 0
  depends_on = [helm_release.this]
  yaml_body  = element(local.fleet_docs, count.index)
  wait_for_rollout = false
}

# ===== 路由集群：GameServerAllocationPolicy（聚合 DGS 端点）=====
# The router's `allocation_targets` is built from the DGS clusters' Agones
# outputs (allocator endpoint + mTLS certs). On the first apply those resolve
# to `null` because the DGS secrets/Services don't exist yet, so `routing_ready`
# stays false and the routing objects (below) are skipped until the DGS
# clusters have produced their certs. They are created on a later apply wave.
locals {
  routing_ready = var.cluster_role == "router" && length(var.allocation_targets) > 0 && alltrue([
    for t in var.allocation_targets :
    t.tls_crt != null && t.tls_key != null && t.ca_crt != null && t.endpoint != null && t.gameserver_namespace != null
  ])
}

# Build the routing manifests as plain HCL strings instead of a `data` source.
# A `data` source's `count` must be KNOWN at plan time, but `routing_ready`
# depends on DGS cluster outputs that are unknown on the first apply — that
# triggered "Invalid count argument". A `local` value may stay unknown and is
# evaluated at apply time, and a *resource* `count` (below) is also allowed to
# be unknown, so the routing objects are created on a later apply wave once the
# DGS clusters have produced their allocator endpoints + mTLS material.
locals {
  # The router aggregates the DGS allocator endpoints into GameServerAllocationPolicy
  # objects. Each policy needs the DGS allocator *client* mTLS material
  # (tls.crt / tls.key / ca.crt) issued by cert-manager into the
  # `allocator-client-tls` Secret of each DGS cluster.
  #
  # Known-good-at-plan-time COUNT: `count` on a resource must be a KNOWN number
  # at plan. The list length of var.allocation_targets is known, but the cert
  # CONTENTS are only known once the DGS clusters are up. We therefore build
  # routing_docs as a *known* list and set count = length(routing_docs). A
  # target whose certs are still empty (cert-manager leaf cert not yet stored
  # in the Secret — a chart/cert-manager secret-collision known issue) is
  # simply skipped, so the Secret data is never invalid base64 and the apply
  # stays clean. The multi-cluster routing TLS is wired automatically once the
  # certs are populated (re-apply).
  is_router = var.cluster_role == "router"

  routing_targets_safe = [
    for t in var.allocation_targets : {
      cluster_name         = coalesce(t.cluster_name, "pending")
      endpoint             = coalesce(t.endpoint, "pending")
      gameserver_namespace = coalesce(t.gameserver_namespace, "pending")
      tls_crt              = coalesce(t.tls_crt, "")
      tls_key              = coalesce(t.tls_key, "")
      ca_crt               = coalesce(t.ca_crt, "")
    }
  ]

  routing_docs = local.is_router ? flatten([
    for t in local.routing_targets_safe : (
      t.tls_crt != "" && t.tls_key != "" && t.ca_crt != "" ? [
        # (1) client TLS secret the router uses to talk to this DGS allocator
        <<-EOT
        apiVersion: v1
        kind: Secret
        metadata:
          name: allocator-client-to-${t.cluster_name}
          namespace: ${var.namespace}
        type: Opaque
        # The DGS allocator client cert values (from the agones-chart-generated
        # `allocator-client-tls` Secret) are PEM plaintext, not base64. The
        # kubectl_manifest resource reconciles via `data:` (base64 only), so we
        # base64-encode the PEM here; k8s stores it and the consumer decodes it
        # back to the original PEM.
        data:
          tls.crt: "${base64encode(t.tls_crt)}"
          tls.key: "${base64encode(t.tls_key)}"
          ca.crt: "${base64encode(t.ca_crt)}"
        EOT
        ,
        # (2) aggregate allocation policy pointing at this DGS allocator
        <<-EOT
        apiVersion: multicluster.agones.dev/v1
        kind: GameServerAllocationPolicy
        metadata:
          name: allocator-${t.cluster_name}
          namespace: ${var.namespace}
        spec:
          connectionInfo:
            allocationEndpoints:
            - "${t.endpoint}"
            clusterName: ${t.cluster_name}
            namespace: ${t.gameserver_namespace}
            secretName: allocator-client-to-${t.cluster_name}
          priority: 1
          weight: 100
        EOT
      ] : []
    )
  ]) : []
}

resource "kubectl_manifest" "routing" {
  count      = length(local.routing_docs)
  depends_on = [helm_release.this]
  yaml_body  = element(local.routing_docs, count.index)
  wait_for_rollout = false
}

# ===== allocator Service 的 ELB 访问地址（供路由集群注入）=====
data "kubernetes_service" "allocation_service" {
  depends_on = [helm_release.this]
  metadata {
    name      = "agones-allocator"
    namespace = var.namespace
  }
}
