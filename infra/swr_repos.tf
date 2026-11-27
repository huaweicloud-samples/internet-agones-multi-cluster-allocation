# ---------------------------------------------------------------------------
# Make the mirrored workload images anonymously pullable by CCE nodes.
#
# Cluster nodes have NO public-NAT egress, so they can ONLY pull images from
# the in-region SWR registry. CCE injects an SWR pull secret (`default-secret`)
# only into the `default` ServiceAccount; the sample's workloads run under
# their own ServiceAccounts (cert-manager, agones, metrics-server, dashboard,
# logging) and therefore pull ANONYMOUSLY. The `agones` org is private, so
# those anonymous pulls return 401. Setting each repository public lets the
# kubelet pull them without a secret.
#
# 注意：`hwcce` 命名空间下 fluent-bit / opentelemetry-collector 镜像在本账号/本区域不可用。
# 这两个镜像已同步至 `agones` 命名空间（见 fluent_bit.yaml / otel.yaml），对应仓库
# 已设为公开，便于 logging DaemonSet/Deployment 无需 secret 拉取。
# ---------------------------------------------------------------------------

resource "huaweicloud_swr_repository" "cert_manager" {
  organization = var.swr_org
  name         = "cert-manager"
  is_public    = true
}

resource "huaweicloud_swr_repository" "cert_manager_webhook" {
  organization = var.swr_org
  name         = "cert-manager-webhook"
  is_public    = true
}

resource "huaweicloud_swr_repository" "cert_manager_cainjector" {
  organization = var.swr_org
  name         = "cert-manager-cainjector"
  is_public    = true
}

resource "huaweicloud_swr_repository" "cert_manager_ctl" {
  organization = var.swr_org
  name         = "cert-manager-ctl"
  is_public    = true
}

resource "huaweicloud_swr_repository" "dashboard" {
  organization = var.swr_org
  name         = "dashboard"
  is_public    = true
}

resource "huaweicloud_swr_repository" "metrics_server" {
  organization = var.swr_org
  name         = "metrics-server/metrics-server"
  is_public    = true
}

resource "huaweicloud_swr_repository" "agones_controller" {
  organization = var.swr_org
  name         = "agones-controller"
  is_public    = true
}

resource "huaweicloud_swr_repository" "agones_allocator" {
  organization = var.swr_org
  name         = "agones-allocator"
  is_public    = true
}

resource "huaweicloud_swr_repository" "agones_ping" {
  organization = var.swr_org
  name         = "agones-ping"
  is_public    = true
}

resource "huaweicloud_swr_repository" "agones_sdk" {
  organization = var.swr_org
  name         = "agones-sdk"
  is_public    = true
}

resource "huaweicloud_swr_repository" "simple_game_server" {
  organization = var.swr_org
  name         = "simple-game-server"
  is_public    = true
}

# Logging collectors — upstream used the public `hwcce` org, which is
# unavailable here, so they are mirrored into `agones` and made public.
resource "huaweicloud_swr_repository" "fluent_bit" {
  organization = var.swr_org
  name         = "fluent-bit"
  is_public    = true
}

resource "huaweicloud_swr_repository" "opentelemetry_collector" {
  organization = var.swr_org
  name         = "opentelemetry-collector"
  is_public    = true
}
