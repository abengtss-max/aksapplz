# Changelog

All notable changes to the `ALZ.AKS` PowerShell module are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.18.1] - 2026-07-28

### Fixed
- **Jumpbox VM size availability — default changed from `Standard_B2s` to
  `Standard_B2s_v2`.** The v1 B-series (`Standard_B2s`, `Standard_B2ms`, …) is
  `NotAvailableForSubscription` / capacity-restricted in several regions, which
  surfaced as a `409 SkuNotAvailable` "Capacity Restrictions" error when
  creating the jumpbox in `SwedenCentral` and failed the CD apply after the rest
  of the landing zone had already provisioned. `Standard_B2s_v2` is the modern
  burstable equivalent (2 vCPU / 8 GiB, Gen2-capable) and is broadly available.
  The new default is applied consistently across the terraform variable
  defaults, the interactive wizard, the generated tfvars/config, every scenario
  config template, the planning checklist and the configuration reference.
  Deployments that explicitly set `jumpbox_vm_size` are unaffected — only the
  default recommendation changed. If a region still restricts this size, set
  any available size (e.g. `Standard_D2s_v5`) via `jumpbox_vm_size`.

## [1.18.0] - 2026-07-29

### Added
- **Opt-in management access: Azure Bastion + hardened jumpbox VM
  (`enable_management_jumpbox`, default `false`).** Provisions an Azure Bastion
  host and a hardened, **no-public-IP** Ubuntu 22.04 jumpbox VM for operating a
  **private** cluster and its private endpoints from inside the spoke VNet.
  - Login is via **Microsoft Entra ID** over Bastion (`AADSSHLoginForLinux`;
    password authentication disabled). The VM has a **system-assigned managed
    identity** granted `Azure Kubernetes Service Cluster User` (and
    `Azure Kubernetes Service RBAC Reader` when `enable_azure_rbac = true`).
  - Hardening: encryption-at-host, daily auto-shutdown to cap idle cost, and
    locked-down NSGs — the jumpbox subnet allows SSH only from the Bastion
    subnet, and the `AzureBastionSubnet` carries the required Bastion rule set
    so it satisfies the ALZ `Deny-Subnet-Without-Nsg` policy.
  - Operator tooling (az CLI, kubectl, kubelogin, helm) is pre-installed via
    cloud-init.
  - Two new subnets (`jumpbox` `10.10.25.0/27`, `AzureBastionSubnet`
    `10.10.26.0/26`; `10.20.x` in the secondary region) are created **only**
    when the flag is on — a standard deployment provisions **zero** of these
    resources and is completely unaffected.
  - Intended for **standalone** deployments; in ALZ/corp topologies the
    connectivity hub provides centralized Bastion/VPN, so leave it off there.
  - New tunables: `jumpbox_vm_size` (`Standard_B2s`), `jumpbox_admin_username`
    (`azureuser`), `bastion_sku` (`Standard`), `jumpbox_auto_shutdown_time` /
    `jumpbox_auto_shutdown_timezone`.
  - Surfaced in the interactive wizard, generated tfvars/config, the planning
    checklist, the configuration reference, scenarios-and-options, and a new
    Day-2 "Management access via Bastion + jumpbox" runbook section.
  - Closes issue #29.

## [1.17.1] - 2026-07-28

### Fixed
- **Durable fix for the plan-vs-apply CD identity RBAC gap that could leave the
  App Gateway backend pool empty on a fresh rebuild.** With Azure RBAC for
  Kubernetes enabled and local accounts disabled, the region module previously
  granted `Azure Kubernetes Service RBAC Reader` only to
  `data.azurerm_client_config.current.object_id`. In the split plan/apply CD
  pipeline that data source resolves at **plan** time to the **plan** managed
  identity and is frozen in the saved `tfplan` - but the CD ingress wire step
  (`az aks command invoke`) runs in the **apply** job as the **apply** managed
  identity, whose kubectl calls were therefore silently `Forbidden`, so the
  Istio internal ingress gateway IP was never discovered and the backend pool
  stayed empty (previously only recoverable by a manual
  `az role assignment create`).
  - The bootstrap composition now emits **both** the plan and apply managed
    identity principal (object) IDs into a terraform-generated
    `terraform/cd-identities.auto.tfvars`, merged into the workload repository's
    managed files. terraform auto-loads it alongside the rendered
    `aks-landing-zone.auto.tfvars`.
  - A new `cd_identity_principal_ids` list variable is plumbed from the root
    module into the region module, and the `deployer_aks_rbac_reader` role
    assignment moved from `count` to `for_each` so the RBAC Reader role is
    granted to **every** CD identity (plan + apply).
  - Standalone `terraform apply` runs where the list is empty fall back to
    `data.azurerm_client_config.current.object_id`, so behaviour outside the
    pipeline is unchanged. Ingress auto-wiring is now genuinely hands-off on
    every fresh rebuild.
- **Destroy is now resilient to transient Azure 409 conflicts on the private
  monitoring/Grafana teardown.** A `terraform destroy` (CD `destroy` action)
  could fail with two concurrency errors: (1) deleting the AMPLS private
  endpoint's `monitor-dns-zone-group` returned `409 AnotherOperationInProgress`,
  because the backup blob private endpoint reuses the SAME shared
  `privatelink.blob.core.windows.net` zone and their private DNS zone groups
  were being deleted concurrently; and (2) deleting the Grafana managed private
  endpoint `mpe-amw-*` returned `409 ConflictInProcessing` ("Operation conflict
  occurred for workspace ... Please try again later") because the Grafana
  control plane serializes operations per workspace and was still busy tearing
  Grafana down.
  - The backup blob private endpoint now has an explicit `depends_on` on the
    AMPLS private endpoint, so Terraform tears the two blob-zone endpoints down
    sequentially instead of in parallel (no-op when the AMPLS endpoint is
    absent).
  - The Grafana managed private endpoint (`azapi_resource`) now retries on the
    transient `ConflictInProcessing` / `AnotherOperationInProgress` responses
    until the workspace is free, instead of failing the whole destroy.
  - Result: destroy and re-apply are now smooth and idempotent with no manual
    cleanup step.
- **Destroy re-runs are now safe — no more `Saved plan is stale`.** The CD
  destroy path previously generated a `terraform plan -destroy` artifact in the
  `plan` job and applied that saved plan in the `apply` job. If a teardown
  stopped partway (e.g. on a transient Azure error), the state moved on and
  re-running the failed job — which reuses the original artifact — failed with
  `Saved plan is stale`. The apply job now runs `terraform destroy -auto-approve`
  (recomputed from live state) for the `destroy` action instead of applying the
  saved plan, so re-running the failed job or dispatching a fresh destroy always
  resumes the teardown idempotently. The `apply` (create/update) path is
  unchanged — it still applies the exact saved plan the approver reviewed — and
  the environment approval gate still governs when destroy may proceed.

## [1.17.0] - 2026-07-27

### Added
- **The AKS cluster autoscaler profile is now tunable — opt-in, with defaults
  unchanged.** A new `auto_scaler_profile` object variable is plumbed through the
  root module, the region module, and into the AVM AKS module's
  `auto_scaler_profile`. It defaults to `null`, so clusters keep the **native AKS
  autoscaler defaults** and existing deployments see **no behavioural change**.
  - The accelerator deliberately does **not** ship an opinionated profile. The
    profile is **cluster-wide** (it also affects the system pool) and the right
    cost-versus-performance values are **workload-specific** — this matches
    Microsoft's own guidance, which frames tuning the profile as a per-workload
    trade-off rather than a default.
  - Customers set only the keys they want to override in their `*.tfvars`;
    everything omitted falls back to the AKS default. The `expander` value is
    validated at plan time to one of `least-waste | most-pods | priority |
    random`.
  - Rather than choosing values for the customer, the accelerator **exposes and
    explains** them: a dedicated docs page (**Advanced → Cluster autoscaler
    tuning**) covering the trade-off, the AKS defaults, Microsoft's example
    cost/performance profiles and copy-paste tfvars snippets; a Configuration
    reference row; a Day-2 runbook cross-link; and a single optional awareness
    row in the planning checklist.
  - Closes roadmap issue #13.

## [1.16.2] - 2026-07-27

### Fixed
- **Azure Backup for AKS no longer deploys in a `ProtectionError` state.** The
  backup datastore is intentionally hardened (`shared_access_key_enabled = false`,
  AAD-only) and, on platforms that mandate private connectivity, has public
  network access disabled. Two gaps left the backup instance unhealthy on a
  fresh deploy:
  - **The backup extension was not told to use Microsoft Entra ID (AAD) for its
    Backup Storage Location.** Without it the in-cluster data mover defaulted to
    *storage-account-key* mode and tried to list the account keys — which the
    keys-disabled account refuses — so the `default` BackupStorageLocation was
    reported *unavailable* (`UserErrorExtensionIdentityNotFound`). The extension
    now sets `configuration.backupStorageLocation.config.useAAD = "true"`, so it
    authenticates to blob storage with its user-assigned extension identity
    (already granted `Storage Blob Data Contributor`) and never lists keys.
  - **The backup storage account had no private endpoint.** With public network
    access disabled the VNet service-endpoint firewall rules are ignored, so the
    data mover's blob requests were blocked (`403 AuthorizationFailure`). The
    region module now provisions a **blob private endpoint** for the backup
    storage account in the spoke's private-endpoint subnet (and sets the
    account's `public_network_access_enabled` from the private-endpoint posture),
    reusing the Azure Monitor (AMPLS) `privatelink.blob.core.windows.net` zone
    when present, self-managing it otherwise, or consuming the hub-supplied zone
    id in corp topology. The backup container create is ordered behind the
    private endpoint so the VNet-injected deployer can reach the account.

## [1.16.1] - 2026-07-27

### Fixed
- **Ingress controller is now auto-selected from the topology.** The
  `ingress_controller` output previously echoed the raw variable, which allowed
  an inconsistent state: with the managed Istio internal ingress gateway enabled
  but `ingress_controller` left at `manual`, the CD pipeline silently skipped the
  automatic App Gateway backend-pool wiring and left the pool empty. The value is
  now **derived**: it resolves to `istio` automatically whenever
  `enable_app_gateway && enable_istio_service_mesh && istio_internal_ingress_gateway`
  are all true, otherwise it falls back to the customer-selected value. The
  wiring is implemented entirely in the pipeline and stays fully **dynamic** - it
  discovers the Istio internal ingress gateway's private LoadBalancer IP at run
  time and sets it on the backend pool, so no IP is ever hard-coded (customers
  bring their own address space).
- **Defender for Containers plan now enables the full extension set.** When
  `enable_defender_for_containers_plan` is set, the subscription plan now
  enables `AgentlessVmScanning` and `ContainerSensor` in addition to
  `AgentlessDiscoveryForKubernetes` and `ContainerRegistriesVulnerabilityAssessments`.
  Previously only the latter two were configured, so opting into the plan left
  Defender for Cloud reporting the sensor / agentless-scanning coverage as
  "partial". The completed set yields full container protection.
- **Deploying identity is now granted Kubernetes read access so automatic
  ingress wiring works end-to-end.** With Azure RBAC for Kubernetes enabled and
  local accounts disabled, the CD identity's `az aks command invoke` kubectl was
  silently *forbidden* to read the Istio internal ingress gateway service, so the
  automatic App Gateway backend-pool wiring never resolved an IP (it only worked
  when an operator wired it by hand). The region module now assigns the deployer
  an **Azure Kubernetes Service RBAC Reader** role on the cluster
  (gated on `enable_azure_rbac`), and the CD wire step now surfaces the in-cluster
  kubectl error instead of swallowing it. Ingress wiring is now genuinely
  hands-off for customers.

## [1.16.0] - 2026-07-27

### Changed
- **Ingress model simplified — managed Istio or bring-your-own.** The
  Application Gateway ingress path no longer installs an open-source controller
  for you. The `ingress_controller` variable now accepts only `istio` or
  `manual` (the `traefik` value and the CD pipeline's Helm/Traefik install are
  removed):
  - `istio` — the accelerator sets up the managed Istio internal ingress
    gateway and the CD pipeline auto-wires its private IP into the App Gateway
    backend pool end-to-end. Requires `enable_istio_service_mesh = true` and
    `istio_internal_ingress_gateway = true` (both set automatically when the
    mesh is enabled).
  - `manual` — the accelerator delivers the baseline (cluster + Application
    Gateway + empty backend pool) and hands off. The customer installs and
    wires their own open-source ingress controller (e.g. Traefik or
    ingress-nginx) as an internal `LoadBalancer` Service and sets the backend
    pool to its private IP. Guidance is printed in the `ingress_next_steps`
    output and the CD job summary.

  This removes Helm from the pipeline entirely and keeps a single, understandable
  framework per path. The interactive wizard no longer prompts for a controller:
  it selects `istio` when the mesh is enabled, otherwise `manual`.

- **Managed Prometheus and Grafana are now private when private endpoints are
  enabled.** Previously the Azure Monitor workspace (Managed Prometheus) and its
  data collection endpoint were reachable over the public internet even in a
  private-endpoint deployment. When private endpoints are in use (corp topology,
  or standalone with `enable_private_endpoints = true`) and Managed Prometheus is
  enabled, the module now:
  - creates an **Azure Monitor Private Link Scope (AMPLS)** with a private
    endpoint (`pe-ampls-*`, subresource `azuremonitor`) into the spoke's
    private-endpoint subnet, and adds the Prometheus **data collection endpoint**
    and the **Log Analytics workspace** as scoped services (private ingestion);
  - sets `public_network_access_enabled = false` on the **Azure Monitor
    workspace** and the **Prometheus DCE**, removing their public exposure;
  - self-manages the five Azure Monitor `privatelink.*` DNS zones and links them
    to the spoke VNet in standalone, or consumes hub-supplied zone ids via the
    new `monitor_private_dns_zone_ids` variable in corp topology;
  - creates a **Grafana managed private endpoint** to the workspace
    (`groupIds = ["prometheusMetrics"]`) so managed Grafana keeps querying
    Prometheus over the private query path after public access is disabled.

  Public deployments (no private endpoints) are unchanged: the workspace and DCE
  keep public network access and no AMPLS is created.

### Fixed
- **Ingress wiring speed and reliability (istio path).** The CD
  "Wire ingress controller into App Gateway" step now discovers the internal
  LoadBalancer IP inside a **single** `az aks command invoke` (one in-cluster
  wait loop) instead of up to 30 separate poll invokes. Each invoke pays a
  ~15–20s command-pod scheduling cost, so the old design could take ~12 minutes
  and, on a transient inner failure, gave up silently — the inner command's
  non-zero exit was masked because `az aks command invoke` returns 0 and
  `-o none` hid the output. The step now runs the wait script with
  `set -eo pipefail`, surfaces failures, and typically completes in ~1 minute.

## [1.15.1] - 2026-07-26

### Fixed
- **Deployment reliability: Flux/Dapr cluster extensions no longer race the AKS
  agent-pool update.** The `azurerm_kubernetes_cluster_extension` resources for
  Flux and Dapr (added in 1.14.0) only referenced the cluster id, so Terraform
  installed them (a long-running cluster operation, ~18 min for Flux)
  concurrently with the AVM AKS module's post-create system agent-pool update
  (`azapi_update_resource.default_agent_pool`). AKS rejected the overlapping
  control-plane PUT with a 409 `EtagMismatch` /
  `PutAgentPool_FailedPrecondition` ("Another operation is in progress",
  https://aka.ms/aks/aksoperationpreempted), failing the entire `terraform
  apply` on fresh deployments that enable GitOps/Dapr and leaving later
  resources (e.g. the ACR private endpoint) uncreated and ingress unwired. Both
  extensions now `depends_on` the whole AKS module, and Dapr additionally waits
  for Flux, so at most one long-running cluster extension operation runs at a
  time. No configuration change; existing deployments are unaffected.

## [1.15.0] - 2026-07-26

### Changed
- **Managed Grafana is now private by default (WAF/CAF-aligned).** Azure Managed
  Grafana's product default is public, but Microsoft's security guidance
  recommends disabling public network access and reaching the workspace over a
  private endpoint. The accelerator now follows that guidance: when private
  endpoints are in use (corp/hub topology, or standalone with the default
  `enable_private_endpoints = true`), Grafana's `public_network_access_enabled`
  is turned OFF and a **Grafana private endpoint** is provisioned in the
  private-endpoints subnet, with a self-managed `privatelink.grafana.azure.com`
  private DNS zone linked to the spoke VNet (or hub-supplied zone ids in corp).
  The workspace stays reachable from the VNet.
- `grafana_public_access` is now a nullable override: when unset it is derived
  from the private-endpoint posture (private when private endpoints are used,
  public otherwise); set it explicitly to `true`/`false` to force a value. The
  wizard default and example tfvars now default to private (`false`). New
  `grafana_private_dns_zone_ids` variable accepts hub-supplied DNS zone ids.

### Notes
- Portal **Pin to Grafana** stops working when private (the portal cannot reach
  a private IP), and the SSO/OAuth endpoint still traverses the public network.
  Access to a private workspace requires VNet line-of-sight (VPN / bastion /
  peered network).
- Backward compatible: configs that set `grafana_public_access = true` keep
  public access.

## [1.14.0] - 2026-07-25

### Fixed
- **`enable_flux`, `enable_dapr` and `enable_cost_analysis` are now actually
  implemented.** These toggles were declared as variables, prompted by the
  wizard, and rendered into tfvars, but nothing consumed them — setting them
  `true` was a no-op (confirmed on a live cluster: no Flux/Dapr extensions and
  cost analysis off despite the tfvars). They are now wired end-to-end in the
  region module: Flux (`microsoft.flux`) and Dapr (`Microsoft.Dapr`) are
  deployed as `azurerm_kubernetes_cluster_extension` resources (new
  `modules/region/platform-extensions.tf`), and Cost Analysis flows into the
  AKS module via `metrics_profile.cost_analysis.enabled` (requires the
  Standard/Premium SKU the accelerator already provisions). All three remain
  opt-in (default `false`), so existing deployments are unaffected.

## [1.13.3] - 2026-07-25

### Fixed
- **App Gateway ingress auto-wire now installs Traefik reliably.** The CD
  "Wire ingress controller into App Gateway" step deployed the internal Traefik
  controller by passing a multi-line script inline to `az aks command invoke
  --command`, which only reliably executes its first line. As a result Traefik
  was never installed, its internal LoadBalancer never received a private IP,
  and the step exhausted all 30 "internal LB IP not ready" polling attempts
  before emitting a manual-wiring warning. The script is now written to a file
  and uploaded with `--file`, so it runs verbatim on the cluster — Traefik
  installs, the internal LB IP is discovered, and the App Gateway backend pool
  is wired automatically.

## [1.13.2] - 2026-07-25

### Fixed
- **Defender for Containers plan no longer fails when already enabled.** When
  `enable_defender_for_containers_plan` is set but the subscription-wide
  Microsoft Defender for Containers plan is already on the Standard tier
  (enabled by a prior run, another landing zone, or Azure Policy), the apply
  used to fail with `a resource with the ID ".../Microsoft.Security/pricings/Containers" already exists`.
  The composition now performs a pre-flight read of the current pricing tier via
  an `azapi_resource` data source and only creates/manages the plan when the
  subscription is still on Free — gracefully skipping an existing plan instead
  of erroring. Safer than importing for shared subscriptions: the landing zone
  never adopts or reverts a plan another team owns.

## [1.13.1] - 2026-07-25

### Changed
- **Microsoft Defender wizard prompts relabeled** to Microsoft's terminology so
  the two toggles are unmistakably different: `enable_defender` now reads
  "Deploy the Microsoft Defender for Containers **sensor** on this cluster
  (agent-based runtime threat protection)", and
  `enable_defender_for_containers_plan` reads "Enable the **subscription-wide**
  Microsoft Defender for Containers **plan** (agentless discovery + vulnerability
  assessment, billed)".

### Added
- **Planning checklist** now covers `enable_defender_for_containers_plan` (was
  missing) plus the v1.13.0 App Gateway ingress decisions `ingress_controller`
  (istio | traefik | manual dropdown) and `appgw_tls_key_vault_secret_id`, each
  with a clickable Microsoft Learn reference link so the customer can decide and
  record them before deployment.

## [1.13.0] - 2026-07-25

### Added
- **Application Gateway can now act as the AKS ingress without AGIC or
  Application Gateway for Containers.** The WAF_v2 Application Gateway is
  configured as a reverse proxy in front of an **internal** in-cluster ingress
  controller. A new `ingress_controller` variable selects `istio` (managed
  Istio internal ingress gateway), `traefik` (deployed internally by the CD
  pipeline), or `manual` (bring your own internal controller). nginx is
  intentionally not offered because the ingress-nginx project is being retired.
  The wizard prompts for this whenever Application Gateway WAF is chosen, and
  auto-selects `istio` when the service mesh is enabled.
- **Dynamic backend wiring (no hard-coded IP).** For `istio`/`traefik` the CD
  pipeline discovers the internal load balancer private IP at deploy time
  (`az aks command invoke`) and writes it to the App Gateway backend pool
  (`az network application-gateway address-pool update`). Traefik is installed
  internally via Helm through command invoke, which works on private clusters.
- **Optional Key Vault TLS.** Setting `appgw_tls_key_vault_secret_id` activates
  an HTTPS:443 listener (certificate read from Key Vault via the AKS
  user-assigned identity) plus an HTTP->HTTPS 301 redirect. Left empty, the
  gateway serves HTTP:80 only.
- **`ingress_next_steps` output** summarising DNS, TLS and controller follow-up
  actions after deployment.

### Changed
- **App Gateway configuration is now Terraform-authoritative.** The previous
  placeholder (empty backend pool, AGIC-oriented broad `ignore_changes`) is
  replaced by a real ingress backend pool, health probe and routing rules.
  Terraform now owns listeners/routing/TLS/probe and ignores only the backend
  pool addresses (managed by the CD auto-wire step).

## [1.12.0] - 2026-07-25

### Changed
- **System node pool is now reserved for AKS-managed add-ons.** The system
  (default) node pool is tainted with `CriticalAddonsOnly=true:NoSchedule` by
  default so application workloads schedule onto the dedicated user pool. This
  is exposed as a new `system_node_pool.node_taints` field (default
  `["CriticalAddonsOnly=true:NoSchedule"]`); set it to `[]` to opt out.
  `CriticalAddonsOnly=true:NoSchedule` is the only taint Azure permits on the
  default system pool. **Upgrade note:** on an existing cluster the next
  `terraform apply` adds the taint, which reschedules any non-tolerating pods
  currently running on the system pool onto the user pool.
- **Managed Grafana public network access is now configurable.** The rendered
  tfvars previously hardcoded `grafana_public_access = true`. It is now driven
  by a `grafana_public_access` wizard prompt / `inputs.yaml` value, defaulting
  to `true` for backward compatibility. Set it to `false` to require private
  access — make sure private connectivity to Grafana is in place first.

### Added
- **Subscription-wide Microsoft Defender for Containers plan toggle.** The
  wizard now prompts for `enable_defender_for_containers_plan` and renders it to
  tfvars. When enabled it raises the subscription Defender for Containers plan
  to Standard and turns on agentless discovery + container-registry
  vulnerability assessment (full Defender for Cloud coverage). Defaults to
  `false` so the accelerator never silently enables subscription-wide billing;
  the per-cluster in-cluster security-monitoring agent (`enable_defender`) is
  unchanged.

## [1.11.0] - 2026-07-25

### Fixed
- **OIDC federated credentials now cover GitHub's immutable subject claim.**
  GitHub is rolling out immutable OIDC subject claims that embed the numeric
  org/repo database IDs
  (`repo:<org>@<orgId>/<repo>@<repoId>:environment:<env>`). Repositories
  enrolled in that rollout no longer match the legacy name-based federated
  credential, so the workload pipeline's `terraform init` failed to
  authenticate to the state backend with
  `AADSTS700213: No matching federated identity record found`. The bootstrap
  now registers **both** subjects for each pipeline environment — the legacy
  name-based subject (`repo:<org>/<repo>:environment:<env>`) and the immutable
  ID-based subject — so authentication succeeds whether or not the organization
  is enrolled. Federated-credential creation moved from the `azure` module to
  the composition root (`bootstrap/alz/github/main.tf`) so the subject can
  reference the repository's numeric id; the existing `fc-github-plan` /
  `fc-github-apply` credentials are adopted in place via `moved` blocks and the
  new `fc-github-plan-immutable` / `fc-github-apply-immutable` credentials are
  added alongside them.

## [1.10.0] - 2026-07-25

### Added
- **Team-owned bootstrap Terraform state (`bootstrap_state_backend`).** The
  bootstrap/foundation state location is now a team decision in `inputs.yaml`.
  The default (`local`) keeps the state on the machine that runs
  `Deploy-AKSLandingZone` and **never** pushes it to a storage account. Teams
  that want a shared remote backend set `bootstrap_state_backend: remote`
  (optionally overriding `bootstrap_state_resource_group` /
  `bootstrap_state_storage_account` / `bootstrap_state_container`) and own the
  network + RBAC path to that backend.

### Fixed
- **BUG-D — no more impossible bootstrap-state migration.** Earlier releases
  always tried to migrate the bootstrap state into the azurerm backend right
  after apply. When the state storage account is private-only
  (`publicNetworkAccess=Disabled`, e.g. under governance policies that force
  it), migrating from an operator workstation failed with
  `403 AuthorizationFailure`, and a stale `backend.tf` left in the module cache
  could later break `terraform init` with a DNS `no such host` after the
  account was destroyed. Keeping bootstrap state `local` by default removes the
  implicit migration entirely. The workload/cluster state is unaffected — it
  still uses the remote backend via the GitHub Actions CI/CD pipeline.

### CI
- **`cd-template` workflow hardening.** Steps and summaries are now
  action-aware (a `destroy` run no longer reports "Apply Complete"), provider
  downloads force HTTP/1.1 (`GODEBUG=http2client=0`), and `terraform init` is
  retried up to three times to survive transient HTTP/2 `PROTOCOL_ERROR` from
  the GitHub release-assets CDN on self-hosted runners.

## [1.9.1] - 2026-07-11

### Fixed
- **Key Vault name no longer blocks destroy-then-redeploy under restrictive governance.** The
  3-character KV suffix was previously a deterministic
  `md5(subscription_id + name_prefix)` hash. In policy-governed subscriptions
  the `keyvault purge` operation is denied by policy, so a soft-deleted vault
  would collide with a fresh apply for up to 90 days (until the scheduled
  purge date), producing `VaultAlreadyExists`. The suffix is now a
  `random_string` (length 3, lowercase alphanumeric) keyed on the region
  `name_prefix`: it is generated once on first apply, preserved in Terraform
  state across re-plans, and regenerates on a fresh apply after
  `terraform destroy` — sidestepping the soft-delete window entirely.
  Cross-tenant and cross-subscription uniqueness is preserved (each fresh
  deployment gets an independent random). Adds `hashicorp/random ~> 3.6` to
  the region module's required providers.

## [1.9.0] - 2026-07-11

### Changed
- **Private endpoints for Key Vault and ACR are now ON by default** in
  standalone deployments. `enable_private_endpoints` default flipped
  `false` → `true` to align with Microsoft Well-Architected Framework and
  Cloud Adoption Framework guidance for AKS landing zones. Fresh standalone
  deployments now automatically provision the private-endpoints subnet,
  create AVM-managed private endpoints on Key Vault
  (`Azure/avm-res-keyvault-vault/azurerm`) and ACR
  (`Azure/avm-res-containerregistry-registry/azurerm`), disable both public
  endpoints, and create + link the `privatelink.vaultcore.azure.net` and
  `privatelink.azurecr.io` private DNS zones to the spoke VNet. Corp/hub
  topology behaviour is unchanged (private DNS zones continue to come from
  the hub).

  > **Operational note:** with the new default, the ACR public endpoint is
  > unreachable. Image builds and pushes must run on a runner with network
  > line of sight to the registry (the built-in self-hosted ACI runner in
  > the VNet is the intended path). Set `enable_private_endpoints = false`
  > in your tfvars if you must keep public endpoints so a GitHub-hosted
  > runner can push images.

  > **Upgrade note:** existing standalone deployments that upgrade will see
  > Terraform plan the creation of the PE subnet, both private endpoints,
  > both private DNS zones + VNet links, and an in-place update to disable
  > the public endpoints. Apply on your in-VNet self-hosted runner.

### Fixed
- **Globally-unique Key Vault name.** `key_vault_name` now always appends a
  3-character subscription-scoped MD5 hash
  (`kv-<name_prefix>-<hash>`, 24-char max), so redeploys and other tenants
  cannot collide with a previously-taken name (soft-deleted Key Vaults in
  other subscriptions/tenants are invisible but still block the name
  globally).
- **`New-BackendMigration` no longer re-locks the tfstate storage account.**
  When governance policies auto-flip a storage account's
  `publicNetworkAccess` to `Disabled`, the bootstrap composition previously
  captured that flipped state as the "original" and re-applied it after
  migration. The captured-state check is now driven by config
  (`use_private_networking` / `topology`) rather than the current firewall
  state, and a defensive post-migration restore explicitly re-enables public
  access when the config says the state SA should be reachable.
- **ACI self-hosted runner registers reliably.** The runner container now
  receives a short-lived registration token from
  `POST /orgs/{org}/actions/runners/registration-token` instead of a raw
  PAT, and `GH_RUNNER_URL` points at the org (`https://github.com/{org}`)
  rather than a specific repo. Fixes the runner-registration 404 loop.

## [1.8.0] - 2026-06-15

### Added
- **Private endpoints for Key Vault and ACR in standalone deployments.** New
  `enable_private_endpoints` toggle (default `false`). When enabled in a
  standalone (no-hub) deployment, Terraform creates the private-endpoints
  subnet, disables public network access on Key Vault and ACR, and — when no
  external `*_private_dns_zone_ids` are supplied — creates and links the
  `privatelink.vaultcore.azure.net` and `privatelink.azurecr.io` private DNS
  zones to the spoke VNet so the cluster resolves both services to their private
  IPs. Corp/hub topology is unchanged (private DNS zones continue to come from
  the hub). Default `false` preserves the existing standalone behaviour (public
  endpoints with deny-by-default ACLs and `AcrPull` RBAC).

  > **Operational note:** enabling this makes the **ACR public endpoint
  > unreachable**. CI jobs that build and push images must run on a runner with
  > network line of sight to the registry (e.g. the self-hosted runner in the
  > VNet); a GitHub-hosted runner can no longer push images. Key Vault and ACR
  > control-plane (Terraform) operations are unaffected.

## [1.7.0] - 2026-06-16

### Added
- **Configurable node pool OS SKU.** `system_node_pool.os_sku` and
  `user_node_pool.os_sku` (default `"Ubuntu"`) let you choose the node OS image
  (e.g. `AzureLinux`). The default preserves existing clusters unchanged.
- **Application Gateway Ingress Controller (AGIC).** New `enable_agic` toggle.
  When `enable_app_gateway` and `enable_agic` are both `true`, the WAF_v2
  Application Gateway is wired to AKS as an in-cluster ingress via the AGIC
  add-on, and the AGIC managed identity is granted `Contributor` on the gateway
  and `Reader` on the resource group. Previously the gateway was deployed but
  never connected to AKS (empty backend pool, no ingress controller).
- **Subscription-wide Defender for Containers plan.** New
  `enable_defender_for_containers_plan` toggle (default `false`). Raises the
  subscription Defender for Containers plan to `Standard` with agentless
  discovery and registry vulnerability assessment, clearing Defender for Cloud
  "partial coverage". **This is subscription-wide and billed** — opt-in only.

### Fixed
- **Private cluster honored in standalone topologies.** `private_cluster_enabled
  = true` previously had no effect unless a hub was attached (corp/online), so
  standalone clusters silently stayed public. The private API server is now
  provisioned in any topology (paired with API Server VNet Integration).
- **Backup instance RBAC propagation race.** AKS backup instance creation could
  fail with `UserErrorExtensionMSIMissingPermissionsOnBackupStorageLocation`
  because data-plane role assignments are eventually consistent. A `time_sleep`
  now lets the storage role assignments propagate before the backup instance is
  created.

## [1.6.3] - 2026-06-15

### Fixed
- **AKS backup storage account failed to create** with
  `403 Key based authentication is not permitted on this storage account`
  (`KeyBasedAuthenticationNotPermitted`). The backup storage account is AAD-only
  (`shared_access_key_enabled = false`), but the `azurerm` provider defaulted to
  key-based authentication when polling the blob service data plane. Set
  `storage_use_azuread = true` on the provider so all storage data-plane
  operations use Azure AD, and added a deployer `Storage Blob Data Contributor`
  role assignment that the backup container now depends on so it can be created
  over the AAD data plane.

## [1.6.2] - 2026-06-14

### Fixed
- **AKS backup storage account failed to create** with
  `NetworkAclsValidationFailure: SubnetsHaveNoServiceEndpointsConfigured`. The
  AVM virtual-network module's subnet object exposes
  `service_endpoints_with_location` (not `service_endpoints`), so the previously
  added key was silently ignored and the `Microsoft.Storage` service endpoint
  was never applied to the AKS node subnets. Corrected the attribute and added
  an explicit `depends_on = [module.spoke_vnet]` on the backup storage account so
  the in-place subnet update completes before the account's network ACL is
  validated.

## [1.6.1] - 2026-06-14

### Added
- **Azure Backup for AKS — complete managed solution.** `enable_backup` now
  provisions the Microsoft-recommended topology instead of a non-functional
  bare extension: a hardened blob datastore storage account + container, a
  dedicated snapshot resource group, a Backup Vault (system-assigned identity),
  the native `azurerm_kubernetes_cluster_extension` backup extension (AAD-based,
  shared keys disabled), an AKS Trusted Access role binding
  (`Microsoft.DataProtection/backupVaults/backup-operator`), all required vault /
  extension / cluster identity role assignments, a default **daily backup policy
  (30-day operational retention)**, and a backup instance protecting the cluster.
  New variables: `backup_retention_days` (30), `backup_storage_replication_type`
  (`ZRS`), `backup_vault_redundancy` (`LocallyRedundant`),
  `backup_vault_soft_delete` (`Off`). The AKS node subnets gain a
  `Microsoft.Storage` service endpoint when backup is enabled so the extension
  can reach the default-deny datastore. Requires the deploying identity to be
  able to create role assignments (Owner/User Access Administrator) when enabled.

### Fixed
- **Grafana provisioning failed on apply** — Azure Managed Grafana Standard SKU
  retired major version 11, so the previous `grafana_major_version` default of
  `"11"` caused `azurerm_dashboard_grafana` to fail. Default bumped to `"12"`.
- **AKS backup extension never installed** — the previous AzAPI extension was
  configured with only `credentials.tenantId` and no `backupStorageLocation`,
  so every apply with `enable_backup = true` failed with a missing
  `configuration.backupStorageLocation.bucket` error. Replaced by the complete
  managed solution above.

## [1.6.0] - 2026-06-14

### Added
- **`enable_agc` (Application Gateway for Containers)** — a new regional ingress
  option alongside `enable_app_gateway`. When enabled, Terraform provisions a
  dedicated delegated subnet (delegated to
  `Microsoft.ServiceNetworking/trafficControllers`) plus its NSG in every region
  (`agc` key added to `subnet_address_prefixes` /
  `secondary_subnet_address_prefixes`, default `10.10.24.0/24` / `10.20.24.0/24`).
  Follows the "managed by ALB Controller" model: the in-cluster ALB Controller
  (which you install separately) creates and manages the AGC `trafficControllers`
  resource and associates it with the subnet — Terraform provisions the network
  infrastructure only. The delegated subnet ID is surfaced via the new
  `agc_subnet_id` (primary) and `agc_subnet_ids` (per-region map) outputs. The
  interactive wizard exposes an `Enable Application Gateway for Containers (ALB)
  subnet?` toggle (default `false`) and an `agc` subnet prefix prompt.
- **`-PatFromKeyVault <vaultName>`** on `Deploy-AKSLandingZone` (with
  `-PatSecretName` / `-RunnerPatSecretName`, defaulting to `github-pat` /
  `github-runners-pat`) — resolves GitHub PATs from an Azure Key Vault at
  run-time into `TF_VAR_github_personal_access_token` and
  `TF_VAR_github_runners_personal_access_token` via the new
  `Resolve-KeyVaultPats` helper. Values are masked in logs.
- **`-OidcOnly`** on `Deploy-AKSLandingZone` — PAT-less mode for the GitHub
  provider. Clears the PAT `TF_VAR`s and validates either GitHub App
  credentials (`GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID`,
  `GITHUB_APP_PEM_FILE` → `TF_VAR_github_app_*`) or a `GH_TOKEN` /
  `GITHUB_TOKEN` environment token. The wizard skips its PAT prompts in this
  mode. The bootstrap `github` provider now uses a conditional `token` plus a
  `dynamic "app_auth"` block, with new `github_app_id`,
  `github_app_installation_id`, `github_app_pem_file` variables.
  `-PatFromKeyVault` and `-OidcOnly` are mutually exclusive.
- **`azd` wrapper** — a thin `azure.yaml` at the repo root with a
  `preprovision` hook (pwsh, interactive) that imports `ALZ.AKS.psd1` and runs
  `Deploy-AKSLandingZone`, plus a no-op `infra/main.tf` shim so `azd up` works.
  See `ALZ.AKS/docs/scenarios-and-options.md` ("Using azd").

### Fixed
- **Multi-region App Gateway public IP idempotency** — `azurerm_public_ip.app_gateway`
  exhibited a spurious `ip_tags` ForceNew diff on refresh, causing Terraform to
  attempt to replace the public IP while it was still attached to the App
  Gateway (`400 PublicIPAddressCannotBeDeleted`). Added
  `lifecycle { ignore_changes = [ip_tags] }`. Discovered and fixed during the
  live multi-region failover drill (2026-06-12).
- **AcrPull role-assignment race** — the per-region `aks_acr_pull` role
  assignment referenced a deterministic ACR resource id, so it had no
  dependency on the actual ACR resource and could be created before the
  registry existed (`404`). Moved the assignment to root `main.acr.tf`
  (`for_each = module.region`, scoped to `module.acr.resource_id`, principal =
  each region's kubelet identity), which preserves a real dependency and breaks
  the region↔acr cycle. Discovered and fixed during the live multi-region
  failover drill (2026-06-12).
- **BUG-D (state migration on private storage)** — the apply path's
  post-apply `terraform init -migrate-state` no longer fails with
  `403 AuthorizationFailure` on regulated topologies whose bootstrap state
  storage account is private (`publicNetworkAccess: Disabled`,
  `defaultAction: Deny`). The cmdlet now records the SA's original network
  posture, opens a temporary firewall window for the migration (60s settle,
  one-shot 90s retry on 403), and **restores the original posture in a
  `finally` block**. Regulated cloud verification still pending.
- **Destroy path — orphaned RG shells** — `-Action destroy` now verifies and
  retries deletion of the state and identity resource groups (polls up to
  3 min, then a final synchronous `az group delete --yes`) and reports an
  ERROR only if an RG is still present (e.g. a resource lock), instead of
  leaving the fire-and-forget `--no-wait` deletions unverified.
- **Wizard — stopped prompting for the unused L7 ingress subnet.** The
  interactive wizard asked for both `subnet_address_prefix_app_gateway` and
  `subnet_address_prefix_agc` during networking (Decision 5), before the ingress
  option was even chosen (Decision 11). It now prompts only for the subnet of the
  ingress actually selected (Application Gateway WAF *or* App Gateway for
  Containers); the unused key keeps its default so the rendered tfvars stays
  valid. Matches the Terraform behaviour, which only creates the subnet whose
  `enable_*` flag is set.
- **Terraform — fixed invalid `moved` block for `aks_acr_pull`.** `moved.tf`
  tried to relocate `azurerm_role_assignment.aks_acr_pull` into
  `module.region["primary"]`, but that role assignment is intentionally kept at
  the root module (`for_each = module.region`) to avoid a region↔ACR dependency
  cycle. `terraform plan` failed with *"Moved object still exists."* The block
  now re-keys the existing instance into `azurerm_role_assignment.aks_acr_pull["primary"]`
  — the correct state migration after adding `for_each` (no destroy/recreate).
- **Bootstrap preflight — now registers the required subscription *feature*.**
  The preflight registered resource *providers* (`az provider register`) but not
  subscription *features* (`az feature register`), which is a separate mechanism.
  A fresh bootstrap subscription without
  `Microsoft.Network/AllowBringYourOwnPublicIpAddress` failed late in apply with
  `SubscriptionNotRegisteredForFeature` when creating the NAT-gateway public IP.
  The preflight now registers that feature idempotently per target subscription,
  waits for propagation, and re-registers `Microsoft.Network` so it takes effect.

## [1.5.2] - 2026-06-14

### Fixed
- **CI/CD — generated workload repo is now self-contained; CD no longer fails
  with "workflow was not found".** The bootstrap creates only the workload repo,
  but its generated `ci.yaml` / `cd.yaml` referenced reusable workflows in a
  separate `<service>-templates` repo that the Terraform path never created
  (and which is restricted on free org plans). The workload repo now ships its
  own `ci-template.yaml` / `cd-template.yaml` and the caller workflows reference
  them locally (`uses: ./.github/workflows/<name>-template.yaml`), removing the
  cross-repo dependency entirely.
- **CI/CD — `cd-template.yaml` referenced variables the bootstrap never set.**
  It read `secrets.ARM_CLIENT_ID/TENANT_ID/SUBSCRIPTION_ID` and
  `vars.BACKEND_RESOURCE_GROUP/STORAGE_ACCOUNT/CONTAINER/KEY`, none of which
  Terraform provisions. It now uses the same convention as the (working) CI
  template: `vars.AZURE_CLIENT_ID/TENANT_ID/SUBSCRIPTION_ID` for OIDC auth and
  `vars.BACKEND_AZURE_RESOURCE_GROUP_NAME/_STORAGE_ACCOUNT_NAME/`
  `_STORAGE_ACCOUNT_CONTAINER_NAME` for backend init, plus new `runner_label`
  (default `self-hosted`) and `backend_key` (default `aks-landing-zone.tfstate`)
  inputs so plan/apply share state and honour the runner choice.

## [1.5.1] - 2026-06-14

### Fixed
- **Release packaging — bootstrap composition was missing from the install
  zip.** The release workflow zipped only `./ALZ.AKS`, so `install.ps1`
  extracted a version cache (`~/.alz-aks/<version>/`) without the Terraform
  bootstrap. `Deploy-AKSLandingZone` then failed at apply time with
  `Bootstrap root not found: …\<version>\bootstrap\alz\github`. The workflow now
  bundles `./bootstrap` alongside the module, so the composition (and its
  `modules/azure`, `modules/github`, `modules/resource_names`) ships in the
  release and resolves automatically — no full-repo clone required. Only
  git-tracked files are packaged, so no local state, logs, or rendered tfvars
  leak into the asset.

## [1.4.0] - 2026-05-24

GA release. Builds on rc5 with three fixes from live E2E validation and
ships standalone (single + multi-region) and hub-and-spoke (single region)
as supported topologies. Regulated and multi-region hub-and-spoke remain
tech preview — see `KNOWN-ISSUES.md`.

### Fixed
- **BUG-B (data loss, hub-and-spoke)** — `Deploy-AKSLandingZone -Action refresh`
  on a `hub_and_spoke` deployment no longer pushes a tfvars file with empty
  `hub_vnet_resource_id`, `hub_vnet_name`, `hub_vnet_resource_group_name`,
  and `hub_firewall_private_ip` values. The refresh path now initialises the
  hub composition workspace and reads its outputs before re-rendering the
  workload tfvars, exactly as the apply path does. Eliminates the
  apply↔refresh content ping-pong of `terraform/aks-landing-zone.auto.tfvars`.
- **BUG-E (silent drift-bypass)** — `Get-WorkloadRepoFileContent` now
  distinguishes a 404 from an empty file (`size: 0`). An empty managed file
  that the operator hand-edited is classified as `[hand-edited]` instead of
  `[add]`, which routes it through the hand-edit safety gate.
- **BUG-F (refresh drift gate)** — resolved as a side effect of BUG-E. With
  empty hand-edited files correctly classified as `hand-edited`, the existing
  drift gate in the refresh path blocks the run and prints the affected
  filenames unless `-Force` is supplied.

### Validation
- S1 (single_region_baseline / standalone) — 8/8 gates pass.
- S2 (single_region_baseline / hub_and_spoke) — 8/8 gates pass post-fix.
- S2.5 (multi_region_baseline / standalone) — 8/8 gates pass.

### Known limitations (deferred to v1.4.1+)
- Multi-region hub-and-spoke (S4) — tech preview only. Not in GA validation
  matrix for v1.4.0.
- Regulated scenarios (S3, S5) — blocked by BUG-D (private-endpoint state
  storage account not reachable from operator workstation). Tech preview.

## [1.4.0-rc5] - 2026-05-23

### Added
- **Re-run contract is now defined and enforced.** Previously, re-running
  `Deploy-AKSLandingZone -Action apply` against an existing env would silently
  overwrite any operator hand-edits to the rendered files in the workload repo
  (`terraform/*.tf`, `.github/workflows/{ci,cd}.yaml`, `terraform/aks-landing-zone.auto.tfvars`,
  `.gitignore`). The behaviour was undocumented and unsafe.

- **`-DryRun` switch** (valid with `-Action apply` and `-Action refresh`).
  Renders templates locally, fetches the current workload-repo content via
  `gh api`, and prints a per-file drift report classifying each managed file
  as `add` / `unchanged` / `update-managed` / `hand-edited`. Exits before
  touching terraform or the repo. Use to preview what a re-run would do.

- **`-Action refresh`**. Re-renders templates + tfvars and pushes only the
  managed files to the workload repo via
  `terraform apply -target=module.github.github_repository_file.this`.
  Skips Entra app, federated creds, state SA, and RBAC bootstrap (those are
  idempotent on a full apply but add several minutes per re-run). Requires a
  previously-applied env. Honours `-DryRun` and `-Force`.

- **`-Force` switch** (valid with `-Action apply|refresh`). Overrides the
  hand-edit safety check so a re-run can intentionally discard operator edits.

- **Hand-edit safety check.** Before `terraform apply` runs on an existing
  env, the cmdlet compares the current workload-repo content against
  terraform state for each `github_repository_file.this[<path>]` entry.
  If any file's repo content differs from state (operator edited it directly),
  the apply is blocked with an error listing the divergent files and the
  remediation: either move the edits into `ALZ.AKS/templates/` and re-run
  without `-Force`, or re-run with `-Force` to overwrite the operator edits.
  Greenfield applies skip this check (state map is empty, every file is an `add`).

### Changed
- `-Action` parameter accepts a new value: `'refresh'`. Validation messages
  for `-StateBackup`, `-DryRun`, and `-Force` updated to reflect the expanded
  action set.
- Help text for `Deploy-AKSLandingZone` expanded to document the re-run
  contract, the four file-status classifications, and which paths in the
  workload repo are managed vs operator-owned.

### Documentation
- README adds a **Re-run contract** section listing managed file paths,
  what `-Action apply` / `refresh` does on a re-run, the hand-edit policy,
  and a worked example of `-DryRun` + `-Action refresh`.
- `ALZ.AKS/docs/day2-runbook.md` adds §7 "Re-run contract" covering all
  four file-status classifications and the operator workflow for safe
  template changes.
- `KNOWN-ISSUES.md` removes the obsolete "Re-run contract" pre-GA row.
- `GAPS.md` §C marks idempotency / re-run contract items as shipped.

### Verified
- Param validation tests (rc5: 4/4 new guards passing).
- Full live cycle on `swedencentral` standalone env: greenfield apply →
  `-DryRun` shows 0 diffs → operator edit via `gh api` → `-DryRun` shows
  1 `hand-edited` → `-Action refresh` (no `-Force`) blocked correctly →
  `-Action refresh -Force` reconciles → `-DryRun` shows 0 diffs again →
  destroy clean.

## [1.4.0-rc4] - 2026-05-23

State recovery feature: when the remote terraform state in the bootstrap
backend gets corrupted, deleted, or otherwise diverges from reality, you can
now repair it without leaving the cmdlet.

### Added
- `-Action import` on `Deploy-AKSLandingZone`. Pushes a known-good terraform
  state file to the remote azurerm backend for the resolved environment. No
  new cmdlet — same single entry point.
- `-StateBackup <path>` parameter. Explicit path to the source state file to
  push. Only valid with `-Action import`. When omitted, the cmdlet auto-
  discovers an `errored.tfstate` left behind in the bootstrap composition by
  a failed apply or destroy.
- Always re-discovers the state RG and storage account on import (never trusts
  on-disk `backend.tf`), then re-grants `Storage Blob Data Contributor` to the
  operator with a 30s propagation wait — same self-heal shape proven in the
  rc3 destroy path. Falls through to a clear "the backend storage account is
  gone" error when the state RG truly doesn't exist anymore.
- Pre-push validation: the source file must parse as JSON and contain
  `version`, `terraform_version`, and `resources` before any backend mutation.
- Post-push verification: aborts with an explicit error if `terraform state
  list` returns zero after the push.
- Workspace handling: selects the per-env workspace if it exists, creates it
  if it doesn't (the whole point of recovery is to repopulate state).
- Auto-cleans the local `errored.tfstate` after a successful push so the file
  doesn't get re-picked-up on a future run.

### Verified
End-to-end on `swedencentral` against the standalone topology:
1. Fresh apply → 45 resources, state migrated to azurerm backend (serial 48).
2. `terraform state pull` → captured 32-resource good state (49 instances).
3. Uploaded an empty serial-1 state to the remote blob via `az storage blob
   upload --overwrite`, breaking the prior stale lease first. Confirmed
   `terraform state list` returned 0 (remote corrupted).
4. `Deploy-AKSLandingZone -Action import -StateBackup good.tfstate -AutoApprove
   -SkipPreflight` → discovered state SA, granted RBAC, init, workspace select,
   pushed state, post-verify reported 49 instances restored, banner printed.
5. `Deploy-AKSLandingZone -Action destroy -AutoApprove -SkipPreflight` against
   the recovered state → workload repo destroyed, all 45 resources inside the
   state and identity RGs destroyed (only empty RG shells remained — same rc3
   self-referential-teardown limitation, not introduced by rc4).

### Parameter validation tests (all passing)
- `-StateBackup` with `-Action apply` → errors fast.
- `-Action import` with no source and no `errored.tfstate` → errors with
  remediation hint.
- `-Action import -StateBackup nonexistent.tfstate` → errors with "does not
  exist".
- `-Action import -StateBackup junk.txt` (non-JSON) → errors with JSON parse
  message.

## [1.4.0-rc3] - 2026-05-23

Bug-fix release for the `-Action destroy` path discovered during real-cloud
end-to-end validation. The rc2 destroy command went through the motions but
could silently report success without actually destroying anything; rc3 makes
the destroy path honest and recovers from terraform's self-referential
backend-teardown.

### Fixed
- **`-Action destroy` now renders `terraform.tfvars.json` before invoking
  `terraform destroy`.** rc2 skipped the render entirely on destroy, which
  caused terraform to fail with `Error: No value for required variable` (the
  PATs and `repository_files` map are still evaluated during destroy).
- **`-Action destroy` no longer reports false-positive success when the target
  workspace is missing.** rc2 logged a warning and fell through to destroy
  whatever workspace happened to be active (typically `default`, which
  contained nothing) and then printed the "Teardown Complete" banner. rc3
  hard-aborts with a clear error if the per-env workspace is not present.
- **`-Action destroy` aborts cleanly when the workspace state has zero
  tracked resources** instead of running a no-op destroy and claiming success.
- **`-Action destroy` recognises terraform's self-referential teardown error
  (404 / "Failed to persist state to backend" / "Error releasing the state
  lock") and treats it as a successful destroy.** This is expected when the
  bootstrap composition manages its own remote state storage account: after
  the SA is destroyed, terraform cannot save final state back to it and
  returns a non-zero exit code, even though every tracked resource was
  destroyed.
- **`-Action destroy` self-heals an operator missing `Storage Blob Data
  Contributor` on the remote state SA** (idempotent grant + 30 s propagation
  sleep) when the destroy is invoked from a different machine than the one
  that ran apply.
- **`-Action destroy` self-heals a stale `backend.tf` on disk** that points
  at a different environment's storage account, by re-discovering the target
  env's state RG + SA from Azure and rewriting the file before init.

### Verified end-to-end (real cloud, swedencentral, `aksapplz-standalone`)
- Fresh apply → 45 resources created; state migrated to fresh remote SA.
- `-Action destroy -AutoApprove` → all 45 resources destroyed (incl. workload
  GitHub repo, federated identities, managed identities, both bootstrap RGs).
  Self-referential teardown error correctly classified as expected success.

## [1.4.0-rc2] - 2026-05-23

API hardening release. Replaces the previously-planned standalone
`Remove-AKSLandingZone` cmdlet with an `-Action` switch on the existing
`Deploy-AKSLandingZone` cmdlet, mirroring the upstream Azure Landing Zone
Accelerator pattern (`Deploy-Accelerator -Action apply|destroy`).

### Added
- **`-Action apply|plan|destroy`** parameter on `Deploy-AKSLandingZone`.
  - `apply` (default) — unchanged behaviour.
  - `plan` — equivalent to legacy `-PlanOnly`.
  - `destroy` — self-contained teardown of the bootstrap (spoke) composition
    followed by the hub composition (when `topology=hub_and_spoke`). Requires
    `-InputConfigPath` or `-Environment` to locate the existing config; prompts
    for the literal word `destroy` unless `-AutoApprove` is passed.
- New examples in the cmdlet help block for `-Action destroy` invocation
  (interactive and non-interactive).

### Changed
- **`-PlanOnly` is now an alias** for `-Action plan` (back-compat preserved).
  Combining `-PlanOnly` with `-Action destroy` is rejected with a clear error.
- **README maturity matrix** — destroy row flipped from "planned" to "shipped",
  pointing at the new `-Action destroy` flow.
- **KNOWN-ISSUES.md** — removed the destroy pre-GA item (now implemented).
- **Day-2 runbook §5** — manual 4-step destroy procedure replaced with the
  one-liner `Deploy-AKSLandingZone -Action destroy`. The "destroy workload
  first via the CD pipeline" guidance is preserved.

### Notes
- The cmdlet only destroys the bootstrap-owned resources (generated GitHub
  repo, GHA federated identities, bootstrap storage account, hub VNet/firewall).
  Spoke Azure resources owned by the workload repo (AKS, App Gateway, NAT GW,
  etc.) must still be destroyed by the workload repo's CD `destroy.yaml`
  workflow first — otherwise the bootstrap-destroy will delete the workflow
  itself before it can clean up those resources.

## [1.4.0-rc1] - 2026-05-23

First release candidate of the v1.4.0 line. Focus is **publish-readiness**:
automated end-to-end test harness, governance files, static-analysis gate,
and documented preview-grade limitations.

### Added
- **End-to-end scenario test harness** under `ALZ.AKS/tests/e2e/` (12 scenarios x 4 levels):
  - **L1 render** (`Scenarios.L1.Tests.ps1`) — 112/204 assertions, ~1.5 s.
  - **L2 terraform plan** (`Scenarios.L2.Tests.ps1`) — 60/60 plans across 12 scenarios in ~13 min.
  - **L3 apply+destroy** (`Scenarios.L3.Tests.ps1`) — gated by `ALZ_AKS_E2E_APPLY=1`; sandbox apply with always-on AfterAll destroy.
  - **L4 wizard end-to-end** (`Scenarios.L4.Tests.ps1`) — gated by `ALZ_AKS_E2E_L4=1`; mirrors repo to sandbox, drives `Deploy-AKSLandingZone -PlanOnly` (default) or `-AutoApprove` (full).
- **Scenario matrix (12)**: 3 topologies (standalone/spoke/hub_and_spoke) x 2 scenarios (baseline/regulated) + 4 multi-region variants + feature-flag minimal + feature-flag maximal.
- **PR gate workflow** `.github/workflows/test-scenarios.yml` — L1 single job + L2 matrix of 12 (OIDC, parallel 6, plan only).
- **L3 / L4 manual workflows** `.github/workflows/test-scenarios-l3.yml` and `test-scenarios-l4.yml` — `workflow_dispatch` with comma-separated or `all` scenario selector, environment-gated.
- **Governance files**: `LICENSE` (MIT), `SECURITY.md`, `KNOWN-ISSUES.md`, `CODE_OF_CONDUCT.md`.
- **Static analysis gate** `.github/workflows/static-analysis.yml` — PSScriptAnalyzer + tfsec + checkov (informational; advisory severities only).

### Changed
- **Module version**: `1.3.0` -> `1.4.0` with `Prerelease = 'rc1'`. Manifest `LicenseUri` / `ProjectUri` corrected to the real repo URL.
- **`.gitignore`** extended for ad-hoc `*.tfvars` and `terraform.tfstate*` at repo root + `bootstrap/alz/hub/*.log` (covers destroy logs).

### Fixed
- Working tree hygiene — removed eight stale `*.log` and `*.tfvars` debug artefacts from prior manual runs.
- **Invalid CIDR in scenario templates**: `templates/scenarios/*.tfvars` shipped `aks_user_nodes = "10.10.1.0/22"`, which Azure rejects with `InvalidCIDRNotation` (a /22 must align on a /22 boundary). Corrected to `10.10.16.0/22` (matches what every e2e YAML already uses). **Surfaced by the new L3 harness on the first real cloud apply** — exactly the class of bug L3 exists to catch. Added `ALZ.AKS/tests/Cidr.Alignment.Tests.ps1` (32 cases, runs in <1 s) so the same class of bug fails at unit-test time before any cloud spend.

### Known limitations (see [KNOWN-ISSUES.md](KNOWN-ISSUES.md))
- **L3 cloud verification**: `01-standalone-baseline` apply (~11 min) + destroy (~10 min) verified on Azure 2026-05-23. Remaining 11 scenarios scheduled before GA.
- L4 wizard automated tests are wired but the first real cloud run is part of the rc1 sign-off; until then treat the wizard apply path as preview.
- Several Section-C items (destroy cmdlet, state recovery, OIDC-only secrets, azd wrapper, PSGallery publish) are deferred to v1.5.0.
- Upstream `log_analytics` AVM module emits a deprecated-arg warning during plan (non-blocking).
- GitHub Free-plan orgs cannot enforce environment reviewer rules on private repos.

## [1.3.0] - 2026-05-23

### Added
- **`hub_and_spoke` topology** (greenfield). When `topology=hub_and_spoke`, `Deploy-AKSLandingZone` now provisions a brand-new hub VNet in the connectivity subscription as a first phase, then runs the existing spoke bootstrap with the freshly-minted hub values wired in automatically — no second invocation, no manual tfvars editing.
  - New Terraform module: `bootstrap/modules/azure_hub/` (resource group + VNet + `AzureFirewallSubnet` + optional Azure Firewall, policy, and zonal public IP).
  - New composition root: `bootstrap/alz/hub/` (separate Terraform state; targets the connectivity subscription).
  - Wizard adds the new topology as a third option, then prompts for `hub_vnet_address_space`, `firewall_subnet_address_prefix`, `deploy_firewall`, and `firewall_sku_tier` (Standard | Premium).
  - Preflight accepts `spoke | standalone | hub_and_spoke` and validates required fields per topology.
  - After hub apply, the cmdlet captures `hub_vnet_resource_id`, `hub_vnet_name`, `hub_vnet_resource_group_name`, `hub_firewall_private_ip` from `terraform output -json` and populates `$config` so the existing spoke render is unchanged.

### Fixed
- **Remote-state migration 403** (`AuthorizationPermissionMismatch`) during `terraform init -migrate-state`. The cmdlet now grants the signed-in operator *Storage Blob Data Contributor* on the bootstrap storage account it just created and waits 30 s for AAD propagation before running the migration. Idempotent — treats "role already exists" as informational. Closes the v1.2.0 known issue.

### Notes
- Azure Firewall **Basic** SKU is intentionally not supported in v1.3 (it requires a Management subnet + Management IP). Use `Standard` or `Premium`.
- Hub composition uses Terraform local state (per-env workspace) for now; remote-state migration for the hub will follow the same pattern as the spoke in a future release.

## [1.2.0] - 2026-05-23

### Added
- **Multi-environment support** for `Deploy-AKSLandingZone`.
  - New `-Environment <name>` parameter (1-8 lowercase alphanumeric chars).
  - When supplied and `-InputConfigPath` is omitted, the cmdlet resolves `config/inputs.<env>.yaml` automatically; falls through to the wizard if it does not exist.
  - Wizard fallback now writes `config/inputs.<env>.yaml` + `config/aks-landing-zone.<env>.tfvars` when `-Environment` is set.
  - `-Environment` overrides `environment_name` in the loaded config so all resource names stay in sync.
- **Per-environment Terraform state isolation** via Terraform workspaces.
  - After `terraform init`, the cmdlet runs `terraform workspace select <env>` and creates a new workspace on demand. Each environment now has its own `terraform.tfstate.d/<env>/` directory inside `bootstrap/alz/github/`.
- End-to-end cloud test against the **standalone** topology in `swedencentral` (sub `029039e3-…`, org `abengtss-max-org`). 27 bootstrap resources created successfully, workload repo + 2 GitHub Actions environments provisioned.

### Changed
- **Breaking — repo & team naming.** `bootstrap/alz/github/locals.tf` now derives:
  - `version_control_system_repository`  = `{{service_name}}-{{environment_name}}`
  - `version_control_system_team`        = `{{service_name}}-{{environment_name}}-approvers`
  Existing deployments will see a destroy/recreate of the GitHub repo + team on the next apply. Use the v1.1.0 template if you must preserve an existing repo name.
- Banner version string now reads from `$script:ScriptVersion` (no longer hardcoded `1.0.0`).

### Known Issues
- Remote-state migration (`terraform init -migrate-state`) fails with **403 AuthorizationPermissionMismatch** because the local Azure principal does not have *Storage Blob Data Contributor* on the storage account that bootstrap just created. Local state remains authoritative and the bootstrap is still considered successful. Workaround: assign the role to the operator (or to the `apply` MI) and re-run with `-SkipPreflight`. Will be fixed in a follow-up by adding the role assignment to the bootstrap composition.

## [1.1.0] - 2026-05-23

### Added
- **Standalone topology** option for the AKS landing zone.
  - New wizard prompt (Decision 2.5): choose `spoke` (peer to an existing ALZ hub, default) or `standalone` (no hub, NAT gateway egress only).
  - When `standalone` is selected, the wizard skips Decisions 3 (connectivity subscription) and 4 (hub VNet / hub firewall).
  - Workload Terraform now derives the internal `is_corp` flag from `hub_vnet_resource_id != ""`, so the route table, UDR, and spoke↔hub VNet peerings are only created when a hub is configured.
- New `topology` field in `config/inputs.yaml` (defaults to `spoke` for back-compat).
- Excel checklist: new row **Decision 0c — topology** with a dropdown (`spoke` / `standalone`).
- Topology coverage in [README.md](README.md), [ALZ.AKS/docs/deployment-checklist.md](ALZ.AKS/docs/deployment-checklist.md) and [ALZ.AKS/docs/scenarios-and-options.md](ALZ.AKS/docs/scenarios-and-options.md).
- Pre-flight validation:
  - Fails fast if `topology` is missing or not one of `spoke` / `standalone`.
  - Enforces all hub_* / `connectivity_subscription_id` fields are set when `topology: spoke`.
  - Auto-clears any leftover hub_* values and warns when `topology: standalone`.

### Changed
- `Deploy-AKSLandingZone` is the only exported cmdlet; the legacy `Invoke-AKSLandingZoneTerraform` name is no longer exported.
- When invoked without `-InputConfigPath`, `Deploy-AKSLandingZone` now runs the interactive wizard by default.

### Notes
- Older `inputs.yaml` files without a `topology` field are still accepted; pre-flight defaults them to `spoke` and emits a warning.

## [1.0.0] - 2026-05-22

### Added
- Initial public version. Single cmdlet `Deploy-AKSLandingZone` renders the `bootstrap/alz/github/` Terraform composition and applies it. End-to-end tested against a spoke landing zone in `swedencentral`.
