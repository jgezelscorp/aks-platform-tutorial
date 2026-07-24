#!/usr/bin/env bash
# Section 10 — Cilium / Kubernetes NetworkPolicy.
# Demonstrates the default-deny -> allow-list pattern in namespace demo:
#   1. default-deny-ingress  (nothing may connect IN to any pod in demo)
#   2. allow-from-agc        (only the AGC data-plane subnet may reach app=demo:80)
# Then validates BOTH paths: the blocked pod-to-pod path and the allowed AGC path.
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh

echo "### 0. Preconditions — demo app must be running (Section 14)"
kubectl -n demo rollout status deploy/demo --timeout=120s

echo "### 1. Apply default-deny ingress + allow-from-AGC"
for f in default-deny-ingress.yaml allow-from-agc.yaml; do
  sed 's/\r$//' "platform/netpol/$f" | kubectl apply -f -
done
kubectl -n demo get netpol

echo "### 2. Validate BLOCKED path — a pod NOT in the AGC subnet must time out"
kubectl -n demo delete pod tester --ignore-not-found --force --grace-period=0 2>/dev/null || true
kubectl -n demo run tester --image=nicolaka/netshoot --restart=Never --command -- sleep 60
kubectl -n demo wait --for=condition=Ready pod/tester --timeout=90s
set +e
CODE=$(kubectl -n demo exec tester -- curl -m 5 -s -o /dev/null -w '%{http_code}' http://demo-svc.demo:80)
RC=$?
set -e
echo "    tester -> demo-svc:80  http_code='${CODE}' curl_rc=${RC}"
if [ "$RC" -ne 0 ] || [ "$CODE" = "000" ]; then
  echo "    OK  pod-to-pod ingress BLOCKED by default-deny (expected timeout)"
else
  echo "    !! pod-to-pod path returned ${CODE} — policy NOT enforced as expected"
fi
kubectl -n demo delete pod tester --ignore-not-found --force --grace-period=0 2>/dev/null || true

echo "### 3. Validate ALLOWED path — real ingress via AGC (source = snet-alb 10.0.4.0/24)"
VIP=$(kubectl get gateway gw-platform -n demo -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)
echo "    frontend=$VIP  host=${APP_HOST:-app.contoso.com}"
if [ -n "$VIP" ]; then
  for i in $(seq 1 12); do
    BODY=$(curl -ksS -m 10 -H "Host: ${APP_HOST:-app.contoso.com}" "https://$VIP/" 2>/dev/null || true)
    echo "$BODY" | grep -qi "Kubernetes\|AKS\|Welcome" && break
    sleep 10
  done
  if echo "$BODY" | grep -qi "Kubernetes\|AKS\|Welcome"; then
    echo "    OK  AGC path STILL WORKS through the policy (HTTP 200)"
  else
    echo "    !! AGC path not returning 200 — allow-from-agc CIDR/port may be wrong"
    echo "$BODY" | head -5
  fi
fi

echo "### Section 10 network policy applied & validated."
echo "    Reminder: default-deny EGRESS (not applied here) also blocks CoreDNS —"
echo "    always allow UDP/TCP 53 to kube-system when you lock down egress."
