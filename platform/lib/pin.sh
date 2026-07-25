#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# pin.sh — pin platform add-on workloads to the SYSTEM node pool.
#
# WHY: the system pool is tainted `CriticalAddonsOnly=true:NoSchedule` and labeled
# `kubernetes.azure.com/mode=system`. We keep the user-installed platform control
# plane (Argo CD, Kyverno, KEDA, ALB controller) OFF the workload (user) pool and
# co-located with the AKS-managed add-ons on the system pool. To land a pod there
# we need BOTH:
#   1. a nodeSelector `kubernetes.azure.com/mode: system`  (only system-mode nodes)
#   2. a toleration for the CriticalAddonsOnly taint       (so the taint lets it in)
#
# We use the `mode=system` LABEL (not `agentpool=<name>`) so the pin survives a
# pool SKU/name change (e.g. resizing the system pool by swapping in a new pool).
#
# IMPORTANT — patch semantics: `kubectl patch --type=merge` (JSON merge patch, RFC
# 7386) RECURSIVELY merges nested objects, so it will NOT remove a pre-existing
# nodeSelector key. That is fine here because these are fresh installs with no prior
# nodeSelector. If you ever re-pin a workload that already carries a stale key (e.g.
# `agentpool: <old-pool>`), null it explicitly: nodeSelector:{"agentpool":null}.
# (tolerations is an array, which JSON merge patch replaces wholesale — good.)
#
# NOTE on capacity: because the whole control plane lands here, the system pool must
# be sized for it — Standard_D4s_v6, min 2 / max 3 (see env.sh / ERRATA E1). A min-1
# system pool cannot fit the platform + kube-system pods on one node.
# ---------------------------------------------------------------------------

PIN_PATCH='{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.azure.com/mode":"system"},"tolerations":[{"key":"CriticalAddonsOnly","operator":"Equal","value":"true","effect":"NoSchedule"}]}}}}'

# pin_to_system <namespace> <kind/name> [<kind/name> ...]
# Patches each workload's pod template. Waits briefly for the resource to exist so
# it works right after an install/apply. Safe to re-run (idempotent).
pin_to_system() {
  local ns="$1"; shift
  local res
  for res in "$@"; do
    # give the resource a moment to appear (install may still be settling)
    local ok=""
    for _ in $(seq 1 12); do
      if kubectl -n "$ns" get "$res" >/dev/null 2>&1; then ok=1; break; fi
      sleep 5
    done
    if [ -z "$ok" ]; then
      echo "      (skip) $ns/$res not found"
      continue
    fi
    if kubectl -n "$ns" patch "$res" --type=merge -p "$PIN_PATCH" >/dev/null 2>&1; then
      echo "      pinned $ns/$res -> system pool"
    else
      echo "      (warn) could not patch $ns/$res"
    fi
  done
}
