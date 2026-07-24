#!/usr/bin/env bash
# Section 20 / Appendix 1 — KEDA (event-driven autoscaling)
# Enables the AKS managed KEDA add-on and proves it with a self-contained
# cron ScaledObject on the demo deployment.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../env.sh"

echo "== [1/4] Enable managed KEDA add-on =="
if az aks show -g "$RG" -n "$AKS" --query 'workloadAutoScalerProfile.keda.enabled' -o tsv 2>/dev/null | grep -qi true; then
  echo "KEDA already enabled — skipping az aks update."
else
  az aks update -g "$RG" -n "$AKS" --enable-keda -o none
fi

echo "== [2/4] Verify KEDA operator pods + CRDs =="
kubectl get pods -n kube-system | grep -i keda || { echo "FAIL: no keda pods"; exit 1; }
kubectl api-resources | grep -i keda.sh || { echo "FAIL: no keda CRDs"; exit 1; }

echo "== [3/4] Apply cron ScaledObject on demo deployment =="
sed 's/\r$//' "$HERE/keda/demo-scaledobject.yaml" | kubectl apply -f -

echo "== [4/4] Confirm KEDA created a managed HPA =="
# KEDA creates an HPA named keda-hpa-<scaledobject> that owns the deployment.
for i in $(seq 1 12); do
  if kubectl get hpa -n demo keda-hpa-demo-scaler >/dev/null 2>&1; then
    echo "OK: KEDA-managed HPA present:"
    kubectl get scaledobject,hpa -n demo
    echo "DONE: KEDA validated."
    exit 0
  fi
  sleep 5
done
echo "FAIL: KEDA HPA not created within timeout"
kubectl describe scaledobject -n demo demo-scaler | tail -30
exit 1
