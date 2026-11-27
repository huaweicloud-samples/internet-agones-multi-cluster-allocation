terraform {
  required_version = ">= 1.10.0"

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
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9.0"
    }
  }
}

# Credentials are supplied through environment variables (HW_ACCESS_KEY /
# HW_SECRET_KEY / HW_REGION_NAME). No credentials are hard-coded anywhere in
# this repository.
provider "huaweicloud" {
  region = var.huawei_cloud_region
}
