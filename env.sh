# ---- env.sh : single source of names ----
# LOCATION: deck default is westeurope. Override by exporting LOCATION (e.g. swedencentral)
# — e.g. when a region is capacity-constrained (AKSCapacityHeavyUsage). See ERRATA.md.
export LOCATION="${LOCATION:-westeurope}"
export PREFIX=aksplat            # your platform prefix
export ENV=dev
export RG=rg-${PREFIX}-${ENV}
export AKS=aks-${PREFIX}-${ENV}
export VNET=vnet-${PREFIX}-${ENV}
export ACR=acr${PREFIX}${ENV}    # globally unique, no dashes
export KV=kv-${PREFIX}-${ENV}    # 3-24 chars, globally unique
export AMW=amw-${PREFIX}-${ENV}  # Azure Monitor workspace
export GRAFANA=graf-${PREFIX}-${ENV}
export LAW=law-${PREFIX}-${ENV}  # Log Analytics
# ---- AKS Backup (Section 16) ----
# Backup vault + a storage account/blob container that holds backup data & metadata.
# BKUP_SA must be 3-24 lowercase alphanumerics and GLOBALLY unique — change the
# suffix if the name is taken. Snapshots land in SNAP_RG (defaults to the app RG).
export BKUP_VAULT=bvault-${PREFIX}-${ENV}
export BKUP_SA=stbkup${PREFIX}${ENV}            # 3-24 lowercase alnum, globally unique
export BKUP_CONTAINER=aksbackup
export BKUP_POLICY=aksbackuppolicy
export BKUP_EXT=azure-aks-backup               # cluster extension instance name
export BKUP_INSTANCE=aksbackup-${PREFIX}-${ENV}
export BKUP_NS="${BKUP_NS:-demo}"              # namespace scope to protect
export SNAP_RG="${SNAP_RG:-$RG}"              # resource group for disk snapshots
# Availability zones: prod-recommended is "1 2 3". Some sandbox/MCAP subs have NO
# AZ support in a region (az aks create -> AvailabilityZoneNotSupported). For those,
# run with SANDBOX_NO_ZONES=1 to deploy zone-less. See ERRATA.md.
export AKS_ZONES="1 2 3"
[ "${SANDBOX_NO_ZONES:-0}" = "1" ] && export AKS_ZONES=""
# VM sizes: the system pool hosts BOTH the AKS-managed add-ons (Cilium, CoreDNS,
# ama-*, CSI) AND the pinned platform control plane (Argo CD, Kyverno, KEDA, ALB
# controller), so it needs 4 vCPU nodes. The user pool only runs your workloads,
# so it stays frugal on 2 vCPU nodes. Some sandbox subs disallow v5 -> we use v6.
# Override either by exporting SYS_VM_SIZE / USER_VM_SIZE before running. See ERRATA.md.
export SYS_VM_SIZE="${SYS_VM_SIZE:-Standard_D4s_v6}"   # system pool: platform add-ons
export USER_VM_SIZE="${USER_VM_SIZE:-Standard_D2s_v6}" # user pool: workloads only
# Legacy single-size var kept for backward compat; SYS/USER sizes above take precedence.
export AKS_VM_SIZE="${AKS_VM_SIZE:-$SYS_VM_SIZE}"
# Node counts (validated design):
#   system pool: min 2 / max 3 — min 2 is REQUIRED (capacity + HA). The full platform
#     control plane + kube-system system pods do NOT fit on a single D4s_v6 node
#     (~3.86 vCPU allocatable), and a min-1 system pool will not reliably autoscale up.
#   user pool:   min 1 / max 3 — frugal; scales from a single node only under load.
export SYS_NODE_COUNT="${SYS_NODE_COUNT:-2}"
export SYS_MIN="${SYS_MIN:-2}"
export SYS_MAX="${SYS_MAX:-3}"
export USER_NODE_COUNT="${USER_NODE_COUNT:-1}"
export USER_MIN="${USER_MIN:-1}"
export USER_MAX="${USER_MAX:-3}"
# Entra ID group object IDs. Real values are kept OUT of source control.
# Copy env.local.sh.example -> env.local.sh and fill in your real object IDs.
# env.local.sh is git-ignored and sourced at the bottom of this file, so its
# values override the placeholders below.
export ADMIN_GROUP="<your-aks-admin-group-object-id>"
export AKS_ADMIN="<your-aks-admin-group-object-id>"
export AKS_DEV="<your-aks-developer-group-object-id>"
export AKS_READ="<your-aks-reader-group-object-id>"
export SUB_ID=$(az account show --query id -o tsv)
export TENANT_ID=$(az account show --query tenantId -o tsv)
# ---- private overrides (real IDs / secrets) — NOT committed ----
_ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
[ -f "$_ENV_DIR/env.local.sh" ] && source "$_ENV_DIR/env.local.sh"
#  source ./env.sh   before every section