@{
    # Module manifest for ALZ.AKS
    # AKS Application Landing Zone Accelerator - PowerShell Module

    # Script module file associated with this manifest
    RootModule        = 'ALZ.AKS.psm1'

    # Version number of this module
    ModuleVersion     = '1.18.0'

    # ID used to uniquely identify this module
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'

    # Author of this module
    Author            = 'Platform Team'

    # Company or vendor of this module
    CompanyName       = 'abengtss-max'

    # Copyright statement for this module
    Copyright         = '(c) 2026 abengtss-max. All rights reserved.'

    # Description of the functionality provided by this module
    Description       = 'AKS Application Landing Zone Accelerator. Deploys a production-ready AKS cluster into an existing Azure Landing Zone using a Terraform composition (AVM-first), following the upstream ALZ accelerator pattern. Run Deploy-AKSLandingZone to bootstrap.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.0'

    # Functions to export from this module
    FunctionsToExport = @('Deploy-AKSLandingZone')

    # Cmdlets to export from this module
    CmdletsToExport   = @()

    # Variables to export from this module
    VariablesToExport  = @()

    # Aliases to export from this module
    AliasesToExport    = @()

    # Private data to pass to the module specified in RootModule
    PrivateData = @{
        PSData = @{
            # Tags applied to this module for PSGallery discovery
            Tags         = @('Azure', 'AKS', 'Kubernetes', 'Landing-Zone', 'Accelerator', 'Terraform', 'ALZ', 'Infrastructure-as-Code')

            # A URL to the license for this module
            LicenseUri   = 'https://github.com/abengtss-max/aksapplz/blob/main/LICENSE'

            # A URL to the main website for this project
            ProjectUri   = 'https://github.com/abengtss-max/aksapplz'

            # ReleaseNotes of this module
            ReleaseNotes = @'
## 1.18.0
- Feature (opt-in management access - Azure Bastion + hardened jumpbox VM, default off): a new `enable_management_jumpbox` flag (default `false`) provisions an Azure Bastion host and a hardened, **no-public-IP** Ubuntu 22.04 jumpbox VM for operating a PRIVATE cluster and its private endpoints from inside the spoke VNet. Login is via **Microsoft Entra ID** over Bastion (AADSSHLoginForLinux; password auth disabled); the VM has a **system-assigned managed identity** granted `Azure Kubernetes Service Cluster User` (and `Azure Kubernetes Service RBAC Reader` when `enable_azure_rbac = true`), auto-shutdown to cap idle cost, encryption-at-host, locked-down NSGs (jumpbox allows SSH only from the Bastion subnet; the `AzureBastionSubnet` carries the required Bastion rule set so it satisfies the ALZ "Deny-Subnet-Without-Nsg" policy), and operator tooling (az CLI, kubectl, kubelogin, helm) pre-installed via cloud-init. Two new subnets (`jumpbox` `10.10.25.0/27`, `AzureBastionSubnet` `10.10.26.0/26`; `10.20.x` in the secondary region) are created **only** when the flag is on - a standard deployment provisions ZERO of these resources and is completely unaffected. Intended for **standalone** deployments; in ALZ/corp topologies the connectivity hub provides centralized Bastion/VPN, so leave it off there. New tunables: `jumpbox_vm_size` (`Standard_B2s`), `jumpbox_admin_username` (`azureuser`), `bastion_sku` (`Standard`), `jumpbox_auto_shutdown_time`/`_timezone`. Surfaced in the interactive wizard, generated tfvars/config, the planning checklist, the configuration reference, scenarios-and-options, and a new Day-2 "Management access via Bastion + jumpbox" runbook section. Closes issue #29.

## 1.17.1
- Fix (durable plan-vs-apply CD identity RBAC for ingress auto-wire): a fresh rebuild could still leave the App Gateway backend pool empty because the region module granted `Azure Kubernetes Service RBAC Reader` only to `data.azurerm_client_config.current.object_id`, which in the split plan/apply pipeline resolves at PLAN time to the PLAN managed identity and is frozen in the saved tfplan - while the CD wire step's `az aks command invoke` runs in the APPLY job as the APPLY managed identity, whose kubectl was therefore silently Forbidden. The bootstrap composition now emits BOTH the plan and apply managed identity principal (object) IDs into a terraform-generated `terraform/cd-identities.auto.tfvars` (auto-loaded alongside the rendered tfvars), and the region module grants the RBAC Reader role to EACH of them - the role assignment moved from `count` to `for_each` over a new `cd_identity_principal_ids` list variable (plumbed root -> region module). Standalone `terraform apply` runs where the list is empty fall back to `data.azurerm_client_config.current.object_id`, so behaviour is unchanged outside the pipeline. This makes the Istio ingress auto-wiring genuinely hands-off on every fresh rebuild, with no manual `az role assignment create` step.
- Fix (smooth destroy - transient 409 conflicts on the private monitoring/Grafana teardown): `terraform destroy` could fail with two concurrency errors. (1) Deleting the AMPLS private endpoint's `monitor-dns-zone-group` returned `409 AnotherOperationInProgress` because the backup blob private endpoint REUSES the same shared `privatelink.blob.core.windows.net` zone and their private DNS zone groups were deleted concurrently - the backup blob private endpoint now has an explicit `depends_on` on the AMPLS private endpoint so the two blob-zone endpoints tear down sequentially (no-op when the AMPLS endpoint is absent). (2) Deleting the Grafana managed private endpoint `mpe-amw-*` returned `409 ConflictInProcessing` ("Operation conflict occurred for workspace ... Please try again later") because the Grafana control plane serializes per-workspace operations - the managed private endpoint (`azapi_resource`) now retries on the transient `ConflictInProcessing` / `AnotherOperationInProgress` responses until the workspace is free. Destroy and re-apply are now smooth and idempotent with no manual cleanup.
- Fix (destroy re-runs are safe - no more "Saved plan is stale"): the CD destroy path no longer applies the saved destroy plan artifact in the apply job. If a teardown stopped partway on a transient error, the state moved on and re-running the job failed with `Saved plan is stale`. The apply job now runs `terraform destroy -auto-approve` (recomputed from live state) for the destroy action instead of `terraform apply <saved-plan>`, so re-running the failed job - or dispatching a fresh destroy - always resumes the teardown idempotently. The apply (create/update) path still applies the exact saved plan the approver reviewed, and the environment approval gate still governs destroy.

- Feature (expose the cluster autoscaler profile - opt-in, defaults unchanged): the AKS cluster-autoscaler profile is now tunable via a new `auto_scaler_profile` object variable, plumbed root -> region module -> AVM `auto_scaler_profile`. It defaults to `null`, so clusters keep the native AKS autoscaler defaults and existing deployments are completely unaffected (no behavioural change). The accelerator deliberately does NOT ship an opinionated profile: the profile is cluster-wide (it also affects the system pool) and the right cost-vs-performance values are workload-specific, which matches Microsoft's own "optimize the cluster autoscaler profile" guidance (a per-workload trade-off, not a default). Customers set only the keys they want to override in tfvars; `expander` is validated to one of `least-waste | most-pods | priority | random`. Instead of picking values for the customer, the accelerator now EXPOSES and EXPLAINS them across three layers: a dedicated docs page (Advanced > Cluster autoscaler tuning) with the trade-off, AKS defaults, Microsoft's example cost/performance profiles and copy-paste tfvars snippets; a Configuration reference row; a Day-2 runbook cross-link; and a single optional awareness row in the planning checklist. Closes roadmap issue #13.

## 1.16.2
- Fix (Azure Backup for AKS deployed in `ProtectionError`): the hardened, AAD-only backup datastore (`shared_access_key_enabled = false`, and public network access disabled where the platform mandates private connectivity) left the backup instance unhealthy on a fresh deploy for two reasons, both now fixed. (1) The backup extension is now installed with `configuration.backupStorageLocation.config.useAAD = "true"`, so its in-cluster data mover authenticates to blob storage with the user-assigned extension identity (already granted `Storage Blob Data Contributor`) instead of defaulting to storage-account-key mode and trying to list the (disabled) account keys - the previous behaviour reported the `default` BackupStorageLocation as unavailable with `UserErrorExtensionIdentityNotFound`. (2) The region module now provisions a blob private endpoint (`pe-<storage account>`, subresource `blob`) for the backup storage account in the spoke private-endpoint subnet and derives the account's `public_network_access_enabled` from the private-endpoint posture; without it, public-access-disabled + ignored VNet service endpoints blocked the data mover with `403 AuthorizationFailure`. The blob `privatelink.blob.core.windows.net` zone is reused from the Azure Monitor (AMPLS) setup when present, self-managed otherwise, or hub-supplied in corp topology, and the backup container create is ordered behind the private endpoint.

## 1.16.1
- Fix (ingress auto-selection): the `ingress_controller` output is now DERIVED from the deployment topology instead of echoing the raw variable. It resolves to `istio` automatically whenever the managed Istio internal ingress gateway is present (`enable_app_gateway && enable_istio_service_mesh && istio_internal_ingress_gateway`), otherwise it falls back to the customer-selected value (`manual`). This prevents an inconsistent config where the Istio internal ingress gateway is enabled but `ingress_controller` was left at `manual`, which silently skipped the CD auto-wiring and left the App Gateway backend pool empty. The wiring itself is implemented in the pipeline and remains fully dynamic - it discovers the Istio internal ingress gateway private LoadBalancer IP at run time and sets it on the backend pool, so no IP is ever hard-coded (customers bring their own address space).
- Fix (Defender for Containers completeness): when `enable_defender_for_containers_plan` is set, the subscription plan now enables the FULL extension set - `AgentlessVmScanning` and `ContainerSensor` were added alongside `AgentlessDiscoveryForKubernetes` and `ContainerRegistriesVulnerabilityAssessments`. Previously only the latter two were configured, so opting into the plan left Defender for Cloud reporting the sensor/agentless-scanning coverage as "partial". The completed set yields full container protection.
- Fix (automatic ingress wiring requires Kubernetes RBAC for the deployer): with Azure RBAC for Kubernetes enabled and local accounts disabled, the CD identity's `az aks command invoke` kubectl was silently forbidden to read the Istio internal ingress gateway service, so the auto-wiring never resolved an IP (it only worked when an operator wired it by hand with their own cluster-admin access). The region module now grants the deploying identity the `Azure Kubernetes Service RBAC Reader` role on the cluster (gated on `enable_azure_rbac`, using `data.azurerm_client_config.current.object_id`), and the CD wire step now surfaces the in-cluster kubectl error instead of swallowing it. Ingress wiring is now genuinely hands-off for customers - the pipeline discovers and sets the IP with no manual step.

## 1.16.0
- Change (ingress model simplified - managed Istio or bring-your-own): the App Gateway ingress path no longer installs an open-source controller for you. `ingress_controller` is now `istio` or `manual` (the `traefik` value and the CD's Helm/Traefik install are removed). For `istio` the accelerator sets up the managed Istio internal ingress gateway AND the CD auto-wires its private IP into the App Gateway backend pool. For `manual` the accelerator delivers the baseline (cluster + App Gateway + empty backend pool) and hands off: the customer installs and wires their own open-source ingress controller (guidance in the `ingress_next_steps` output and the CD job summary). This removes Helm from the pipeline entirely and keeps a single, understandable framework per path.
- Change (Managed Prometheus + Grafana private): when private endpoints are in use (corp topology, or standalone with `enable_private_endpoints = true`) and Managed Prometheus is enabled, the Azure Monitor workspace and its Prometheus data collection endpoint are no longer reachable over the public internet. The module creates an Azure Monitor Private Link Scope (AMPLS) with a private endpoint (`pe-ampls-*`, subresource `azuremonitor`), adds the Prometheus DCE and the Log Analytics workspace as scoped services, sets `public_network_access_enabled = false` on the workspace and DCE, self-manages the five Azure Monitor `privatelink.*` DNS zones (or consumes hub-supplied ids via the new `monitor_private_dns_zone_ids` variable), and creates a Grafana managed private endpoint (`groupIds = ["prometheusMetrics"]`) so managed Grafana keeps querying Prometheus over the private path. Public deployments (no private endpoints) are unchanged.
- Fix/perf (ingress wiring speed + reliability): when `istio` is selected, the CD "Wire ingress controller into App Gateway" step now discovers the internal LoadBalancer IP inside a SINGLE `az aks command invoke` (one in-cluster wait loop) instead of up to 30 separate poll invokes. Each invoke pays a ~15-20s command-pod scheduling cost, so the old design could take ~12 minutes and, on a transient inner failure, gave up silently (the inner command's non-zero exit was masked because `az aks command invoke` returns 0 and `-o none` hid the output). The step now surfaces failures and typically completes in ~1 minute.

## 1.15.1
- Fix (deployment reliability): the Flux and Dapr cluster extensions (added in 1.14.0) now depend on the whole AKS module, so they no longer install concurrently with the AVM module's post-create system agent-pool update (`azapi_update_resource.default_agent_pool`). That concurrency caused a 409 `EtagMismatch` / `PutAgentPool_FailedPrecondition` ("Another operation is in progress", https://aka.ms/aks/aksoperationpreempted) that failed the whole apply on fresh deployments with GitOps/Dapr enabled, leaving later resources (e.g. the ACR private endpoint) uncreated and ingress unwired. The extensions are also serialized against each other (Dapr waits for Flux) so at most one long-running cluster extension operation is in flight at a time.

## 1.15.0
- Change (Grafana private by default): Managed Grafana now follows Microsoft security guidance (disable public network access + private endpoint). When private endpoints are in use (corp/hub topology, or standalone with the default `enable_private_endpoints = true`), Grafana `public_network_access_enabled` is turned off and a Grafana private endpoint is provisioned in the private-endpoints subnet with a self-managed `privatelink.grafana.azure.com` DNS zone linked to the spoke VNet (hub-supplied zone ids honored in corp). `grafana_public_access` is now a nullable override derived from the private-endpoint posture when unset; the wizard default and example tfvars default to private (false). New `grafana_private_dns_zone_ids` variable. Note: portal Pin-to-Grafana stops working when private and SSO still uses the public network; access requires VNet line-of-sight. Backward compatible: setting `grafana_public_access = true` keeps public access.

## 1.14.0
- Fix (feature wiring): `enable_flux`, `enable_dapr` and `enable_cost_analysis` were exposed as toggles (wizard prompt + rendered tfvars) but were never consumed by the Terraform - setting them true did nothing. They are now fully wired in the region module: Flux (`microsoft.flux`) and Dapr (`Microsoft.Dapr`) are provisioned as `azurerm_kubernetes_cluster_extension` resources (new `platform-extensions.tf`), and Cost Analysis is wired through the AKS module's `metrics_profile.cost_analysis.enabled` (requires the Standard/Premium SKU, which the accelerator already uses). Passed through `main.region.tf` and declared in the region module. Backward compatible: all three default to false. Discovered during live-cluster validation where the toggles were true in tfvars but Flux/Dapr extensions were absent and cost analysis was off.

## 1.13.3
- Fix (App Gateway ingress auto-wire): the CD step that deploys the internal Traefik ingress controller now uploads its Helm install script with `az aks command invoke --file` instead of passing a multi-line script inline via `--command`. The inline multi-line form was unreliable (only the first line reliably executed), so Traefik was never actually installed, its internal LoadBalancer never got an IP, and the wire step spun through all 30 "internal LB IP not ready" attempts before giving up with a manual-wiring warning. With the script uploaded as a file it runs verbatim, Traefik installs, the internal LB IP is discovered, and the App Gateway backend pool is wired automatically.

## 1.13.2
- Fix (Defender for Containers plan): enabling `enable_defender_for_containers_plan` no longer fails the whole deployment when the subscription-wide Microsoft Defender for Containers plan is ALREADY on the Standard tier (enabled by a prior run, another landing zone, or Azure Policy). The composition now reads the current `Microsoft.Security/pricings/Containers` tier first and only creates/manages the plan when the subscription is still on Free, leaving an existing plan untouched instead of erroring with "a resource with the ID ... already exists". This is safer for shared subscriptions than importing, because the landing zone never adopts or reverts a plan another team owns.

## 1.13.1
- Docs/UX (Microsoft Defender naming): the two Defender wizard prompts now use Microsoft's terminology and are clearly distinct — `enable_defender` = "Deploy the Microsoft Defender for Containers SENSOR on this cluster (agent-based runtime threat protection)"; `enable_defender_for_containers_plan` = "Enable the SUBSCRIPTION-WIDE Microsoft Defender for Containers PLAN (agentless discovery + vulnerability assessment, billed)".
- Planning checklist: added the previously-missing `enable_defender_for_containers_plan` row and the App Gateway ingress decisions `ingress_controller` (istio | traefik | manual dropdown) and `appgw_tls_key_vault_secret_id`, each with a clickable Microsoft Learn reference link so customers can decide and document them up front.

## 1.13.0
- Feature (Application Gateway as AKS ingress, no AGIC / no AGC): the WAF_v2 Application Gateway can now act as a plain reverse proxy in front of an INTERNAL in-cluster ingress controller. New `ingress_controller` variable selects `istio` (managed Istio internal ingress gateway), `traefik` (deployed internally by the CD pipeline), or `manual` (bring your own internal controller). nginx is intentionally not offered as the ingress-nginx project is being retired. The wizard prompts for this whenever Application Gateway WAF is chosen; Istio is auto-selected when the mesh is enabled.
- Feature (dynamic backend wiring, no hard-coded IP): for `istio`/`traefik` the CD pipeline discovers the internal load balancer private IP at deploy time (`az aks command invoke`) and sets it on the App Gateway backend pool (`az network application-gateway address-pool update`). Terraform ignores changes to the backend pool addresses so the two never fight. Traefik is installed internally via Helm through command invoke (works on private clusters).
- Feature (optional TLS): set `appgw_tls_key_vault_secret_id` to a Key Vault certificate secret ID to activate an HTTPS:443 listener plus an HTTP->HTTPS 301 redirect. The gateway reads the certificate with the AKS user-assigned identity (already Key Vault Secrets User). Left empty, the gateway serves HTTP:80 only (backward compatible).
- Change (App Gateway config is now Terraform-authoritative): the placeholder AGIC-oriented config (empty backend, broad `ignore_changes`) is replaced by a real ingress backend pool, health probe and routing; only the backend pool addresses are left to the CD auto-wire step. New `ingress_next_steps` output prints DNS/TLS/controller guidance after deployment.

## 1.12.0
- Hardening (system node pool): the system (default) node pool is now tainted with `CriticalAddonsOnly=true:NoSchedule` by default, reserving it for AKS-managed add-ons so application workloads schedule onto the dedicated user pool. Exposed as `system_node_pool.node_taints` (default `["CriticalAddonsOnly=true:NoSchedule"]`); set to `[]` to opt out. NOTE: on an existing cluster the next apply adds the taint, which reschedules any non-tolerating pods currently on the system pool onto the user pool.
- Feature (Defender): the SUBSCRIPTION-WIDE Microsoft Defender for Containers plan (agentless discovery + registry vulnerability assessment) is now selectable from the wizard and rendered to tfvars via `enable_defender_for_containers_plan`. Defaults to `false` so the accelerator never silently enables subscription-wide billing; the in-cluster `enable_defender` security-monitoring agent is unchanged.
- Feature (Grafana): Managed Grafana public network access is now a wizard/inputs.yaml choice (`grafana_public_access`) instead of a hardcoded `true` in the rendered tfvars. Defaults to `true` for backward compatibility; set `false` to require private access (ensure private connectivity to Grafana is in place first).

## 1.11.0
- Fix (OIDC): the bootstrap now registers BOTH the legacy name-based and the new GitHub immutable OIDC subject for each pipeline environment. GitHub is rolling out immutable subject claims that embed the numeric org/repo database IDs (repo:<org>@<orgId>/<repo>@<repoId>:environment:<env>); repositories enrolled in that rollout no longer match the legacy name-based federated credential, which caused pipeline terraform init to fail with AADSTS700213 "No matching federated identity record found". Federated credential creation moved from module.azure to the composition root so the subject can reference the repository's numeric id; the legacy plan/apply credentials are preserved in place via moved blocks, and immutable variants (fc-github-plan-immutable / fc-github-apply-immutable) are added alongside them. Authentication now succeeds whether or not the organization is enrolled in immutable subjects.

## 1.10.0
- Feature: The bootstrap/foundation Terraform state is now team-owned. By default (bootstrap_state_backend: local) the bootstrap state stays on the machine that runs Deploy-AKSLandingZone and is NEVER migrated to a storage account. Teams that want a shared remote backend opt in with bootstrap_state_backend: remote (optionally overriding bootstrap_state_resource_group / bootstrap_state_storage_account / bootstrap_state_container) and own the network + RBAC path to it.
- Fix (BUG-D): removes the implicit, often-impossible post-apply state migration to a private state storage account. Under governance policies that force publicNetworkAccess=Disabled, migrating the bootstrap state from an operator workstation would fail with 403 AuthorizationFailure (and a stale backend.tf could later break init with a DNS "no such host" after teardown). Keeping bootstrap state local by default eliminates this entirely; the workload/cluster state continues to use the remote backend via CI/CD as before.
- CI: cd-template workflow now labels steps/summaries per action (a destroy run no longer reports "Apply Complete"), forces HTTP/1.1 for provider downloads (GODEBUG=http2client=0) and retries terraform init up to 3 times to survive transient HTTP/2 PROTOCOL_ERROR on self-hosted runners.

## 1.8.0
- Feature: Private endpoints for Key Vault and ACR in standalone (no-hub) deployments via enable_private_endpoints (default false). When enabled the module creates the private-endpoints subnet, turns OFF public network access on Key Vault and ACR, and (when no external private DNS zone ids are supplied) creates and links privatelink.vaultcore.azure.net and privatelink.azurecr.io to the spoke VNet so the cluster resolves both to their private IPs. Corp/hub topology is unchanged (zones still come from the hub). NOTE: enabling this makes the ACR public endpoint unreachable - CI image builds/pushes must run on a runner with network line of sight to the registry (self-hosted runner in the VNet); GitHub-hosted runners can no longer push.

## 1.7.0
- Feature: Node pool OS SKU is now configurable via system_node_pool.os_sku / user_node_pool.os_sku (default "Ubuntu" - no change to existing clusters). Supports AzureLinux and other AKS-supported SKUs.
- Feature: Application Gateway Ingress Controller (enable_agic). When enable_app_gateway and enable_agic are both true, the WAF_v2 Application Gateway is wired to AKS as an in-cluster ingress (AGIC add-on) and the AGIC managed identity is granted Contributor on the gateway and Reader on the resource group. Previously the gateway was deployed but never connected to AKS (empty backend pool).
- Feature: Subscription-wide Microsoft Defender for Containers plan (enable_defender_for_containers_plan, default false). Raises the subscription Defender for Containers plan to Standard with agentless discovery and registry vulnerability assessment, clearing Defender for Cloud "partial coverage". SUBSCRIPTION-WIDE and BILLED - opt-in only.
- Fix: Private cluster is now honored independently of corp/online connectivity. private_cluster_enabled = true previously had no effect in standalone deployments (the cluster stayed public); it now provisions a private API server in any topology (paired with API Server VNet Integration).
- Fix: AKS backup instance creation could fail with UserErrorExtensionMSIMissingPermissionsOnBackupStorageLocation due to eventually-consistent data-plane RBAC. A time_sleep now lets the storage role assignments propagate before the backup instance is created.

## 1.6.3
- Fix: AKS backup storage account creation failed with "Key based authentication is not permitted on this storage account" (403). The storage account is AAD-only (shared_access_key_enabled = false), so the azurerm provider now uses Azure AD for storage data-plane operations (storage_use_azuread = true) and the backup container waits on a deployer Storage Blob Data Contributor role assignment.

## 1.6.2
- Fix: AKS backup storage account failed with SubnetsHaveNoServiceEndpointsConfigured. The AVM subnet object uses service_endpoints_with_location (not service_endpoints); the node-subnet Microsoft.Storage endpoint is now applied correctly and the storage account waits for the subnet update via depends_on.

## 1.6.1
- Azure Backup for AKS (enable_backup): complete managed solution (Backup Vault, hardened storage datastore, extension, Trusted Access, daily 30-day policy and backup instance) replacing the non-functional bare extension
- Fix: Grafana major version default 11 -> 12 (Azure retired v11 for the Standard SKU)

## 1.6.0
- enable_agc, -PatFromKeyVault, -OidcOnly, azd integration; feature-registration in bootstrap preflight

## 1.5.0
- Application Gateway for Containers (enable_agc): delegated subnet + NSG per region (ALB Controller managed)
- Customer documentation site (MkDocs Material) published to GitHub Pages
- Versioned GitHub Releases with install.ps1 entrypoint and -Release pinning (default latest)
- Non-blocking newer-release check in Deploy-AKSLandingZone (-SkipUpdateCheck)
- Multi-region GA: Front Door / Traffic Manager, Fleet Manager, geo-replicated ACR

## 1.0.0
- Initial release
- Interactive wizard matching ALZ Deploy-Accelerator pattern
- Azure Verified Modules for AKS, VNet, ACR, Key Vault, App Gateway, Grafana
- Two-phase deployment: interactive config generation + execution
- OIDC/Federated credentials for GitHub Actions
- Self-hosted runner support
'@

            # Prerelease string — empty for a GA release.
            Prerelease = ''
        }
    }
}
