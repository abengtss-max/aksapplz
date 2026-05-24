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
# Bind version to the manifest so the banner can never drift from ALZ.AKS.psd1.
$script:ScriptVersion = try {
    (Test-ModuleManifest -Path (Join-Path $PSScriptRoot 'ALZ.AKS.psd1') -ErrorAction Stop).Version.ToString()
} catch { '0.0.0' }

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
    param([string]$Action = 'apply')
    # Destroy gets a red, scary banner; everything else stays cyan/info.
    if ($Action -eq 'destroy') {
        # Helper: print a row with red border and white body so the warning
        # text is legible while the box itself still screams "destructive".
        function _row($body) {
            Write-Host "  ║ " -ForegroundColor Red -NoNewline
            Write-Host ($body.PadRight(60)) -ForegroundColor White -NoNewline
            Write-Host " ║" -ForegroundColor Red
        }
        Write-Host ""
        Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Red
        Write-Host "  ║ " -ForegroundColor Red -NoNewline
        Write-Host ("  /!\  AKS Application Landing Zone — TEARDOWN  /!\".PadRight(60)) -ForegroundColor Yellow -NoNewline
        Write-Host " ║" -ForegroundColor Red
        Write-Host "  ║ " -ForegroundColor Red -NoNewline
        Write-Host (("                  v$script:ScriptVersion").PadRight(60)) -ForegroundColor White -NoNewline
        Write-Host " ║" -ForegroundColor Red
        _row ""
        _row " [!] DESTRUCTIVE ACTION — this will permanently delete:"
        _row "     - the bootstrap resource group"
        _row "     - the Terraform state storage account"
        _row "     - the generated GitHub workload repository"
        _row "     - the federated workload identities"
        _row ""
        _row " [i] AKS / spoke VNet / App Gateway must already be torn"
        _row "     down by the workload repo's CD pipeline first."
        Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Red
        Write-Host ""
    } else {
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

    # ── Decision 5: AKS VNet Networking ──
    Write-Log "spoke_vnet_address_space" -Severity "INPUT REQUIRED"
    if ($config.topology -eq 'standalone') {
        Write-Host "Address space for the AKS VNet (standalone — no hub/peering). Pick a range that won't clash with anything you may peer to later."
    } else {
        Write-Host "Address space for the spoke VNet. Must not overlap with hub or other spokes."
    }
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
    Write-Host "Token 1 of 2 — the Landing Zone PAT (used by Terraform to create repos, push files, set secrets/variables/environments)."
    Write-Host "Permissions & setup: see QUICKSTART.md § Token 1  |  Create at https://github.com/settings/personal-access-tokens"
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
    Write-Host "Token 2 of 2 — the Runners PAT (only needed if use_self_hosted_runners = true; lets runners register with GitHub)."
    Write-Host "Permissions & setup: see QUICKSTART.md § Token 2  |  Create at https://github.com/settings/personal-access-tokens"
    Write-Host "Optional: press Enter to skip if using GitHub-hosted runners."
    if ($env:TF_VAR_github_runners_personal_access_token) {
        $masked = Get-MaskedValue -Value $env:TF_VAR_github_runners_personal_access_token
        Write-Host "Environment variable TF_VAR_github_runners_personal_access_token is set ($masked)"
        Write-Host "Press enter to use the environment variable, or enter a new value."
        $v = Read-Host -MaskInput "Enter PAT (masked)"
        if (![string]::IsNullOrEmpty($v)) {
            $env:TF_VAR_github_runners_personal_access_token = $v
        }
    } else {
        $v = Read-Host -MaskInput "Enter PAT (masked, press Enter to skip)"
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
        TemplateRepoName    = "$svc-templates"
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
        # Priority:
        #   1. explicit config.template_repository ("owner/name")
        #   2. convention: <github_organization_name>/<service_name>-templates
        #      (workload repos in the org can consume sibling-org reusable workflows)
        #   3. local git remote (only works when bootstrap repo is in the same org
        #      AND is reachable from the workload — typically not the case)
        $templateRepo = $null
        if ($Config.ContainsKey('template_repository') -and -not [string]::IsNullOrWhiteSpace($Config.template_repository)) {
            $templateRepo = [string]$Config.template_repository
        } elseif (-not [string]::IsNullOrWhiteSpace($Config.github_organization_name) -and -not [string]::IsNullOrWhiteSpace($Config.service_name)) {
            $templateRepo = "$($Config.github_organization_name)/$($Config.service_name)-templates"
        } else {
            try {
                $remoteUrl = (& git -C (Split-Path $TemplateRoot -Parent) remote get-url origin 2>$null)
                if ($remoteUrl -match 'github\.com[:/]+([^/]+/[^/.]+)') { $templateRepo = $Matches[1] }
            } catch { }
        }
        if ([string]::IsNullOrWhiteSpace($templateRepo)) {
            $templateRepo = "$($Config.github_organization_name)/__TEMPLATE_REPO_NAME__"
            Write-Log "template_repository not set and could not be derived; workload workflows will keep '__TEMPLATE_REPO_NAME__' placeholder." -Severity "WARNING"
        }
        $templateOrg  = ($templateRepo -split '/')[0]
        $templateName = ($templateRepo -split '/')[1]
        # Pick a runner label that matches how the bootstrap provisioned compute.
        # ACI runner is only created when use_self_hosted_runners=true.
        $runnerLabel = if ($Config.use_self_hosted_runners -eq $true) { "self-hosted" } else { "ubuntu-latest" }
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
                $content = $content -replace '__RUNNER_LABEL__',      $runnerLabel
                $files[".github/workflows/$wfFile"] = $content
            }
        }
    }

    # tfvars file (rendered from wizard answers) -> terraform/aks-landing-zone.auto.tfvars
    # Must live inside the terraform/ working directory so Terraform auto-loads it
    # (auto.tfvars are only picked up from CWD, and our CD/CI workflows run from terraform/).
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        Write-TfvarsFile -Config $Config -OutputPath $tmp
        $files["terraform/aks-landing-zone.auto.tfvars"] = (Get-Content $tmp -Raw)
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

# -----------------------------------------------------------------------------
# Re-run contract helpers (v1.4.0-rc5)
# -----------------------------------------------------------------------------
# These power -DryRun, -Action refresh, and hand-edit detection.
# The contract: every file in Get-RepositoryFilesMap is "managed" — the
# cmdlet reconciles its content on every apply/refresh and will overwrite
# operator edits. Anything else in the workload repo is operator-owned.

function Compare-NormalizedContent {
    param([string]$A, [string]$B)
    if ($null -eq $A -and $null -eq $B) { return $true }
    if ($null -eq $A -or  $null -eq $B) { return $false }
    $na = ($A -replace "`r`n", "`n").TrimEnd("`n", "`r", " ", "`t")
    $nb = ($B -replace "`r`n", "`n").TrimEnd("`n", "`r", " ", "`t")
    return $na -eq $nb
}

function Get-WorkloadRepoFileContent {
    # Fetch the current content of a file in the generated workload repo via the
    # GitHub API. Returns $null if the file doesn't exist (404) or the request
    # fails. Requires GH_TOKEN / GITHUB_TOKEN to be set (caller's responsibility).
    param(
        [Parameter(Mandatory)][string]$Owner,
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$Path
    )
    $b64 = & gh api "repos/$Owner/$Repo/contents/$Path" --jq '.content' 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    # File exists but is empty (e.g. operator truncated `.gitignore` to 0 bytes).
    # gh prints an empty string for `.content` in that case — return "" so the
    # caller can distinguish "absent" ($null → classified as add) from "present
    # but empty" ("" → classified as hand-edited when state has content).
    if ([string]::IsNullOrWhiteSpace($b64)) { return "" }
    try {
        # The GitHub contents API returns base64 with newlines every 60 chars.
        $clean = ($b64 -join '') -replace "`r", '' -replace "`n", '' -replace ' ', ''
        return [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($clean))
    } catch {
        Write-Log "Could not decode content for ${Path}: $($_.Exception.Message)" -Severity "WARNING"
        return $null
    }
}

function Get-StateContentMap {
    # Returns a hashtable: managed-path => content currently recorded in
    # terraform state for module.github.github_repository_file.this[<path>].
    # Returns empty map when state is empty or terraform show fails (treated as
    # "no prior apply" — every file will look like an add).
    param([Parameter(Mandatory)][string]$BootstrapRoot)
    Push-Location $BootstrapRoot
    try {
        $raw = & terraform show -json 2>$null | Out-String
        if ([string]::IsNullOrWhiteSpace($raw)) { return @{} }
        try { $json = $raw | ConvertFrom-Json } catch { return @{} }
        $map = @{}
        $stack = New-Object System.Collections.Stack
        if ($json.values -and $json.values.root_module) { $stack.Push($json.values.root_module) }
        while ($stack.Count -gt 0) {
            $m = $stack.Pop()
            if ($m.resources) {
                foreach ($r in $m.resources) {
                    if ($r.type -eq 'github_repository_file' -and $r.name -eq 'this' -and $r.values -and $r.values.file) {
                        $map[[string]$r.values.file] = [string]$r.values.content
                    }
                }
            }
            if ($m.child_modules) { foreach ($cm in $m.child_modules) { $stack.Push($cm) } }
        }
        return $map
    } finally { Pop-Location }
}

function Get-RenderDriftReport {
    # Compares three views of every managed file:
    #   - $RenderNew     : what Get-RepositoryFilesMap just rendered (about to push)
    #   - $stateContent  : what terraform state thinks is in the repo
    #   - $repoNow       : what's actually in the workload repo right now (gh api)
    #
    # Classification (per path):
    #   unchanged       : repoNow == renderNew → no-op
    #   add             : repoNow == $null (file not in repo yet) → first push
    #   update-managed  : repoNow == stateContent AND repoNow != renderNew → clean update
    #   hand-edited     : repoNow != stateContent (operator edited the repo directly)
    #                     AND repoNow != renderNew (otherwise the edit converged with the new render anyway)
    param(
        [Parameter(Mandatory)][hashtable]$RenderNew,
        [Parameter(Mandatory)][string]$Owner,
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][hashtable]$StateMap
    )
    $report = @()
    foreach ($path in ($RenderNew.Keys | Sort-Object)) {
        $renderContent = [string]$RenderNew[$path]
        $stateContent  = if ($StateMap.ContainsKey($path)) { [string]$StateMap[$path] } else { $null }
        $repoNow       = Get-WorkloadRepoFileContent -Owner $Owner -Repo $Repo -Path $path

        $status = 'unknown'
        if ($null -eq $repoNow) {
            $status = 'add'
        } elseif (Compare-NormalizedContent -A $repoNow -B $renderContent) {
            $status = 'unchanged'
        } elseif ($null -ne $stateContent -and (Compare-NormalizedContent -A $repoNow -B $stateContent)) {
            $status = 'update-managed'
        } else {
            $status = 'hand-edited'
        }

        $report += [pscustomobject]@{
            Path            = $path
            Status          = $status
            RenderBytes     = $renderContent.Length
            RepoBytes       = if ($null -eq $repoNow) { 0 } else { $repoNow.Length }
            StateBytes      = if ($null -eq $stateContent) { 0 } else { $stateContent.Length }
        }
    }
    return ,$report
}

function Show-DriftReport {
    param(
        [Parameter(Mandatory)][object[]]$Report,
        [Parameter(Mandatory)][string]$Owner,
        [Parameter(Mandatory)][string]$Repo
    )
    $colorMap = @{
        'unchanged'      = 'DarkGray'
        'add'            = 'Cyan'
        'update-managed' = 'Yellow'
        'hand-edited'    = 'Red'
    }
    Write-Host ""
    Write-Host "  Re-run drift report for $Owner/$Repo" -ForegroundColor White
    Write-Host "  -----------------------------------" -ForegroundColor DarkGray
    $maxPath = (($Report | ForEach-Object { $_.Path.Length }) + 4 | Measure-Object -Maximum).Maximum
    if ($maxPath -lt 40) { $maxPath = 40 }
    foreach ($row in $Report) {
        $color = $colorMap[$row.Status]
        if (-not $color) { $color = 'White' }
        $line = ("  [{0,-14}] {1,-${maxPath}}  render={2}B  repo={3}B  state={4}B" -f $row.Status, $row.Path, $row.RenderBytes, $row.RepoBytes, $row.StateBytes)
        Write-Host $line -ForegroundColor $color
    }
    $counts = $Report | Group-Object Status | ForEach-Object { "$($_.Name)=$($_.Count)" }
    Write-Host ""
    Write-Host ("  Totals: " + ($counts -join ', ')) -ForegroundColor White
    Write-Host ""
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
    Pass `-auto-approve` to the chosen terraform action (and skip the post-wizard
    "ready to bootstrap?" / "ready to destroy?" prompts).

.PARAMETER Action
    What terraform action to run against the bootstrap composition. One of:
      - 'apply'   (default) — render templates, init, plan, apply, migrate state.
      - 'plan'   — render templates, init, plan only. Equivalent to legacy -PlanOnly.
      - 'refresh' — render templates + tfvars and run `terraform apply -target=
                    module.github.github_repository_file.this` ONLY against an
                    existing env. Skips Entra app, federated creds, state SA,
                    and RBAC bootstrap. Use when you've changed a template or
                    a value in inputs.<env>.yaml and just want to push the new
                    rendered files to the workload repo. Requires -InputConfigPath
                    or -Environment and a previously-applied env.
      - 'destroy' — load existing inputs file, init against the already-migrated
                    azurerm backend, then terraform destroy. For hub_and_spoke
                    topology, the spoke bootstrap is destroyed first (which
                    deletes the generated workload repo + GHA env identities),
                    then the hub composition. Requires -InputConfigPath or
                    -Environment.
      - 'import' — state recovery. Load existing inputs file, init against the
                   azurerm backend, then push a known-good terraform state file
                   to the remote backend. Source state is either -StateBackup
                   <path> or an 'errored.tfstate' left behind by a failed
                   apply/destroy in the bootstrap composition directory.
                   Requires -InputConfigPath or -Environment.

.PARAMETER PlanOnly
    DEPRECATED. Equivalent to -Action plan. Kept for backward compatibility.

.PARAMETER SkipPreflight
    Skip tool / `az login` / Microsoft.ContainerInstance RP / PAT checks. Advanced.

.PARAMETER StateBackup
    Path to a known-good terraform state file to push to the remote backend.
    Only valid with -Action import. When omitted, the cmdlet looks for an
    'errored.tfstate' left behind in the bootstrap composition directory by
    a failed apply or destroy.

.PARAMETER DryRun
    Render templates, fetch current workload-repo content via gh api, compare to
    terraform state, and print a per-file drift report (add / update-managed /
    hand-edited / unchanged). Exits BEFORE touching terraform or the workload
    repo. Valid with -Action apply or -Action refresh. Use this to preview
    what a re-run would do.

.PARAMETER Force
    With -Action apply or -Action refresh, override the safety check that blocks
    a re-run when any managed file in the workload repo has been hand-edited
    (i.e. its content no longer matches terraform state). Use only when you
    intentionally want to discard the operator edits and push the freshly
    rendered templates.

.EXAMPLE
    # Interactive (recommended)
    Deploy-AKSLandingZone

.EXAMPLE
    # Advanced — bring your own inputs.yaml
    $env:TF_VAR_github_personal_access_token         = 'github_pat_...'
    $env:TF_VAR_github_runners_personal_access_token = 'github_pat_...'
    Deploy-AKSLandingZone -InputConfigPath .\config\inputs.yaml -AutoApprove

.EXAMPLE
    # Tear down a previously bootstrapped environment
    Deploy-AKSLandingZone -Environment dev -Action destroy

.EXAMPLE
    # Same, non-interactive
    Deploy-AKSLandingZone -InputConfigPath .\config\inputs.dev.yaml -Action destroy -AutoApprove

.EXAMPLE
    # Recover from a failed apply or destroy by pushing the leftover errored.tfstate
    Deploy-AKSLandingZone -InputConfigPath .\config\inputs.dev.yaml -Action import -AutoApprove

.EXAMPLE
    # Recover from an external state backup
    Deploy-AKSLandingZone -InputConfigPath .\config\inputs.dev.yaml -Action import -StateBackup .\backup.tfstate -AutoApprove
#>
function Deploy-AKSLandingZone {
    [CmdletBinding()]
    param(
        [Parameter()][string]$InputConfigPath,
        [Parameter()][string]$BootstrapRoot,
        [Parameter()][string]$Environment,
        [Parameter()][switch]$AutoApprove,
        [Parameter()][ValidateSet('apply','plan','refresh','destroy','import')][string]$Action = 'apply',
        [Parameter()][switch]$PlanOnly,
        [Parameter()][switch]$SkipPreflight,
        # State recovery (-Action import): explicit path to a known-good terraform
        # state file to push to the remote backend. When omitted, the cmdlet looks
        # for an 'errored.tfstate' left behind in the bootstrap composition by a
        # failed apply/destroy. Mutually exclusive with -Action apply|plan|destroy|refresh.
        [Parameter()][string]$StateBackup,
        # Re-run contract (v1.4.0-rc5): preview what a re-run would push, without
        # touching terraform or the workload repo. Valid with -Action apply|refresh.
        [Parameter()][switch]$DryRun,
        # Re-run contract (v1.4.0-rc5): override the hand-edit safety check that
        # blocks apply/refresh when an operator has edited a managed file in the
        # workload repo directly. Valid with -Action apply|refresh.
        [Parameter()][switch]$Force
    )

    # Backward compatibility: -PlanOnly is equivalent to -Action plan.
    if ($PlanOnly -and $Action -eq 'apply') { $Action = 'plan' }
    if ($PlanOnly -and $Action -ne 'plan') {
        Write-Log "-PlanOnly is only valid with -Action plan (or the default 'apply')." -Severity "ERROR"; return
    }
    if ($StateBackup -and $Action -ne 'import') {
        Write-Log "-StateBackup is only valid with -Action import." -Severity "ERROR"; return
    }
    if ($DryRun -and $Action -notin @('apply','refresh')) {
        Write-Log "-DryRun is only valid with -Action apply or -Action refresh." -Severity "ERROR"; return
    }
    if ($Force -and $Action -notin @('apply','refresh')) {
        Write-Log "-Force is only valid with -Action apply or -Action refresh (operator hand-edit override)." -Severity "ERROR"; return
    }

    Show-Banner -Action $Action
    $headerLabel = switch ($Action) { 'apply' { 'Bootstrap' } 'plan' { 'Bootstrap (PLAN)' } 'refresh' { 'RE-RENDER (managed files only)' } 'destroy' { 'TEARDOWN' } 'import' { 'STATE RECOVERY' } }
    if ($DryRun) { $headerLabel = "$headerLabel — DRY RUN" }
    Write-Log "=== AKS Application Landing Zone — $headerLabel ===" -Severity "INFO"

    # -Action destroy|import|refresh require an existing inputs file (no wizard fallback).
    if ($Action -in @('destroy','import','refresh') -and [string]::IsNullOrEmpty($InputConfigPath) -and [string]::IsNullOrWhiteSpace($Environment)) {
        Write-Log "-Action $Action requires either -InputConfigPath or -Environment (to locate the existing config)." -Severity "ERROR"
        return
    }

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
            # Offer to open the generated files for review before bootstrap kicks off.
            $codeCmd = Get-Command code -ErrorAction SilentlyContinue
            if ($codeCmd) {
                Write-Log "Open generated config in VS Code to review before deploy?" -Severity "INPUT REQUIRED"
                Write-Host "  Files: $InputConfigPath"
                Write-Host "         $tfvarsPath"
                $openIt = Read-Host "Open in VS Code? (y/N)"
                if ($openIt -eq 'y' -or $openIt -eq 'yes') {
                    & code $InputConfigPath $tfvarsPath | Out-Null
                    Write-Log "Opened in VS Code. Save your edits, then return here to continue." -Severity "INFO"
                }
            } else {
                Write-Host "Tip: review the generated files before continuing:" -ForegroundColor DarkGray
                Write-Host "  $InputConfigPath" -ForegroundColor DarkGray
                Write-Host "  $tfvarsPath" -ForegroundColor DarkGray
            }
            Write-Host ""

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
        # Skip on destroy — providers are irrelevant for teardown.
        if ($Action -ne 'destroy') {
            Write-Log "Ensuring Microsoft.ContainerInstance resource provider is registered..." -Severity "INFO"
            $rpState = (az provider show --namespace Microsoft.ContainerInstance --query registrationState -o tsv 2>$null)
            if ($rpState -ne 'Registered') {
                az provider register --namespace Microsoft.ContainerInstance --wait | Out-Null
                Write-Log "Microsoft.ContainerInstance registered." -Severity "SUCCESS"
            } else {
                Write-Log "Microsoft.ContainerInstance already registered." -Severity "SUCCESS"
            }
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

    # ── Pre-flight: Register required resource providers across all subs ──
    # The ALZ accelerator bootstrap creates ACR / ACI / KeyVault / etc. in the
    # AKS landing zone subscription (and connectivity sub for hub topologies).
    # If those resource providers are not registered up front, terraform apply
    # fails late with `MissingSubscriptionRegistration` (e.g. for
    # Microsoft.ContainerRegistry). Register them now in every relevant sub.
    # Skip on destroy — provider registration is irrelevant for teardown.
    if (!$SkipPreflight -and $Action -ne 'destroy') {
        $subsToRegister = @()
        foreach ($s in @($config.aks_landing_zone_subscription_id, $config.bootstrap_subscription_id, $config.connectivity_subscription_id)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$s) -and $subsToRegister -notcontains $s) {
                $subsToRegister += $s
            }
        }
        if ($subsToRegister.Count -gt 0) {
            $origAksSub = $config.aks_landing_zone_subscription_id
            foreach ($subId in $subsToRegister) {
                Write-Log "Registering required resource providers in subscription $subId..." -Severity "INFO"
                $config.aks_landing_zone_subscription_id = $subId
                Register-RequiredProviders -Config $config
            }
            $config.aks_landing_zone_subscription_id = $origAksSub
        }
    }

    # ── DESTROY PATH ──
    # Self-contained teardown: spoke first (deletes the generated workload repo +
    # GHA federated identities), then hub (if topology=hub_and_spoke). Returns
    # before the apply path so the rest of the function is apply/plan-only.
    if ($Action -eq 'destroy') {
        $workspaceName = if (-not [string]::IsNullOrWhiteSpace($Environment)) { $Environment } else { [string]$config.environment_name }
        if (-not $AutoApprove) {
            Write-Host ""
            Write-Log "ABOUT TO DESTROY the AKS Application Landing Zone bootstrap for environment '$workspaceName'." -Severity "WARNING"
            Write-Log "This will delete the generated GitHub workload repo, GHA federated identities, and the bootstrap storage account." -Severity "WARNING"
            Write-Log "Any Azure resources managed by the workload repo (AKS, spoke VNet, App Gateway, etc.) MUST already have been destroyed by its CD pipeline." -Severity "WARNING"
            $confirm = Read-Host "Type 'destroy' to confirm"
            if ($confirm -ne 'destroy') { Write-Log "Aborted." -Severity "INFO"; return }
        }

        # Spoke / bootstrap destroy
        $stateRg = $null
        Push-Location $BootstrapRoot
        try {
          # Wrap the terraform-related work in a single-iteration loop so we can
          # 'break' out to the cleanup phase (below the Push-Location) without
          # returning from the whole function. Returning would skip the always-on
          # GitHub repo + state RG cleanup, which the user expects to run even
          # when the backend storage account is already gone from a prior run.
          do {
            # Self-heal stale backend.tf: if the on-disk backend.tf references a
            # different env's storage account (or no backend.tf exists), rebuild
            # it from the actual state RG + storage account in Azure for the
            # target env. This mirrors what the apply path does via $shouldClean.
            # We always discover the SA from Azure so we can grant data-plane
            # RBAC unconditionally (the apply path grants this; destroys run
            # on a different machine or after RBAC drift need it again).
            $backendTfPath = Join-Path $BootstrapRoot "backend.tf"
            $needsRewrite  = $true
            if (Test-Path $backendTfPath) {
                $existingBackend = Get-Content $backendTfPath -Raw
                if (-not [string]::IsNullOrWhiteSpace($workspaceName) -and $existingBackend -match "(?i)-$([regex]::Escape($workspaceName))-") {
                    $needsRewrite = $false
                } else {
                    Write-Log "On-disk backend.tf references a different environment; rebuilding for '$workspaceName'." -Severity "WARNING"
                }
            } else {
                Write-Log "No backend.tf on disk; discovering bootstrap storage account for '$workspaceName'..." -Severity "INFO"
            }

            # Always discover the state RG + SA so we can (a) optionally rewrite
            # backend.tf and (b) always grant operator RBAC on the SA.
            $svc     = [string]$config.service_name
            $subId   = [string]$config.bootstrap_subscription_id
            $stateRg = az group list --subscription $subId --query "[?starts_with(name,'rg-$svc-$workspaceName-state-')].name | [0]" -o tsv 2>$null
            if ([string]::IsNullOrWhiteSpace($stateRg)) {
                Write-Log "No state RG matching 'rg-$svc-$workspaceName-state-*' found — backend storage is already gone. Skipping terraform destroy and falling through to direct GitHub/Azure cleanup." -Severity "WARNING"
                $stateRg = $null
                break
            }
            $saName = az storage account list -g $stateRg --subscription $subId --query "[0].name" -o tsv 2>$null
            if ([string]::IsNullOrWhiteSpace($saName)) {
                Write-Log "State RG '$stateRg' exists but contains no storage account. Skipping terraform destroy and falling through to direct cleanup." -Severity "WARNING"
                break
            }

            if ($needsRewrite) {
                $backendTf = @"
terraform {
  backend "azurerm" {
    resource_group_name  = "$stateRg"
    storage_account_name = "$saName"
    container_name       = "tfstate"
    key                  = "bootstrap.tfstate"
    use_azuread_auth     = true
    subscription_id      = "$subId"
    tenant_id            = "$($config.tenant_id)"
  }
}
"@
                Set-Content -Path $backendTfPath -Value $backendTf -Encoding UTF8
                Write-Log "Rewrote backend.tf -> $stateRg / $saName" -Severity "SUCCESS"
            }

            # ALWAYS wipe the .terraform cache + lock AND any local-backend
            # workspace state before init. Terraform's cached
            # .terraform/terraform.tfstate records the previously-used backend,
            # and any leftover terraform.tfstate / terraform.tfstate.d/ at the
            # working-dir root is interpreted as a 'local' backend with
            # workspaces — either triggers a phantom 'local -> azurerm'
            # migration on init -reconfigure, which inspects BOTH sides and
            # surfaces the misleading
            # 'Error inspecting states in the "local" backend: listing blobs ... 403'
            # even when current backend.tf is correct.
            $wipeTargets = @(
                ".terraform",
                ".terraform.lock.hcl",
                "terraform.tfstate",
                "terraform.tfstate.backup",
                "terraform.tfstate.d",
                "errored.tfstate"
            )
            foreach ($p in $wipeTargets) {
                $full = Join-Path $BootstrapRoot $p
                if (Test-Path $full) {
                    Remove-Item -Path $full -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Log "Removed stale $p" -Severity "INFO"
                }
            }

            # Always (idempotently) ensure the operator has Storage Blob Data
            # Contributor on the backend SA — terraform init's listBlobs call
            # uses Entra data-plane auth and returns 403 without it.
            $saResourceId = "/subscriptions/$subId/resourceGroups/$stateRg/providers/Microsoft.Storage/storageAccounts/$saName"
            $signedInId   = (az ad signed-in-user show --query id -o tsv 2>$null)
            if (-not [string]::IsNullOrWhiteSpace($signedInId)) {
                # Check first to avoid the 30s propagation wait when role is already present.
                $hasRole = az role assignment list `
                    --assignee $signedInId `
                    --role "Storage Blob Data Contributor" `
                    --scope $saResourceId `
                    --subscription $subId `
                    --query "[0].id" -o tsv 2>$null
                if ([string]::IsNullOrWhiteSpace($hasRole)) {
                    $raOutput = az role assignment create `
                        --assignee-object-id $signedInId `
                        --assignee-principal-type User `
                        --role "Storage Blob Data Contributor" `
                        --scope $saResourceId `
                        --subscription $subId 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "Granted Storage Blob Data Contributor on $saName to operator. Waiting 30s for RBAC propagation..." -Severity "INFO"
                        Start-Sleep -Seconds 30
                    } elseif ($raOutput -match 'already exists|RoleAssignmentExists') {
                        Write-Log "Storage Blob Data Contributor on $saName already present for operator." -Severity "INFO"
                    } else {
                        Write-Log "Could not create role assignment on $saName (terraform init may fail with 403): $raOutput" -Severity "WARNING"
                    }
                } else {
                    Write-Log "Operator already has Storage Blob Data Contributor on $saName." -Severity "INFO"
                }
            } else {
                Write-Log "Could not resolve signed-in user object id; skipping RBAC self-heal (terraform init may fail with 403)." -Severity "WARNING"
            }

            # Always (idempotently) make the backend SA reachable from the
            # operator. The Secure-Baseline-compliant SA defaults to
            # publicNetworkAccess=Disabled and/or defaultAction=Deny, which
            # makes terraform's listBlobs call fail with 403 even when RBAC is
            # correct. IP allowlists are brittle (NAT/CGNAT/VPN can hide the
            # real egress IP), so we set defaultAction=Allow for the duration
            # of the destroy. The SA is deleted seconds later, so there is
            # nothing to revert.
            try {
                az storage account update -n $saName --subscription $subId `
                    --public-network-access Enabled --default-action Allow `
                    --bypass AzureServices Logging Metrics -o none 2>&1 | Out-Null
                Write-Log "Set $saName publicNetworkAccess=Enabled, defaultAction=Allow for the destroy run (will be deleted)." -Severity "WARNING"
                Write-Log "Waiting 60s for storage firewall propagation..." -Severity "INFO"
                Start-Sleep -Seconds 60
            } catch {
                Write-Log "Could not adjust backend SA network rules: $($_.Exception.Message). terraform init may fail with 403." -Severity "WARNING"
            }

            Write-Log "Initialising bootstrap composition (reconfigure against existing azurerm backend)..." -Severity "INFO"
            $initArgs = @('init','-input=false','-reconfigure')
            & terraform @initArgs 2>&1 | Tee-Object -Variable initTee | Out-Host
            if ($LASTEXITCODE -ne 0) {
                # One-shot retry for the storage-firewall race: if init failed
                # with a 403, wait another 90s and retry. Propagation can be
                # slow on freshly-changed Storage network rules.
                $joinedInit = ($initTee | Out-String)
                if ($joinedInit -match '403' -or $joinedInit -match 'AuthorizationFailure') {
                    Write-Log "init failed with 403 — waiting an extra 90s for firewall propagation, then retrying once..." -Severity "WARNING"
                    Start-Sleep -Seconds 90
                    & terraform @initArgs
                }
                if ($LASTEXITCODE -ne 0) {
                    Write-Log "bootstrap terraform init failed (backend may already be gone) — falling through to direct cleanup." -Severity "WARNING"; break
                }
            }

            # terraform destroy still evaluates all required variables (PATs, repository_files),
            # so we must render terraform.tfvars.json before destroying. This also keeps the
            # var values consistent with what was used at apply time.
            try {
                Write-Log "Rendering terraform.tfvars.json for destroy (required variables must be resolvable)..." -Severity "INFO"
                $repoFilesForDestroy = Get-RepositoryFilesMap -Config $config
                $null = New-TerraformTfvarsJson -Config $config -BootstrapRoot $BootstrapRoot -RepositoryFiles $repoFilesForDestroy
            } catch {
                Write-Log "Could not render tfvars before destroy: $($_.Exception.Message) — falling through to direct cleanup." -Severity "WARNING"; break
            }

            # Resolve which workspace actually has state. Apply may have run
            # without -Environment (state landed in 'default') or against a
            # differently-named workspace. We list all workspaces, prefer the
            # requested one, then 'default', then any other workspace that has
            # resources. We skip terraform destroy only when no workspace has
            # any tracked resources — but the final brute-force cleanup phase
            # below always runs regardless, so orphans get cleaned up either way.
            $tfDestroyRan = $false
            $wsListRaw = (& terraform workspace list 2>$null) -join "`n"
            $wsAvailable = @()
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($wsListRaw)) {
                $wsAvailable = $wsListRaw -split "`n" | ForEach-Object { ($_ -replace '^\*?\s*','').Trim() } | Where-Object { $_ }
            }
            Write-Log "Available terraform workspaces: $($wsAvailable -join ', ')" -Severity "INFO"

            $candidates = @()
            if (-not [string]::IsNullOrWhiteSpace($workspaceName)) { $candidates += $workspaceName }
            $candidates += 'default'
            foreach ($w in $wsAvailable) { if ($candidates -notcontains $w) { $candidates += $w } }

            $picked = $null
            foreach ($w in $candidates) {
                if ($wsAvailable -notcontains $w) { continue }
                & terraform workspace select $w 2>$null | Out-Null
                if ($LASTEXITCODE -ne 0) { continue }
                $stateLines = & terraform state list 2>$null
                if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($stateLines -join "`n"))) {
                    $picked = $w
                    Write-Log "Selected workspace '$w' (contains $($stateLines.Count) tracked resources)." -Severity "INFO"
                    break
                } else {
                    Write-Log "Workspace '$w' is empty — skipping." -Severity "INFO"
                }
            }

            if ($null -eq $picked) {
                Write-Log "No terraform workspace contains tracked resources — skipping terraform destroy and falling through to direct Azure/GitHub cleanup." -Severity "WARNING"
            } else {
                $destroyArgs = @('destroy','-input=false')
                if ($AutoApprove) { $destroyArgs += '-auto-approve' }
                Write-Log "Running terraform destroy against bootstrap composition (workspace='$picked')..." -Severity "INFO"
                & terraform @destroyArgs 2>&1 | Tee-Object -Variable destroyTee | Out-Host
                $destroyExit = $LASTEXITCODE
                if ($destroyExit -ne 0) {
                    # Self-referential teardown: terraform destroyed its own backend storage
                    # account, then fails to persist state / release lock against the now-gone
                    # SA (404 ResourceNotFound). The actual destroy succeeded — detect this
                    # and report success rather than a false-negative ERROR.
                    $joined = ($destroyTee | Out-String)
                    $isBackendGone = $joined -match 'Failed to persist state to backend' `
                                  -or $joined -match 'Failed to save state' `
                                  -or $joined -match 'Error releasing the state lock' `
                                  -or ($joined -match 'ResourceNotFound' -and $joined -match 'Destruction complete')
                    if ($isBackendGone) {
                        Write-Log "Terraform destroyed its own backend storage account; the post-destroy state save returned 404 (expected). Treating destroy as successful." -Severity "WARNING"
                        $tfDestroyRan = $true
                    } else {
                        Write-Log "bootstrap terraform destroy failed — falling through to direct Azure/GitHub cleanup." -Severity "WARNING"
                    }
                } else {
                    $tfDestroyRan = $true
                    Write-Log "Bootstrap composition destroyed." -Severity "SUCCESS"
                }
            }
          } while ($false)
        }
        finally { Pop-Location }

        # ── BELT-AND-SUSPENDERS CLEANUP ──
        # Always runs, regardless of whether terraform destroy ran or succeeded.
        # The user's expectation is "destroy means destroy" — leftover state
        # mismatches, empty workspaces, or failed apply attempts must NOT leave
        # orphan resources behind. We brute-force delete what the bootstrap
        # composition would have created, idempotently.
        Write-Log "Running final cleanup of bootstrap RG + state RG + GitHub repos (idempotent)..." -Severity "INFO"
        try {
            $svc         = [string]$config.service_name
            $subId       = [string]$config.bootstrap_subscription_id
            $orgName     = [string]$config.github_organization_name
            $workloadRepo = "$svc-$workspaceName"
            $templateRepo = "$svc-templates"

            # Resolve a GitHub token the same way the apply path does: prefer
            # TF_VAR_github_personal_access_token (already exported when the
            # operator ran apply), fall back to the value stored in inputs.yaml.
            # Then export GH_TOKEN so 'gh' uses it instead of (or in addition
            # to) the local 'gh auth' login — which on a fresh machine may
            # have no delete_repo scope, or no auth at all.
            $patForGh = if ($env:TF_VAR_github_personal_access_token) { $env:TF_VAR_github_personal_access_token }
                        elseif ($config.github_personal_access_token -and $config.github_personal_access_token -notmatch '^Set via') { [string]$config.github_personal_access_token }
                        else { $null }
            $savedGhToken = $env:GH_TOKEN
            if (-not [string]::IsNullOrWhiteSpace($patForGh)) {
                $env:GH_TOKEN = $patForGh
                Write-Log "Authenticating gh CLI via TF_VAR_github_personal_access_token (same PAT used by apply)." -Severity "INFO"
            } else {
                Write-Log "No TF_VAR_github_personal_access_token in env and no PAT in config — falling back to local 'gh auth' session. Run: gh auth refresh -s delete_repo if delete fails." -Severity "WARNING"
            }

            # Small helper so we capture gh's actual error text on failure.
            function _ghDelete($fullName) {
                $out = gh repo delete $fullName --yes 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Deleted $fullName" -Severity "SUCCESS"
                } else {
                    $msg = ($out | Out-String).Trim()
                    Write-Log "gh repo delete $fullName failed: $msg" -Severity "ERROR"
                }
            }

            # 1. Workload GitHub repo (e.g. aliapplz-prod)
            if (-not [string]::IsNullOrWhiteSpace($orgName)) {
                $repoCheck = gh repo view "$orgName/$workloadRepo" --json name 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Deleting GitHub repo $orgName/$workloadRepo ..." -Severity "WARNING"
                    _ghDelete "$orgName/$workloadRepo"
                } else {
                    Write-Log "GitHub repo $orgName/$workloadRepo not present (already deleted or never created)." -Severity "INFO"
                }

                # 2. Templates GitHub repo (e.g. aliapplz-templates) — created by
                # the wizard outside terraform, so terraform destroy never removes it.
                $tplCheck = gh repo view "$orgName/$templateRepo" --json name 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Deleting GitHub repo $orgName/$templateRepo ..." -Severity "WARNING"
                    _ghDelete "$orgName/$templateRepo"
                } else {
                    Write-Log "GitHub repo $orgName/$templateRepo not present (already deleted or never created)." -Severity "INFO"
                }

                # 2b. Approvers team (e.g. aliapplz-prod-approvers). Naming
                # mirrors Get-ResourceNames -> TeamName = "$svc-$env-approvers".
                $teamSlug = "$svc-$workspaceName-approvers"
                $teamCheck = gh api "orgs/$orgName/teams/$teamSlug" 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Deleting GitHub team $orgName/$teamSlug ..." -Severity "WARNING"
                    $teamDelOut = gh api -X DELETE "orgs/$orgName/teams/$teamSlug" 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "Deleted team $orgName/$teamSlug" -Severity "SUCCESS"
                    } else {
                        Write-Log "gh team delete $orgName/$teamSlug failed: $(($teamDelOut | Out-String).Trim())" -Severity "ERROR"
                    }
                } else {
                    Write-Log "GitHub team $orgName/$teamSlug not present (already deleted or never created)." -Severity "INFO"
                }
            }

            # 3. State RG — reuse the value we already discovered above. The SA
            # naming prefix isn't guaranteed (service_name shortening, suffix
            # randomisation), so re-querying with starts_with is fragile.
            if (-not [string]::IsNullOrWhiteSpace($stateRg)) {
                $exists = az group exists -n $stateRg --subscription $subId 2>$null
                if ($exists -eq 'true') {
                    Write-Log "Deleting state RG $stateRg ..." -Severity "WARNING"
                    $rgDelOut = az group delete -n $stateRg --subscription $subId --yes --no-wait 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "Submitted delete for $stateRg (async)" -Severity "SUCCESS"
                    } else {
                        Write-Log "Could not delete $stateRg : $(($rgDelOut | Out-String).Trim())" -Severity "ERROR"
                    }
                } else {
                    Write-Log "State RG $stateRg already gone." -Severity "INFO"
                }
            }

            # 4. Any leftover workload RGs (identity, net, agents, aks, etc.)
            # that terraform destroy didn't clean up (e.g. backend was already
            # gone). Match anything prefixed rg-<svc>-<env>-*. Use -o json so
            # shell-prompt noise can't leak into the variable.
            #
            # BEFORE deleting RGs we harvest principalIds of any user-assigned
            # managed identities inside them. Subscription-scope role
            # assignments (Contributor on AKS LZ sub, Network Contributor on
            # connectivity sub) live outside the RG and would otherwise linger
            # as ghosts ("Identity not found") after the RG is gone.
            $orphanPrincipalIds = @()
            $idJson = az group list --subscription $subId -o json 2>$null
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($idJson)) {
                try {
                    $leftoverRgs = ($idJson | ConvertFrom-Json) | Where-Object {
                        $_.name -like "rg-$svc-$workspaceName-*"
                    } | Select-Object -ExpandProperty name

                    # Harvest MI principalIds first.
                    foreach ($rg in @($leftoverRgs)) {
                        if ([string]::IsNullOrWhiteSpace($rg)) { continue }
                        if ($rg -eq $stateRg) { continue }
                        $miJson = az identity list -g $rg --subscription $subId -o json 2>$null
                        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($miJson)) {
                            try {
                                $mis = $miJson | ConvertFrom-Json
                                foreach ($mi in @($mis)) {
                                    if ($mi.principalId) {
                                        $orphanPrincipalIds += [string]$mi.principalId
                                        Write-Log "Captured principalId $($mi.principalId) for MI $($mi.name) in $rg" -Severity "INFO"
                                    }
                                }
                            } catch { }
                        }
                    }

                    # Now delete the RGs.
                    foreach ($rg in @($leftoverRgs)) {
                        if ([string]::IsNullOrWhiteSpace($rg)) { continue }
                        if ($rg -eq $stateRg) { continue }
                        Write-Log "Deleting leftover RG $rg ..." -Severity "WARNING"
                        $rgDelOut = az group delete -n $rg --subscription $subId --yes --no-wait 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            Write-Log "Submitted delete for $rg (async)" -Severity "SUCCESS"
                        } else {
                            Write-Log "Could not delete $rg : $(($rgDelOut | Out-String).Trim())" -Severity "ERROR"
                        }
                    }
                } catch {
                    Write-Log "Could not parse az group list output: $($_.Exception.Message)" -Severity "WARNING"
                }
            }

            # 5. Orphan role assignments for the harvested MI principalIds
            # across every subscription the bootstrap could have touched.
            $orphanPrincipalIds = $orphanPrincipalIds | Select-Object -Unique
            if ($orphanPrincipalIds.Count -gt 0) {
                $subsToScrub = @()
                $subsToScrub += [string]$config.bootstrap_subscription_id
                if ($config.aks_landing_zone_subscription_id) { $subsToScrub += [string]$config.aks_landing_zone_subscription_id }
                if ($config.connectivity_subscription_id)     { $subsToScrub += [string]$config.connectivity_subscription_id }
                $subsToScrub = $subsToScrub | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

                foreach ($principalId in $orphanPrincipalIds) {
                    foreach ($s in $subsToScrub) {
                        Write-Log "Removing role assignments for principal $principalId in subscription $s ..." -Severity "WARNING"
                        $raOut = az role assignment delete --assignee $principalId --subscription $s 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            Write-Log "Removed role assignments for $principalId in $s" -Severity "SUCCESS"
                        } else {
                            $msg = ($raOut | Out-String).Trim()
                            # 'No matching role assignments' is fine.
                            if ($msg -match 'No matching role assignments') {
                                Write-Log "No role assignments for $principalId in $s" -Severity "INFO"
                            } else {
                                Write-Log "Could not remove role assignments for $principalId in $s : $msg" -Severity "ERROR"
                            }
                        }
                    }
                }
            }
        } catch {
            Write-Log "Final cleanup phase hit an error: $($_.Exception.Message)" -Severity "WARNING"
        } finally {
            # Restore any prior GH_TOKEN so we don't poison the user's shell.
            if ($null -ne $savedGhToken) { $env:GH_TOKEN = $savedGhToken }
            else { Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue }
        }

        # Hub destroy (only for hub_and_spoke topology)
        if ($config.topology -eq 'hub_and_spoke') {
            $repoRootForHub = Split-Path -Parent $script:ModuleRoot
            $hubRoot        = Join-Path $repoRootForHub "bootstrap/alz/hub"
            if (!(Test-Path $hubRoot)) {
                Write-Log "Hub composition not found at $hubRoot — skipping hub destroy." -Severity "WARNING"
            } else {
                Push-Location $hubRoot
                try {
                    Write-Log "Initialising hub composition..." -Severity "INFO"
                    & terraform @('init','-input=false','-reconfigure')
                    if ($LASTEXITCODE -ne 0) { Write-Log "hub terraform init failed." -Severity "ERROR"; return }

                    if (-not [string]::IsNullOrWhiteSpace($workspaceName)) {
                        & terraform workspace select $workspaceName 2>$null
                        if ($LASTEXITCODE -ne 0) {
                            Write-Log "Hub workspace '$workspaceName' not found — skipping hub destroy." -Severity "WARNING"
                            return
                        }
                    }

                    $hubDestroyArgs = @('destroy','-input=false')
                    if ($AutoApprove) { $hubDestroyArgs += '-auto-approve' }
                    Write-Log "Running terraform destroy against hub composition..." -Severity "INFO"
                    & terraform @hubDestroyArgs
                    if ($LASTEXITCODE -ne 0) { Write-Log "hub terraform destroy failed." -Severity "ERROR"; return }
                    Write-Log "Hub composition destroyed." -Severity "SUCCESS"
                }
                finally { Pop-Location }
            }
        }

        Write-Host ""
        Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "  ║   Teardown Complete                                          ║" -ForegroundColor Green
        Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
        return
    }

    # ── IMPORT / STATE RECOVERY PATH ──
    # Push a known-good terraform state file to the remote backend. Source is
    # either -StateBackup <path> or an 'errored.tfstate' left behind in the
    # bootstrap composition by a failed apply/destroy. Backend self-heal +
    # SBDC role grant mirror the destroy path so this works on a fresh machine.
    if ($Action -eq 'import') {
        $workspaceName = if (-not [string]::IsNullOrWhiteSpace($Environment)) { $Environment } else { [string]$config.environment_name }

        # Resolve source state file up front so we fail fast.
        $sourceState = $null
        if (-not [string]::IsNullOrWhiteSpace($StateBackup)) {
            if (-not (Test-Path -LiteralPath $StateBackup)) {
                Write-Log "-StateBackup '$StateBackup' does not exist." -Severity "ERROR"; return
            }
            $sourceState = (Resolve-Path -LiteralPath $StateBackup).Path
        } else {
            $erroredPath = Join-Path $BootstrapRoot "errored.tfstate"
            if (Test-Path -LiteralPath $erroredPath) {
                $sourceState = (Resolve-Path -LiteralPath $erroredPath).Path
                Write-Log "Auto-discovered errored.tfstate at $sourceState" -Severity "INFO"
            } else {
                Write-Log "No -StateBackup provided and no errored.tfstate found at $erroredPath. Nothing to recover." -Severity "ERROR"
                Write-Log "Pass -StateBackup <path> with a known-good terraform state file to push." -Severity "INFO"
                return
            }
        }

        # Validate it's a real terraform state file before touching the backend.
        try {
            $stateJson = Get-Content -LiteralPath $sourceState -Raw | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Log "Source file is not valid JSON: $($_.Exception.Message)" -Severity "ERROR"; return
        }
        if ($null -eq $stateJson.version -or $null -eq $stateJson.terraform_version -or $null -eq $stateJson.resources) {
            Write-Log "Source file does not look like a terraform state (missing version/terraform_version/resources)." -Severity "ERROR"; return
        }
        $sourceResourceCount = @($stateJson.resources).Count
        $sourceSerial        = $stateJson.serial
        $sourceTfVersion     = $stateJson.terraform_version
        Write-Log "Source state: $sourceResourceCount resources, serial=$sourceSerial, terraform=$sourceTfVersion" -Severity "INFO"

        if (-not $AutoApprove) {
            Write-Host ""
            Write-Log "ABOUT TO PUSH state to the remote backend for environment '$workspaceName'." -Severity "WARNING"
            Write-Log "This will OVERWRITE the current remote state. Make sure the file is correct." -Severity "WARNING"
            $confirm = Read-Host "Type 'import' to confirm"
            if ($confirm -ne 'import') { Write-Log "Aborted." -Severity "INFO"; return }
        }

        Push-Location $BootstrapRoot
        try {
            # Reuse the destroy-path backend self-heal pattern, but ALWAYS
            # re-discover for import — the whole point of recovery is that
            # something is broken, so we don't trust on-disk backend.tf.
            $backendTfPath = Join-Path $BootstrapRoot "backend.tf"
            Write-Log "Discovering bootstrap storage account for '$workspaceName' (always re-discover on import)..." -Severity "INFO"
            if ($true) {
                $svc     = [string]$config.service_name
                $subId   = [string]$config.bootstrap_subscription_id
                $stateRg = az group list --subscription $subId --query "[?starts_with(name,'rg-$svc-$workspaceName-state-')].name | [0]" -o tsv 2>$null
                if ([string]::IsNullOrWhiteSpace($stateRg)) {
                    Write-Log "No state RG matching 'rg-$svc-$workspaceName-state-*' found in subscription $subId. Cannot recover state — the backend storage account is gone." -Severity "ERROR"
                    return
                }
                $saName = az storage account list -g $stateRg --subscription $subId --query "[0].name" -o tsv 2>$null
                if ([string]::IsNullOrWhiteSpace($saName)) {
                    Write-Log "State RG '$stateRg' exists but contains no storage account. Cannot recover state." -Severity "ERROR"
                    return
                }
                $backendTf = @"
terraform {
  backend "azurerm" {
    resource_group_name  = "$stateRg"
    storage_account_name = "$saName"
    container_name       = "tfstate"
    key                  = "bootstrap.tfstate"
    use_azuread_auth     = true
    subscription_id      = "$subId"
    tenant_id            = "$($config.tenant_id)"
  }
}
"@
                Set-Content -Path $backendTfPath -Value $backendTf -Encoding UTF8
                Write-Log "Rewrote backend.tf -> $stateRg / $saName" -Severity "SUCCESS"
                foreach ($p in @(".terraform",".terraform.lock.hcl")) {
                    $full = Join-Path $BootstrapRoot $p
                    if (Test-Path $full) { Remove-Item -Path $full -Recurse -Force -ErrorAction SilentlyContinue }
                }
                $saResourceId = "/subscriptions/$subId/resourceGroups/$stateRg/providers/Microsoft.Storage/storageAccounts/$saName"
                $signedInId   = (az ad signed-in-user show --query id -o tsv 2>$null)
                if (-not [string]::IsNullOrWhiteSpace($signedInId)) {
                    $raOutput = az role assignment create `
                        --assignee-object-id $signedInId `
                        --assignee-principal-type User `
                        --role "Storage Blob Data Contributor" `
                        --scope $saResourceId `
                        --subscription $subId 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "Granted Storage Blob Data Contributor on $saName to operator. Waiting 30s for RBAC propagation..." -Severity "INFO"
                        Start-Sleep -Seconds 30
                    } elseif ($raOutput -match 'already exists|RoleAssignmentExists') {
                        Write-Log "Storage Blob Data Contributor on $saName already present for operator." -Severity "INFO"
                    } else {
                        Write-Log "Could not create role assignment (will try anyway): $raOutput" -Severity "WARNING"
                    }
                }
            }

            # Render tfvars so terraform init / state push has all required vars resolvable.
            try {
                Write-Log "Rendering terraform.tfvars.json for import (required variables must be resolvable)..." -Severity "INFO"
                $repoFilesForImport = Get-RepositoryFilesMap -Config $config
                $null = New-TerraformTfvarsJson -Config $config -BootstrapRoot $BootstrapRoot -RepositoryFiles $repoFilesForImport
            } catch {
                Write-Log "Could not render tfvars before import: $($_.Exception.Message)" -Severity "ERROR"; return
            }

            Write-Log "Initialising bootstrap composition (reconfigure against existing azurerm backend)..." -Severity "INFO"
            & terraform @('init','-input=false','-reconfigure')
            if ($LASTEXITCODE -ne 0) { Write-Log "bootstrap terraform init failed." -Severity "ERROR"; return }

            # Workspace: select if present, otherwise create. State push targets the
            # current workspace, so we must be on the right one before pushing.
            if (-not [string]::IsNullOrWhiteSpace($workspaceName)) {
                & terraform workspace select $workspaceName 2>$null
                if ($LASTEXITCODE -ne 0) {
                    Write-Log "Workspace '$workspaceName' not found; creating it." -Severity "INFO"
                    & terraform workspace new $workspaceName
                    if ($LASTEXITCODE -ne 0) { Write-Log "Failed to create workspace '$workspaceName'." -Severity "ERROR"; return }
                }
                Write-Log "On workspace '$workspaceName'." -Severity "INFO"
            }

            # Show current remote state before overwriting.
            $preCount = @(& terraform state list 2>$null).Count
            Write-Log "Remote state currently tracks $preCount resource(s). Will overwrite with $sourceResourceCount from source." -Severity "INFO"

            Write-Log "Pushing state to remote backend..." -Severity "INFO"
            & terraform state push $sourceState
            if ($LASTEXITCODE -ne 0) {
                Write-Log "terraform state push failed. If you see 'cannot import state with serial X over newer state with serial Y', pass -StateBackup with a file whose serial is >= the remote serial, or use 'terraform state push -force' manually." -Severity "ERROR"
                return
            }

            # Verify.
            $postState = & terraform state list 2>$null
            $postCount = @($postState).Count
            if ($postCount -lt 1) {
                Write-Log "State push reported success but remote state is empty. Investigate manually." -Severity "ERROR"; return
            }
            Write-Log "State recovery complete. Remote state now tracks $postCount resource(s)." -Severity "SUCCESS"

            # Clean up errored.tfstate so it doesn't get picked up again on a future run.
            if ($sourceState -eq (Join-Path $BootstrapRoot "errored.tfstate")) {
                Remove-Item -LiteralPath $sourceState -Force -ErrorAction SilentlyContinue
                Write-Log "Removed local errored.tfstate (state has been pushed to remote backend)." -Severity "INFO"
            }
        }
        finally { Pop-Location }

        Write-Host ""
        Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "  ║   State Recovery Complete                                    ║" -ForegroundColor Green
        Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
        Write-Log "Next: run 'Deploy-AKSLandingZone -Action plan' to verify state matches Azure, then apply or destroy as needed." -Severity "INFO"
        return
    }

    # ── REFRESH PATH ──
    # Re-render templates + tfvars and push them to the workload repo via
    # `terraform apply -target=module.github.github_repository_file.this`.
    # Skips Entra app, federated creds, state SA, RBAC bootstrap — those are
    # idempotent on -Action apply anyway and add several minutes per re-run.
    # Honours -DryRun (preview only) and -Force (override hand-edit safety).
    if ($Action -eq 'refresh') {
        $workspaceName = if (-not [string]::IsNullOrWhiteSpace($Environment)) { $Environment } else { [string]$config.environment_name }
        if ([string]::IsNullOrWhiteSpace($workspaceName)) {
            Write-Log "-Action refresh requires environment_name in config or -Environment." -Severity "ERROR"; return
        }

        $svc        = [string]$config.service_name
        $orgName    = [string]$config.github_organization_name
        $repoName   = "$svc-$workspaceName"
        Write-Log "Workload repo target: $orgName/$repoName" -Severity "INFO"

        # PAT export for gh api (gh CLI honours GH_TOKEN). The TF_VAR PAT is
        # already required for terraform apply; we just reuse it for gh.
        $hadGhToken = $env:GH_TOKEN
        if ([string]::IsNullOrWhiteSpace($env:GH_TOKEN)) {
            $env:GH_TOKEN = $env:TF_VAR_github_personal_access_token
        }
        try {
            Push-Location $BootstrapRoot
            try {
                # Backend self-heal (mirrors destroy/import paths): refresh must
                # work on a fresh machine where backend.tf may be missing or stale.
                $backendTfPath = Join-Path $BootstrapRoot "backend.tf"
                $subId         = [string]$config.bootstrap_subscription_id
                $stateRg = az group list --subscription $subId --query "[?starts_with(name,'rg-$svc-$workspaceName-state-')].name | [0]" -o tsv 2>$null
                if ([string]::IsNullOrWhiteSpace($stateRg)) {
                    Write-Log "No state RG matching 'rg-$svc-$workspaceName-state-*' found. -Action refresh requires a previously-applied env." -Severity "ERROR"; return
                }
                $saName = az storage account list -g $stateRg --subscription $subId --query "[0].name" -o tsv 2>$null
                if ([string]::IsNullOrWhiteSpace($saName)) {
                    Write-Log "State RG '$stateRg' exists but contains no storage account. Cannot refresh." -Severity "ERROR"; return
                }
                $backendTf = @"
terraform {
  backend "azurerm" {
    resource_group_name  = "$stateRg"
    storage_account_name = "$saName"
    container_name       = "tfstate"
    key                  = "bootstrap.tfstate"
    use_azuread_auth     = true
    subscription_id      = "$subId"
    tenant_id            = "$($config.tenant_id)"
  }
}
"@
                Set-Content -Path $backendTfPath -Value $backendTf -Encoding UTF8
                foreach ($p in @(".terraform",".terraform.lock.hcl")) {
                    $full = Join-Path $BootstrapRoot $p
                    if (Test-Path $full) { Remove-Item -Path $full -Recurse -Force -ErrorAction SilentlyContinue }
                }
                # Idempotent SBDC role grant (same pattern as destroy/import).
                $saResourceId = "/subscriptions/$subId/resourceGroups/$stateRg/providers/Microsoft.Storage/storageAccounts/$saName"
                $signedInId   = (az ad signed-in-user show --query id -o tsv 2>$null)
                if (-not [string]::IsNullOrWhiteSpace($signedInId)) {
                    $raOutput = az role assignment create `
                        --assignee-object-id $signedInId `
                        --assignee-principal-type User `
                        --role "Storage Blob Data Contributor" `
                        --scope $saResourceId `
                        --subscription $subId 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "Granted Storage Blob Data Contributor on $saName. Waiting 30s for RBAC propagation..." -Severity "INFO"
                        Start-Sleep -Seconds 30
                    }
                }

                # Render templates + tfvars (must come before init: tfvars are evaluated).
                Write-Log "Re-rendering managed files from templates..." -Severity "INFO"
                # BUG-B fix: for hub_and_spoke topology, read the existing hub
                # composition outputs and populate $config.hub_* BEFORE rendering.
                # Without this the rendered aks-landing-zone.auto.tfvars contains
                # empty strings for hub_vnet_resource_id / hub_vnet_name /
                # hub_vnet_resource_group_name / hub_firewall_private_ip — the
                # subsequent targeted apply would silently push the broken file
                # to the workload repo and break spoke peering.
                if ($config.topology -eq 'hub_and_spoke') {
                    $repoRootForHub = Split-Path -Parent $script:ModuleRoot
                    $hubRoot        = Join-Path $repoRootForHub "bootstrap/alz/hub"
                    if (!(Test-Path $hubRoot)) {
                        Write-Log "Hub composition not found at $hubRoot — cannot resolve hub_* outputs for refresh." -Severity "ERROR"; return
                    }
                    Push-Location $hubRoot
                    try {
                        Write-Log "Reading hub composition outputs for hub_and_spoke refresh..." -Severity "INFO"
                        & terraform @('init','-input=false','-upgrade') | Out-Null
                        if ($LASTEXITCODE -ne 0) { Write-Log "Hub terraform init failed during refresh." -Severity "ERROR"; return }
                        $hubWs = $workspaceName
                        & terraform workspace select $hubWs 2>$null
                        if ($LASTEXITCODE -ne 0) {
                            Write-Log "Hub workspace '$hubWs' not found — refresh requires the hub composition to have been previously applied." -Severity "ERROR"; return
                        }
                        $hubOutRaw = (& terraform output -json) | Out-String
                        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($hubOutRaw)) {
                            Write-Log "Hub terraform output returned no data — hub state appears empty." -Severity "ERROR"; return
                        }
                        $hubOut = $hubOutRaw | ConvertFrom-Json
                        $config.hub_vnet_resource_id         = [string]$hubOut.hub_vnet_resource_id.value
                        $config.hub_vnet_name                = [string]$hubOut.hub_vnet_name.value
                        $config.hub_vnet_resource_group_name = [string]$hubOut.hub_vnet_resource_group_name.value
                        $config.hub_firewall_private_ip      = [string]$hubOut.hub_firewall_private_ip.value
                        Write-Log "Hub outputs loaded: vnet=$($config.hub_vnet_name), fw_ip=$($config.hub_firewall_private_ip)" -Severity "SUCCESS"
                    }
                    finally { Pop-Location }
                }
                $repoFiles = Get-RepositoryFilesMap -Config $config
                $null      = New-TerraformTfvarsJson -Config $config -BootstrapRoot $BootstrapRoot -RepositoryFiles $repoFiles
                Write-Log "Rendered $($repoFiles.Keys.Count) managed files." -Severity "SUCCESS"

                Write-Log "Initialising bootstrap composition (reconfigure against existing azurerm backend)..." -Severity "INFO"
                & terraform @('init','-input=false','-reconfigure')
                if ($LASTEXITCODE -ne 0) { Write-Log "bootstrap terraform init failed." -Severity "ERROR"; return }

                & terraform workspace select $workspaceName 2>$null
                if ($LASTEXITCODE -ne 0) {
                    Write-Log "Workspace '$workspaceName' not found in bootstrap state. -Action refresh requires an already-applied env." -Severity "ERROR"; return
                }

                # Drift report: render-new vs state vs repo-now.
                Write-Log "Comparing rendered templates against workload repo and terraform state..." -Severity "INFO"
                $stateMap = Get-StateContentMap -BootstrapRoot $BootstrapRoot
                $report   = Get-RenderDriftReport -RenderNew $repoFiles -Owner $orgName -Repo $repoName -StateMap $stateMap
                Show-DriftReport -Report $report -Owner $orgName -Repo $repoName

                $handEdits = @($report | Where-Object { $_.Status -eq 'hand-edited' })
                if ($handEdits.Count -gt 0 -and -not $Force -and -not $DryRun) {
                    Write-Log "$($handEdits.Count) managed file(s) in $orgName/$repoName have been hand-edited and no longer match terraform state." -Severity "ERROR"
                    Write-Log "These files: $($handEdits.Path -join ', ')" -Severity "ERROR"
                    Write-Log "Re-run with -Force to OVERWRITE the operator edits with freshly-rendered templates, OR copy the edits into the template tree under ALZ.AKS/templates/ and re-run without -Force." -Severity "INFO"
                    return
                }

                $needsApply = @($report | Where-Object { $_.Status -in @('add','update-managed','hand-edited') })
                if ($needsApply.Count -eq 0) {
                    Write-Log "Nothing to push: every managed file matches the rendered template." -Severity "SUCCESS"
                    return
                }

                if ($DryRun) {
                    Write-Log "DryRun: would apply $($needsApply.Count) change(s) — exiting before terraform apply." -Severity "INFO"
                    return
                }

                if (-not $AutoApprove) {
                    Write-Host ""
                    Write-Log "About to push $($needsApply.Count) file change(s) to $orgName/$repoName via terraform apply -target=module.github.github_repository_file.this." -Severity "INPUT REQUIRED"
                    $proceed = Read-Host "Enter '[y]es' to continue, '[n]o' to abort"
                    if ($proceed -notin @('y','yes')) { Write-Log "Aborted." -Severity "INFO"; return }
                }

                $applyArgs = @('apply','-input=false','-target=module.github.github_repository_file.this')
                if ($AutoApprove) { $applyArgs += '-auto-approve' }
                Write-Log "Running targeted terraform apply..." -Severity "INFO"
                & terraform @applyArgs
                if ($LASTEXITCODE -ne 0) { Write-Log "Refresh apply failed." -Severity "ERROR"; return }

                Write-Log "Refresh complete: managed files in $orgName/$repoName are now reconciled to the rendered templates." -Severity "SUCCESS"
            }
            finally { Pop-Location }
        }
        finally {
            if ([string]::IsNullOrWhiteSpace($hadGhToken)) { Remove-Item Env:\GH_TOKEN -ErrorAction SilentlyContinue }
        }

        Write-Host ""
        Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "  ║   Refresh Complete                                           ║" -ForegroundColor Green
        Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
        return
    }

    # ── Hub composition (greenfield) ──
    # When topology=hub_and_spoke, run bootstrap/alz/hub/ first to create the hub VNet
    # (+ optional Azure Firewall), then populate $config.hub_* from its outputs so the
    # downstream render + spoke bootstrap pick them up transparently.
    # Skipped when -Action destroy — for destroy, hub teardown runs AFTER the spoke
    # bootstrap is destroyed (so the workload repo + identities are gone first).
    if ($config.topology -eq 'hub_and_spoke' -and $Action -in @('apply','plan')) {
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
    # Skipped for destroy/import: terraform reads from existing state, no template render needed.
    if ($Action -in @('apply','plan')) {
        Write-Log "Building repository_files map from /terraform and /workflows templates..." -Severity "INFO"
        $repoFiles = Get-RepositoryFilesMap -Config $config
        Write-Log "Repository files: $($repoFiles.Keys.Count) entries" -Severity "SUCCESS"

        # ── Render terraform.tfvars.json ──
        $tfvarsJson = New-TerraformTfvarsJson -Config $config -BootstrapRoot $BootstrapRoot -RepositoryFiles $repoFiles
    }

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

        # ── Re-run contract: drift report + hand-edit safety check (v1.4.0-rc5) ──
        # Run BEFORE the plan/apply split so `Action plan` (DryRun) shows the same
        # render-vs-repo-vs-state table that operators rely on for Gate-2/4/7 checks.
        $hadGhTokenApply = $env:GH_TOKEN
        if ([string]::IsNullOrWhiteSpace($env:GH_TOKEN)) { $env:GH_TOKEN = $env:TF_VAR_github_personal_access_token }
        $blockedByHandEdit = $false
        try {
            $orgNameApply  = [string]$config.github_organization_name
            $repoNameApply = "$([string]$config.service_name)-$workspaceName"
            $stateMapApply = Get-StateContentMap -BootstrapRoot $BootstrapRoot
            if ($stateMapApply.Count -gt 0) {
                Write-Log "Comparing rendered templates against workload repo and terraform state..." -Severity "INFO"
                $reportApply  = Get-RenderDriftReport -RenderNew $repoFiles -Owner $orgNameApply -Repo $repoNameApply -StateMap $stateMapApply
                Show-DriftReport -Report $reportApply -Owner $orgNameApply -Repo $repoNameApply

                $handEditsApply = @($reportApply | Where-Object { $_.Status -eq 'hand-edited' })
                if ($handEditsApply.Count -gt 0 -and -not $Force -and -not $DryRun) {
                    Write-Log "$($handEditsApply.Count) managed file(s) in $orgNameApply/$repoNameApply have been hand-edited and no longer match terraform state." -Severity "ERROR"
                    Write-Log "These files: $($handEditsApply.Path -join ', ')" -Severity "ERROR"
                    Write-Log "Re-run with -Force to OVERWRITE the operator edits, OR move the edits into the template tree under ALZ.AKS/templates/ and re-run without -Force." -Severity "INFO"
                    $blockedByHandEdit = $true
                }
            } else {
                Write-Log "No prior state for this env — first apply. Skipping drift report (every managed file is an add)." -Severity "INFO"
            }
        }
        finally {
            if ([string]::IsNullOrWhiteSpace($hadGhTokenApply)) { Remove-Item Env:\GH_TOKEN -ErrorAction SilentlyContinue }
        }
        if ($blockedByHandEdit) { return }

        if ($PlanOnly -or $Action -eq 'plan') {
            Write-Log "Running terraform plan (-PlanOnly mode)..." -Severity "INFO"
            $planArgs = @('plan','-input=false','-out=bootstrap.tfplan')
            & terraform @planArgs
            if ($LASTEXITCODE -ne 0) { Write-Log "terraform plan failed." -Severity "ERROR"; return }
            Write-Log "Plan saved to bootstrap.tfplan. Exiting (PlanOnly)." -Severity "SUCCESS"
            return
        }

        if ($DryRun) {
            Write-Log "DryRun: exiting before terraform apply." -Severity "INFO"
            return
        }

        $applyArgs = @('apply','-input=false')
        if ($AutoApprove) { $applyArgs += '-auto-approve' }
        Write-Log "Running terraform apply..." -Severity "INFO"
        & terraform @applyArgs
        if ($LASTEXITCODE -ne 0) { Write-Log "terraform apply failed." -Severity "ERROR"; return }

        # ── Ensure the reusable-workflows (templates) repo exists & is populated ──
        # The bootstrap composition only creates the workload repo. Its generated
        # ci.yaml / cd.yaml reference reusable workflows in
        # <org>/<service_name>-templates. If that repo is missing (or empty), the
        # CD run fails with "workflow was not found". Create + populate + grant
        # org access here so the workload repo can call into it.
        try {
            $tplOrg  = [string]$config.github_organization_name
            $tplName = "$([string]$config.service_name)-templates"
            $tplSlug = "$tplOrg/$tplName"
            $wfSrc   = Join-Path $script:TemplateRoot "workflows"
            if (-not (Test-Path (Join-Path $wfSrc "cd-template.yaml"))) {
                Write-Log "Templates source not found at $wfSrc — skipping templates repo bootstrap." -Severity "WARNING"
            } else {
                # 1. Create the repo if it doesn't exist.
                $exists = gh repo view $tplSlug --json name 2>$null
                if (-not $exists) {
                    Write-Log "Creating reusable-workflows repo $tplSlug..." -Severity "INFO"
                    gh repo create $tplSlug --private --description "AKS Application Landing Zone - CI/CD reusable workflows" 2>&1 | Out-Null
                } else {
                    Write-Log "Reusable-workflows repo $tplSlug already exists — updating contents." -Severity "INFO"
                }

                # 2. Upsert ci-template.yaml + cd-template.yaml via Contents API
                #    (avoids git+PAT auth dance; gh CLI carries its own token).
                foreach ($f in @('ci-template.yaml','cd-template.yaml')) {
                    $srcFile = Join-Path $wfSrc $f
                    if (-not (Test-Path $srcFile)) { continue }
                    $apiPath = ".github/workflows/$f"
                    $content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-Content $srcFile -Raw)))
                    $existingSha = gh api "/repos/$tplSlug/contents/$apiPath" --jq '.sha' 2>$null
                    $args = @('api','-X','PUT',"/repos/$tplSlug/contents/$apiPath",'-f',"message=Bootstrap update $f",'-f',"content=$content")
                    if ($existingSha) { $args += @('-f',"sha=$existingSha") }
                    gh @args 2>&1 | Out-Null
                }
                Write-Log "Pushed ci-template.yaml + cd-template.yaml to $tplSlug" -Severity "SUCCESS"

                # 3. Grant org access so private workload repos can call these workflows.
                gh api -X PUT "/repos/$tplSlug/actions/permissions/access" -F access_level=organization 2>&1 | Out-Null
                Write-Log "Actions access on $tplSlug set to 'organization'" -Severity "SUCCESS"
            }
        } catch {
            Write-Log "Templates repo bootstrap encountered an error: $($_.Exception.Message). Workload CD may fail until templates repo exists." -Severity "WARNING"
        }

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

        # ── Multi-env loop: offer to deploy another environment without leaving the shell ──
        if (-not $AutoApprove -and -not $PlanOnly) {
            Write-Host ""
            Write-Log "Deploy another environment now? (e.g. dev/test/qa/prod)" -Severity "INPUT REQUIRED"
            $another = Read-Host "Enter an environment name to bootstrap next, or press Enter to finish"
            if (-not [string]::IsNullOrWhiteSpace($another)) {
                if ($another -notmatch '^[a-z0-9]{1,8}$') {
                    Write-Log "Environment '$another' is invalid (must be 1-8 lowercase alphanumeric). Skipping loop." -Severity "WARNING"
                } else {
                    Write-Log "Re-invoking wizard for environment '$another'..." -Severity "INFO"
                    Pop-Location
                    Deploy-AKSLandingZone -Environment $another
                    return
                }
            }
        }
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
