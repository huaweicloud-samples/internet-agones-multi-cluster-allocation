variable "cluster_name" {
  type = string
}
variable "cluster_role" {
  description = "router 或 dgs"
  type        = string
}
variable "namespace" {
  type    = string
  default = "agones"
}
variable "gameserver_namespace" {
  type    = string
  default = "agones-gameserver"
}
variable "allocator_allowed_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}
variable "gameserver_allowed_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}
variable "subnet_id" {
  type = string
}

variable "gameserver_image" {
  description = "SWR-synced simple-game-server image (avoids pulling from gcr.io which needs public NAT). See src/mirror/sync-images.sh."
  type        = string
  default     = "swr.cn-north-4.myhuaweicloud.com/agones/simple-game-server:0.13"
}
variable "region" {
  type    = string
  default = "cn-north-4"
}

variable "swr_addr" {
  description = "SWR registry endpoint for the mirrored Agones controller/allocator/sdk images (no-NAT)."
  type        = string
  default     = "swr.cn-north-4.myhuaweicloud.com"
}

variable "swr_org" {
  description = "SWR organization the Agones images were mirrored into."
  type        = string
  default     = "agones"
}
variable "allocation_targets" {
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
