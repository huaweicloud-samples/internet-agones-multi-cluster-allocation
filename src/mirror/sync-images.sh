#!/usr/bin/env bash
#
# sync-images.sh — mirror the sample's public container images into Huawei
# Cloud SWR so the CCE nodes NEVER need public-network egress (project
# constraint: no public NAT gateway on the cluster nodes).
#
# The sync runs on a CI/build host that DOES have internet egress (this is not
# the cluster, so the NAT ban does not apply here). It pulls each public image,
# re-tags it under your SWR organization, and pushes it. Cluster manifests then
# reference the SWR paths (see infra/modules/*/manifests and agones/values.yaml).
#
# Usage:
#   SWR_ADDR=swr.cn-north-4.myhuaweicloud.com \
#   SWR_ORG=agones \
#   SWR_USER=<iam-user> SWR_PASS=<iam-password-or-token> \
#   ./sync-images.sh
#
# Requires: docker (or podman), bash.
set -uo pipefail

: "${SWR_ADDR:?SWR_ADDR required, e.g. swr.cn-north-4.myhuaweicloud.com}"
: "${SWR_ORG:?SWR_ORG required, your SWR organization name}"
: "${SWR_USER:?SWR_USER required (IAM user name)}"
: "${SWR_PASS:?SWR_PASS required (IAM password or temporary token)}"

echo ">> Logging in to ${SWR_ADDR}"
echo "${SWR_PASS}" | docker login "${SWR_ADDR}" -u "${SWR_USER}" --password-stdin

# Public source -> SWR destination. Add/remove entries as the sample evolves.
# Keep these in sync with the image references in infra/modules/*/manifests/*.yaml
# and infra/modules/agones/values.yaml (agones chart images come from its repo).
IMAGES=(
  # Agones game server demo image (originally gcr.io/agones-images/simple-game-server)
  "gcr.io/agones-images/simple-game-server:0.13|simple-game-server:0.13"
  # cert-manager 1.8.1 (originally quay.io/jetstack/*). The chart references
  # four SEPARATE repos; map each to SWR keeping the same repo name so the
  # helm overrides in infra/modules/cert_manager/main.tf resolve correctly.
  "quay.io/jetstack/cert-manager-controller:v1.8.1|cert-manager:v1.8.1"
  "quay.io/jetstack/cert-manager-webhook:v1.8.1|cert-manager-webhook:v1.8.1"
  "quay.io/jetstack/cert-manager-cainjector:v1.8.1|cert-manager-cainjector:v1.8.1"
  "quay.io/jetstack/cert-manager-ctl:v1.8.1|cert-manager-ctl:v1.8.1"
  # Kubernetes Dashboard (originally kubernetesui/dashboard). The vendored chart
  # is 5.10.0 whose default tag is v2.6.1 (the upstream helm repo at
  # kubernetes.github.io/dashboard was taken down). metrics-scraper is NOT
  # deployed by 5.10.0 (no subchart dependency), so it is intentionally omitted.
  "kubernetesui/dashboard:v2.6.1|dashboard:v2.6.1"
  # metrics-server (originally registry.k8s.io/metrics-server/metrics-server).
  # Chart composes <repository>/<name>:<tag>; keep the double "metrics-server"
  # so the helm override image.repository=SWR/agones/metrics-server resolves.
  "registry.k8s.io/metrics-server/metrics-server:v0.6.4|metrics-server/metrics-server:v0.6.4"
  # Agones controller/allocator/ping/sdk (originally gcr.io/agones-images/*).
  # Redirected to SWR via the agones.image.registry helm override.
  "gcr.io/agones-images/agones-controller:1.24.0|agones-controller:1.24.0"
  "gcr.io/agones-images/agones-allocator:1.24.0|agones-allocator:1.24.0"
  "gcr.io/agones-images/agones-ping:1.24.0|agones-ping:1.24.0"
  "gcr.io/agones-images/agones-sdk:1.24.0|agones-sdk:1.24.0"
  # NOTE: fluent-bit:1.9.9 and opentelemetry-collector:0.102.0 are pulled
  # DIRECTLY from the Huawei Cloud public namespace hwcce (CCE nodes in
  # cn-north-4 reach it via the in-region SWR private link, no NAT needed).
  # The manifests in infra/modules/logging/manifests/ reference
  # swr.cn-north-4.myhuaweicloud.com/hwcce/... so they bypass SWR_ORG and
  # do NOT need to be mirrored here. Intentionally omitted from IMAGES.
)

total=0
fail=0
for entry in "${IMAGES[@]}"; do
  src="${entry%%|*}"
  dst="${entry##*|}"
  target="${SWR_ADDR}/${SWR_ORG}/${dst}"
  echo ">> ${src}  ->  ${target}"
  total=$((total + 1))
  if ! docker pull "${src}" || \
     ! docker tag  "${src}" "${target}" || \
     ! docker push "${target}"; then
    echo "!! PUSH_FAIL ${target}" >&2
    fail=$((fail + 1))
  fi
  docker rmi "${target}" >/dev/null 2>&1 || true
done

# All workload images above are now mirrored into SWR; the helm overrides in
# infra/modules/{cert_manager,agones,kubernetes_dashboard}/main.tf point every
# chart at the SWR mirror, so the CCE nodes need NO public-NAT egress.
# fluent-bit and opentelemetry-collector are pulled directly from the
# hwcce public namespace (in-region SWR private link) and are not mirrored here.
if [ "${fail}" -eq 0 ]; then
  echo ">> Done. ${total}/${total} images mirrored into ${SWR_ADDR}/${SWR_ORG}/. Next: terraform init && terraform plan && terraform apply."
else
  echo ">> Done with errors: ${fail}/${total} FAILED. See 'PUSH_FAIL' lines above. Re-run the script to retry; idempotent pushes already-succeeded images." >&2
  exit 1
fi
