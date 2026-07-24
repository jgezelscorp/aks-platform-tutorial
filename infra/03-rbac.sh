#!/usr/bin/env bash
# Section 6 — Entra + Azure RBAC role assignments for the cluster.
# FIX vs deck slide 36: deck uses <admin/dev/viewer-group-object-id> placeholders;
# here they are wired to the real groups exported by env.sh
# (ADMIN/AKS_ADMIN, AKS_DEV, AKS_READ). Also assigns the Cluster User Role so the
# groups can pull a kubeconfig (get-credentials), which the deck only mentions in a comment.
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh

AKS_ID=$(az aks show -g "$RG" -n "$AKS" --query id -o tsv)
echo "AKS_ID=$AKS_ID"

assign() {  # assign <group-object-id> <role> <scope>
  local grp="$1" role="$2" scope="$3"
  if az role assignment list --assignee "$grp" --role "$role" --scope "$scope" \
        --query "[0].id" -o tsv 2>/dev/null | grep -q .; then
    echo "  = already assigned: '$role' -> $grp"
  else
    az role assignment create --assignee "$grp" --role "$role" --scope "$scope" -o none
    echo "  + assigned: '$role' -> $grp"
  fi
}

echo "### Platform admins: RBAC Cluster Admin (cluster-wide)"
assign "$AKS_ADMIN" "Azure Kubernetes Service RBAC Cluster Admin" "$AKS_ID"

echo "### Developers: RBAC Writer, scoped to namespace 'demo'"
assign "$AKS_DEV" "Azure Kubernetes Service RBAC Writer" "$AKS_ID/namespaces/demo"

echo "### Read-only (SRE/on-call): RBAC Reader (cluster-wide)"
assign "$AKS_READ" "Azure Kubernetes Service RBAC Reader" "$AKS_ID"

echo "### Cluster User Role (lets each group run 'az aks get-credentials')"
for grp in "$AKS_ADMIN" "$AKS_DEV" "$AKS_READ"; do
  assign "$grp" "Azure Kubernetes Service Cluster User Role" "$AKS_ID"
done

echo "### Current assignments on the cluster scope:"
az role assignment list --scope "$AKS_ID" \
  --query "[].{principal:principalName, role:roleDefinitionName, scope:scope}" -o table
