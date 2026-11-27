# internet-agones-multi-cluster-allocation · 多集群 Agones 游戏服务器分配（华为云 CCE 最佳实践）

<img src="https://img.shields.io/badge/License-MIT--0-blue.svg" alt="License">
[![License](https://img.shields.io/badge/license-MIT--No--Attribution-green.svg)](LICENSE)
[![Huawei Cloud](https://img.shields.io/badge/Huawei%20Cloud-Best%20Practice-blue.svg)](https://www.huaweicloud.com)
[![Terraform](https://img.shields.io/badge/terraform-validated-success.svg)](https://www.terraform.io)
基于华为云 **CCE** 的多集群 Agones 示例：一个路由（router）集群聚合两个专用游戏服务器（DGS）集群的分配端点，使用 Agones Multi-Cluster Allocation 把玩家请求分配到负载最低的 DGS 集群。

## 1. 简介 / Overview

### 简介


基于华为云 **CCE** 的多集群 Agones 示例：一个路由（router）集群聚合两个专用游戏服务器（DGS）集群的分配端点，使用 Agones Multi-Cluster Allocation 把玩家请求分配到负载最低的 DGS 集群。

---

## 2. 目录

- [1. 简介 / Overview](#1-简介--overview)
- [2. 目录](#2-目录)
- [3. 架构图](#3-架构图)
- [4. 方案亮点](#4-方案亮点)
- [5. 涉及云服务](#5-涉及云服务)
- [6. 前置条件](#6-前置条件)
- [7. 快速开始](#7-快速开始)
- [8. 分步部署](#8-分步部署)
- [9. 使用方法 / 验证](#9-使用方法--验证)
- [10. 清理资源](#10-清理资源)
- [11. 详细说明](#11-详细说明)
- [12. 依赖](#12-依赖)
- [13. FAQ / 故障排除](#13-faq--故障排除)
- [14. 贡献指南](#14-贡献指南)
- [15. 许可证](#15-许可证)
- [16. 联系方式 / 维护者](#16-联系方式--维护者)


```
.
├── infra/ # Terraform 根模块 + 子模块
│ ├── versions.tf # provider 声明（huaweicloud/helm/kubernetes/kubectl/random/time）
│ ├── variables.tf # 根变量（region / cidr / flavor / 凭证变量等）
│ ├── vpc.tf / obs.tf / agency.tf / lts.tf
│ ├── main.tf / outputs.tf # 编排 3 个 CCE 集群
│ └── modules/
│ ├── cce_cluster/ # CCE 集群 + 节点池 + provider 注入 + 子模块
│ ├── cert_manager/ # cert-manager (helm)
│ ├── agones/ # Agones (helm) + 证书/HPA/Fleet/路由清单
│ ├── kubernetes_dashboard/ # Dashboard + metrics-server
│ └── logging/ # Fluent Bit + OTel → LTS/AOM
├── src/mirror/sync-images.sh # 公网镜像同步到 SWR（规避公网 NAT）
└── docs/ # architecture / deployment-guide / response-constraints
```

---

## 3. 架构图

- **router 集群**：运行 Agones controller / allocator（公网 ELB 可达），通过 `GameServerAllocationPolicy` 聚合 dgs01 / dgs02 的 mTLS 端点。
- **dgs01 / dgs02**：运行 `Fleet` + `FleetAutoscaler`，游戏服务器 Pod 调度到弹性节点池（0→30）。
- **mTLS**：cert-manager 自签证书，router 安全调用 DGS allocator。
- **可观测**：Fluent Bit + OTel Collector → **LTS**（日志）/ **AOM**（指标）；权限由 **CCE 委托（Agency）** 提供。

详见 [docs/architecture.md](docs/architecture.md)。

---

## 4. 方案亮点

- **多集群聚合分配**：单一 router 集群统一调度跨多 DGS 集群的 game server 分配请求。
- **弹性节点池**：游戏节点池 max=30，按业务弹性伸缩。
- **mTLS 安全**：cert-manager 自签证书，跨集群 allocator 调用全链路加密。
- **无公网 NAT**：节点走 SWR 内网拉镜像，客户端入站走 ELB，降低攻击面与成本。
- **完整可观测**：Fluent Bit + OTel Collector 双链路落地 LTS/AOM。

---

## 5. 涉及云服务

本实践使用以下华为云服务：

| 服务 | 用途 |
|---|---|
| CCE（云容器引擎） | 3 集群编排（router + 2 DGS） |
| LTS（日志服务） | 容器/数据面日志落地 |
| AOM（应用运维管理） | 指标采集 |
| OBS | 构建产物 / ELB 日志桶 |
| SWR | 容器镜像仓库（公网镜像同步目标） |
| IAM（Agency） | CCE 委托给 Pod 临时凭证 |

---

## 6. 前置条件

- 华为云账号，目标区域 `cn-north-4`，具备 CCE / LTS / AOM / OBS / SWR 创建权限。
- 本地：Terraform ≥ 1.5、Docker、kubectl、helm（可选）。
- 容器节点系统盘 / 数据盘规格已在 `variables.tf` 中显式写死。
- 镜像同步（公网 → SWR）需构建机出网，集群节点不出公网 NAT。
- 凭据仅经环境变量提供（`HW_ACCESS_KEY` / `HW_SECRET_KEY`），勿写入任何文件。

---

## 7. 快速开始

```bash
# 1) 凭证注入（环境变量，禁止落盘）
export HW_ACCESS_KEY="<AK>" HW_SECRET_KEY="<SK>" HW_REGION_NAME="cn-north-4"
export TF_VAR_hw_access_key="$HW_ACCESS_KEY" TF_VAR_hw_secret_key="$HW_SECRET_KEY"
export TF_VAR_hw_project_id="<projectId>" TF_VAR_key_pair_name="<keyPair>"

# 2) 同步镜像到 SWR（构建机出网，集群节点不出公网 NAT）
cd src/mirror && SWR_ADDR=swr.cn-north-4.myhuaweicloud.com SWR_ORG=agones \
SWR_USER=<u> SWR_PASS=<p> ./sync-images.sh && cd ../..

# 3) 部署
cd infra
terraform init
terraform validate
terraform plan
terraform apply
```

---

## 8. 分步部署

1. **配置环境变量**（HW_ACCESS_KEY / HW_SECRET_KEY / HW_REGION_NAME / TF_VAR_hw_* / TF_VAR_hw_project_id / TF_VAR_key_pair_name）。
2. **同步镜像到 SWR**：构建机出网把公网镜像（registry.k8s.io / docker.io 等）同步到 SWR，集群节点不出公网 NAT。
3. **Terraform 初始化与预览**：`cd infra && terraform init && terraform plan`。
4. **应用部署**：`terraform apply`，依次创建 3 个 CCE 集群 + 节点池 + 子模块。
5. **验证**：参考 `docs/deployment-guide.md` 第 7 节，逐项验证集群就绪、Agones Pod、`GameServerAllocationPolicy`、Dashboard token、LTS/AOM 数据。

---

## 9. 使用方法 / 验证

### 使用方法与验证


`terraform validate` 已通过（0 错误）。部署后验证步骤见 [docs/deployment-guide.md](docs/deployment-guide.md) 第 7 节：集群就绪、Agones Pod Running、`GameServerAllocationPolicy` 存在、Dashboard token 登录、LTS/AOM 有数据。

部署完成后请按本节步骤自行验证，确认业务功能可用，方可视为交付完成。

---

## 10. 清理资源

```bash
cd infra && terraform destroy
```

---

## 11. 详细说明

### 约束

- **凭证不落盘**：仅经环境变量提供。
- **禁止公网 NAT**：节点镜像走 SWR 内网；客户端入站走 ELB。
- **漂移忽略**：CCE 运行期改写字段用 `ignore_changes` / 变量弱约束处理。
- **仅销毁自身资源**：同 AKSK 下勿误删他方实例。

---

## 12. 依赖

- Agones 文档：https://agones.dev
- 华为云 CCE：https://support.huaweicloud.com/cce/
- 华为云 LTS / AOM / ELB / OBS 官方文档

---

## 13. FAQ / 故障排除

### FAQ


- **节点无法拉取镜像**：构建机出网同步镜像至 SWR 后，确认 `kubernetes_dashboard` 模块里 `image.repository` 已指向 SWR 路径。
- **GameServerAllocationPolicy 报 mTLS 失败**：确认 cert-manager 已成功签发 `agones-allocator-client` 证书（K8s Secret 存在）。

---

## 14. 贡献指南

欢迎提交 Issue 反馈问题或改进建议。请通过项目 Issue 渠道提交反馈。

---

## 15. 许可证

本实践采用 **MIT No Attribution** 许可证，详见仓库根目录 [`LICENSE`](LICENSE) 文件。


本实践代码基于 MIT-0 许可证发布（Copyright Huawei Cloud），详见仓库根目录 `LICENSE`。

---

## 16. 联系方式 / 维护者
| 项 | 内容 |
|---|---|
| **创建者** | [dgc-git](https://github.com/dgc-git) |
| **维护者** | [dgc-git](https://github.com/dgc-git) |
| **联系方式** | GitHub Issues / PR（见[第 14 节](#14-贡献指南)） |
