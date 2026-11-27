terraform {
  required_providers {
    huaweicloud = {
      source  = "huaweicloud/huaweicloud"
      version = ">= 1.96.0"
    }
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

data "huaweicloud_availability_zones" "this" {}

# ===== 公网 API 访问 EIP（非 NAT 网关）=====
# Terraform runs outside the VPC and cannot reach the cluster's private
# kube-apiserver endpoint, so we bind a public EIP to expose the
# control-plane API publicly for management. Disable (var.enable_public_api_access
# = false) after deployment if you want a fully private cluster — but then
# terraform can no longer push k8s changes remotely.
resource "huaweicloud_vpc_eip" "this" {
  count = var.enable_public_api_access ? 1 : 0

  publicip {
    type = "5_bgp"
  }

  bandwidth {
    name        = "${var.cluster_name}-api-eip"
    size        = 5
    share_type  = "PER"
    charge_mode = "traffic"
  }
}

# ===== CCE 集群 =====
resource "huaweicloud_cce_cluster" "this" {
  name                   = var.cluster_name
  flavor_id             = var.cluster_flavor_id
  vpc_id                = var.vpc_id
  subnet_id             = var.subnet_id
  container_network_type = "vpc-router"
  container_network_cidr = var.container_network_cidr
  cluster_version       = var.cluster_version
  authentication_mode   = "rbac"
  description           = "Agones 多集群示例 - ${var.cluster_role} 集群"

  # Bind the EIP to enable public kube-apiserver access (null = private only).
  # NOTE: CCE expects the EIP's *public IP address*, not the EIP resource id.
  eip = var.enable_public_api_access ? huaweicloud_vpc_eip.this[0].address : null
}

# ===== 集群 API 端点 + 证书，注入各 Kubernetes provider =====
# certificate_clusters[].server 为集群 API 地址；开启公网访问(eip)后该列表
# 同时含私网(RFC1918)与公网端点。Terraform 跑在 VPC 之外只能连公网端点，
# 因此优先选非私网地址的条目。该选择内联在 provider 配置里（引用集群资源
# 属性），terraform 会延迟到 apply 阶段、集群建好后再求值，避免 plan 阶段
# 对尚未创建的集群求 certificate_clusters[0] 越界。
locals {
  # internal CCE endpoints use RFC1918 prefixes and are unreachable outside VPC.
  _private_prefix = "^https://(10\\.|192\\.168\\.|172\\.(1[6-9]|2[0-9]|3[0-1])\\.)"
}

provider "kubernetes" {
  host = try(
    [for c in huaweicloud_cce_cluster.this.certificate_clusters : c.server
     if !can(regex(local._private_prefix, c.server)) && length(c.certificate_authority_data) > 0][0],
    huaweicloud_cce_cluster.this.certificate_clusters[0].server
  )
  cluster_ca_certificate = base64decode(try(
    [for c in huaweicloud_cce_cluster.this.certificate_clusters : c.certificate_authority_data
     if !can(regex(local._private_prefix, c.server)) && length(c.certificate_authority_data) > 0][0],
    huaweicloud_cce_cluster.this.certificate_clusters[0].certificate_authority_data
  ))
  client_certificate = base64decode(huaweicloud_cce_cluster.this.certificate_users[0].client_certificate_data)
  client_key         = base64decode(huaweicloud_cce_cluster.this.certificate_users[0].client_key_data)
}

# Helm 3.x accepts a single top-level `kubernetes` argument (a map of the
# standard connection keys) — the nested `kubernetes {}` block and individual
# host/cert top-level args were both removed. All cert fields are base64-decoded
# from the CCE cluster attributes (helm/kubernetes/kubectl expect PEM, CCE
# returns base64-encoded `_data` values).
provider "helm" {
  kubernetes = {
    host = try(
      [for c in huaweicloud_cce_cluster.this.certificate_clusters : c.server
       if !can(regex(local._private_prefix, c.server)) && length(c.certificate_authority_data) > 0][0],
      huaweicloud_cce_cluster.this.certificate_clusters[0].server
    )
    cluster_ca_certificate = base64decode(try(
      [for c in huaweicloud_cce_cluster.this.certificate_clusters : c.certificate_authority_data
       if !can(regex(local._private_prefix, c.server)) && length(c.certificate_authority_data) > 0][0],
      huaweicloud_cce_cluster.this.certificate_clusters[0].certificate_authority_data
    ))
    client_certificate = base64decode(huaweicloud_cce_cluster.this.certificate_users[0].client_certificate_data)
    client_key         = base64decode(huaweicloud_cce_cluster.this.certificate_users[0].client_key_data)
  }
}

provider "kubectl" {
  host = try(
    [for c in huaweicloud_cce_cluster.this.certificate_clusters : c.server
     if !can(regex(local._private_prefix, c.server)) && length(c.certificate_authority_data) > 0][0],
    huaweicloud_cce_cluster.this.certificate_clusters[0].server
  )
  cluster_ca_certificate = base64decode(try(
    [for c in huaweicloud_cce_cluster.this.certificate_clusters : c.certificate_authority_data
     if !can(regex(local._private_prefix, c.server)) && length(c.certificate_authority_data) > 0][0],
    huaweicloud_cce_cluster.this.certificate_clusters[0].certificate_authority_data
  ))
  client_certificate = base64decode(huaweicloud_cce_cluster.this.certificate_users[0].client_certificate_data)
  client_key         = base64decode(huaweicloud_cce_cluster.this.certificate_users[0].client_key_data)
  load_config_file   = false
}

# ===== 系统节点池（默认节点组）=====
resource "huaweicloud_cce_node_pool" "system" {
  cluster_id        = huaweicloud_cce_cluster.this.id
  name              = "${var.cluster_name}-system"
  flavor_id         = var.node_flavor_id
  initial_node_count = 1
  subnet_id         = var.subnet_id
  key_pair          = var.key_pair_name
  os                = var.node_os
  availability_zone = data.huaweicloud_availability_zones.this.names[0]
  labels            = { "agones.dev/agones-system" = "true" }
  scall_enable      = false

  root_volume {
    size       = 40
    volumetype = "GPSSD"
  }

  # s6.large.2 is a non-local-disk flavor, so CCE requires at least one data
  # volume on the node pool.
  data_volumes {
    size       = 100
    volumetype = "GPSSD"
  }

  # The platform may add system labels to node pools at runtime; ignore them
  # so `terraform plan` doesn't report spurious drift. (Elastic scaling
  # mutates only computed attributes, which Terraform already treats as
  # drift-free.)
  lifecycle {
    ignore_changes = [labels]
  }
}

# ===== 游戏服务器 / 弹性节点池（节点池级弹性伸缩）=====
resource "huaweicloud_cce_node_pool" "gameserver" {
  cluster_id        = huaweicloud_cce_cluster.this.id
  name              = "${var.cluster_name}-gameserver"
  flavor_id         = var.gameserver_flavor_id
  initial_node_count = 0
  min_node_count    = 0
  max_node_count    = 30
  scall_enable      = false  # 游戏节点池保持固定规模，不自动扩缩
  subnet_id         = var.subnet_id
  key_pair          = var.key_pair_name
  os                = var.node_os
  availability_zone = data.huaweicloud_availability_zones.this.names[0]
  labels            = { "gameserver" = "true" }

  root_volume {
    size       = 40
    volumetype = "GPSSD"
  }

  # s6.large.2 is a non-local-disk flavor, so CCE requires at least one data
  # volume on the node pool.
  data_volumes {
    size       = 100
    volumetype = "GPSSD"
  }

  # The platform may add system labels to node pools at runtime; ignore them
  # so `terraform plan` doesn't report spurious drift. (Elastic scaling
  # mutates only computed attributes, which Terraform already treats as
  # drift-free.)
  lifecycle {
    ignore_changes = [labels]
  }
}

# NOTE: cert-manager is deployed ONCE, inside the agones submodule
# (modules/agones/main.tf -> module.cert_manager). Deploying it again here
# would create a second Helm release named "cert-manager" in namespace
# "cert-manager" of the same cluster, colliding with the agones one
# ("cannot re-use a name that is still in use"). The agones module's
# cert-manager is the single source of truth for the allocator mTLS certs.

# ===== 子模块：Agones（含证书 / HPA / Fleet 或路由策略）=====
module "agones" {
  source = "../agones"
  providers = {
    helm       = helm
    kubernetes = kubernetes
    kubectl    = kubectl
  }

  swr_addr                        = var.swr_addr
  swr_org                         = var.swr_org
  cluster_name                    = var.cluster_name
  cluster_role                    = var.cluster_role
  namespace                       = "agones"
  gameserver_namespace            = "agones-gameserver"
  allocation_targets              = var.allocation_targets
  allocator_allowed_cidrs         = var.allocator_allowed_cidrs
  gameserver_allowed_cidrs        = var.gameserver_allowed_cidrs
  subnet_id                       = var.subnet_id
  region                          = var.region
  depends_on                      = [huaweicloud_cce_node_pool.system]
}

# ===== 子模块：Kubernetes Dashboard + metrics-server =====
module "kubernetes_dashboard" {
  source = "../kubernetes_dashboard"
  providers = {
    helm       = helm
    kubernetes = kubernetes
    kubectl    = kubectl
  }

  swr_addr = var.swr_addr
  swr_org  = var.swr_org
}

# ===== 子模块：日志 / 指标（Fluent Bit → LTS，OTel → AOM）=====
module "logging" {
  source = "../logging"
  providers = {
    kubernetes = kubernetes
    kubectl    = kubectl
  }

  region          = var.region
  project_id      = var.hw_project_id
  cluster_name    = var.cluster_name
  lts_group_id    = var.lts_group_id
  lts_stream_id   = var.lts_stream_id
  hw_access_key   = var.hw_access_key
  hw_secret_key   = var.hw_secret_key
}
