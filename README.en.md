# internet-agones-multi-cluster-allocation

<img src="https://img.shields.io/badge/License-MIT--0-blue.svg" alt="License">
[![License](https://img.shields.io/badge/license-MIT--No--Attribution-green.svg)](LICENSE)
[![Huawei Cloud](https://img.shields.io/badge/Huawei%20Cloud-Best%20Practice-blue.svg)](https://www.huaweicloud.com)
[![Terraform](https://img.shields.io/badge/terraform-validated-success.svg)](https://www.terraform.io)
A multi-cluster Agones example based on Huawei Cloud **CCE**: one router cluster aggregates the allocation endpoints of two dedicated game server (DGS) clusters, and Agones Multi-Cluster Allocation assigns player requests to the DGS cluster with the lowest load.

## 1. Overview

### Introduction

A multi-cluster Agones example based on Huawei Cloud **CCE**: one router cluster aggregates the allocation endpoints of two dedicated game server (DGS) clusters, and Agones Multi-Cluster Allocation assigns player requests to the DGS cluster with the lowest load.

---

## 2. Table of Contents

- [1. Overview](#1-overview)
- [2. Table of Contents](#2-table-of-contents)
- [3. Architecture Diagram](#3-architecture-diagram)
- [4. Highlights](#4-highlights)
- [5. Cloud Services Used](#5-cloud-services-used)
- [6. Prerequisites](#6-prerequisites)
- [7. Quick Start](#7-quick-start)
- [8. Step-by-Step Deployment](#8-step-by-step-deployment)
- [9. Usage / Verification](#9-usage--verification)
- [10. Cleanup](#10-cleanup)
- [11. Detailed Explanation](#11-detailed-explanation)
- [12. Dependencies](#12-dependencies)
- [13. FAQ / Troubleshooting](#13-faq--troubleshooting)
- [14. Contributing](#14-contributing)
- [15. License](#15-license)
- [16. Contact / Maintainers](#16-contact--maintainers)


```
.
├── infra/ # Terraform root module + submodules
│ ├── versions.tf # provider declarations (huaweicloud/helm/kubernetes/kubectl/random/time)
│ ├── variables.tf # root variables (region / cidr / flavor / credential variables, etc.)
│ ├── vpc.tf / obs.tf / agency.tf / lts.tf
│ ├── main.tf / outputs.tf # orchestrate 3 CCE clusters
│ └── modules/
│ ├── cce_cluster/ # CCE cluster + node pool + providers + submodules
│ ├── cert_manager/ # cert-manager (helm)
│ ├── agones/ # Agones (helm) + certificate/HPA/Fleet/router manifests
│ ├── kubernetes_dashboard/ # Dashboard + metrics-server
│ └── logging/ # Fluent Bit + OTel → LTS/AOM
├── src/mirror/sync-images.sh # sync public images to SWR (avoid public NAT)
└── docs/ # architecture / deployment-guide / response-constraints
```

---

## 3. Architecture Diagram

- **router cluster**: runs the Agones controller / allocator (reachable through a public ELB) and aggregates the mTLS endpoints of dgs01 / dgs02 through `GameServerAllocationPolicy`.
- **dgs01 / dgs02**: run `Fleet` + `FleetAutoscaler`; game server Pods are scheduled onto elastic node pools (0→30).
- **mTLS**: cert-manager self-signed certificates allow the router to call the DGS allocator securely.
- **Observability**: Fluent Bit + OTel Collector → **LTS** (logs) / **AOM** (metrics); permissions are provided by the **CCE Agency**.

See [docs/architecture.md](docs/architecture.md) for details.

---

## 4. Highlights

- **Multi-cluster aggregated allocation**: a single router cluster uniformly schedules game server allocation requests across multiple DGS clusters.
- **Elastic node pools**: the game node pool has max=30 and scales with the business load.
- **mTLS security**: cert-manager self-signed certificates encrypt the entire cross-cluster allocator call path.
- **No public NAT**: nodes pull images from SWR over the internal network and client ingress goes through the ELB, reducing the attack surface and cost.
- **Complete observability**: Fluent Bit + OTel Collector deliver dual pipelines to LTS/AOM.

---

## 5. Cloud Services Used

This practice uses the following Huawei Cloud services:

| Service | Purpose |
|---|---|
| CCE (Cloud Container Engine) | Orchestration of 3 clusters (router + 2 DGS) |
| LTS (Log Tank Service) | Container / data plane logs |
| AOM (Application Operations Management) | Metrics collection |
| OBS (Object Storage Service) | Build artifacts / ELB log bucket |
| SWR (Software Repository for Containers) | Container image registry (target for public image sync) |
| IAM (Agency) | CCE agency granting temporary credentials to Pods |

---

## 6. Prerequisites

- A Huawei Cloud account with the target region `cn-north-4` and permission to create CCE / LTS / AOM / OBS / SWR resources.
- Local tools: Terraform >= 1.5, Docker, kubectl, helm (optional).
- The container node system disk / data disk flavors are explicitly pinned in `variables.tf`.
- Image synchronization (public → SWR) requires the build machine to have outbound Internet access; cluster nodes do not use public NAT.
- Credentials are provided only through environment variables (`HW_ACCESS_KEY` / `HW_SECRET_KEY`); do not write them into any file.

---

## 7. Quick Start

```bash
# 1) Set credentials (via environment variables; do not write to disk)
export HW_ACCESS_KEY="<AK>" HW_SECRET_KEY="<SK>" HW_REGION_NAME="cn-north-4"
export TF_VAR_hw_access_key="$HW_ACCESS_KEY" TF_VAR_hw_secret_key="$HW_SECRET_KEY"
export TF_VAR_hw_project_id="<projectId>" TF_VAR_key_pair_name="<keyPair>"

# 2) Sync images to SWR (build machine has outbound access; cluster nodes do not use public NAT)
cd src/mirror && SWR_ADDR=swr.cn-north-4.myhuaweicloud.com SWR_ORG=agones \
SWR_USER=<u> SWR_PASS=<p> ./sync-images.sh && cd ../..

# 3) Deploy
cd infra
terraform init
terraform validate
terraform plan
terraform apply
```

---

## 8. Step-by-Step Deployment

1. **Set environment variables** (HW_ACCESS_KEY / HW_SECRET_KEY / HW_REGION_NAME / TF_VAR_hw_* / TF_VAR_hw_project_id / TF_VAR_key_pair_name).
2. **Sync images to SWR**: the build machine syncs public images (registry.k8s.io / docker.io, etc.) to SWR with outbound access; cluster nodes do not use public NAT.
3. **Terraform initialization and preview**: `cd infra && terraform init && terraform plan`.
4. **Apply the deployment**: `terraform apply` creates the 3 CCE clusters + node pools + submodules in order.
5. **Verify**: follow Section 7 of `docs/deployment-guide.md` to check cluster readiness, Agones Pods, `GameServerAllocationPolicy`, the Dashboard token, and LTS/AOM data item by item.

---

## 9. Usage / Verification

### Usage and Verification

`terraform validate` has passed (0 errors). The post-deployment verification steps are in Section 7 of [docs/deployment-guide.md](docs/deployment-guide.md): cluster readiness, Agones Pods Running, `GameServerAllocationPolicy` present, Dashboard token login, and data in LTS/AOM.

After deployment, follow these steps to verify that the business functionality works before considering the delivery complete.

---

## 10. Cleanup

```bash
cd infra && terraform destroy
```

---

## 11. Detailed Explanation

### Constraints

- **Credentials are not written to disk**: they are provided only through environment variables.
- **No public NAT**: node images come from SWR over the internal network; client ingress goes through the ELB.
- **Drift ignored**: runtime-rewritten CCE fields are handled with `ignore_changes` / relaxed variable constraints.
- **Destroy only your own resources**: under the same AK/SK, do not accidentally delete other parties' instances.

---

## 12. Dependencies

- Agones documentation: https://agones.dev
- Huawei Cloud CCE: https://support.huaweicloud.com/cce/
- Official Huawei Cloud documentation for LTS / AOM / ELB / OBS

---

## 13. FAQ / Troubleshooting

### FAQ

- **Nodes cannot pull images**: after the build machine syncs images to SWR, confirm that `image.repository` in the `kubernetes_dashboard` module points to the SWR path.
- **`GameServerAllocationPolicy` reports an mTLS failure**: confirm that cert-manager has successfully issued the `agones-allocator-client` certificate (the K8s Secret exists).

---

## 14. Contributing

Issues are welcome for feedback or improvement suggestions. Please submit feedback through the project Issue channel.

---

## 15. License

This practice is licensed under **MIT No Attribution**; see the [`LICENSE`](LICENSE) file in the repository root.

The code of this practice is released under the MIT-0 License (Copyright Huawei Cloud); see `LICENSE` in the repository root.

---

## 16. Contact / Maintainers
| Item | Content |
|---|---|
| **Creator** | [dgc-git](https://github.com/dgc-git) |
| **Maintainer** | [dgc-git](https://github.com/dgc-git) |
| **Contact** | GitHub Issues / PR (see [Section 14](#14-contributing)) |
