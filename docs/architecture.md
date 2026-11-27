# 架构说明（华为云）

本仓库提供一套**多集群 Agones 游戏服务器分配**最佳实践：一个路由（router）集群聚合两个专用游戏服务器（DGS, Dedicated Game Server）集群的分配端点，通过 Agones 多集群分配（Multi-Cluster Allocation）把玩家分配到负载最低的 DGS 集群。

> 本设计为华为云原生实现，所有组件均使用华为云服务与开源可复用组件，不依赖任何单一云厂商的专属控制器。

## 组件与实现

| 关注点 | 实现 | 说明 |
| --- | --- | --- |
| 容器集群 | **CCE** (Cloud Container Engine) | Kubernetes 集群 |
| 网络 | **VPC** + 子网 + **ELB** | 每集群独立子网；allocator Service 自动创建性能型四层 ELB |
| 对象存储 | **OBS** | 存储 ELB 访问日志 / 构建产物 |
| 日志 | **LTS** (Log Tank Service) | 容器日志汇聚 |
| 指标 | **AOM** (Application Operations Management) | 集群/Agones 指标 |
| 权限委托 | **CCE 委托（Agency）** | 集群工作负载通过委托获取临时凭证访问 LTS/AOM |
| 证书 | cert-manager（开源） | 签发 allocator mTLS 证书 |
| 游戏服务器框架 | Agones（开源） | 含 controller / allocator / Fleet / FleetAutoscaler |
| 弹性伸缩 | CCE 节点池弹性伸缩 | 节点池级 `scall_enable` + min/max |
| 控制台 | Kubernetes Dashboard + metrics-server（开源） | 集群可视化管理 |

## 集群拓扑

```
┌─────────────────────────────────────────────┐
玩家/客户端 ─▶│ router 集群 (CCE) │
│ agones-allocator (ELB, 公网可达) │
│ 持有 GameServerAllocationPolicy: │
│ - dgs01 (mTLS secret + endpoint) │
│ - dgs02 (mTLS secret + endpoint) │
└───────┬───────────────────────┬─────────────┘
│分配请求 (mTLS) │
┌─────────▼─────────┐ ┌─────────▼─────────┐
│ dgs01 集群 (CCE) │ │ dgs02 集群 (CCE) │
│ Fleet: dgs-fleet │ │ Fleet: dgs-fleet │
│ GameServer 池 │ │ GameServer 池 │
│ 弹性节点池(0→30) │ │ 弹性节点池(0→30) │
└────────────────────┘ └────────────────────┘
```

- **router**：只运行 Agones controller / allocator，不跑游戏服务器；通过 `GameServerAllocationPolicy` 把请求转发到 DGS 集群。
- **dgs01 / dgs02**：运行 `Fleet`（游戏服务器副本集）与 `FleetAutoscaler`（按 Buffer 策略扩缩）；游戏服务器 Pod 调度到带 `gameserver=true` 标签且允许弹性伸缩的节点池。

## 多集群 mTLS

- 每个集群由 cert-manager 自签 `allocator-tls-org`（服务端 CA）与 `allocator-client-tls`（客户端）。
- router 通过 Terraform 注入每个 DGS 集群的客户端证书 + 服务端 CA + allocator ELB 端点，构造 `GameServerAllocationPolicy`，实现对 DGS 集群的安全调用。
- 证书在 Helm 安装之外独立生成并注入，避免 Chart 重装导致 CN 失效。

## 客户端真实 IP（pass-through）

allocator Service 通过 CCE ELB 注解 `kubernetes.io/elb.pass-through: "true"` 开启透传，确保游戏服务端能拿到玩家真实 IP。

## 日志与指标链路

容器日志 → Fluent Bit（DaemonSet，OTLP）→ OTel Collector → **LTS**（日志）/ **AOM**（指标）。
OTel Collector 运行在绑定了 CCE 委托的节点上，自动获取临时凭证完成 LTS/AOM 写入鉴权。
