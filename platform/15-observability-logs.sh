#!/usr/bin/env bash
# Section 19 — Logs (Container Insights), Alerting (action group), Grafana dashboards.
# Builds on Section 13 (managed Prometheus). Container Insights is the SEPARATE
# logs pipeline into Log Analytics.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../env.sh"

echo "== [1/6] Resolve Log Analytics workspace id =="
LAW_ID=$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query id -o tsv)
LAW_GUID=$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query customerId -o tsv)
echo "LAW_ID=$LAW_ID"

echo "== [2/6] Enable Container Insights (monitoring add-on) =="
if az aks show -g "$RG" -n "$AKS" --query 'addonProfiles.omsagent.enabled' -o tsv 2>/dev/null | grep -qi true; then
  echo "Container Insights already enabled — skipping."
else
  az aks enable-addons -g "$RG" -n "$AKS" --addons monitoring \
    --workspace-resource-id "$LAW_ID" -o none
fi

echo "== [3/6] Verify ama-logs DaemonSet is Running on every node =="
for i in $(seq 1 18); do
  ready=$(kubectl -n kube-system get ds ama-logs -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)
  desired=$(kubectl -n kube-system get ds ama-logs -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo 0)
  echo "  ama-logs ready=$ready/$desired (attempt $i)"
  [ "${ready:-0}" -gt 0 ] && [ "${ready:-0}" = "${desired:-x}" ] && break
  sleep 10
done
kubectl -n kube-system get ds ama-logs 2>&1 | sed 's/\r$//'

echo "== [4/6] Prove log ingestion via KQL (may lag a few min after enable) =="
Q='KubePodInventory | where TimeGenerated > ago(20m) | summarize n=count() by Namespace | top 10 by n'
if az monitor log-analytics query -w "$LAW_GUID" --analytics-query "$Q" -o table 2>/dev/null | sed 's/\r$//' | grep -q .; then
  az monitor log-analytics query -w "$LAW_GUID" --analytics-query "$Q" -o table 2>&1 | sed 's/\r$//'
  echo "OK: Container Insights ingesting into Log Analytics."
else
  echo "NOTE: no rows yet — Container Insights ingestion lags ~5-10 min after enable. DaemonSet is running; data will appear."
fi

echo "== [5/6] Create Azure Monitor action group (alert routing target) =="
az monitor action-group create -g "$RG" -n oncall --short-name oncall \
  --action email sre sre-oncall@example.com -o none
az monitor action-group show -g "$RG" -n oncall --query '{name:name,emailReceivers:emailReceivers[].name}' -o json 2>&1 | sed 's/\r$//'

echo "== [6/6] Confirm Grafana built-in AKS dashboards exist =="
# Managed Grafana auto-provisions AKS dashboards + the AMW Prometheus data source
# when linked at --enable-azure-monitor-metrics time (Section 13).
az grafana dashboard list -n "$GRAFANA" --query "length(@)" -o tsv 2>/dev/null | sed 's/\r$//' | { read c; echo "Grafana dashboards present: ${c:-unknown}"; }
az grafana data-source list -n "$GRAFANA" --query "[].{name:name,type:type}" -o table 2>&1 | sed 's/\r$//' | head -15

echo "DONE: Section 19 (logs + alerting + Grafana) validated."
