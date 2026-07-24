#!/usr/bin/env bash
# Section 4 (Steps 3-5 + Validation) — Create the AKS cluster, add user node pool,
# taint the system pool, fetch credentials, and validate the five load-bearing settings.
#
# FIX vs deck slide 23: the deck omits the trailing "\" after --generate-ssh-keys, which
# silently splits the command and makes "--enable-acns" run as a separate (failing) command.
#
# DECK FIX #2 (universal): the deck never sets --service-cidr, so AKS defaults the Kubernetes
# service CIDR to 10.0.0.0/16 — which overlaps the VNet (10.0.0.0/16) and snet-sys (10.0.0.0/22),
# failing with ServiceCidrOverlapExistingSubnetsCidr. We set a non-overlapping 172.16.0.0/16.
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh

# Self-contained: re-derive the system subnet id (works in a fresh shell).
SYS_SUBNET_ID=$(az network vnet subnet show -g "$RG" --vnet-name "$VNET" -n snet-sys --query id -o tsv)

echo "### 3. Create cluster $AKS (Azure CNI Overlay + Cilium). ~5-10 min ..."
if az aks show -g "$RG" -n "$AKS" -o none 2>/dev/null; then
  echo "    Cluster already exists; skipping create."
else
  az aks create -g "$RG" -n "$AKS" -l "$LOCATION" \
    --tier standard \
    --network-plugin azure \
    --network-plugin-mode overlay \
    --network-dataplane cilium \
    --network-policy cilium \
    --pod-cidr 10.244.0.0/16 \
    --service-cidr 172.16.0.0/16 \
    --dns-service-ip 172.16.0.10 \
    --vnet-subnet-id "$SYS_SUBNET_ID" \
    --nodepool-name systempool \
    --node-count "$SYS_NODE_COUNT" ${AKS_ZONES:+--zones $AKS_ZONES} \
    --node-vm-size "$AKS_VM_SIZE" \
    --enable-cluster-autoscaler \
    --min-count "$SYS_MIN" --max-count "$SYS_MAX" \
    --enable-aad --enable-azure-rbac \
    --aad-admin-group-object-ids "$ADMIN_GROUP" \
    --enable-oidc-issuer \
    --enable-workload-identity \
    --enable-managed-identity \
    --disable-local-accounts \
    --auto-upgrade-channel patch \
    --node-os-upgrade-channel NodeImage \
    --generate-ssh-keys \
    --enable-acns \
    -o none
fi

echo "### 4. Add user node pool (workloads)"
if az aks nodepool show -g "$RG" --cluster-name "$AKS" -n userpool -o none 2>/dev/null; then
  echo "    userpool already exists; skipping."
else
  az aks nodepool add -g "$RG" --cluster-name "$AKS" \
    --name userpool --mode User \
    --node-count "$USER_NODE_COUNT" ${AKS_ZONES:+--zones $AKS_ZONES} \
    --node-vm-size "$AKS_VM_SIZE" \
    --enable-cluster-autoscaler \
    --min-count "$USER_MIN" --max-count "$USER_MAX" \
    --labels workload=general -o none
fi

echo "### 5. Taint system pool (reserve for critical add-ons)"
az aks nodepool update -g "$RG" --cluster-name "$AKS" --name systempool \
  --node-taints CriticalAddonsOnly=true:NoSchedule -o none

echo "### 6. Get kubeconfig (Entra + Azure RBAC) and convert for non-interactive az auth"
az aks get-credentials -g "$RG" -n "$AKS" --overwrite-existing
kubelogin convert-kubeconfig -l azurecli

echo "### VALIDATION"
echo "-- nodes / zones --"
kubectl get nodes -o wide
kubectl get nodes -L topology.kubernetes.io/zone
echo "-- cilium dataplane --"
kubectl -n kube-system get pods | grep -i cilium || echo "  (no cilium pods yet)"
echo "-- OIDC issuer URL --"
az aks show -g "$RG" -n "$AKS" --query oidcIssuerProfile.issuerUrl -o tsv
echo "-- workload identity + azure rbac --"
az aks show -g "$RG" -n "$AKS" \
  --query "{wi:securityProfile.workloadIdentity.enabled, azrbac:aadProfile.enableAzureRbac}" -o yaml
echo "-- network profile (expect azure/overlay/cilium/cilium) --"
az aks show -g "$RG" -n "$AKS" --query networkProfile -o yaml
