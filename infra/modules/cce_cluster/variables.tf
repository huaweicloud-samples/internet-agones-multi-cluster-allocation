variable "cluster_name" {
  description = "Name of this CCE cluster (e.g. dgs01, router)."
  type        = string
}

variable "cluster_role" {
  description = "Role of this cluster: 'dgs' deploys a Fleet; 'router' deploys GameServerAllocationPolicy objects."
  type        = string
  validation {
    condition     = contains(["dgs", "router"], var.cluster_role)
    error_message = "cluster_role must be 'dgs' or 'router'."
  }
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "key_pair_name" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "container_network_cidr" {
  description = "Pod/container network CIDR for this cluster. Must be unique per cluster within the same VPC (CCE locks the CIDR at create time)."
  type        = string
}

variable "enable_public_api_access" {
  description = "Bind a public EIP to enable public kube-apiserver access so Terraform (running outside the VPC) can manage workloads. This is a control-plane EIP, NOT a NAT gateway, so it respects the no-NAT constraint."
  type        = bool
  default     = true
}

variable "node_flavor_id" {
  type = string
}

variable "gameserver_flavor_id" {
  type = string
}

variable "node_os" {
  type = string
}

variable "cluster_flavor_id" {
  type = string
}

variable "cluster_version" {
  type = string
}

variable "lts_group_id" {
  type = string
}

variable "lts_stream_id" {
  type = string
}

variable "gameserver_allowed_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "allocator_allowed_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "cluster_endpoint_allowed_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
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

variable "hw_project_id" {
  type    = string
  default = ""
}

variable "swr_addr" {
  description = "SWR registry endpoint for mirrored chart images (no-NAT)."
  type        = string
  default     = "swr.cn-north-4.myhuaweicloud.com"
}

variable "swr_org" {
  description = "SWR organization the chart images were mirrored into."
  type        = string
  default     = "agones"
}

variable "gameserver_namespace" {
  description = "Namespace Agones pods and GameServers are placed into."
  type        = string
  default     = "default"
}

variable "allocation_targets" {
  description = "Only used when cluster_role == 'router'. Built by the root module from the DGS clusters."
  type = list(object({
    cluster_name         = string
    tls_crt              = string
    tls_key              = string
    ca_crt               = string
    endpoint             = string
    gameserver_namespace = string
  }))
  default = []
}
