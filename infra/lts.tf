# LTS (Log Tank Service) group + stream. Fluent Bit 写入应用/数据面/主机日志。
# Metrics 由 AOM 处理（见 logging module）；LTS 仅做日志落地。
resource "huaweicloud_lts_group" "agones" {
  group_name  = "agones-multi-cluster"
  ttl_in_days = var.log_group_ttl_in_days
}

resource "huaweicloud_lts_stream" "fluentbit" {
  group_id    = huaweicloud_lts_group.agones.id
  stream_name = "fluentbit-container-logs"
}
