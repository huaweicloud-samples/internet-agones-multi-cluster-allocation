terraform {
  required_providers {
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

# ---------------------------------------------------------------------------
# 日志 / 指标采集器
#
# 落点：
#   * 日志   -> LTS（Log Tank Service），group/stream 在根模块创建
#   * 指标  -> AOM（Application Operations Management）
#
# 鉴权：CCE 集群启动时携带 `agency_name` 委托，Pod 可从 CCE 元数据服务获取临时
# 凭证 — 无需在代码中提交 Secret。如需回退，可经环境变量（TF_VAR_*）提供
# HW_ACCESS_KEY/HW_SECRET_KEY，由本模块投影为 K8s Secret（永不写入文件）。
# ---------------------------------------------------------------------------

variable "region" {
  type = string
}

variable "project_id" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "lts_group_id" {
  type = string
}

variable "lts_stream_id" {
  type = string
}

variable "namespace" {
  type    = string
  default = "logging"
}

variable "hw_access_key" {
  type      = string
  default   = ""
  sensitive = true
}

variable "hw_secret_key" {
  type      = string
  default   = ""
  sensitive = true
}

resource "kubernetes_namespace" "this" {
  metadata {
    name = var.namespace
  }
}

# Fallback credentials Secret — only created when AK/SK are supplied via env.
resource "kubernetes_secret" "creds" {
  count = var.hw_access_key != "" ? 1 : 0

  metadata {
    name      = "hw-logging-creds"
    namespace = var.namespace
  }

  data = {
    HW_ACCESS_KEY  = base64encode(var.hw_access_key)
    HW_SECRET_KEY  = base64encode(var.hw_secret_key)
    HW_PROJECT_ID  = base64encode(var.project_id)
    HW_REGION      = base64encode(var.region)
  }

  type = "Opaque"
}

# Fluent Bit DaemonSet: tails container logs and forwards them over OTLP to the
# OTel collector (which performs the Huawei Cloud sink signing).
#
# Document count is computed at plan time via templatefile()+split (see locals)
# instead of kubectl_path_documents, whose documents render only at apply time.
locals {
  logging_docs = {
    fluent_bit = [
      for d in split("\n---\n", replace(templatefile("${path.module}/manifests/fluent_bit.yaml", {
        namespace = var.namespace
        region    = var.region
      }), "\r\n", "\n")) : d if trimspace(d) != ""
    ]
    otel = [
      for d in split("\n---\n", replace(templatefile("${path.module}/manifests/otel.yaml", {
        namespace     = var.namespace
        region        = var.region
        project_id    = var.project_id
        cluster_name  = var.cluster_name
        lts_group_id  = var.lts_group_id
        lts_stream_id = var.lts_stream_id
      }), "\r\n", "\n")) : d if trimspace(d) != ""
    ]
  }
}

resource "kubectl_manifest" "fluent_bit" {
  count      = length(local.logging_docs["fluent_bit"])
  depends_on = [kubernetes_namespace.this]
  yaml_body  = element(local.logging_docs["fluent_bit"], count.index)
  wait_for_rollout = false
}

# OTel Collector: receives OTLP, exports metrics to AOM and logs to LTS.
resource "kubectl_manifest" "otel" {
  count      = length(local.logging_docs["otel"])
  depends_on = [kubectl_manifest.fluent_bit]
  yaml_body  = element(local.logging_docs["otel"], count.index)
  wait_for_rollout = false
}
