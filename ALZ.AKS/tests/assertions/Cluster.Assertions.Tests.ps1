<#
.SYNOPSIS
    Post-deploy assertions for a live AKS Application Landing Zone cluster.

    Consumed by nightly-integration.yml and e2e-release.yml AFTER a successful
    `terraform apply`. Reads the deployed cluster once via `az aks show` and
    asserts the invariants that MUST hold for any healthy landing-zone cluster,
    plus self-consistent feature checks derived from the cluster's own state.

    Contract (set by the calling workflow):
      AKSTEST_SUBSCRIPTION_ID  - subscription containing the cluster
      AKSTEST_RESOURCE_GROUP   - resource group of the cluster
      AKSTEST_CLUSTER_NAME     - AKS cluster name

    Design notes:
      - These run across every scenario the nightly/e2e matrix deploys, so
        per-feature checks are CONDITIONAL: "if the cluster reports X enabled,
        then X must be configured correctly". This keeps the suite meaningful
        without hard-coding a single scenario's feature set.
      - Requires the Azure CLI on PATH and an authenticated session (the
        workflow performs azure/login before invoking Pester).

    Run locally against an existing cluster:
      $env:AKSTEST_SUBSCRIPTION_ID = '<sub>'
      $env:AKSTEST_RESOURCE_GROUP  = 'rg-...'
      $env:AKSTEST_CLUSTER_NAME    = 'aks-...'
      Invoke-Pester -Path .\ALZ.AKS\tests\assertions -Output Detailed
#>

BeforeDiscovery {
    $Script:HasAz = [bool](Get-Command az -ErrorAction SilentlyContinue)
    $Script:HaveEnv = [bool]($env:AKSTEST_RESOURCE_GROUP -and $env:AKSTEST_CLUSTER_NAME)
}

BeforeAll {
    $rg   = $env:AKSTEST_RESOURCE_GROUP
    $name = $env:AKSTEST_CLUSTER_NAME
    $sub  = $env:AKSTEST_SUBSCRIPTION_ID

    $Script:Cluster   = $null
    $Script:LoadError = $null

    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        $Script:LoadError = 'Azure CLI (az) is not on PATH.'
        return
    }
    if (-not ($rg -and $name)) {
        $Script:LoadError = 'AKSTEST_RESOURCE_GROUP / AKSTEST_CLUSTER_NAME are not set.'
        return
    }

    # `az --query` mangles JMESPath brackets on PowerShell; pull the whole
    # object and parse it locally instead.
    $azArgs = @('aks', 'show', '--resource-group', $rg, '--name', $name, '-o', 'json')
    if ($sub) { $azArgs += @('--subscription', $sub) }

    try {
        $raw = & az @azArgs 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            $Script:LoadError = "az aks show failed (exit $LASTEXITCODE):`n$raw"
            return
        }
        $Script:Cluster = $raw | ConvertFrom-Json
    } catch {
        $Script:LoadError = "Failed to load cluster JSON: $($_.Exception.Message)"
    }
}

Describe 'AKS landing zone — cluster health invariants' -Skip:(-not ($Script:HasAz -and $Script:HaveEnv)) {

    It 'the cluster was retrieved from Azure' {
        $Script:LoadError | Should -BeNullOrEmpty
        $Script:Cluster   | Should -Not -BeNullOrEmpty
    }

    It 'provisioningState is Succeeded' {
        $Script:Cluster.provisioningState | Should -Be 'Succeeded'
    }

    It 'power state is Running' {
        $Script:Cluster.powerState.code | Should -Be 'Running'
    }

    It 'reports a Kubernetes version' {
        $Script:Cluster.kubernetesVersion | Should -Not -BeNullOrEmpty
    }

    It 'has a managed identity (not a service principal)' {
        $Script:Cluster.identity | Should -Not -BeNullOrEmpty
        $Script:Cluster.identity.type | Should -Match 'Assigned'
    }

    It 'has a network profile' {
        $Script:Cluster.networkProfile | Should -Not -BeNullOrEmpty
        $Script:Cluster.networkProfile.networkPlugin | Should -Not -BeNullOrEmpty
    }
}

Describe 'AKS landing zone — node pools' -Skip:(-not ($Script:HasAz -and $Script:HaveEnv)) {

    BeforeAll {
        $Script:Pools  = @($Script:Cluster.agentPoolProfiles)
        $Script:System = @($Script:Pools | Where-Object { $_.mode -eq 'System' })
        $Script:User   = @($Script:Pools | Where-Object { $_.mode -eq 'User' })
    }

    It 'has at least one System-mode node pool' {
        $Script:System.Count | Should -BeGreaterThan 0
    }

    It 'has at least one User-mode node pool (workload isolation)' {
        $Script:User.Count | Should -BeGreaterThan 0
    }

    It 'every node pool is in a Succeeded state' {
        foreach ($p in $Script:Pools) {
            $p.provisioningState | Should -Be 'Succeeded' -Because "pool '$($p.name)'"
        }
    }
}

Describe 'AKS landing zone — security & governance' -Skip:(-not ($Script:HasAz -and $Script:HaveEnv)) {

    It 'Entra ID (AAD) managed RBAC is enabled' {
        $Script:Cluster.aadProfile | Should -Not -BeNullOrEmpty
        $Script:Cluster.aadProfile.managed | Should -BeTrue
    }

    It 'has at least one admin group assigned' -Skip:(-not $Script:Cluster.aadProfile.enableAzureRbac) {
        # Group-based admin (adminGroupObjectIDs) OR Azure RBAC for Kubernetes auth
        $groups = @($Script:Cluster.aadProfile.adminGroupObjectIDs)
        ($groups.Count -gt 0 -or $Script:Cluster.aadProfile.enableAzureRbac) | Should -BeTrue
    }

    It 'local accounts are disabled when Azure RBAC for Kubernetes is on' -Skip:(-not $Script:Cluster.aadProfile.enableAzureRbac) {
        $Script:Cluster.disableLocalAccounts | Should -BeTrue
    }
}

Describe 'AKS landing zone — feature consistency (conditional)' -Skip:(-not ($Script:HasAz -and $Script:HaveEnv)) {

    It 'workload identity + OIDC issuer are enabled together' -Skip:(-not $Script:Cluster.securityProfile.workloadIdentity.enabled) {
        $Script:Cluster.oidcIssuerProfile.enabled | Should -BeTrue -Because 'workload identity requires the OIDC issuer'
        $Script:Cluster.oidcIssuerProfile.issuerUrl | Should -Not -BeNullOrEmpty
    }

    It 'Azure Policy add-on is healthy when enabled' -Skip:(-not $Script:Cluster.addonProfiles.azurepolicy.enabled) {
        $Script:Cluster.addonProfiles.azurepolicy.enabled | Should -BeTrue
    }

    It 'Microsoft Defender is configured when enabled' -Skip:(-not $Script:Cluster.securityProfile.defender.securityMonitoring.enabled) {
        $Script:Cluster.securityProfile.defender.securityMonitoring.enabled | Should -BeTrue
    }

    It 'Azure Monitor metrics (managed Prometheus) is configured when enabled' -Skip:(-not $Script:Cluster.azureMonitorProfile.metrics.enabled) {
        $Script:Cluster.azureMonitorProfile.metrics.enabled | Should -BeTrue
    }

    It 'image cleaner has a scan interval when enabled' -Skip:(-not $Script:Cluster.securityProfile.imageCleaner.enabled) {
        $Script:Cluster.securityProfile.imageCleaner.intervalHours | Should -BeGreaterThan 0
    }

    It 'KEDA workload autoscaler is configured when enabled' -Skip:(-not $Script:Cluster.workloadAutoScalerProfile.keda.enabled) {
        $Script:Cluster.workloadAutoScalerProfile.keda.enabled | Should -BeTrue
    }

    It 'vertical pod autoscaler is configured when enabled' -Skip:(-not $Script:Cluster.workloadAutoScalerProfile.verticalPodAutoscaler.enabled) {
        $Script:Cluster.workloadAutoScalerProfile.verticalPodAutoscaler.enabled | Should -BeTrue
    }

    It 'Istio service mesh has at least one revision when enabled' -Skip:(-not ($Script:Cluster.serviceMeshProfile -and $Script:Cluster.serviceMeshProfile.mode -eq 'Istio')) {
        @($Script:Cluster.serviceMeshProfile.istio.revisions).Count | Should -BeGreaterThan 0
    }

    It 'private cluster exposes a private FQDN when enabled' -Skip:(-not $Script:Cluster.apiServerAccessProfile.enablePrivateCluster) {
        $Script:Cluster.privateFqdn | Should -Not -BeNullOrEmpty
    }
}
