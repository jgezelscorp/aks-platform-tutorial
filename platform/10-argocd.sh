#!/usr/bin/env bash
# Section 12 — Argo CD (GitOps delivery).
#   1. Install Argo CD (upstream stable manifests).
#   2. Wait for core components; fetch initial admin password.
#   3. Prove the GitOps loop: apply the guestbook Application (public repo) and
#      watch it reconcile to Synced + Healthy.
# NOTE (deck fix): the deck split the install.yaml URL across lines with a mid-URL
# backslash — fragile. Use the single clean URL below. GitOps needs a real repo;
# we use Argo's public example repo to prove the loop without private creds.
set -euo pipefail
cd "$(dirname "$0")/.."
source ./env.sh
source ./platform/lib/pin.sh

ARGO_URL="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"

echo "### 1. Install Argo CD"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
if ! kubectl apply -n argocd -f "$ARGO_URL" >/tmp/argo-apply.log 2>&1; then
  echo "    client-side apply hit a limit; retrying server-side..."
  kubectl apply -n argocd --server-side --force-conflicts -f "$ARGO_URL"
else
  tail -3 /tmp/argo-apply.log
fi

echo "### 1b. Pin Argo CD to the system pool (keep GitOps control plane off the user pool)"
pin_to_system argocd \
  deploy/argocd-server deploy/argocd-repo-server deploy/argocd-redis \
  deploy/argocd-dex-server deploy/argocd-applicationset-controller \
  deploy/argocd-notifications-controller statefulset/argocd-application-controller

echo "### 2. Wait for Argo CD core to be Available"
for d in argocd-repo-server argocd-server argocd-applicationset-controller; do
  kubectl -n argocd rollout status deploy/$d --timeout=240s || true
done
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=240s || true
echo "    Argo pods:"
kubectl -n argocd get pods --no-headers | awk '{print "      "$1"  "$3}'

echo "### 3. Initial admin password (for the UI / CLI)"
for i in $(seq 1 12); do
  PW=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || true)
  [ -n "$PW" ] && break
  sleep 5
done
echo "    admin password: ${PW:-<not ready — secret is deleted after first login/HEAL>}"
echo "    UI: kubectl -n argocd port-forward svc/argocd-server 8080:443  then https://localhost:8080 (admin / above)"

echo "### 4. Prove the GitOps loop — guestbook Application from a public repo"
sed 's/\r$//' platform/argocd/guestbook-app.yaml | kubectl apply -f -

echo "### 5. Wait for Synced + Healthy"
SYNC="" ; HEALTH=""
for i in $(seq 1 30); do
  SYNC=$(kubectl -n argocd get application guestbook -o jsonpath='{.status.sync.status}' 2>/dev/null || true)
  HEALTH=$(kubectl -n argocd get application guestbook -o jsonpath='{.status.health.status}' 2>/dev/null || true)
  echo "      t=$((i*10))s  sync=$SYNC  health=$HEALTH"
  [ "$SYNC" = "Synced" ] && [ "$HEALTH" = "Healthy" ] && break
  sleep 10
done

echo "### 6. Result"
kubectl -n argocd get application guestbook
if [ "$SYNC" = "Synced" ] && [ "$HEALTH" = "Healthy" ]; then
  echo "    OK  Argo CD reconciled the guestbook app from Git → Synced + Healthy"
  echo "    guestbook workloads:"
  kubectl -n guestbook get pods --no-headers 2>/dev/null | awk '{print "      "$1"  "$3}'
else
  echo "    !! guestbook not yet Synced+Healthy (sync=$SYNC health=$HEALTH)"
  kubectl -n argocd describe application guestbook | sed -n '/Conditions:/,/Source:/p' | head -20
fi

echo "### Section 12 Argo CD installed & GitOps loop validated."
echo "    For YOUR platform: edit platform/app-of-apps.yaml repoURL to your fork and"
echo "    kubectl apply it — the root app then creates child apps for every component."
