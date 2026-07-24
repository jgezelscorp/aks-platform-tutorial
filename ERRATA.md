# ERRATA — AKS Platform Deployment Tutorial

**Validated companion to `AKS-Platform-Deployment-Tutorial.pptx`.**

Every command in the deck was executed against a live Azure subscription. This
document records each defect found, its root cause, the corrected command, and
the validation status. Where the deck and this errata disagree, **this errata is
authoritative** — its commands were run and observed to work.

- **Validation cluster:** `aks-aksplat-dev` in **North Europe**, Kubernetes 1.35.x
- **Node SKU:** `Standard_D2s_v6` (POC sizing — see caveat E1)
- **Companion repo:** curated, runnable tree in this folder (`infra/`, `apps/`,
  `.github/workflows/`, `env.sh`). The GitHub Actions pipeline is wired to a real
  repository and every workflow ran green.

---

## 1. Environment & POC caveats (not bugs — read before you start)

| # | Caveat | Detail |
|---|--------|--------|
| E1 | **POC SKUs / node counts** | Validation used `Standard_D2s_v6`, system pool min/max **1/3**, user pool min/max **1/3**. Production should size up. The user pool autoscaler is deliberately **min=1** so idle demo clusters do not park spare nodes (resource waste). |
| E2 | **No availability zones in sandbox** | The validation subscription could not place zonal node pools, so zones were disabled (`--zones` omitted). Production clusters should span zones. |
| E3 | **Region** | Everything validated in `northeurope`. If you change region, check that every dependent service (managed Prometheus, Grafana, AGC) is available there. |
| E4 | **Pin the Kubernetes version** | The deck's `az aks create` omits `--kubernetes-version`, so you get whatever the region defaults to. Pin it (e.g. `--kubernetes-version 1.31.1`) for reproducibility. |
| E5 | **Add-ons run on the system pool** | Platform add-ons (Cilium/ACNS, Kyverno, Argo CD, KEDA, CSI) belong on the **system** node pool; keep the user pool for workloads. Ensure the system pool has enough headroom (this is why system max = 3). |

---

## 2. Confirmed deck bugs (with fixes)

### Section 3–4 — Cluster provisioning

**B1 — Missing line-continuation backslash (slide ~23).**
A multi-line `az` command is missing a trailing `\`, so the shell runs a
truncated command. Fix: add the `\` at the end of the broken line, or put the
command on one line.

**B2 — Missing `--service-cidr` / `--dns-service-ip` (universal).**
Every `az aks create` in the deck omits the service CIDR. On subscriptions where
the default `10.0.0.0/16` overlaps peered/VNet space this fails or causes routing
problems. Fix — set them explicitly and keep them consistent with your VNet:
```bash
--service-cidr 172.16.0.0/16 --dns-service-ip 172.16.0.10
```

**B3 — `aks-preview` extension pin is broken.**
The deck pins `az extension add --name aks-preview --version 21.0.0b8`, which
fails to install. Fix: install the current preview (`az extension add --name
aks-preview` without the version pin) or omit it entirely — none of the
validated features required that exact build.

### Section 6 — Application Gateway for Containers (AGC / ALB controller)

**B4 — ALB identity role scoped to the wrong resource group.**
The deck grants the ALB managed identity `Reader`/config roles on the **cluster**
resource group. The controller needs them on the **node (managed) resource
group** (`MC_...`) where the AGC association and subnet live. Fix — scope the role
assignments to the node RG:
```bash
NODE_RG=$(az aks show -g $RG -n $AKS --query nodeResourceGroup -o tsv)
az role assignment create --assignee $ALB_IDENTITY_PRINCIPAL_ID \
  --role "Reader" --scope $(az group show -n $NODE_RG --query id -o tsv)
```

### Section 9 — Key Vault + Secrets Store CSI driver

**B5 — Deck assumes a public Key Vault.**
The steps create a vault with public network access and never provision a private
endpoint, so on a locked-down/network-restricted subscription the CSI mount fails.
Fix — create a **private endpoint** + private DNS zone
(`privatelink.vaultcore.azure.net`) linked to the cluster VNet (see
`infra/` for the validated shape).

**B6 — Wrong CSI driver API group in the `SecretProviderClass`.**
The deck uses `secrets-store.x-k8s.io`. The installed driver serves
`secrets-store.csi.x-k8s.io` for the CSI object but the **`SecretProviderClass`
CRD** is `secrets-store.csi.x-k8s.io/v1`. Use the API version that
`kubectl api-resources | grep secret` reports on your cluster — validated value:
```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
```

### Section 10 — Cilium network policy

**B7 — Test traffic hits the wrong port.**
The netpol demo curls port **8080**, but the sample app/service listens on **80**.
The "blocked/allowed" test therefore always fails regardless of policy. Fix: target
port **80** (or align the Service `targetPort` to 8080 consistently).

### Section 11 — Kyverno policies

**B8 — Invalid policy YAML + unsafe cluster-wide `Enforce`.**
The pasted `ClusterPolicy` has a YAML indentation error and ships with
`validationFailureAction: Enforce` cluster-wide, which can block system namespaces
(kube-system, gatekeeper, etc.) and wedge the cluster. Fix — correct the
indentation and start with **`Audit`**, scoping any later `Enforce` to app
namespaces only. All validated policies run in `Audit`.

### Section 12 — Argo CD

**B9 — Broken install URL + placeholder + missing server-side apply.**
Three problems: (1) the `install.yaml` raw URL is split across a line break and
404s when pasted; (2) an unreplaced `<org>` placeholder in a manifest; (3) the
Argo CRDs exceed the client-side apply annotation limit. Fixes:
```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```
Use `--server-side` (avoids the `metadata.annotations too long` error) and replace
every `<org>` with your real GitHub org/repo.

### Section 13 — Managed Prometheus / Grafana

**B10 — Wrong metrics port in the scrape example.**
The deck curls `localhost:8080/metrics`; the sample exporter serves metrics on a
different port. Confirm the container's actual metrics port (validated app used
the app port, not 8080) before wiring the `PodMonitor`/scrape config.

### Section 20 — KEDA & Flux

**B11 — KEDA Prometheus trigger needs `TriggerAuthentication` for managed Prometheus.**
Azure Monitor managed Prometheus requires Entra auth; the deck's bare
`prometheus` trigger (no auth) returns 401. Fix — add a `TriggerAuthentication`
using workload identity and reference the managed Prometheus **query endpoint**,
not an in-cluster Prometheus.

**B12 — Flux extension has no `target_namespace` parameter.**
`az k8s-configuration flux create` does **not** accept `--target-namespace` the way
the deck implies; namespace targeting is done inside the `kustomization` /
`GitRepository` spec. Remove the unsupported flag.

### Section 4/5 — Infrastructure as Code

**B13 — Bicep/Terraform excerpts are incomplete.**
The IaC snippets omit `serviceCidr`/`dnsServiceIP`, the **user node pool**, and a
pinned Kubernetes version, so a copy-paste deploy diverges from the CLI cluster.
The validated, complete templates live in `infra/bicep/main.bicep` and
`infra/terraform/` (both pass `az bicep build` and `terraform validate`).

### Section 20 — Fleet capstone

**B14 — Stale Fleet Kubernetes version.**
`az fleet updaterun ... --kubernetes-version 1.29.0` is stale/unavailable. Use a
version currently offered in your region (`az aks get-versions -l <region>`).

### Section 18 — GitHub Actions CI/CD

**B15 — `aquasecurity/trivy-action@0.24.0` does not exist.**
That tag was never published; the workflow fails at "Set up job". Fix — pin to a
real release **by commit SHA** (the deck itself recommends SHA-pinning):
```yaml
uses: aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25 # v0.36.0
```

**B16 — Undefined `$ACR` in `build.yml`.**
The build job references `$ACR` which is never defined. Fix — resolve it from a
repo **variable**:
```yaml
env:
  ACR: ${{ vars.ACR_NAME }}
```

**B17 — Broken backslash inside the Trivy `image-ref` string.**
A line-continuation `\` inside the image reference splits the tag, producing an
invalid ref. Fix: put `image-ref:` on a single line
(`${{ vars.ACR_NAME }}.azurecr.io/demo:${{ github.sha }}`).

**B18 — `deploy.yml` GitOps commit fails: git identity not set.**
The promotion job commits (`kustomize edit set image` → `git commit`) but never
sets `user.email`, so the commit is rejected on the runner. Fix:
```bash
git config user.name  "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
```

---

## 3. OIDC federation caveats (Section 18 — critical, easy to miss)

These are not deck typos but **real-world gotchas** that will block a customer
following the deck verbatim. All three were hit and resolved during validation.

**O1 — The ACR must exist before `build.yml` runs.**
`az acr import` fails with *"registry could not be found"* if you haven't created
the registry first. Create it (any SKU; Basic is fine for the demo) and set the
`ACR_NAME` repo variable to match.

**O2 — Federated-credential SUBJECT may need immutable numeric IDs.**
For some GitHub accounts the OIDC **subject claim** is presented with immutable
numeric IDs baked into the prefix, e.g.:
```
repo:OWNER@<ownerId>/REPO@<repoId>:ref:refs/heads/main
```
instead of the documented `repo:OWNER/REPO:ref:refs/heads/main`. When this happens,
`azure/login` fails with **AADSTS700213 — No matching federated identity record**.
The error message prints the exact `subject claim` it presented — **copy that
string verbatim** into the federated credential's `subject`. Check your account's
format via:
```bash
gh api /repos/OWNER/REPO/actions/oidc/customization/sub
# a non-empty "sub_claim_prefix" with @<digits> means you must use the numeric form
```

**O3 — Allow time for federated-credential propagation.**
After creating or updating a federated identity credential, control-plane calls
(`az acr import`) may succeed while a data-plane call in the **same job**
(`az acr login`) still returns AADSTS700213 for a few minutes. This is Entra
propagation lag, not a config error — re-run the workflow after a short wait.

**O4 — Section 18 uses variables, not secrets.**
OIDC is passwordless: there is **no client secret**. `AZURE_CLIENT_ID`,
`AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID` are stored as repo **variables**
(`vars.*`), which is acceptable even in a public repo. SARIF upload to the
Security tab works because the validation repo is **public** (free code scanning).

---

## 4. Validation status

| Section | Topic | Status |
|---------|-------|--------|
| 3–4 | Providers, RG/LAW/VNet, AKS create, node pool, creds | ✅ executed |
| 5 | IaC (Bicep + Terraform) | ✅ `az bicep build` + `terraform validate` |
| 6 | AGC / ALB controller, Gateway, HTTPRoute | ✅ executed (PROGRAMMED=True) |
| 7 | Entra RBAC role assignments | ✅ executed |
| 8 | Workload Identity | ✅ executed |
| 9 | Key Vault (private endpoint) + CSI driver | ✅ executed |
| 10 | Cilium network policy | ✅ executed |
| 11 | Kyverno policies (Audit) | ✅ executed |
| 12 | Argo CD (server-side apply) | ✅ Synced/Healthy |
| 13 | Managed Prometheus + Grafana | ✅ executed |
| 14 | Demo app + end-to-end | ✅ executed |
| 15 | Troubleshooting one-liners | ✅ spot-checked live |
| 18 | GitHub CI/CD (OIDC) | ✅ **all 3 workflows green** |
| 19 | Container Insights, Grafana, alerting | ✅ ingestion proven |
| 20 | KEDA, ACNS/Hubble, Flux | ✅ executed |
| 20 | Fleet capstone | ⚠️ reviewed (command shapes verified via `--help`; not run — needs multiple clusters) |
| 16 | Cleanup / teardown | ⏸️ run **last**, on purpose |

---

_Generated during live validation. Keep this file next to the deck when sharing
with customers._
