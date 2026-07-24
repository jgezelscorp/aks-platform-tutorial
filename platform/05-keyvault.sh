#!/usr/bin/env bash
# Section 8 — Key Vault (RBAC mode) + Secrets Store CSI driver add-on.
#
# GOVERNANCE NOTE: the deck seeds the demo secret here with `az keyvault secret set` from the
# operator's workstation. That works ONLY for a PUBLIC vault. Under the NIST SP 800-53 policy on
# this subscription the vault is private (publicNetworkAccess=Disabled), so the data-plane write
# must happen from INSIDE the VNet. The vault + secret seeding therefore split into:
#   05-keyvault.sh            -> vault (control plane) + WI read grant + CSI add-on   (this file)
#   05b-kv-private-endpoint.sh-> private endpoint + private DNS
#   05c-kv-seed-secret.sh     -> seed the secret via an in-cluster workload-identity Job
# On a NON-governed sub you can instead just run `az keyvault secret set` directly (see ERRATA.md).
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh

echo "### 1. Key Vault $KV (RBAC mode)"
if az keyvault show -n "$KV" -o none 2>/dev/null; then
  echo "    vault exists"
else
  az keyvault create -g "$RG" -n "$KV" -l "$LOCATION" --enable-rbac-authorization true -o none
  echo "    created"
fi
KV_ID=$(az keyvault show -n "$KV" --query id -o tsv)

echo "### 2. Grant demo workload identity 'Key Vault Secrets User' (read at runtime)"
DEMO_PRIN=$(az identity show -g "$RG" -n demo-identity --query principalId -o tsv)
if az role assignment list --assignee "$DEMO_PRIN" --role "Key Vault Secrets User" --scope "$KV_ID" --query "[0].id" -o tsv 2>/dev/null | grep -q .; then
  echo "    already assigned"
else
  az role assignment create --assignee "$DEMO_PRIN" --role "Key Vault Secrets User" --scope "$KV_ID" -o none
  echo "    assigned"
fi

echo "### 3. Enable Secrets Store CSI add-on + rotation"
az aks enable-addons -g "$RG" -n "$AKS" \
  --addons azure-keyvault-secrets-provider \
  --enable-secret-rotation -o none 2>&1 | tail -2 || \
  echo "    (add-on may already be enabled)"

echo "### Key Vault control-plane ready. Next: 05b (private endpoint) then 05c (seed secret)."
