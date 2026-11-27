# sync-images.ps1 — Windows/PowerShell port of sync-images.sh
#
# Mirrors the sample's public container images into Huawei Cloud SWR so the
# CCE nodes NEVER need public-network egress (project constraint: no public
# NAT gateway on the cluster nodes). Runs on a build host that DOES have
# internet egress (this is NOT the cluster, so the NAT ban does not apply).
#
# Usage (PowerShell):
#   $env:SWR_ADDR="swr.cn-north-4.myhuaweicloud.com"
#   $env:SWR_ORG="agones"
#   $env:SWR_USER="cn-north-4@HST3WK54BG2G0V67JEFH"   # your docker login username (-u)
#   $env:SWR_PASS="<your-swr-password>"               # your docker login password (-p)
#   .\sync-images.ps1
#
# Or pass inline (password lives only on the command line, never saved to a file):
#   .\sync-images.ps1 -SWRUser "cn-north-4@HST3WK54BG2G0V67JEFH" -SWRPass "<password>"
#
# Requires: Docker Desktop RUNNING (whale icon = "running"), PowerShell 5.1+.

param(
  [string]$SWRAddr = $env:SWR_ADDR,
  [string]$SWROrg  = $env:SWR_ORG,
  [string]$SWRUser = $env:SWR_USER,
  [string]$SWRPass = $env:SWR_PASS
)

$ErrorActionPreference = "Stop"

if (-not $SWRAddr) { Write-Error "SWR_ADDR required (e.g. swr.cn-north-4.myhuaweicloud.com)"; exit 1 }
if (-not $SWROrg)  { Write-Error "SWR_ORG required (your SWR organization name)"; exit 1 }
if (-not $SWRUser) { Write-Error "SWR_USER required (docker login username, e.g. cn-north-4@<name>)"; exit 1 }
if (-not $SWRPass) { Write-Error "SWR_PASS required (docker login password)"; exit 1 }

# Pre-flight: Docker daemon must be reachable.
docker info > $null 2>&1
if ($LASTEXITCODE -ne 0) {
  Write-Error "Docker daemon not reachable. Start Docker Desktop first (whale icon -> 'Docker Desktop running'), then retry."
  exit 1
}

Write-Host ">> Logging in to $SWRAddr" -ForegroundColor Cyan
$SWRPass | docker login $SWRAddr -u $SWRUser --password-stdin
if ($LASTEXITCODE -ne 0) { Write-Error "docker login failed"; exit 1 }

# Public source -> SWR destination. Keep in sync with infra image overrides.
$IMAGES = @(
  "gcr.io/agones-images/simple-game-server:0.13|simple-game-server:0.13"
  "quay.io/jetstack/cert-manager-controller:v1.8.1|cert-manager:v1.8.1"
  "quay.io/jetstack/cert-manager-webhook:v1.8.1|cert-manager-webhook:v1.8.1"
  "quay.io/jetstack/cert-manager-cainjector:v1.8.1|cert-manager-cainjector:v1.8.1"
  "quay.io/jetstack/cert-manager-ctl:v1.8.1|cert-manager-ctl:v1.8.1"
  "kubernetesui/dashboard:v2.6.1|dashboard:v2.6.1"
  "registry.k8s.io/metrics-server/metrics-server:v0.6.4|metrics-server/metrics-server:v0.6.4"
  "gcr.io/agones-images/agones-controller:1.24.0|agones-controller:1.24.0"
  "gcr.io/agones-images/agones-allocator:1.24.0|agones-allocator:1.24.0"
  "gcr.io/agones-images/agones-ping:1.24.0|agones-ping:1.24.0"
  "gcr.io/agones-images/agones-sdk:1.24.0|agones-sdk:1.24.0"
  "swr.cn-north-4.myhuaweicloud.com/hwcce/fluent-bit:1.9.9|fluent-bit:1.9.9"
  "swr.cn-north-4.myhuaweicloud.com/hwcce/opentelemetry-collector:0.102.0|opentelemetry-collector:0.102.0"
)

foreach ($entry in $IMAGES) {
  $parts = $entry -split '\|'
  $src  = $parts[0]
  $dst  = $parts[1]
  $target = "$SWRAddr/$SWROrg/$dst"
  Write-Host ">> $src  ->  $target" -ForegroundColor Green
  docker pull $src
  if ($LASTEXITCODE -ne 0) { Write-Error "pull failed: $src"; exit 1 }
  docker tag $src $target
  docker push $target
  if ($LASTEXITCODE -ne 0) { Write-Error "push failed: $target"; exit 1 }
  docker rmi $target > $null 2>&1
}

Write-Host ">> Done. Images mirrored into $SWRAddr/$SWROrg/. Next: terraform init && terraform plan && terraform apply." -ForegroundColor Cyan
