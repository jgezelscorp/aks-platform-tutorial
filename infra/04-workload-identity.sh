#!/usr/bin/env bash
# Section 7 — Workload Identity for the demo app.
# Creates the workload's user-assigned managed identity and federates the
# Kubernetes ServiceAccount demo/demo-sa to it (issuer + subject + audience).
# The annotated ServiceAccount itself is rendered/applied with the app (apps/deploy-demo.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh

OIDC=$(az aks show -g "$RG" -n "$AKS" --query oidcIssuerProfile.issuerUrl -o tsv)
echo "OIDC issuer: $OIDC"
[ -n "$OIDC" ] || { echo "ERROR: OIDC issuer empty — cluster missing --enable-oidc-issuer"; exit 1; }

echo "### 1. Managed identity demo-identity"
az identity create -g "$RG" -n demo-identity -o none
DEMO_CLIENT=$(az identity show -g "$RG" -n demo-identity --query clientId -o tsv)
echo "    DEMO_CLIENT=$DEMO_CLIENT"

echo "### 2. Federated credential demo-fic for system:serviceaccount:demo:demo-sa"
if az identity federated-credential show --name demo-fic -g "$RG" --identity-name demo-identity -o none 2>/dev/null; then
  echo "    federated credential already exists"
else
  az identity federated-credential create \
    --name demo-fic -g "$RG" --identity-name demo-identity \
    --issuer "$OIDC" \
    --subject system:serviceaccount:demo:demo-sa \
    --audience api://AzureADTokenExchange -o none
fi

echo "### Workload identity configured. Use DEMO_CLIENT on the demo-sa annotation."
