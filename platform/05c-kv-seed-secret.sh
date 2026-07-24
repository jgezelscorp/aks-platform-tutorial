#!/usr/bin/env bash
# Section 8c (governance) — Seed the demo secret into the PRIVATE Key Vault from INSIDE the VNet.
#
# WHY: with publicNetworkAccess=Disabled (NIST policy), the operator's workstation cannot reach
# the KV data plane. We seed via a Kubernetes Job that runs on an AKS node (in the VNet, resolving
# the vault through the private endpoint) and authenticates as the demo workload identity.
# The demo identity is granted 'Key Vault Secrets Officer' ONLY for the duration of seeding, then
# downgraded back to read-only 'Key Vault Secrets User' (which 05-keyvault.sh already granted).
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh

export DEMO_CLIENT=$(az identity show -g "$RG" -n demo-identity --query clientId -o tsv)
DEMO_PRIN=$(az identity show -g "$RG" -n demo-identity --query principalId -o tsv)
KV_ID=$(az keyvault show -n "$KV" --query id -o tsv)
export KV_NAME="$KV" SECRET_NAME=demo-secret SECRET_VALUE='S3cr3t-from-KV'
echo "DEMO_CLIENT=$DEMO_CLIENT  KV=$KV_NAME"

echo "### 1. Namespace demo + annotated ServiceAccount demo-sa"
envsubst '$DEMO_CLIENT' < apps/demo/namespace-sa.yaml.tmpl | sed 's/\r$//' | kubectl apply -f -

echo "### 2. TEMP grant demo identity 'Key Vault Secrets Officer' (write, for seeding only)"
GRANTED=0
if ! az role assignment list --assignee "$DEMO_PRIN" --role "Key Vault Secrets Officer" --scope "$KV_ID" --query "[0].id" -o tsv 2>/dev/null | grep -q .; then
  az role assignment create --assignee "$DEMO_PRIN" --role "Key Vault Secrets Officer" --scope "$KV_ID" -o none
  GRANTED=1
  echo "    granted (will revoke after seeding); waiting 30s for RBAC + AAD propagation"
  sleep 30
else
  echo "    already had Officer"
fi

echo "### 3. Run the in-VNet seed Job"
kubectl -n demo delete job kv-seed-secret --ignore-not-found >/dev/null 2>&1 || true
# NOTE: restrict envsubst to seeding vars ONLY. $AZURE_CLIENT_ID / $AZURE_TENANT_ID /
# $AZURE_FEDERATED_TOKEN_FILE are injected into the pod by the Workload Identity webhook at
# runtime and MUST pass through literally (plain envsubst would blank them and break az login).
envsubst '$KV_NAME $SECRET_NAME $SECRET_VALUE' < platform/kv/seed-job.yaml.tmpl | sed 's/\r$//' | kubectl apply -f -
echo "    waiting for job to complete (up to 4 min)..."
if kubectl -n demo wait --for=condition=complete job/kv-seed-secret --timeout=240s 2>/dev/null; then
  SEED_RC=0
else
  SEED_RC=1
fi
echo "-- seed job logs --"
kubectl -n demo logs -l job-name=kv-seed-secret --tail=30 2>/dev/null || \
  kubectl -n demo logs job/kv-seed-secret --tail=30 2>/dev/null || \
  echo "    (no logs — job may have been GC'd)"

echo "### 4. Revoke the temporary 'Key Vault Secrets Officer' grant (keep read-only)"
if [ "$GRANTED" = "1" ]; then
  az role assignment delete --assignee "$DEMO_PRIN" --role "Key Vault Secrets Officer" --scope "$KV_ID" -o none || \
    echo "    (revoke failed — remove 'Key Vault Secrets Officer' on demo-identity manually)"
  echo "    revoked"
fi

if [ "$SEED_RC" = "0" ]; then
  echo "### Secret seeded. demo-identity is back to read-only (Secrets User)."
else
  echo "### ERROR: seed job did not complete — inspect logs above." >&2
  exit 1
fi
