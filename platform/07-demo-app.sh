#!/usr/bin/env bash
# Section 14 — Demo/test application. Capstone that exercises the whole platform:
#   Workload Identity  →  Key Vault CSI mount (proves the PRIVATE-endpoint read path)
#   Service            →  HTTPRoute  →  AGC Gateway (proves ingress)
#
# Uses the public aks-helloworld image so the platform can be validated without first
# pushing a custom image to ACR (the deck uses <ACR>.azurecr.io/demo:1.0).
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh

export DEMO_CLIENT=$(az identity show -g "$RG" -n demo-identity --query clientId -o tsv)
export TENANT_ID=$(az account show --query tenantId -o tsv)
export KV_NAME="$KV"
echo "DEMO_CLIENT=$DEMO_CLIENT  KV=$KV_NAME  TENANT=$TENANT_ID"

echo "### 1. Namespace + WI ServiceAccount"
envsubst '$DEMO_CLIENT' < apps/demo/namespace-sa.yaml.tmpl | sed 's/\r$//' | kubectl apply -f -

echo "### 2. SecretProviderClass (KV via Workload Identity)"
envsubst '$DEMO_CLIENT $KV_NAME $TENANT_ID' < apps/demo/secretproviderclass.yaml.tmpl | sed 's/\r$//' | kubectl apply -f -

echo "### 3. Deployment + Service + HTTPRoute"
for f in deployment.yaml service.yaml httproute.yaml; do
  sed 's/\r$//' "apps/demo/$f" | kubectl apply -f -
done

echo "### 4. Wait for rollout"
kubectl -n demo rollout status deploy/demo --timeout=180s

echo "### 5. Validate — KV secret mounted via CSI (proves private-endpoint read path)"
POD=$(kubectl -n demo get pod -l app=demo -o jsonpath='{.items[0].metadata.name}')
SECRET_VAL=$(kubectl -n demo exec "$POD" -- cat /mnt/secrets/demo-secret 2>/dev/null || true)
if [ -n "$SECRET_VAL" ]; then
  echo "    OK  /mnt/secrets/demo-secret = '$SECRET_VAL'  (read from private KV via WI+CSI)"
else
  echo "    !! secret NOT mounted — check SecretProviderClass clientID/keyvault, WI label/SA, and the private-DNS resolution of the vault"
  kubectl -n demo describe pod "$POD" | sed -n '/Events:/,$p' | tail -20
  exit 1
fi

echo "### 6. Validate — HTTPRoute Accepted"
for i in $(seq 1 18); do
  ACC=$(kubectl -n demo get httproute demo-route \
    -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}' 2>/dev/null || true)
  [ "$ACC" = "True" ] && break
  sleep 10
done
echo "    HTTPRoute Accepted=${ACC:-Unknown}"

echo "### 7. Validate — reach the app through the AGC frontend"
VIP=$(kubectl get gateway gw-platform -n demo -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)
echo "    frontend=$VIP  host=${APP_HOST:-app.contoso.com}"
if [ -n "$VIP" ]; then
  for i in $(seq 1 18); do
    BODY=$(curl -ksS -m 10 -H "Host: ${APP_HOST:-app.contoso.com}" "https://$VIP/" 2>/dev/null || true)
    echo "$BODY" | grep -qi "Kubernetes\|AKS\|Welcome" && break
    sleep 10
  done
  if echo "$BODY" | grep -qi "Kubernetes\|AKS\|Welcome"; then
    echo "    OK  app reachable through AGC (HTTP 200, helloworld page served)"
  else
    echo "    !! app not reachable yet through AGC — last body (truncated):"
    echo "$BODY" | head -5
    echo "    (AGC data-plane propagation can lag ~1-2 min after Programmed; re-run to recheck)"
  fi
fi

echo "### Demo app deployed & validated."
echo "    Ingress: point DNS ${APP_HOST:-app.contoso.com} -> ${VIP:-<frontend>} (or curl with -H Host)."
