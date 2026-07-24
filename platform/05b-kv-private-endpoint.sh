#!/usr/bin/env bash
# Section 8b (governance) — Key Vault PRIVATE ENDPOINT + private DNS.
#
# WHY THIS EXISTS: the deck provisions a PUBLIC Key Vault. In any environment governed
# by the "NIST SP 800-53 Rev. 5" initiative (or the standalone "Key Vault should disable
# public network access" policy), the vault is force-set to publicNetworkAccess=Disabled
# by a modify effect — the instant you enable public access it flips back. With no public
# data-plane path, BOTH admin secret-seeding AND the in-cluster CSI read fail unless the
# vault is reached over a Private Endpoint. This script wires that up (the production-correct
# pattern for regulated customers). See ERRATA.md.
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh

PE_SUBNET=snet-pe
PE_PREFIX=10.0.5.0/24               # free: snet-sys=10.0.0.0/22, snet-alb=10.0.4.0/24
DNS_ZONE=privatelink.vaultcore.azure.net
PE_NAME="pe-$KV"

KV_ID=$(az keyvault show -n "$KV" --query id -o tsv)
echo "KV_ID=$KV_ID"

echo "### 1. Private-endpoint subnet $PE_SUBNET ($PE_PREFIX)"
if ! az network vnet subnet show -g "$RG" --vnet-name "$VNET" -n "$PE_SUBNET" -o none 2>/dev/null; then
  az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n "$PE_SUBNET" \
    --address-prefixes "$PE_PREFIX" -o none
  echo "    created"
else
  echo "    exists"
fi

echo "### 2. Private DNS zone $DNS_ZONE + VNet link"
az network private-dns zone show -g "$RG" -n "$DNS_ZONE" -o none 2>/dev/null || \
  az network private-dns zone create -g "$RG" -n "$DNS_ZONE" -o none
az network private-dns link vnet show -g "$RG" -z "$DNS_ZONE" -n "link-$VNET" -o none 2>/dev/null || \
  az network private-dns link vnet create -g "$RG" -z "$DNS_ZONE" -n "link-$VNET" \
    --virtual-network "$VNET" --registration-enabled false -o none
echo "    zone + link ready"

echo "### 3. Private endpoint $PE_NAME -> $KV (group-id: vault)"
if ! az network private-endpoint show -g "$RG" -n "$PE_NAME" -o none 2>/dev/null; then
  az network private-endpoint create -g "$RG" -n "$PE_NAME" -l "$LOCATION" \
    --vnet-name "$VNET" --subnet "$PE_SUBNET" \
    --private-connection-resource-id "$KV_ID" \
    --group-id vault \
    --connection-name "conn-$KV" -o none
  echo "    created"
else
  echo "    exists"
fi

echo "### 4. DNS zone group (auto-registers the A record for the PE)"
# Pass the zone RESOURCE ID (not the name) — the CLI silently stores an empty/invalid
# zone reference when given only the name, and no A record gets created.
ZONE_ID="/subscriptions/${SUB_ID}/resourceGroups/${RG}/providers/Microsoft.Network/privateDnsZones/${DNS_ZONE}"
az network private-endpoint dns-zone-group show -g "$RG" --endpoint-name "$PE_NAME" -n zg -o none 2>/dev/null || \
  az network private-endpoint dns-zone-group create -g "$RG" \
    --endpoint-name "$PE_NAME" -n zg \
    --private-dns-zone "$ZONE_ID" --zone-name vault -o none
echo "    zone group ready"

echo "### VALIDATION"
echo "-- private endpoint NIC IP --"
az network private-endpoint show -g "$RG" -n "$PE_NAME" \
  --query "customDnsConfigs[].{fqdn:fqdn, ip:ipAddresses[0]}" -o table
echo "-- private DNS A record (should map the vault FQDN to a 10.0.5.x address) --"
az network private-dns record-set a list -g "$RG" -z "$DNS_ZONE" \
  --query "[].{record:name, ip:aRecords[0].ipv4Address}" -o table
echo "### Key Vault private endpoint ready."
