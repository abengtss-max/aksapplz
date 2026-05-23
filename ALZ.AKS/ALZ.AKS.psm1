# =============================================================================
# ALZ.AKS Module - AKS Application Landing Zone Accelerator
# =============================================================================
# This module provides the Deploy-AKSLandingZone (Terraform-based, recommended)
# and Deploy-AKSLandingZoneLegacy (legacy imperative bootstrap) functions, which
# mirror
# the Azure Landing Zone Accelerator (Deploy-Accelerator) pattern exactly.
#
# Usage:
#   Install-PSResource -Name ALZ.AKS
#   Deploy-AKSLandingZone
#   Deploy-AKSLandingZoneLegacy
#
# The module embeds all Terraform, workflow, and config templates internally.
# No repository cloning is needed — everything is generated in the target folder.
# =============================================================================

$script:ModuleRoot    = $PSScriptRoot
$script:TemplateRoot  = Join-Path $PSScriptRoot "templates"
$script:ScriptVersion = "1.3.0"

# =============================================================================
# Helper Functions (Private — not exported)
# =============================================================================

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("INFO","SUCCESS","WARNING","ERROR","INPUT REQUIRED")]
        [string]$Severity = "INFO"
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $color = switch ($Severity) {
        "INFO"           { "White"  }
        "SUCCESS"        { "Green"  }
        "WARNING"        { "Yellow" }
        "ERROR"          { "Red"    }
        "INPUT REQUIRED" { "Cyan"   }
    }
    Write-Host "[$ts] [$Severity] $Message" -ForegroundColor $color
}

function Show-Banner {
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║        AKS Application Landing Zone Accelerator            ║" -ForegroundColor Cyan
    Write-Host "  ║                    v$script:ScriptVersion                              ║" -ForegroundColor Cyan
    Write-Host "  ║                                                            ║" -ForegroundColor Cyan
    Write-Host "  ║  Deploys a production-ready AKS cluster into an existing   ║" -ForegroundColor Cyan
    Write-Host "  ║  Azure Landing Zone using the ALZ Accelerator pattern.     ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Test-SoftwareRequirements {
    Write-Log "Checking the software requirements for the Accelerator..."
    Write-Host ""

    $results = @()

    # PowerShell version
    $psVer = $PSVersionTable.PSVersion
    if ($psVer.Major -ge 7) {
        $results += [pscustomobject]@{ Result = "Success"; Details = "PowerShell version $psVer is supported." }
    } else {
        $results += [pscustomobject]@{ Result = "Failure"; Details = "PowerShell 7+ is required. Current: $psVer." }
    }

    # Git
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $results += [pscustomobject]@{ Result = "Success"; Details = "Git is installed." }
    } else {
        $results += [pscustomobject]@{ Result = "Failure"; Details = "Git is not installed." }
    }

    # Terraform
    if (Get-Command terraform -ErrorAction SilentlyContinue) {
        $tfVer = try { (terraform version -json 2>$null | ConvertFrom-Json).terraform_version } catch { "unknown" }
        $results += [pscustomobject]@{ Result = "Success"; Details = "Terraform is installed (version $tfVer)." }
    } else {
        $results += [pscustomobject]@{ Result = "Failure"; Details = "Terraform is not installed." }
    }

    # GitHub CLI
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        $results += [pscustomobject]@{ Result = "Success"; Details = "GitHub CLI (gh) is installed." }
    } else {
        $results += [pscustomobject]@{ Result = "Warning"; Details = "GitHub CLI (gh) is not installed. Required for bootstrap execution." }
    }

    # Environment variables (PATs). Token-1 is always required for bootstrap; token-2 only when
    # use_self_hosted_runners = true. ARM_SUBSCRIPTION_ID is auto-resolved from inputs.yaml so
    # we do not enforce it here.
    $token1Set = [bool]$env:TF_VAR_github_personal_access_token
    $token2Set = [bool]$env:TF_VAR_github_runners_personal_access_token

    if ($token1Set -and $token2Set) {
        $results += [pscustomobject]@{ Result = "Success"; Details = "GitHub PAT environment variables are set: TF_VAR_github_personal_access_token, TF_VAR_github_runners_personal_access_token." }
    } elseif ($token1Set) {
        $results += [pscustomobject]@{ Result = "Success"; Details = "TF_VAR_github_personal_access_token is set. TF_VAR_github_runners_personal_access_token is only required if use_self_hosted_runners = true." }
    } else {
        $results += [pscustomobject]@{ Result = "Warning"; Details = "TF_VAR_github_personal_access_token is not set. The wizard will prompt for it (see README Section 2.3 for fine-grained PAT permissions)." }
    }

    # Azure CLI
    if (Get-Command az -ErrorAction SilentlyContinue) {
        $results += [pscustomobject]@{ Result = "Success"; Details = "Azure CLI is installed." }
    } else {
        $results += [pscustomobject]@{ Result = "Failure"; Details = "Azure CLI is not installed." }
    }

    # Azure CLI login
    $account = $null
    try { $account = az account show --output json 2>$null | ConvertFrom-Json } catch {}

    if ($account) {
        $results += [pscustomobject]@{ Result = "Success"; Details = "Azure CLI is logged in. Tenant ID: $($account.tenantId), Subscription: $($account.name) ($($account.id))" }
        try {
            $null = az account get-access-token --output json 2>$null | ConvertFrom-Json
            $results += [pscustomobject]@{ Result = "Success"; Details = "Azure CLI access token is valid." }
        } catch {
            $results += [pscustomobject]@{ Result = "Warning"; Details = "Azure CLI access token may be expired. Run 'az login' to refresh." }
        }
    } else {
        $results += [pscustomobject]@{ Result = "Failure"; Details = "Azure CLI is not logged in. Run 'az login' first." }
    }

    # Script version
    $results += [pscustomobject]@{ Result = "Success"; Details = "AKS LZ Accelerator module version $script:ScriptVersion." }

    # powershell-yaml
    $pyMod = Get-Module -ListAvailable powershell-yaml -ErrorAction SilentlyContinue
    if ($pyMod) {
        $results += [pscustomobject]@{ Result = "Success"; Details = "powershell-yaml module is installed (version $($pyMod.Version))." }
    } else {
        $results += [pscustomobject]@{ Result = "Success"; Details = "Using built-in YAML parser (powershell-yaml not required)." }
    }

    # Render table
    Write-Host ""
    Write-Host ("{0,-12} {1}" -f "Check Result", "Check Details")
    Write-Host ("{0,-12} {1}" -f "------------", "-------------")

    $hasFailure = $false
    foreach ($r in $results) {
        $c = switch ($r.Result) { "Success" { "Green" } "Warning" { "Yellow" } "Failure" { "Red" } }
        Write-Host ("{0,-12} {1}" -f $r.Result, $r.Details) -ForegroundColor $c
        if ($r.Result -eq "Failure") { $hasFailure = $true }
    }
    Write-Host ""
    Write-Host ""

    if ($hasFailure) {
        Write-Log "One or more required prerequisites are missing. Please install them and try again." -Severity "ERROR"
        return $null
    }

    return $account
}

function Get-AzureContext {
    Write-Log "Querying Azure for subscriptions and regions..."

    $currentAccount = az account show --output json 2>$null | ConvertFrom-Json

    $subscriptions = @(az account list --query "[?state=='Enabled'].{id:id, name:name}" -o json 2>$null | ConvertFrom-Json)

    $allLocations = @(az account list-locations -o json 2>$null | ConvertFrom-Json)
    $locations = @($allLocations |
        Where-Object { $_.metadata.regionType -eq 'Physical' } |
        Sort-Object displayName)

    $azRegionNames = @()
    try {
        $azRegionNames = @($allLocations |
            Where-Object { $null -ne $_.availabilityZoneMappings -and @($_.availabilityZoneMappings).Count -gt 0 } |
            ForEach-Object { $_.name })
    } catch { }

    $subCount = ($subscriptions | Measure-Object).Count
    $locCount = ($locations    | Measure-Object).Count
    Write-Log "Found $subCount subscriptions and $locCount regions" -Severity "INFO"

    return @{
        CurrentAccount = $currentAccount
        Subscriptions  = $subscriptions
        Locations      = $locations
        AZRegionNames  = $azRegionNames
    }
}

function Show-NumberedList {
    param(
        [Parameter(Mandatory)][array]$Items,
        [string]$LabelProperty,
        [string]$ValueProperty,
        [string]$CurrentValue  = "",
        [switch]$ShowAZ,
        [array]$AZValues       = @()
    )
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $item  = $Items[$i]
        $label = if ($LabelProperty) { $item.$LabelProperty } else { "$item" }
        $value = if ($ValueProperty) { $item.$ValueProperty } else { "$item" }

        $display = "  [$($i + 1)] $label ($value)"
        if ($ShowAZ -and $AZValues -contains $value) { $display += " [AZ]" }
        if ($CurrentValue -and $value -eq $CurrentValue) { $display += " (current)" }
        Write-Host $display
    }
    Write-Host "  [0] Enter manually"
}

function Read-NumberedSelection {
    param(
        [Parameter(Mandatory)][array]$Items,
        [string]$ValueProperty,
        [int]$DefaultIndex     = -1,
        [string]$PromptLabel   = "Enter selection"
    )
    $max = $Items.Count
    $defTxt = if ($DefaultIndex -ge 0) { ", default: $($DefaultIndex + 1)" } else { "" }

    $raw = Read-Host "$PromptLabel (1-$max, 0 for manual entry$defTxt)"

    if ([string]::IsNullOrEmpty($raw) -and $DefaultIndex -ge 0) {
        $sel = $Items[$DefaultIndex]
        if ($ValueProperty) { return $sel.$ValueProperty } else { return "$sel" }
    }

    $num = 0
    if ([int]::TryParse($raw, [ref]$num)) {
        if ($num -eq 0) {
            return (Read-Host "Enter value manually")
        }
        if ($num -ge 1 -and $num -le $max) {
            $sel = $Items[$num - 1]
            if ($ValueProperty) { return $sel.$ValueProperty } else { return "$sel" }
        }
    }

    Write-Log "Invalid selection. Falling back to manual input." -Severity "WARNING"
    return (Read-Host "Enter value manually")
}

function Get-MaskedValue {
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return "" }
    if ($Value.Length -le 6) { return "***" }
    return "$($Value.Substring(0,3))***$($Value.Substring($Value.Length - 3))"
}

function Read-FlatYaml {
    param([string]$Path)

    $config = @{}
    $currentListKey = $null
    $currentList = @()

    foreach ($line in (Get-Content $Path)) {
        if ($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line) -or $line -match '^---') {
            if ($currentListKey) {
                $config[$currentListKey] = $currentList
                $currentListKey = $null; $currentList = @()
            }
            continue
        }
        if ($line -match '^\s+-\s+"?([^"]*)"?\s*$' -and $currentListKey) {
            $currentList += $Matches[1].Trim(); continue
        }
        if ($currentListKey -and $line -notmatch '^\s+-') {
            $config[$currentListKey] = $currentList
            $currentListKey = $null; $currentList = @()
        }
        if     ($line -match '^(\w[\w_]*)\s*:\s*"([^"]*)"\s*(#.*)?$')   { $config[$Matches[1]] = $Matches[2] }
        elseif ($line -match '^(\w[\w_]*)\s*:\s*\[\]\s*(#.*)?$')        { $config[$Matches[1]] = @() }
        elseif ($line -match '^(\w[\w_]*)\s*:\s*\[(.+)\]\s*(#.*)?$')    {
            $items = $Matches[2] -split ',' | ForEach-Object { $_.Trim().Trim('"') }
            $config[$Matches[1]] = $items
        }
        elseif ($line -match '^(\w[\w_]*)\s*:\s*(\S+)\s*(#.*)?$') {
            $key = $Matches[1]
            $val = $Matches[2]
            if     ($val -eq "true")    { $config[$key] = $true }
            elseif ($val -eq "false")   { $config[$key] = $false }
            elseif ($val -match '^\d+$'){ $config[$key] = [int]$val }
            else                        { $config[$key] = $val }
        }
        elseif ($line -match '^(\w[\w_]*)\s*:\s*$') {
            $currentListKey = $Matches[1]; $currentList = @()
        }
    }
    if ($currentListKey) { $config[$currentListKey] = $currentList }
    return $config
}

# =============================================================================
# Template Deployment — copies embedded templates to target folder
# =============================================================================
function Initialize-FolderStructure {
    param([string]$TargetPath)

    $configDir    = Join-Path $TargetPath "config"
    $terraformDir = Join-Path $TargetPath "terraform"
    $workflowDir  = Join-Path $TargetPath "workflows"

    foreach ($dir in @($configDir, $terraformDir, $workflowDir)) {
        if (!(Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    # Copy templates from the MODULE's embedded templates directory
    # This is the key difference vs. the old script — no repo clone needed!
    $srcTerraform = Join-Path $script:TemplateRoot "terraform"
    $srcWorkflows = Join-Path $script:TemplateRoot "workflows"

    if (Test-Path $srcTerraform) {
        Copy-Item -Path "$srcTerraform\*" -Destination $terraformDir -Recurse -Force
        Write-Log "Terraform templates deployed to $terraformDir" -Severity "INFO"
    } else {
        Write-Log "WARNING: Terraform templates not found in module at $srcTerraform" -Severity "WARNING"
    }

    if (Test-Path $srcWorkflows) {
        Copy-Item -Path "$srcWorkflows\*" -Destination $workflowDir -Recurse -Force
        Write-Log "Workflow templates deployed to $workflowDir" -Severity "INFO"
    } else {
        Write-Log "WARNING: Workflow templates not found in module at $srcWorkflows" -Severity "WARNING"
    }

    Write-Log "Folder structure ready at: $TargetPath" -Severity "SUCCESS"
    Write-Log "Config folder: $configDir" -Severity "INFO"
    return $configDir
}

# =============================================================================
# Interactive Inputs
# =============================================================================
function Get-InteractiveInputs {
    param([hashtable]$AzureContext)

    $config       = @{}
    $locations    = $AzureContext.Locations
    $subs         = $AzureContext.Subscriptions
    $currentAcct  = $AzureContext.CurrentAccount
    $azRegions    = $AzureContext.AZRegionNames
    $currentSub   = $currentAcct.id
    $currentLoc   = "swedencentral"

    Write-Log "=== Bootstrap Configuration (inputs.yaml) ===" -Severity "INFO"
    Write-Log "For more information, see: https://aka.ms/alz/acc/phase0" -Severity "INFO"
    Write-Host ""

    # ── Scenario Selection ──
    Write-Log "scenario" -Severity "INPUT REQUIRED"
    Write-Host "Select the AKS deployment scenario. Each scenario pre-configures features and security settings."
    Write-Host ""
    Write-Host "Scenarios:"
    $scenarioItems = @(
        [pscustomobject]@{ label = "Single Region Baseline    - Standard AKS baseline (recommended)"; value = "single_region_baseline" }
        [pscustomobject]@{ label = "Multi Region Baseline     - Multi-region with Front Door, Fleet, Flux"; value = "multi_region_baseline" }
        [pscustomobject]@{ label = "Single Region Regulated   - PCI-DSS 4.0.1 compliant (FIPS, Istio, Premium)"; value = "single_region_regulated" }
        [pscustomobject]@{ label = "Multi Region Regulated    - PCI-DSS multi-region (FIPS, Istio, Flux, Premium)"; value = "multi_region_regulated" }
    )
    Show-NumberedList -Items $scenarioItems -LabelProperty "label" -ValueProperty "value"
    $config.scenario = Read-NumberedSelection -Items $scenarioItems -ValueProperty "value" -DefaultIndex 0 -PromptLabel "Enter selection"
    Write-Host ""

    # Apply scenario defaults to config
    $scenarioDefaults = @{
        "single_region_baseline" = @{
            aks_sku_tier = "Standard"; network_policy = "calico"; enable_fips = $false
            enable_istio = $false; enable_flux = $false; enable_vpa = $false
            enable_backup = $false; enable_cost_analysis = $false
        }
        "multi_region_baseline" = @{
            aks_sku_tier = "Standard"; network_policy = "calico"; enable_fips = $false
            enable_istio = $false; enable_flux = $true; enable_vpa = $true
            enable_backup = $true; enable_cost_analysis = $false
            enable_acr_geo_replication = $true
        }
        "single_region_regulated" = @{
            aks_sku_tier = "Premium"; network_policy = "azure"; enable_fips = $true
            enable_istio = $true; enable_flux = $false; enable_vpa = $true
            enable_backup = $true; enable_cost_analysis = $true
        }
        "multi_region_regulated" = @{
            aks_sku_tier = "Premium"; network_policy = "azure"; enable_fips = $true
            enable_istio = $true; enable_flux = $true; enable_vpa = $true
            enable_backup = $true; enable_cost_analysis = $true
            enable_acr_geo_replication = $true
        }
    }
    $defaults = $scenarioDefaults[$config.scenario]
    foreach ($key in $defaults.Keys) {
        $config[$key] = $defaults[$key]
    }
    Write-Log "Scenario '$($config.scenario)' selected — defaults applied." -Severity "SUCCESS"
    Write-Host ""

    # ── Secondary Location (multi-region scenarios only) ──
    if ($config.scenario -match "multi_region") {
        Write-Log "secondary_location" -Severity "INPUT REQUIRED"
        Write-Host "Multi-region scenario selected. Choose a secondary Azure region for:"
        Write-Host "  - ACR geo-replication"
        Write-Host "  - Future: second AKS cluster, Azure Front Door"
        Write-Host "Default: westeurope"
        Write-Host "Required: Yes (for multi-region scenarios)"
        Write-Host "Available regions (AZ = Availability Zone support):"

        $defaultSecIdx = -1
        for ($i = 0; $i -lt $locations.Count; $i++) {
            if ($locations[$i].name -eq "westeurope") { $defaultSecIdx = $i; break }
        }
        Show-NumberedList -Items $locations -LabelProperty "displayName" -ValueProperty "name" `
            -CurrentValue "westeurope" -ShowAZ -AZValues $azRegions
        $config.secondary_location = Read-NumberedSelection -Items $locations -ValueProperty "name" `
            -DefaultIndex $defaultSecIdx -PromptLabel "Enter selection"
        $config.enable_acr_geo_replication = $true
        Write-Host ""
    } else {
        $config.secondary_location = ""
        $config.enable_acr_geo_replication = $false
    }

    # ── Decision 1: Bootstrap Location ──
    Write-Log "bootstrap_location" -Severity "INPUT REQUIRED"
    Write-Host "The Azure region where bootstrap resources like storage accounts will be created."
    Write-Host "See Decision 1 in the planning phase."
    Write-Host "https://github.com/aksapplz/docs/planning#decision-1"
    Write-Host "Default: $currentLoc"
    Write-Host "Required: Yes"
    Write-Host "Available regions (AZ = Availability Zone support):"

    $defaultLocIdx = -1
    for ($i = 0; $i -lt $locations.Count; $i++) {
        if ($locations[$i].name -eq $currentLoc) { $defaultLocIdx = $i; break }
    }
    Show-NumberedList -Items $locations -LabelProperty "displayName" -ValueProperty "name" `
        -CurrentValue $currentLoc -ShowAZ -AZValues $azRegions
    $config.bootstrap_location = Read-NumberedSelection -Items $locations -ValueProperty "name" `
        -DefaultIndex $defaultLocIdx -PromptLabel "Enter selection"
    Write-Host ""

    # ── Decision 2: AKS Landing Zone Subscription ──
    Write-Log "aks_landing_zone_subscription_id" -Severity "INPUT REQUIRED"
    Write-Host "The subscription where the AKS cluster and supporting resources will be deployed."
    Write-Host "See Decision 2 in the planning phase."
    Write-Host "Default: $currentSub"
    Write-Host "Required: Yes"
    Write-Host "Available subscriptions:"

    $defaultSubIdx = -1
    for ($i = 0; $i -lt $subs.Count; $i++) {
        if ($subs[$i].id -eq $currentSub) { $defaultSubIdx = $i; break }
    }
    Show-NumberedList -Items $subs -LabelProperty "name" -ValueProperty "id" -CurrentValue $currentSub
    $config.aks_landing_zone_subscription_id = Read-NumberedSelection -Items $subs -ValueProperty "id" `
        -DefaultIndex $defaultSubIdx -PromptLabel "Enter selection"
    Write-Host ""

    # ── Decision 2.5: Topology ──
    Write-Log "topology" -Severity "INPUT REQUIRED"
    Write-Host "How should the AKS landing zone connect to the network?"
    Write-Host ""
    $topoItems = @(
        [pscustomobject]@{ label = "Spoke           - Peer to an existing ALZ hub VNet (UDR egress via hub firewall). Requires Decisions 3 & 4."; value = "spoke" }
        [pscustomobject]@{ label = "Standalone      - No hub, no VNet peering. NAT gateway egress only. Skips Decisions 3 & 4."; value = "standalone" }
        [pscustomobject]@{ label = "Hub-and-Spoke   - Greenfield: this run also creates a new hub VNet (+ optional Azure Firewall) in the connectivity subscription."; value = "hub_and_spoke" }
    )
    Show-NumberedList -Items $topoItems -LabelProperty "label" -ValueProperty "value"
    $config.topology = Read-NumberedSelection -Items $topoItems -ValueProperty "value" -DefaultIndex 0 -PromptLabel "Enter selection"
    Write-Host ""

    if ($config.topology -eq "standalone") {
        Write-Log "Topology 'standalone' selected — skipping hub-related decisions (3 & 4)." -Severity "INFO"
        $config.connectivity_subscription_id  = ""
        $config.hub_vnet_resource_id          = ""
        $config.hub_vnet_name                 = ""
        $config.hub_vnet_resource_group_name  = ""
        $config.hub_firewall_private_ip       = ""
        Write-Host ""
    }
    elseif ($config.topology -eq "hub_and_spoke") {
        Write-Log "Topology 'hub_and_spoke' selected — bootstrap will provision a new hub VNet." -Severity "INFO"

        # Connectivity subscription is still required (this is where the hub lives).
        Write-Log "connectivity_subscription_id" -Severity "INPUT REQUIRED"
        Write-Host "Subscription where the new hub VNet (and optional Azure Firewall) will be created."
        Write-Host "Required: Yes"
        Write-Host "Available subscriptions:"
        Show-NumberedList -Items $subs -LabelProperty "name" -ValueProperty "id" -CurrentValue $currentSub
        $config.connectivity_subscription_id = Read-NumberedSelection -Items $subs -ValueProperty "id" `
            -DefaultIndex $defaultSubIdx -PromptLabel "Enter selection"
        Write-Host ""

        Write-Log "hub_vnet_address_space" -Severity "INPUT REQUIRED"
        Write-Host "Hub VNet address space (CIDR list, comma-separated). Must not overlap with the spoke."
        Write-Host "Default: 10.0.0.0/16"
        $v = Read-Host "Enter value (press enter to accept default)"
        if ([string]::IsNullOrWhiteSpace($v)) {
            $config.hub_vnet_address_space = @("10.0.0.0/16")
        } else {
            $config.hub_vnet_address_space = ($v -split '\s*,\s*') | Where-Object { $_ }
        }
        Write-Host ""

        Write-Log "hub_firewall_subnet_address_prefix" -Severity "INPUT REQUIRED"
        Write-Host "AzureFirewallSubnet prefix (must be /26 or larger and inside the hub address space)."
        Write-Host "Default: 10.0.0.0/26"
        $v = Read-Host "Enter value (press enter to accept default)"
        $config.hub_firewall_subnet_address_prefix = if ([string]::IsNullOrWhiteSpace($v)) { "10.0.0.0/26" } else { $v }
        Write-Host ""

        Write-Log "hub_deploy_firewall" -Severity "INPUT REQUIRED"
        Write-Host "Deploy an Azure Firewall in the hub? (y/N)"
        Write-Host "  y = Provision Azure Firewall + policy + zonal public IP. UDR from spoke will route through it."
        Write-Host "  n = Hub VNet + AzureFirewallSubnet only. You can attach a firewall later."
        $fw = Read-Host "Enter value (default: y)"
        $config.hub_deploy_firewall = if ($fw -eq 'n' -or $fw -eq 'no') { $false } else { $true }
        Write-Host ""

        if ($config.hub_deploy_firewall) {
            Write-Log "hub_firewall_sku_tier" -Severity "INPUT REQUIRED"
            $skuItems = @(
                [pscustomobject]@{ label = "Standard  - L3/L4 + threat intel. Recommended default."; value = "Standard" }
                [pscustomobject]@{ label = "Premium   - Adds TLS inspection, IDPS, URL filtering. Higher cost."; value = "Premium" }
            )
            Show-NumberedList -Items $skuItems -LabelProperty "label" -ValueProperty "value"
            $config.hub_firewall_sku_tier = Read-NumberedSelection -Items $skuItems -ValueProperty "value" -DefaultIndex 0 -PromptLabel "Enter selection"
            Write-Host ""
        } else {
            $config.hub_firewall_sku_tier = "Standard"
        }

        # Hub_* values that the spoke needs will be auto-populated after the hub apply runs.
        $config.hub_vnet_resource_id          = ""
        $config.hub_vnet_name                 = ""
        $config.hub_vnet_resource_group_name  = ""
        $config.hub_firewall_private_ip       = ""
    }
    else {
    # ── Decision 3: Connectivity Subscription ──
    Write-Log "connectivity_subscription_id" -Severity "INPUT REQUIRED"
    Write-Host "The subscription containing the hub VNet and firewall (deployed by ALZ)."
    Write-Host "See Decision 3 in the planning phase."
    Write-Host "Required: Yes"
    Write-Host "Available subscriptions:"

    Show-NumberedList -Items $subs -LabelProperty "name" -ValueProperty "id" -CurrentValue $currentSub
    $config.connectivity_subscription_id = Read-NumberedSelection -Items $subs -ValueProperty "id" `
        -DefaultIndex $defaultSubIdx -PromptLabel "Enter selection"
    Write-Host ""

    # ── Decision 4: Hub Networking ──
    Write-Log "hub_vnet_resource_id" -Severity "INPUT REQUIRED"
    Write-Host "The hub VNet to peer with the AKS spoke VNet."
    Write-Host "See Decision 4 in the planning phase."
    Write-Host "https://github.com/aksapplz/docs/planning#decision-4"
    Write-Host "Required: Yes"

    # Query VNets from the connectivity subscription the user just selected
    $connSubId = $config.connectivity_subscription_id
    $connSubName = ($subs | Where-Object { $_.id -eq $connSubId }).name
    Write-Log "Querying VNets in subscription '$connSubName' ($connSubId)..." -Severity "INFO"
    $vnetsJson = az network vnet list --subscription $connSubId --output json 2>$null
    $vnets = @()
    if ($vnetsJson) {
        $vnets = @($vnetsJson | ConvertFrom-Json)
    }

    if ($vnets.Count -gt 0) {
        Write-Host "Available VNets in '$connSubName':"
        $vnetItems = $vnets | ForEach-Object {
            $rg = ($_.id -split '/resourceGroups/')[1] -split '/' | Select-Object -First 1
            $addrStr = if ($_.addressSpace.addressPrefixes) { ($_.addressSpace.addressPrefixes -join ', ') } else { "?" }
            [PSCustomObject]@{
                name  = "$($_.name) (RG: $rg, Address: $addrStr)"
                value = $_.id
            }
        }
        Show-NumberedList -Items $vnetItems -LabelProperty "name" -ValueProperty "value"
        $config.hub_vnet_resource_id = Read-NumberedSelection -Items $vnetItems -ValueProperty "value" -PromptLabel "Enter selection"
    } else {
        Write-Log "No VNets found in '$connSubName'. Enter the resource ID manually." -Severity "WARNING"
        Write-Host "Format: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Network/virtualNetworks/{name}"
        $config.hub_vnet_resource_id = Read-Host "Enter value"
    }

    # Parse hub_vnet_name and hub_vnet_resource_group_name from the resource ID
    if ($config.hub_vnet_resource_id -match '/resourceGroups/([^/]+)/providers/Microsoft.Network/virtualNetworks/([^/]+)') {
        $config.hub_vnet_resource_group_name = $Matches[1]
        $config.hub_vnet_name = $Matches[2]
    } else {
        Write-Log "Could not parse VNet name/RG from resource ID. You'll need to set them manually in tfvars." -Severity "WARNING"
        $config.hub_vnet_resource_group_name = ""
        $config.hub_vnet_name = ""
    }
    Write-Host ""

    Write-Log "hub_firewall_private_ip" -Severity "INPUT REQUIRED"
    Write-Host "Private IP of the hub firewall. Used for UDR to route egress from AKS nodes."
    Write-Host "Default: 10.0.0.4"
    Write-Host "Required: Yes"
    $fwIp = Read-Host "Enter value (press enter to accept default)"
    $config.hub_firewall_private_ip = if ([string]::IsNullOrEmpty($fwIp)) { "10.0.0.4" } else { $fwIp }
    Write-Host ""
    }

    # ── Decision 5: Spoke Networking ──
    Write-Log "spoke_vnet_address_space" -Severity "INPUT REQUIRED"
    Write-Host "Address space for the spoke VNet. Must not overlap with hub or other spokes."
    Write-Host "https://github.com/aksapplz/docs/planning#decision-5"
    Write-Host "Default: 10.10.0.0/16"
    Write-Host "Required: Yes"
    $v = Read-Host "Enter value (press enter to accept default)"
    $config.spoke_vnet_address_space = if ([string]::IsNullOrEmpty($v)) { "10.10.0.0/16" } else { $v }

    Write-Log "subnet_address_prefix_aks_system_nodes" -Severity "INPUT REQUIRED"
    Write-Host "Subnet for AKS system node pool (CriticalAddonsOnly). Isolated from user workloads."
    Write-Host "Default: 10.10.0.0/24"
    $v = Read-Host "Enter value (press enter to accept default)"
    $config.subnet_address_prefix_aks_system_nodes = if ([string]::IsNullOrEmpty($v)) { "10.10.0.0/24" } else { $v }

    Write-Log "subnet_address_prefix_aks_user_nodes" -Severity "INPUT REQUIRED"
    Write-Host "Subnet for AKS user/workload node pool. Separate from system pool (AKS baseline best practice)."
    Write-Host "Default: 10.10.16.0/22"
    $v = Read-Host "Enter value (press enter to accept default)"
    $config.subnet_address_prefix_aks_user_nodes = if ([string]::IsNullOrEmpty($v)) { "10.10.16.0/22" } else { $v }

    Write-Log "subnet_address_prefix_aks_api_server" -Severity "INPUT REQUIRED"
    Write-Host "Subnet for AKS API Server VNet Integration. Minimum /28."
    Write-Host "Default: 10.10.20.0/28"
    $v = Read-Host "Enter value (press enter to accept default)"
    $config.subnet_address_prefix_aks_api_server = if ([string]::IsNullOrEmpty($v)) { "10.10.20.0/28" } else { $v }

    Write-Log "subnet_address_prefix_app_gateway" -Severity "INPUT REQUIRED"
    Write-Host "Subnet for Application Gateway WAF v2."
    Write-Host "Default: 10.10.21.0/24"
    $v = Read-Host "Enter value (press enter to accept default)"
    $config.subnet_address_prefix_app_gateway = if ([string]::IsNullOrEmpty($v)) { "10.10.21.0/24" } else { $v }

    Write-Log "subnet_address_prefix_private_endpoints" -Severity "INPUT REQUIRED"
    Write-Host "Subnet for private endpoints (ACR, Key Vault)."
    Write-Host "Default: 10.10.22.0/24"
    $v = Read-Host "Enter value (press enter to accept default)"
    $config.subnet_address_prefix_private_endpoints = if ([string]::IsNullOrEmpty($v)) { "10.10.22.0/24" } else { $v }

    Write-Log "subnet_address_prefix_ingress" -Severity "INPUT REQUIRED"
    Write-Host "Subnet for ingress controller internal load balancer."
    Write-Host "Default: 10.10.23.0/24"
    $v = Read-Host "Enter value (press enter to accept default)"
    $config.subnet_address_prefix_ingress = if ([string]::IsNullOrEmpty($v)) { "10.10.23.0/24" } else { $v }
    Write-Host ""

    # ── Decision 6: AKS Configuration ──
    Write-Log "kubernetes_version" -Severity "INPUT REQUIRED"
    Write-Host "Kubernetes version for the AKS cluster."
    Write-Host "Required: Yes"

    # Query available AKS versions for the selected region
    $aksRegion = $config.bootstrap_location
    Write-Log "Querying AKS versions for '$aksRegion'..." -Severity "INFO"
    $aksVersionsJson = az aks get-versions -l $aksRegion -o json 2>$null
    $aksVersionItems = @()
    $defaultK8sIdx = -1
    if ($aksVersionsJson) {
        $aksVersionsData = $aksVersionsJson | ConvertFrom-Json
        $versionEntries = @($aksVersionsData.values | Sort-Object { [version]($_.version + ".0") } -Descending)
        for ($i = 0; $i -lt $versionEntries.Count; $i++) {
            $entry = $versionEntries[$i]
            # Get the latest patch version for this minor
            $patches = @($entry.patchVersions.PSObject.Properties.Name | Sort-Object { [version]$_ } -Descending)
            $latestPatch = if ($patches.Count -gt 0) { $patches[0] } else { "$($entry.version).0" }
            $support = if ($entry.capabilities.supportPlan) { $entry.capabilities.supportPlan -join ', ' } else { '' }
            $isDefault = ($entry.isDefault -eq $true)
            $defaultTag = if ($isDefault) { " (default)" } else { "" }
            $previewTag = if ($entry.isPreview -eq $true) { " [preview]" } else { "" }
            $aksVersionItems += [PSCustomObject]@{
                label = "$latestPatch ($support)$defaultTag$previewTag"
                value = $latestPatch
            }
            if ($isDefault) { $defaultK8sIdx = $i }
        }
    }

    if ($aksVersionItems.Count -gt 0) {
        $defaultVer = if ($defaultK8sIdx -ge 0) { $aksVersionItems[$defaultK8sIdx].value } else { $aksVersionItems[0].value }
        Write-Host "Default: $defaultVer"
        Write-Host "Available versions (latest patch per minor):"
        Show-NumberedList -Items $aksVersionItems -LabelProperty "label" -ValueProperty "value"
        $config.kubernetes_version = Read-NumberedSelection -Items $aksVersionItems -ValueProperty "value" `
            -DefaultIndex $(if ($defaultK8sIdx -ge 0) { $defaultK8sIdx } else { 0 }) -PromptLabel "Enter selection"
    } else {
        Write-Log "Could not query AKS versions. Enter version manually." -Severity "WARNING"
        Write-Host "Default: 1.33.6"
        $v = Read-Host "Enter value (press enter to accept default)"
        $config.kubernetes_version = if ([string]::IsNullOrEmpty($v)) { "1.33.6" } else { $v }
    }

    Write-Log "aks_sku_tier" -Severity "INPUT REQUIRED"
    Write-Host "AKS pricing tier. Standard includes SLA, Premium adds more features."
    Write-Host "Default: Standard"
    Write-Host "Required: Yes"
    $skuItems = @(
        [pscustomobject]@{ label = "Free";     value = "Free" }
        [pscustomobject]@{ label = "Standard"; value = "Standard" }
        [pscustomobject]@{ label = "Premium";  value = "Premium" }
    )
    Show-NumberedList -Items $skuItems -LabelProperty "label" -ValueProperty "value"
    $config.aks_sku_tier = Read-NumberedSelection -Items $skuItems -ValueProperty "value" -DefaultIndex 1 -PromptLabel "Enter selection"

    Write-Log "aks_private_cluster" -Severity "INPUT REQUIRED"
    Write-Host "Enable private cluster with API Server VNet Integration."
    Write-Host "Default: true"
    Write-Host "Required: Yes"
    $v = Read-Host "Enter value (true/false) (press enter to accept default)"
    $config.aks_private_cluster = if ($v -eq "false") { $false } else { $true }

    Write-Log "aks_admin_group_object_ids" -Severity "INPUT REQUIRED"
    Write-Host "Entra ID group Object ID(s) for Kubernetes cluster admin RBAC binding."
    Write-Host "Format: Comma-separated list of values" -ForegroundColor DarkGray
    Write-Host "Default: (none)"
    $v = Read-Host "Enter values (comma-separated)"
    $config.aks_admin_group_object_ids = if ([string]::IsNullOrEmpty($v)) { @() } else { ($v -split ",") | ForEach-Object { $_.Trim() } }
    Write-Host ""

    # ── Decision 7: Bootstrap Subscription ──
    Write-Log "bootstrap_subscription_id" -Severity "INPUT REQUIRED"
    Write-Host "The subscription where bootstrap resources (storage, identity) will be created."
    Write-Host "See Decision 7 in the planning phase."
    Write-Host "https://github.com/aksapplz/docs/planning#decision-7"
    Write-Host "Default: $($config.aks_landing_zone_subscription_id)"
    Write-Host "Required: Yes"
    Write-Host "Available subscriptions:"

    $defaultBootIdx = -1
    for ($i = 0; $i -lt $subs.Count; $i++) {
        if ($subs[$i].id -eq $config.aks_landing_zone_subscription_id) { $defaultBootIdx = $i; break }
    }
    Show-NumberedList -Items $subs -LabelProperty "name" -ValueProperty "id" -CurrentValue $config.aks_landing_zone_subscription_id
    $config.bootstrap_subscription_id = Read-NumberedSelection -Items $subs -ValueProperty "id" `
        -DefaultIndex $defaultBootIdx -PromptLabel "Enter selection"
    Write-Host ""

    # ── Decision 8: Bootstrap Resource Naming ──
    Write-Log "service_name" -Severity "INPUT REQUIRED"
    Write-Host "A short name identifier for the service, used in resource naming (e.g., 'aksapplz')."
    Write-Host "See Decision 8 in the planning phase."
    Write-Host "https://github.com/aksapplz/docs/planning#decision-8"
    Write-Host "Default: aksapplz"
    Write-Host "Required: Yes"
    $v = Read-Host "Enter value (press enter to accept default)"
    $config.service_name = if ([string]::IsNullOrEmpty($v)) { "aksapplz" } else { $v }

    Write-Log "environment_name" -Severity "INPUT REQUIRED"
    Write-Host "The environment name used in resource naming (e.g., 'mgmt', 'prod')."
    Write-Host "See Decision 8 in the planning phase."
    Write-Host "Default: prod"
    Write-Host "Required: Yes"
    $v = Read-Host "Enter value (press enter to accept default)"
    $config.environment_name = if ([string]::IsNullOrEmpty($v)) { "prod" } else { $v }

    Write-Log "postfix_number" -Severity "INPUT REQUIRED"
    Write-Host "A numeric postfix for resource naming to ensure uniqueness."
    Write-Host "See Decision 8 in the planning phase."
    Write-Host "Default: 1"
    Write-Host "Required: Yes"
    $v = Read-Host "Enter value (press enter to accept default)"
    $config.postfix_number = if ([string]::IsNullOrEmpty($v)) { 1 } else { [int]$v }
    Write-Host ""

    # ── Decision 9: Bootstrap Networking and Agents ──
    Write-Log "use_self_hosted_runners" -Severity "INPUT REQUIRED"
    Write-Host "Whether to deploy self-hosted GitHub Actions runners in Azure instead of GitHub-hosted runners."
    Write-Host "See Decision 9 in the planning phase."
    Write-Host "https://github.com/aksapplz/docs/planning#decision-9"
    Write-Host "Default: true"
    Write-Host "Required: Yes"
    $v = Read-Host "Enter value (true/false) (press enter to accept default)"
    $config.use_self_hosted_runners = if ($v -eq "false") { $false } else { $true }

    Write-Log "use_private_networking" -Severity "INPUT REQUIRED"
    Write-Host "Whether to use private networking for the bootstrap resources."
    Write-Host "When enabled, resources will use private endpoints and be isolated from the public internet."
    Write-Host "See Decision 9 in the planning phase."
    Write-Host "Default: true"
    Write-Host "Required: Yes"
    $v = Read-Host "Enter value (true/false) (press enter to accept default)"
    $config.use_private_networking = if ($v -eq "false") { $false } else { $true }
    Write-Host ""

    # ── Decision 10: Version Control System Settings ──
    Write-Log "github_personal_access_token" -Severity "INPUT REQUIRED"
    Write-Host "A GitHub fine-grained Personal Access Token (token-1) used by Terraform to"
    Write-Host "create the repos, push files, set secrets and variables, and configure environments."
    Write-Host "Resource owner: your organization   |   Repository access: All repositories"
    Write-Host "Repository permissions (all Read and write):"
    Write-Host "  Actions, Administration, Contents, Environments, Secrets, Variables, Workflows"
    Write-Host "Organization permissions (all Read and write):"
    Write-Host "  Members, Self-hosted runners (only if using org-level runner groups)"
    Write-Host "Create at: https://github.com/settings/personal-access-tokens (Fine-grained tokens)"
    Write-Host "Required: Yes"
    if ($env:TF_VAR_github_personal_access_token) {
        $masked = Get-MaskedValue -Value $env:TF_VAR_github_personal_access_token
        Write-Host "Environment variable TF_VAR_github_personal_access_token is set ($masked)"
        Write-Host "Press enter to use the environment variable, or enter a new value."
        $v = Read-Host -MaskInput "Enter PAT (masked)"
        if ([string]::IsNullOrEmpty($v)) {
            $env:TF_VAR_github_personal_access_token = $env:TF_VAR_github_personal_access_token  # keep as-is
        } else {
            $env:TF_VAR_github_personal_access_token = $v
        }
    } else {
        $v = Read-Host -MaskInput "Enter PAT (masked)"
        if ([string]::IsNullOrEmpty($v)) {
            Write-Log "PAT is required. Set `$env:TF_VAR_github_personal_access_token or enter a value." -Severity "ERROR"
            return $null
        }
        $env:TF_VAR_github_personal_access_token = $v
    }
    Write-Log "PAT stored in environment variable TF_VAR_github_personal_access_token (current session only)." -Severity "SUCCESS"
    Write-Host ""

    Write-Log "github_runners_personal_access_token" -Severity "INPUT REQUIRED"
    Write-Host "A GitHub fine-grained PAT (token-2) used by self-hosted runners to register with GitHub."
    Write-Host "Resource owner: your organization   |   Repository access: All repositories"
    Write-Host "Repository permissions (Read and write):"
    Write-Host "  Administration"
    Write-Host "Organization permissions (Read and write):"
    Write-Host "  Self-hosted runners (only if using org-level runner groups)"
    Write-Host "Create at: https://github.com/settings/personal-access-tokens (Fine-grained tokens)"
    if ($env:TF_VAR_github_runners_personal_access_token) {
        $masked = Get-MaskedValue -Value $env:TF_VAR_github_runners_personal_access_token
        Write-Host "Environment variable TF_VAR_github_runners_personal_access_token is set ($masked)"
        Write-Host "Press enter to use the environment variable, or enter a new value."
        $v = Read-Host -MaskInput "Enter PAT (masked)"
        if (![string]::IsNullOrEmpty($v)) {
            $env:TF_VAR_github_runners_personal_access_token = $v
        }
    } else {
        Write-Host "Optional: Only needed if use_self_hosted_runners = true"
        $v = Read-Host -MaskInput "Enter PAT (masked, press enter to skip)"
        if (![string]::IsNullOrEmpty($v)) {
            $env:TF_VAR_github_runners_personal_access_token = $v
        }
    }

    Write-Log "github_organization_name" -Severity "INPUT REQUIRED"
    Write-Host "The name of your GitHub organization or username where the repository will be created."
    Write-Host "https://github.com/aksapplz/docs/prerequisites"
    Write-Host "Required: Yes"
    $config.github_organization_name = Read-Host "Enter value"
    Write-Host ""

    Write-Log "apply_approvers" -Severity "INPUT REQUIRED"
    Write-Host "List of GitHub usernames or email addresses who can approve Terraform apply operations."
    Write-Host "https://github.com/aksapplz/docs/prerequisites"
    Write-Host "Format: Comma-separated list of values" -ForegroundColor DarkGray
    $v = Read-Host "Enter values (comma-separated)"
    $config.apply_approvers = if ([string]::IsNullOrEmpty($v)) { @() } else { ($v -split ",") | ForEach-Object { $_.Trim() } }
    Write-Host ""

    # ── Decision 11: Features & Options ──
    Write-Log "features" -Severity "INPUT REQUIRED"
    Write-Host "Toggle optional components on or off. Defaults are set by your scenario ($($config.scenario))."
    Write-Host "Press Enter to accept the scenario default for each."
    Write-Host ""

    # Determine scenario defaults for feature toggles
    $isRegulated = $config.scenario -match "regulated"
    $isMultiRegion = $config.scenario -match "multi_region"

    $featureDefaults = @(
        # --- Core Security ---
        @{ Key = "enable_defender";         Label = "Enable Defender for Containers?";          Default = "true" }
        @{ Key = "enable_workload_identity"; Label = "Enable Workload Identity?";               Default = "true" }
        @{ Key = "enable_azure_policy";     Label = "Enable Azure Policy add-on?";              Default = "true" }
        # --- Monitoring ---
        @{ Key = "enable_prometheus";       Label = "Enable Managed Prometheus?";               Default = "true" }
        @{ Key = "enable_grafana";          Label = "Enable Managed Grafana?";                  Default = "true" }
        # --- Supporting Resources (ACR + Key Vault always deployed — not toggleable) ---
        @{ Key = "enable_app_gateway";      Label = "Enable Application Gateway WAF?";          Default = "true" }
        # --- Scaling ---
        @{ Key = "enable_keda";             Label = "Enable KEDA autoscaling?";                 Default = "true" }
        @{ Key = "enable_vpa";              Label = "Enable Vertical Pod Autoscaler?";          Default = $(if ($isRegulated -or $isMultiRegion) { "true" } else { "false" }) }
        @{ Key = "enable_node_auto_provisioning"; Label = "Enable Node Auto Provisioning (Karpenter)?"; Default = $(if ($isMultiRegion) { "true" } else { "false" }) }
        # --- Networking ---
        @{ Key = "enable_istio";            Label = "Enable Istio service mesh (mTLS)?";        Default = $(if ($isRegulated) { "true" } else { "false" }) }
        # --- GitOps ---
        @{ Key = "enable_flux";             Label = "Enable Flux v2 GitOps?";                   Default = $(if ($isMultiRegion) { "true" } else { "false" }) }
        @{ Key = "enable_dapr";             Label = "Enable Dapr extension?";                   Default = "false" }
        # --- Compliance ---
        @{ Key = "enable_fips";             Label = "Enable FIPS 140-2 compliant node OS?";     Default = $(if ($isRegulated) { "true" } else { "false" }) }
        @{ Key = "enable_backup";           Label = "Enable Azure Backup for AKS?";             Default = $(if ($isRegulated -or $isMultiRegion) { "true" } else { "false" }) }
        @{ Key = "enable_cost_analysis";    Label = "Enable cost analysis add-on?";             Default = $(if ($isRegulated) { "true" } else { "false" }) }
    )
    foreach ($feat in $featureDefaults) {
        $v = Read-Host "  $($feat.Label) (true/false) [$($feat.Default)]"
        if ([string]::IsNullOrEmpty($v)) {
            $config[$feat.Key] = ($feat.Default -eq "true")
        } else {
            $config[$feat.Key] = ($v -ne "false")
        }
    }
    Write-Host ""

    # Basic Inputs (hardcoded)
    $config.iac_type              = "terraform"
    $config.bootstrap_module_name = "aksapplz_github"
    $config.starter_module_name   = "aks_landing_zone"

    return $config
}

# =============================================================================
# Config File Generation
# =============================================================================
function Write-InputsYaml {
    param(
        [hashtable]$Config,
        [string]$OutputPath
    )

    $boolStr = { param($v) if ($v -eq $true) { "true" } else { "false" } }

    # PATs are NEVER written to the config file — always use environment variable placeholders
    $patValue       = 'Set via environment variable TF_VAR_github_personal_access_token'
    $runnerPatValue = 'Set via environment variable TF_VAR_github_runners_personal_access_token'

    $adminGroupsList = if ($Config.aks_admin_group_object_ids -and $Config.aks_admin_group_object_ids.Count -gt 0) {
        $quoted = ($Config.aks_admin_group_object_ids | ForEach-Object { "`"$_`"" }) -join ", "
        "[$quoted]"
    } else { "[]" }

    $approversList = if ($Config.apply_approvers -and $Config.apply_approvers.Count -gt 0) {
        $quoted = ($Config.apply_approvers | ForEach-Object { "`"$_`"" }) -join ", "
        "[$quoted]"
    } else { "[]" }

    $yaml = @"
---
# Required Inputs

# This section contains the required inputs to bootstrap the AKS Application Landing Zone
# For more detail on these inputs, visit the project README.md

# For advanced configuration options, any variable available in the bootstrap module can be set in this file

## Scenario
scenario: "$($Config.scenario)"
secondary_location: "$($Config.secondary_location)"

## Topology: standalone | spoke
# - standalone : no hub, no VNet peering, NAT gateway egress only
# - spoke      : peer to an existing ALZ hub VNet, UDR egress via hub firewall (Decisions 3 & 4 required)
topology: "$(if ($Config.topology) { $Config.topology } else { 'spoke' })"

## Decision 1: Bootstrap Resource Azure Region
bootstrap_location: "$($Config.bootstrap_location)"

## Decision 2: AKS Landing Zone Subscription
# The subscription where the AKS cluster and supporting resources will be deployed
aks_landing_zone_subscription_id: "$($Config.aks_landing_zone_subscription_id)"

## Decision 3: Connectivity Subscription (only used when topology = spoke)
# The subscription containing the hub VNet and firewall (deployed by ALZ)
connectivity_subscription_id: "$($Config.connectivity_subscription_id)"

## Decision 4: Hub Networking (only used when topology = spoke)
# Required for VNet peering and UDR to route egress through the hub firewall
hub_vnet_resource_id: "$($Config.hub_vnet_resource_id)"
hub_vnet_name: "$($Config.hub_vnet_name)"
hub_vnet_resource_group_name: "$($Config.hub_vnet_resource_group_name)"
hub_firewall_private_ip: "$($Config.hub_firewall_private_ip)"

## Decision 5: Spoke Networking
# System and user node pools use separate subnets (AKS baseline best practice)
spoke_vnet_address_space: "$($Config.spoke_vnet_address_space)"
subnet_address_prefix_aks_system_nodes: "$($Config.subnet_address_prefix_aks_system_nodes)"
subnet_address_prefix_aks_user_nodes: "$($Config.subnet_address_prefix_aks_user_nodes)"
subnet_address_prefix_aks_api_server: "$($Config.subnet_address_prefix_aks_api_server)"
subnet_address_prefix_app_gateway: "$($Config.subnet_address_prefix_app_gateway)"
subnet_address_prefix_private_endpoints: "$($Config.subnet_address_prefix_private_endpoints)"
subnet_address_prefix_ingress: "$($Config.subnet_address_prefix_ingress)"

## Decision 6: AKS Configuration
kubernetes_version: "$($Config.kubernetes_version)"
aks_sku_tier: "$($Config.aks_sku_tier)"
aks_private_cluster: $(& $boolStr $Config.aks_private_cluster)
aks_admin_group_object_ids: $adminGroupsList

## Decision 7: Bootstrap Resource Subscription
bootstrap_subscription_id: "$($Config.bootstrap_subscription_id)"

## Decision 8: Bootstrap Resource Naming
# Resources will be named: {service_name}-{environment_name}-{postfix_number}
# For example: aksapplz-prod-001
service_name: "$($Config.service_name)"
environment_name: "$($Config.environment_name)"
postfix_number: $($Config.postfix_number)

## Decision 9: Bootstrap Networking and Agents
use_self_hosted_runners: $(& $boolStr $Config.use_self_hosted_runners)
use_private_networking: $(& $boolStr $Config.use_private_networking)

## Decision 10: Version Control System Settings
github_personal_access_token: "$patValue"
github_runners_personal_access_token: "$runnerPatValue"
github_organization_name: "$($Config.github_organization_name)"
apply_approvers: $approversList

## Decision 11: Features & Options
# Core security
enable_defender: $(& $boolStr $Config.enable_defender)
enable_workload_identity: $(& $boolStr $Config.enable_workload_identity)
enable_azure_policy: $(& $boolStr $Config.enable_azure_policy)
# Monitoring
enable_prometheus: $(& $boolStr $Config.enable_prometheus)
enable_grafana: $(& $boolStr $Config.enable_grafana)
# Supporting resources (ACR + Key Vault always deployed)
enable_app_gateway: $(& $boolStr $Config.enable_app_gateway)
# Scaling
enable_keda: $(& $boolStr $Config.enable_keda)
enable_vpa: $(& $boolStr $Config.enable_vpa)
enable_node_auto_provisioning: $(& $boolStr $Config.enable_node_auto_provisioning)
# Networking
enable_istio: $(& $boolStr $Config.enable_istio)
# GitOps
enable_flux: $(& $boolStr $Config.enable_flux)
enable_dapr: $(& $boolStr $Config.enable_dapr)
# Compliance
enable_fips: $(& $boolStr $Config.enable_fips)
enable_backup: $(& $boolStr $Config.enable_backup)
enable_cost_analysis: $(& $boolStr $Config.enable_cost_analysis)
# Multi-region
enable_acr_geo_replication: $(& $boolStr $Config.enable_acr_geo_replication)

# Basic Inputs (Do not modify)
iac_type: "terraform"
bootstrap_module_name: "aksapplz_github"
starter_module_name: "aks_landing_zone"
"@

    Set-Content -Path $OutputPath -Value $yaml -Encoding UTF8
    Write-Log "Updated inputs.yaml" -Severity "SUCCESS"
}

function Write-TfvarsFile {
    param(
        [hashtable]$Config,
        [string]$OutputPath
    )

    $subnetBlock = @"
  aks_system_nodes  = "$($Config.subnet_address_prefix_aks_system_nodes)"
  aks_user_nodes    = "$($Config.subnet_address_prefix_aks_user_nodes)"
  aks_api_server    = "$($Config.subnet_address_prefix_aks_api_server)"
  app_gateway       = "$($Config.subnet_address_prefix_app_gateway)"
  private_endpoints = "$($Config.subnet_address_prefix_private_endpoints)"
  ingress           = "$($Config.subnet_address_prefix_ingress)"
"@

    $boolTf = { param($v) if ($v -eq $true) { "true" } else { "false" } }

    $adminGroupTf = if ($Config.aks_admin_group_object_ids -and $Config.aks_admin_group_object_ids.Count -gt 0) {
        $quoted = ($Config.aks_admin_group_object_ids | ForEach-Object { "`"$_`"" }) -join ", "
        "[$quoted]"
    } else { '["REPLACE_ME"]  # Entra ID group for AKS admins' }

    $networkPolicy = if ($Config.scenario -match "regulated") { "azure" } else { "calico" }
    $nodeOsUpgrade = if ($Config.scenario -match "regulated") { "SecurityPatch" } else { "NodeImage" }
    $isRegulated   = $Config.scenario -match "regulated"
    $nodeMinCount  = if ($isRegulated) { 3 } else { 2 }
    $userNodeLabelsBlock = if ($isRegulated) {
        @"
  node_labels = {
    "workload"   = "user"
    "compliance" = "pci-dss"
  }
"@
    } else {
        @"
  node_labels = {
    "workload" = "user"
  }
"@
    }

    $content = @"
# =============================================================================
# AKS Application Landing Zone - Configuration
# =============================================================================
# Generated by Deploy-AKSLandingZoneLegacy interactive mode.
# Scenario: $($Config.scenario)
# Review and customize these values before running the bootstrap.
# =============================================================================

# -----------------------------------------------------------------------------
# Scenario
# -----------------------------------------------------------------------------
scenario = "$($Config.scenario)"

# Secondary region (multi-region scenarios only)
secondary_location = "$($Config.secondary_location)"

# -----------------------------------------------------------------------------
# Core Settings
# -----------------------------------------------------------------------------
subscription_id              = "$($Config.aks_landing_zone_subscription_id)"
connectivity_subscription_id = "$($Config.connectivity_subscription_id)"
tenant_id                    = "$($Config.tenant_id)"
location                     = "$($Config.bootstrap_location)"
workload_name                = "$($Config.service_name)"
environment                  = "$($Config.environment_name)"

tags = {
  "costCenter"   = "IT"
  "owner"        = "platform-team"
  "application"  = "aks-landing-zone"
}

# -----------------------------------------------------------------------------
# Networking - Spoke VNet
# System and user node pools use separate subnets (AKS baseline best practice)
# -----------------------------------------------------------------------------
vnet_address_space = "$($Config.spoke_vnet_address_space)"

subnet_address_prefixes = {
$subnetBlock
}

# Hub VNet peering (from your ALZ deployment)
hub_vnet_resource_id         = "$($Config.hub_vnet_resource_id)"
hub_vnet_name                = "$($Config.hub_vnet_name)"
hub_vnet_resource_group_name = "$($Config.hub_vnet_resource_group_name)"
hub_firewall_private_ip      = "$($Config.hub_firewall_private_ip)"
use_remote_gateways          = false

# -----------------------------------------------------------------------------
# AKS Configuration
# -----------------------------------------------------------------------------
kubernetes_version = "$($Config.kubernetes_version)"
aks_sku_tier       = "$($Config.aks_sku_tier)"
availability_zones = ["1", "2", "3"]

# Network plugin
network_plugin      = "azure"
network_plugin_mode = "overlay"
network_policy      = "$networkPolicy"

# IP ranges
service_cidr   = "172.16.0.0/16"
dns_service_ip = "172.16.0.10"
pod_cidr       = "192.168.0.0/16"

# Private cluster
private_cluster_enabled             = $(& $boolTf $Config.aks_private_cluster)
private_cluster_public_fqdn_enabled = false
private_dns_zone_id                 = "system"

# API server VNet integration
enable_api_server_vnet_integration = true
api_server_authorized_ip_ranges    = []

# Entra ID admin groups
aks_admin_group_object_ids = $adminGroupTf

# Auto-upgrade
automatic_upgrade_channel = "patch"
node_os_upgrade_channel   = "$nodeOsUpgrade"

# Maintenance window
maintenance_window = {
  frequency   = "Weekly"
  interval    = 1
  duration    = 4
  day_of_week = "Sunday"
  start_time  = "02:00"
  utc_offset  = "+01:00"
}

# -----------------------------------------------------------------------------
# System Node Pool (dedicated subnet: snet-aks-system-*)
# Regulated scenarios: min_count=3 for higher HA
# -----------------------------------------------------------------------------
system_node_pool = {
  vm_size         = "Standard_D4ds_v5"
  os_disk_size_gb = 128
  os_disk_type    = "Ephemeral"
  max_pods        = 110
  min_count       = $nodeMinCount
  max_count       = 5
  node_count      = $nodeMinCount
  max_surge       = "33%"
}

# -----------------------------------------------------------------------------
# User Node Pool (dedicated subnet: snet-aks-user-*)
# Regulated scenarios: min_count=3 for higher HA + compliance label
# -----------------------------------------------------------------------------
user_node_pool = {
  vm_size         = "Standard_D4ds_v5"
  os_disk_size_gb = 128
  os_disk_type    = "Ephemeral"
  max_pods        = 110
  min_count       = $nodeMinCount
  max_count       = 20
  node_count      = $nodeMinCount
  max_surge       = "33%"
$userNodeLabelsBlock
}

# -----------------------------------------------------------------------------
# Identity & Security
# -----------------------------------------------------------------------------
enable_workload_identity = $(& $boolTf $Config.enable_workload_identity)
enable_azure_rbac        = true
disable_local_accounts   = true
enable_image_cleaner     = true
enable_azure_policy      = $(& $boolTf $Config.enable_azure_policy)
enable_defender          = $(& $boolTf $Config.enable_defender)

# -----------------------------------------------------------------------------
# Monitoring
# -----------------------------------------------------------------------------
enable_managed_prometheus  = $(& $boolTf $Config.enable_prometheus)
enable_managed_grafana     = $(& $boolTf $Config.enable_grafana)
enable_diagnostic_settings = true

# -----------------------------------------------------------------------------
# Scaling
# -----------------------------------------------------------------------------
enable_keda                   = $(& $boolTf $Config.enable_keda)
enable_vpa                    = $(& $boolTf $Config.enable_vpa)
enable_node_auto_provisioning = $(& $boolTf $Config.enable_node_auto_provisioning)

# -----------------------------------------------------------------------------
# Networking Features
# -----------------------------------------------------------------------------
enable_app_gateway                        = $(& $boolTf $Config.enable_app_gateway)
enable_istio_service_mesh                 = $(& $boolTf $Config.enable_istio)
istio_internal_ingress_gateway            = $(& $boolTf $Config.enable_istio)
istio_external_ingress_gateway            = false

# -----------------------------------------------------------------------------
# Storage
# -----------------------------------------------------------------------------
enable_blob_csi_driver    = true
enable_disk_csi_driver    = true
enable_file_csi_driver    = true
enable_snapshot_controller = true

# -----------------------------------------------------------------------------
# GitOps & Extensions
# -----------------------------------------------------------------------------
enable_flux = $(& $boolTf $Config.enable_flux)
enable_dapr = $(& $boolTf $Config.enable_dapr)

# -----------------------------------------------------------------------------
# Compliance
# -----------------------------------------------------------------------------
enable_fips          = $(& $boolTf $Config.enable_fips)
enable_backup        = $(& $boolTf $Config.enable_backup)
enable_cost_analysis = $(& $boolTf $Config.enable_cost_analysis)

# -----------------------------------------------------------------------------
# Application Gateway with WAF v2
# -----------------------------------------------------------------------------
waf_mode                 = "Prevention"
app_gateway_min_capacity = 1
app_gateway_max_capacity = 10

# -----------------------------------------------------------------------------
# Azure Container Registry
# -----------------------------------------------------------------------------
acr_zone_redundancy_enabled    = true
acr_retention_days             = 30
enable_acr_geo_replication      = $(& $boolTf $Config.enable_acr_geo_replication)
acr_private_dns_zone_ids       = []
keyvault_private_dns_zone_ids  = []

# -----------------------------------------------------------------------------
# Monitoring Configuration
# -----------------------------------------------------------------------------
log_retention_days    = 90
grafana_sku           = "Standard"
grafana_zone_redundancy = $(& $boolTf $Config.grafana_zone_redundancy)
grafana_public_access   = true
grafana_admin_group_object_id = "$($Config.grafana_admin_group_object_id)"
"@

    Set-Content -Path $OutputPath -Value $content -Encoding UTF8
    Write-Log "Updated aks-landing-zone.tfvars" -Severity "SUCCESS"
}

# =============================================================================
# Compute Derived Names
# =============================================================================
function Get-DerivedNames {
    param([hashtable]$Config)

    $svc = $Config.service_name
    $envName = $Config.environment_name
    $num = "{0:D3}" -f [int]$Config.postfix_number
    $loc = $Config.bootstrap_location

    $locationShortcodes = @{
        "swedencentral"      = "sc";  "westeurope"         = "we";  "northeurope"        = "ne"
        "eastus"             = "eus"; "eastus2"            = "eus2"; "westus2"            = "wus2"
        "westus3"            = "wus3"; "centralus"          = "cus"; "uksouth"            = "uks"
        "ukwest"             = "ukw"; "germanywestcentral" = "gwc"; "francecentral"      = "frc"
        "norwayeast"         = "noe"; "australiaeast"      = "ae";  "japaneast"          = "jpe"
        "southeastasia"      = "sea"; "canadacentral"      = "cc";  "brazilsouth"        = "brs"
    }
    $locShort = if ($locationShortcodes.ContainsKey($loc)) { $locationShortcodes[$loc] } else { $loc.Substring(0, [Math]::Min(3, $loc.Length)) }

    return @{
        ResourceGroupName   = "rg-$svc-$envName-$locShort-$num"
        IdentityRgName      = "rg-$svc-$envName-$locShort-identity"
        StorageAccountName  = "st${svc}${envName}${locShort}${num}"
        ContainerName       = "tfstate"
        ManagedIdentityName = "id-$svc-$envName-$locShort-$num"
        RepoName            = "$svc-$envName"
        TemplateRepoName    = "$svc-$envName-templates"
        TeamName            = "$svc-$envName-approvers"
        PlanEnvironment     = "$svc-plan"
        ApplyEnvironment    = "$svc-apply"
        StateKey            = "$svc-$envName.terraform.tfstate"
        Prefix              = "$svc-$envName-$locShort"
    }
}

# =============================================================================
# Pre-flight: Register Required Azure Resource Providers
# =============================================================================
function Register-RequiredProviders {
    param(
        [hashtable]$Config
    )

    Write-Log "Checking Azure resource provider registrations..." -Severity "INFO"

    $aksSubId = if ([string]::IsNullOrEmpty($Config.aks_landing_zone_subscription_id)) {
        (az account show --query id -o tsv)
    } else { $Config.aks_landing_zone_subscription_id }

    # Core providers always required
    $requiredProviders = @(
        "Microsoft.ContainerService"
        "Microsoft.Network"
        "Microsoft.Storage"
        "Microsoft.KeyVault"
        "Microsoft.ContainerRegistry"
        "Microsoft.OperationalInsights"
        "microsoft.insights"
        "Microsoft.Monitor"
        "Microsoft.ManagedIdentity"
        "Microsoft.Authorization"
    )

    # Conditional providers based on config
    if ($Config.enable_grafana -eq $true) {
        $requiredProviders += "Microsoft.Dashboard"
    }
    if ($Config.enable_defender -eq $true) {
        $requiredProviders += "Microsoft.Security"
    }
    if ($Config.enable_flux -eq $true -or $Config.enable_backup -eq $true) {
        $requiredProviders += "Microsoft.KubernetesConfiguration"
    }
    if ($Config.enable_backup -eq $true) {
        $requiredProviders += "Microsoft.DataProtection"
    }

    $registered = az provider list --subscription $aksSubId --query "[?registrationState=='Registered'].namespace" -o tsv 2>$null
    $registeredSet = @{}
    if ($registered) {
        $registered -split "`n" | ForEach-Object { $registeredSet[$_.Trim().ToLower()] = $true }
    }

    $toRegister = @()
    foreach ($rp in $requiredProviders) {
        if (-not $registeredSet.ContainsKey($rp.ToLower())) {
            $toRegister += $rp
        }
    }

    if ($toRegister.Count -eq 0) {
        Write-Log "All $($requiredProviders.Count) resource providers already registered" -Severity "SUCCESS"
    } else {
        Write-Log "Registering $($toRegister.Count) missing provider(s)..." -Severity "INFO"
        foreach ($rp in $toRegister) {
            az provider register --namespace $rp --subscription $aksSubId --output none 2>$null
            Write-Log "Registered: $rp" -Severity "SUCCESS"
        }
        # Wait for registrations to propagate (up to 60s)
        $maxWait = 60
        $waited = 0
        $allRegistered = $false
        while (-not $allRegistered -and $waited -lt $maxWait) {
            Start-Sleep -Seconds 5
            $waited += 5
            $allRegistered = $true
            foreach ($rp in $toRegister) {
                $state = az provider show --namespace $rp --subscription $aksSubId --query registrationState -o tsv 2>$null
                if ($state -ne "Registered") { $allRegistered = $false; break }
            }
        }
        if ($allRegistered) {
            Write-Log "All providers registered successfully" -Severity "SUCCESS"
        } else {
            Write-Log "Some providers still registering — Terraform will handle them" -Severity "WARNING"
        }
    }
}

# =============================================================================
# Step 1: Create Terraform Backend (idempotent)
# =============================================================================
function New-TerraformBackend {
    param([hashtable]$Config, [hashtable]$Names)

    Write-Log "Creating Terraform backend storage..." -Severity "INFO"

    $subscriptionId = if ([string]::IsNullOrEmpty($Config.bootstrap_subscription_id)) {
        (az account show --query id -o tsv)
    } else { $Config.bootstrap_subscription_id }

    az group create --name $Names.ResourceGroupName --location $Config.bootstrap_location `
        --subscription $subscriptionId --output none
    Write-Log "Resource group: $($Names.ResourceGroupName)" -Severity "SUCCESS"

    $existing = az storage account show --name $Names.StorageAccountName --resource-group $Names.ResourceGroupName `
        --subscription $subscriptionId --query name -o tsv 2>$null
    if (!$existing) {
        az storage account create --name $Names.StorageAccountName `
            --resource-group $Names.ResourceGroupName --location $Config.bootstrap_location `
            --subscription $subscriptionId --sku Standard_ZRS --kind StorageV2 `
            --min-tls-version TLS1_2 --allow-blob-public-access false --https-only true `
            --allow-shared-key-access false --output none
    }
    Write-Log "Storage account: $($Names.StorageAccountName)" -Severity "SUCCESS"

    # Storage security hardening (ALZ pattern: soft delete, versioning)
    az storage account blob-service-properties update `
        --account-name $Names.StorageAccountName --resource-group $Names.ResourceGroupName `
        --subscription $subscriptionId `
        --enable-delete-retention true --delete-retention-days 7 `
        --enable-versioning true `
        --enable-container-delete-retention true --container-delete-retention-days 7 `
        --output none 2>$null
    Write-Log "Storage security: soft delete (7d), versioning, shared key disabled" -Severity "SUCCESS"

    az storage container create --name $Names.ContainerName --account-name $Names.StorageAccountName `
        --auth-mode login --output none 2>$null
    Write-Log "Container: $($Names.ContainerName)" -Severity "SUCCESS"
    Write-Host ""

    return @{
        SubscriptionId     = $subscriptionId
        ResourceGroupName  = $Names.ResourceGroupName
        StorageAccountName = $Names.StorageAccountName
        ContainerName      = $Names.ContainerName
        Key                = $Names.StateKey
    }
}

# =============================================================================
# Step 2: Create Managed Identity + Federated Credentials (OIDC)
# =============================================================================
function New-ManagedIdentity {
    param([hashtable]$Config, [hashtable]$Names, [hashtable]$Backend)

    Write-Log "Creating managed identity with OIDC federation..." -Severity "INFO"

    $org      = $Config.github_organization_name
    $repoName = $Names.RepoName

    # Dedicated identity resource group (ALZ pattern: separate RG for identities)
    $identityRg = $Names.IdentityRgName
    az group create --name $identityRg --location $Config.bootstrap_location `
        --subscription $Backend.SubscriptionId --output none 2>$null
    Write-Log "Resource group (identity): $identityRg" -Severity "SUCCESS"

    $identity = az identity show --name $Names.ManagedIdentityName --resource-group $identityRg `
        --subscription $Backend.SubscriptionId --output json 2>$null | ConvertFrom-Json
    if (!$identity) {
        $identity = az identity create --name $Names.ManagedIdentityName `
            --resource-group $identityRg --location $Config.bootstrap_location `
            --subscription $Backend.SubscriptionId --output json | ConvertFrom-Json
    }
    Write-Log "Managed identity: $($Names.ManagedIdentityName)" -Severity "SUCCESS"

    $tenantId = (az account show --query tenantId -o tsv)

    $aksSubId = if ([string]::IsNullOrEmpty($Config.aks_landing_zone_subscription_id)) {
        (az account show --query id -o tsv)
    } else { $Config.aks_landing_zone_subscription_id }

    # -------------------------------------------------------------------------
    # Role assignments (idempotent) — Least-privilege design
    # -------------------------------------------------------------------------
    # Owner on AKS subscription — required because Terraform creates the
    # resource group itself AND creates role assignments (e.g. AKS network
    # contributor, Grafana roles). Owner includes both resource writes and
    # Microsoft.Authorization/roleAssignments/write which Contributor lacks.
    az role assignment create --assignee-object-id $identity.principalId `
        --assignee-principal-type ServicePrincipal --role "Owner" `
        --scope "/subscriptions/$aksSubId" --output none 2>$null
    Write-Log "Owner on AKS subscription ($aksSubId)" -Severity "SUCCESS"

    # Network Contributor scoped to the hub VNet resource group only (NOT the
    # entire connectivity subscription). Only needed for VNet peering in corp mode.
    if (![string]::IsNullOrEmpty($Config.connectivity_subscription_id) -and
        ![string]::IsNullOrEmpty($Config.hub_vnet_resource_group_name)) {
        $hubVnetRgScope = "/subscriptions/$($Config.connectivity_subscription_id)/resourceGroups/$($Config.hub_vnet_resource_group_name)"
        az role assignment create --assignee-object-id $identity.principalId `
            --assignee-principal-type ServicePrincipal --role "Network Contributor" `
            --scope $hubVnetRgScope --output none 2>$null
        Write-Log "Network Contributor on hub VNet RG ($($Config.hub_vnet_resource_group_name))" -Severity "SUCCESS"
    } elseif (![string]::IsNullOrEmpty($Config.connectivity_subscription_id)) {
        # Fallback: hub RG name not available. Do NOT assign at subscription level
        # — that would be overly broad. Skip and instruct user to assign manually.
        Write-Log "Hub VNet resource group name could not be determined." -Severity "WARNING"
        Write-Log "Network Contributor role NOT assigned on connectivity subscription (too broad)." -Severity "WARNING"
        Write-Log "Please assign manually: az role assignment create --assignee-object-id $($identity.principalId) --role 'Network Contributor' --scope '/subscriptions/$($Config.connectivity_subscription_id)/resourceGroups/<hub-vnet-rg>'" -Severity "WARNING"
    }

    # Storage Blob Data Contributor scoped to the container (ALZ pattern: least privilege)
    $storageContainerScope = "/subscriptions/$($Backend.SubscriptionId)/resourceGroups/$($Backend.ResourceGroupName)/providers/Microsoft.Storage/storageAccounts/$($Backend.StorageAccountName)/blobServices/default/containers/$($Backend.ContainerName)"
    az role assignment create --assignee-object-id $identity.principalId `
        --assignee-principal-type ServicePrincipal --role "Storage Blob Data Contributor" `
        --scope $storageContainerScope --output none 2>$null
    Write-Log "Storage Blob Data Contributor on tfstate container" -Severity "SUCCESS"

    # Federated credentials (check before create)
    $planSubject  = "repo:${org}/${repoName}:environment:$($Names.PlanEnvironment)"
    $applySubject = "repo:${org}/${repoName}:environment:$($Names.ApplyEnvironment)"

    $existingFc = az identity federated-credential list --identity-name $Names.ManagedIdentityName `
        --resource-group $identityRg --subscription $Backend.SubscriptionId `
        --query "[].name" -o json 2>$null | ConvertFrom-Json

    if ($existingFc -notcontains "fc-$($Names.PlanEnvironment)") {
        az identity federated-credential create --name "fc-$($Names.PlanEnvironment)" `
            --identity-name $Names.ManagedIdentityName --resource-group $identityRg `
            --subscription $Backend.SubscriptionId --issuer "https://token.actions.githubusercontent.com" `
            --subject $planSubject --audiences "api://AzureADTokenExchange" --output none
    }
    Write-Log "Federated credential (plan): $planSubject" -Severity "SUCCESS"

    if ($existingFc -notcontains "fc-$($Names.ApplyEnvironment)") {
        az identity federated-credential create --name "fc-$($Names.ApplyEnvironment)" `
            --identity-name $Names.ManagedIdentityName --resource-group $identityRg `
            --subscription $Backend.SubscriptionId --issuer "https://token.actions.githubusercontent.com" `
            --subject $applySubject --audiences "api://AzureADTokenExchange" --output none
    }
    Write-Log "Federated credential (apply): $applySubject" -Severity "SUCCESS"
    Write-Host ""

    return @{ ClientId = $identity.clientId; PrincipalId = $identity.principalId; TenantId = $tenantId }
}

# =============================================================================
# Step 3: Bootstrap GitHub (idempotent)
# =============================================================================
function New-GitHubBootstrap {
    param([hashtable]$Config, [hashtable]$Names, [hashtable]$Backend, [hashtable]$Identity)

    Write-Log "Bootstrapping GitHub..." -Severity "INFO"

    $pat = if ($env:TF_VAR_github_personal_access_token) { $env:TF_VAR_github_personal_access_token }
           else { $Config.github_personal_access_token }
    $org = $Config.github_organization_name

    # Hard-fail if no PAT is available. Falling back to the gh CLI keyring OAuth token
    # produces confusing 'CreateRepository' errors when the OAuth app is not authorized
    # for the org. The wizard requires a fine-grained PAT explicitly.
    if ([string]::IsNullOrWhiteSpace($pat)) {
        Write-Log "No fine-grained PAT available for bootstrap." -Severity "ERROR"
        Write-Log "Set `$env:TF_VAR_github_personal_access_token to a fine-grained PAT before re-running." -Severity "ERROR"
        Write-Log "See README Section 2.3 for required permissions, or generate one at:" -Severity "ERROR"
        Write-Log "  https://github.com/settings/personal-access-tokens" -Severity "ERROR"
        return $false
    }
    $env:GH_TOKEN = $pat

    # Validate token works
    $tokenCheck = gh api user --jq ".login" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "GitHub token validation failed — check PAT. Error: $tokenCheck" -Severity "ERROR"
        return $false
    }
    Write-Log "Authenticated as: $tokenCheck (via TF_VAR_github_personal_access_token)" -Severity "INFO"

    # Detect whether the PAT is fine-grained ('github_pat_*') vs classic OAuth/PAT.
    # Classic OAuth tokens from `gh auth login` cannot create org repos unless the
    # OAuth app is org-authorized — this is the most common silent failure.
    $isFineGrained = $pat.StartsWith('github_pat_')
    if (-not $isFineGrained) {
        Write-Log "PAT does not look fine-grained (expected prefix 'github_pat_'). If creation fails, regenerate as fine-grained at https://github.com/settings/personal-access-tokens" -Severity "WARNING"
    }

    # Repos (check before create)
    $repoCheck = gh repo view "$org/$($Names.RepoName)" --json name,visibility 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Creating private repository $org/$($Names.RepoName)..." -Severity "INFO"
        $createResult = gh repo create "$org/$($Names.RepoName)" --private -d "AKS Application Landing Zone - Infrastructure" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Failed to create repo: $createResult" -Severity "ERROR"
            if ("$createResult" -match 'does not have the correct permissions to execute .CreateRepository' -or
                "$createResult" -match 'You need admin access to the organization') {
                Write-Log "Remediation: token-1 cannot create repositories in organization '$org' right now." -Severity "ERROR"
                Write-Log "  1. MOST LIKELY: PAT 'Resource owner' is set to your USER, not the organization." -Severity "ERROR"
                Write-Log "     A fine-grained PAT can only create org resources when its Resource owner = '$org'." -Severity "ERROR"
                Write-Log "     Regenerate the PAT at https://github.com/settings/personal-access-tokens/new and set:" -Severity "ERROR"
                Write-Log "       - Resource owner: $org   (NOT your personal user)" -Severity "ERROR"
                Write-Log "       - Repository access: All repositories" -Severity "ERROR"
                Write-Log "  2. Required Repository permissions (Read and write): Administration, Contents," -Severity "ERROR"
                Write-Log "     Actions, Environments, Secrets, Variables, Workflows. 'Administration: R/W' is" -Severity "ERROR"
                Write-Log "     what authorizes repo creation." -Severity "ERROR"
                Write-Log "  3. Required Organization permissions (Read and write): Members, Self-hosted runners." -Severity "ERROR"
                Write-Log "  4. After generating, an org Owner must APPROVE the PAT request at:" -Severity "ERROR"
                Write-Log "       https://github.com/organizations/$org/settings/personal-access-token-requests" -Severity "ERROR"
                Write-Log "  5. Verify org allows private repo creation: Settings -> Member privileges." -Severity "ERROR"
            }
            return $false
        }
    } else {
        # Existing repo: enforce private visibility (bootstrap requires private).
        $existing = $repoCheck | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($existing -and $existing.visibility -and $existing.visibility -ne 'PRIVATE') {
            Write-Log "Existing repo $org/$($Names.RepoName) is $($existing.visibility); switching to PRIVATE..." -Severity "WARNING"
            $null = gh repo edit "$org/$($Names.RepoName)" --visibility private --accept-visibility-change-consequences 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Log "Could not switch visibility to private. Set it manually in GitHub and re-run." -Severity "ERROR"
                return $false
            }
        }
    }
    Write-Log "Repository: $org/$($Names.RepoName) (private)" -Severity "SUCCESS"

    $templateRepoCheck = gh repo view "$org/$($Names.TemplateRepoName)" --json name,visibility 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Creating private repository $org/$($Names.TemplateRepoName)..." -Severity "INFO"
        $createResult2 = gh repo create "$org/$($Names.TemplateRepoName)" --private -d "AKS Application Landing Zone - CI/CD workflow templates" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Failed to create template repo: $createResult2" -Severity "ERROR"
            if ("$createResult2" -match 'does not have the correct permissions to execute .CreateRepository') {
                Write-Log "Remediation: see the repo-creation remediation hint printed above." -Severity "ERROR"
            }
            return $false
        }
    } else {
        $existingTpl = $templateRepoCheck | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($existingTpl -and $existingTpl.visibility -and $existingTpl.visibility -ne 'PRIVATE') {
            Write-Log "Existing repo $org/$($Names.TemplateRepoName) is $($existingTpl.visibility); switching to PRIVATE..." -Severity "WARNING"
            $null = gh repo edit "$org/$($Names.TemplateRepoName)" --visibility private --accept-visibility-change-consequences 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Log "Could not switch visibility to private. Set it manually in GitHub and re-run." -Severity "ERROR"
                return $false
            }
        }
    }
    Write-Log "Repository: $org/$($Names.TemplateRepoName) (private)" -Severity "SUCCESS"

    # Team (check before create) — use lowercase slug for API consistency
    $teamSlug = ($Names.TeamName -replace '[^a-zA-Z0-9-]', '-').ToLower()
    $existingTeam = gh api "orgs/$org/teams/$teamSlug" 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
    if (!$existingTeam -or !$existingTeam.id) {
        $teamResult = gh api -X POST "orgs/$org/teams" -f name="$($Names.TeamName)" -f privacy="closed" `
            -f description="Approvers for AKS Application Landing Zone deployments" 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($teamResult -and $teamResult.slug) {
            $teamSlug = $teamResult.slug
            $existingTeam = $teamResult
        }
    }
    Write-Log "Team: $($Names.TeamName)" -Severity "SUCCESS"

    # Get current authenticated user for fallback
    $currentUser = gh api /user 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue

    # Add approvers to team
    $approvers = $Config.apply_approvers
    if ($approvers -is [string]) { $approvers = @($approvers) }
    foreach ($approver in $approvers) {
        $a = "$approver".Trim()
        if (![string]::IsNullOrEmpty($a)) {
            $memberResult = gh api -X PUT "orgs/$org/teams/$teamSlug/memberships/$a" 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "Added $a to $($Names.TeamName)" -Severity "SUCCESS"
            } else {
                Write-Log "Could not add '$a' to team (user may not exist or is not a member of the org)" -Severity "WARNING"
            }
        }
    }

    # Team repo access — catch errors gracefully
    $teamRepoResult1 = gh api -X PUT "orgs/$org/teams/$teamSlug/repos/$org/$($Names.RepoName)" -f permission="admin" 2>&1
    $teamRepoResult2 = gh api -X PUT "orgs/$org/teams/$teamSlug/repos/$org/$($Names.TemplateRepoName)" -f permission="admin" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Team granted admin on both repositories" -Severity "SUCCESS"
    } else {
        Write-Log "Team repo permissions — may require manual setup in org settings" -Severity "WARNING"
    }

    # Environments
    gh api -X PUT "repos/$org/$($Names.RepoName)/environments/$($Names.PlanEnvironment)" 2>$null
    Write-Log "Environment: $($Names.PlanEnvironment)" -Severity "SUCCESS"

    # Apply environment with team approval protection
    $teamInfo = if ($existingTeam -and $existingTeam.id) { $existingTeam }
                else { gh api "orgs/$org/teams/$teamSlug" 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue }

    if ($teamInfo -and $teamInfo.id) {
        $envPayload = @{
            reviewers = @( @{ type = "Team"; id = $teamInfo.id } )
        } | ConvertTo-Json -Depth 3 -Compress
        $envResult = $envPayload | gh api -X PUT "repos/$org/$($Names.RepoName)/environments/$($Names.ApplyEnvironment)" --input - 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Environment: $($Names.ApplyEnvironment) (protected — team approval required)" -Severity "SUCCESS"
        } else {
            gh api -X PUT "repos/$org/$($Names.RepoName)/environments/$($Names.ApplyEnvironment)" 2>$null
            Write-Log "Environment: $($Names.ApplyEnvironment) (created without team protection — configure manually)" -Severity "WARNING"
        }
    } else {
        gh api -X PUT "repos/$org/$($Names.RepoName)/environments/$($Names.ApplyEnvironment)" 2>$null
        Write-Log "Environment: $($Names.ApplyEnvironment) (team not found — configure protection manually)" -Severity "WARNING"
    }

    # Secrets
    $aksSubId = if ([string]::IsNullOrEmpty($Config.aks_landing_zone_subscription_id)) {
        (az account show --query id -o tsv)
    } else { $Config.aks_landing_zone_subscription_id }

    gh secret set "ARM_CLIENT_ID"       --repo "$org/$($Names.RepoName)" --body $Identity.ClientId  2>$null
    gh secret set "ARM_TENANT_ID"       --repo "$org/$($Names.RepoName)" --body $Identity.TenantId  2>$null
    gh secret set "ARM_SUBSCRIPTION_ID" --repo "$org/$($Names.RepoName)" --body $aksSubId            2>$null
    Write-Log "Repository secrets: ARM_CLIENT_ID, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID" -Severity "SUCCESS"

    # Variables
    gh variable set "BACKEND_RESOURCE_GROUP"  --repo "$org/$($Names.RepoName)" --body $Backend.ResourceGroupName  2>$null
    gh variable set "BACKEND_STORAGE_ACCOUNT" --repo "$org/$($Names.RepoName)" --body $Backend.StorageAccountName 2>$null
    gh variable set "BACKEND_CONTAINER"       --repo "$org/$($Names.RepoName)" --body $Backend.ContainerName      2>$null
    gh variable set "BACKEND_KEY"             --repo "$org/$($Names.RepoName)" --body $Backend.Key                2>$null
    Write-Log "Repository variables: BACKEND_RESOURCE_GROUP, BACKEND_STORAGE_ACCOUNT, BACKEND_CONTAINER, BACKEND_KEY" -Severity "SUCCESS"

    # Branch protection on main (public repos support this on GitHub Free)
    $bp = @{
        required_status_checks = @{ strict = $true; contexts = @("CI / plan") }
        required_pull_request_reviews = @{ required_approving_review_count = 1; dismiss_stale_reviews = $true }
        enforce_admins = $true
        restrictions   = $null
    } | ConvertTo-Json -Depth 4 -Compress
    $bpResult = $bp | gh api -X PUT "repos/$org/$($Names.RepoName)/branches/main/protection" --input - 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Branch protection on main (require PR + CI pass + dismiss stale reviews)" -Severity "SUCCESS"
    } else {
        Write-Log "Branch protection failed — ensure repo is public or upgrade to GitHub Pro" -Severity "WARNING"
    }

    Write-Host ""
    return $true
}

# =============================================================================
# Step 4: Deploy Self-Hosted Runner (ACI) — matches ALZ Accelerator pattern
# =============================================================================
function New-SelfHostedRunner {
    param([hashtable]$Config, [hashtable]$Names, [hashtable]$Backend)

    if ($Config.use_self_hosted_runners -ne $true) {
        Write-Log "Self-hosted runners not enabled — skipping ACI deployment." -Severity "INFO"
        Write-Host ""
        return
    }

    Write-Log "Deploying self-hosted runner infrastructure..." -Severity "INFO"

    $org = $Config.github_organization_name
    $runnerPat = if ($env:TF_VAR_github_runners_personal_access_token) {
        $env:TF_VAR_github_runners_personal_access_token
    } elseif (![string]::IsNullOrEmpty($Config.github_runners_personal_access_token) -and
              $Config.github_runners_personal_access_token -notlike "*Set via*") {
        $Config.github_runners_personal_access_token
    } else { $null }

    if ([string]::IsNullOrEmpty($runnerPat)) {
        Write-Log "Runner PAT not set. Set env:TF_VAR_github_runners_personal_access_token" -Severity "ERROR"
        Write-Log "Skipping ACI runner deployment. Workflows will not run until a self-hosted runner is registered." -Severity "WARNING"
        Write-Host ""
        return
    }

    $subscriptionId = $Backend.SubscriptionId
    $location       = $Config.bootstrap_location
    $prefix         = $Names.Prefix
    $usePrivateNet  = $Config.use_private_networking -eq $true

    # --- Derived resource names (ALZ naming pattern) ---
    $agentsRgName   = "rg-$prefix-agents"
    $networkRgName  = "rg-$prefix-network"
    $acrName        = ("acr$prefix" -replace '-','').ToLower()
    $aciName        = "aci-$prefix-runner"
    $aciMiName      = "id-$prefix-aci"
    $vnetName       = "vnet-$prefix-agents"
    $vnetAddrSpace  = "10.250.0.0/24"
    $subnetAci      = "10.250.0.0/26"
    $subnetPe       = "10.250.0.64/26"
    $natGwName      = "nat-$prefix-agents"
    $pipName        = "pip-$prefix-nat"

    # =================================================================
    # 4a. Resource Groups (agents + network)
    # =================================================================
    # Ensure the ContainerInstance resource provider is registered (idempotent).
    # New subscriptions often need this; the failure is otherwise opaque.
    $rpState = az provider show -n Microsoft.ContainerInstance --subscription $subscriptionId --query registrationState -o tsv 2>$null
    if ($rpState -ne 'Registered') {
        Write-Log "Registering resource provider Microsoft.ContainerInstance (current: $rpState)..." -Severity "INFO"
        az provider register --namespace Microsoft.ContainerInstance --subscription $subscriptionId --wait 2>&1 | Out-Null
        Write-Log "Resource provider registered: Microsoft.ContainerInstance" -Severity "SUCCESS"
    }

    az group create --name $agentsRgName --location $location --subscription $subscriptionId --output none 2>$null
    Write-Log "Resource group: $agentsRgName" -Severity "SUCCESS"

    if ($usePrivateNet) {
        az group create --name $networkRgName --location $location --subscription $subscriptionId --output none 2>$null
        Write-Log "Resource group: $networkRgName" -Severity "SUCCESS"
    }

    # =================================================================
    # 4b. Container Registry (ACR) — build runner image from Dockerfile
    # =================================================================
    $acrSku = if ($usePrivateNet) { "Premium" } else { "Basic" }
    $existingAcr = az acr show --name $acrName --resource-group $agentsRgName --subscription $subscriptionId --query name -o tsv 2>$null
    if (!$existingAcr) {
        $acrCreateArgs = @(
            "acr", "create", "--name", $acrName, "--resource-group", $agentsRgName,
            "--location", $location, "--subscription", $subscriptionId,
            "--sku", $acrSku, "--output", "none"
        )
        if ($usePrivateNet) {
            $acrCreateArgs += @("--zone-redundancy", "Enabled")
        }
        az @acrCreateArgs 2>$null
    }
    Write-Log "Container Registry: $acrName ($acrSku)" -Severity "SUCCESS"

    # ACR network rule bypass for ACR Tasks (ALZ pattern)
    if ($usePrivateNet) {
        az acr update --name $acrName --resource-group $agentsRgName --subscription $subscriptionId `
            --network-rule-bypass-option AzureServices --output none 2>$null
        Write-Log "ACR network rule bypass: AzureServices (allows ACR Tasks behind firewall)" -Severity "SUCCESS"
    }

    # Build runner image in ACR using ACR Tasks (GitHub Actions runner Dockerfile)
    # Source: https://github.com/Azure/avm-container-images-cicd-agents-and-runners (ALZ official)
    $dockerfileUrl = "https://github.com/Azure/avm-container-images-cicd-agents-and-runners.git#57a937f:github-runner-aci"
    $imageName = "github-runner:latest"
    Write-Log "Building runner image via ACR Task (this may take 2-3 minutes)..." -Severity "INFO"

    # For re-runs when ACR is already private: temporarily enable public access for build
    $acrPublicAccess = az acr show --name $acrName --resource-group $agentsRgName `
        --subscription $subscriptionId --query publicNetworkAccess -o tsv 2>$null
    $reEnablePrivate = $false
    if ($usePrivateNet -and $acrPublicAccess -eq "Disabled") {
        # Must set BOTH public-network-enabled AND default-action Allow
        # Otherwise the ACR's networkRuleSet defaultAction=Deny blocks the build agent IP
        az acr update --name $acrName --resource-group $agentsRgName --subscription $subscriptionId `
            --public-network-enabled true --default-action Allow --output none 2>$null
        $reEnablePrivate = $true
        Write-Log "Temporarily enabled ACR public access for image build" -Severity "INFO"
    } elseif ($usePrivateNet) {
        # ACR is new (public) but might get Deny rules — ensure Allow during build
        az acr update --name $acrName --resource-group $agentsRgName --subscription $subscriptionId `
            --default-action Allow --output none 2>$null
    }

    az acr build --registry $acrName --resource-group $agentsRgName --subscription $subscriptionId `
        --image $imageName --file "Dockerfile" $dockerfileUrl --no-logs --output none 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Runner image built: $acrName.azurecr.io/$imageName" -Severity "SUCCESS"
    } else {
        Write-Log "ACR build failed. Check ACR Tasks logs in Azure Portal for details." -Severity "ERROR"
        Write-Log "ACR: $acrName | RG: $agentsRgName | Subscription: $subscriptionId" -Severity "INFO"
        Write-Log "Troubleshoot: az acr task-run list --registry $acrName -o table" -Severity "INFO"
        throw "ACR image build failed. Cannot deploy ACI runner without a runner image."
    }

    # Lock down ACR after build (set/restore private access)
    if ($usePrivateNet) {
        az acr update --name $acrName --resource-group $agentsRgName --subscription $subscriptionId `
            --public-network-enabled false --default-action Deny --output none 2>$null
        Write-Log "ACR public network access disabled" -Severity "SUCCESS"
    }

    # =================================================================
    # 4c. User-Assigned Managed Identity for ACI (AcrPull)
    # =================================================================
    $existingMi = az identity show --name $aciMiName --resource-group $agentsRgName --subscription $subscriptionId --query clientId -o tsv 2>$null
    if (!$existingMi) {
        az identity create --name $aciMiName --resource-group $agentsRgName `
            --location $location --subscription $subscriptionId --output none 2>$null
    }
    $aciMi = az identity show --name $aciMiName --resource-group $agentsRgName `
        --subscription $subscriptionId --query "{clientId:clientId, principalId:principalId, id:id}" -o json 2>$null | ConvertFrom-Json
    Write-Log "Managed Identity (ACI): $aciMiName" -Severity "SUCCESS"

    # Grant AcrPull to the ACI managed identity
    $acrId = az acr show --name $acrName --resource-group $agentsRgName --subscription $subscriptionId --query id -o tsv 2>$null
    az role assignment create --assignee-object-id $aciMi.principalId --assignee-principal-type ServicePrincipal `
        --role "AcrPull" --scope $acrId --output none 2>$null
    Write-Log "Role assignment: AcrPull on $acrName" -Severity "SUCCESS"

    # =================================================================
    # 4d. Networking (VNet, subnets, NAT Gateway) — private networking
    # =================================================================
    $subnetAciId = $null
    if ($usePrivateNet) {
        # VNet
        $existingVnet = az network vnet show --name $vnetName --resource-group $networkRgName `
            --subscription $subscriptionId --query name -o tsv 2>$null
        if (!$existingVnet) {
            az network vnet create --name $vnetName --resource-group $networkRgName --location $location `
                --subscription $subscriptionId --address-prefix $vnetAddrSpace --output none 2>$null
        }
        Write-Log "VNet: $vnetName ($vnetAddrSpace)" -Severity "SUCCESS"

        # ACI subnet (delegated to Microsoft.ContainerInstance/containerGroups)
        $existingSubnet = az network vnet subnet show --name "snet-aci" --vnet-name $vnetName `
            --resource-group $networkRgName --subscription $subscriptionId --query name -o tsv 2>$null
        if (!$existingSubnet) {
            az network vnet subnet create --name "snet-aci" --vnet-name $vnetName `
                --resource-group $networkRgName --subscription $subscriptionId `
                --address-prefixes $subnetAci `
                --delegations "Microsoft.ContainerInstance/containerGroups" --output none 2>$null
        }
        $subnetAciId = az network vnet subnet show --name "snet-aci" --vnet-name $vnetName `
            --resource-group $networkRgName --subscription $subscriptionId --query id -o tsv 2>$null
        Write-Log "Subnet: snet-aci ($subnetAci) — delegated to ACI" -Severity "SUCCESS"

        # Private Endpoints subnet
        $existingPeSubnet = az network vnet subnet show --name "snet-pe" --vnet-name $vnetName `
            --resource-group $networkRgName --subscription $subscriptionId --query name -o tsv 2>$null
        if (!$existingPeSubnet) {
            az network vnet subnet create --name "snet-pe" --vnet-name $vnetName `
                --resource-group $networkRgName --subscription $subscriptionId `
                --address-prefixes $subnetPe --output none 2>$null
        }
        Write-Log "Subnet: snet-pe ($subnetPe)" -Severity "SUCCESS"

        # NAT Gateway + Public IP (outbound internet for ACI)
        $existingPip = az network public-ip show --name $pipName --resource-group $networkRgName `
            --subscription $subscriptionId --query name -o tsv 2>$null
        if (!$existingPip) {
            az network public-ip create --name $pipName --resource-group $networkRgName `
                --location $location --subscription $subscriptionId --sku Standard --allocation-method Static --output none 2>$null
        }
        $existingNat = az network nat gateway show --name $natGwName --resource-group $networkRgName `
            --subscription $subscriptionId --query name -o tsv 2>$null
        if (!$existingNat) {
            az network nat gateway create --name $natGwName --resource-group $networkRgName `
                --location $location --subscription $subscriptionId `
                --public-ip-addresses $pipName --output none 2>$null
        }
        # Associate NAT GW with ACI subnet
        az network vnet subnet update --name "snet-aci" --vnet-name $vnetName `
            --resource-group $networkRgName --subscription $subscriptionId `
            --nat-gateway $natGwName --output none 2>$null
        Write-Log "NAT Gateway: $natGwName -> snet-aci (outbound internet)" -Severity "SUCCESS"

        # --- Private Endpoints ---
        # ACR Private Endpoint
        $existingAcrPe = az network private-endpoint show --name "pe-$acrName" --resource-group $networkRgName `
            --subscription $subscriptionId --query name -o tsv 2>$null
        if (!$existingAcrPe) {
            az network private-endpoint create --name "pe-$acrName" --resource-group $networkRgName `
                --location $location --subscription $subscriptionId `
                --vnet-name $vnetName --subnet "snet-pe" `
                --private-connection-resource-id $acrId `
                --group-ids "registry" --connection-name "pe-$acrName" --output none 2>$null
        }
        Write-Log "Private Endpoint: pe-$acrName (registry)" -Severity "SUCCESS"

        # ACR Private DNS Zone
        $acrDnsZone = "privatelink.azurecr.io"
        $existingDns = az network private-dns zone show --name $acrDnsZone --resource-group $networkRgName `
            --subscription $subscriptionId --query name -o tsv 2>$null
        if (!$existingDns) {
            az network private-dns zone create --name $acrDnsZone --resource-group $networkRgName `
                --subscription $subscriptionId --output none 2>$null
            az network private-dns link vnet create --name "link-$acrName" --resource-group $networkRgName `
                --subscription $subscriptionId --zone-name $acrDnsZone `
                --virtual-network $vnetName --registration-enabled false --output none 2>$null
        }
        # DNS Zone Group on PE
        az network private-endpoint dns-zone-group create --endpoint-name "pe-$acrName" `
            --resource-group $networkRgName --subscription $subscriptionId `
            --name "default" --zone-name "acr" --private-dns-zone $acrDnsZone --output none 2>$null
        Write-Log "Private DNS: $acrDnsZone -> $vnetName" -Severity "SUCCESS"

        # Storage Account Private Endpoint  
        $storageId = az storage account show --name $Backend.StorageAccountName --resource-group $Backend.ResourceGroupName `
            --subscription $subscriptionId --query id -o tsv 2>$null
        if ($storageId) {
            $existingStPe = az network private-endpoint show --name "pe-$($Backend.StorageAccountName)" `
                --resource-group $networkRgName --subscription $subscriptionId --query name -o tsv 2>$null
            if (!$existingStPe) {
                az network private-endpoint create --name "pe-$($Backend.StorageAccountName)" `
                    --resource-group $networkRgName --location $location --subscription $subscriptionId `
                    --vnet-name $vnetName --subnet "snet-pe" `
                    --private-connection-resource-id $storageId `
                    --group-ids "blob" --connection-name "pe-$($Backend.StorageAccountName)" --output none 2>$null
            }

            # Storage Private DNS Zone
            $blobDnsZone = "privatelink.blob.core.windows.net"
            $existingBlobDns = az network private-dns zone show --name $blobDnsZone --resource-group $networkRgName `
                --subscription $subscriptionId --query name -o tsv 2>$null
            if (!$existingBlobDns) {
                az network private-dns zone create --name $blobDnsZone --resource-group $networkRgName `
                    --subscription $subscriptionId --output none 2>$null
                az network private-dns link vnet create --name "link-blob" --resource-group $networkRgName `
                    --subscription $subscriptionId --zone-name $blobDnsZone `
                    --virtual-network $vnetName --registration-enabled false --output none 2>$null
            }
            az network private-endpoint dns-zone-group create --endpoint-name "pe-$($Backend.StorageAccountName)" `
                --resource-group $networkRgName --subscription $subscriptionId `
                --name "default" --zone-name "blob" --private-dns-zone $blobDnsZone --output none 2>$null
            Write-Log "Private Endpoint: pe-$($Backend.StorageAccountName) (blob)" -Severity "SUCCESS"

            # Lock down storage account — default deny
            az storage account update --name $Backend.StorageAccountName --resource-group $Backend.ResourceGroupName `
                --subscription $subscriptionId --default-action Deny --bypass None --output none 2>$null
            Write-Log "Storage account network rules: default Deny" -Severity "SUCCESS"
        }
    }

    # =================================================================
    # 4e. Container Instance (ACI) — the runner itself
    # =================================================================
    $existing = az container show --name $aciName --resource-group $agentsRgName `
        --subscription $subscriptionId --query name -o tsv 2>$null
    if ($existing) {
        Write-Log "ACI runner already exists: $aciName" -Severity "SUCCESS"
        Write-Host ""
        return
    }

    # Determine image source
    $runnerImage = if ($imageName) {
        "$acrName.azurecr.io/$imageName"
    } else {
        "myoung34/github-runner:latest"
    }
    $useAcr = $runnerImage -like "*azurecr.io*"

    Write-Log "Creating container instance: $aciName (image: $runnerImage)" -Severity "INFO"

    # Build the az container create command
    $aciArgs = @(
        "container", "create",
        "--resource-group", $agentsRgName,
        "--subscription", $subscriptionId,
        "--name", $aciName,
        "--image", $runnerImage,
        "--os-type", "Linux",
        "--cpu", "4", "--memory", "16",
        "--restart-policy", "Always",
        "--location", $location,
        "--zone", "1",
        "--output", "none"
    )

    # Use managed identity for ACR pull
    if ($useAcr) {
        $aciArgs += @("--assign-identity", $aciMi.id)
        $aciArgs += @("--acr-identity", $aciMi.id)
    }

    # Private networking — deploy into subnet
    if ($usePrivateNet -and $subnetAciId) {
        $aciArgs += @("--subnet", $subnetAciId)
        $aciArgs += @("--ip-address", "Private")
    }

    # Environment variables (match ALZ runner image: Azure/avm-container-images-cicd-agents-and-runners)
    $aciArgs += @(
        "--environment-variables",
        "GH_RUNNER_URL=https://github.com/$org/$($Names.RepoName)",
        "GH_RUNNER_NAME=$aciName",
        "GH_RUNNER_MODE=persistent"
    )

    # Secure environment variables (PAT)
    $aciArgs += @("--secure-environment-variables", "GH_RUNNER_TOKEN=$runnerPat")

    # Execute (capture stderr so failures aren't silent)
    $aciOutput = az @aciArgs 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Log "ACI runner deployed: $aciName" -Severity "SUCCESS"
        Write-Log "Runner will auto-register with GitHub org: $org" -Severity "SUCCESS"
        if ($usePrivateNet) {
            Write-Log "Runner is deployed with private networking (VNet: $vnetName)" -Severity "SUCCESS"
        }
    } else {
        Write-Log "ACI runner deployment FAILED (exit $LASTEXITCODE)." -Severity "ERROR"
        Write-Log "az container create output:" -Severity "ERROR"
        foreach ($line in ($aciOutput | Out-String -Stream | Where-Object { $_ })) {
            Write-Log "  $line" -Severity "ERROR"
        }
        Write-Log "Re-run the bootstrap after fixing the issue; ACI creation is idempotent." -Severity "INFO"
        Write-Log "Manual retry: az container show --name $aciName --resource-group $agentsRgName --subscription $subscriptionId" -Severity "INFO"
    }
    Write-Host ""
}

# =============================================================================
# Step 5: Push Terraform Code
# =============================================================================
function Push-TerraformCode {
    param([hashtable]$Config, [hashtable]$Names, [hashtable]$Backend, [string]$TargetRoot)

    Write-Log "Pushing Terraform code to $($Config.github_organization_name)/$($Names.RepoName)..." -Severity "INFO"

    $org = $Config.github_organization_name
    $pat = if ($env:TF_VAR_github_personal_access_token) { $env:TF_VAR_github_personal_access_token } else { $env:GH_TOKEN }
    $tempDir = Join-Path $env:TEMP "aksapplz-push-$(Get-Random)"

    git clone "https://x-access-token:${pat}@github.com/$org/$($Names.RepoName).git" $tempDir 2>$null
    if (!(Test-Path $tempDir)) {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        Push-Location $tempDir
        git init 2>$null
        git remote add origin "https://x-access-token:${pat}@github.com/$org/$($Names.RepoName).git" 2>$null
        Pop-Location
    }

    # Copy Terraform files from embedded templates
    $terraformSource = Join-Path $TargetRoot "terraform"
    if (!(Test-Path $terraformSource)) {
        $terraformSource = Join-Path $script:TemplateRoot "terraform"
    }
    if (Test-Path $terraformSource) {
        Copy-Item -Path "$terraformSource\*" -Destination $tempDir -Recurse -Force
    }

    # Copy tfvars
    $tfvarsSource = Join-Path $TargetRoot "config\aks-landing-zone.tfvars"
    if (Test-Path $tfvarsSource) {
        Copy-Item $tfvarsSource -Destination (Join-Path $tempDir "aks-landing-zone.auto.tfvars") -Force
    }

    # Copy caller workflows and replace placeholders with actual names
    $workflowDir = Join-Path $tempDir ".github\workflows"
    New-Item -ItemType Directory -Path $workflowDir -Force | Out-Null
    $workflowSource = Join-Path $TargetRoot "workflows"
    if (!(Test-Path $workflowSource)) {
        $workflowSource = Join-Path $script:TemplateRoot "workflows"
    }
    if (Test-Path $workflowSource) {
        foreach ($wfFile in @("ci.yaml", "cd.yaml")) {
            $srcFile = Join-Path $workflowSource $wfFile
            if (Test-Path $srcFile) {
                $content = Get-Content $srcFile -Raw
                $content = $content -replace '__ORG_NAME__', $Config.github_organization_name
                $content = $content -replace '__TEMPLATE_REPO_NAME__', $Names.TemplateRepoName
                $content = $content -replace '__PLAN_ENVIRONMENT__', $Names.PlanEnvironment
                $content = $content -replace '__APPLY_ENVIRONMENT__', $Names.ApplyEnvironment
                $content | Set-Content -Path (Join-Path $workflowDir $wfFile) -NoNewline
            }
        }
    }

    # .gitignore
    @"
.terraform/
*.tfstate
*.tfstate.backup
*.tfplan
.terraform.lock.hcl
override.tf
override.tf.json
*_override.tf
*_override.tf.json
"@ | Set-Content -Path (Join-Path $tempDir ".gitignore")

    # Copy README.md from module templates (end-user documentation)
    $readmeSource = Join-Path $script:TemplateRoot "README.md"
    if (Test-Path $readmeSource) {
        $readmeContent = Get-Content $readmeSource -Raw
        # Replace placeholder values with actual deployment names
        $readmeContent = $readmeContent -replace '<your-org>', $Config.github_organization_name
        $readmeContent = $readmeContent -replace '<your-repo>', $Names.RepoName
        $readmeContent = $readmeContent -replace '<your-aks-subscription-id>', $Config.aks_landing_zone_subscription_id
        $readmeContent = $readmeContent -replace '<your-backend-rg>', $Backend.ResourceGroupName
        $readmeContent = $readmeContent -replace '<your-storage-account>', $Backend.StorageAccountName
        $readmeContent = $readmeContent -replace '<your-state-key>', $Backend.Key
        $readmeContent = $readmeContent -replace 'rg-<workload>-<env>-<region>', "rg-$($Config.service_name)-$($Config.environment_name)-*"
        $readmeContent = $readmeContent -replace 'aks-<workload>-<env>-<region>', "aks-$($Config.service_name)-$($Config.environment_name)-*"
        $readmeContent | Set-Content -Path (Join-Path $tempDir "README.md") -NoNewline
        Write-Log "README.md added to repository" -Severity "SUCCESS"
    }

    # Copy docs folder (deployment checklist, multi-region guide, etc.)
    $docsSource = Join-Path $script:TemplateRoot "docs"
    if (Test-Path $docsSource) {
        $docsTarget = Join-Path $tempDir "docs"
        New-Item -ItemType Directory -Path $docsTarget -Force | Out-Null
        Copy-Item -Path "$docsSource\*" -Destination $docsTarget -Recurse -Force
        Write-Log "docs/ folder added to repository" -Severity "SUCCESS"
    }

    Push-Location $tempDir
    git add -A
    # [skip ci] prevents the CD workflow from auto-triggering on the bootstrap push.
    # The user runs the first deploy manually via workflow_dispatch; future pushes trigger normally.
    git commit -m "AKS Application Landing Zone configuration [skip ci]" 2>$null
    git push origin main 2>$null
    Pop-Location

    Write-Log "Terraform code pushed to $org/$($Names.RepoName)" -Severity "SUCCESS"
    Write-Host ""

    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Step 6: Push CI/CD Templates
# =============================================================================
function Push-TemplateWorkflows {
    param([hashtable]$Config, [hashtable]$Names, [string]$TargetRoot)

    Write-Log "Pushing CI/CD templates to $($Config.github_organization_name)/$($Names.TemplateRepoName)..." -Severity "INFO"

    $org = $Config.github_organization_name
    $pat = if ($env:TF_VAR_github_personal_access_token) { $env:TF_VAR_github_personal_access_token } else { $env:GH_TOKEN }
    $tempDir = Join-Path $env:TEMP "aksapplz-templates-$(Get-Random)"

    git clone "https://x-access-token:${pat}@github.com/$org/$($Names.TemplateRepoName).git" $tempDir 2>$null

    $workflowDir = Join-Path $tempDir ".github\workflows"
    New-Item -ItemType Directory -Path $workflowDir -Force | Out-Null
    $templateSource = Join-Path $TargetRoot "workflows"
    if (Test-Path $templateSource) {
        Copy-Item -Path (Join-Path $templateSource "ci-template.yaml") -Destination $workflowDir -Force -ErrorAction SilentlyContinue
        Copy-Item -Path (Join-Path $templateSource "cd-template.yaml") -Destination $workflowDir -Force -ErrorAction SilentlyContinue
    }

    Push-Location $tempDir
    git add -A
    git commit -m "CI/CD workflow templates [skip ci]" 2>$null
    git push origin main 2>$null
    Pop-Location

    # Allow org repos to call reusable workflows from this private repo
    $headers = @{ Authorization = "Bearer $pat"; Accept = "application/vnd.github+json"; "X-GitHub-Api-Version" = "2022-11-28" }
    $accessBody = @{ access_level = "organization" } | ConvertTo-Json
    try {
        Invoke-RestMethod -Uri "https://api.github.com/repos/$org/$($Names.TemplateRepoName)/actions/permissions/access" `
            -Method PUT -Headers $headers -Body $accessBody -ContentType "application/json" | Out-Null
        Write-Log "Actions access set to 'organization' on $($Names.TemplateRepoName)" -Severity "SUCCESS"
    } catch {
        Write-Log "Warning: Could not set Actions access policy. You may need to manually allow org access in Settings > Actions > General." -Severity "WARNING"
    }

    Write-Log "Templates pushed to $org/$($Names.TemplateRepoName)" -Severity "SUCCESS"
    Write-Host ""

    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Summary
# =============================================================================
function Show-Summary {
    param([hashtable]$Config, [hashtable]$Names, [hashtable]$Backend, [hashtable]$Identity)

    $org = $Config.github_organization_name
    $runnerType = if ($Config.use_self_hosted_runners -eq $true) { "Self-hosted (ACI)" } else { "GitHub-hosted" }
    $netType    = if ($Config.use_private_networking -eq $true)  { "Private" }            else { "Public" }

    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║              Bootstrap Complete!                            ║" -ForegroundColor Green
    Write-Host "  ╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Green
    Write-Host "  ║                                                            ║" -ForegroundColor Green
    Write-Host "  ║  GitHub Repository:    $org/$($Names.RepoName)" -ForegroundColor White
    Write-Host "  ║  Templates Repository: $org/$($Names.TemplateRepoName)" -ForegroundColor White
    Write-Host "  ║  Approver Team:        $($Names.TeamName)" -ForegroundColor White
    Write-Host "  ║  Plan Environment:     $($Names.PlanEnvironment)" -ForegroundColor White
    Write-Host "  ║  Apply Environment:    $($Names.ApplyEnvironment) (team approval required)" -ForegroundColor White
    Write-Host "  ║                                                            ║" -ForegroundColor Green
    Write-Host "  ║  TF State RG:          $($Backend.ResourceGroupName)" -ForegroundColor White
    Write-Host "  ║  TF State Storage:     $($Backend.StorageAccountName)" -ForegroundColor White
    Write-Host "  ║  Identity RG:          $($Names.IdentityRgName)" -ForegroundColor White
    Write-Host "  ║  Managed Identity:     $($Names.ManagedIdentityName)" -ForegroundColor White
    Write-Host "  ║  Client ID:            $($Identity.ClientId)" -ForegroundColor White
    Write-Host "  ║  Authentication:       OIDC (Federated Credentials)" -ForegroundColor White
    Write-Host "  ║  Runners:              $runnerType ($netType networking)" -ForegroundColor White
    Write-Host "  ║                                                            ║" -ForegroundColor Green
    Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Next steps (Phase 3 - Run):" -ForegroundColor Yellow
    Write-Host "  1. Review the Terraform code in https://github.com/$org/$($Names.RepoName)"
    Write-Host "  2. Update aks-landing-zone.auto.tfvars with your specific values"
    Write-Host "  3. Create a branch, commit changes, and open a Pull Request"
    Write-Host "  4. CI will automatically run 'terraform plan'"
    Write-Host "  5. Merge the PR to main -> CD will run plan -> wait for team approval -> apply"
    Write-Host "  6. Use 'workflow_dispatch' on the CD workflow to trigger apply/destroy manually"
    Write-Host ""
}

# =============================================================================
# Destroy
# =============================================================================
function Invoke-Destroy {
    Write-Log "Destroying bootstrapped resources..." -Severity "WARNING"
    Write-Host ""
    Write-Host "  This will destroy:" -ForegroundColor DarkYellow
    Write-Host "     - Terraform state storage account and resource group"
    Write-Host "     - Managed identity and federated credentials"
    Write-Host "     - GitHub repositories, teams, and environments"
    Write-Host ""
    Write-Host "  This will NOT destroy:" -ForegroundColor DarkYellow
    Write-Host "     - Azure subscriptions"
    Write-Host "     - Any resources deployed by Terraform (AKS, VNet, etc.)"
    Write-Host "     - Entra ID groups"
    Write-Host ""

    $confirm = Read-Host "  Type 'yes' to confirm destruction"
    if ($confirm -ne "yes") {
        Write-Log "Cancelled." -Severity "WARNING"
        return
    }

    Write-Host ""
    Write-Log "To fully destroy, run the following steps:" -Severity "INFO"
    Write-Host ""
    Write-Host "  # 1. First destroy Terraform-managed resources (AKS, VNet, etc.)" -ForegroundColor DarkGray
    Write-Host "  cd <repo-clone> && terraform destroy -auto-approve" -ForegroundColor White
    Write-Host ""
    Write-Host "  # 2. Then delete bootstrap resources" -ForegroundColor DarkGray
    Write-Host "  az group delete --name <rg-name> --yes" -ForegroundColor White
    Write-Host "  gh repo delete <org>/<repo> --yes" -ForegroundColor White
    Write-Host "  gh repo delete <org>/<repo>-templates --yes" -ForegroundColor White
    Write-Host ""
}


# =============================================================================
# Terraform-based Bootstrap (Phase 7 — AVM)
# =============================================================================
# Renders bootstrap/alz/github/terraform.tfvars.json from the wizard config
# and the repository_files map (terraform/*.tf + workflows/*.yaml) that the
# github module pushes into the workload repository.

function New-TerraformTfvarsJson {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$BootstrapRoot,
        [Parameter(Mandatory)][hashtable]$RepositoryFiles
    )

    # Pass-through map: every wizard input the workload repo will need at apply time.
    # Stored verbatim under aks_landing_zone_inputs so the workload tfvars can
    # reference whatever fields it wants.
    $passThrough = @{}
    foreach ($k in $Config.Keys) {
        # Strip PATs and noise; never write secrets into tfvars.json.
        if ($k -in @('github_personal_access_token','github_runners_personal_access_token')) { continue }
        $passThrough[$k] = $Config[$k]
    }

    $tfvars = [ordered]@{
        scenario                              = $Config.scenario
        bootstrap_location                    = $Config.bootstrap_location
        secondary_location                    = $Config.secondary_location
        service_name                          = $Config.service_name
        environment_name                      = $Config.environment_name
        postfix_number                        = [int]$Config.postfix_number
        tenant_id                             = $Config.tenant_id
        bootstrap_subscription_id             = $Config.bootstrap_subscription_id
        aks_landing_zone_subscription_id      = $Config.aks_landing_zone_subscription_id
        connectivity_subscription_id          = $Config.connectivity_subscription_id
        hub_vnet_resource_id                  = $Config.hub_vnet_resource_id
        hub_vnet_name                         = $Config.hub_vnet_name
        hub_vnet_resource_group_name          = $Config.hub_vnet_resource_group_name
        hub_firewall_private_ip               = $Config.hub_firewall_private_ip
        github_organization_name              = $Config.github_organization_name
        apply_approvers                       = @($Config.apply_approvers)
        use_self_hosted_runners               = [bool]$Config.use_self_hosted_runners
        use_private_networking                = [bool]$Config.use_private_networking
        repository_files                      = $RepositoryFiles
        aks_landing_zone_inputs               = $passThrough
        tags                                  = @{ managedBy = "aksapplz-bootstrap-terraform"; service = $Config.service_name; environment = $Config.environment_name }
    }

    $outPath = Join-Path $BootstrapRoot "terraform.tfvars.json"
    $json    = $tfvars | ConvertTo-Json -Depth 12
    Set-Content -Path $outPath -Value $json -Encoding UTF8
    Write-Log "Wrote $outPath" -Severity "SUCCESS"
    return $outPath
}

function Get-RepositoryFilesMap {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [string]$TemplateRoot
    )

    if ([string]::IsNullOrEmpty($TemplateRoot)) { $TemplateRoot = $script:TemplateRoot }

    $files = @{}

    # Terraform code -> /terraform/*.tf in the workload repo
    $tfSrc = Join-Path $TemplateRoot "terraform"
    if (Test-Path $tfSrc) {
        foreach ($f in Get-ChildItem -Path $tfSrc -Recurse -File) {
            $rel = "terraform/$($f.Name)"
            $files[$rel] = (Get-Content $f.FullName -Raw)
        }
    }

    # Workflows (caller copies only — templates stay private to the workload repo)
    $wfSrc = Join-Path $TemplateRoot "workflows"
    if (Test-Path $wfSrc) {
        # Resolve the template repo (owner/name) that hosts the reusable
        # cd-template.yaml / ci-template.yaml workflows.
        # Priority: explicit config override -> derive from local git remote.
        $templateRepo = $null
        if ($Config.ContainsKey('template_repository') -and -not [string]::IsNullOrWhiteSpace($Config.template_repository)) {
            $templateRepo = [string]$Config.template_repository
        } else {
            try {
                $remoteUrl = (& git -C (Split-Path $TemplateRoot -Parent) remote get-url origin 2>$null)
                if ($remoteUrl -match 'github\.com[:/]+([^/]+/[^/.]+)') { $templateRepo = $Matches[1] }
            } catch { }
        }
        if ([string]::IsNullOrWhiteSpace($templateRepo)) {
            $templateRepo = "$($Config.github_organization_name)/__TEMPLATE_REPO_NAME__"
            Write-Log "template_repository not set and git remote not resolvable; workload workflows will keep '__TEMPLATE_REPO_NAME__' placeholder." -Severity "WARNING"
        }
        $templateOrg  = ($templateRepo -split '/')[0]
        $templateName = ($templateRepo -split '/')[1]
        foreach ($wfFile in @("ci.yaml","cd.yaml")) {
            $p = Join-Path $wfSrc $wfFile
            if (Test-Path $p) {
                $content = Get-Content $p -Raw
                # Best-effort placeholder substitution — workload workflows are simple.
                # __ORG_NAME__ + __TEMPLATE_REPO_NAME__ together form the `uses:` ref
                # pointing at the template repo that owns the reusable workflow.
                $content = $content -replace '__ORG_NAME__',           $templateOrg
                $content = $content -replace '__TEMPLATE_REPO_NAME__', $templateName
                $content = $content -replace '__PLAN_ENVIRONMENT__',  "plan"
                $content = $content -replace '__APPLY_ENVIRONMENT__', "apply"
                $files[".github/workflows/$wfFile"] = $content
            }
        }
    }

    # tfvars file (rendered from wizard answers) -> aks-landing-zone.auto.tfvars
    # Reuse Write-TfvarsFile by piping its output through a temp file.
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        Write-TfvarsFile -Config $Config -OutputPath $tmp
        $files["aks-landing-zone.auto.tfvars"] = (Get-Content $tmp -Raw)
    } finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }

    # .gitignore — keep workload repo tidy
    $files[".gitignore"] = @"
.terraform/
*.tfstate
*.tfstate.backup
*.tfplan
.terraform.lock.hcl
"@

    return $files
}

# =============================================================================
# ████████  PUBLIC FUNCTION: Deploy-AKSLandingZone (Terraform)  ████████
# =============================================================================

<#
.SYNOPSIS
    Deploy the AKS Application Landing Zone bootstrap using the Terraform composition.

.DESCRIPTION
    Single entry point for both interactive and advanced (non-interactive) workflows.

    INTERACTIVE MODE (recommended) — invoke without -InputConfigPath. The cmdlet
    walks you through every decision, writes `<repo>/config/inputs.yaml` for you,
    asks for confirmation, then renders `bootstrap/alz/github/terraform.tfvars.json`
    and runs `terraform init` + `plan` + `apply` against the bootstrap composition.

    ADVANCED MODE — pass -InputConfigPath pointing to a pre-filled inputs.yaml.
    Skips the wizard and goes straight to render + Terraform.

    Idempotent; safe to re-run.

.PARAMETER InputConfigPath
    Path to a wizard-generated inputs.yaml. Omit to run the interactive wizard
    (the wizard will write `<repo>/config/inputs.yaml` and use it).

.PARAMETER BootstrapRoot
    Optional. Defaults to `<repo>/bootstrap/alz/github` (the Terraform composition shipped with this module).

.PARAMETER AutoApprove
    Pass `-auto-approve` to `terraform apply` (and skip the post-wizard "ready to bootstrap?" prompt).

.PARAMETER PlanOnly
    Run `terraform init` + `terraform plan` and stop.

.PARAMETER SkipPreflight
    Skip tool / `az login` / Microsoft.ContainerInstance RP / PAT checks. Advanced.

.EXAMPLE
    # Interactive (recommended)
    Deploy-AKSLandingZone

.EXAMPLE
    # Advanced — bring your own inputs.yaml
    $env:TF_VAR_github_personal_access_token         = 'github_pat_...'
    $env:TF_VAR_github_runners_personal_access_token = 'github_pat_...'
    Deploy-AKSLandingZone -InputConfigPath .\config\inputs.yaml -AutoApprove
#>
function Deploy-AKSLandingZone {
    [CmdletBinding()]
    param(
        [Parameter()][string]$InputConfigPath,
        [Parameter()][string]$BootstrapRoot,
        [Parameter()][string]$Environment,
        [Parameter()][switch]$AutoApprove,
        [Parameter()][switch]$PlanOnly,
        [Parameter()][switch]$SkipPreflight
    )

    Show-Banner
    Write-Log "=== AKS Application Landing Zone — Bootstrap ===" -Severity "INFO"

    # Validate -Environment naming (matches workload-side validation: 1-8 lowercase alphanumeric)
    if (-not [string]::IsNullOrWhiteSpace($Environment)) {
        if ($Environment -notmatch '^[a-z0-9]{1,8}$') {
            Write-Log "-Environment '$Environment' is invalid. Must be 1-8 lowercase alphanumeric characters." -Severity "ERROR"
            return
        }
        Write-Log "Environment scope: $Environment" -Severity "INFO"
    }

    # When -Environment is set but no -InputConfigPath, default to per-env config file
    if (-not [string]::IsNullOrWhiteSpace($Environment) -and [string]::IsNullOrEmpty($InputConfigPath)) {
        $repoRoot  = Split-Path -Parent $script:ModuleRoot
        $candidate = Join-Path $repoRoot "config/inputs.$Environment.yaml"
        if (Test-Path $candidate) {
            $InputConfigPath = $candidate
            Write-Log "Resolved -InputConfigPath from -Environment: $InputConfigPath" -Severity "INFO"
        } else {
            Write-Log "No config file at $candidate — falling through to interactive wizard." -Severity "INFO"
        }
    }

    # ── Interactive wizard fallback when no config supplied ──
    if ([string]::IsNullOrEmpty($InputConfigPath)) {
        Write-Log "No -InputConfigPath provided — running interactive wizard." -Severity "INFO"

        $repoRoot  = Split-Path -Parent $script:ModuleRoot
        $configDir = Join-Path $repoRoot "config"
        if (!(Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }

        Write-Log "Querying Azure for subscriptions and regions..." -Severity "INFO"
        $azureContext = Get-AzureContext

        $config = Get-InteractiveInputs -AzureContext $azureContext
        if ($null -eq $config) {
            Write-Log "Wizard cancelled — no configuration written." -Severity "WARN"
            return
        }

        # If -Environment was passed, override the wizard-collected environment_name so
        # per-env files are written to predictable paths.
        if (-not [string]::IsNullOrWhiteSpace($Environment)) {
            $config.environment_name = $Environment
            Write-Log "Overrode environment_name to '$Environment' from -Environment parameter." -Severity "INFO"
        }

        $envSuffix = if (-not [string]::IsNullOrWhiteSpace($config.environment_name)) { ".$($config.environment_name)" } else { "" }
        $InputConfigPath = Join-Path $configDir "inputs$envSuffix.yaml"
        $tfvarsPath      = Join-Path $configDir "aks-landing-zone$envSuffix.tfvars"
        Write-InputsYaml -Config $config -OutputPath $InputConfigPath
        Write-TfvarsFile -Config $config -OutputPath $tfvarsPath
        Write-Log "Configuration written to $InputConfigPath" -Severity "SUCCESS"
        if (-not [string]::IsNullOrWhiteSpace($Environment)) {
            Write-Log "Re-run later with: Deploy-AKSLandingZone -Environment $Environment" -Severity "INFO"
        }

        Write-Host ""
        Write-Log "PAT tokens are read from environment variables (never written to disk):" -Severity "INFO"
        Write-Host "  TF_VAR_github_personal_access_token" -ForegroundColor Yellow
        Write-Host "  TF_VAR_github_runners_personal_access_token  (only if use_self_hosted_runners = true)" -ForegroundColor Yellow
        Write-Host ""

        if (-not $AutoApprove -and -not $PlanOnly) {
            Write-Log "Ready to run the Terraform bootstrap now?" -Severity "INPUT REQUIRED"
            $proceed = Read-Host "Enter '[y]es' to continue or '[n]o' to stop here and review files"
            if ($proceed -ne "y" -and $proceed -ne "yes") {
                Write-Log "Stopped. Re-run with: Deploy-AKSLandingZone -InputConfigPath `"$InputConfigPath`"" -Severity "INFO"
                return
            }
        }
    }

    # ── Resolve bootstrap composition path ──
    if ([string]::IsNullOrEmpty($BootstrapRoot)) {
        $repoRoot      = Split-Path -Parent $script:ModuleRoot
        $BootstrapRoot = Join-Path $repoRoot "bootstrap/alz/github"
    }
    if (!(Test-Path $BootstrapRoot)) {
        Write-Log "Bootstrap root not found: $BootstrapRoot" -Severity "ERROR"
        Write-Log "Pass -BootstrapRoot pointing to <repo>/bootstrap/alz/github." -Severity "INFO"
        return
    }
    Write-Log "Bootstrap composition: $BootstrapRoot" -Severity "INFO"

    # ── Preflight ──
    if (!$SkipPreflight) {
        foreach ($cmd in @('terraform','az','gh')) {
            if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
                Write-Log "Required tool not found on PATH: $cmd" -Severity "ERROR"
                return
            }
        }
        $tfVer = (terraform version -json | ConvertFrom-Json).terraform_version
        Write-Log "terraform $tfVer detected" -Severity "SUCCESS"

        $acct = az account show -o json 2>$null | ConvertFrom-Json
        if (-not $acct) { Write-Log "az not logged in. Run 'az login'." -Severity "ERROR"; return }
        Write-Log "az logged in as $($acct.user.name), tenant $($acct.tenantId)" -Severity "SUCCESS"

        # Register Microsoft.ContainerInstance (idempotent — Terraform cannot
        # cleanly own this because the RP is often already registered).
        Write-Log "Ensuring Microsoft.ContainerInstance resource provider is registered..." -Severity "INFO"
        $rpState = (az provider show --namespace Microsoft.ContainerInstance --query registrationState -o tsv 2>$null)
        if ($rpState -ne 'Registered') {
            az provider register --namespace Microsoft.ContainerInstance --wait | Out-Null
            Write-Log "Microsoft.ContainerInstance registered." -Severity "SUCCESS"
        } else {
            Write-Log "Microsoft.ContainerInstance already registered." -Severity "SUCCESS"
        }

        if ([string]::IsNullOrEmpty($env:TF_VAR_github_personal_access_token)) {
            Write-Log "TF_VAR_github_personal_access_token is not set." -Severity "ERROR"
            Write-Log "Export a fine-grained PAT (admin:org + repo) before re-running." -Severity "INFO"
            return
        }
    }

    # ── Load wizard config ──
    if (!(Test-Path $InputConfigPath)) {
        Write-Log "Input config not found: $InputConfigPath" -Severity "ERROR"; return
    }
    Write-Log "Loading $InputConfigPath" -Severity "INFO"
    $config = Read-FlatYaml -Path $InputConfigPath

    # -Environment overrides the value in the loaded config (keeps resource naming consistent).
    if (-not [string]::IsNullOrWhiteSpace($Environment)) {
        if ($config.environment_name -and $config.environment_name -ne $Environment) {
            Write-Log "Overriding config environment_name '$($config.environment_name)' with -Environment '$Environment'." -Severity "WARNING"
        }
        $config.environment_name = $Environment
    }

    # Make sure tenant_id is present (Read-FlatYaml does not derive it).
    if ([string]::IsNullOrEmpty($config.tenant_id)) {
        $config.tenant_id = (az account show --query tenantId -o tsv).Trim()
        Write-Log "Derived tenant_id from az context: $($config.tenant_id)" -Severity "INFO"
    }

    # ── Topology validation ──
    if ([string]::IsNullOrWhiteSpace([string]$config.topology)) {
        $config.topology = 'spoke'
        Write-Log "topology not set in inputs — defaulting to 'spoke' for back-compat." -Severity "WARNING"
    }
    $allowedTopologies = @('spoke','standalone','hub_and_spoke')
    if ($allowedTopologies -notcontains $config.topology) {
        Write-Log "topology '$($config.topology)' is invalid. Allowed: $($allowedTopologies -join ', ')." -Severity "ERROR"
        return
    }
    if ($config.topology -eq 'spoke') {
        $reqSpoke = @('connectivity_subscription_id','hub_vnet_resource_id','hub_vnet_name','hub_vnet_resource_group_name','hub_firewall_private_ip')
        $missing = $reqSpoke | Where-Object { [string]::IsNullOrWhiteSpace([string]$config.$_) }
        if ($missing.Count -gt 0) {
            Write-Log "topology=spoke is missing required hub fields: $($missing -join ', ')" -Severity "ERROR"
            return
        }
    }
    if ($config.topology -eq 'standalone') {
        $hubFields = @('connectivity_subscription_id','hub_vnet_resource_id','hub_vnet_name','hub_vnet_resource_group_name','hub_firewall_private_ip')
        $stale = $hubFields | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$config.$_) }
        if ($stale.Count -gt 0) {
            Write-Log "topology=standalone but hub fields were set; clearing: $($stale -join ', ')" -Severity "WARNING"
            foreach ($f in $stale) { $config.$f = "" }
        }
    }
    if ($config.topology -eq 'hub_and_spoke') {
        if ([string]::IsNullOrWhiteSpace([string]$config.connectivity_subscription_id)) {
            Write-Log "topology=hub_and_spoke requires connectivity_subscription_id (where the new hub will be created)." -Severity "ERROR"
            return
        }
        if (-not $config.hub_vnet_address_space -or $config.hub_vnet_address_space.Count -eq 0) {
            $config.hub_vnet_address_space = @("10.0.0.0/16")
            Write-Log "hub_vnet_address_space not set — defaulting to 10.0.0.0/16." -Severity "WARNING"
        }
        if ([string]::IsNullOrWhiteSpace([string]$config.hub_firewall_subnet_address_prefix)) {
            $config.hub_firewall_subnet_address_prefix = "10.0.0.0/26"
        }
        if ($null -eq $config.hub_deploy_firewall) {
            $config.hub_deploy_firewall = $true
        }
        if ([string]::IsNullOrWhiteSpace([string]$config.hub_firewall_sku_tier)) {
            $config.hub_firewall_sku_tier = "Standard"
        }
    }

    # ── Hub composition (greenfield) ──
    # When topology=hub_and_spoke, run bootstrap/alz/hub/ first to create the hub VNet
    # (+ optional Azure Firewall), then populate $config.hub_* from its outputs so the
    # downstream render + spoke bootstrap pick them up transparently.
    if ($config.topology -eq 'hub_and_spoke') {
        $repoRootForHub = Split-Path -Parent $script:ModuleRoot
        $hubRoot        = Join-Path $repoRootForHub "bootstrap/alz/hub"
        if (!(Test-Path $hubRoot)) {
            Write-Log "Hub composition not found at $hubRoot." -Severity "ERROR"; return
        }
        Write-Log "Hub composition: $hubRoot" -Severity "INFO"

        $hubTfvars = [ordered]@{
            connectivity_subscription_id   = [string]$config.connectivity_subscription_id
            tenant_id                      = [string]$config.tenant_id
            location                       = [string]$config.bootstrap_location
            service_name                   = [string]$config.service_name
            environment_name               = [string]$config.environment_name
            postfix_number                 = if ($config.postfix_number) { [int]$config.postfix_number } else { 1 }
            hub_vnet_address_space         = @($config.hub_vnet_address_space)
            deploy_firewall                = [bool]$config.hub_deploy_firewall
            firewall_sku_tier              = [string]$config.hub_firewall_sku_tier
            firewall_subnet_address_prefix = [string]$config.hub_firewall_subnet_address_prefix
        }
        $hubTfvarsPath = Join-Path $hubRoot "terraform.tfvars.json"
        $hubTfvars | ConvertTo-Json -Depth 10 | Set-Content -Path $hubTfvarsPath -Encoding UTF8
        Write-Log "Wrote $hubTfvarsPath" -Severity "SUCCESS"

        Push-Location $hubRoot
        try {
            Write-Log "Initialising hub composition..." -Severity "INFO"
            & terraform @('init','-input=false','-upgrade')
            if ($LASTEXITCODE -ne 0) { Write-Log "Hub terraform init failed." -Severity "ERROR"; return }

            # Per-env workspace for hub state too.
            $hubWs = if (-not [string]::IsNullOrWhiteSpace($Environment)) { $Environment } else { $config.environment_name }
            if (-not [string]::IsNullOrWhiteSpace($hubWs)) {
                & terraform workspace select $hubWs 2>$null
                if ($LASTEXITCODE -ne 0) {
                    & terraform workspace new $hubWs
                    if ($LASTEXITCODE -ne 0) { Write-Log "Hub workspace new failed." -Severity "ERROR"; return }
                }
            }

            if ($PlanOnly) {
                Write-Log "Hub: terraform plan (-PlanOnly mode)..." -Severity "INFO"
                & terraform @('plan','-input=false','-out=hub.tfplan')
                if ($LASTEXITCODE -ne 0) { Write-Log "Hub terraform plan failed." -Severity "ERROR"; return }
            } else {
                $applyArgs = @('apply','-input=false')
                if ($AutoApprove) { $applyArgs += '-auto-approve' }
                Write-Log "Hub: terraform apply..." -Severity "INFO"
                & terraform @applyArgs
                if ($LASTEXITCODE -ne 0) { Write-Log "Hub terraform apply failed." -Severity "ERROR"; return }

                $hubOut = (& terraform output -json) | ConvertFrom-Json
                $config.hub_vnet_resource_id          = [string]$hubOut.hub_vnet_resource_id.value
                $config.hub_vnet_name                 = [string]$hubOut.hub_vnet_name.value
                $config.hub_vnet_resource_group_name  = [string]$hubOut.hub_vnet_resource_group_name.value
                $config.hub_firewall_private_ip       = [string]$hubOut.hub_firewall_private_ip.value
                Write-Log "Hub ready:" -Severity "SUCCESS"
                Write-Host "    hub_vnet_resource_id    = $($config.hub_vnet_resource_id)" -ForegroundColor White
                Write-Host "    hub_vnet_name           = $($config.hub_vnet_name)" -ForegroundColor White
                Write-Host "    hub_vnet_resource_group = $($config.hub_vnet_resource_group_name)" -ForegroundColor White
                Write-Host "    hub_firewall_private_ip = $($config.hub_firewall_private_ip)" -ForegroundColor White
            }
        }
        finally { Pop-Location }

        if ($PlanOnly) {
            Write-Log "PlanOnly: skipping spoke phase (hub_* are not populated without an apply). Re-run without -PlanOnly to continue." -Severity "INFO"
            return
        }
    }

    # ── Build repository_files map ──
    Write-Log "Building repository_files map from /terraform and /workflows templates..." -Severity "INFO"
    $repoFiles = Get-RepositoryFilesMap -Config $config
    Write-Log "Repository files: $($repoFiles.Keys.Count) entries" -Severity "SUCCESS"

    # ── Render terraform.tfvars.json ──
    $tfvarsJson = New-TerraformTfvarsJson -Config $config -BootstrapRoot $BootstrapRoot -RepositoryFiles $repoFiles

    # ── terraform init + workspace + plan/apply ──
    Push-Location $BootstrapRoot
    try {
        # Cross-env safety: if a backend.tf from a different environment is still on
        # disk (each env writes its own remote backend in its own storage account),
        # or if cached .terraform metadata points at a different workspace, wipe those
        # artefacts so this run starts with a clean local init. The remote state for
        # each env is safe in its own storage account.
        $backendTfPath = Join-Path $BootstrapRoot "backend.tf"
        $envMarker     = Join-Path $BootstrapRoot ".terraform/environment"
        $targetEnv     = if (-not [string]::IsNullOrWhiteSpace($Environment)) { $Environment } else { [string]$config.environment_name }
        $shouldClean   = $false
        if (Test-Path $backendTfPath) {
            $existingBackend = Get-Content $backendTfPath -Raw
            # backend.tf for env X always contains the env token inside the SA's RG name
            # (rg-<service>-<env>-state-…) and the SA name. If the current target env
            # token is missing, the backend belongs to another env.
            if (-not [string]::IsNullOrWhiteSpace($targetEnv) -and $existingBackend -notmatch "(?i)-$([regex]::Escape($targetEnv))-") {
                Write-Log "Detected backend.tf from a different environment (current target='$targetEnv'); cleaning local Terraform artefacts before init." -Severity "WARNING"
                $shouldClean = $true
            }
        }
        if (-not $shouldClean -and (Test-Path $envMarker)) {
            $cachedWs = (Get-Content $envMarker -ErrorAction SilentlyContinue).Trim()
            if (-not [string]::IsNullOrWhiteSpace($cachedWs) -and -not [string]::IsNullOrWhiteSpace($targetEnv) -and $cachedWs -ne $targetEnv -and -not (Test-Path $backendTfPath)) {
                Write-Log "Cached workspace '$cachedWs' differs from target '$targetEnv'; cleaning local Terraform artefacts." -Severity "WARNING"
                $shouldClean = $true
            }
        }
        if ($shouldClean) {
            foreach ($p in @("$BootstrapRoot\backend.tf", "$BootstrapRoot\.terraform", "$BootstrapRoot\.terraform.lock.hcl", "$BootstrapRoot\terraform.tfstate", "$BootstrapRoot\terraform.tfstate.backup")) {
                if (Test-Path $p) { Remove-Item -Path $p -Recurse -Force -ErrorAction SilentlyContinue }
            }
            Write-Log "Local Terraform artefacts cleaned. Remote state in the prior env's storage account is unaffected." -Severity "INFO"
        }

        Write-Log "Running terraform init..." -Severity "INFO"
        $initArgs = @('init','-input=false','-upgrade')
        & terraform @initArgs
        if ($LASTEXITCODE -ne 0) { Write-Log "terraform init failed." -Severity "ERROR"; return }

        # Per-environment state isolation: select or create a Terraform workspace named
        # after the environment so each env (dev/test/qa/prod/standalone/…) keeps its own
        # state file inside the same bootstrap composition.
        $workspaceName = if (-not [string]::IsNullOrWhiteSpace($Environment)) { $Environment } else { $config.environment_name }
        if (-not [string]::IsNullOrWhiteSpace($workspaceName)) {
            $currentWs = (& terraform workspace show).Trim()
            if ($currentWs -ne $workspaceName) {
                & terraform workspace select $workspaceName 2>$null
                if ($LASTEXITCODE -ne 0) {
                    Write-Log "Creating new Terraform workspace '$workspaceName' for state isolation." -Severity "INFO"
                    & terraform workspace new $workspaceName
                    if ($LASTEXITCODE -ne 0) { Write-Log "terraform workspace new failed." -Severity "ERROR"; return }
                } else {
                    Write-Log "Selected Terraform workspace '$workspaceName'." -Severity "INFO"
                }
            } else {
                Write-Log "Already on Terraform workspace '$workspaceName'." -Severity "INFO"
            }
        }

        if ($PlanOnly) {
            Write-Log "Running terraform plan (-PlanOnly mode)..." -Severity "INFO"
            $planArgs = @('plan','-input=false','-out=bootstrap.tfplan')
            & terraform @planArgs
            if ($LASTEXITCODE -ne 0) { Write-Log "terraform plan failed." -Severity "ERROR"; return }
            Write-Log "Plan saved to bootstrap.tfplan. Exiting (PlanOnly)." -Severity "SUCCESS"
            return
        }

        $applyArgs = @('apply','-input=false')
        if ($AutoApprove) { $applyArgs += '-auto-approve' }
        Write-Log "Running terraform apply..." -Severity "INFO"
        & terraform @applyArgs
        if ($LASTEXITCODE -ne 0) { Write-Log "terraform apply failed." -Severity "ERROR"; return }

        # ── Capture outputs ──
        $outputs = (& terraform output -json) | ConvertFrom-Json
        $rg      = $outputs.backend_resource_group_name.value
        $sa      = $outputs.backend_storage_account_name.value
        $ct      = $outputs.backend_container_name.value
        $repoUrl = $outputs.repository_html_url.value
        Write-Log "Backend: rg=$rg sa=$sa container=$ct" -Severity "SUCCESS"
        Write-Log "Workload repo: $repoUrl" -Severity "SUCCESS"

        # ── Migrate state to the storage account just created ──
        $backendTf = @"
terraform {
  backend "azurerm" {
    resource_group_name  = "$rg"
    storage_account_name = "$sa"
    container_name       = "$ct"
    key                  = "bootstrap.tfstate"
    use_azuread_auth     = true
    subscription_id      = "$($config.bootstrap_subscription_id)"
    tenant_id            = "$($config.tenant_id)"
  }
}
"@
        $backendPath = Join-Path $BootstrapRoot "backend.tf"
        Set-Content -Path $backendPath -Value $backendTf -Encoding UTF8
        Write-Log "Wrote $backendPath" -Severity "SUCCESS"

        # ── Grant the local operator data-plane access on the SA before migrating ──
        # The bootstrap composition only assigns Storage Blob Data Contributor to the
        # 'apply' / 'plan' managed identities. The local user running this cmdlet owns
        # the SA at the control plane but has no data-plane RBAC, so
        # `terraform init -migrate-state` (which uses use_azuread_auth=true) returns
        # 403 AuthorizationPermissionMismatch. Grant the role idempotently and wait
        # briefly for propagation.
        $saResourceId = "/subscriptions/$($config.bootstrap_subscription_id)/resourceGroups/$rg/providers/Microsoft.Storage/storageAccounts/$sa"
        $signedInId   = (az ad signed-in-user show --query id -o tsv 2>$null)
        if ([string]::IsNullOrWhiteSpace($signedInId)) {
            $signedInId = (az account show --query user.name -o tsv 2>$null)
            Write-Log "Could not resolve signed-in user objectId; falling back to UPN '$signedInId' for role assignment." -Severity "WARNING"
        }
        if (-not [string]::IsNullOrWhiteSpace($signedInId)) {
            Write-Log "Granting Storage Blob Data Contributor on $sa to current operator ($signedInId)..." -Severity "INFO"
            $raOutput = az role assignment create `
                --assignee-object-id $signedInId `
                --assignee-principal-type User `
                --role "Storage Blob Data Contributor" `
                --scope $saResourceId `
                --subscription $config.bootstrap_subscription_id 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "Role assignment created. Waiting 30s for RBAC propagation..." -Severity "SUCCESS"
                Start-Sleep -Seconds 30
            } elseif ($raOutput -match 'already exists|RoleAssignmentExists') {
                Write-Log "Role assignment already exists; continuing." -Severity "INFO"
            } else {
                Write-Log "Could not create role assignment: $raOutput" -Severity "WARNING"
                Write-Log "Migration may still fail with 403; fall back to: az role assignment create --assignee <you> --role 'Storage Blob Data Contributor' --scope $saResourceId" -Severity "WARNING"
            }
        }

        Write-Log "Migrating state to azurerm backend..." -Severity "INFO"
        $migrateArgs = @('init','-migrate-state','-force-copy','-input=false')
        & terraform @migrateArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Log "State migration failed. Local state is still authoritative; you can re-run with -SkipPreflight after RBAC propagates." -Severity "WARNING"
        } else {
            Write-Log "State migrated to $sa/$ct/bootstrap.tfstate" -Severity "SUCCESS"
        }

        Write-Host ""
        Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "  ║   Terraform Bootstrap Complete                              ║" -ForegroundColor Green
        Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
        Write-Host "  Workload repository : $repoUrl" -ForegroundColor White
        Write-Host "  Backend             : $sa / $ct" -ForegroundColor White
        Write-Host "  Identities          : $($outputs.managed_identity_client_ids.value | ConvertTo-Json -Compress)" -ForegroundColor White
        if ($outputs.container_registry_login_server.value) {
            Write-Host "  ACR / runner image  : $($outputs.runner_image.value)" -ForegroundColor White
        }
        Write-Host ""
        Write-Host "  Next: open the workload repo, review files, then trigger the CD workflow." -ForegroundColor Yellow
    }
    finally {
        Pop-Location
    }
}

# =============================================================================
# ████████  PUBLIC FUNCTION: Deploy-AKSLandingZoneLegacy  ████████
# =============================================================================

<#
.SYNOPSIS
    Deploy an AKS Application Landing Zone into an existing Azure Landing Zone.

.DESCRIPTION
    Interactive wizard that mirrors the Azure Landing Zone Accelerator (Deploy-Accelerator)
    deployment experience. No repository cloning needed — the module ships with all
    Terraform, workflow, and configuration templates embedded.

    Run without parameters to start the interactive wizard.
    The wizard generates configuration files in a target folder and stops.
    Then re-run with -InputConfigPath to execute the bootstrap.

.PARAMETER InputConfigPath
    Path to the inputs.yaml configuration file. When provided, runs in execution mode.
    When omitted, the script runs in interactive mode, generates config files, and stops.

.PARAMETER Destroy
    Destroy the bootstrapped resources (Terraform state, identity, GitHub repos).

.EXAMPLE
    # Install the module
    Install-PSResource -Name ALZ.AKS

    # Run the interactive wizard (generates config files, stops)
    Deploy-AKSLandingZoneLegacy

    # Review config files in VS Code, then execute the bootstrap
    Deploy-AKSLandingZoneLegacy -InputConfigPath ~/aksapplz/config/inputs.yaml

    # Destroy bootstrapped resources
    Deploy-AKSLandingZoneLegacy -Destroy
#>
function Deploy-AKSLandingZoneLegacy {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$InputConfigPath,

        [Parameter()]
        [switch]$Destroy,

        [Parameter()]
        [switch]$Force
    )

    $ErrorActionPreference = "Stop"
    $InformationPreference = "Continue"

    Show-Banner

    # --- Destroy mode ---
    if ($Destroy) {
        Invoke-Destroy
        return
    }

    # --- Prerequisites (always run) ---
    $account = Test-SoftwareRequirements
    if ($null -eq $account) {
        return
    }

    $isAdvanced = ![string]::IsNullOrEmpty($InputConfigPath)

    # =========================================================================
    # MODE A: EXECUTION (with -InputConfigPath)
    # =========================================================================
    if ($isAdvanced) {
        Write-Log "Input configuration file provided: $InputConfigPath" -Severity "INFO"
        Write-Log "For more information, see: https://aka.ms/alz/acc/phase2" -Severity "INFO"
        Write-Host ""

        if (!(Test-Path $InputConfigPath)) {
            Write-Log "Configuration file not found: $InputConfigPath" -Severity "ERROR"
            return
        }

        $config = Read-FlatYaml -Path $InputConfigPath
        Write-Log "Loaded configuration from $InputConfigPath" -Severity "SUCCESS"
        Write-Host ""

        # Resolve PATs from env vars if config has placeholder text
        if ($config.github_personal_access_token -like "*Set via*" -or [string]::IsNullOrEmpty($config.github_personal_access_token)) {
            if ($env:TF_VAR_github_personal_access_token) {
                $config.github_personal_access_token = $env:TF_VAR_github_personal_access_token
            } else {
                Write-Log "GitHub PAT not set. Set `$env:TF_VAR_github_personal_access_token" -Severity "ERROR"
                return
            }
        }
        if ($config.github_runners_personal_access_token -like "*Set via*" -or [string]::IsNullOrEmpty($config.github_runners_personal_access_token)) {
            if ($env:TF_VAR_github_runners_personal_access_token) {
                $config.github_runners_personal_access_token = $env:TF_VAR_github_runners_personal_access_token
            }
        }

        # Auto-resolve tenant_id from Azure CLI if not set
        if ([string]::IsNullOrEmpty($config.tenant_id) -or $config.tenant_id -eq "REPLACE_ME") {
            $config.tenant_id = (az account show --query tenantId -o tsv 2>$null)
            Write-Log "Auto-resolved tenant_id: $($config.tenant_id)" -Severity "INFO"
        }

        # Validate required string inputs that the bootstrap cannot recover from on its own.
        # Default topology to 'spoke' for back-compat when older inputs.yaml files don't carry the field.
        if ([string]::IsNullOrWhiteSpace([string]$config.topology)) {
            $config.topology = 'spoke'
            Write-Log "topology not set in inputs — defaulting to 'spoke' for back-compat." -Severity "WARNING"
        }
        $allowedTopologies = @('spoke', 'standalone')
        if ($allowedTopologies -notcontains $config.topology) {
            Write-Log "topology '$($config.topology)' is invalid. Allowed values: $($allowedTopologies -join ', ')." -Severity "ERROR"
            return
        }

        $requiredStrings = @(
            'github_organization_name',
            'service_name',
            'environment_name',
            'bootstrap_location',
            'aks_landing_zone_subscription_id',
            'bootstrap_subscription_id'
        )
        if ($config.topology -eq 'spoke') {
            $requiredStrings += @(
                'connectivity_subscription_id',
                'hub_vnet_resource_id',
                'hub_vnet_name',
                'hub_vnet_resource_group_name',
                'hub_firewall_private_ip'
            )
        }
        $missingRequired = $requiredStrings | Where-Object { [string]::IsNullOrWhiteSpace([string]$config.$_) }
        if ($missingRequired.Count -gt 0) {
            Write-Log "Configuration is missing required values: $($missingRequired -join ', ')" -Severity "ERROR"
            Write-Log "Edit $InputConfigPath and set the missing value(s), or re-run the wizard to regenerate it." -Severity "ERROR"
            return
        }

        # Standalone topology: any leftover hub_* / connectivity_subscription_id values are misleading.
        # Auto-clear them and warn, so the rendered tfvars cannot accidentally trigger peering or UDR.
        if ($config.topology -eq 'standalone') {
            $hubFields = @('connectivity_subscription_id','hub_vnet_resource_id','hub_vnet_name','hub_vnet_resource_group_name','hub_firewall_private_ip')
            $stale = $hubFields | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$config.$_) }
            if ($stale.Count -gt 0) {
                Write-Log "topology=standalone but the following hub fields were set and will be cleared: $($stale -join ', ')" -Severity "WARNING"
                foreach ($f in $stale) { $config.$f = "" }
            }
        }

        # Auto-resolve grafana_admin_group_object_id from admin groups or current user
        if ([string]::IsNullOrEmpty($config.grafana_admin_group_object_id) -or $config.grafana_admin_group_object_id -eq "REPLACE_ME") {
            if ($config.aks_admin_group_object_ids -and $config.aks_admin_group_object_ids.Count -gt 0 -and $config.aks_admin_group_object_ids[0] -ne "REPLACE_ME") {
                $config.grafana_admin_group_object_id = $config.aks_admin_group_object_ids[0]
            } else {
                $config.grafana_admin_group_object_id = (az ad signed-in-user show --query id -o tsv 2>$null)
            }
            Write-Log "Auto-resolved grafana_admin_group_object_id: $($config.grafana_admin_group_object_id)" -Severity "INFO"
        }

        # Auto-resolve grafana_zone_redundancy based on region (not all regions support it)
        $grafanaZrRegions = @("australiaeast","canadacentral","centralindia","eastasia","eastus","eastus2euap","francecentral","koreacentral","northeurope","norwayeast","southcentralus","uksouth","westus3")
        if ($null -eq $config.grafana_zone_redundancy) {
            $config.grafana_zone_redundancy = $grafanaZrRegions -contains $config.bootstrap_location
            Write-Log "Auto-resolved grafana_zone_redundancy: $($config.grafana_zone_redundancy) (region: $($config.bootstrap_location))" -Severity "INFO"
        }

        # Derive target root from config path (config file is at {target}/config/inputs.yaml)
        $configDir  = Split-Path -Parent $InputConfigPath
        $targetRoot = Split-Path -Parent $configDir

        # Compute names
        $names = Get-DerivedNames -Config $config

        # Configuration summary
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "  Configuration Summary" -ForegroundColor Cyan
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "  Service Name:     $($config.service_name)"
        Write-Host "  Environment:      $($config.environment_name)"
        Write-Host "  Postfix:          $($config.postfix_number)"
        Write-Host "  Location:         $($config.bootstrap_location)"
        Write-Host "  GitHub Org:       $($config.github_organization_name)"
        Write-Host "  Repository:       $($names.RepoName)"
        Write-Host "  Templates Repo:   $($names.TemplateRepoName)"
        Write-Host "  Self-hosted:      $($config.use_self_hosted_runners)"
        Write-Host "  Private Net:      $($config.use_private_networking)"
        Write-Host "  Resource Group:   $($names.ResourceGroupName)"
        Write-Host "  Storage Account:  $($names.StorageAccountName)"
        Write-Host "  Managed Identity: $($names.ManagedIdentityName)"
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host ""

        if (!$Force) {
            $proceed = Read-Host "Proceed with bootstrap? (yes/no)"
            if ($proceed -ne "yes") {
                Write-Log "Cancelled." -Severity "WARNING"
                return
            }
        } else {
            Write-Log "Force mode — skipping confirmation." -Severity "INFO"
        }
        Write-Host ""

        # ── Deploy template files to target folder ──
        Initialize-FolderStructure -TargetPath $targetRoot
        Write-Log "Template files deployed to $targetRoot" -Severity "SUCCESS"

        # ── Generate aks-landing-zone.tfvars from config ──
        $tfvarsPath = Join-Path $configDir "aks-landing-zone.tfvars"
        if (!(Test-Path $tfvarsPath)) {
            $templateTfvars = Join-Path $script:TemplateRoot "config\aks-landing-zone.tfvars"
            if (Test-Path $templateTfvars) {
                Copy-Item $templateTfvars -Destination $tfvarsPath -Force
            }
        }
        Write-TfvarsFile -Config $config -OutputPath $tfvarsPath
        Write-Log "Generated aks-landing-zone.tfvars" -Severity "SUCCESS"
        Write-Host ""

        # ── Execute bootstrap ──
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "  Pre-flight: Resource Provider Registration" -ForegroundColor Cyan
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Register-RequiredProviders -Config $config

        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "  Step 1/6: Terraform Backend" -ForegroundColor Cyan
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        $backend = New-TerraformBackend -Config $config -Names $names

        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "  Step 2/6: Managed Identity + OIDC" -ForegroundColor Cyan
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        $identity = New-ManagedIdentity -Config $config -Names $names -Backend $backend

        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "  Step 3/6: GitHub Bootstrap" -ForegroundColor Cyan
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        $ghResult = New-GitHubBootstrap -Config $config -Names $names -Backend $backend -Identity $identity
        if ($ghResult -eq $false) {
            Write-Log "Step 3 failed — aborting bootstrap. Fix errors above and re-run." -Severity "ERROR"
            return
        }

        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "  Step 4/6: Self-Hosted Runner (ACI)" -ForegroundColor Cyan
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        New-SelfHostedRunner -Config $config -Names $names -Backend $backend

        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "  Step 5/6: Push Terraform Code" -ForegroundColor Cyan
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Push-TerraformCode -Config $config -Names $names -Backend $backend -TargetRoot $targetRoot

        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "  Step 6/6: Push CI/CD Templates" -ForegroundColor Cyan
        Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Push-TemplateWorkflows -Config $config -Names $names -TargetRoot $targetRoot

        Show-Summary -Config $config -Names $names -Backend $backend -Identity $identity
    }

    # =========================================================================
    # MODE B: INTERACTIVE (no -InputConfigPath)
    # =========================================================================
    else {
        Write-Log "No input configuration files provided. Let's set up the accelerator folder structure first..." -Severity "SUCCESS"
        Write-Log "For more information, see: https://aka.ms/alz/acc/phase2" -Severity "INFO"
        Write-Host ""

        # ── Target folder prompt ──
        Write-Log "Enter the target folder path for the accelerator files:" -Severity "INPUT REQUIRED"
        Write-Host "Default: ~/aksapplz"
        $targetInput = Read-Host "Target folder path"
        $targetPath  = if ([string]::IsNullOrEmpty($targetInput)) {
            Join-Path $HOME "aksapplz"
        } else {
            [System.IO.Path]::GetFullPath($targetInput)
        }
        Write-Host ""

        # ── Overwrite detection ──
        if (Test-Path $targetPath) {
            Write-Log "Target folder '$targetPath' already exists." -Severity "WARNING"
            Write-Host ""
            Write-Log "Do you want to overwrite the existing folder structure? This will replace existing configuration files." -Severity "INPUT REQUIRED"
            Write-Host "Default: no"
            $overwrite = Read-Host "Enter '[y]es' to overwrite or '[n]o' to keep existing"
            Write-Host ""
            if ($overwrite -eq "y" -or $overwrite -eq "yes") {
                Write-Log "Overwriting folder structure at: $targetPath" -Severity "INFO"
                $configDir = Initialize-FolderStructure -TargetPath $targetPath
            } else {
                Write-Log "Using existing folder structure at: $targetPath" -Severity "SUCCESS"
                $configDir = Join-Path $targetPath "config"
                if (!(Test-Path $configDir)) {
                    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
                }
            }
        } else {
            $configDir = Initialize-FolderStructure -TargetPath $targetPath
        }

        Write-Log "Config folder: $configDir" -Severity "INFO"
        Write-Host ""

        # ── "Configure interactively?" prompt ──
        Write-Log "Would you like to configure the input values interactively now?" -Severity "INPUT REQUIRED"
        Write-Host "Default: yes"
        $interactive = Read-Host "Enter '[y]es' for interactive mode or '[n]o' to update the file manually later"

        if ($interactive -eq "n" -or $interactive -eq "no") {
            # Write template files with defaults/placeholders and stop
            Write-Log "Skipping interactive configuration. Update the files manually:" -Severity "INFO"

            # Copy the template inputs.yaml from MODULE TEMPLATES
            $templateInputs = Join-Path $script:TemplateRoot "config\inputs.yaml"
            $outputInputs   = Join-Path $configDir "inputs.yaml"
            if ((Test-Path $templateInputs) -and !(Test-Path $outputInputs)) {
                Copy-Item $templateInputs -Destination $outputInputs -Force
                Write-Log "Template inputs.yaml deployed to $outputInputs" -Severity "SUCCESS"
            } elseif (!(Test-Path $outputInputs)) {
                # Generate a minimal template
                $minConfig = @{
                    bootstrap_location = "swedencentral"; aks_landing_zone_subscription_id = ""
                    connectivity_subscription_id = ""; hub_vnet_resource_id = ""; hub_vnet_name = ""; hub_vnet_resource_group_name = ""; hub_firewall_private_ip = ""
                    spoke_vnet_address_space = "10.10.0.0/16"
                    subnet_address_prefix_aks_nodes = "10.10.0.0/20"; subnet_address_prefix_aks_api_server = "10.10.16.0/28"
                    subnet_address_prefix_app_gateway = "10.10.17.0/24"; subnet_address_prefix_private_endpoints = "10.10.18.0/24"
                    subnet_address_prefix_ingress = "10.10.19.0/24"
                    kubernetes_version = "1.33.6"; aks_sku_tier = "Standard"; aks_private_cluster = $true
                    aks_admin_group_object_ids = @(); bootstrap_subscription_id = ""
                    service_name = "aksapplz"; environment_name = "prod"; postfix_number = 1
                    use_self_hosted_runners = $true; use_private_networking = $true
                    github_personal_access_token = "Set via environment variable TF_VAR_github_personal_access_token"
                    github_runners_personal_access_token = "Set via environment variable TF_VAR_github_runners_personal_access_token"
                    github_organization_name = ""; apply_approvers = @()
                    enable_defender = $true; enable_keda = $true; enable_prometheus = $true
                    enable_grafana = $true; enable_app_gateway = $true
                    enable_node_auto_provisioning = $false; scenario = "single_region_baseline"
                }
                Write-InputsYaml -Config $minConfig -OutputPath $outputInputs
            }

            $templateTfvars = Join-Path $script:TemplateRoot "config\aks-landing-zone.tfvars"
            $outputTfvars   = Join-Path $configDir "aks-landing-zone.tfvars"
            if ((Test-Path $templateTfvars) -and !(Test-Path $outputTfvars)) {
                Copy-Item $templateTfvars -Destination $outputTfvars -Force
                Write-Log "Template aks-landing-zone.tfvars deployed to $outputTfvars" -Severity "SUCCESS"
            }

            Write-Host ""
            Write-Log "Edit these files, then re-run:" -Severity "INFO"
            Write-Host "  Deploy-AKSLandingZoneLegacy -InputConfigPath `"$outputInputs`"" -ForegroundColor White
            Write-Host ""

            # Open in VS Code
            Write-Log "Would you like to open the config folder in VS Code?" -Severity "INPUT REQUIRED"
            Write-Host "Default: yes"
            $openVSCode = Read-Host "Enter '[y]es' to open or '[n]o' to continue without opening"
            if ($openVSCode -ne "n" -and $openVSCode -ne "no") {
                code $configDir 2>$null
            }
            return
        }

        # ── Interactive configuration ──
        Write-Log "Querying Azure for subscriptions and regions..." -Severity "INFO"
        $azureContext = Get-AzureContext

        $config = Get-InteractiveInputs -AzureContext $azureContext
        if ($null -eq $config) { return }

        # ── Write config files ──
        $inputsPath = Join-Path $configDir "inputs.yaml"
        $tfvarsPath = Join-Path $configDir "aks-landing-zone.tfvars"

        Write-InputsYaml -Config $config -OutputPath $inputsPath
        Write-TfvarsFile -Config $config -OutputPath $tfvarsPath

        # ── Sensitive value reminder ──
        Write-Host ""
        Write-Log "PAT tokens are stored as environment variables only (not written to config files)." -Severity "INFO"
        Write-Host "  TF_VAR_github_personal_access_token" -ForegroundColor Yellow
        Write-Host "  TF_VAR_github_runners_personal_access_token" -ForegroundColor Yellow
        Write-Log "These environment variables are set for the current PowerShell session only." -Severity "INFO"
        Write-Host ""

        # ── Next steps — STOP here, do not execute bootstrap ──
        Write-Log "Configuration files generated successfully." -Severity "SUCCESS"
        Write-Host ""
        Write-Host "  Files generated:" -ForegroundColor White
        Write-Host "    $inputsPath" -ForegroundColor White
        Write-Host "    $tfvarsPath" -ForegroundColor White
        Write-Host ""
        Write-Host "  Review and customize these files, then run the bootstrap:" -ForegroundColor White
        Write-Host "  Deploy-AKSLandingZoneLegacy -InputConfigPath `"$inputsPath`"" -ForegroundColor Cyan
        Write-Host ""

        # Open in VS Code
        Write-Log "Would you like to open the config folder in VS Code?" -Severity "INPUT REQUIRED"
        Write-Host "Default: yes"
        $openVSCode = Read-Host "Enter '[y]es' to open or '[n]o' to continue without opening"
        if ($openVSCode -ne "n" -and $openVSCode -ne "no") {
            code $configDir 2>$null
        }

        # Ask if user is ready to bootstrap
        Write-Host ""
        Write-Log "Are you ready to run the bootstrap now?" -Severity "INPUT REQUIRED"
        Write-Host "This will create Azure resources, GitHub repos, and push Terraform code."
        Write-Host "You can also run it later with:"
        Write-Host "  Deploy-AKSLandingZoneLegacy -InputConfigPath `"$inputsPath`"" -ForegroundColor Cyan
        $readyToBoot = Read-Host "Enter '[y]es' to bootstrap now or '[n]o' to exit"
        if ($readyToBoot -eq "y" -or $readyToBoot -eq "yes") {
            Write-Log "Starting bootstrap execution..." -Severity "INFO"
            Deploy-AKSLandingZone -InputConfigPath $inputsPath
        } else {
            Write-Log "Exiting. Run the bootstrap later with:" -Severity "INFO"
            Write-Host "  Deploy-AKSLandingZone -InputConfigPath `"$inputsPath`"" -ForegroundColor Cyan
        }
    }
}

# =============================================================================
# Export the public function
# =============================================================================
Export-ModuleMember -Function Deploy-AKSLandingZone
