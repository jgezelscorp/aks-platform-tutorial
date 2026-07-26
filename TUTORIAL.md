# AKS Platform Deployment — A Hands-On Tutorial for Beginners

> **Validated, end-to-end.** Every command in this tutorial was executed against a live Azure subscription and corrected until it worked. It takes you from an empty subscription to a production-shaped AKS platform with ingress, secrets, policy, GitOps, autoscaling, observability, and CI/CD — explaining each step as you go.
>
> This is the **repository (sanitized) edition**: it uses variables and placeholders instead of real subscription IDs, tenant IDs, or Entra group IDs. Wherever a real value is required, the guide explains how to obtain and store it. A companion Word document contains the reference environment's real identifiers for direct execution.
>
> **Companion files:** `env.sh` (your names and IDs) · `ERRATA.md` (every validated fix and caveat) · the `infra/`, `platform/`, and `apps/` script trees.

---

## How to read this guide

Each numbered section follows the same rhythm, so once you learn the pattern you can move through the guide quickly:

- **What & why** — a short, plain-language explanation of what the section accomplishes and why it matters.
- **Steps** — the exact, validated commands to run, each followed by a short *How it works* note so you understand what just happened.
- **Hands-on examples** — small, self-contained exercises that let you practise the core concept (KEDA scalers, Kustomize overlays, Helm releases, Kyverno policies, and more) on your own.

Throughout the guide you will see GitHub-style callouts:

> [!NOTE]
> Background or context worth knowing.

> [!TIP]
> A shortcut, convenience, or good practice.

> [!IMPORTANT]
> A validated design decision — please do not skip it.

> [!WARNING]
> A common pitfall that will break the deployment if ignored.

Every command assumes you have run `source ./env.sh` first (see Section 0), which loads every name and ID into your shell.

## Table of contents

- [**Introduction — what you will build**](#introduction--what-you-will-build)
- [🧰 **0. Before you begin — prerequisites & environment setup**](#0-before-you-begin--prerequisites--environment-setup)
- [🏗️ **1. Providers & Resource Group**](#1-providers--resource-group)
- [🌐 **2. Networking**](#2-networking)
- [🔐 **3. Identity, RBAC & Entra groups**](#3-identity-rbac--entra-groups)
- [☸️ **4. AKS Cluster + Node Pools + System-Pool Pinning**](#4-aks-cluster--node-pools--system-pool-pinning)
- [🪪 **5. Workload Identity**](#5-workload-identity)
- [🔑 **6. Key Vault + Private Endpoint + CSI Secret Mount**](#6-key-vault--private-endpoint--csi-secret-mount)
- [🚪 **7. Application Gateway for Containers / ALB ingress**](#7-application-gateway-for-containers--alb-ingress)
- [📦 **8. Deploy the demo app with Kustomize**](#8-deploy-the-demo-app-with-kustomize)
- [🛡️ **9. Network Policies / Cilium**](#9-network-policies--cilium)
- [📋 **10. Kyverno policy governance**](#10-kyverno-policy-governance)
- [🔄 **11. Argo CD GitOps**](#11-argo-cd-gitops)
- [📈 **12. Managed Prometheus + Grafana**](#12-managed-prometheus--grafana)
- [⚖️ **13. KEDA event-driven autoscaling**](#13-keda-event-driven-autoscaling)
- [🔎 **14. Advanced Container Networking Services and Hubble**](#14-advanced-container-networking-services-and-hubble)
- [🌊 **15. Flux GitOps**](#15-flux-gitops)
- [📊 **16. Container Insights and logs**](#16-container-insights-and-logs)
- [🚀 **17. CI/CD with GitHub Actions and OIDC**](#17-cicd-with-github-actions-and-oidc)
- [💾 **18. Backup & Restore with Azure Backup for AKS**](#18-backup--restore-with-azure-backup-for-aks)
- [🧹 **19. Cleanup — tear it all down**](#19-cleanup--tear-it-all-down)
- [**Where to go next**](#where-to-go-next)


---

## Introduction — what you will build

This tutorial walks you, step by step, through building a **production-shaped Azure Kubernetes Service (AKS) platform** and every supporting capability a real team needs on day one. It is written for **beginners**: if you know your way around a terminal but are new to AKS, Kubernetes, and Microsoft Entra ID, you are in the right place. Every command here was **executed against a live Azure subscription and corrected** until it worked — where a command in this guide differs from what you may have seen elsewhere, this guide is the validated version.

By the end you will have:

- A **two-node-pool AKS cluster** with a hardened **system pool** for platform components and a separate **user pool** for your applications.
- **Cilium-powered networking** with network policies and **Advanced Container Networking Services (ACNS)** + **Hubble** flow visibility.
- **Secrets** delivered from **Azure Key Vault** over a **private endpoint** using the Secrets Store CSI driver and **Workload Identity** (no passwords in your cluster).
- **Ingress** through **Application Gateway for Containers (AGC)** using the Kubernetes **Gateway API**.
- **Policy governance** with **Kyverno**, **GitOps** delivery with **Argo CD** and **Flux**, **event-driven autoscaling** with **KEDA**, and full **observability** with managed **Prometheus**, **Grafana**, and **Container Insights**.
- A passwordless **CI/CD pipeline** with **GitHub Actions + OpenID Connect (OIDC)**.

### The architecture at a glance

The platform is layered. Each layer is one section of this tutorial:

- **Infrastructure** — resource providers, resource group, virtual network, identity/RBAC, the AKS cluster and its node pools, and Workload Identity.
- **Secrets** — Key Vault behind a private endpoint, mounted into pods via the CSI driver.
- **Ingress & apps** — the AGC ingress, a demo application deployed with Kustomize, and network policies.
- **Governance & delivery** — Kyverno policy, Argo CD and Flux GitOps.
- **Scaling & observability** — KEDA, ACNS/Hubble, managed Prometheus/Grafana, and Container Insights.
- **Automation** — GitHub Actions CI/CD with OIDC.

### The design decisions baked into this guide

Two choices shape everything that follows, so it is worth understanding them up front:

1. **Two node pools with clear jobs.** The **system pool** runs `Standard_D4s_v6` nodes (4 vCPU) with the autoscaler set to **min 2 / max 3**. Min 2 is *required*, not a preference: this pool hosts both the AKS‑managed add‑ons (Cilium, CoreDNS, monitoring agents, the CSI driver) **and** the platform control plane you install later (Argo CD, Kyverno, KEDA, the ALB controller). That workload does not fit on a single node, and a single‑node system pool will not reliably scale up. The **user pool** runs the frugal `Standard_D2s_v6` (2 vCPU) with the autoscaler at **min 1 / max 3**, so an idle demo cluster does not park spare workload nodes.

2. **Platform add-ons are pinned to the system pool.** So your user pool stays reserved for *your* applications, the platform components are pinned back onto the system pool with a Kubernetes **`nodeSelector: kubernetes.azure.com/mode=system`** plus a **`CriticalAddonsOnly`** toleration. Using the `mode=system` *label* (rather than a specific pool name) means the pin keeps working even if you later resize or rename the pool.

> [!NOTE]
> **A note on the two documents.** This tutorial ships in two forms. The **Word (.docx)** version contains the real subscription IDs, tenant ID, and Entra group object IDs for the reference environment, so you can execute it directly. The **Markdown (.md)** version — the one synced to the repository — is **sanitized**: it uses variables and placeholders instead of real IDs. Wherever a real value is needed, the Markdown explains how to obtain and store it (see Section 17 for CI/CD secrets).

---

## 0. Before you begin — prerequisites & environment setup

**What & why**
Before the first `az` command, you need a few tools installed, an Azure subscription you can create resources in, and a small file that holds all the names and IDs your commands will reuse. Getting this right once means every later section is copy‑paste.

### Tools you need

| Tool | Why | Install |
|------|-----|---------|
| **Azure CLI** (`az`) | Creates and manages every Azure resource | <https://learn.microsoft.com/cli/azure/install-azure-cli> |
| **kubectl** | Talks to the Kubernetes API of your cluster | `az aks install-cli` |
| **Helm** | Installs packaged Kubernetes apps (Kyverno, ALB controller) | <https://helm.sh/docs/intro/install/> |
| **GitHub CLI** (`gh`) | Sets up the CI/CD pipeline and OIDC | <https://cli.github.com/> |
| **git** | Clones the repo and drives GitOps | <https://git-scm.com/downloads> |
| **A bash shell** | All scripts are bash | Native on macOS/Linux; on **Windows use WSL** (`wsl --install`) |

> [!TIP]
> **Windows tip.** Run everything from a **WSL (Ubuntu)** shell. The Azure CLI, kubectl, and Helm all work there, and the bash scripts in this repo assume a Linux‑style shell.

### Step 1 — Sign in and pick your subscription

```bash
az login
az account set --subscription "<your-subscription-name-or-id>"
az account show --query "{name:name, id:id, tenant:tenantId}" -o table
```
**How it works** — `az login` opens a browser to authenticate. `az account set` selects which subscription new resources land in (skip if you only have one). The last line prints the subscription and tenant you are now targeting — confirm it is the right one before creating anything.

### Step 2 — Create your environment file

Every section reuses the same resource names and IDs. Rather than retype them, this repo keeps them in a single file, **`env.sh`**, that you `source` before each section. Here is the sanitized template — copy it to `env.sh` and fill in the placeholders:

```bash
# ---- env.sh : single source of names ----
export LOCATION="${LOCATION:-westeurope}"   # override for capacity-constrained regions
export PREFIX=aksplat            # your platform prefix
export ENV=dev
export RG=rg-${PREFIX}-${ENV}
export AKS=aks-${PREFIX}-${ENV}
export VNET=vnet-${PREFIX}-${ENV}
export ACR=acr${PREFIX}${ENV}    # globally unique, no dashes
export KV=kv-${PREFIX}-${ENV}    # 3-24 chars, globally unique
export AMW=amw-${PREFIX}-${ENV}  # Azure Monitor workspace (managed Prometheus)
export GRAFANA=graf-${PREFIX}-${ENV}
export LAW=law-${PREFIX}-${ENV}  # Log Analytics workspace

# Availability zones: prod-recommended is "1 2 3". Some sandbox subscriptions have
# no AZ support in a region — run with SANDBOX_NO_ZONES=1 to deploy zone-less.
export AKS_ZONES="1 2 3"
[ "${SANDBOX_NO_ZONES:-0}" = "1" ] && export AKS_ZONES=""

# VM sizes — validated design (see Introduction):
export SYS_VM_SIZE="${SYS_VM_SIZE:-Standard_D4s_v6}"   # system pool: platform add-ons
export USER_VM_SIZE="${USER_VM_SIZE:-Standard_D2s_v6}" # user pool: workloads only
export AKS_VM_SIZE="${AKS_VM_SIZE:-$SYS_VM_SIZE}"      # legacy fallback

# Node counts — validated design:
export SYS_NODE_COUNT="${SYS_NODE_COUNT:-2}"; export SYS_MIN="${SYS_MIN:-2}"; export SYS_MAX="${SYS_MAX:-3}"
export USER_NODE_COUNT="${USER_NODE_COUNT:-1}"; export USER_MIN="${USER_MIN:-1}"; export USER_MAX="${USER_MAX:-3}"

# Microsoft Entra group object IDs — create these groups (Section 3) and paste their IDs:
export ADMIN_GROUP=<your-aks-admin-group-object-id>
export AKS_ADMIN=<your-aks-admin-group-object-id>
export AKS_DEV=<your-aks-developer-group-object-id>
export AKS_READ=<your-aks-reader-group-object-id>

# Resolved automatically from your logged-in context:
export SUB_ID=$(az account show --query id -o tsv)
export TENANT_ID=$(az account show --query tenantId -o tsv)
```
**How it works** — Names are derived from `PREFIX` and `ENV` so they stay consistent and unique. `SUB_ID` and `TENANT_ID` are filled in automatically from your login. The three `AKS_*` group IDs are the only values you must paste by hand — you will create those Entra groups in **Section 3** and then come back to fill these in. `ACR` and `KV` must be **globally unique**, so change `PREFIX` if creation fails with a name‑taken error.

### Step 3 — Load the file (do this at the start of every section)

```bash
source ./env.sh
```
**How it works** — `source` runs the file in your *current* shell so the `export`ed variables are available to the commands that follow. Because each new terminal starts fresh, re‑run this line whenever you open a new shell or start a new section.

> [!IMPORTANT]
> **Idempotency.** The scripts in this repo are safe to re‑run — they register providers, add extensions, and create resources only if they are missing. If a section fails halfway, fix the cause and run it again.

---

## 1. Providers & Resource Group

Run `source ./env.sh` before each section so the commands use the canonical names, sizes, groups, tenant, and subscription variables. Do not paste real subscription IDs, tenant IDs, object IDs, client IDs, or secret values into shared docs or scripts.

**What & why**

Azure resource providers are the service namespaces that let a subscription create specific resource types, such as AKS, Key Vault, Monitor, and private networking. Registering them first prevents confusing “namespace not registered” errors later. The resource group is the container that holds the platform resources so they can be secured, tagged, and cleaned up together.

### Steps

1. Sign in, select the subscription from `env.sh`, and confirm the active account.

```bash
source ./env.sh
az account set --subscription "$SUB_ID"
az account show --query "{subscription:id, tenant:tenantId, user:user.name}" -o table
```

How it works: `az account set` tells Azure CLI which subscription to use. The table output is a quick sanity check; keep the IDs out of repo-safe documentation.

2. Register the resource providers used by the validated platform.

```bash
source ./env.sh
for p in Microsoft.ContainerService \
         Microsoft.ServiceNetworking \
         Microsoft.KeyVault \
         Microsoft.Monitor \
         Microsoft.Dashboard \
         Microsoft.OperationalInsights; do
  echo "Registering $p"
  az provider register --namespace "$p" --wait
done
```

How it works: a provider is registered once per subscription. `--wait` blocks until Azure reports the provider as ready, which avoids racing into the next section too early.

3. Verify the provider registration state.

```bash
source ./env.sh
for p in Microsoft.ContainerService Microsoft.ServiceNetworking Microsoft.KeyVault \
         Microsoft.Monitor Microsoft.Dashboard Microsoft.OperationalInsights; do
  state=$(az provider show -n "$p" --query registrationState -o tsv)
  printf "%-35s %s\n" "$p" "$state"
done
```

How it works: each provider should show `Registered`. If one is still registering, re-run the check after a minute.

4. Install or update the Azure CLI extensions used by the infrastructure scripts.

```bash
source ./env.sh
az extension add --upgrade --name alb -y
az extension add --upgrade --name amg -y
az extension add --upgrade --name aks-preview -y
az version --query '"azure-cli"' -o tsv
az extension list --query "[].{name:name, version:version}" -o table
```

How it works: `--upgrade` makes the command idempotent: it installs the extension if missing and updates it if present. The validated fix is to avoid pinning the broken `aks-preview` version from the deck.

5. Create the resource group.

```bash
source ./env.sh
az group create -n "$RG" -l "$LOCATION" -o none
az group show -n "$RG" --query "{name:name, location:location}" -o table
```

How it works: the resource group name and region come from `env.sh`. Re-running `az group create` is safe; Azure updates the existing group if it already exists.

### Hands-on examples

#### Check one provider in detail

Use this when a later command says a namespace is not registered.

```bash
source ./env.sh
az provider show -n Microsoft.ContainerService \
  --query "{namespace:namespace, state:registrationState}" -o yaml
```

This checks the AKS provider directly. `Microsoft.ContainerService` must be registered before `az aks create` can succeed.

#### See what will live in the platform resource group

After later sections run, this command gives a beginner-friendly inventory.

```bash
source ./env.sh
az resource list -g "$RG" --query "[].{name:name, type:type, location:location}" -o table
```

The resource group becomes the main boundary for the tutorial platform resources.

#### Register a single provider and watch it turn Registered

Registration is asynchronous. This polls one provider until Azure reports `Registered`.

```bash
source ./env.sh
az provider register --namespace Microsoft.KeyVault
until [ "$(az provider show -n Microsoft.KeyVault --query registrationState -o tsv)" = "Registered" ]; do
  echo "waiting for Microsoft.KeyVault ..."
  sleep 10
done
echo "Microsoft.KeyVault is Registered"
```

Use this pattern whenever a later command complains that a namespace is not registered — swap in the provider it names.

#### List only the providers this platform needs

```bash
source ./env.sh
az provider list --query "[?registrationState=='Registered'].namespace" -o tsv \
  | grep -E 'ContainerService|KeyVault|Monitor|ServiceNetworking|Dashboard|OperationalInsights' \
  | sort
```

This filters the full provider list down to the six namespaces this platform depends on, so you can confirm every prerequisite in one glance.

## 2. Networking

**What & why**

AKS nodes run inside an Azure Virtual Network (VNet), which is your private network boundary. This deployment uses a system-node subnet for the AKS system pool and later adds a private-endpoint subnet for Key Vault. The cluster uses Azure CNI Overlay, so pod IPs come from a separate pod CIDR and do not consume VNet IP addresses.

### Steps

1. Create the Log Analytics workspace used later by Container Insights.

```bash
source ./env.sh
az monitor log-analytics workspace create \
  -g "$RG" -n "$LAW" -l "$LOCATION" -o none
LAW_ID=$(az monitor log-analytics workspace show \
  -g "$RG" -n "$LAW" --query id -o tsv)
echo "LAW_ID=$LAW_ID"
```

How it works: Log Analytics stores container logs and diagnostic data. `LAW_ID` is the Azure resource ID, not a secret.

2. Create the VNet and the system subnet.

```bash
source ./env.sh
if ! az network vnet show -g "$RG" -n "$VNET" -o none 2>/dev/null; then
  az network vnet create -g "$RG" -n "$VNET" \
    --address-prefixes 10.0.0.0/16 \
    --subnet-name snet-sys \
    --subnet-prefixes 10.0.0.0/22 -o none
else
  az network vnet subnet show -g "$RG" --vnet-name "$VNET" -n snet-sys -o none 2>/dev/null || \
    az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n snet-sys \
      --address-prefixes 10.0.0.0/22 -o none
fi
```

How it works: `10.0.0.0/16` is the VNet address space. `snet-sys` is where the initial AKS system node pool will be attached.

3. Capture and verify the system subnet ID.

```bash
source ./env.sh
SYS_SUBNET_ID=$(az network vnet subnet show \
  -g "$RG" --vnet-name "$VNET" -n snet-sys --query id -o tsv)
echo "SYS_SUBNET_ID=$SYS_SUBNET_ID"
az network vnet subnet show \
  -g "$RG" --vnet-name "$VNET" -n snet-sys \
  --query "{name:name, prefix:addressPrefix, id:id}" -o yaml
```

How it works: AKS needs the subnet resource ID when the cluster is created. The ID contains your subscription ID, so use it in commands but do not paste the real value into shared docs.

4. Reserve the service CIDR that AKS will use internally.

```bash
source ./env.sh
export AKS_SERVICE_CIDR=172.16.0.0/16
export AKS_DNS_SERVICE_IP=172.16.0.10
echo "AKS services: $AKS_SERVICE_CIDR, DNS: $AKS_DNS_SERVICE_IP"
```

How it works: Kubernetes Services get virtual IPs from the service CIDR. The validated fix is to set `172.16.0.0/16` and `172.16.0.10` explicitly so AKS does not default to `10.0.0.0/16`, which overlaps this VNet.

### Hands-on examples

#### Show VNet and subnet ranges

```bash
source ./env.sh
az network vnet show -g "$RG" -n "$VNET" \
  --query "{vnet:name, prefixes:addressSpace.addressPrefixes, subnets:subnets[].{name:name,prefix:addressPrefix}}" -o yaml
```

This helps you see the difference between the whole VNet range and individual subnet ranges.

#### Understand overlay pod addressing

```bash
source ./env.sh
echo "VNet:        10.0.0.0/16"
echo "System net:  snet-sys = 10.0.0.0/22"
echo "Pod CIDR:    10.244.0.0/16 (overlay)"
echo "Service CIDR:172.16.0.0/16"
```

With Azure CNI Overlay, pods use the overlay pod CIDR instead of taking IPs directly from `snet-sys`.

#### Add the private-endpoint subnet Key Vault will use

Section 6 places Key Vault behind a private endpoint, which needs its own subnet. Create it now.

```bash
source ./env.sh
az network vnet subnet create \
  -g "$RG" --vnet-name "$VNET" -n snet-pe \
  --address-prefixes 10.0.4.0/24 \
  --disable-private-endpoint-network-policies true -o none
az network vnet subnet show -g "$RG" --vnet-name "$VNET" -n snet-pe \
  --query "{name:name, prefix:addressPrefix}" -o table
```

`--disable-private-endpoint-network-policies true` is required before a private endpoint can attach to the subnet. `10.0.4.0/24` sits inside the VNet but does not overlap `snet-sys` (`10.0.0.0/22`).

#### Prove your subnets do not overlap

```bash
source ./env.sh
az network vnet subnet list -g "$RG" --vnet-name "$VNET" \
  --query "[].{name:name, prefix:addressPrefix}" -o table
```

Overlapping ranges are the most common networking mistake. `snet-sys` (`10.0.0.0/22`) and `snet-pe` (`10.0.4.0/24`) are distinct, and both stay clear of the `172.16.0.0/16` service CIDR — which is exactly why Section 2 reserves Kubernetes services on `172.16` instead of the default `10.0`.

## 3. Identity, RBAC & Entra groups

**What & why**

Microsoft Entra ID is the identity system used for people, groups, and workload identities. AKS Azure RBAC maps Entra groups to Kubernetes permissions, so you can grant admin, writer, or reader access without handing out local cluster credentials. The validated deployment disables local accounts and uses Entra-backed access.

### Steps

1. Confirm the sanitized group variables from `env.sh` are present.

```bash
source ./env.sh
printf "ADMIN_GROUP=%s\nAKS_ADMIN=%s\nAKS_DEV=%s\nAKS_READ=%s\n" \
  '$ADMIN_GROUP' '$AKS_ADMIN' '$AKS_DEV' '$AKS_READ'
```

How it works: the real object IDs live in your local `env.sh`, but repo-safe docs should reference only the variable names. `$AKS_ADMIN`, `$AKS_DEV`, and `$AKS_READ` represent Entra group object IDs.

2. Get the AKS resource ID after the cluster exists.

```bash
source ./env.sh
AKS_ID=$(az aks show -g "$RG" -n "$AKS" --query id -o tsv)
echo "AKS_ID=$AKS_ID"
```

How it works: Azure role assignments need a scope. Here, the scope is the AKS cluster resource ID, or a namespace path under that resource ID.

3. Assign cluster-admin access to the platform administrator group.

```bash
source ./env.sh
AKS_ID=$(az aks show -g "$RG" -n "$AKS" --query id -o tsv)
az role assignment create \
  --assignee "$AKS_ADMIN" \
  --role "Azure Kubernetes Service RBAC Cluster Admin" \
  --scope "$AKS_ID" -o none
```

How it works: `Azure Kubernetes Service RBAC Cluster Admin` grants Kubernetes admin permissions through Azure RBAC. Use it only for the platform administrators group.

4. Assign writer access to developers in the `demo` namespace.

```bash
source ./env.sh
AKS_ID=$(az aks show -g "$RG" -n "$AKS" --query id -o tsv)
az role assignment create \
  --assignee "$AKS_DEV" \
  --role "Azure Kubernetes Service RBAC Writer" \
  --scope "$AKS_ID/namespaces/demo" -o none
```

How it works: scoping the role to `$AKS_ID/namespaces/demo` limits developers to one namespace. A namespace is a Kubernetes partition used to group related app resources.

5. Assign read-only access and kubeconfig access.

```bash
source ./env.sh
AKS_ID=$(az aks show -g "$RG" -n "$AKS" --query id -o tsv)
az role assignment create \
  --assignee "$AKS_READ" \
  --role "Azure Kubernetes Service RBAC Reader" \
  --scope "$AKS_ID" -o none

for grp in "$AKS_ADMIN" "$AKS_DEV" "$AKS_READ"; do
  az role assignment create \
    --assignee "$grp" \
    --role "Azure Kubernetes Service Cluster User Role" \
    --scope "$AKS_ID" -o none
done
```

How it works: `RBAC Reader` allows read-only Kubernetes access. `Cluster User Role` lets group members run `az aks get-credentials`; without it they may have Kubernetes permissions but still fail to download kubeconfig.

6. Review the cluster-scope assignments.

```bash
source ./env.sh
AKS_ID=$(az aks show -g "$RG" -n "$AKS" --query id -o tsv)
az role assignment list --scope "$AKS_ID" \
  --query "[].{principal:principalName, role:roleDefinitionName, scope:scope}" -o table
```

How it works: this shows who has Azure RBAC permissions at the cluster scope. Namespace-scoped assignments are under a more specific scope.

### Hands-on examples

#### Create a new Entra group for a lab

```bash
source ./env.sh
az ad group create \
  --display-name "aks-platform-lab-readers" \
  --mail-nickname "aks-platform-lab-readers" \
  --query "{displayName:displayName, objectId:id}" -o yaml
```

Use the returned object ID as `<your-object-id>` in experiments. Do not commit the real object ID to repo-safe content.

#### Assign reader access to a custom group

```bash
source ./env.sh
AKS_ID=$(az aks show -g "$RG" -n "$AKS" --query id -o tsv)
az role assignment create \
  --assignee "<your-object-id>" \
  --role "Azure Kubernetes Service RBAC Reader" \
  --scope "$AKS_ID" -o none
```

This is the same pattern as `$AKS_READ`, but uses a placeholder for a group you create yourself.

#### Test a user-friendly kubeconfig flow

```bash
source ./env.sh
az aks get-credentials -g "$RG" -n "$AKS" --overwrite-existing
kubelogin convert-kubeconfig -l azurecli
kubectl auth can-i get pods -n demo
```

`kubelogin` converts the kubeconfig to use Azure CLI authentication. `kubectl auth can-i` asks the API server what your current identity is allowed to do.

#### List every role assignment for one group

```bash
source ./env.sh
az role assignment list \
  --assignee "$AKS_ADMIN" --all \
  --query "[].{role:roleDefinitionName, scope:scope}" -o table
```

`--all` walks every scope in the subscription, so you can see exactly where the admin group has been granted access. Swap `$AKS_ADMIN` for `$AKS_DEV` or `$AKS_READ` to audit the developer and reader groups the same way.

## 4. AKS Cluster + Node Pools + System-Pool Pinning

**What & why**

An AKS cluster has a managed control plane and one or more node pools where pods run. This validated platform uses a dedicated system pool for AKS-managed add-ons plus pinned platform control-plane add-ons, and a separate user pool for application workloads. The system pool is `Standard_D4s_v6` with autoscaler min 2 / max 3; min 2 is required because the platform add-ons and kube-system pods do not fit reliably on one node.

### Steps

1. Pick and pin a Kubernetes version offered in your region.

```bash
source ./env.sh
az aks get-versions -l "$LOCATION" -o table
export K8S_VERSION="<supported-aks-version>"
echo "K8S_VERSION=$K8S_VERSION"
```

How it works: pinning avoids silently getting a newer regional default later. Choose a non-preview version shown by `az aks get-versions` for your region.

2. Derive the system subnet ID in the current shell.

```bash
source ./env.sh
SYS_SUBNET_ID=$(az network vnet subnet show \
  -g "$RG" --vnet-name "$VNET" -n snet-sys --query id -o tsv)
echo "SYS_SUBNET_ID=$SYS_SUBNET_ID"
```

How it works: each script starts from a fresh shell, so it re-derives IDs instead of assuming a previous variable still exists.

3. Create the AKS cluster with the validated networking, identity, and system-pool settings.

```bash
source ./env.sh
export K8S_VERSION="<supported-aks-version>"
SYS_SUBNET_ID=$(az network vnet subnet show \
  -g "$RG" --vnet-name "$VNET" -n snet-sys --query id -o tsv)

az aks create -g "$RG" -n "$AKS" -l "$LOCATION" \
  --kubernetes-version "$K8S_VERSION" \
  --tier standard \
  --network-plugin azure \
  --network-plugin-mode overlay \
  --network-dataplane cilium \
  --network-policy cilium \
  --pod-cidr 10.244.0.0/16 \
  --service-cidr 172.16.0.0/16 \
  --dns-service-ip 172.16.0.10 \
  --vnet-subnet-id "$SYS_SUBNET_ID" \
  --nodepool-name systempool \
  --node-count "$SYS_NODE_COUNT" ${AKS_ZONES:+--zones $AKS_ZONES} \
  --node-vm-size "$SYS_VM_SIZE" \
  --enable-cluster-autoscaler \
  --min-count "$SYS_MIN" --max-count "$SYS_MAX" \
  --enable-aad --enable-azure-rbac \
  --aad-admin-group-object-ids "$ADMIN_GROUP" \
  --enable-oidc-issuer \
  --enable-workload-identity \
  --enable-managed-identity \
  --disable-local-accounts \
  --auto-upgrade-channel patch \
  --node-os-upgrade-channel NodeImage \
  --generate-ssh-keys \
  --enable-acns \
  -o none
```

How it works: overlay + Cilium provides scalable pod networking and Cilium network policy. `--service-cidr 172.16.0.0/16 --dns-service-ip 172.16.0.10` is mandatory in this validated design to avoid overlap with the VNet, and `${AKS_ZONES:+--zones $AKS_ZONES}` uses zones `1 2 3` unless `SANDBOX_NO_ZONES=1` disables them for sandbox subscriptions.

4. Add the frugal user node pool for application workloads.

```bash
source ./env.sh
az aks nodepool add -g "$RG" --cluster-name "$AKS" \
  --name userpool --mode User \
  --node-count "$USER_NODE_COUNT" ${AKS_ZONES:+--zones $AKS_ZONES} \
  --node-vm-size "$USER_VM_SIZE" \
  --enable-cluster-autoscaler \
  --min-count "$USER_MIN" --max-count "$USER_MAX" \
  --labels workload=general -o none
```

How it works: the user pool is `Standard_D2s_v6`, autoscaler min 1 / max 3. It is intentionally smaller and reserved for workloads, not platform control-plane add-ons.

5. Taint the system pool so regular workloads do not land there.

```bash
source ./env.sh
az aks nodepool update -g "$RG" --cluster-name "$AKS" --name systempool \
  --node-taints CriticalAddonsOnly=true:NoSchedule -o none
```

How it works: a taint is a “keep out unless tolerated” rule on nodes. Only pods with the matching `CriticalAddonsOnly` toleration can schedule onto the system pool.

6. Get kubeconfig and validate the load-bearing settings.

```bash
source ./env.sh
az aks get-credentials -g "$RG" -n "$AKS" --overwrite-existing
kubelogin convert-kubeconfig -l azurecli

kubectl get nodes -o wide
kubectl get nodes -L topology.kubernetes.io/zone,kubernetes.azure.com/mode
kubectl -n kube-system get pods | grep -i cilium || echo "No cilium pods listed yet"
az aks show -g "$RG" -n "$AKS" --query oidcIssuerProfile.issuerUrl -o tsv
az aks show -g "$RG" -n "$AKS" \
  --query "{wi:securityProfile.workloadIdentity.enabled, azrbac:aadProfile.enableAzureRbac, network:networkProfile}" -o yaml
```

How it works: this verifies nodes, zones, Cilium, OIDC issuer, Workload Identity, Azure RBAC, and network profile. The node label `kubernetes.azure.com/mode=system` is the stable label used for platform pinning.

### Hands-on examples

#### Pin platform add-ons to the system pool

Platform add-ons such as Argo CD, Kyverno, KEDA, and the ALB controller are pinned with the helper in `platform/lib/pin.sh`.

```bash
source ./env.sh
source ./platform/lib/pin.sh
pin_to_system argocd deploy/argocd-server deploy/argocd-repo-server deploy/argocd-application-controller
pin_to_system keda deploy/keda-operator deploy/keda-operator-metrics-apiserver
```

The helper patches workloads with `nodeSelector: kubernetes.azure.com/mode=system` and a `CriticalAddonsOnly=true:NoSchedule` toleration. It uses the mode label, not `agentpool=<name>`, so the pin survives future system pool name or SKU changes.

#### See the exact pinning patch

```bash
cat <<'JSON'
{
  "spec": {
    "template": {
      "spec": {
        "nodeSelector": {
          "kubernetes.azure.com/mode": "system"
        },
        "tolerations": [
          {
            "key": "CriticalAddonsOnly",
            "operator": "Equal",
            "value": "true",
            "effect": "NoSchedule"
          }
        ]
      }
    }
  }
}
JSON
```

A node selector chooses nodes by label. A toleration allows the pod onto nodes that carry the matching taint.

#### Read node labels and taints

```bash
kubectl get nodes -L kubernetes.azure.com/mode,kubernetes.azure.com/agentpool
kubectl describe nodes | grep -E "Name:|Taints:|kubernetes.azure.com/mode|kubernetes.azure.com/agentpool"
```

This shows why `mode=system` is more durable than matching the pool name. Labels identify node characteristics; taints control scheduling.

#### Temporarily disable zones in a sandbox

```bash
export SANDBOX_NO_ZONES=1
source ./env.sh
echo "AKS_ZONES='$AKS_ZONES'"
```

Production should use zones `1 2 3`. Some sandbox subscriptions or regions reject zonal node pools, so `SANDBOX_NO_ZONES=1` intentionally omits `--zones`.

## 5. Workload Identity

**What & why**

Workload Identity lets a Kubernetes ServiceAccount authenticate to Azure without a client secret. AKS issues a token for the pod, Entra trusts that token through a federated credential, and Azure grants the mapped managed identity access to resources. This is safer than storing passwords or secrets in Kubernetes.

### Steps

1. Confirm the cluster has an OIDC issuer.

```bash
source ./env.sh
OIDC=$(az aks show -g "$RG" -n "$AKS" --query oidcIssuerProfile.issuerUrl -o tsv)
echo "OIDC issuer: $OIDC"
test -n "$OIDC"
```

How it works: OIDC is the token issuer AKS uses for Workload Identity. If this is empty, the cluster was not created with `--enable-oidc-issuer`.

2. Create the managed identity for the demo workload.

```bash
source ./env.sh
az identity create -g "$RG" -n demo-identity -o none
DEMO_CLIENT=$(az identity show -g "$RG" -n demo-identity --query clientId -o tsv)
echo "DEMO_CLIENT=$DEMO_CLIENT"
```

How it works: a user-assigned managed identity is an Azure identity your pod can use. `clientId` is needed in Kubernetes annotations but should be referenced as `$DEMO_CLIENT` in repo-safe docs.

3. Create the federated credential that binds the ServiceAccount to the identity.

```bash
source ./env.sh
OIDC=$(az aks show -g "$RG" -n "$AKS" --query oidcIssuerProfile.issuerUrl -o tsv)
az identity federated-credential create \
  --name demo-fic \
  -g "$RG" \
  --identity-name demo-identity \
  --issuer "$OIDC" \
  --subject system:serviceaccount:demo:demo-sa \
  --audience api://AzureADTokenExchange \
  -o none
```

How it works: the subject means “the ServiceAccount named `demo-sa` in the `demo` namespace.” The audience `api://AzureADTokenExchange` is the standard Entra token exchange audience for Workload Identity.

4. Create the namespace and annotated ServiceAccount.

```bash
source ./env.sh
DEMO_CLIENT=$(az identity show -g "$RG" -n demo-identity --query clientId -o tsv)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: demo
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: demo-sa
  namespace: demo
  annotations:
    azure.workload.identity/client-id: "$DEMO_CLIENT"
  labels:
    azure.workload.identity/use: "true"
EOF
```

How it works: the annotation points the ServiceAccount to the managed identity client ID. The label tells the Workload Identity webhook to inject the projected token into pods that use this ServiceAccount.

5. Verify the ServiceAccount configuration.

```bash
kubectl -n demo get serviceaccount demo-sa -o yaml
az identity federated-credential list \
  -g "$RG" --identity-name demo-identity \
  --query "[].{name:name, subject:subject, issuer:issuer}" -o table
```

How it works: both sides must match: Kubernetes has the ServiceAccount annotation, and Azure has a federated credential for the same namespace/name subject.

### Hands-on examples

#### Create a second federated credential for another namespace

```bash
source ./env.sh
OIDC=$(az aks show -g "$RG" -n "$AKS" --query oidcIssuerProfile.issuerUrl -o tsv)
az identity federated-credential create \
  --name api-fic \
  -g "$RG" \
  --identity-name demo-identity \
  --issuer "$OIDC" \
  --subject system:serviceaccount:api:api-sa \
  --audience api://AzureADTokenExchange \
  -o none
```

Federated credentials are exact matches. `api/api-sa` would not grant access to `demo/demo-sa`.

#### Check what a pod will use

```bash
kubectl -n demo get sa demo-sa \
  -o jsonpath='{.metadata.annotations.azure\.workload\.identity/client-id}{"\n"}'
kubectl -n demo get sa demo-sa --show-labels
```

This confirms the ServiceAccount has both the client-id annotation and the `azure.workload.identity/use=true` label.

#### Inspect the cluster OIDC issuer URL

```bash
source ./env.sh
az aks show -g "$RG" -n "$AKS" \
  --query oidcIssuerProfile.issuerUrl -o tsv
```

Every federated credential's `--issuer` must match this URL exactly. It is public (not a secret) and is the trust anchor Entra uses to validate the tokens your pods present.

#### Remove a federated credential you no longer need

```bash
source ./env.sh
az identity federated-credential delete \
  --name api-fic \
  -g "$RG" --identity-name demo-identity --yes -o none
```

Federated credentials are cheap but should be cleaned up when a namespace or service account is retired, so trust does not linger for workloads that no longer exist.

## 6. Key Vault + Private Endpoint + CSI Secret Mount

**What & why**

Key Vault stores secrets outside the cluster, and the Secrets Store CSI driver mounts selected secrets into pods as files. In locked-down subscriptions, public Key Vault access can fail, so the validated design uses a private endpoint plus the private DNS zone `privatelink.vaultcore.azure.net`. The SecretProviderClass CRD apiVersion must be `secrets-store.csi.x-k8s.io/v1`.

### Steps

1. Create the Key Vault in Azure RBAC mode.

```bash
source ./env.sh
az keyvault show -n "$KV" -o none 2>/dev/null || \
  az keyvault create -g "$RG" -n "$KV" -l "$LOCATION" \
    --enable-rbac-authorization true -o none
KV_ID=$(az keyvault show -n "$KV" --query id -o tsv)
echo "KV_ID=$KV_ID"
```

How it works: Azure RBAC mode means permissions are assigned with Azure role assignments instead of Key Vault access policies. The vault name comes from `$KV`.

2. Grant the demo workload read access to Key Vault secrets.

```bash
source ./env.sh
DEMO_PRIN=$(az identity show -g "$RG" -n demo-identity --query principalId -o tsv)
KV_ID=$(az keyvault show -n "$KV" --query id -o tsv)
az role assignment create \
  --assignee "$DEMO_PRIN" \
  --role "Key Vault Secrets User" \
  --scope "$KV_ID" -o none
```

How it works: `Key Vault Secrets User` lets the workload read secret values at runtime. It does not grant permission to manage the vault itself.

3. Enable the AKS Secrets Store CSI add-on with rotation.

```bash
source ./env.sh
az aks enable-addons -g "$RG" -n "$AKS" \
  --addons azure-keyvault-secrets-provider \
  --enable-secret-rotation -o none
```

How it works: the CSI driver is the Kubernetes component that mounts external secrets into pods. Rotation lets mounted values refresh after the Key Vault secret changes.

4. Create the private-endpoint subnet.

```bash
source ./env.sh
PE_SUBNET=snet-pe
PE_PREFIX=10.0.5.0/24
az network vnet subnet show -g "$RG" --vnet-name "$VNET" -n "$PE_SUBNET" -o none 2>/dev/null || \
  az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n "$PE_SUBNET" \
    --address-prefixes "$PE_PREFIX" -o none
```

How it works: private endpoints need an IP address in your VNet. `10.0.5.0/24` is kept separate from `snet-sys`.

5. Create the private DNS zone and link it to the VNet.

```bash
source ./env.sh
DNS_ZONE=privatelink.vaultcore.azure.net
az network private-dns zone show -g "$RG" -n "$DNS_ZONE" -o none 2>/dev/null || \
  az network private-dns zone create -g "$RG" -n "$DNS_ZONE" -o none
az network private-dns link vnet show -g "$RG" -z "$DNS_ZONE" -n "link-$VNET" -o none 2>/dev/null || \
  az network private-dns link vnet create -g "$RG" -z "$DNS_ZONE" -n "link-$VNET" \
    --virtual-network "$VNET" --registration-enabled false -o none
```

How it works: private DNS makes `$KV.vault.azure.net` resolve to the private endpoint IP from inside the VNet. Without this, pods may try the public endpoint and fail.

6. Create the private endpoint and DNS zone group.

```bash
source ./env.sh
PE_SUBNET=snet-pe
DNS_ZONE=privatelink.vaultcore.azure.net
PE_NAME="pe-$KV"
KV_ID=$(az keyvault show -n "$KV" --query id -o tsv)

az network private-endpoint show -g "$RG" -n "$PE_NAME" -o none 2>/dev/null || \
  az network private-endpoint create -g "$RG" -n "$PE_NAME" -l "$LOCATION" \
    --vnet-name "$VNET" --subnet "$PE_SUBNET" \
    --private-connection-resource-id "$KV_ID" \
    --group-id vault \
    --connection-name "conn-$KV" -o none

ZONE_ID="/subscriptions/${SUB_ID}/resourceGroups/${RG}/providers/Microsoft.Network/privateDnsZones/${DNS_ZONE}"
az network private-endpoint dns-zone-group show -g "$RG" --endpoint-name "$PE_NAME" -n zg -o none 2>/dev/null || \
  az network private-endpoint dns-zone-group create -g "$RG" \
    --endpoint-name "$PE_NAME" -n zg \
    --private-dns-zone "$ZONE_ID" --zone-name vault -o none
```

How it works: the endpoint connects the VNet to the Key Vault private link resource using group ID `vault`. The DNS zone group creates the private A record; pass the zone resource ID, not just the zone name.

7. Validate private endpoint DNS.

```bash
source ./env.sh
DNS_ZONE=privatelink.vaultcore.azure.net
PE_NAME="pe-$KV"
az network private-endpoint show -g "$RG" -n "$PE_NAME" \
  --query "customDnsConfigs[].{fqdn:fqdn, ip:ipAddresses[0]}" -o table
az network private-dns record-set a list -g "$RG" -z "$DNS_ZONE" \
  --query "[].{record:name, ip:aRecords[0].ipv4Address}" -o table
```

How it works: the private DNS record should point the vault name to a private `10.0.5.x` address.

8. Seed a demo secret from inside the VNet without exposing a real value.

```bash
source ./env.sh
export KV_NAME="$KV"
export SECRET_NAME=demo-secret
export SECRET_VALUE="<demo-secret-value>"
DEMO_PRIN=$(az identity show -g "$RG" -n demo-identity --query principalId -o tsv)
KV_ID=$(az keyvault show -n "$KV" --query id -o tsv)

az role assignment create \
  --assignee "$DEMO_PRIN" \
  --role "Key Vault Secrets Officer" \
  --scope "$KV_ID" -o none

cat <<'EOF' | envsubst '$KV_NAME $SECRET_NAME $SECRET_VALUE' | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: kv-seed-secret
  namespace: demo
spec:
  backoffLimit: 2
  ttlSecondsAfterFinished: 600
  template:
    metadata:
      labels:
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: demo-sa
      restartPolicy: Never
      containers:
        - name: seed
          image: mcr.microsoft.com/azure-cli:latest
          command: ["/bin/bash", "-c"]
          args:
            - |
              set -e
              az login --service-principal \
                -u "$AZURE_CLIENT_ID" -t "$AZURE_TENANT_ID" \
                --federated-token "$(cat "$AZURE_FEDERATED_TOKEN_FILE")" >/dev/null
              az keyvault secret set --vault-name "${KV_NAME}" \
                --name "${SECRET_NAME}" --value "${SECRET_VALUE}" -o none
EOF

kubectl -n demo wait --for=condition=complete job/kv-seed-secret --timeout=240s
az role assignment delete \
  --assignee "$DEMO_PRIN" \
  --role "Key Vault Secrets Officer" \
  --scope "$KV_ID" -o none
```

How it works: the job runs on AKS inside the VNet, reaches Key Vault through the private endpoint, and authenticates with Workload Identity. The write role is temporary; after seeding, the workload keeps only read access.

### Hands-on examples

#### Create a SecretProviderClass for the demo secret

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: demo-kv
  namespace: demo
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "false"
    clientID: "$DEMO_CLIENT"
    keyvaultName: "$KV"
    tenantId: "$TENANT_ID"
    objects: |
      array:
        - |
          objectName: demo-secret
          objectType: secret
```

This object tells the CSI driver which vault, identity, tenant, and secret to use. The validated API version is `secrets-store.csi.x-k8s.io/v1`.

#### Apply the SecretProviderClass with environment substitution

```bash
source ./env.sh
DEMO_CLIENT=$(az identity show -g "$RG" -n demo-identity --query clientId -o tsv)
export DEMO_CLIENT KV_NAME="$KV" TENANT_ID
cat <<'EOF' | envsubst '$DEMO_CLIENT $KV_NAME $TENANT_ID' | kubectl apply -f -
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: demo-kv
  namespace: demo
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "false"
    clientID: "${DEMO_CLIENT}"
    keyvaultName: "${KV_NAME}"
    tenantId: "${TENANT_ID}"
    objects: |
      array:
        - |
          objectName: demo-secret
          objectType: secret
EOF
```

`envsubst` fills only the safe variable references at apply time. Do not hard-code real tenant IDs or client IDs in committed manifests.

#### Mount and verify the secret file in a test pod

```bash
kubectl -n demo apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: kv-mount-test
  labels:
    azure.workload.identity/use: "true"
spec:
  serviceAccountName: demo-sa
  restartPolicy: Never
  containers:
    - name: app
      image: mcr.microsoft.com/azure-cli:latest
      command: ["/bin/bash", "-c", "ls -l /mnt/secrets-store && test -s /mnt/secrets-store/demo-secret && echo mounted"]
      volumeMounts:
        - name: secrets-store
          mountPath: /mnt/secrets-store
          readOnly: true
  volumes:
    - name: secrets-store
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: demo-kv
EOF
kubectl -n demo wait --for=condition=Ready pod/kv-mount-test --timeout=120s || true
kubectl -n demo logs kv-mount-test
```

This verifies the file exists without printing the secret value. The pod uses `demo-sa`, so the CSI driver can exchange the projected token for Key Vault access.

#### Clean up the test pod

```bash
kubectl -n demo delete pod kv-mount-test --ignore-not-found
```

Cleaning up test pods keeps the namespace tidy after validation.

---

## 7. Application Gateway for Containers / ALB ingress

**What & why**

Application Gateway for Containers (AGC), also called the ALB data plane in the manifests, gives AKS a managed HTTP/HTTPS entry point. This section uses Kubernetes Gateway API: a standard set of Custom Resource Definitions (CRDs) where the platform team owns the shared `Gateway` and app teams attach `HTTPRoute` objects. Success is not just “pods are running”; the validated success signal is `Gateway` and `HTTPRoute` reporting `Programmed=True`.

Assume you run this once before each section:

```bash
source ./env.sh
```

### Steps

1. Create the ALB controller identity and grant roles on the AKS node resource group.

```bash
az identity create -g "$RG" -n alb-identity -o none 2>/dev/null || true
ALB_MI_CLIENT=$(az identity show -g "$RG" -n alb-identity --query clientId -o tsv)
ALB_MI_PRIN=$(az identity show -g "$RG" -n alb-identity --query principalId -o tsv)
OIDC=$(az aks show -g "$RG" -n "$AKS" --query oidcIssuerProfile.issuerUrl -o tsv)

az identity federated-credential create \
  --name alb-fic -g "$RG" --identity-name alb-identity \
  --issuer "$OIDC" \
  --subject system:serviceaccount:azure-alb-system:alb-controller-sa \
  --audience api://AzureADTokenExchange -o none 2>/dev/null || true

NODE_RG=$(az aks show -g "$RG" -n "$AKS" --query nodeResourceGroup -o tsv)
NODE_RG_ID=$(az group show -n "$NODE_RG" --query id -o tsv)
az role assignment create --assignee-object-id "$ALB_MI_PRIN" --assignee-principal-type ServicePrincipal \
  --role 'AppGw for Containers Configuration Manager' --scope "$NODE_RG_ID" -o none 2>/dev/null || true
az role assignment create --assignee-object-id "$ALB_MI_PRIN" --assignee-principal-type ServicePrincipal \
  --role 'Reader' --scope "$NODE_RG_ID" -o none 2>/dev/null || true
```

How it works: Workload Identity lets the controller call Azure without a secret. The validated fix is role scope: the ALB identity needs access to the node resource group (`MC_...`), not only the cluster resource group, because AGC associations are reconciled there.

2. Create the delegated ALB subnet and grant subnet permissions.

```bash
az network vnet subnet create -g "$RG" --vnet-name "$VNET" -n snet-alb \
  --address-prefixes 10.0.4.0/24 \
  --delegations Microsoft.ServiceNetworking/trafficControllers -o none 2>/dev/null || true
export ALB_SUBNET_ID=$(az network vnet subnet show -g "$RG" --vnet-name "$VNET" -n snet-alb --query id -o tsv)
az role assignment create --assignee-object-id "$ALB_MI_PRIN" --assignee-principal-type ServicePrincipal \
  --role 'Network Contributor' --scope "$ALB_SUBNET_ID" -o none 2>/dev/null || true
```

How it works: AGC uses a delegated subnet for data-plane networking. The role is scoped narrowly to that subnet.

3. Install the ALB Controller and pin it to the system pool.

```bash
source ./platform/lib/pin.sh
ALB_CHART=oci://mcr.microsoft.com/application-lb/charts/alb-controller
ALB_VER=$(helm show chart "$ALB_CHART" 2>/dev/null | awk '/^version:/{print $2}')
helm upgrade --install alb-controller "$ALB_CHART" -n azure-alb-system --create-namespace \
  ${ALB_VER:+--version "$ALB_VER"} \
  --set albController.namespace=azure-alb-system \
  --set albController.podIdentity.clientID="$ALB_MI_CLIENT" \
  --wait --timeout 5m
pin_to_system azure-alb-system deploy/alb-controller
```

How it works: `platform/lib/pin.sh` provides `pin_to_system <ns> <kind/name>...`, which patches add-on pods with `nodeSelector: kubernetes.azure.com/mode=system` and a `CriticalAddonsOnly` toleration. This keeps platform add-ons on the system pool.

4. Apply the ApplicationLoadBalancer and Gateway.

```bash
kubectl create namespace alb-infra --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace demo --dry-run=client -o yaml | kubectl apply -f -
envsubst '$ALB_SUBNET_ID' < platform/agc/alb.yaml.tmpl | sed 's/\r$//' | kubectl apply -f -
mkdir -p .certs
openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
  -keyout .certs/demo-tls.key -out .certs/demo-tls.crt \
  -subj "/CN=${APP_HOST:-app.contoso.com}"
kubectl -n demo create secret tls demo-tls --cert=.certs/demo-tls.crt --key=.certs/demo-tls.key \
  --dry-run=client -o yaml | kubectl apply -f -
sed 's/\r$//' platform/agc/gateway.yaml | kubectl apply -f -
```

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: gw-platform
  namespace: demo
  annotations:
    alb.networking.azure.io/alb-namespace: alb-infra
    alb.networking.azure.io/alb-name: alb-platform
spec:
  gatewayClassName: azure-alb-external
  listeners:
  - name: https
    port: 443
    protocol: HTTPS
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        name: demo-tls
    allowedRoutes:
      namespaces:
        from: Same
```

How it works: the `ApplicationLoadBalancer` points at the delegated subnet; the `Gateway` creates the public HTTPS listener. The self-signed certificate is validation-only.

5. Apply the HTTPRoute and wait for programming.

```bash
sed 's/\r$//' apps/demo/httproute.yaml | kubectl apply -f -
for i in $(seq 1 30); do
  PROG=$(kubectl get gateway gw-platform -n demo -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || true)
  ROUTE_PROG=$(kubectl -n demo get httproute demo-route -o jsonpath='{.status.parents[0].conditions[?(@.type=="Programmed")].status}' 2>/dev/null || true)
  [ "$PROG" = "True" ] && [ "$ROUTE_PROG" = "True" ] && break
  sleep 10
done
kubectl get gateway gw-platform -n demo
kubectl get httproute demo-route -n demo
```

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: demo-route
  namespace: demo
spec:
  parentRefs:
  - name: gw-platform
  hostnames:
  - "app.contoso.com"
  rules:
  - matches:
    - path: { type: PathPrefix, value: / }
    backendRefs:
    - { name: demo-svc, port: 80 }
```

How it works: `HTTPRoute` maps a hostname and path to a Service. `Programmed=True` means the controller pushed the route to AGC.

### Hands-on examples

The examples below go from *inspecting* the gateway to *reaching* your app, then on to more advanced routing. Start at the top if you are new to the Gateway API.

#### See the gateway and its public address

The `Gateway` is the shared front door. This is how you find it and, crucially, the public address AGC gave it.

```bash
source ./env.sh
# List every Gateway in the cluster (which namespace, which class, is it Programmed?)
kubectl get gateway -A

# Look at ours in detail
kubectl get gateway gw-platform -n demo -o wide
kubectl describe gateway gw-platform -n demo

# The one value you care about: the public entry point AGC assigned
kubectl get gateway gw-platform -n demo \
  -o jsonpath='{.status.addresses[0].value}{"\n"}'
```

How it works: `describe` shows the listeners (here HTTPS on 443) and a `Programmed=True` condition once AGC has accepted the config. The value under `.status.addresses` is an **AGC frontend FQDN** (something like `xxxxx.fzyy.alb.azure.com`) — that is the real, internet-facing address your app lives behind. Everything else in this section is about steering traffic from that address to the right pods.

#### List the routes attached to the gateway

A `Gateway` on its own serves nothing — traffic only flows when an `HTTPRoute` attaches to it. This shows which routes exist and whether they actually bound to the gateway.

```bash
source ./env.sh
# All routes, all namespaces, with the hostnames they answer for
kubectl get httproute -A
kubectl get httproute demo-route -n demo -o wide

# Did it attach to the gateway and get programmed?
kubectl -n demo get httproute demo-route \
  -o jsonpath='{range .status.parents[*]}parent={.parentRef.name} accepted={.conditions[?(@.type=="Accepted")].status} programmed={.conditions[?(@.type=="Programmed")].status}{"\n"}{end}'

# Full detail, including any binding errors
kubectl describe httproute demo-route -n demo
```

How it works: each route names a `parentRef` (the gateway it wants to join). The `Accepted` condition means the gateway allowed the attachment; `Programmed=True` means AGC pushed the rule live. If a route serves no traffic, this is the first place to look — usually `Accepted=False` (the gateway's `allowedRoutes` rejected it) or a bad `backendRef`.

#### Reach your app behind the gateway

This ties it all together: how a request travels from the public address to your pods, and how to test it before you own any DNS.

The request path is a chain — follow it top to bottom:

```
client ──▶ AGC frontend FQDN (.status.addresses)
        ──▶ Gateway listener (HTTPS :443, serves the demo-tls cert)
        ──▶ HTTPRoute match (hostname app.contoso.com + path /)
        ──▶ backendRef Service demo-svc:80
        ──▶ Endpoints (the demo pods)
```

```bash
source ./env.sh
FQDN=$(kubectl get gateway gw-platform -n demo -o jsonpath='{.status.addresses[0].value}')
echo "Public entry point : https://$FQDN"

# What hostname must the request carry to match the route?
kubectl -n demo get httproute demo-route -o jsonpath='{.spec.hostnames[0]}{"\n"}'

# What backs the route, and is anything actually running behind it?
kubectl -n demo get svc demo-svc -o wide
kubectl -n demo get endpoints demo-svc

# Reach it. -k trusts the self-signed cert; -H "Host: ..." stands in for DNS.
curl -ksS -o /dev/null -w "HTTP %{http_code}\n" \
  -H "Host: app.contoso.com" "https://$FQDN/"
```

How it works: the route only matches when the request's `Host` equals `app.contoso.com`, so you send that as a header (`-H "Host: ..."`) even though you are dialing the raw FQDN. A `HTTP 200` proves the whole chain works. If `kubectl get endpoints demo-svc` is empty, the route is fine but no pods back it — deploy the demo app (Section 8) first.

#### Point real DNS at the gateway

In production you do not curl with a `Host` header — you give users a real name. You do that by pointing your hostname at the gateway's FQDN with a CNAME.

```bash
source ./env.sh
FQDN=$(kubectl get gateway gw-platform -n demo -o jsonpath='{.status.addresses[0].value}')

# If you manage the DNS zone in Azure DNS:
az network dns record-set cname set-record \
  -g <your-dns-rg> -z contoso.com -n app -c "$FQDN" -o none

# Now the app resolves on its own name — no Host header, and with a real
# (non-self-signed) cert you can drop -k too:
curl -sS -o /dev/null -w "HTTP %{http_code}\n" "https://app.contoso.com/"
```

How it works: a `CNAME` from `app.contoso.com` to the AGC FQDN lets public DNS resolve your hostname to the gateway. Because the `Host` now genuinely *is* `app.contoso.com`, the same `HTTPRoute` matches with no header trickery. Pair this with a CA-issued certificate (or `cert-manager`) instead of the validation-only self-signed one.

#### Add path-based routing

One hostname can fan out to several services by URL path — the classic "web app plus API" split.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: demo-api-route
  namespace: demo
spec:
  parentRefs:
  - name: gw-platform
  hostnames:
  - "app.contoso.com"
  rules:
  - matches:
    - path: { type: PathPrefix, value: /api }
    backendRefs:
    - name: demo-api-svc
      port: 80
```

Requests under `/api` go to `demo-api-svc`; the existing `/` route keeps serving the web app. Verify it the same way as before: `curl -ksS -H "Host: app.contoso.com" "https://$FQDN/api"`.

#### Add another hostname

A shared gateway can serve many hostnames — add a route with a different `hostnames` value and it is live on the same public address.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: demo-alt-host
  namespace: demo
spec:
  parentRefs:
  - name: gw-platform
  hostnames:
  - "demo.contoso.com"
  rules:
  - backendRefs:
    - name: demo-svc
      port: 80
```

Both `app.contoso.com` and `demo.contoso.com` now resolve through the one gateway; each just needs its own DNS record pointing at the same FQDN.

#### Troubleshoot route programming

When a route will not go live, these two commands explain almost every case.

```bash
source ./env.sh
kubectl -n demo describe httproute demo-route
kubectl -n azure-alb-system logs deploy/alb-controller --tail=100
```

Look for `Accepted=False` (the gateway's `allowedRoutes` rejected the route), an invalid `backendRef` (wrong Service name or port), missing node-resource-group roles on the ALB identity, or a subnet-delegation problem. The controller logs name the exact resource that failed.

## 8. Deploy the demo app with Kustomize

**What & why**

Kustomize is a Kubernetes configuration tool for applying a directory of YAML and layering environment-specific changes without copying every manifest. The demo app validates Deployment, Service, Workload Identity, Key Vault CSI, and HTTPRoute behavior. The validated app listens on port 80, so probes, Service, route, and tests all use port 80.

### Steps

1. Create the namespace and Workload Identity ServiceAccount.

```bash
export DEMO_CLIENT=$(az identity show -g "$RG" -n demo-identity --query clientId -o tsv)
envsubst '$DEMO_CLIENT' < apps/demo/namespace-sa.yaml.tmpl | sed 's/\r$//' | kubectl apply -f -
```

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: demo-sa
  namespace: demo
  annotations:
    azure.workload.identity/client-id: "${DEMO_CLIENT}"
  labels:
    azure.workload.identity/use: "true"
```

How it works: the ServiceAccount annotation points to a managed identity client ID from your environment. The label opts the pod into Workload Identity.

2. Apply the SecretProviderClass.

```bash
export KV_NAME="$KV"
export TENANT_ID=$(az account show --query tenantId -o tsv)
envsubst '$DEMO_CLIENT $KV_NAME $TENANT_ID' < apps/demo/secretproviderclass.yaml.tmpl | sed 's/\r$//' | kubectl apply -f -
```

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: demo-kv
  namespace: demo
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "false"
    clientID: "${DEMO_CLIENT}"
    keyvaultName: "${KV_NAME}"
    tenantId: "${TENANT_ID}"
    objects: |
      array:
        - |
          objectName: demo-secret
          objectType: secret
```

How it works: the Secrets Store CSI Driver mounts Key Vault content as files. The tutorial uses variables and never stores tenant IDs, client IDs, or secrets in Git.

3. Deploy the app with Kustomize.

```bash
kubectl apply -k apps/demo
kubectl -n demo rollout status deploy/demo --timeout=180s
kubectl -n demo get deploy,pod,svc,httproute
```

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: demo
resources:
- deployment.yaml
- service.yaml
- httproute.yaml
```

How it works: `kubectl apply -k` renders the Kustomize directory then applies it. The Service maps port 80 to targetPort 80.

4. Validate the mount and route without printing secret values.

```bash
POD=$(kubectl -n demo get pod -l app=demo -o jsonpath='{.items[0].metadata.name}')
kubectl -n demo exec "$POD" -- ls /mnt/secrets
kubectl -n demo get httproute demo-route -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}{"\n"}'
```

How it works: listing the mount path confirms CSI mounted files without exposing values. `Accepted=True` means the route attached to the Gateway.

### Hands-on examples

#### See what Kustomize will apply

Before changing anything, render the manifests Kustomize builds from the base plus overlays. Nothing is applied — you just *see* the result.

```bash
source ./env.sh
# Render the final YAML Kustomize produces for the demo app
kubectl kustomize apps/demo | head -40

# Preview the difference between what is live and what the overlay wants
kubectl diff -k apps/demo || true
```

`kubectl kustomize` prints the combined result; `kubectl diff -k` shows exactly what an apply would change. This is the safest way to understand an overlay before you touch the cluster.
#### Create a dev overlay

```bash
mkdir -p apps/demo/overlays/dev
cat > apps/demo/overlays/dev/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../../
namePrefix: dev-
patches:
- target:
    kind: Deployment
    name: demo
  patch: |-
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: demo
    spec:
      replicas: 2
EOF
kubectl kustomize apps/demo/overlays/dev
```

This renders a dev variant without changing the base files.

#### Override an image tag

```bash
cp -r apps/demo apps/demo-work
cd apps/demo-work
kustomize edit set image mcr.microsoft.com/azuredocs/aks-helloworld:v1=${ACR}.azurecr.io/demo:<image-tag>
kubectl kustomize .
cd -
```

Use immutable tags, such as a Git SHA, for promotion.

#### Inject common labels

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: demo
commonLabels:
  app.kubernetes.io/part-of: aks-platform-tutorial
  team: platform
resources:
- deployment.yaml
- service.yaml
- httproute.yaml
```

Common labels help policy, ownership, and troubleshooting.

#### Inspect the live pod

```bash
kubectl -n demo get deploy demo -o yaml
kubectl -n demo describe pod -l app=demo
```

Check for `serviceAccountName: demo-sa`, probes on port 80, and the `kv` CSI volume.

## 9. Network Policies / Cilium

**What & why**

A Kubernetes NetworkPolicy is a pod-level firewall rule. With Azure CNI powered by Cilium, AKS enforces those rules with eBPF in the data plane. The validated pattern is default-deny ingress first, then allow only AGC traffic to the demo app on port 80.

### Steps

1. Confirm the app is healthy.

```bash
kubectl -n demo rollout status deploy/demo --timeout=120s
kubectl -n demo get svc demo-svc
```

How it works: policy tests are meaningful only when the target app and Service already work. The demo Service listens on port 80, not 8080.

2. Apply default-deny ingress.

```bash
sed 's/\r$//' platform/netpol/default-deny-ingress.yaml | kubectl apply -f -
```

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: demo
spec:
  podSelector: {}
  policyTypes:
  - Ingress
```

How it works: `podSelector: {}` selects every pod in the namespace. With no `ingress` list, inbound connections are denied; egress stays allowed.

3. Allow AGC to reach the app on port 80.

```bash
sed 's/\r$//' platform/netpol/allow-from-agc.yaml | kubectl apply -f -
kubectl -n demo get netpol
```

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-agc
  namespace: demo
spec:
  podSelector:
    matchLabels:
      app: demo
  policyTypes:
  - Ingress
  ingress:
  - from:
    - ipBlock:
        cidr: 10.0.4.0/24
    ports:
    - protocol: TCP
      port: 80
```

How it works: only traffic from the delegated AGC subnet can reach pods labeled `app: demo`, and only on TCP 80. The port is the validated correction from the errata.

4. Prove a normal pod is blocked.

```bash
kubectl -n demo delete pod tester --ignore-not-found --force --grace-period=0 2>/dev/null || true
kubectl -n demo run tester --image=nicolaka/netshoot --restart=Never --command -- sleep 60
kubectl -n demo wait --for=condition=Ready pod/tester --timeout=90s
set +e
CODE=$(kubectl -n demo exec tester -- curl -m 5 -s -o /dev/null -w '%{http_code}' http://demo-svc.demo:80)
RC=$?
set -e
echo "tester -> demo-svc:80  http_code=${CODE} curl_rc=${RC}"
```

How it works: timeout or `000` is expected. This tests policy behavior on the correct app port.

5. Prove AGC is still allowed.

```bash
VIP=$(kubectl get gateway gw-platform -n demo -o jsonpath='{.status.addresses[0].value}')
curl -ksS -H "Host: ${APP_HOST:-app.contoso.com}" "https://$VIP/"
```

How it works: the source path is the AGC subnet, so it matches `allow-from-agc`.

### Hands-on examples

#### Allow a trusted namespace

```bash
kubectl create namespace trusted --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace trusted access=demo --overwrite
```

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-trusted-namespace
  namespace: demo
spec:
  podSelector:
    matchLabels:
      app: demo
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          access: demo
    ports:
    - protocol: TCP
      port: 80
```

This is useful for service-to-service traffic inside the cluster.

#### Compare blocked and allowed curl

```bash
kubectl -n demo exec tester -- curl -m 5 -v http://demo-svc.demo:80 || true
kubectl -n trusted run trusted-curl --image=curlimages/curl --restart=Never --command -- sleep 300
kubectl -n trusted wait --for=condition=Ready pod/trusted-curl --timeout=90s
kubectl -n trusted exec trusted-curl -- curl -m 5 -sS http://demo-svc.demo:80
```

The first request is blocked by default-deny; the second works only after the namespace allow policy exists.

#### Remember DNS if you later deny egress

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
  namespace: demo
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - { protocol: UDP, port: 53 }
    - { protocol: TCP, port: 53 }
```

This tutorial denies only ingress. If you add egress deny, allow DNS or service names will stop resolving.

#### Inspect policy objects

```bash
kubectl -n demo describe netpol default-deny-ingress
kubectl -n demo describe netpol allow-from-agc
kubectl -n kube-system get pods -l k8s-app=cilium
```

Start with standard Kubernetes inspection before using deeper Cilium tools.

## 10. Kyverno policy governance

**What & why**

Kyverno is an admission controller: it reviews Kubernetes objects when they are created or updated. An admission webhook is the API server callback that performs that review. Start policies in `Audit`, never cluster-wide `Enforce`, because a bad enforcing policy can block system namespaces and wedge the cluster.

### Steps

1. Install Kyverno pinned to the system pool.

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null 2>&1 || true
helm repo update kyverno >/dev/null
helm upgrade --install kyverno kyverno/kyverno -n kyverno --create-namespace \
  -f platform/kyverno/pin-values.yaml --wait --timeout 5m
kubectl -n kyverno get pods
```

```yaml
_pin: &pin
  nodeSelector:
    kubernetes.azure.com/mode: system
  tolerations:
  - key: CriticalAddonsOnly
    operator: Equal
    value: "true"
    effect: NoSchedule
admissionController:
  <<: *pin
backgroundController:
  <<: *pin
cleanupController:
  <<: *pin
reportsController:
  <<: *pin
```

How it works: Kyverno is pinned at Helm-install time using `platform/kyverno/pin-values.yaml`. This avoids a self-webhook bootstrap deadlock: Kyverno's webhook uses `failurePolicy=Fail`, so if its pods are Pending, cluster-wide mutating calls can fail.

2. Apply the validated Audit guardrails.

```bash
envsubst '$ACR' < platform/kyverno/policies.yaml.tmpl | sed 's/\r$//' | kubectl apply -f -
for p in require-labels disallow-privileged restrict-registry require-limits; do
  kubectl wait --for=condition=Ready clusterpolicy/$p --timeout=60s 2>/dev/null || true
done
kubectl get clusterpolicy
```

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-labels
spec:
  validationFailureAction: Audit
  background: true
  rules:
  - name: check-labels
    match:
      any:
      - resources:
          kinds: [Deployment]
    validate:
      message: "labels app.kubernetes.io/name and team are required"
      pattern:
        metadata:
          labels:
            app.kubernetes.io/name: "?*"
            team: "?*"
```

How it works: `Audit` records violations but does not block deployments. The indentation keeps `validate` under the rule, which fixes the invalid deck shape.

3. Demonstrate Enforce safely in one namespace.

```bash
kubectl create namespace kyverno-test --dry-run=client -o yaml | kubectl apply -f -
envsubst '$ACR' < platform/kyverno/enforce-demo.yaml.tmpl | sed 's/\r$//' | kubectl apply -f -
kubectl wait --for=condition=Ready clusterpolicy/kyverno-test-enforce-registry --timeout=60s 2>/dev/null || true
```

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: kyverno-test-enforce-registry
spec:
  validationFailureAction: Enforce
  background: false
  rules:
  - name: registry-only-acr
    match:
      any:
      - resources:
          kinds: [Pod]
          namespaces: [kyverno-test]
    validate:
      message: "images must come from ${ACR}.azurecr.io"
      pattern:
        spec:
          containers:
          - image: "${ACR}.azurecr.io/*"
```

How it works: this policy hard-blocks only pods in `kyverno-test`. It does not affect kube-system, Kyverno, Argo CD, or the ALB controller.

4. Test the block, then clean up.

```bash
set +e
OUT=$(kubectl -n kyverno-test run bad --image=docker.io/nginx --restart=Never 2>&1)
RC=$?
set -e
echo "$OUT"
test "$RC" -ne 0 && echo "Blocked as expected"
kubectl delete clusterpolicy kyverno-test-enforce-registry --ignore-not-found
kubectl delete namespace kyverno-test --ignore-not-found --wait=false
```

How it works: the bad pod is denied before creation. Cleanup leaves the persistent Audit policies in place.

5. View policy reports.

```bash
kubectl get clusterpolicy
kubectl get policyreport -A
kubectl get clusterpolicyreport 2>/dev/null || true
```

How it works: PolicyReports show which resources pass or fail. Review them before moving any policy to `Enforce`.

### Hands-on examples

#### Require labels in Audit

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-basic-app-labels
spec:
  validationFailureAction: Audit
  background: true
  rules:
  - name: require-team-and-name
    match:
      any:
      - resources:
          kinds: [Deployment]
    validate:
      message: "Deployments need app.kubernetes.io/name and team labels"
      pattern:
        metadata:
          labels:
            app.kubernetes.io/name: "?*"
            team: "?*"
```

Audit mode teaches teams the rule before it blocks them.

#### Disallow `latest` image tags

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-latest-tag
spec:
  validationFailureAction: Audit
  background: true
  rules:
  - name: require-fixed-tag
    match:
      any:
      - resources:
          kinds: [Pod]
    validate:
      message: "Use an immutable image tag, not :latest"
      pattern:
        spec:
          containers:
          - image: "!*:latest"
```

Immutable tags make rollbacks and audits reliable.

#### Read reports for one namespace

```bash
kubectl get policyreport -n demo
kubectl describe policyreport -n demo
```

Reports show the resource, policy, rule, and result.

#### Enforce only in an app namespace

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: demo-enforce-labels
spec:
  validationFailureAction: Enforce
  background: false
  rules:
  - name: require-demo-labels
    match:
      any:
      - resources:
          kinds: [Deployment]
          namespaces: [demo]
    validate:
      message: "demo deployments require team and app name labels"
      pattern:
        metadata:
          labels:
            app.kubernetes.io/name: "?*"
            team: "?*"
```

Enforce only after Audit is clean, and scope to app namespaces.

## 11. Argo CD GitOps

**What & why**

GitOps means Git is the source of truth and a controller continuously reconciles the cluster to match Git. Argo CD is that controller here: it watches a repository and applies Kubernetes manifests. The validated install uses server-side apply to avoid the `metadata.annotations: Too long` error on Argo CD CRDs.

### Steps

1. Install Argo CD with server-side apply.

```bash
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

How it works: `--server-side` lets the API server manage fields instead of writing a very large client-side annotation. This is the validated errata fix.

2. Pin Argo CD to the system pool.

```bash
source ./platform/lib/pin.sh
pin_to_system argocd \
  deploy/argocd-server deploy/argocd-repo-server deploy/argocd-redis \
  deploy/argocd-dex-server deploy/argocd-applicationset-controller \
  deploy/argocd-notifications-controller statefulset/argocd-application-controller
```

How it works: Argo CD is platform control plane, so it uses the same system-pool pinning pattern as ALB: `nodeSelector: kubernetes.azure.com/mode=system` plus the `CriticalAddonsOnly` toleration.

3. Wait for core pods and open the UI locally.

```bash
for d in argocd-repo-server argocd-server argocd-applicationset-controller; do
  kubectl -n argocd rollout status deploy/$d --timeout=240s || true
done
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=240s || true
kubectl -n argocd get pods
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

How it works: port-forwarding exposes the UI only on your machine at `https://localhost:8080`. Retrieve any initial password locally and do not paste it into docs, tickets, or chat.

4. Apply the validated guestbook Application.

```bash
sed 's/\r$//' platform/argocd/guestbook-app.yaml | kubectl apply -f -
```

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps
    path: guestbook
    targetRevision: HEAD
  destination:
    server: https://kubernetes.default.svc
    namespace: guestbook
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

How it works: an Argo CD `Application` points to Git, chooses a path, and declares the destination cluster and namespace. The public guestbook app proves the loop without private repo credentials.

5. Wait for Synced and Healthy.

```bash
for i in $(seq 1 30); do
  SYNC=$(kubectl -n argocd get application guestbook -o jsonpath='{.status.sync.status}' 2>/dev/null || true)
  HEALTH=$(kubectl -n argocd get application guestbook -o jsonpath='{.status.health.status}' 2>/dev/null || true)
  echo "sync=$SYNC health=$HEALTH"
  [ "$SYNC" = "Synced" ] && [ "$HEALTH" = "Healthy" ] && break
  sleep 10
done
kubectl -n argocd get application guestbook
```

How it works: `Synced` means the live cluster matches Git. `Healthy` means the deployed Kubernetes resources are running correctly.

6. Confirm the reconciled workload is actually running.

```bash
kubectl -n guestbook get pods --no-headers
kubectl -n guestbook get deploy,svc
```

How it works: Argo CD reporting `Synced`/`Healthy` is the control-plane view; listing pods in the `guestbook` namespace is the proof that the workload Argo CD pulled from Git is live on your cluster. This closes the GitOps loop end to end.

### Hands-on examples

#### Create an Application for your repo

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: demo
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<your-github-org>/<your-repo>
    path: apps/demo
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: demo
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

Replace placeholders with a real `<your-github-org>/<your-repo>` value before applying. Do not leave the deck's `<org>` placeholder in manifests.

#### Bootstrap app-of-apps

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: platform-root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<your-github-org>/<your-repo>
    path: platform
    targetRevision: main
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

App-of-apps means one root Application creates child Applications. It is a clean way to bootstrap ingress, policy, observability, and apps from Git.

#### View sync status from kubectl

```bash
kubectl -n argocd get applications
kubectl -n argocd get application guestbook -o jsonpath='{.status.sync.status}{" / "}{.status.health.status}{"\n"}'
kubectl -n argocd describe application guestbook
```

These commands are useful when the Argo CD CLI is not installed.

#### Pause auto-sync temporarily

```bash
kubectl -n argocd patch application guestbook --type=merge -p '{"spec":{"syncPolicy":null}}'
kubectl -n argocd get application guestbook
```

Pausing is useful during a live incident or training. Re-apply the manifest from Git to restore auto-sync.

## 12. Managed Prometheus + Grafana

**What & why**

Managed Prometheus stores metrics in an Azure Monitor workspace, and Azure Managed Grafana visualizes them. PromQL is the Prometheus query language; for example, `count(up)` asks how many scrape targets are up. The validated caveat is important: confirm the container's actual metrics port. The demo app uses app port 80 and does not expose Prometheus `/metrics`, so the PodMonitor is the correct shape for a real metrics-enabled app.

### Steps

1. Register providers and create the Azure Monitor workspace.

```bash
az provider register --namespace Microsoft.Monitor --wait 2>/dev/null || true
az provider register --namespace Microsoft.Dashboard --wait 2>/dev/null || true
az monitor account create -g "$RG" -n "$AMW" -l "$LOCATION" -o none
AMW_ID=$(az monitor account show -g "$RG" -n "$AMW" --query id -o tsv)
```

How it works: the Azure Monitor workspace is the managed Prometheus storage backend. Keep the resource ID in variables, not documentation.

2. Create Azure Managed Grafana.

```bash
az grafana create -g "$RG" -n "$GRAFANA" -l "$LOCATION" -o none
GRAF_ID=$(az grafana show -g "$RG" -n "$GRAFANA" --query id -o tsv)
GRAF_EP=$(az grafana show -g "$RG" -n "$GRAFANA" --query 'properties.endpoint' -o tsv)
echo "Grafana endpoint: $GRAF_EP"
```

How it works: Grafana provides dashboards and Explore. Access is protected by Microsoft Entra ID.

3. Enable managed Prometheus on AKS and link Grafana.

```bash
az aks update -g "$RG" -n "$AKS" \
  --enable-azure-monitor-metrics \
  --azure-monitor-workspace-resource-id "$AMW_ID" \
  --grafana-resource-id "$GRAF_ID" -o none
```

How it works: AKS installs `ama-metrics` and connects it to the workspace. Reconciliation can take several minutes.

4. Validate the add-on and integrations.

```bash
kubectl -n kube-system rollout status deploy/ama-metrics --timeout=180s || true
kubectl -n kube-system get pods -o wide | grep ama-metrics
az aks show -g "$RG" -n "$AKS" \
  --query '{metricsEnabled:azureMonitorProfile.metrics.enabled, profile:azureMonitorProfile.metrics.metricsProfile}' -o json
az grafana show -g "$RG" -n "$GRAFANA" \
  --query 'properties.grafanaIntegrations.azureMonitorWorkspaceIntegrations[].azureMonitorWorkspaceResourceId' -o tsv
```

How it works: the pod check confirms the scraper is running. The Azure queries confirm AKS and Grafana are linked to the workspace.

5. Confirm the app port before scraping.

```bash
kubectl -n demo get deploy demo -o jsonpath='{range .spec.template.spec.containers[*].ports[*]}{.name}{"="}{.containerPort}{"\n"}{end}'
kubectl -n demo get pod -l app=demo -o jsonpath='{.items[0].spec.containers[0].image}{"\n"}'
```

How it works: do not assume port 8080. The validated app uses the named `http` port on 80; only a real metrics app should serve `/metrics` there.

6. Apply the PodMonitor shape.

```bash
sed 's/\r$//' platform/observability/podmonitor.yaml | kubectl apply -f -
```

```yaml
apiVersion: azmonitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: demo-podmonitor
  namespace: demo
spec:
  selector:
    matchLabels:
      app: demo
  podMetricsEndpoints:
  - port: http
    path: /metrics
    interval: 30s
```

How it works: `port: http` references the container port name. Change it to your real metrics port name if your app exposes metrics separately.

7. Confirm Grafana is wired to Managed Prometheus.

```bash
source ./env.sh
az grafana data-source list -n "$GRAFANA" \
  --query "[].{name:name, type:type}" -o table
az grafana dashboard list -n "$GRAFANA" \
  --query "length(@)" -o tsv
```

How it works: the observability wiring links your Managed Grafana instance to the Azure Monitor workspace as a data source. Listing data sources confirms the Prometheus/Azure Monitor connection exists; the dashboard count confirms the curated Kubernetes dashboards were provisioned.

### Hands-on examples

#### Open Grafana and find a dashboard

The fastest way to see metrics is the Grafana UI — no PromQL required to start.

```bash
source ./env.sh
# Print the Grafana URL, then open it in a browser and sign in with your Azure account
az grafana show -g "$RG" -n "$GRAFANA" --query 'properties.endpoint' -o tsv

# See which dashboards are already provisioned
az grafana dashboard list -n "$GRAFANA" -o table 2>/dev/null | head -20
```

In the UI, open **Dashboards -> Kubernetes / Compute Resources / Namespace (Workloads)** and pick the `demo` namespace. You will see CPU and memory graphs for the app with no query writing at all — the PromQL examples below are for when you want to build your own.
#### Run a basic PromQL query

```promql
count(up)
```

Run this in Grafana Explore against the managed Prometheus data source. A value greater than zero proves Prometheus is ingesting built-in targets.

#### Query demo targets

```promql
up{namespace="demo"}
```

This returns data only when a real metrics endpoint in `demo` is scraped. The default demo image does not expose `/metrics`.

#### Use a dedicated metrics port

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: metrics-example
  namespace: demo
  labels:
    app: metrics-example
spec:
  containers:
  - name: app
    image: <your-metrics-image>
    ports:
    - name: http
      containerPort: 80
    - name: metrics
      containerPort: 9090
```

If you use this shape, set the PodMonitor endpoint to `port: metrics`.

#### Create a simple alert rule

```yaml
apiVersion: azmonitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: demo-alerts
  namespace: demo
spec:
  groups:
  - name: demo.rules
    rules:
    - alert: DemoTargetDown
      expr: up{namespace="demo"} == 0
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "No demo scrape targets are up"
        description: "Managed Prometheus has not seen an up demo target for 5 minutes."
```

Treat this as a starting shape. Wire notification routing and severity labels to your production alerting standard.

---

## 13. KEDA event-driven autoscaling

**What & why**  
KEDA (Kubernetes Event-driven Autoscaling) scales Kubernetes workloads from external signals such as schedules, queues, Prometheus queries, or resource usage. In this validated AKS platform, KEDA is enabled as an **AKS-managed add-on** that runs in `kube-system`, and its three deployments are pinned to the system node pool so application nodes stay reserved for workloads. A **ScaledObject** is the KEDA custom resource that tells KEDA which Deployment to scale, how low/high it may go, how often to check signals, and which trigger to use.

### Steps

1. Enable the AKS-managed KEDA add-on and pin it to the system pool.

```bash
source ./env.sh

az aks update -g "$RG" -n "$AKS" --enable-keda -o none

source platform/lib/pin.sh
pin_to_system kube-system \
  deploy/keda-operator \
  deploy/keda-operator-metrics-apiserver \
  deploy/keda-admission-webhooks
```

How it works: `--enable-keda` installs the managed KEDA control plane. The pinning helper applies `nodeSelector: kubernetes.azure.com/mode=system` plus the system-pool toleration so KEDA runs with the rest of the platform add-ons.

2. Verify the operator pods and KEDA CRDs.

```bash
source ./env.sh

kubectl get pods -n kube-system | grep -i keda
kubectl api-resources | grep -i keda.sh
```

How it works: KEDA installs custom resource definitions such as `ScaledObject` and `TriggerAuthentication`. If those resources exist, Kubernetes understands KEDA manifests.

3. Apply the validated cron ScaledObject demo.

```bash
source ./env.sh

kubectl apply -f platform/keda/demo-scaledobject.yaml
kubectl get scaledobject,hpa -n demo
```

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: demo-scaler
  namespace: demo
spec:
  scaleTargetRef:
    name: demo
  minReplicaCount: 1
  maxReplicaCount: 4
  cooldownPeriod: 60
  pollingInterval: 15
  triggers:
    - type: cron
      metadata:
        timezone: Etc/UTC
        start: "0,10,20,30,40,50 * * * *"
        end: "5,15,25,35,45,55 * * * *"
        desiredReplicas: "3"
```

How it works: KEDA creates and owns an HPA named `keda-hpa-demo-scaler`. `minReplicaCount` and `maxReplicaCount` set the safe scaling range, `pollingInterval` controls how often KEDA checks triggers, and `cooldownPeriod` waits before scaling back down.

4. Confirm KEDA created the managed HPA and is controlling replicas.

```bash
source ./env.sh

kubectl describe scaledobject -n demo demo-scaler
kubectl get hpa -n demo keda-hpa-demo-scaler
kubectl get deploy -n demo demo
```

How it works: KEDA is not replacing Kubernetes HPA; it creates an HPA for you and feeds it external metrics. The Deployment replica count changes when the trigger is active.

### Hands-on examples

#### See the scaler and watch it scale

Start here: look at the ScaledObject, the HPA KEDA created from it, then force a scale event so you can watch replicas change live.

```bash
source ./env.sh
# The scaling rule you defined, and the HPA KEDA generated and owns
kubectl get scaledobject,hpa -n demo
kubectl describe scaledobject demo-scaler -n demo | sed -n '1,30p'
```

Force a scale event now instead of waiting for the cron window, then watch it:

```bash
# Set the cron window to start this minute (scales within ~1 min)
S=$(date -u +%M | sed 's/^0//'); [ -z "$S" ] && S=0
E=$(( (S + 8) % 60 ))
kubectl -n demo patch scaledobject demo-scaler --type=merge \
  -p "{\"spec\":{\"triggers\":[{\"type\":\"cron\",\"metadata\":{\"timezone\":\"UTC\",\"start\":\"$S * * * *\",\"end\":\"$E * * * *\",\"desiredReplicas\":\"3\"}}]}}"

# Watch REPLICAS climb 1 -> 3 (Ctrl+C when it reaches 3)
kubectl -n demo get hpa keda-hpa-demo-scaler -w
```

Reset to the standard 10-minute schedule afterwards:

```bash
kubectl -n demo patch scaledobject demo-scaler --type=merge \
  -p '{"spec":{"triggers":[{"type":"cron","metadata":{"timezone":"UTC","start":"0,10,20,30,40,50 * * * *","end":"5,15,25,35,45,55 * * * *","desiredReplicas":"3"}}]}}'
```

The `HPA` column moving from `1` to `3` proves the trigger fired and KEDA scaled the Deployment. This inspect-then-watch pattern works for every trigger type below.
#### Cron ScaledObject

Use a cron trigger when you know traffic will rise at a predictable time, such as office hours or batch windows.

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: office-hours-demo
  namespace: demo
spec:
  scaleTargetRef:
    name: demo
  minReplicaCount: 1
  maxReplicaCount: 5
  cooldownPeriod: 300
  pollingInterval: 30
  triggers:
    - type: cron
      metadata:
        timezone: Europe/Amsterdam
        start: "0 8 * * 1-5"
        end: "0 18 * * 1-5"
        desiredReplicas: "3"
```

This keeps the app at three replicas during weekday office hours, then lets it return to the normal minimum after the cooldown.

#### CPU and memory ScaledObject

Use CPU or memory triggers for simple workload-based scaling. These triggers need at least one running pod, so keep `minReplicaCount` at `1` or higher.

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: resource-demo
  namespace: demo
spec:
  scaleTargetRef:
    name: demo
  minReplicaCount: 1
  maxReplicaCount: 6
  cooldownPeriod: 120
  pollingInterval: 30
  triggers:
    - type: cpu
      metricType: Utilization
      metadata:
        value: "70"
    - type: memory
      metricType: Utilization
      metadata:
        value: "75"
```

KEDA creates an HPA that scales out when average CPU exceeds 70% or average memory exceeds 75% of the requested resources.

#### Managed Prometheus trigger with workload identity

Azure Monitor managed Prometheus requires Entra authentication. A bare KEDA `prometheus` trigger returns `401`, so use a `TriggerAuthentication`, Azure Workload Identity, and the managed Prometheus **query endpoint**.

```bash
source ./env.sh

AMW_ID=$(az monitor account show -g "$RG" -n "$AMW" --query id -o tsv)
PROM_QUERY_ENDPOINT=$(az monitor account show -g "$RG" -n "$AMW" --query 'metrics.prometheusQueryEndpoint' -o tsv)
OIDC_ISSUER=$(az aks show -g "$RG" -n "$AKS" --query 'oidcIssuerProfile.issuerUrl' -o tsv)

az identity create -g "$RG" -n keda-prometheus-reader -l "$LOCATION" -o none
KEDA_UAMI_CLIENT_ID=$(az identity show -g "$RG" -n keda-prometheus-reader --query clientId -o tsv)
KEDA_UAMI_PRINCIPAL_ID=$(az identity show -g "$RG" -n keda-prometheus-reader --query principalId -o tsv)

az role assignment create \
  --assignee "$KEDA_UAMI_PRINCIPAL_ID" \
  --role "Monitoring Data Reader" \
  --scope "$AMW_ID" -o none

az identity federated-credential create \
  -g "$RG" \
  --identity-name keda-prometheus-reader \
  --name keda-operator \
  --issuer "$OIDC_ISSUER" \
  --subject "system:serviceaccount:kube-system:keda-operator" \
  --audience "api://AzureADTokenExchange" -o none

kubectl annotate serviceaccount -n kube-system keda-operator \
  azure.workload.identity/client-id="$KEDA_UAMI_CLIENT_ID" --overwrite
kubectl patch deploy -n kube-system keda-operator \
  --type merge \
  -p '{"spec":{"template":{"metadata":{"labels":{"azure.workload.identity/use":"true"}}}}}'
```

```yaml
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: managed-prometheus-auth
  namespace: demo
spec:
  podIdentity:
    provider: azure-workload
    identityId: <AZURE_CLIENT_ID_OF_KEDA_PROMETHEUS_READER>
---
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: prometheus-demo
  namespace: demo
spec:
  scaleTargetRef:
    name: demo
  minReplicaCount: 1
  maxReplicaCount: 5
  pollingInterval: 30
  cooldownPeriod: 120
  triggers:
    - type: prometheus
      authenticationRef:
        name: managed-prometheus-auth
      metadata:
        serverAddress: <MANAGED_PROMETHEUS_QUERY_ENDPOINT>
        metricName: demo_request_rate
        query: sum(rate(container_cpu_usage_seconds_total{namespace="demo"}[2m]))
        threshold: "0.5"
        authModes: "azure"
```

A `TriggerAuthentication` stores the authentication method for the trigger. Workload identity lets the KEDA operator exchange its Kubernetes service account token for an Entra token without a password or client secret.

#### Scaling to zero

Use scale-to-zero for event-driven workloads that can be cold when there is no demand. Do not use CPU or memory as the only trigger for scale-to-zero because those metrics require a running pod.

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: night-batch-zero
  namespace: demo
spec:
  scaleTargetRef:
    name: demo
  minReplicaCount: 0
  maxReplicaCount: 3
  cooldownPeriod: 60
  pollingInterval: 30
  triggers:
    - type: cron
      metadata:
        timezone: Etc/UTC
        start: "0 1 * * *"
        end: "30 1 * * *"
        desiredReplicas: "2"
```

Outside the active cron window, KEDA can reduce the Deployment to zero replicas. The app will not receive traffic until a trigger wakes it back up.

## 14. Advanced Container Networking Services and Hubble

**What & why**  
Advanced Container Networking Services (ACNS) adds observability and security capabilities for AKS clusters that use Cilium. Hubble is Cilium's flow-visibility tool; it uses eBPF, a safe Linux kernel technology for observing network events, to show which pods talk to each other and whether traffic is forwarded or dropped. This is useful when debugging network policies, DNS, or unexpected service-to-service calls.

### Steps

1. Enable ACNS observability on the AKS cluster.

```bash
source ./env.sh

az aks update -g "$RG" -n "$AKS" \
  --enable-acns \
  --disable-acns-security \
  -o none \
  || az aks update -g "$RG" -n "$AKS" --enable-acns -o none
```

How it works: `--enable-acns` enables the ACNS data plane. The validated script disables ACNS security first to keep the proof-of-concept minimal, then falls back to the full enable command if the CLI version does not accept that flag.

2. Verify the Hubble or Retina pods.

```bash
source ./env.sh

kubectl get pods -n kube-system | grep -Ei 'hubble|retina'
kubectl get svc -n kube-system hubble-relay
```

How it works: Hubble Relay exposes flow data from the Cilium agents. Some AKS versions may vary pod names, so search for both `hubble` and `retina`.

3. Forward Hubble Relay to your workstation.

```bash
source ./env.sh

kubectl port-forward -n kube-system svc/hubble-relay 4245:443
```

How it works: `kubectl port-forward` creates a local tunnel. In another terminal, the Hubble CLI can connect to `localhost:4245` and query recent flows.

4. Observe recent flows from the demo namespace.

```bash
source ./env.sh

hubble observe --server localhost:4245 --namespace demo --last 20
```

How it works: A flow is one observed network conversation. Hubble shows the source, destination, protocol, and verdict such as `FORWARDED` or `DROPPED`.

### Hands-on examples

#### Enable ACNS and confirm it is active

This repeats the safe validated enablement and checks the data plane.

```bash
source ./env.sh

az aks show -g "$RG" -n "$AKS" \
  --query 'networkProfile.advancedNetworking.enabled' -o tsv
kubectl get pods -n kube-system -o wide | grep -Ei 'hubble|retina|cilium'
```

If the query returns `true` and pods are running, ACNS observability is available.

#### Observe Hubble flows by namespace

Use namespace filtering to keep output readable for beginners.

```bash
source ./env.sh

kubectl port-forward -n kube-system svc/hubble-relay 4245:443
echo "In a second terminal, run:"
hubble observe --server localhost:4245 --namespace demo --last 50
```

This shows only traffic involving pods in the `demo` namespace, which is much easier than reading cluster-wide flow logs.

#### Filter flows by pod and verdict

A verdict filter helps you find denied traffic after applying network policies.

```bash
source ./env.sh

hubble observe \
  --server localhost:4245 \
  --namespace demo \
  --pod demo \
  --verdict DROPPED \
  --last 100
```

`--pod` narrows the view to one workload and `--verdict DROPPED` shows flows blocked by policy or routing decisions.

#### Open the Hubble UI

Use the UI when teaching or troubleshooting with a team.

```bash
source ./env.sh

kubectl port-forward -n kube-system svc/hubble-ui 12000:80
```

Open `http://localhost:12000` in a browser. If your AKS version does not expose `hubble-ui`, use the CLI examples above; Hubble Relay is the validated dependency.

## 15. Flux GitOps

**What & why**  
GitOps means the desired cluster state lives in Git, and a controller continuously reconciles the cluster to match the repository. Flux v2 is available on AKS through the Azure-managed `microsoft.flux` extension and can be configured with `az k8s-configuration flux create`. Important validated caveat: `az k8s-configuration flux create` does **not** accept `--target-namespace`; namespace placement must be declared in the manifests or in a Flux `Kustomization` custom resource.

### Steps

1. Install the Azure CLI extensions and register the provider.

```bash
source ./env.sh

az extension add --name k8s-configuration -y -o none || true
az extension add --name k8s-extension -y -o none || true
az provider register --namespace Microsoft.KubernetesConfiguration -o none || true
```

How it works: The `k8s-configuration` extension manages GitOps configurations, and AKS installs the `microsoft.flux` extension automatically when you create a Flux configuration.

2. Create the target namespace in the cluster.

```bash
source ./env.sh

kubectl create namespace demo --dry-run=client -o yaml | kubectl apply -f -
```

How it works: Because the Azure command cannot inject a target namespace, your manifests must include `metadata.namespace`, include a `Namespace` object, or use a Flux `Kustomization` CR with `targetNamespace`.

3. Create a Flux configuration that points at a Git repository.

```bash
source ./env.sh

FLUX_CFG=demo-gitops
GITOPS_REPO=https://github.com/<your-github-org>/<your-repo>.git
GITOPS_BRANCH=main

az k8s-configuration flux create \
  -g "$RG" \
  -c "$AKS" \
  --cluster-type managedClusters \
  -n "$FLUX_CFG" \
  --namespace flux-system \
  --scope cluster \
  --url "$GITOPS_REPO" \
  --branch "$GITOPS_BRANCH" \
  --kustomization name=demo path=./apps/demo prune=true \
  --interval 1m \
  -o none
```

How it works: `--namespace flux-system` is where the Flux controllers run; it is not the application target namespace. `prune=true` tells Flux to remove cluster objects that were deleted from Git.

4. Check controller and compliance status.

```bash
source ./env.sh

kubectl get pods -n flux-system
az k8s-configuration flux show \
  -g "$RG" \
  -c "$AKS" \
  --cluster-type managedClusters \
  -n demo-gitops \
  --query '{complianceState:complianceState, repository:repositoryRef.repositoryUrl}' \
  -o json
kubectl get kustomizations,gitrepositories -A
```

How it works: `complianceState=Compliant` means the Azure extension believes Flux reconciled the requested source and kustomization. The Kubernetes resources show the lower-level Flux status.

5. Confirm the reconciled workload landed in its target namespace.

```bash
kubectl get deploy,svc -n flux-demo
```

How it works: the Flux kustomization sets its target namespace to `flux-demo` inside the object spec (not via a `--target-namespace` flag). Listing deployments and services there proves Flux applied the manifests from Git — the same GitOps outcome as Argo CD, driven by the Azure Flux extension instead.

### Hands-on examples

#### Create a Flux configuration for your repo

Use this when your application manifests already live under `apps/demo` and include the namespace they should deploy to.

```bash
source ./env.sh

az k8s-configuration flux create \
  -g "$RG" -c "$AKS" --cluster-type managedClusters \
  -n demo-gitops \
  --namespace flux-system \
  --scope cluster \
  --url https://github.com/<your-github-org>/<your-repo>.git \
  --branch main \
  --kustomization name=demo path=./apps/demo prune=true sync_interval=1m \
  --interval 1m \
  -o none
```

Do not add `--target-namespace`; that flag is unsupported for this command.

#### Flux Kustomization CR with target namespace

A `Kustomization` CR is a Flux custom resource that tells Flux which path to reconcile and how to apply it.

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: demo-repo
  namespace: flux-system
spec:
  interval: 1m
  url: https://github.com/<your-github-org>/<your-repo>.git
  ref:
    branch: main
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: demo
  namespace: flux-system
spec:
  interval: 1m
  path: ./apps/demo
  prune: true
  targetNamespace: demo
  sourceRef:
    kind: GitRepository
    name: demo-repo
```

`targetNamespace: demo` is the correct place to target a namespace when using native Flux resources.

#### Check Flux status and troubleshoot

Use both Azure and Kubernetes views when something is not syncing.

```bash
source ./env.sh

az k8s-configuration flux list \
  -g "$RG" -c "$AKS" --cluster-type managedClusters -o table

az k8s-configuration flux show \
  -g "$RG" -c "$AKS" --cluster-type managedClusters \
  -n demo-gitops -o yaml

kubectl -n flux-system get gitrepositories,kustomizations
kubectl -n flux-system describe kustomization demo
```

The Azure command shows managed extension compliance. The `kubectl describe` output usually contains the fastest explanation for bad paths, missing namespaces, or authentication failures.

#### Flux vs Argo CD comparison note

Both tools implement GitOps, but they optimize for different workflows.

```yaml
Flux:
  style: Kubernetes-native controllers and CRDs
  strength: Lightweight reconciliation, Azure Policy integration, fleet-style enforcement
ArgoCD:
  style: Application-centric controller with rich UI
  strength: Visual app health, sync waves, manual promotion workflows
```

For this platform, Flux demonstrates the Azure-managed GitOps extension. Argo CD remains valid when teams prefer an application dashboard and manual sync controls.

## 16. Container Insights and logs

**What & why**  
Managed Prometheus handles metrics, while Container Insights sends logs and inventory to Log Analytics. Logs answer questions like "which pod wrote this error?", "which container restarted?", and "what happened before the rollout failed?" The AKS monitoring add-on deploys the `ama-logs` DaemonSet so every node can forward container and Kubernetes inventory data.

### Steps

1. Resolve the Log Analytics workspace IDs.

```bash
source ./env.sh

LAW_ID=$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query id -o tsv)
LAW_GUID=$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query customerId -o tsv)
```

How it works: Azure resource IDs are used for configuration. The workspace GUID is used by the query API.

2. Enable Container Insights.

```bash
source ./env.sh

LAW_ID=$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query id -o tsv)

az aks enable-addons \
  -g "$RG" \
  -n "$AKS" \
  --addons monitoring \
  --workspace-resource-id "$LAW_ID" \
  -o none
```

How it works: This enables the `omsagent`/Azure Monitor logs add-on and connects it to the Log Analytics workspace.

3. Verify `ama-logs` is running on every node.

```bash
source ./env.sh

kubectl -n kube-system get ds ama-logs
kubectl -n kube-system get pods -l component=ama-logs -o wide
```

How it works: A DaemonSet schedules one log collector pod per node. New log rows can take 5-10 minutes to appear after enablement.

4. Prove ingestion with a KQL query.

```bash
source ./env.sh

LAW_GUID=$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query customerId -o tsv)

az monitor log-analytics query \
  -w "$LAW_GUID" \
  --analytics-query 'KubePodInventory | where TimeGenerated > ago(20m) | summarize Rows=count() by Namespace | top 10 by Rows' \
  -o table
```

How it works: KQL (Kusto Query Language) is the query language for Log Analytics. `KubePodInventory` is a Container Insights table containing pod metadata and status.

### Hands-on examples

#### Enable the add-on safely

Use this idempotent pattern when re-running the tutorial.

```bash
source ./env.sh

LAW_ID=$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query id -o tsv)

if az aks show -g "$RG" -n "$AKS" --query 'addonProfiles.omsagent.enabled' -o tsv | grep -qi true; then
  echo "Container Insights already enabled"
else
  az aks enable-addons -g "$RG" -n "$AKS" --addons monitoring --workspace-resource-id "$LAW_ID" -o none
fi
```

The check prevents unnecessary cluster updates when the add-on is already installed.

#### Query recent container logs

`ContainerLogV2` stores stdout and stderr from containers.

```kql
ContainerLogV2
| where TimeGenerated > ago(30m)
| where PodNamespace == "demo"
| project TimeGenerated, PodNamespace, PodName, ContainerName, LogMessage
| order by TimeGenerated desc
| take 50
```

Run it from the Azure portal Logs blade or with `az monitor log-analytics query`.

#### Query pod restarts

Use this query to find containers that restarted recently.

```kql
KubePodInventory
| where TimeGenerated > ago(2h)
| summarize Restarts=max(ContainerRestartCount) by Namespace, PodName, ContainerName
| where Restarts > 0
| order by Restarts desc
```

Restarts often indicate crash loops, failed probes, or resource pressure.

#### Wire an alert route and a metric alert

An action group is the notification target. Replace the email placeholder before running.

```bash
source ./env.sh

AKS_ID=$(az aks show -g "$RG" -n "$AKS" --query id -o tsv)

az monitor action-group create \
  -g "$RG" \
  -n oncall \
  --short-name oncall \
  --action email sre <your-alert-email@example.com> \
  -o none

ACTION_GROUP_ID=$(az monitor action-group show -g "$RG" -n oncall --query id -o tsv)

az monitor metrics alert create \
  -g "$RG" \
  -n aks-node-cpu-high \
  --scopes "$AKS_ID" \
  --description "AKS average node CPU is high" \
  --condition "avg node_cpu_usage_percentage > 80" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --action "$ACTION_GROUP_ID" \
  -o none
```

This creates the routing target and an example metric alert. If your cluster exposes a different metric name, list available metrics with `az monitor metrics list-definitions --resource "$AKS_ID" -o table` and adjust the condition.

## 17. CI/CD with GitHub Actions and OIDC

**What & why**  
CI/CD automates validation, image build, security scanning, and GitOps promotion. This platform uses passwordless GitHub Actions authentication with OIDC federation: GitHub sends a short-lived identity token to Entra ID, and Entra exchanges it for an Azure token. There is **no client secret**; `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, and `ACR_NAME` are GitHub repository variables referenced as `vars.*`.

### Steps

1. Create or confirm the Azure Container Registry exists before `build.yml` runs.

```bash
source ./env.sh

az acr show -g "$RG" -n "$ACR" -o table \
  || az acr create -g "$RG" -n "$ACR" -l "$LOCATION" --sku Basic -o none
```

How it works: The validated build imports an image into ACR. If the registry does not exist, the workflow fails before scanning or deployment.

2. Create the Entra app registration and service principal for GitHub Actions.

```bash
source ./env.sh

GITHUB_ORG=<your-github-org>
GITHUB_REPO=<your-repo>
APP_NAME=github-${PREFIX}-${ENV}-oidc

AZURE_CLIENT_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
SP_OBJECT_ID=$(az ad sp create --id "$AZURE_CLIENT_ID" --query id -o tsv)

az role assignment create \
  --assignee "$SP_OBJECT_ID" \
  --role Contributor \
  --scope "/subscriptions/$SUB_ID/resourceGroups/$RG" \
  -o none

ACR_ID=$(az acr show -g "$RG" -n "$ACR" --query id -o tsv)
az role assignment create \
  --assignee "$SP_OBJECT_ID" \
  --role AcrPush \
  --scope "$ACR_ID" \
  -o none
```

How it works: The app registration is the identity GitHub will use. The service principal receives only the Azure roles needed by the workflows.

3. Add a federated credential for the `main` branch.

```bash
source ./env.sh

GITHUB_ORG=<your-github-org>
GITHUB_REPO=<your-repo>
AZURE_CLIENT_ID=<AZURE_CLIENT_ID>
SUBJECT="repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/main"

az ad app federated-credential create \
  --id "$AZURE_CLIENT_ID" \
  --parameters "{\"name\":\"github-main\",\"issuer\":\"https://token.actions.githubusercontent.com\",\"subject\":\"$SUBJECT\",\"audiences\":[\"api://AzureADTokenExchange\"]}"
```

How it works: The `subject` locks this credential to one repo and branch. If `azure/login` fails with `AADSTS700213`, copy the exact `subject claim` from the error; some GitHub orgs use immutable numeric IDs such as `repo:OWNER@<ownerId>/REPO@<repoId>:ref:refs/heads/main`.

4. Store GitHub repository variables, not secrets.

```bash
source ./env.sh

echo "Requires GitHub CLI authenticated to <your-github-org>/<your-repo>."
gh variable set AZURE_CLIENT_ID --body "<AZURE_CLIENT_ID>"
gh variable set AZURE_TENANT_ID --body "$TENANT_ID"
gh variable set AZURE_SUBSCRIPTION_ID --body "$SUB_ID"
gh variable set ACR_NAME --body "$ACR"
gh variable set ADMIN_GROUP_OBJECT_ID --body "<ADMIN_GROUP_OBJECT_ID>"
```

How it works: OIDC is passwordless, so there is no `AZURE_CLIENT_SECRET`. Repository variables are available to workflows as `${{ vars.NAME }}`; use secrets only for actual passwords, tokens, or private keys.

5. Understand the validated workflows.

```yaml
build.yml: imports/pushes demo image to ACR, logs in with OIDC, scans with Trivy
pr-validate.yml: validates Terraform, Bicep, Kustomize, and IaC scan results
infra.yml: applies Terraform after the protected GitHub Environment approval
deploy.yml: updates the GitOps image tag and commits it back to main
```

How it works: Build produces an immutable image tag using `${{ github.sha }}`. Deploy promotes by editing Git, and the GitOps controller reconciles the cluster.

### Hands-on examples

#### OIDC federated-credential creation commands

This command creates the normal branch-based subject. Use the numeric subject from the `azure/login` error if your tenant requires it.

```bash
source ./env.sh

GITHUB_ORG=<your-github-org>
GITHUB_REPO=<your-repo>
AZURE_CLIENT_ID=<AZURE_CLIENT_ID>

az ad app federated-credential create \
  --id "$AZURE_CLIENT_ID" \
  --parameters "{\"name\":\"github-main\",\"issuer\":\"https://token.actions.githubusercontent.com\",\"subject\":\"repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/main\",\"audiences\":[\"api://AzureADTokenExchange\"]}"
```

If you see `AADSTS700213`, do not guess. Copy the exact subject claim printed by the workflow failure and create or update the federated credential with that value.

#### Minimal build and push job

This is the validated pattern: `ACR` comes from `vars.ACR_NAME`, and Azure login uses repo variables.

```yaml
name: build
on:
  push:
    branches: [ main ]
    paths: [ 'apps/**' ]
  workflow_dispatch: {}
permissions:
  contents: read
  id-token: write
  security-events: write
env:
  ACR: ${{ vars.ACR_NAME }}
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: azure/login@v2
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID }}
          tenant-id: ${{ vars.AZURE_TENANT_ID }}
          subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
      - name: Import image to ACR
        run: |
          az acr import --name "$ACR" --force \
            --image demo:${{ github.sha }} \
            --source mcr.microsoft.com/azuredocs/aks-helloworld:v1
```

`id-token: write` allows GitHub to request the OIDC token. The workflow does not store or use a password.

#### Trivy scan step pinned by SHA

Trivy is the vulnerability scanner. SARIF is a standard security-results format that GitHub can upload to the Security tab.

```yaml
- name: ACR docker login for scanner pull
  run: az acr login --name "${{ vars.ACR_NAME }}"

- name: Trivy image scan
  uses: aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25 # v0.36.0
  with:
    image-ref: ${{ vars.ACR_NAME }}.azurecr.io/demo:${{ github.sha }}
    exit-code: '0'
    severity: 'CRITICAL,HIGH'
```

The tag `aquasecurity/trivy-action@0.24.0` does not exist, and the image reference must stay on one line. In production, consider `exit-code: '1'` to fail on high-severity findings.

#### Kustomize set-image GitOps promotion step

This is the deployment handoff: GitHub Actions edits Git, then Flux or Argo CD reconciles the cluster.

```yaml
- uses: azure/setup-kubectl@v4

- name: Install kustomize
  run: |
    curl -sfL https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh | bash
    sudo mv kustomize /usr/local/bin/

- name: Bump image tag watched by GitOps
  env:
    ACR: ${{ vars.ACR_NAME }}
  run: |
    cd apps/demo
    kustomize edit set image demo="${ACR}.azurecr.io/demo:${{ github.event.workflow_run.head_sha }}"
    git config user.name "github-actions[bot]"
    git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
    git commit -am "deploy demo ${{ github.event.workflow_run.head_sha }}" || echo "no changes"
    git push
```

The git identity is required; without `user.name` and `user.email`, the runner refuses to create the GitOps commit.

---

## 18. Backup & Restore with Azure Backup for AKS

**What & why**  
Azure Backup for AKS snapshots your Kubernetes workloads — namespaced objects (Deployments, Services, ConfigMaps, Secrets) and, optionally, the data on persistent volumes via CSI snapshots — into a **Backup vault** so you can recover after an accidental `kubectl delete`, a bad rollout, or the loss of a whole namespace. It is a managed, policy-driven service: you define a schedule and retention once, and Azure runs the backups and prunes old restore points for you.

There are a few moving parts, and it helps to know what each one does before you run the commands:

- **Backup vault** — the Azure resource that stores restore points and enforces retention. Separate from a Recovery Services vault.
- **Backup storage account + blob container** — the in-cluster data mover writes the actual backup blobs here.
- **AKS Backup extension** — a cluster extension (`microsoft.dataprotection.kubernetes`) that runs the data mover pods inside `kube-system`. It gets its own managed identity.
- **Trusted Access** — a role binding that lets the Backup vault operate on the cluster's API without you handing out kubeconfig credentials.
- **Backup policy** — the schedule (the default template is hourly with a daily full) and retention (7 days).
- **Backup instance** — the actual protected item: "namespace `demo` on this cluster, using this policy."

> [!IMPORTANT]
> **Governed-subscription wrinkle.** On subscriptions governed by security baselines (for example the NIST or CIS initiatives), a policy **force-disables public network access** on new storage accounts. With no public data-plane path, the in-cluster data mover cannot reach the backup blob container and the backup instance fails with `UserErrorGenericNetworkMisconfiguration` (a 403). The production-correct fix — and the one this tutorial uses — is to wire a **blob private endpoint** into the AKS VNet, exactly like the Key Vault private endpoint in Section 6. Two related gotchas fall out of this: (1) create the blob container over the **management plane** (`az storage container-rm create`), because a data-plane create from a machine that is not on the VNet silently fails; and (2) when you create the private-endpoint DNS zone group, pass the private DNS zone's **resource ID**, or no A record is registered and the cluster resolves `NXDOMAIN`.

The whole flow is automated and idempotent in **`platform/16-backup.sh`** — you can run that script end to end. The steps below walk through what it does so you understand each stage.

### Steps

1. Create the backup storage account and its blob container.

```bash
source ./env.sh

# Storage account for the backup blobs (LRS is fine for a demo).
az storage account create -g "$RG" -n "$BKUP_SA" -l "$LOCATION" \
  --sku Standard_LRS --min-tls-version TLS1_2 --allow-blob-public-access false -o none

# IMPORTANT: create the container over the MANAGEMENT plane (container-rm), not the
# data plane (container create). On governed subs the SA has public access disabled,
# so a data-plane create from off-VNet fails silently.
az storage container-rm create --storage-account "$BKUP_SA" -g "$RG" -n "$BKUP_CONTAINER" -o none
```

**How it works** — The data mover reads and writes backup blobs in `$BKUP_CONTAINER`. `container-rm` goes through Azure Resource Manager, so it works regardless of the storage firewall, whereas the data-plane `az storage container create` needs a network path to the blob endpoint that a governed SA does not expose publicly.

2. Give the cluster a private path to the storage account (blob private endpoint + private DNS).

```bash
source ./env.sh

SA_ID=$(az storage account show -g "$RG" -n "$BKUP_SA" --query id -o tsv)

# Private DNS zone for blob + link it to the AKS VNet.
az network private-dns zone create -g "$RG" -n privatelink.blob.core.windows.net -o none
az network private-dns link vnet create -g "$RG" -z privatelink.blob.core.windows.net \
  -n "link-$VNET" --virtual-network "$VNET" --registration-enabled false -o none

# Private endpoint into the shared PE subnet (snet-pe, created in Section 6).
az network private-endpoint create -g "$RG" -n "pe-$BKUP_SA" -l "$LOCATION" \
  --vnet-name "$VNET" --subnet snet-pe \
  --private-connection-resource-id "$SA_ID" \
  --group-id blob --connection-name "conn-$BKUP_SA" -o none

# DNS zone group — pass the zone RESOURCE ID (not the name) so the A record registers.
ZONE_ID="/subscriptions/${SUB_ID}/resourceGroups/${RG}/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
az network private-endpoint dns-zone-group create -g "$RG" \
  --endpoint-name "pe-$BKUP_SA" -n zg \
  --private-dns-zone "$ZONE_ID" --zone-name blob -o none
```

**How it works** — The private endpoint gives the storage account a private IP inside `snet-pe`. The private DNS zone `privatelink.blob.core.windows.net`, linked to the AKS VNet, makes the cluster resolve `$BKUP_SA.blob.core.windows.net` to that private IP instead of a public one. The zone group auto-registers the A record — but only if you pass the zone's resource ID.

3. Create the Backup vault.

```bash
source ./env.sh

az dataprotection backup-vault create -g "$RG" --vault-name "$BKUP_VAULT" -l "$LOCATION" \
  --type SystemAssigned \
  --storage-settings datastore-type="VaultStore" type="LocallyRedundant" -o none
```

**How it works** — The vault holds restore points and gets a **system-assigned managed identity** that later needs permissions on the cluster and snapshot resource group. `VaultStore` + `LocallyRedundant` keeps a single-region copy (cheapest tier).

4. Install the AKS Backup extension and grant its identity access to the storage account.

```bash
source ./env.sh

SA_ID=$(az storage account show -g "$RG" -n "$BKUP_SA" --query id -o tsv)

az k8s-extension create --name "$BKUP_EXT" \
  --extension-type microsoft.dataprotection.kubernetes \
  --scope cluster --cluster-type managedClusters \
  --cluster-name "$AKS" --resource-group "$RG" --release-train stable \
  --configuration-settings \
    blobContainer="$BKUP_CONTAINER" storageAccount="$BKUP_SA" \
    storageAccountResourceGroup="$RG" storageAccountSubscriptionId="$SUB_ID" -o none

# The extension gets its own managed identity — grant it data access to the SA.
EXT_MSI=$(az k8s-extension show --name "$BKUP_EXT" --cluster-name "$AKS" \
  --resource-group "$RG" --cluster-type managedClusters \
  --query aksAssignedIdentity.principalId -o tsv)

az role assignment create --assignee-object-id "$EXT_MSI" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" --scope "$SA_ID" -o none
```

**How it works** — The extension runs the data mover pods in the cluster. It authenticates to the storage account with its own managed identity, so that identity needs **Storage Blob Data Contributor** on the SA to write backup blobs.

5. Wire Trusted Access, then create the backup policy.

```bash
source ./env.sh

VAULT_ID=$(az dataprotection backup-vault show -g "$RG" --vault-name "$BKUP_VAULT" --query id -o tsv)

# Trusted Access lets the vault operate on the cluster without kubeconfig creds.
az aks trustedaccess rolebinding create -g "$RG" --cluster-name "$AKS" \
  -n aksbackup-tab --source-resource-id "$VAULT_ID" \
  --roles "Microsoft.DataProtection/backupVaults/backup-operator" -o none

# Backup policy from the built-in default template (hourly schedule, 7-day retention).
az dataprotection backup-policy get-default-policy-template \
  --datasource-type AzureKubernetesService > policy.json
az dataprotection backup-policy create -g "$RG" --vault-name "$BKUP_VAULT" \
  -n "$BKUP_POLICY" --policy "$(cat policy.json)" -o none
```

**How it works** — Trusted Access binds the vault's `backup-operator` role to the cluster so the managed backup flow can snapshot resources. The policy defines *when* and *how long*: the default template runs a backup on a schedule and keeps restore points for 7 days.

6. Configure and create the backup instance for the `demo` namespace.

```bash
source ./env.sh

CLUSTER_ID=$(az aks show -g "$RG" -n "$AKS" --query id -o tsv)
POLICY_ID=$(az dataprotection backup-policy show -g "$RG" --vault-name "$BKUP_VAULT" -n "$BKUP_POLICY" --query id -o tsv)

# What to back up: the demo namespace, including PV snapshots and cluster-scoped refs.
az dataprotection backup-instance initialize-backupconfig \
  --datasource-type AzureKubernetesService \
  --included-namespaces "$BKUP_NS" --snapshot-volumes true \
  --include-cluster-scope-resources true > backupconfig.json

az dataprotection backup-instance initialize \
  --datasource-type AzureKubernetesService --datasource-location "$LOCATION" \
  --datasource-id "$CLUSTER_ID" --policy-id "$POLICY_ID" \
  --backup-configuration "$(cat backupconfig.json)" \
  --friendly-name "$BKUP_INSTANCE" \
  --snapshot-resource-group-name "$RG" > backupinstance.json

# Grant the vault identity the roles it needs, then create the instance.
az dataprotection backup-instance update-msi-permissions \
  --datasource-type AzureKubernetesService --resource-group "$RG" \
  --vault-name "$BKUP_VAULT" --backup-instance "$(cat backupinstance.json)" \
  --operation Backup --permissions-scope ResourceGroup --yes -o none

az dataprotection backup-instance create -g "$RG" --vault-name "$BKUP_VAULT" \
  --backup-instance "$(cat backupinstance.json)" -o none
```

**How it works** — The backup *configuration* declares scope (namespace `$BKUP_NS`, volume snapshots on, cluster-scoped resources included). `update-msi-permissions` grants the vault's identity the cluster/snapshot/storage roles it needs. `create` then registers the protected item; it takes a couple of minutes to reach `ProtectionConfigured`.

### Hands-on examples

#### Show what is protected

Start every backup demo by proving the pieces exist and the item is healthy.

```bash
source ./env.sh

# The vault, the policy, and the protected item with its live protection state.
az dataprotection backup-vault show -g "$RG" --vault-name "$BKUP_VAULT" \
  --query "{name:name, state:properties.provisioningState}" -o table

az dataprotection backup-instance list -g "$RG" --vault-name "$BKUP_VAULT" \
  --query "[].{name:properties.friendlyName, state:properties.currentProtectionState}" -o table
```

A healthy item shows `ProtectionConfigured`. If you see `ConfiguringProtection`, wait a minute and re-run — the backend is still finishing setup.

#### Trigger an on-demand backup and watch the job

You do not have to wait for the schedule — force a backup now and follow the job to completion.

```bash
source ./env.sh

BI=$(az dataprotection backup-instance list -g "$RG" --vault-name "$BKUP_VAULT" --query "[0].name" -o tsv)
RULE=$(az dataprotection backup-policy show -g "$RG" --vault-name "$BKUP_VAULT" -n "$BKUP_POLICY" \
  --query 'properties.policyRules[?backupParameters].name | [0]' -o tsv)

az dataprotection backup-instance adhoc-backup --name "$BI" -g "$RG" --vault-name "$BKUP_VAULT" \
  --rule-name "$RULE" --retention-tag-override Default -o none

# Follow the most recent job until it reads "Completed".
az dataprotection job list -g "$RG" --vault-name "$BKUP_VAULT" \
  --query "[0].{op:properties.operationCategory, status:properties.status, start:properties.startTime}" -o table
```

**How it works** — `adhoc-backup` submits a one-off backup using the policy's backup rule; `--retention-tag-override Default` tags the restore point with the default retention. The job moves `InProgress → Completed` in a few minutes.

#### List restore points

Every completed backup produces a restore point you can recover from.

```bash
source ./env.sh

BI=$(az dataprotection backup-instance list -g "$RG" --vault-name "$BKUP_VAULT" --query "[0].name" -o tsv)

az dataprotection recovery-point list -g "$RG" --vault-name "$BKUP_VAULT" \
  --backup-instance-name "$BI" \
  --query "[].{name:name, time:properties.recoveryPointTime}" -o table
```

**How it works** — Each row is a point in time you can restore. The `name` (a GUID) is what you pass to a restore operation as `--recovery-point-id`.

#### Prepare a namespace restore

Restore is the payoff. This example shows how to build and validate a restore request — run the validation first so you catch problems before touching the cluster.

```bash
source ./env.sh

BI=$(az dataprotection backup-instance list -g "$RG" --vault-name "$BKUP_VAULT" --query "[0].name" -o tsv)
CLUSTER_ID=$(az aks show -g "$RG" -n "$AKS" --query id -o tsv)
RP=$(az dataprotection recovery-point list -g "$RG" --vault-name "$BKUP_VAULT" \
  --backup-instance-name "$BI" --query "[0].name" -o tsv)

# Build a restore request: restore the demo namespace from the newest restore point.
az dataprotection backup-instance restore initialize-for-item-recovery \
  --datasource-type AzureKubernetesService \
  --restore-location "$LOCATION" --source-datastore OperationalStore \
  --recovery-point-id "$RP" \
  --backup-instance-id "$(az dataprotection backup-instance show -g "$RG" --vault-name "$BKUP_VAULT" -n "$BI" --query id -o tsv)" \
  --included-namespaces "$BKUP_NS" > restorerequest.json

# Validate BEFORE running — this checks permissions, conflicts, and snapshot access.
az dataprotection backup-instance validate-for-restore -g "$RG" --vault-name "$BKUP_VAULT" \
  --name "$BI" --restore-request-object "$(cat restorerequest.json)" -o table

# When validation passes, trigger the restore:
# az dataprotection backup-instance restore trigger -g "$RG" --vault-name "$BKUP_VAULT" \
#   --name "$BI" --restore-request-object "$(cat restorerequest.json)" -o none
```

**How it works** — `initialize-for-item-recovery` builds the restore request JSON (what to restore, from which point, into which namespace). `validate-for-restore` dry-runs it against the cluster so you catch RBAC or conflict issues first. Only after it passes do you uncomment and run `restore trigger`. To rehearse safely, restore into a *different* namespace with `--target-resource-group-name`/namespace mapping so you never overwrite live workloads.

## 19. Cleanup — tear it all down

**What & why**
Everything you built lives inside a single resource group, so cleanup is a one‑liner. Do this **last**, and only when you are finished — deleting the resource group is irreversible and removes the cluster, Key Vault, monitoring workspaces, and networking in one shot. Running it stops all further cost.

### Steps

1. Delete the whole resource group.
```bash
source ./env.sh
az group delete --name "$RG" --yes --no-wait
```
**How it works** — `az group delete` removes the resource group and **every resource inside it**. `--yes` skips the confirmation prompt and `--no-wait` returns immediately while Azure deletes in the background. Because you placed the cluster, Key Vault, VNet, and monitoring resources all in `$RG`, this single command cleans up the entire platform.

2. (Optional) Confirm the deletion finished.
```bash
az group exists --name "$RG"   # prints "false" once deletion completes
```
**How it works** — `az group exists` returns `true` while the group is still being torn down and `false` once it is gone. Deletion of a full AKS platform typically takes a few minutes.

3. (Optional) Remove leftover GitHub CI/CD identity.
```bash
# Only if you created a dedicated Entra app registration for OIDC (Section 17):
az ad app delete --id "<AZURE_CLIENT_ID>"
```
**How it works** — The federated CI/CD identity lives in **Microsoft Entra ID**, not in the resource group, so it survives an `az group delete`. Remove it separately if you no longer need the pipeline. Repository variables in GitHub can be deleted from **Settings → Secrets and variables → Actions**.

> [!WARNING]
> **Cost tip.** Managed Prometheus, Grafana, Log Analytics, and the AGC load balancer accrue cost while they run. If you want to pause spend without destroying your work, you can instead **stop the cluster** with `az aks stop -g "$RG" -n "$AKS"` and start it later with `az aks start` — but note that stopped clusters still bill for disks, the load balancer, and monitoring workspaces. A full `az group delete` is the only way to stop all charges.

---

## Where to go next

You now have a validated, end‑to‑end AKS platform. Good next steps:

- **Harden for production** — enable availability zones (`AKS_ZONES="1 2 3"`), raise the system pool to min 3 for zone spread, pin your Kubernetes version, and review the Kyverno policies you want to move from `Audit` to `Enforce`.
- **Promote GitOps** — move more of your platform installs into Argo CD or Flux so the cluster state is fully declarative and reproducible.
- **Extend CI/CD** — add environments (staging/prod), approvals, and image‑signing to the pipeline.
- **Keep the errata handy** — the companion `ERRATA.md` records every validated fix and caveat; keep it next to this tutorial when you share it.