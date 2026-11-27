# 部署指南（华为云 CCE）

## 1. 前置条件

- 已安装 Terraform `>= 1.10`，以及 `docker`（用于镜像同步）。
- 拥有华为云账号，具备 VPC / CCE / ELB / OBS / LTS / AOM / IAM 权限。
- 已创建 **KeyPair**（用于登录集群节点），记录其名称。
- 已开通 **SWR** 组织（用于镜像同步，规避公网 NAT）。

## 2. 凭证注入（环境变量，禁止落盘）

所有云凭证通过环境变量传入，仓库内不出现任何明文 AK/SK：

```bash
export HW_ACCESS_KEY="<你的AK>"
export HW_SECRET_KEY="<你的SK>"
export HW_REGION_NAME="cn-north-4" # provider 读取此变量
export TF_VAR_hw_access_key="$HW_ACCESS_KEY"
export TF_VAR_hw_secret_key="$HW_SECRET_KEY"
export TF_VAR_hw_project_id="<你的项目ID>"
export TF_VAR_key_pair_name="<你的KeyPair名称>"
```

> 真实 AK/SK 绝不写入任何 `.tf` 文件或提交到仓库，一律用占位符 `<HW_ACCESS_KEY>` 等表述。

## 3. 同步镜像（规避公网 NAT）

集群节点不允许走公网 NAT，因此镜像必须来自 SWR 内网镜像。先在具备出网的构建机上同步：

```bash
cd src/mirror
SWR_ADDR=swr.cn-north-4.myhuaweicloud.com SWR_ORG=agones \
SWR_USER=<iam-user> SWR_PASS=<iam-pass> ./sync-images.sh
```

同步完成后，确认 `infra/modules/agones/values.yaml` 与 `infra/modules/*/manifests/*.yaml` 中的镜像地址指向你的 SWR 组织（默认值 `swr.cn-north-4.myhuaweicloud.com/agones/...`，按需修改）。

## 4. Terraform 初始化与校验

```bash
cd infra
terraform init
terraform validate # 期望输出: The configuration is valid
terraform plan
```

## 5. 规格确认

> 云服务规格请以实际部署为准，部署前请确认所需配额与权限。

## 6. 部署

```bash
terraform apply
```

完成后关键输出（`terraform output`）：

- `allocation_service_hostname`：router 集群 allocator 的 ELB 地址（玩家连接入口）。
- `log_bucket`：OBS 桶名。

## 7. 部署后验证

1. **集群就绪**：`huaweicloud_cce_cluster` 三集群状态为 Available。
2. **Agones 健康**：各集群 `kubectl get pods -n agones` 中 controller / allocator 为 Running。
3. **多集群分配**：
- router：`kubectl get gameserverallocationpolicies -n agones` 应列出 dgs01 / dgs02。
- dgs：`kubectl get fleet,gameservers -n agones-gameserver` 应能看到 Fleet 与 GameServer。
4. **Dashboard 登录**：
```bash
kubectl -n kubernetes-dashboard get secret admin-user-token -o jsonpath='{.data.token}' | base64 -d
```
使用 token 在 Dashboard 登录。
5. **日志/指标**：在 LTS / AOM 控制台确认出现对应日志流与指标。

## 8. 销毁

```bash
terraform destroy
```

仅销毁本仓库创建的资源；请勿对同 AKSK 下其他任务创建的实例执行销毁（约束）。
