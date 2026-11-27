# 部署运行手册（Agones 多集群 → 华为云 CCE）

> 本手册用于**构建机**（有公网、有 Docker、有 terraform、有 SWR 登录密码）
> 不在集群节点上跑任何东西。集群节点只从 SWR 拉镜像（无公网 NAT）。

## 前置条件
- terraform >= 1.10（`D:/workbuddy/terraform.exe` v1.10.5 已就绪；构建机自行安装）
- docker / podman，**且 Docker daemon 已启动**（Docker Desktop 处于 running 状态）。
⚠️ 沙箱里只有 docker 客户端、daemon 没起，所以镜像推送只能在你的构建机做。
- 华为云 AK/SK（环境变量注入，不落盘）
- **SWR 用户名 / 密码**：就是登录指令里的 `-u` / `-p`，**不是另一套凭据**，不用去控制台再生成。
你已提供的登录指令：
`docker login -u cn-north-4@HST3WK54BG2G0V67JEFH -p <从控制台临时登录指令拿> swr.cn-north-4.myhuaweicloud.com`
→ `SWR_USER = cn-north-4@HST3WK54BG2G0V67JEFH`，`SWR_PASS = <刚才 -p 后面那串>`（完整串见你控制台截图，不要粘进对话历史）。
明文密码**绝不写进脚本/仓库**，只用环境变量/命令行参数注入。
- 已确认存在：`ray-cce-keypair` 密钥对、`project_id = cc2cb3d01b0c46798d77c4cd8ecf6b7e`（cn-north-4）
- **所有 helm chart 已本地化到 `src/charts/`**（cert-manager 1.8.1 / agones 1.24.0 /
metrics-server 3.11.0 / kubernetes-dashboard 5.10.0），terraform 不再在 plan/apply 时
从外网拉 chart —— 因此原"dashboard chart 404"和"cert-manager Windows rename"两个坑已消除。

## 步骤 0：把镜像同步进 SWR（必须，沙箱做不了）
> 运行环境：一台**有公网 + Docker Desktop 已 running**的机器（你的 PC 即可）。
> 集群节点才禁公网，构建机不禁。

### 方式 A：PowerShell（推荐，无需 Git Bash）
```powershell
cd D:\workbuddy\huaweicloud\internet-agones-multi-cluster-allocation\src\mirror
$env:SWR_ADDR="swr.cn-north-4.myhuaweicloud.com"
$env:SWR_ORG="agones"
$env:SWR_USER="cn-north-4@HST3WK54BG2G0V67JEFH" # 登录指令里的 -u（注意 `cn-north-4@` 前缀不要丢）
$env:SWR_PASS="<SWR_PASS>" # 登录指令里的 -p，运行时注入
.\sync-images.ps1
```
### 方式 B：Git Bash / WSL（bash 版）
```bash
cd src/mirror
SWR_ADDR=swr.cn-north-4.myhuaweicloud.com \
SWR_ORG=agones \
SWR_USER=cn-north-4@HST3WK54BG2G0V67JEFH \
SWR_PASS=<SWR_PASS> \
./sync-images.sh
```
> 密码只出现在你自己的命令行里，不会写进任何文件。

脚本会把以下镜像推到 `swr.cn-north-4.myhuaweicloud.com/agones/*`：
- simple-game-server:0.13
- cert-manager (controller) / cert-manager-webhook / cert-manager-cainjector / cert-manager-ctl (v1.8.1)
- agones-controller / agones-allocator / agones-ping / agones-sdk (1.24.0)
- dashboard:v2.6.1 ← 注意：本地化后的 chart 是 5.10.0，默认 tag 即 v2.6.1
- metrics-server/metrics-server:v0.6.4
（metrics-scraper **已不再需要**：5.10.0 chart 不把它当子图部署；
fluent-bit / opentelemetry-collector 是华为同区域 SWR，节点无需公网即可拉，不用同步）

## 步骤 1：初始化
```bash
cd infra
export HW_ACCESS_KEY=... HW_SECRET_KEY=... HW_REGION_NAME=cn-north-4 HW_PROJECT_ID=cc2cb3d01b0c46798d77c4cd8ecf6b7e
export TF_VAR_key_pair_name=ray-cce-keypair
export TF_VAR_hw_access_key=... TF_VAR_hw_secret_key=... TF_VAR_hw_project_id=cc2cb3d01b0c46798d77c4cd8ecf6b7e
terraform init -input=false
```

## 步骤 2：阶段一 apply（只建集群/网络/agency/LTS/OBS）
> 原因：in-cluster 的 kubectl/helm provider 依赖 CCE 集群证书，而证书只有集群建好后才知道。
> 单次 `apply` 会因 `count = length(kubectl_path_documents...)` 在 plan 阶段算不出而报错。
> 所以先只把"集群 + 节点池 + VPC/子网/agency/LTS/OBS"建出来，让证书变已知。

```bash
terraform apply -auto-approve \
-target='module.dgs01.huaweicloud_cce_cluster.this' \
-target='module.dgs01.huaweicloud_cce_node_pool.system' \
-target='module.dgs01.huaweicloud_cce_node_pool.gameserver' \
-target='module.dgs02.huaweicloud_cce_cluster.this' \
-target='module.dgs02.huaweicloud_cce_node_pool.system' \
-target='module.dgs02.huaweicloud_cce_node_pool.gameserver' \
-target='module.router.huaweicloud_cce_cluster.this' \
-target='module.router.huaweicloud_cce_node_pool.system' \
-target='module.router.huaweicloud_cce_node_pool.gameserver'
```
（-target 会自动带上它们的依赖：VPC、子网、agency、LTS、OBS）

## 步骤 3：阶段二 apply（全量，含 in-cluster 工作负载）
> 此时证书已已知，kubectl/helm provider 可正常连线，agones/cert-manager/dashboard/logging 全部就绪。
```bash
terraform apply -auto-approve
```

## 步骤 4：验证 + 截图取证（L3）
1. 3 个 CCE 集群 `Running`：控制台 → CCE → 集群列表
2. agones pods：`kubectl get pods -n agones`（controller/allocator Running）
3. AllocationPolicy：`kubectl get gameserverallocationpolicy -A`（router 集群应有 dgs01/dgs02 两条）
4. Fleet/GameServer：`kubectl get fleet,gameserver -n agones-gameserver`（dgs 集群）
5. allocator ELB：CCE → 集群 → 服务 → agones-allocator 的 ELB 公网地址
6. Dashboard token：`kubectl -n kubernetes-dashboard get secret admin-user-token -o jsonpath='{.data.token}' | base64 -d`
7. LTS/AOM：控制台 → 应用运维管理 AOM / 日志 LTS，确认有 fluent-bit 上报数据

## 已知坑（按出现概率）
- ~~**dashboard chart 404**~~ —— 已解决：已将官方 chart 本地化为 `kubernetes-dashboard-5.10.0.tgz`
并移除了它内嵌的 metrics-server 子图依赖（我们已单独部署 metrics-server 3.11.0）。
- ~~**cert-manager Windows 临时目录 rename Access is denied**~~ —— 已解决：chart 改为本地
`src/charts/*.tgz` 路径，terraform 不再在 plan/apply 时从外网下载并解压到临时目录。
- 两阶段 apply 是**架构性要求**（in-cluster 的 kubectl/helm provider 依赖 apply 后才可知的
CCE 集群证书，导致 `count = length(kubectl_path_documents...)` 在 plan 期算不出），不是偶发。
- dashboard 版本从原 5.8.0 升到 5.10.0：仅 UI 镜像 tag 由 v2.7.0 变为 v2.6.1，且不再带
metrics-scraper 子图；UI 仍可通过已部署的 metrics-server 3.11.0 显示资源 metrics。
