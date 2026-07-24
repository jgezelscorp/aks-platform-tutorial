#!/usr/bin/env bash
# Section 11 — Kyverno policy & governance.
#   1. Install Kyverno via Helm.
#   2. Apply 4 canonical guardrails cluster-wide in AUDIT (safe; report-only).
#   3. Prove ENFORCE blocking in a throwaway kyverno-test namespace.
#   4. Show ClusterPolicies + PolicyReports, then tear the enforce demo down.
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh

echo "### 1. Install Kyverno (Helm)"
helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null 2>&1 || true
helm repo update kyverno >/dev/null
helm upgrade --install kyverno kyverno/kyverno -n kyverno --create-namespace --wait --timeout 5m
echo "    Kyverno pods:"
kubectl -n kyverno get pods --no-headers | awk '{print "      "$1"  "$3}'
echo "    Kyverno version: $(kubectl -n kyverno get deploy kyverno-admission-controller -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | sed 's#.*:##')"

echo "### 2. Apply guardrails cluster-wide (AUDIT mode)"
envsubst '$ACR' < platform/kyverno/policies.yaml.tmpl | sed 's/\r$//' | kubectl apply -f -
echo "    Waiting for policies to be Ready..."
for p in require-labels disallow-privileged restrict-registry require-limits; do
  kubectl wait --for=condition=Ready clusterpolicy/$p --timeout=60s 2>/dev/null || true
done
kubectl get clusterpolicy

echo "### 3. ENFORCE demo — scoped to namespace kyverno-test"
kubectl create namespace kyverno-test --dry-run=client -o yaml | kubectl apply -f -
envsubst '$ACR' < platform/kyverno/enforce-demo.yaml.tmpl | sed 's/\r$//' | kubectl apply -f -
kubectl wait --for=condition=Ready clusterpolicy/kyverno-test-enforce-registry --timeout=60s 2>/dev/null || true
sleep 5

echo "### 3a. Violating pod (docker.io/nginx) — MUST be blocked"
set +e
OUT=$(kubectl -n kyverno-test run bad --image=docker.io/nginx --restart=Never 2>&1)
RC=$?
set -e
echo "$OUT" | sed 's/^/      /'
if [ $RC -ne 0 ] && echo "$OUT" | grep -qi "must come from"; then
  echo "    OK  non-compliant image BLOCKED at admission by Kyverno"
else
  echo "    !! expected a block on docker.io/nginx (rc=$RC)"
fi

echo "### 3b. Compliant pod (${ACR}.azurecr.io/...) — MUST be admitted"
set +e
OUT=$(kubectl -n kyverno-test run good --image=${ACR}.azurecr.io/demo:1.0 --restart=Never \
      --labels app.kubernetes.io/name=demo,team=platform 2>&1)
RC=$?
set -e
echo "$OUT" | sed 's/^/      /'
if [ $RC -eq 0 ]; then
  echo "    OK  compliant image ADMITTED (pod created; image pull is post-admission)"
else
  echo "    !! compliant pod was rejected unexpectedly (rc=$RC)"
fi

echo "### 4. Policy results"
kubectl get clusterpolicy
echo "    PolicyReports (demo namespace):"
kubectl get policyreport -n demo 2>/dev/null | sed 's/^/      /' || echo "      (none yet — reports populate in background)"

echo "### 5. Tear down the enforce demo (keep the 4 audit guardrails)"
kubectl delete clusterpolicy kyverno-test-enforce-registry --ignore-not-found
kubectl delete namespace kyverno-test --ignore-not-found --wait=false

echo "### Section 11 Kyverno installed & validated."
echo "    Persistent: Kyverno + 4 AUDIT guardrails. Flip to Enforce per-policy after"
echo "    reviewing PolicyReports, and always exclude system namespaces."
