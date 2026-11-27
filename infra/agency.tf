# NOTE (2026-08-14): CCE delegated agencies are no longer created manually.
#
# 华为云关闭了为 2026-04 之后开通的账号手动创建 `cce_admin_trust` /
# `cce_cluster_agency` 的能力。CCE 现已改为自动创建替代委托（`CCEServiceAgency`、
# `CCEAutoClusterAgency`、`CCENodeAgency`）— 无需手动操作，且旧名称已无法通过 API 创建
# （返回 404 "Could not find domain: cce"，其背后含义是"该类委托已禁止创建"）。
#
# 自定义委托 `agones-cce-agency`（用于可观测性 Pod 访问的临时凭证）也已弃用：节点委托
# `CCENodeAgency` 已通过 CCE 元数据服务为工作负载 Pod 提供临时凭证，Fluent Bit / OTel
# 采集器可直接使用。详见 HUAWEI CCE 公告 cce_bulletin_0133。
#
# 集群版本必须 >= v1.28.15-r90（新委托模型）且 <= v1.28（Agones 1.24.0 上限）。
# 详见 variables.tf `cluster_version`。
