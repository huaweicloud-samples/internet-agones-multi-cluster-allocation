# 三个 CCE 集群（router + 两个 DGS 集群）共用一个 VPC。
# 每个集群从 VPC CIDR 中分得独立子网。
#
# IMPORTANT（项目约束）：不使用公网 NAT 网关。节点通过 VPC / 私网端点访问 SWR 镜像仓库
# 与华为云 API；面向游戏客户端的公网流量走每个 Service 的 ELB（见 agones values.yaml），
# 不走 NAT 网关。
resource "huaweicloud_vpc" "this" {
  name = "agones-multi-cluster-vpc"
  cidr = var.vpc_cidr
}

resource "huaweicloud_vpc_subnet" "this" {
  for_each   = { for i, n in var.cluster_names : n => i }
  name       = "agones-${each.key}-subnet"
  cidr       = cidrsubnet(var.vpc_cidr, 4, each.value)
  gateway_ip = cidrhost(cidrsubnet(var.vpc_cidr, 4, each.value), 1)
  vpc_id     = huaweicloud_vpc.this.id
}
