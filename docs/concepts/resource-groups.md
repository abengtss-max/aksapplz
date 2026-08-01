# Resource groups

How the accelerator organises Azure resource groups, and why. This follows the Cloud Adoption
Framework (CAF) guidance to **group resources by lifecycle** — resources that are created,
updated, and deleted together belong in the same resource group.

## The two layouts

The `resource_group_layout` setting (default `flat`) selects one of two layouts per region.

### `flat` (default)

A single regional resource group, `rg-<prefix>`, holds everything. Simple, and unchanged from
earlier releases. Good for demos, dev, and single-purpose clusters.

### `lifecycle`

Three resource groups split by lifecycle:

```text
rg-<prefix>-network    connectivity foundation (rarely changes)
rg-<prefix>-platform   stateful shared services (long-lived, compliance data)
rg-<prefix>-runtime    the cluster tier (disposable, rebuildable)
```

Plus the resource groups the accelerator already isolates: the AKS node resource group
(`MC_*`), the backup snapshot group (`rg-<prefix>-snap`), and the global Front Door / Traffic
Manager group. Those are unaffected by this setting.

## What each group holds, and why

| Resource group | Contents | Why it's grouped this way |
|---|---|---|
| `…-network` | Spoke VNet, subnets, NSGs, route tables, VNet peering. | Connectivity is the slowest-changing layer. Keeping it separate means IP plans and peering survive cluster rebuilds untouched. |
| `…-platform` | Key Vault, ACR, Log Analytics / Managed Prometheus / Grafana, Azure Backup, and the private endpoints + private DNS zones that front those services. | These hold **state** — secrets, images, telemetry history, backups — often under retention/compliance rules. A private endpoint's lifecycle follows the service it fronts, so it lives with that service (CAF lifecycle grouping), not with the VNet. |
| `…-runtime` | AKS cluster, Application Gateway + WAF, optional management jumpbox. | The **disposable** tier. You can destroy and recreate it to rebuild the cluster, change VM sizes, or recover from drift, without risking network or stateful data. |

The one-line story: **destroy `runtime`, keep `platform`, keep `network`.**

!!! note "About the name `platform`"
    Here `platform` means *workload-shared services* (Key Vault, ACR, monitoring, backup for this
    landing zone). It is **not** an Azure Landing Zone *platform* management group — that term
    refers to the centrally-managed connectivity/identity/management subscriptions, which are out
    of scope for this workload accelerator.

## Managed identity placement

User-assigned managed identities are placed by lifecycle, the same as everything else:

| Identity | Resource group | Rationale |
|---|---|---|
| Persistent / federation identities (e.g. CI/CD federated credentials, shared app identities) | `…-platform` | They outlive any single cluster and are shared across rebuilds. |
| Cluster-scoped identities (AKS control-plane UAMI, kubelet, AGIC/ALB) | `…-runtime` | They are created and destroyed with the cluster. |

AKS system-assigned identities live in the node resource group (`MC_*`) as usual; this rule only
applies to user-assigned identities the accelerator creates.

## Teardown behaviour

The main reason to choose `lifecycle` is a clean cluster teardown. When you destroy only the
runtime tier:

- **AKS + its `MC_*` group** are removed together — no orphaned node RG.
- **Application Gateway and the jumpbox** go with it. (When destroying the jumpbox, the VM must be
  running first so the `AADSSHLoginForLinux` extension can be removed cleanly.)
- **Key Vault, ACR, monitoring history, and backups stay put** in `platform`, so you don't hit
  Key Vault soft-delete name collisions or a Backup vault that blocks its resource group from
  deleting.
- **Private endpoints and private DNS zones** for the platform services stay with those services,
  so runtime teardown doesn't race the `network` or `platform` groups with
  `AnotherOperationInProgress` (409) errors.

In the `flat` layout everything shares one resource group, so a full teardown must sequence all of
the above together — which is exactly the friction the `lifecycle` layout removes.

## Switching layouts is breaking

Azure cannot move a resource between resource groups in place. Changing `resource_group_layout`
on an existing deployment forces the affected resources to be **recreated**. Pick the layout at
first deployment. To migrate an existing environment, plan a destroy/redeploy of the region (or a
Terraform `state mv` / import exercise). Track migration guidance in
[issue #40](https://github.com/abengtss-max/aksapplz/issues/40).
