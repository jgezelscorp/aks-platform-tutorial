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
# Availability zones: prod-recommended is "1 2 3". Some sandbox/MCAP subs have NO
# AZ support in a region (az aks create -> AvailabilityZoneNotSupported). For those,
# run with SANDBOX_NO_ZONES=1 to deploy zone-less. See ERRATA.md.
export AKS_ZONES="1 2 3"
[ "${SANDBOX_NO_ZONES:-0}" = "1" ] && export AKS_ZONES=""
# VM size: prod default Standard_D4s_v5. Some sandbox subs disallow v5 -> override
# by exporting AKS_VM_SIZE (e.g. Standard_D4s_v6) before running. See ERRATA.md.
export AKS_VM_SIZE="${AKS_VM_SIZE:-Standard_D4s_v5}"
# Node counts: deck defaults are system 3 (3-5) + user 2 (2-6). Overridable for POC /
# capacity-constrained sandboxes (e.g. 1-node pools). See ERRATA.md.
export SYS_NODE_COUNT="${SYS_NODE_COUNT:-3}"
export SYS_MIN="${SYS_MIN:-3}"
export SYS_MAX="${SYS_MAX:-5}"
export USER_NODE_COUNT="${USER_NODE_COUNT:-2}"
export USER_MIN="${USER_MIN:-2}"
export USER_MAX="${USER_MAX:-6}"
export ADMIN_GROUP=ec66c421-c071-4642-ae43-322442d653ba
export AKS_ADMIN=ec66c421-c071-4642-ae43-322442d653ba
export AKS_DEV=28128f79-c135-4abd-9a6a-774b35d59f89
export AKS_READ=b1b2dc3c-62e3-41bc-bdb8-cc6baa5e9d66
export SUB_ID=$(az account show --query id -o tsv)
export TENANT_ID=$(az account show --query tenantId -o tsv)
#  source ./env.sh   before every section