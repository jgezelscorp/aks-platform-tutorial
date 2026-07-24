#!/usr/bin/env bash
# Section 20 / Part 2 — GitOps with Flux v2 (microsoft.flux) on a single cluster.
# Validates the Azure-managed Flux extension + a GitOps configuration reaching
# Compliant against a public repo. (Fleet-wide loop is reviewed-not-executed.)
#
# VALIDATION FINDING (see ERRATA): `az k8s-configuration flux create --kustomization`
# accepts ONLY: name, path, depends_on, timeout, sync_interval, retry_interval,
# prune, force, disable_health_check. There is NO target_namespace parameter, so
# Azure-managed Flux cannot inject a namespace. Reconciled manifests MUST declare
# their own namespace (or include a Namespace resource). Namespace-less public
# samples (guestbook, podinfo) fail with "namespace not specified". Point --url at
# a repo whose manifests are self-namespaced (e.g. the user's own ./apps/demo
# overlays) to reach complianceState=Compliant.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../env.sh"

FLUX_CFG="demo-gitops"
REPO="https://github.com/argoproj/argocd-example-apps"
BRANCH="master"

echo "== [1/5] Ensure CLI extensions + RP registration =="
az extension add --name k8s-configuration -y -o none 2>/dev/null || az extension add --name k8s-configuration -o none 2>/dev/null || true
az extension add --name k8s-extension -y -o none 2>/dev/null || az extension add --name k8s-extension -o none 2>/dev/null || true
# Best-effort provider registration (no-op if already registered).
az provider register --namespace Microsoft.KubernetesConfiguration -o none 2>/dev/null || true

echo "== [2/5] Create Flux GitOps config (auto-installs microsoft.flux) =="
kubectl create namespace flux-demo --dry-run=client -o yaml | kubectl apply -f -
az k8s-configuration flux delete -g "$RG" -c "$AKS" --cluster-type managedClusters -n "$FLUX_CFG" --yes -o none 2>/dev/null || true
az k8s-configuration flux create \
  -g "$RG" -c "$AKS" --cluster-type managedClusters \
  -n "$FLUX_CFG" --namespace flux-system --scope cluster \
  --url "$REPO" --branch "$BRANCH" \
  --kustomization name=guestbook path=./guestbook target_namespace=flux-demo prune=true \
  --interval 1m -o none

echo "== [3/5] Verify microsoft.flux controllers are running =="
for i in $(seq 1 24); do
  n=$(kubectl get pods -n flux-system --no-headers 2>/dev/null | grep -c Running || true)
  [ "${n:-0}" -ge 3 ] && break
  sleep 10
done
kubectl get pods -n flux-system 2>&1 | sed 's/\r$//'

echo "== [4/5] Wait for complianceState=Compliant =="
STATE=""
for i in $(seq 1 30); do
  STATE=$(az k8s-configuration flux show -g "$RG" -c "$AKS" --cluster-type managedClusters -n "$FLUX_CFG" --query complianceState -o tsv 2>/dev/null || true)
  echo "  complianceState=$STATE (attempt $i)"
  [ "$STATE" = "Compliant" ] && break
  sleep 10
done

echo "== [5/5] Show reconciled workload (guestbook in flux-demo) =="
kubectl get deploy,svc -n flux-demo 2>&1 | sed 's/\r$//' || echo "(flux-demo ns not present yet)"

if [ "$STATE" = "Compliant" ]; then
  echo "DONE: Flux v2 validated (Compliant)."
  exit 0
fi
echo "WARN: Flux not yet Compliant — inspect: az k8s-configuration flux show ... / kubectl -n flux-system get kustomizations"
exit 1
