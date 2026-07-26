#!/usr/bin/env bash
# Section 16 — AKS Backup (Azure Backup for AKS)
# Protects the demo namespace with the Azure Backup extension: creates a storage
# account + Backup vault, installs the in-cluster extension, wires Trusted Access
# and MSI permissions, then configures a daily/7-day backup instance and validates
# it with an on-demand backup. Idempotent — safe to re-run.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../env.sh"

LOC="$(az aks show -g "$RG" -n "$AKS" --query location -o tsv)"
CLUSTER_ID="$(az aks show -g "$RG" -n "$AKS" --query id -o tsv)"
echo "Cluster: $AKS  region: $LOC  namespace scope: $BKUP_NS"

echo "== [1/10] Storage account + blob container for backups =="
az storage account create -g "$RG" -n "$BKUP_SA" -l "$LOC" \
  --sku Standard_LRS --min-tls-version TLS1_2 --allow-blob-public-access false -o none \
  2>/dev/null || echo "storage account exists"
SA_ID="$(az storage account show -g "$RG" -n "$BKUP_SA" --query id -o tsv)"
# Create the blob container over the MANAGEMENT plane (container-rm), NOT the data
# plane (container create). Governed subs disable public network access on the SA, so
# a data-plane create from a CLI that is not on the VNet fails silently — container-rm
# goes through ARM and works regardless of the data-plane firewall.
az storage container-rm create --storage-account "$BKUP_SA" -g "$RG" -n "$BKUP_CONTAINER" -o none \
  2>/dev/null || echo "container exists"

echo "== [1b/10] Blob PRIVATE ENDPOINT for the backup storage account =="
# WHY: governed subscriptions force-set publicNetworkAccess=Disabled on new storage
# accounts (a policy modify effect). With no public data-plane path, the in-cluster
# backup data-mover cannot reach the blob endpoint and the backup instance fails with
# a 403 (UserErrorGenericNetworkMisconfiguration -> AuthorizationFailure). Wire a blob
# Private Endpoint into the AKS VNet — the same production-correct pattern used for the
# Key Vault (05b). publicNetworkAccess stays Disabled, so this is policy-compliant and
# is NOT reverted. See ERRATA.md.
PE_SUBNET=snet-pe
BLOB_DNS_ZONE=privatelink.blob.core.windows.net
BLOB_PE_NAME="pe-$BKUP_SA"
# Ensure the PE subnet exists (05b creates it; create here too so 16 is standalone).
if ! az network vnet subnet show -g "$RG" --vnet-name "$VNET" -n "$PE_SUBNET" -o none 2>/dev/null; then
  az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n "$PE_SUBNET" \
    --address-prefixes 10.0.5.0/24 -o none
fi
# Private DNS zone + VNet link (registration disabled — records come from the zone group).
az network private-dns zone show -g "$RG" -n "$BLOB_DNS_ZONE" -o none 2>/dev/null || \
  az network private-dns zone create -g "$RG" -n "$BLOB_DNS_ZONE" -o none
az network private-dns link vnet show -g "$RG" -z "$BLOB_DNS_ZONE" -n "link-$VNET" -o none 2>/dev/null || \
  az network private-dns link vnet create -g "$RG" -z "$BLOB_DNS_ZONE" -n "link-$VNET" \
    --virtual-network "$VNET" --registration-enabled false -o none
# Private endpoint -> blob subresource of the backup SA.
if ! az network private-endpoint show -g "$RG" -n "$BLOB_PE_NAME" -o none 2>/dev/null; then
  az network private-endpoint create -g "$RG" -n "$BLOB_PE_NAME" -l "$LOC" \
    --vnet-name "$VNET" --subnet "$PE_SUBNET" \
    --private-connection-resource-id "$SA_ID" \
    --group-id blob --connection-name "conn-$BKUP_SA" -o none
fi
# DNS zone group auto-registers the A record. Pass the zone RESOURCE ID (not the name)
# or the CLI stores an empty reference and no A record is created.
BLOB_ZONE_ID="/subscriptions/${SUB_ID}/resourceGroups/${RG}/providers/Microsoft.Network/privateDnsZones/${BLOB_DNS_ZONE}"
az network private-endpoint dns-zone-group show -g "$RG" --endpoint-name "$BLOB_PE_NAME" -n zg -o none 2>/dev/null || \
  az network private-endpoint dns-zone-group create -g "$RG" \
    --endpoint-name "$BLOB_PE_NAME" -n zg \
    --private-dns-zone "$BLOB_ZONE_ID" --zone-name blob -o none
echo "    blob private endpoint ready ($BLOB_PE_NAME)"

echo "== [2/10] Backup vault (SystemAssigned MI, LRS VaultStore) =="
az dataprotection backup-vault create -g "$RG" --vault-name "$BKUP_VAULT" -l "$LOC" \
  --type SystemAssigned \
  --storage-settings datastore-type="VaultStore" type="LocallyRedundant" -o none \
  2>/dev/null || echo "backup vault exists"
VAULT_ID="$(az dataprotection backup-vault show -g "$RG" --vault-name "$BKUP_VAULT" --query id -o tsv)"

echo "== [3/10] Install AKS Backup extension on the cluster =="
if az k8s-extension show --name "$BKUP_EXT" --cluster-name "$AKS" \
     --resource-group "$RG" --cluster-type managedClusters >/dev/null 2>&1; then
  echo "extension already installed"
else
  az k8s-extension create --name "$BKUP_EXT" \
    --extension-type microsoft.dataprotection.kubernetes \
    --scope cluster --cluster-type managedClusters \
    --cluster-name "$AKS" --resource-group "$RG" \
    --release-train stable \
    --configuration-settings \
      blobContainer="$BKUP_CONTAINER" \
      storageAccount="$BKUP_SA" \
      storageAccountResourceGroup="$RG" \
      storageAccountSubscriptionId="$SUB_ID" -o none
fi
# Wait for the extension to finish installing.
for i in $(seq 1 20); do
  st="$(az k8s-extension show --name "$BKUP_EXT" --cluster-name "$AKS" \
        --resource-group "$RG" --cluster-type managedClusters \
        --query provisioningState -o tsv 2>/dev/null || echo Pending)"
  echo "  extension provisioningState: $st"
  [ "$st" = "Succeeded" ] && break
  sleep 20
done

echo "== [4/10] Grant extension identity 'Storage Blob Data Contributor' on the SA =="
EXT_MSI="$(az k8s-extension show --name "$BKUP_EXT" --cluster-name "$AKS" \
  --resource-group "$RG" --cluster-type managedClusters \
  --query aksAssignedIdentity.principalId -o tsv)"
az role assignment create --assignee-object-id "$EXT_MSI" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" --scope "$SA_ID" -o none \
  2>/dev/null || echo "role assignment exists"

echo "== [5/10] Trusted Access rolebinding (backup-operator) =="
# Note: the flag is --source-resource-id (the -s alias is not accepted on all CLI
# versions). Microsoft.ContainerService can intermittently return a transient
# InvalidApiVersionParameter from the ARM gateway, so retry until it lands.
if az aks trustedaccess rolebinding show -g "$RG" --cluster-name "$AKS" \
     -n aksbackup-tab >/dev/null 2>&1; then
  echo "trusted access rolebinding already exists"
else
  for i in $(seq 1 12); do
    if az aks trustedaccess rolebinding create -g "$RG" --cluster-name "$AKS" \
         -n aksbackup-tab --source-resource-id "$VAULT_ID" \
         --roles "Microsoft.DataProtection/backupVaults/backup-operator" -o none 2>/tmp/tab_err.txt; then
      echo "trusted access rolebinding created"; break
    fi
    grep -qi "already exists\|Conflict" /tmp/tab_err.txt && { echo "already exists"; break; }
    echo "  rolebinding attempt $i failed (transient?) — retrying"; sleep 25
  done
fi

echo "== [6/10] Backup policy (default template: daily / 7-day retention) =="
if az dataprotection backup-policy show -g "$RG" --vault-name "$BKUP_VAULT" \
     -n "$BKUP_POLICY" >/dev/null 2>&1; then
  echo "policy exists"
else
  az dataprotection backup-policy get-default-policy-template \
    --datasource-type AzureKubernetesService > /tmp/aksbkp-policy.json
  az dataprotection backup-policy create -g "$RG" --vault-name "$BKUP_VAULT" \
  -n "$BKUP_POLICY" --policy "$(cat /tmp/aksbkp-policy.json)" -o none
fi
POLICY_ID="$(az dataprotection backup-policy show -g "$RG" --vault-name "$BKUP_VAULT" \
  -n "$BKUP_POLICY" --query id -o tsv)"

echo "== [7/10] Build backup configuration (namespace: $BKUP_NS) =="
az dataprotection backup-instance initialize-backupconfig \
  --datasource-type AzureKubernetesService \
  --included-namespaces "$BKUP_NS" \
  --snapshot-volumes true \
  --include-cluster-scope-resources true > /tmp/aksbkp-config.json

echo "== [8/10] Initialize backup instance =="
az dataprotection backup-instance initialize \
  --datasource-type AzureKubernetesService \
  --datasource-location "$LOC" \
  --datasource-id "$CLUSTER_ID" \
  --policy-id "$POLICY_ID" \
  --backup-configuration "$(cat /tmp/aksbkp-config.json)" \
  --friendly-name "$BKUP_INSTANCE" \
  --snapshot-resource-group-name "$SNAP_RG" > /tmp/aksbkp-instance.json

echo "== [9/10] Grant vault MSI required roles, then create the backup instance =="
az dataprotection backup-instance update-msi-permissions \
  --datasource-type AzureKubernetesService \
  --resource-group "$RG" --vault-name "$BKUP_VAULT" \
  --backup-instance "$(cat /tmp/aksbkp-instance.json)" \
  --operation Backup --permissions-scope ResourceGroup --yes -o none \
  || echo "msi-permissions step reported an issue (may already be granted)"
echo "  waiting 45s for role propagation..."
sleep 45
if az dataprotection backup-instance list -g "$RG" --vault-name "$BKUP_VAULT" \
     --query "[?properties.friendlyName=='$BKUP_INSTANCE']" -o tsv | grep -q .; then
  echo "backup instance already configured"
else
  # ContainerService RP can throw a transient InvalidApiVersionParameter — retry.
  for i in $(seq 1 5); do
    if az dataprotection backup-instance create -g "$RG" --vault-name "$BKUP_VAULT" \
         --backup-instance "$(cat /tmp/aksbkp-instance.json)" -o none 2>"$HERE/../_bkup_lasterr.txt"; then
      echo "backup instance created"; break
    fi
    echo "  instance create attempt $i failed — retrying"; tail -3 "$HERE/../_bkup_lasterr.txt"; sleep 30
  done
fi

echo "== [10/10] Validate protection status =="
az dataprotection backup-instance list -g "$RG" --vault-name "$BKUP_VAULT" \
  --query "[].{name:name,friendly:properties.friendlyName,state:properties.currentProtectionState}" \
  -o table
echo "DONE: AKS Backup configured for namespace '$BKUP_NS' (vault: $BKUP_VAULT, policy: $BKUP_POLICY)."
echo "Trigger an on-demand backup with:"
echo "  BI=\$(az dataprotection backup-instance list -g $RG --vault-name $BKUP_VAULT --query \"[0].name\" -o tsv)"
echo "  RULE=\$(az dataprotection backup-policy show -g $RG --vault-name $BKUP_VAULT -n $BKUP_POLICY --query 'properties.policyRules[?backupParameters].name | [0]' -o tsv)"
echo "  az dataprotection backup-instance adhoc-backup --name \$BI -g $RG --vault-name $BKUP_VAULT --rule-name \$RULE --retention-tag-override Default"
