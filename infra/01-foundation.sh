#!/usr/bin/env bash
# Section 4 (Steps 1-2) — Resource group, Log Analytics, VNet + system-node subnet.
# Idempotent: uses create commands that no-op or update if the resource exists.
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh

echo "### 1. Resource group $RG in $LOCATION"
az group create -n "$RG" -l "$LOCATION" -o none

echo "### 2. Log Analytics workspace $LAW (Container Insights sink)"
az monitor log-analytics workspace create -g "$RG" -n "$LAW" -l "$LOCATION" -o none
LAW_ID=$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query id -o tsv)
echo "    LAW_ID=$LAW_ID"

echo "### 3. VNet $VNET (10.0.0.0/16) + system subnet snet-sys (10.0.0.0/22)"
if ! az network vnet show -g "$RG" -n "$VNET" -o none 2>/dev/null; then
  az network vnet create -g "$RG" -n "$VNET" \
    --address-prefixes 10.0.0.0/16 \
    --subnet-name snet-sys \
    --subnet-prefixes 10.0.0.0/22 -o none
else
  echo "    VNet exists; ensuring snet-sys subnet is present"
  az network vnet subnet show -g "$RG" --vnet-name "$VNET" -n snet-sys -o none 2>/dev/null || \
    az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n snet-sys \
      --address-prefixes 10.0.0.0/22 -o none
fi
SYS_SUBNET_ID=$(az network vnet subnet show -g "$RG" --vnet-name "$VNET" -n snet-sys --query id -o tsv)
echo "    SYS_SUBNET_ID=$SYS_SUBNET_ID"

echo "### Foundation ready."
