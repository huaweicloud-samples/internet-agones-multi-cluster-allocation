# OBS bucket. 存放 ELB 访问日志与构建产物。
# Encryption 启用（SSE-OBS，华为云托管密钥）；CCE 上 Kubernetes Secret 的 KMS（DEW）
# 信封加密为可选，本样例刻意省略以保持简洁。
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "huaweicloud_obs_bucket" "log_bucket" {
  bucket        = "${var.log_bucket_name}-${random_id.bucket_suffix.hex}"
  force_destroy = true
  versioning    = true
  encryption    = true
  acl           = "private"
}
