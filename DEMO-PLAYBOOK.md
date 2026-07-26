# 🎬 AKS Platform — Live Demo Playbook

> **Audience:** your customer walkthrough · **Presenter level:** beginner-friendly · **Duration:** ~45–60 min (modular — skip any block)
> **Companion to:** `TUTORIAL.md` (build guide). This playbook assumes the platform is **already deployed and running** in your environment. You are here to *show it off*, not build it.

This is a **read-and-run script**. Every block is copy-paste. For each feature you get three parts:

| Part | Meaning |
|------|---------|
| 🟦 **What** | One or two sentences to *say* to the customer — the concept. |
| ⚙️ **How** | The exact commands to *run*, in order. Copy the whole block. |
| ✅ **Prove** | The command whose output *demonstrates it works* — your "wow" moment. Read the output out loud. |

> [!IMPORTANT]
> Run **Module 0 (Pre-flight)** ~10 minutes before the customer joins. It connects you to the cluster and confirms everything is green so nothing surprises you live.

---

## Table of contents

- [Module 0 — Pre-flight & connect](#module-0--pre-flight--connect)
- [Module 1 — The platform at a glance (node pools & pinning)](#module-1--the-platform-at-a-glance-node-pools--pinning)
- [Module 2 — Secretless secrets (Workload Identity + Key Vault CSI)](#module-2--secretless-secrets-workload-identity--key-vault-csi)
- [Module 3 — Ingress with Application Gateway for Containers](#module-3--ingress-with-application-gateway-for-containers)
- [Module 4 — App delivery with Kustomize](#module-4--app-delivery-with-kustomize)
- [Module 5 — Cilium network policy (block & allow, live)](#module-5--cilium-network-policy-block--allow-live)
- [Module 6 — Hubble flow visibility (ACNS)](#module-6--hubble-flow-visibility-acns)
- [Module 7 — Kyverno policy governance (block a bad deploy)](#module-7--kyverno-policy-governance-block-a-bad-deploy)
- [Module 8 — GitOps with Argo CD (self-heal)](#module-8--gitops-with-argo-cd-self-heal)
- [Module 9 — GitOps with Flux (Azure-managed)](#module-9--gitops-with-flux-azure-managed)
- [Module 10 — Autoscaling with KEDA](#module-10--autoscaling-with-keda)
- [Module 11 — Metrics with Managed Prometheus + Grafana](#module-11--metrics-with-managed-prometheus--grafana)
- [Module 12 — Logs with Container Insights](#module-12--logs-with-container-insights)
- [Module 13 — Backup & restore with Azure Backup for AKS](#module-13--backup--restore-with-azure-backup-for-aks)
- [Closing recap (say this)](#closing-recap-say-this)
- [Appendix A — One-screen cheat sheet](#appendix-a--one-screen-cheat-sheet)
- [Appendix B — Q&A back-pocket](#appendix-b--qa-back-pocket)
- [Appendix C — Reset between runs](#appendix-c--reset-between-runs)

---

## Presenter golden rules

1. **Two terminals.** Keep one terminal for commands and a second one free for `port-forward` (which blocks). I note when you need the second one.
2. **Everything starts with `source ./env.sh`.** That loads the names (`$RG`, `$AKS`, `$GRAFANA`, …). If a `$VAR` is empty, you forgot this.
3. **If a command hangs**, press `Ctrl+C` and move on — no block depends on the previous one except where I say so.
4. **Read the output.** The customer's "aha" comes from *you pointing at a line* of output and saying what it proves.
5. **Never paste a real secret value on screen.** Where a demo touches Key Vault, we list the *file*, not its contents. I flag this.

---

## Module 0 — Pre-flight & connect

🟦 **What:** "Let me connect to the cluster and confirm the platform is healthy."

⚙️ **How** — run this whole block once:

```bash
cd /path/to/repo          # the folder with env.sh
source ./env.sh           # loads RG, AKS, GRAFANA, LAW, etc.

# Download cluster credentials into your kubeconfig
az aks get-credentials -g "$RG" -n "$AKS" --overwrite-existing

# Confirm you are pointed at the right cluster
kubectl config current-context
```

✅ **Prove the platform is up** — one health sweep:

```bash
echo "== Nodes =="
kubectl get nodes -L kubernetes.azure.com/mode,kubernetes.azure.com/agentpool
echo "== Platform namespaces =="
kubectl get pods -n azure-alb-system
kubectl get pods -n argocd
kubectl get pods -n flux-system
kubectl get pods -n kube-system | grep -Ei 'keda|hubble|retina|ama-logs'
echo "== Demo app =="
kubectl get deploy,svc -n demo
```

Everything should show `Running` / `Ready`. If a pod is `Pending` or `CrashLoopBackOff`, note it and simply skip that module.

> [!TIP]
> Widen your terminal font now. The customer reads your screen, not your slides.

---

## Module 1 — The platform at a glance (node pools & pinning)

🟦 **What:** "This cluster separates *platform* workloads from *your* workloads. Add-ons (ingress controller, Argo, KEDA…) run on a dedicated **system** node pool; your apps get the **user** pool to themselves. That's how we keep a noisy app from starving the platform."

⚙️ **How:**

```bash
source ./env.sh

# Show the two pools and each node's role
kubectl get nodes -L kubernetes.azure.com/mode,kubernetes.azure.com/agentpool

# Show the Azure side: sizes, autoscaling, zones
az aks nodepool list -g "$RG" --cluster-name "$AKS" \
  -o table --query "[].{Name:name, Mode:mode, VM:vmSize, Min:minCount, Max:maxCount, Zones:availabilityZones}"
```

✅ **Prove the pinning works** — show that a platform add-on actually landed on a **system** node:

```bash
# Where does the ingress controller run? -> a system-mode node
kubectl -n azure-alb-system get pods -o wide

# Confirm system nodes carry the mode label the add-ons select on
kubectl get nodes -l kubernetes.azure.com/mode=system
```

> **Point at:** the ingress/Argo/KEDA pods sit on `systempool` nodes, while the `demo` app sits on the user pool. Say: *"Platform and app are physically isolated onto different VMs."*

---

## Module 2 — Secretless secrets (Workload Identity + Key Vault CSI)

🟦 **What:** "Pods here don't hold passwords. They prove *who they are* to Azure with **Workload Identity** (a federated token, no secret), and Key Vault secrets are **mounted as files** by the CSI driver — nothing sensitive is stored inside Kubernetes."

⚙️ **How:**

```bash
source ./env.sh

# 1) The OIDC issuer that makes federation possible
az aks show -g "$RG" -n "$AKS" --query oidcIssuerProfile.issuerUrl -o tsv

# 2) The app's service account is linked to an Azure identity (annotation), no secret
kubectl -n demo get serviceaccount demo-sa -o yaml | grep -A2 annotations

# 3) The rule that says "mount THESE Key Vault secrets as files"
kubectl -n demo get secretproviderclass
kubectl -n demo describe secretproviderclass
```

✅ **Prove a secret is delivered as a file — without printing it:**

```bash
# Find a pod in the demo namespace that mounts the secret store
POD=$(kubectl -n demo get pods -o name | head -1)

# List the mounted secret files (names + sizes only — we do NOT cat the value)
kubectl -n demo exec "$POD" -- ls -l /mnt/secrets-store 2>/dev/null \
  || echo "No CSI mount on this pod — pick a pod that references the SecretProviderClass"

# Prove there is NO plaintext Kubernetes Secret holding it
kubectl -n demo get secrets
```

> [!WARNING]
> Do **not** run `cat /mnt/secrets-store/<file>` in front of the customer — that prints the secret. Listing the file (`ls -l`) proves delivery safely.

> **Say:** *"The value lives in Key Vault behind a private endpoint. The pod reads it as a file at runtime using a token it earns — there's no password anywhere in this cluster."*

---

## Module 3 — Ingress with Application Gateway for Containers

🟦 **What:** "This is the front door. **Application Gateway for Containers** gives us a managed public HTTPS endpoint. The platform team owns a shared **Gateway**; app teams attach **HTTPRoutes** to steer traffic to their services."

⚙️ **How — show the gateway and its public address:**

```bash
source ./env.sh

# The shared front door
kubectl get gateway -A
kubectl describe gateway gw-platform -n demo

# The one value that matters: the public entry point AGC assigned
FQDN=$(kubectl get gateway gw-platform -n demo -o jsonpath='{.status.addresses[0].value}')
echo "Public entry point: https://$FQDN"

# The routes attached to it (which hostname goes where)
kubectl get httproute -A
kubectl describe httproute demo-route -n demo
```

✅ **Prove you can reach the app through the front door:**

```bash
# The route only matches host app.contoso.com, so we send that as a header.
# -k trusts the demo's self-signed cert.
curl -ksS -o /dev/null -w "HTTP status: %{http_code}\n" \
  -H "Host: app.contoso.com" "https://$FQDN/"
```

`HTTP status: 200` = the full chain works: **internet → AGC FQDN → Gateway listener → HTTPRoute (host+path) → Service `demo-svc:80` → pods**.

> **Say:** *"In production you'd point a real DNS name (a CNAME) at that FQDN and use a real certificate — then customers just browse to `https://app.contoso.com`."*

---

## Module 4 — App delivery with Kustomize

🟦 **What:** "The demo app isn't a pile of hand-edited YAML. It's built with **Kustomize** — a base set of manifests plus environment overlays — so the same app is reproducible across dev/test/prod with small patches."

⚙️ **How:**

```bash
source ./env.sh

# What is actually running
kubectl get all -n demo

# Render the manifests Kustomize would apply — WITHOUT changing anything
kubectl kustomize apps/demo | head -40
```

✅ **Prove Kustomize is the source of truth** — do a safe, reversible change and watch it reconcile:

```bash
# Preview a diff of what re-applying the overlay would do
kubectl diff -k apps/demo || true

# Re-apply the desired state from the overlay (idempotent)
kubectl apply -k apps/demo
kubectl -n demo rollout status deploy/demo --timeout=120s
```

> **Say:** *"Everything is declarative. I describe the desired state in Git; Kustomize renders it; Kubernetes makes reality match."* This is the perfect segue into GitOps (Modules 8–9).

---

## Module 5 — Cilium network policy (block & allow, live)

🟦 **What:** "Networking here is **Azure CNI powered by Cilium**, enforced with eBPF in the Linux kernel. That means I can write a pod-level firewall — a **NetworkPolicy** — and Cilium enforces it instantly. Let me *create a policy and show the result.*"

This is the classic three-act demo: **open → deny → allow.**

⚙️ **How — Act 1: baseline (traffic flows):**

```bash
source ./env.sh

# Launch a throwaway test pod with curl inside the demo namespace
kubectl -n demo delete pod tester --ignore-not-found --force --grace-period=0 2>/dev/null || true
kubectl -n demo run tester --image=nicolaka/netshoot --restart=Never --command -- sleep 600
kubectl -n demo wait --for=condition=Ready pod/tester --timeout=90s

# It can reach the app service -> expect 200
kubectl -n demo exec tester -- curl -m 5 -s -o /dev/null -w 'baseline http=%{http_code}\n' http://demo-svc.demo:80
```

⚙️ **Act 2: apply a default-deny policy (create a policy, see the result):**

```bash
kubectl apply -f platform/netpol/default-deny-ingress.yaml
kubectl -n demo get netpol
```

✅ **Prove it's blocked now:**

```bash
# Same call as before -> now it hangs/fails: http=000
kubectl -n demo exec tester -- curl -m 5 -s -o /dev/null -w 'after-deny http=%{http_code}\n' http://demo-svc.demo:80
```

`http=000` = Cilium dropped the connection. **You just changed the network with one YAML file.**

⚙️ **Act 3: allow only the front door back in (least privilege):**

```bash
kubectl apply -f platform/netpol/allow-from-agc.yaml
kubectl -n demo get netpol
```

✅ **Prove the public app still works while internal callers stay blocked:**

```bash
FQDN=$(kubectl get gateway gw-platform -n demo -o jsonpath='{.status.addresses[0].value}')
curl -ksS -o /dev/null -w "public via gateway http=%{http_code}\n" -H "Host: app.contoso.com" "https://$FQDN/"

# The in-cluster tester is still denied (it is not the AGC subnet)
kubectl -n demo exec tester -- curl -m 5 -s -o /dev/null -w 'internal tester http=%{http_code}\n' http://demo-svc.demo:80
```

> **Say:** *"Default-deny, then allow exactly one source. The public path works; a random pod in the same namespace does not. That's zero-trust networking, enforced in the kernel."*

**Keep the `tester` pod and these policies for Module 6.**

---

## Module 6 — Hubble flow visibility (ACNS)

🟦 **What:** "How do I *see* that Cilium dropped that traffic? **Advanced Container Networking Services (ACNS)** ships **Hubble** — it watches every network flow with eBPF and tells me source, destination, and whether it was **FORWARDED** or **DROPPED**."

⚙️ **How** — *(needs your second terminal for the port-forward)*:

```bash
# --- Terminal 2 (leave this running) ---
source ./env.sh
kubectl get pods -n kube-system | grep -Ei 'hubble|retina'   # confirm Hubble is present
kubectl port-forward -n kube-system svc/hubble-relay 4245:443
```

```bash
# --- Terminal 1 ---
# Generate a flow the customer can watch: the blocked tester call from Module 5
kubectl -n demo exec tester -- curl -m 5 -s -o /dev/null http://demo-svc.demo:80 || true

# Now observe recent flows in the demo namespace
hubble observe --server localhost:4245 --namespace demo --last 20
```

✅ **Prove the drop is visible** — filter to just the dropped verdicts:

```bash
hubble observe --server localhost:4245 --namespace demo --verdict DROPPED --last 20
```

> **Point at:** a line showing `tester ... -> demo-svc ... DROPPED`. Say: *"Cilium didn't just block it silently — Hubble gives me an audit trail of every allow and deny."*

**Optional — the visual wow (Hubble UI):**

```bash
# --- Terminal 2 (instead of relay) ---
kubectl port-forward -n kube-system svc/hubble-ui 12000:80
# then open http://localhost:12000 and pick the "demo" namespace
```

> [!NOTE]
> Some AKS versions don't ship `hubble-ui`. If the port-forward fails, the CLI `hubble observe` above is the validated, always-works path.

---

## Module 7 — Kyverno policy governance (block a bad deploy)

🟦 **What:** "Cilium governs the *network*; **Kyverno** governs *what you're allowed to deploy*. It's a policy engine — require labels, block privileged pods, force images to come from our registry. Let me try to deploy something that breaks the rules and watch it get rejected."

⚙️ **How — show the guardrails, then break one on purpose:**

```bash
source ./env.sh

# The cluster-wide policies already in place (mostly Audit = warn-only)
kubectl get clusterpolicy

# Turn ON hard-blocking (Enforce) in ONE throwaway namespace only — safe
kubectl create namespace kyverno-test --dry-run=client -o yaml | kubectl apply -f -
envsubst '$ACR' < platform/kyverno/enforce-demo.yaml.tmpl | sed 's/\r$//' | kubectl apply -f -
kubectl wait --for=condition=Ready clusterpolicy/kyverno-test-enforce-registry --timeout=60s 2>/dev/null || true
```

✅ **Prove a violating deploy is rejected before it's created:**

```bash
# Try to run an image from docker.io (not our approved registry) -> DENIED
kubectl -n kyverno-test run bad --image=docker.io/nginx --restart=Never
```

You'll see an admission error like *"images must come from `<registry>`.azurecr.io"* and **no pod is created**. That's the money shot.

⚙️ **Show the reporting side, then clean up:**

```bash
# Kyverno records pass/fail across the cluster
kubectl get policyreport -A

# Tidy up the enforce demo (leaves the audit policies in place)
kubectl delete clusterpolicy kyverno-test-enforce-registry --ignore-not-found
kubectl delete namespace kyverno-test --ignore-not-found --wait=false
```

> **Say:** *"We audit everywhere and enforce where it matters. Bad workloads are stopped at the door, and every decision is reported."*

---

## Module 8 — GitOps with Argo CD (self-heal)

🟦 **What:** "**Argo CD** watches a Git repo and makes the cluster match it. If someone changes the cluster by hand, Argo notices the **drift** and heals it back. Git is the single source of truth."

⚙️ **How — show the app Argo manages:**

```bash
source ./env.sh

kubectl -n argocd get applications
kubectl -n argocd get application guestbook \
  -o jsonpath='{.status.sync.status}{" / "}{.status.health.status}{"\n"}'
```

Expect `Synced / Healthy`. Optionally open the UI *(second terminal)*:

```bash
# --- Terminal 2 ---
kubectl -n argocd port-forward svc/argocd-server 8080:443
# open https://localhost:8080  (user: admin; get password below)
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

✅ **Prove self-heal — delete something and watch Argo restore it:**

```bash
# Break it on purpose: delete the guestbook deployment
kubectl -n guestbook delete deploy guestbook-ui

# Watch Argo detect drift and put it back (Ctrl+C after it returns to Synced)
kubectl -n argocd get application guestbook -w
# In another moment, confirm the deployment is back:
kubectl -n guestbook get deploy
```

> **Point at:** the app going `OutOfSync` then back to `Synced/Healthy`, and the deployment reappearing. Say: *"I didn't run apply. Argo did — because Git says it should exist."*

---

## Module 9 — GitOps with Flux (Azure-managed)

🟦 **What:** "Argo CD is one GitOps engine we run ourselves. **Flux** is the *Azure-managed* GitOps extension — Azure keeps it reconciling for us and reports compliance right in the resource. Same idea, managed by the platform."

⚙️ **How:**

```bash
source ./env.sh

# The Azure-managed extension view (compliance state)
az k8s-configuration flux list -g "$RG" -c "$AKS" -t managedClusters -o table 2>/dev/null || \
  echo "(If this errors, use the kubectl view below.)"

# The Kubernetes-level view: the Git source + what it applies
kubectl get gitrepositories,kustomizations -A
```

✅ **Prove Flux delivered a workload from Git:**

```bash
kubectl get deploy,svc -n flux-demo
```

A running app in `flux-demo` that *you never deployed by hand* = Flux pulled it from Git and applied it.

> **Say:** *"Two GitOps options, one philosophy: nobody `kubectl apply`s to production — Git is the control plane."*

---

## Module 10 — Autoscaling with KEDA

🟦 **What:** "Standard Kubernetes scales on CPU. **KEDA** scales on *anything* — a schedule, a queue depth, a Prometheus query. Here a **ScaledObject** scales our demo app on a schedule; KEDA creates and drives the HPA for us."

⚙️ **How — show the scaler and the HPA it owns:**

```bash
source ./env.sh

# KEDA is a managed add-on in kube-system
kubectl get pods -n kube-system | grep -i keda

# The scaling rule and the HPA KEDA created from it
kubectl get scaledobject,hpa -n demo
kubectl describe scaledobject demo-scaler -n demo | sed -n '1,40p'
```

> **Say:** *"`demo-scaler` says: between minutes 0–5, 10–15, 20–25… of every hour, run 3 replicas; otherwise 1. KEDA turns that into a live HPA."*

✅ **Prove it scales — force a scale event now (no waiting):**

```bash
# Set the cron window to start THIS minute so it scales within ~1 min
S=$(date -u +%M | sed 's/^0//'); [ -z "$S" ] && S=0
E=$(( (S + 8) % 60 ))
kubectl -n demo patch scaledobject demo-scaler --type=merge \
  -p "{\"spec\":{\"triggers\":[{\"type\":\"cron\",\"metadata\":{\"timezone\":\"UTC\",\"start\":\"$S * * * *\",\"end\":\"$E * * * *\",\"desiredReplicas\":\"3\"}}]}}"

# Watch replicas climb from 1 -> 3 (Ctrl+C when you see 3)
kubectl -n demo get hpa keda-hpa-demo-scaler -w
```

Then confirm the pods actually appeared:

```bash
kubectl -n demo get pods -l app=demo
```

⚙️ **Reset to the standard 10-minute schedule after the demo:**

```bash
kubectl -n demo patch scaledobject demo-scaler --type=merge \
  -p '{"spec":{"triggers":[{"type":"cron","metadata":{"timezone":"UTC","start":"0,10,20,30,40,50 * * * *","end":"5,15,25,35,45,55 * * * *","desiredReplicas":"3"}}]}}'
```

> **Point at:** the HPA's `REPLICAS` column moving 1 → 3. Say: *"Event-driven scaling — and it would scale to zero for a queue worker with no messages."*

---

## Module 11 — Metrics with Managed Prometheus + Grafana

🟦 **What:** "Metrics are collected by **Azure Monitor managed Prometheus** — no Prometheus server for us to babysit — and visualized in **Azure Managed Grafana** with Entra sign-in."

⚙️ **How:**

```bash
source ./env.sh

# Grafana's URL — open it in a browser and sign in with your Azure account
az grafana show -g "$RG" -n "$GRAFANA" --query 'properties.endpoint' -o tsv

# The dashboards already provisioned for Kubernetes
az grafana dashboard list -n "$GRAFANA" -o table 2>/dev/null | head -20

# Confirm Prometheus is wired in as a data source
az grafana data-source list -n "$GRAFANA" --query "[].{Name:name, Type:type}" -o table
```

✅ **Prove live metrics:** open the Grafana endpoint, sign in, and open a **Kubernetes / Compute Resources / Namespace (Workloads)** dashboard. Pick the `demo` namespace.

> **Point at:** CPU/memory graphs for the demo app. If you just ran Module 10, the extra replicas show up here. Say: *"Fully managed metrics — Azure runs Prometheus, Grafana renders it, and it's all zoned and patched by the platform."*

> [!TIP]
> Have the Grafana tab **already open and logged in** before the demo. Entra sign-in mid-demo is the most common stumble.

---

## Module 12 — Logs with Container Insights

🟦 **What:** "Metrics tell me *how much*; **Container Insights** tells me *what happened*. Every node runs a log agent that ships container logs and inventory to **Log Analytics**, which I query with **KQL**."

⚙️ **How:**

```bash
source ./env.sh

# The log-collection agent runs on every node
kubectl -n kube-system get ds ama-logs

# Resolve the workspace GUID the query API needs
LAW_GUID=$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query customerId -o tsv)
echo "Workspace: $LAW_GUID"
```

✅ **Prove ingestion with a live query:**

```bash
az monitor log-analytics query --workspace "$LAW_GUID" \
  --analytics-query 'KubePodInventory | where TimeGenerated > ago(20m) | summarize Pods=dcount(Name) by Namespace | top 10 by Pods' \
  -o table
```

Rows grouped by namespace (including `demo`, `argocd`, `flux-demo`) = logs and inventory are flowing.

> **Say:** *"Same walkthrough is available in the portal under the cluster's **Monitoring → Insights** blade — click a pod, read its logs, see restarts, all without SSH."*

---

## Module 13 — Backup & restore with Azure Backup for AKS

🟦 **What:** "Everything so far keeps the platform *running*. **Azure Backup for AKS** is my safety net for when someone *deletes* something. A **Backup vault** holds recovery points; an in-cluster **extension** snapshots the `demo` namespace on a schedule and copies it to a storage account. If a namespace gets wiped, I restore it to a point in time."

⚙️ **How — show what is protected:**

```bash
source ./env.sh

# 1) The vault that stores recovery points
az dataprotection backup-vault show -g "$RG" --vault-name "$BKUP_VAULT" \
  --query "{name:name, redundancy:properties.storageSettings[0].type}" -o table

# 2) The backup instance and its live protection state (want: ProtectionConfigured)
az dataprotection backup-instance list -g "$RG" --vault-name "$BKUP_VAULT" \
  --query "[].{name:name, scope:properties.friendlyName, state:properties.protectionStatus.status}" -o table
```

> **Say:** *"`ProtectionConfigured` means the schedule is live. The policy backs up hourly and keeps 7 days — governed by the same Azure RBAC as everything else."*

✅ **Prove — trigger an on-demand backup and watch it finish:**

```bash
# Resolve the instance name and the policy's backup rule
BI=$(az dataprotection backup-instance list -g "$RG" --vault-name "$BKUP_VAULT" --query "[0].name" -o tsv)
RULE=$(az dataprotection backup-policy show -g "$RG" --vault-name "$BKUP_VAULT" -n "$BKUP_POLICY" \
  --query 'properties.policyRules[?backupParameters].name | [0]' -o tsv)

# Force a backup right now (don't wait for the hourly schedule)
az dataprotection backup-instance adhoc-backup --name "$BI" -g "$RG" --vault-name "$BKUP_VAULT" \
  --rule-name "$RULE" --retention-tag-override Default -o none

# Follow the newest job until Status reads "Completed" (a few minutes)
az dataprotection job list -g "$RG" --vault-name "$BKUP_VAULT" \
  --query "sort_by([].{op:properties.operationCategory, status:status, start:properties.startTime}, &start)[-1]" -o table
```

✅ **Prove — a recovery point now exists you could restore from:**

```bash
az dataprotection recovery-point list -g "$RG" --vault-name "$BKUP_VAULT" \
  --backup-instance-name "$BI" --query "[].{id:name, time:properties.recoveryPointTime}" -o table
```

At least one row = the `demo` namespace is captured and restorable.

> **Say:** *"To recover, I'd pick one of these recovery points and restore the namespace — either back onto this cluster or a different one — through the same `az dataprotection backup-instance restore` flow. The point for today: the data is protected and the restore path is one command away."*

---

## Closing recap (say this)

> "So in one cluster you've seen: **isolated node pools** for platform vs apps, **secretless** access to Key Vault, a **managed HTTPS front door**, **Kustomize** for declarative apps, **Cilium** zero-trust networking with **Hubble** visibility, **Kyverno** guardrails that block bad deploys, **two GitOps engines** keeping Git as the source of truth, **KEDA** event-driven autoscaling, **managed Prometheus/Grafana + Container Insights** for full observability, and **Azure Backup for AKS** as the point-in-time safety net — all Entra-secured and zone-redundant. Every piece is managed or GitOps-driven, so the platform team operates it, not babysits it."

---

## Appendix A — One-screen cheat sheet

Copy any single line during the demo.

```bash
source ./env.sh

# Nodes & pools
kubectl get nodes -L kubernetes.azure.com/mode,kubernetes.azure.com/agentpool

# Ingress front door + reach the app
FQDN=$(kubectl get gateway gw-platform -n demo -o jsonpath='{.status.addresses[0].value}'); echo $FQDN
curl -ksS -o /dev/null -w "%{http_code}\n" -H "Host: app.contoso.com" "https://$FQDN/"

# Cilium: deny then allow
kubectl apply -f platform/netpol/default-deny-ingress.yaml
kubectl apply -f platform/netpol/allow-from-agc.yaml
kubectl -n demo get netpol

# Hubble (Terminal 2): kubectl port-forward -n kube-system svc/hubble-relay 4245:443
hubble observe --server localhost:4245 --namespace demo --verdict DROPPED --last 20

# Kyverno: block a bad image
kubectl get clusterpolicy

# Argo CD
kubectl -n argocd get application guestbook -o jsonpath='{.status.sync.status}{" / "}{.status.health.status}{"\n"}'

# Flux
kubectl get gitrepositories,kustomizations -A

# KEDA
kubectl get scaledobject,hpa -n demo

# Grafana URL
az grafana show -g "$RG" -n "$GRAFANA" --query 'properties.endpoint' -o tsv

# Container Insights agent
kubectl -n kube-system get ds ama-logs

# Backup: protection state + trigger on-demand + list recovery points
az dataprotection backup-instance list -g "$RG" --vault-name "$BKUP_VAULT" --query "[].{name:name,state:properties.protectionStatus.status}" -o table
BI=$(az dataprotection backup-instance list -g "$RG" --vault-name "$BKUP_VAULT" --query "[0].name" -o tsv)
az dataprotection recovery-point list -g "$RG" --vault-name "$BKUP_VAULT" --backup-instance-name "$BI" -o table
```

---

## Appendix B — Q&A back-pocket

| Customer asks | Short answer |
|---------------|--------------|
| "Is this production-ready?" | Yes — 3 availability zones, Standard tier control plane, managed add-ons, GitOps delivery. Swap the self-signed cert for a CA/`cert-manager` cert and point real DNS at the AGC FQDN. |
| "Where are the secrets?" | In Key Vault behind a private endpoint. Pods mount them as files via the CSI driver using Workload Identity — no secrets stored in Kubernetes. |
| "Why two GitOps tools (Argo + Flux)?" | To show both. Flux is the Azure-managed extension; Argo CD gives a rich UI and app-of-apps. Most teams pick one. |
| "What stops a bad deployment?" | Kyverno at admission (policy) and Cilium at the network layer (NetworkPolicy). Both were shown live. |
| "How does it scale?" | Cluster autoscaler adds nodes (user pool min 1 / max 3); KEDA scales pods on events/schedules/queues. |
| "How do we operate it?" | Managed Prometheus + Grafana for metrics, Container Insights for logs, Hubble for network flows — all in Azure Monitor. |

---

## Appendix C — Reset between runs

If you demo twice, restore clean state first:

```bash
source ./env.sh

# Remove the throwaway tester pod
kubectl -n demo delete pod tester --ignore-not-found --force --grace-period=0 2>/dev/null || true

# Reset KEDA cron to the standard schedule (see Module 10 reset block)
kubectl -n demo patch scaledobject demo-scaler --type=merge \
  -p '{"spec":{"triggers":[{"type":"cron","metadata":{"timezone":"UTC","start":"0,10,20,30,40,50 * * * *","end":"5,15,25,35,45,55 * * * *","desiredReplicas":"3"}}]}}'

# Re-sync Argo-managed app if you deleted anything
kubectl -n guestbook get deploy || true

# (Kyverno enforce namespace is already cleaned up at the end of Module 7)
```

> The network policies from Module 5 are part of the validated platform design — you can leave them applied. To fully clear them: `kubectl -n demo delete netpol default-deny-ingress allow-from-agc`.

---

*This playbook is generated from the validated, deployed platform and mirrors `TUTORIAL.md`. Sanitized edition — no secrets, IDs, or tenant details. The private `.docx` edition contains any environment-specific values you may need.*
