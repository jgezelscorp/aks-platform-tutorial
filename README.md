# AKS Platform Deployment Tutorial — validated companion repo

A hands-on, **validated** reference for standing up a secured, observable AKS platform on
Azure CNI Overlay + Cilium, with Entra Workload Identity, Application Gateway for Containers
(AGC) ingress, Key Vault CSI secrets, Kyverno + Cilium policy, GitOps (Argo CD), and managed
Prometheus + Grafana. Every command in this repo was executed against a live Azure
subscription and corrected where the original tutorial was wrong (see [`ERRATA.md`](ERRATA.md)).

## Layout

```
.
├── .github/workflows/    # CI/CD — pr-validate, infra, build, deploy (passwordless OIDC)
├── infra/
│   ├── bicep/            # main.bicep — validated (az bicep build)
│   ├── terraform/        # main.tf + variables/versions — validated (terraform validate)
│   └── *.sh              # imperative CLI provisioning path (alternative to IaC)
├── platform/             # cluster add-ons: AGC, netpol, Kyverno, Argo CD, observability, KEDA…
├── apps/demo/            # demo workload (Deployment/Service/HTTPRoute + kustomization)
└── env.sh                # single source of resource names (IDs resolved at runtime)
```

## CI/CD (Section 18)

Passwordless pipeline — GitHub federates to Microsoft Entra via **OIDC** (no stored cloud
secrets). CI builds and scans; **Argo CD** performs the actual deploy from Git.

| Workflow | Trigger | Does |
| --- | --- | --- |
| `pr-validate.yml` | PR → main | terraform fmt/validate, bicep build, kustomize validate, Trivy IaC scan → SARIF |
| `infra.yml` | push to `infra/**` / manual | `terraform apply` in the **prod** Environment (requires approval) |
| `build.yml` | push to `apps/**` / manual | `az acr import` a pinned image → ACR, Trivy image scan |
| `deploy.yml` | after `build` succeeds | bump the kustomize image tag in Git → Argo CD reconciles |

### Required Actions *variables* (Settings → Secrets and variables → Actions → Variables)

All are **variables, not secrets** — OIDC means no client secret is ever stored.

| Variable | Purpose |
| --- | --- |
| `AZURE_CLIENT_ID` | App registration (client) ID of the CI identity |
| `AZURE_TENANT_ID` | Entra tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target subscription |
| `ACR_NAME` | Azure Container Registry name (no domain) |
| `ADMIN_GROUP_OBJECT_ID` | Entra group granted cluster-admin (used by `infra.yml`) |

See `ERRATA.md` for the full list of corrections applied to the original tutorial.

<!-- CI validation trigger -->
