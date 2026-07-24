#!/usr/bin/env bash
# Section 5 — Application Gateway for Containers (AGC) + ALB Controller + Gateway
# Standalone/idempotent: re-derives all values from Azure. Validated companion to the deck.
#
# Deck fixes applied here:
#   1. --version <chart-version> placeholder -> resolved live via `helm show chart`.
#   2. Deck omits the required "Network Contributor" role on the delegated subnet
#      for the ALB identity -> added.
#   3. ApplicationLoadBalancer CR hardcodes literal $ALB_SUBNET_ID in YAML ->
#      rendered with envsubst before apply.
#   4. ALB CR namespace `alb-infra` is never created -> created here.
#   5. Gateway references a `demo-tls` secret that never exists -> a self-signed
#      cert is generated for validation (replace with a real/Key Vault cert in prod).
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh

echo "### 1. ALB Controller managed identity + federation + roles ..."
az identity create -g "$RG" -n alb-identity -o none 2>/dev/null || true
ALB_MI_CLIENT=$(az identity show -g "$RG" -n alb-identity --query clientId -o tsv)
ALB_MI_PRIN=$(az identity show -g "$RG" -n alb-identity --query principalId -o tsv)
OIDC=$(az aks show -g "$RG" -n "$AKS" --query oidcIssuerProfile.issuerUrl -o tsv)

# Federate the controller's ServiceAccount (azure-alb-system/alb-controller-sa)
az identity federated-credential create \
  --name alb-fic -g "$RG" --identity-name alb-identity \
  --issuer "$OIDC" \
  --subject system:serviceaccount:azure-alb-system:alb-controller-sa \
  --audience api://AzureADTokenExchange -o none 2>/dev/null || true

RG_ID=$(az group show -n "$RG" --query id -o tsv)
# 'AppGw for Containers Configuration Manager' on the RG (manage the AGC).
az role assignment create --assignee-object-id "$ALB_MI_PRIN" \
  --assignee-principal-type ServicePrincipal \
  --role 'AppGw for Containers Configuration Manager' \
  --scope "$RG_ID" -o none 2>/dev/null || true

# DECK FIX: the ALB Controller reads the AKS *node* resource group (mc_*) to place/locate
# the AGC. The deck only grants the role on the cluster RG, so the controller gets a 403
# (AuthorizationFailed on mc_*) and the Gateway never programs. Grant Config Manager + Reader
# on the node resource group as well.
NODE_RG=$(az aks show -g "$RG" -n "$AKS" --query nodeResourceGroup -o tsv)
SUB_ID=$(az account show --query id -o tsv)
NODE_RG_ID="/subscriptions/$SUB_ID/resourceGroups/$NODE_RG"
az role assignment create --assignee-object-id "$ALB_MI_PRIN" \
  --assignee-principal-type ServicePrincipal \
  --role 'AppGw for Containers Configuration Manager' \
  --scope "$NODE_RG_ID" -o none 2>/dev/null || true
az role assignment create --assignee-object-id "$ALB_MI_PRIN" \
  --assignee-principal-type ServicePrincipal \
  --role 'Reader' \
  --scope "$NODE_RG_ID" -o none 2>/dev/null || true

echo "### 2. Delegated subnet snet-alb (10.0.4.0/24) ..."
az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n snet-alb \
  --address-prefixes 10.0.4.0/24 \
  --delegations Microsoft.ServiceNetworking/trafficControllers -o none 2>/dev/null || true
export ALB_SUBNET_ID=$(az network vnet subnet show -g "$RG" --vnet-name "$VNET" -n snet-alb --query id -o tsv)

# DECK FIX: Network Contributor on the delegated subnet for the ALB identity.
az role assignment create --assignee-object-id "$ALB_MI_PRIN" \
  --assignee-principal-type ServicePrincipal \
  --role 'Network Contributor' \
  --scope "$ALB_SUBNET_ID" -o none 2>/dev/null || true

echo "### 3. Install ALB Controller (resolving real chart version) ..."
ALB_CHART=oci://mcr.microsoft.com/application-lb/charts/alb-controller
ALB_VER=$(helm show chart "$ALB_CHART" 2>/dev/null | awk '/^version:/{print $2}')
echo "    ALB controller chart version: ${ALB_VER:-<unresolved>}"
helm upgrade --install alb-controller "$ALB_CHART" \
  -n azure-alb-system --create-namespace \
  ${ALB_VER:+--version "$ALB_VER"} \
  --set albController.namespace=azure-alb-system \
  --set albController.podIdentity.clientID="$ALB_MI_CLIENT" \
  --wait --timeout 5m

echo "### 4. ApplicationLoadBalancer CR (templated subnet id) + Gateway ..."
kubectl create namespace alb-infra --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace demo --dry-run=client -o yaml | kubectl apply -f -
envsubst '$ALB_SUBNET_ID' < platform/agc/alb.yaml.tmpl | sed 's/\r$//' | kubectl apply -f -

# DECK FIX: generate the demo-tls secret the Gateway references (self-signed, validation only).
# NOTE: kubectl here is Windows kubectl.exe, which cannot read WSL /tmp paths via --cert/--key.
# So we base64-embed the cert/key into a Secret manifest and apply via stdin (path-free).
if ! kubectl get secret demo-tls -n demo >/dev/null 2>&1; then
  TLSDIR=$(mktemp -d)
  openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
    -keyout "$TLSDIR/tls.key" -out "$TLSDIR/tls.crt" \
    -subj "/CN=${APP_HOST:-app.contoso.com}" >/dev/null 2>&1
  CRT_B64=$(base64 -w0 "$TLSDIR/tls.crt")
  KEY_B64=$(base64 -w0 "$TLSDIR/tls.key")
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: demo-tls
  namespace: demo
type: kubernetes.io/tls
data:
  tls.crt: ${CRT_B64}
  tls.key: ${KEY_B64}
EOF
  rm -rf "$TLSDIR"
fi
sed 's/\r$//' platform/agc/gateway.yaml | kubectl apply -f -

# DECK FIX (robustness): if the ALB Controller was already running when the node-RG role was
# granted, its cached ARM token predates the grant and it will 403 until propagation. Restart
# the controller so it reconciles with a fresh token immediately.
kubectl -n azure-alb-system rollout restart deploy/alb-controller >/dev/null 2>&1 || true
kubectl -n azure-alb-system rollout status deploy/alb-controller --timeout=120s || true

echo "### 5. Validate — wait for Gateway PROGRAMMED=True (~1-2 min) ..."
for i in $(seq 1 30); do
  PROG=$(kubectl get gateway gw-platform -n demo \
    -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || true)
  [ "$PROG" = "True" ] && break
  sleep 10
done
kubectl get gateway gw-platform -n demo
VIP=$(kubectl get gateway gw-platform -n demo -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)
echo "Gateway PROGRAMMED=${PROG:-Unknown}  frontend=${VIP:-<pending>}"
[ "$PROG" = "True" ] || { echo "!! Gateway not Programmed — check ALB controller logs / subnet delegation / roles"; exit 1; }
echo "OK: AGC provisioned. Point DNS (${APP_HOST:-app.contoso.com}) at ${VIP}."
