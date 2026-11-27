variable "huawei_cloud_region" {
  description = "Huawei Cloud region to deploy this sample to (e.g. cn-north-4)."
  type        = string
  default     = "cn-north-4"
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC that hosts all three CCE clusters."
  type        = string
  default     = "10.0.0.0/16"
}

# The first name in this list MUST be the routing cluster. The remaining names
# are treated as DGS (Dedicated Game Server) clusters. `main.tf` wires dgs01/dgs02
# into the router's allocation_targets.
variable "cluster_names" {
  description = "Ordered list of cluster names. The name 'router' is the routing cluster; the rest are DGS clusters."
  type        = list(string)
  default     = ["dgs01", "dgs02", "router"]
}

variable "key_pair_name" {
  description = "Name of an existing Huawei Cloud KeyPair used to log into cluster nodes."
  type        = string
}

variable "gameserver_allowed_cidrs" {
  description = "CIDRs that may reach the game server pods (UDP/TCP 7000-8000)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_endpoint_allowed_cidrs" {
  description = "CIDRs that may access the CCE cluster API endpoint (kube-apiserver)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "agones_allocator_allowed_cidrs" {
  description = "CIDRs that may reach the Agones allocator LoadBalancer Service."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_flavor_id" {
  description = "ECS flavor for the Agones system node pool (runs controller/allocator)."
  type        = string
  default     = "s6.large.2"
}

variable "gameserver_flavor_id" {
  description = "ECS flavor for the game server node pool (scales from zero)."
  type        = string
  default     = "s6.large.2"
}

variable "node_os" {
  description = "Node OS image for CCE node pools."
  type        = string
  default     = "EulerOS 2.9"
}

variable "cluster_flavor_id" {
  description = "CCE control plane flavor."
  type        = string
  default     = "cce.s1.small"
}

variable "cluster_version" {
  description = "Kubernetes version of the CCE clusters."
  type        = string
  default     = "v1.28"
}

variable "log_group_ttl_in_days" {
  description = "Retention (days) of the LTS log group."
  type        = number
  default     = 60
}

variable "log_bucket_name" {
  description = "Prefix of the OBS bucket used for ELB access logs / artifacts."
  type        = string
  default     = "agones-log-bucket"
}

# Cloud credentials for the logging/metrics pods. Supplied via environment
# (e.g. TF_VAR_hw_access_key) so nothing secret is committed.
variable "hw_access_key" {
  description = "Huawei Cloud Access Key for the logging/metrics collectors. Provide via env, not in files."
  type        = string
  default     = ""
  sensitive   = true
}

variable "hw_secret_key" {
  description = "Huawei Cloud Secret Key for the logging/metrics collectors. Provide via env, not in files."
  type        = string
  default     = ""
  sensitive   = true
}

variable "hw_project_id" {
  description = "Huawei Cloud project (tenant) ID, used by the OTel->AOM exporter."
  type        = string
  default     = ""
}

# SWR mirror coordinates for the sample's container images. Cluster nodes have
# NO public-NAT egress, so every workload image MUST be pulled from SWR (see
# src/mirror/sync-images.sh). Override here if you mirrored into a different org.
variable "swr_addr" {
  description = "SWR registry endpoint for the mirrored sample images (no-NAT enforcement)."
  type        = string
  default     = "swr.cn-north-4.myhuaweicloud.com"
}

variable "swr_org" {
  description = "SWR organization the sample images were mirrored into."
  type        = string
  # 1) Get the real value: SWR console → 右上角"我的凭证" → "通用型登录指令" / "临时登录指令"
  #    → 复制 -u 参数里 `cn-north-4@` 后面的那一段（HST3Wxxxxxxxx，组织名是租户级 ID）。
  # 2) Override per-environment (do not commit your org id into a .tfvars file):
  #      export TF_VAR_swr_org='<paste from console>'
  default = "agones"
}
