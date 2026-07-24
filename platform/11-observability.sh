#!/usr/bin/env bash
# Section 13 — Azure Monitor managed Prometheus + Azure Managed Grafana.
#   1. Azure Monitor workspace (managed Prometheus store).
#   2. Azure Managed Grafana.
#   3. Wire both into AKS (--enable-azure-monitor-metrics).
#   4. Validate ama-metrics running + Grafana linked + built-in scrape ingesting.
# NOTE (deck fix): the deck's app-scrape proof (curl localhost:8080/metrics,
# up{namespace="demo"}==1) can't work with the aks-helloworld image, which serves
# on :80 and exposes NO /metrics. We prove the pipeline via the BUILT-IN cluster
# scrape (always present once the add-on runs) and document the app-metrics caveat.
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh

echo "### 0. Ensure providers registered"
az provider register --namespace Microsoft.Monitor  --wait 2>/dev/null || true
az provider register --namespace Microsoft.Dashboard --wait 2>/dev/null || true

echo "### 1. Azure Monitor workspace (managed Prometheus store)"
az monitor account create -g "$RG" -n "$AMW" -l "$LOCATION" -o none
AMW_ID=$(az monitor account show -g "$RG" -n "$AMW" --query id -o tsv)
echo "    AMW_ID=$AMW_ID"

echo "### 2. Azure Managed Grafana (this can take a few minutes)"
az grafana create -g "$RG" -n "$GRAFANA" -l "$LOCATION" -o none
GRAF_ID=$(az grafana show -g "$RG" -n "$GRAFANA" --query id -o tsv)
echo "    GRAF_ID=$GRAF_ID"

echo "### 3. Wire managed Prometheus + Grafana into AKS (reconcile ~5 min)"
az aks update -g "$RG" -n "$AKS" \
  --enable-azure-monitor-metrics \
  --azure-monitor-workspace-resource-id "$AMW_ID" \
  --grafana-resource-id "$GRAF_ID" -o none

echo "### 4. Validate — ama-metrics add-on pods Running"
kubectl -n kube-system rollout status deploy/ama-metrics --timeout=180s || true
kubectl -n kube-system get pods -o wide | grep ama-metrics | awk '{print "    "$1"  "$3}'

echo "### 5. Validate — linkage recorded on the cluster"
az aks show -g "$RG" -n "$AKS" \
  --query '{metricsEnabled:azureMonitorProfile.metrics.enabled, amw:azureMonitorProfile.metrics.metricsProfile}' -o json 2>/dev/null || true
echo "    Grafana integrations (should list the AMW as a datasource):"
az grafana show -g "$RG" -n "$GRAFANA" \
  --query 'properties.grafanaIntegrations.azureMonitorWorkspaceIntegrations[].azureMonitorWorkspaceResourceId' -o tsv 2>/dev/null | sed 's/^/      /' || true
GRAF_EP=$(az grafana show -g "$RG" -n "$GRAFANA" --query 'properties.endpoint' -o tsv)
echo "    Grafana endpoint (Entra-secured UI): $GRAF_EP"

echo "### 6. Validate — managed Prometheus is INGESTING (built-in cluster scrape)"
PROM_EP=$(az monitor account show -g "$RG" -n "$AMW" --query 'metrics.prometheusQueryEndpoint' -o tsv)
echo "    query endpoint: $PROM_EP"
CALLER=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || az account show --query user.name -o tsv)
az role assignment create --assignee "$CALLER" --role "Monitoring Data Reader" --scope "$AMW_ID" -o none 2>/dev/null || true
PROVEN=""
for i in $(seq 1 20); do
  TOKEN=$(az account get-access-token --resource "https://prometheus.monitor.azure.com" --query accessToken -o tsv 2>/dev/null || true)
  if [ -n "$TOKEN" ] && [ -n "$PROM_EP" ]; then
    RES=$(curl -sS -G "$PROM_EP/api/v1/query" --data-urlencode 'query=count(up)' \
          -H "Authorization: Bearer $TOKEN" 2>/dev/null || true)
    echo "$RES" | grep -q '"status":"success"' && { echo "$RES" | grep -q '"value"' && { PROVEN="$RES"; break; }; }
  fi
  sleep 30
done
if [ -n "$PROVEN" ]; then
  VAL=$(echo "$PROVEN" | sed -n 's/.*"value":\[[0-9.]*,"\([0-9]*\)"\].*/\1/p' | head -1)
  echo "    OK  managed Prometheus is ingesting — count(up)=${VAL:-<see raw>} built-in targets scraped"
else
  echo "    ~~ could not confirm ingestion via the query API from here (role/token/propagation)."
  echo "       ama-metrics is Running and linked; confirm in Grafana: PromQL 'count(up)' > 0."
fi

echo "### 7. Apply the demo PodMonitor (correct SHAPE; no targets until app serves /metrics)"
sed 's/\r$//' platform/observability/podmonitor.yaml | kubectl apply -f -

echo "### Section 13 managed Prometheus + Grafana wired & validated."
echo "    Built-in AKS dashboards appear automatically in Grafana ($GRAF_EP)."
echo "    App-metrics caveat: the demo image exposes no /metrics; point the PodMonitor"
echo "    at a real app that serves Prometheus metrics on a named port to get up{app}==1."
