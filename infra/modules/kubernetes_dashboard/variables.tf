variable "swr_addr" {
  description = "SWR registry endpoint for the mirrored dashboard/metrics-server images (no-NAT)."
  type        = string
  default     = "swr.cn-north-4.myhuaweicloud.com"
}

variable "swr_org" {
  description = "SWR organization the dashboard/metrics-server images were mirrored into."
  type        = string
  default     = "agones"
}
