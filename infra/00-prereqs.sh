#!/usr/bin/env bash
# Section 3 — Prerequisites: register resource providers + add CLI extensions.
# Idempotent: safe to re-run. Source env.sh first for consistency (not strictly needed here).
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh

echo "### Registering resource providers (idempotent) ..."
for p in Microsoft.ContainerService \
         Microsoft.ServiceNetworking \
         Microsoft.KeyVault \
         Microsoft.Monitor \
         Microsoft.Dashboard \
         Microsoft.OperationalInsights; do
  echo "  - $p"
  az provider register --namespace "$p" --wait
done

echo "### Provider registration states:"
for p in Microsoft.ContainerService Microsoft.ServiceNetworking Microsoft.KeyVault \
         Microsoft.Monitor Microsoft.Dashboard Microsoft.OperationalInsights; do
  state=$(az provider show -n "$p" --query registrationState -o tsv)
  printf "  %-35s %s\n" "$p" "$state"
done

echo "### Adding / updating CLI extensions ..."
# --upgrade makes 'add' idempotent (installs if missing, upgrades if present).
az extension add --upgrade --name alb -y
az extension add --upgrade --name amg -y
az extension add --upgrade --name aks-preview -y

echo "### CLI + extension versions:"
az version --query '"azure-cli"' -o tsv
az extension list --query "[].{name:name, version:version}" -o table
