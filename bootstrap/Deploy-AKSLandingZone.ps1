<#
.SYNOPSIS
    Deploy-AKSLandingZone - Bootstrap script for AKS Application Landing Zone Accelerator.
    Mirrors the Azure Landing Zone Accelerator (Deploy-Accelerator) deployment pattern exactly.

.DESCRIPTION
    This script bootstraps an AKS Application Landing Zone following the same phased approach
    as the ALZ Terraform Accelerator:

    - Phase 0: Planning (document decisions in checklist.xlsx)
    - Phase 1: Pre-requisites (subscriptions, PATs, Entra ID groups)
    - Phase 2: Bootstrap (this script - creates repos, pipelines, TF backend, identity)
    - Phase 3: Run (CI/CD deploys the AKS landing zone via GitHub Actions)

    The script supports a two-phase execution model:
    - WITHOUT -InputConfigPath: Interactive mode that generates config files and STOPS.
      The user can review/edit the generated files in VS Code before executing.
    - WITH    -InputConfigPath: Advanced / execution mode. Reads the config and executes
      the full 5-step bootstrap.

    Authentication to GitHub uses Personal Access Tokens (PATs) supplied via environment variables,
    matching the Deploy-Accelerator pattern:
      $env:TF_VAR_github_personal_access_token
      $env:TF_VAR_github_runners_personal_access_token  (only when use_self_hosted_runners = true)

.PARAMETER InputConfigPath
    Path to the inputs.yaml configuration file. When provided, runs in execution mode.
    When omitted, the script runs in interactive mode, generates config files, and stops.

.PARAMETER Destroy
    Destroy the bootstrapped resources (Terraform state, identity, GitHub repos).

.EXAMPLE
    # Interactive mode — generates config files, opens VS Code, stops.
    .\Deploy-AKSLandingZone.ps1

    # Execution mode — reads config and runs the 5-step bootstrap.
    .\Deploy-AKSLandingZone.ps1 -InputConfigPath .\config\inputs.yaml

    # Destroy bootstrapped resources.
    .\Deploy-AKSLandingZone.ps1 -Destroy
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$InputConfigPath,

    [Parameter()]
    [switch]$Destroy
)

$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"
$script:ScriptVersion  = "1.0.0"
$script:ProjectRoot    = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { $PWD.Path }

# =============================================================================
# Structured Logging  [Gap #1]
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

# =============================================================================
# Banner  [Gap #18 — version shown]
# =============================================================================
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

# =============================================================================
# Software Requirements Table  [Gap #2, #18, #19, #25]
# =============================================================================
function Test-SoftwareRequirements {
    Write-Log "Checking the software requirements for the Accelerator..."
    Write-Host ""

    $results = @()

    # --- PowerShell version ---
    $psVer = $PSVersionTable.PSVersion
    if ($psVer.Major -ge 7) {
        $results += [pscustomobject]@{ Result = "Success"; Details = "PowerShell version $psVer is supported." }
    } else {
        $results += [pscustomobject]@{ Result = "Failure"; Details = "PowerShell 7+ is required. Current: $psVer." }
    }

    # --- Git ---
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $results += [pscustomobject]@{ Result = "Success"; Details = "Git is installed." }
    } else {
        $results += [pscustomobject]@{ Result = "Failure"; Details = "Git is not installed." }
    }

    # --- Terraform ---
    if (Get-Command terraform -ErrorAction SilentlyContinue) {
        $tfVer = try { (terraform version -json 2>$null | ConvertFrom-Json).terraform_version } catch { "unknown" }
        $results += [pscustomobject]@{ Result = "Success"; Details = "Terraform is installed (version $tfVer)." }
    } else {
        $results += [pscustomobject]@{ Result = "Failure"; Details = "Terraform is not installed." }
    }

    # --- GitHub CLI  [Gap #25] ---
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        $results += [pscustomobject]@{ Result = "Success"; Details = "GitHub CLI (gh) is installed." }
    } else {
        $results += [pscustomobject]@{ Result = "Warning"; Details = "GitHub CLI (gh) is not installed. Required for bootstrap execution." }
    }

    # --- Environment variables ---
    $envVars = @()
    if ($env:TF_VAR_github_personal_access_token)         { $envVars += "TF_VAR_github_personal_access_token" }
    if ($env:TF_VAR_github_runners_personal_access_token)  { $envVars += "TF_VAR_github_runners_personal_access_token" }
    if ($env:ARM_SUBSCRIPTION_ID)                          { $envVars += "ARM_SUBSCRIPTION_ID ($($env:ARM_SUBSCRIPTION_ID))" }
    $allExpected = @("TF_VAR_github_personal_access_token","TF_VAR_github_runners_personal_access_token","ARM_SUBSCRIPTION_ID")
    $missing = $allExpected | Where-Object { -not (Get-Item "env:$_" -ErrorAction SilentlyContinue) }

    if ($envVars.Count -eq 0) {
        $results += [pscustomobject]@{ Result = "Warning"; Details = "No expected environment variables are set. PATs should be set via TF_VAR_github_personal_access_token." }
    } elseif ($missing.Count -gt 0 -and $envVars.Count -gt 0) {
        $results += [pscustomobject]@{ Result = "Warning"; Details = "At least one environment variable is set, but the other expected environment variables are not set. Set environment variables: $($envVars -join ', ')." }
    } else {
        $results += [pscustomobject]@{ Result = "Success"; Details = "All expected environment variables are set: $($envVars -join ', ')." }
    }

    # --- Azure CLI ---
    if (Get-Command az -ErrorAction SilentlyContinue) {
        $results += [pscustomobject]@{ Result = "Success"; Details = "Azure CLI is installed." }
    } else {
        $results += [pscustomobject]@{ Result = "Failure"; Details = "Azure CLI is not installed." }
    }

    # --- Azure CLI login ---
    $account = $null
    try { $account = az account show --output json 2>$null | ConvertFrom-Json } catch {}

    if ($account) {
        $results += [pscustomobject]@{ Result = "Success"; Details = "Azure CLI is logged in. Tenant ID: $($account.tenantId), Subscription: $($account.name) ($($account.id))" }
        # Access token
        try {
            $null = az account get-access-token --output json 2>$null | ConvertFrom-Json
            $results += [pscustomobject]@{ Result = "Success"; Details = "Azure CLI access token is valid." }
        } catch {
            $results += [pscustomobject]@{ Result = "Warning"; Details = "Azure CLI access token may be expired. Run 'az login' to refresh." }
        }
    } else {
        $results += [pscustomobject]@{ Result = "Failure"; Details = "Azure CLI is not logged in. Run 'az login' first." }
    }

    # --- Script version  [Gap #18] ---
    $results += [pscustomobject]@{ Result = "Success"; Details = "AKS LZ Accelerator script version $script:ScriptVersion." }

    # --- powershell-yaml  [Gap #19] ---
    $pyMod = Get-Module -ListAvailable powershell-yaml -ErrorAction SilentlyContinue
    if ($pyMod) {
        $results += [pscustomobject]@{ Result = "Success"; Details = "powershell-yaml module is installed and imported (version $($pyMod.Version))." }
    } else {
        $results += [pscustomobject]@{ Result = "Success"; Details = "Using built-in YAML parser (powershell-yaml not required)." }
    }

    # --- Render table ---
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
        exit 1
    }

    return $account
}

# =============================================================================
# Azure Context Query  [Gap #7]
# =============================================================================
function Get-AzureContext {
    Write-Log "Querying Azure for subscriptions and regions..."

    $currentAccount = az account show --output json 2>$null | ConvertFrom-Json

    # Subscriptions
    $subscriptions = @(az account list --query "[?state=='Enabled'].{id:id, name:name}" -o json 2>$null | ConvertFrom-Json)

    # Physical regions sorted
    $allLocations = @(az account list-locations -o json 2>$null | ConvertFrom-Json)
    $locations = @($allLocations |
        Where-Object { $_.metadata.regionType -eq 'Physical' } |
        Sort-Object displayName)

    # AZ-capable region names  [Gap #9]
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

# =============================================================================
# Numbered Selection Lists  [Gap #8, #9, #10]
# =============================================================================
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

    # Accept default
    if ([string]::IsNullOrEmpty($raw) -and $DefaultIndex -ge 0) {
        $sel = $Items[$DefaultIndex]
        return if ($ValueProperty) { $sel.$ValueProperty } else { "$sel" }
    }

    $num = 0
    if ([int]::TryParse($raw, [ref]$num)) {
        if ($num -eq 0) {
            return (Read-Host "Enter value manually")
        }
        if ($num -ge 1 -and $num -le $max) {
            $sel = $Items[$num - 1]
            return if ($ValueProperty) { $sel.$ValueProperty } else { "$sel" }
        }
    }

    Write-Log "Invalid selection. Falling back to manual input." -Severity "WARNING"
    return (Read-Host "Enter value manually")
}

# =============================================================================
# Sensitive Value Masking  [Gap #12]
# =============================================================================
function Get-MaskedValue {
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return "" }
    if ($Value.Length -le 6) { return "***" }
    return "$($Value.Substring(0,3))***$($Value.Substring($Value.Length - 3))"
}

# =============================================================================
# YAML Parser (flat key-value)
# =============================================================================
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
        elseif ($line -match '^(\w[\w_]*)\s*:\s*(\S+)\s*(#.*)?$') {
            $val = $Matches[2]
            if     ($val -eq "true")    { $config[$Matches[1]] = $true }
            elseif ($val -eq "false")   { $config[$Matches[1]] = $false }
            elseif ($val -match '^\d+$'){ $config[$Matches[1]] = [int]$val }
            else                        { $config[$Matches[1]] = $val }
        }
        elseif ($line -match '^(\w[\w_]*)\s*:\s*\[\]\s*(#.*)?$')        { $config[$Matches[1]] = @() }
        elseif ($line -match '^(\w[\w_]*)\s*:\s*\[(.+)\]\s*(#.*)?$')    {
            $items = $Matches[2] -split ',' | ForEach-Object { $_.Trim().Trim('"') }
            $config[$Matches[1]] = $items
        }
        elseif ($line -match '^(\w[\w_]*)\s*:\s*$') {
            $currentListKey = $Matches[1]; $currentList = @()
        }
    }
    if ($currentListKey) { $config[$currentListKey] = $currentList }
    return $config
}

# =============================================================================
# Folder Structure Setup  [Gap #3, #4, #5]
# =============================================================================
function Initialize-FolderStructure {
    param([string]$TargetPath)

    $configDir    = Join-Path $TargetPath "config"
    $terraformDir = Join-Path $TargetPath "terraform"
    $workflowDir  = Join-Path $TargetPath "workflows"

    # Create directories
    foreach ($dir in @($configDir, $terraformDir, $workflowDir)) {
        if (!(Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    # Copy Terraform template files from project root if they exist and target is different
    $srcTerraform = Join-Path $script:ProjectRoot "terraform"
    $srcWorkflows = Join-Path $script:ProjectRoot "workflows"

    if ((Test-Path $srcTerraform) -and ($srcTerraform -ne $terraformDir)) {
        Copy-Item -Path "$srcTerraform\*" -Destination $terraformDir -Recurse -Force
        Write-Log "Copied Terraform files to $terraformDir" -Severity "INFO"
    }
    if ((Test-Path $srcWorkflows) -and ($srcWorkflows -ne $workflowDir)) {
        Copy-Item -Path "$srcWorkflows\*" -Destination $workflowDir -Recurse -Force
        Write-Log "Copied workflow templates to $workflowDir" -Severity "INFO"
    }

    Write-Log "Folder structure ready at: $TargetPath" -Severity "SUCCESS"
    Write-Log "Config folder: $configDir" -Severity "INFO"
    return $configDir
}

# =============================================================================
# Interactive Inputs  [Gap #7, #8, #9, #10, #11, #12]
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

    # ── Decision 1: Bootstrap Location ──────────────────────────────────────
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

    # ── Decision 2: AKS Landing Zone Subscription ──────────────────────────
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

    # ── Decision 3: Connectivity Subscription ──────────────────────────────
    Write-Log "connectivity_subscription_id" -Severity "INPUT REQUIRED"
    Write-Host "The subscription containing the hub VNet and firewall (deployed by ALZ)."
    Write-Host "See Decision 3 in the planning phase."
    Write-Host "Required: Yes"
    Write-Host "Available subscriptions:"

    Show-NumberedList -Items $subs -LabelProperty "name" -ValueProperty "id" -CurrentValue $currentSub
    $config.connectivity_subscription_id = Read-NumberedSelection -Items $subs -ValueProperty "id" `
        -DefaultIndex $defaultSubIdx -PromptLabel "Enter selection"
    Write-Host ""

    # ── Decision 4: Hub Networking ─────────────────────────────────────────
    Write-Log "hub_vnet_resource_id" -Severity "INPUT REQUIRED"
    Write-Host "Full ARM resource ID of the hub VNet for VNet peering."
    Write-Host "https://github.com/aksapplz/docs/planning#decision-4"
    Write-Host "Format: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Network/virtualNetworks/{name}"
    Write-Host "Required: Yes"
    $config.hub_vnet_resource_id = Read-Host "Enter value"
    Write-Host ""

    Write-Log "hub_firewall_private_ip" -Severity "INPUT REQUIRED"
    Write-Host "Private IP of the hub firewall. Used for UDR to route egress from AKS nodes."
    Write-Host "Default: 10.0.0.4"
    Write-Host "Required: Yes"
    $fwIp = Read-Host "Enter value (press enter to accept default)"
    $config.hub_firewall_private_ip = if ([string]::IsNullOrEmpty($fwIp)) { "10.0.0.4" } else { $fwIp }
    Write-Host ""

    # ── Decision 5: Spoke Networking ───────────────────────────────────────
    Write-Log "spoke_vnet_address_space" -Severity "INPUT REQUIRED"
    Write-Host "Address space for the spoke VNet. Must not overlap with hub or other spokes."
    Write-Host "https://github.com/aksapplz/docs/planning#decision-5"
    Write-Host "Default: 10.10.0.0/16"
    Write-Host "Required: Yes"
    $v = Read-Host "Enter value (press enter to accept default)"
    $config.spoke_vnet_address_space = if ([string]::IsNullOrEmpty($v)) { "10.10.0.0/16" } else { $v }

    Write-Log "subnet_address_prefix_aks_nodes" -Severity "INPUT REQUIRED"
    Write-Host "Subnet for AKS node pools."
    Write-Host "Default: 10.10.0.0/20"
    $v = Read-Host "Enter value (press enter to accept default)"
    $config.subnet_address_prefix_aks_nodes = if ([string]::IsNullOrEmpty($v)) { "10.10.0.0/20" } else { $v }

    Write-Log "subnet_address_prefix_aks_api_server" -Severity "INPUT REQUIRED"
    Write-Host "Subnet for AKS API Server VNet Integration. Minimum /28."
    Write-Host "Default: 10.10.16.0/28"
    $v = Read-Host "Enter value (press enter to accept default)"
    $config.subnet_address_prefix_aks_api_server = if ([string]::IsNullOrEmpty($v)) { "10.10.16.0/28" } else { $v }

    Write-Log "subnet_address_prefix_app_gateway" -Severity "INPUT REQUIRED"
    Write-Host "Subnet for Application Gateway WAF v2."
    Write-Host "Default: 10.10.17.0/24"
    $v = Read-Host "Enter value (press enter to accept default)"
    $config.subnet_address_prefix_app_gateway = if ([string]::IsNullOrEmpty($v)) { "10.10.17.0/24" } else { $v }

    Write-Log "subnet_address_prefix_private_endpoints" -Severity "INPUT REQUIRED"
    Write-Host "Subnet for private endpoints (ACR, Key Vault)."
    Write-Host "Default: 10.10.18.0/24"
    $v = Read-Host "Enter value (press enter to accept default)"
    $config.subnet_address_prefix_private_endpoints = if ([string]::IsNullOrEmpty($v)) { "10.10.18.0/24" } else { $v }

    Write-Log "subnet_address_prefix_ingress" -Severity "INPUT REQUIRED"
    Write-Host "Subnet for ingress controller internal load balancer."
    Write-Host "Default: 10.10.19.0/24"
    $v = Read-Host "Enter value (press enter to accept default)"
    $config.subnet_address_prefix_ingress = if ([string]::IsNullOrEmpty($v)) { "10.10.19.0/24" } else { $v }
    Write-Host ""

    # ── Decision 6: AKS Configuration ─────────────────────────────────────
    Write-Log "kubernetes_version" -Severity "INPUT REQUIRED"
    Write-Host "Kubernetes version for the AKS cluster."
    Write-Host "Check available versions: az aks get-versions -l <region> -o table"
    Write-Host "Default: 1.31"
    Write-Host "Required: Yes"
    $v = Read-Host "Enter value (press enter to accept default)"
    $config.kubernetes_version = if ([string]::IsNullOrEmpty($v)) { "1.31" } else { $v }

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

    # ── Decision 7: Bootstrap Subscription ────────────────────────────────
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

    # ── Decision 8: Bootstrap Resource Naming ─────────────────────────────
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

    # ── Decision 9: Bootstrap Networking and Agents ───────────────────────
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

    # ── Decision 10: Version Control System Settings ─────────────────────
    Write-Log "github_personal_access_token" -Severity "INPUT REQUIRED"
    Write-Host "A GitHub Personal Access Token (PAT) with repo and workflow scopes."
    Write-Host "Can also be supplied via environment variable TF_VAR_github_personal_access_token."
    Write-Host "https://github.com/aksapplz/docs/prerequisites"
    $patDefault = $env:TF_VAR_github_personal_access_token
    if ($patDefault) {
        $masked = Get-MaskedValue -Value $patDefault
        Write-Host "Default: $masked"
    }
    Write-Host "Required: Yes"
    $v = Read-Host "Enter value (press enter to accept default)"
    if ([string]::IsNullOrEmpty($v) -and $patDefault) {
        $config.github_personal_access_token = $patDefault
    } elseif ([string]::IsNullOrEmpty($v)) {
        Write-Log "PAT is required. Set `$env:TF_VAR_github_personal_access_token and try again." -Severity "ERROR"
        exit 1
    } else {
        $config.github_personal_access_token = $v
    }

    Write-Log "github_runners_personal_access_token" -Severity "INPUT REQUIRED"
    Write-Host "A GitHub Personal Access Token (PAT) for registering self-hosted runners."
    Write-Host "Can also be supplied via environment variable TF_VAR_github_runners_personal_access_token."
    Write-Host "https://github.com/aksapplz/docs/prerequisites"
    $runnerPatDefault = $env:TF_VAR_github_runners_personal_access_token
    if ($runnerPatDefault) {
        $masked = Get-MaskedValue -Value $runnerPatDefault
        Write-Host "Default: $masked"
    }
    $v = Read-Host "Enter value (press enter to accept default)"
    if ([string]::IsNullOrEmpty($v) -and $runnerPatDefault) {
        $config.github_runners_personal_access_token = $runnerPatDefault
    } elseif (![string]::IsNullOrEmpty($v)) {
        $config.github_runners_personal_access_token = $v
    } else {
        $config.github_runners_personal_access_token = ""
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

    # ── Decision 11: Features ─────────────────────────────────────────────
    Write-Log "features" -Severity "INPUT REQUIRED"
    Write-Host "Toggle optional components on or off."
    Write-Host "See Decision 11 in the planning phase."

    $featureDefaults = @(
        @{ Key = "enable_defender";     Label = "Enable Defender for Containers?";      Default = "true" }
        @{ Key = "enable_keda";         Label = "Enable KEDA autoscaling?";             Default = "true" }
        @{ Key = "enable_prometheus";   Label = "Enable Managed Prometheus?";           Default = "true" }
        @{ Key = "enable_grafana";      Label = "Enable Managed Grafana?";              Default = "true" }
        @{ Key = "enable_app_gateway";  Label = "Enable Application Gateway WAF?";      Default = "true" }
        @{ Key = "enable_acr";          Label = "Enable Azure Container Registry?";     Default = "true" }
        @{ Key = "enable_key_vault";    Label = "Enable Key Vault?";                    Default = "true" }
    )
    foreach ($feat in $featureDefaults) {
        $v = Read-Host "  $($feat.Label) (true/false) [$($feat.Default)]"
        $config[$feat.Key] = if ($v -eq "false") { $false } else { $true }
    }
    Write-Host ""

    # Basic Inputs (hardcoded — do not modify)
    $config.iac_type              = "terraform"
    $config.bootstrap_module_name = "aksapplz_github"
    $config.starter_module_name   = "aks_landing_zone"

    return $config
}

# =============================================================================
# Config File Generation  [Gap #14]
# =============================================================================
function Write-InputsYaml {
    param(
        [hashtable]$Config,
        [string]$OutputPath
    )

    # Build YAML content
    $boolStr = { param($v) if ($v -eq $true) { "true" } else { "false" } }

    # Determine which PAT fields are from env vars
    $patPlaceholder       = 'Set via environment variable TF_VAR_github_personal_access_token'
    $runnerPatPlaceholder = 'Set via environment variable TF_VAR_github_runners_personal_access_token'
    $patValue       = if ($env:TF_VAR_github_personal_access_token -and
                          $Config.github_personal_access_token -eq $env:TF_VAR_github_personal_access_token) {
                          $patPlaceholder
                      } else { $Config.github_personal_access_token }
    $runnerPatValue = if ($env:TF_VAR_github_runners_personal_access_token -and
                          $Config.github_runners_personal_access_token -eq $env:TF_VAR_github_runners_personal_access_token) {
                          $runnerPatPlaceholder
                      } elseif ([string]::IsNullOrEmpty($Config.github_runners_personal_access_token)) {
                          $runnerPatPlaceholder
                      } else { $Config.github_runners_personal_access_token }

    # Format admin group list
    $adminGroupsList = if ($Config.aks_admin_group_object_ids -and $Config.aks_admin_group_object_ids.Count -gt 0) {
        $quoted = ($Config.aks_admin_group_object_ids | ForEach-Object { "`"$_`"" }) -join ", "
        "[$quoted]"
    } else { "[]" }

    # Format approvers list
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

## Decision 1: Bootstrap Resource Azure Region
bootstrap_location: "$($Config.bootstrap_location)"

## Decision 2: AKS Landing Zone Subscription
# The subscription where the AKS cluster and supporting resources will be deployed
aks_landing_zone_subscription_id: "$($Config.aks_landing_zone_subscription_id)"

## Decision 3: Connectivity Subscription
# The subscription containing the hub VNet and firewall (deployed by ALZ)
connectivity_subscription_id: "$($Config.connectivity_subscription_id)"

## Decision 4: Hub Networking
# Required for VNet peering and UDR to route egress through the hub firewall
hub_vnet_resource_id: "$($Config.hub_vnet_resource_id)"
hub_firewall_private_ip: "$($Config.hub_firewall_private_ip)"

## Decision 5: Spoke Networking
spoke_vnet_address_space: "$($Config.spoke_vnet_address_space)"
subnet_address_prefix_aks_nodes: "$($Config.subnet_address_prefix_aks_nodes)"
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

## Decision 11: Features
# Toggle optional components on or off
enable_defender: $(& $boolStr $Config.enable_defender)
enable_keda: $(& $boolStr $Config.enable_keda)
enable_prometheus: $(& $boolStr $Config.enable_prometheus)
enable_grafana: $(& $boolStr $Config.enable_grafana)
enable_app_gateway: $(& $boolStr $Config.enable_app_gateway)
enable_acr: $(& $boolStr $Config.enable_acr)
enable_key_vault: $(& $boolStr $Config.enable_key_vault)

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

    # Format subnet map
    $subnetBlock = @"
  aks_nodes         = "$($Config.subnet_address_prefix_aks_nodes)"
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

    $content = @"
# =============================================================================
# AKS Application Landing Zone - Configuration
# =============================================================================
# Generated by Deploy-AKSLandingZone.ps1 interactive mode.
# Review and customize these values before running the bootstrap.
# =============================================================================

# -----------------------------------------------------------------------------
# Core Settings
# -----------------------------------------------------------------------------
subscription_id              = "$($Config.aks_landing_zone_subscription_id)"
connectivity_subscription_id = "$($Config.connectivity_subscription_id)"
tenant_id                    = "REPLACE_ME"  # Entra ID tenant ID
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
# -----------------------------------------------------------------------------
vnet_address_space = "$($Config.spoke_vnet_address_space)"

subnet_address_prefixes = {
$subnetBlock
}

# Hub VNet peering (from your ALZ deployment)
hub_vnet_resource_id         = "$($Config.hub_vnet_resource_id)"
hub_vnet_name                = "REPLACE_ME"
hub_vnet_resource_group_name = "REPLACE_ME"
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
network_policy      = "calico"

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
node_os_upgrade_channel   = "NodeImage"

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
# System Node Pool
# -----------------------------------------------------------------------------
system_node_pool = {
  vm_size         = "Standard_D4ds_v5"
  os_disk_size_gb = 128
  os_disk_type    = "Ephemeral"
  max_pods        = 110
  min_count       = 2
  max_count       = 5
  node_count      = 2
  max_surge       = "33%"
}

# -----------------------------------------------------------------------------
# User Node Pool
# -----------------------------------------------------------------------------
user_node_pool = {
  vm_size         = "Standard_D4ds_v5"
  os_disk_size_gb = 128
  os_disk_type    = "Ephemeral"
  max_pods        = 110
  min_count       = 2
  max_count       = 20
  node_count      = 2
  max_surge       = "33%"
  node_labels = {
    "workload" = "user"
  }
}

# -----------------------------------------------------------------------------
# Features
# -----------------------------------------------------------------------------
enable_defender            = $(& $boolTf $Config.enable_defender)
enable_keda                = $(& $boolTf $Config.enable_keda)
enable_managed_prometheus  = $(& $boolTf $Config.enable_prometheus)
enable_managed_grafana     = $(& $boolTf $Config.enable_grafana)
enable_app_gateway         = $(& $boolTf $Config.enable_app_gateway)
enable_diagnostic_settings = true

# -----------------------------------------------------------------------------
# Application Gateway with WAF v2
# -----------------------------------------------------------------------------
waf_mode                 = "Prevention"
app_gateway_min_capacity = 1
app_gateway_max_capacity = 10

# -----------------------------------------------------------------------------
# Azure Container Registry
# -----------------------------------------------------------------------------
acr_zone_redundancy_enabled = true
acr_retention_days          = 30
acr_private_dns_zone_ids    = []
keyvault_private_dns_zone_ids = []

# -----------------------------------------------------------------------------
# Monitoring
# -----------------------------------------------------------------------------
log_retention_days    = 90
grafana_sku           = "Standard"
grafana_zone_redundancy = true
grafana_public_access   = true
grafana_admin_group_object_id = "REPLACE_ME"
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
    $env = $Config.environment_name
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
        ResourceGroupName   = "rg-$svc-$env-$locShort-$num"
        StorageAccountName  = "st${svc}${env}${locShort}${num}"
        ContainerName       = "tfstate"
        ManagedIdentityName = "id-$svc-$env-$locShort-$num"
        RepoName            = "$svc-$env"
        TemplateRepoName    = "$svc-$env-templates"
        TeamName            = "$svc-$env-approvers"
        PlanEnvironment     = "$svc-plan"
        ApplyEnvironment    = "$svc-apply"
        StateKey            = "$svc-$env.terraform.tfstate"
        Prefix              = "$svc-$env-$locShort"
    }
}

# =============================================================================
# Step 1: Create Terraform Backend  [Gap #24 — idempotent]
# =============================================================================
function New-TerraformBackend {
    param([hashtable]$Config, [hashtable]$Names)

    Write-Log "Creating Terraform backend storage..." -Severity "INFO"

    $subscriptionId = if ([string]::IsNullOrEmpty($Config.bootstrap_subscription_id)) {
        (az account show --query id -o tsv)
    } else { $Config.bootstrap_subscription_id }

    # Resource group (az group create is idempotent)
    az group create --name $Names.ResourceGroupName --location $Config.bootstrap_location `
        --subscription $subscriptionId --output none
    Write-Log "Resource group: $($Names.ResourceGroupName)" -Severity "SUCCESS"

    # Storage account — check existence first  [Gap #24]
    $existing = az storage account show --name $Names.StorageAccountName --resource-group $Names.ResourceGroupName `
        --subscription $subscriptionId --query name -o tsv 2>$null
    if (!$existing) {
        az storage account create --name $Names.StorageAccountName `
            --resource-group $Names.ResourceGroupName --location $Config.bootstrap_location `
            --subscription $subscriptionId --sku Standard_GRS --kind StorageV2 `
            --min-tls-version TLS1_2 --allow-blob-public-access false --https-only true --output none
    }
    Write-Log "Storage account: $($Names.StorageAccountName)" -Severity "SUCCESS"

    # Container
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
# Step 2: Create Managed Identity + Federated Credentials (OIDC)  [Gap #24]
# =============================================================================
function New-ManagedIdentity {
    param([hashtable]$Config, [hashtable]$Names, [hashtable]$Backend)

    Write-Log "Creating managed identity with OIDC federation..." -Severity "INFO"

    $org      = $Config.github_organization_name
    $repoName = $Names.RepoName

    # Check if identity exists  [Gap #24]
    $identity = az identity show --name $Names.ManagedIdentityName --resource-group $Backend.ResourceGroupName `
        --subscription $Backend.SubscriptionId --output json 2>$null | ConvertFrom-Json
    if (!$identity) {
        $identity = az identity create --name $Names.ManagedIdentityName `
            --resource-group $Backend.ResourceGroupName --location $Config.bootstrap_location `
            --subscription $Backend.SubscriptionId --output json | ConvertFrom-Json
    }
    Write-Log "Managed identity: $($Names.ManagedIdentityName)" -Severity "SUCCESS"

    $tenantId = (az account show --query tenantId -o tsv)

    $aksSubId = if ([string]::IsNullOrEmpty($Config.aks_landing_zone_subscription_id)) {
        (az account show --query id -o tsv)
    } else { $Config.aks_landing_zone_subscription_id }

    # Role assignments (idempotent — az role assignment create is idempotent)
    az role assignment create --assignee-object-id $identity.principalId `
        --assignee-principal-type ServicePrincipal --role "Contributor" `
        --scope "/subscriptions/$aksSubId" --output none 2>$null
    Write-Log "Contributor on AKS subscription ($aksSubId)" -Severity "SUCCESS"

    if (![string]::IsNullOrEmpty($Config.connectivity_subscription_id)) {
        az role assignment create --assignee-object-id $identity.principalId `
            --assignee-principal-type ServicePrincipal --role "Network Contributor" `
            --scope "/subscriptions/$($Config.connectivity_subscription_id)" --output none 2>$null
        Write-Log "Network Contributor on connectivity subscription ($($Config.connectivity_subscription_id))" -Severity "SUCCESS"
    }

    az role assignment create --assignee-object-id $identity.principalId `
        --assignee-principal-type ServicePrincipal --role "Storage Blob Data Contributor" `
        --scope "/subscriptions/$($Backend.SubscriptionId)/resourceGroups/$($Backend.ResourceGroupName)" --output none 2>$null
    Write-Log "Storage Blob Data Contributor on tfstate" -Severity "SUCCESS"

    # Federated credentials  [Gap #24 — check before create]
    $planSubject  = "repo:${org}/${repoName}:environment:$($Names.PlanEnvironment)"
    $applySubject = "repo:${org}/${repoName}:environment:$($Names.ApplyEnvironment)"

    $existingFc = az identity federated-credential list --identity-name $Names.ManagedIdentityName `
        --resource-group $Backend.ResourceGroupName --subscription $Backend.SubscriptionId `
        --query "[].name" -o json 2>$null | ConvertFrom-Json

    if ($existingFc -notcontains "fc-$($Names.PlanEnvironment)") {
        az identity federated-credential create --name "fc-$($Names.PlanEnvironment)" `
            --identity-name $Names.ManagedIdentityName --resource-group $Backend.ResourceGroupName `
            --subscription $Backend.SubscriptionId --issuer "https://token.actions.githubusercontent.com" `
            --subject $planSubject --audiences "api://AzureADTokenExchange" --output none
    }
    Write-Log "Federated credential (plan): $planSubject" -Severity "SUCCESS"

    if ($existingFc -notcontains "fc-$($Names.ApplyEnvironment)") {
        az identity federated-credential create --name "fc-$($Names.ApplyEnvironment)" `
            --identity-name $Names.ManagedIdentityName --resource-group $Backend.ResourceGroupName `
            --subscription $Backend.SubscriptionId --issuer "https://token.actions.githubusercontent.com" `
            --subject $applySubject --audiences "api://AzureADTokenExchange" --output none
    }
    Write-Log "Federated credential (apply): $applySubject" -Severity "SUCCESS"
    Write-Host ""

    return @{ ClientId = $identity.clientId; PrincipalId = $identity.principalId; TenantId = $tenantId }
}

# =============================================================================
# Step 3: Bootstrap GitHub  [Gap #24 — idempotent]
# =============================================================================
function New-GitHubBootstrap {
    param([hashtable]$Config, [hashtable]$Names, [hashtable]$Backend, [hashtable]$Identity)

    Write-Log "Bootstrapping GitHub..." -Severity "INFO"

    $pat = if ($env:TF_VAR_github_personal_access_token) { $env:TF_VAR_github_personal_access_token }
           else { $Config.github_personal_access_token }
    $org = $Config.github_organization_name
    $env:GH_TOKEN = $pat

    # Repos  [Gap #24 — check before create]
    $existingRepo = gh repo view "$org/$($Names.RepoName)" --json name 2>$null
    if (!$existingRepo) {
        gh repo create "$org/$($Names.RepoName)" --private --description "AKS Application Landing Zone - Infrastructure" --confirm 2>$null
    }
    Write-Log "Repository: $org/$($Names.RepoName)" -Severity "SUCCESS"

    $existingTemplateRepo = gh repo view "$org/$($Names.TemplateRepoName)" --json name 2>$null
    if (!$existingTemplateRepo) {
        gh repo create "$org/$($Names.TemplateRepoName)" --private --description "AKS Application Landing Zone - CI/CD workflow templates" --confirm 2>$null
    }
    Write-Log "Repository: $org/$($Names.TemplateRepoName)" -Severity "SUCCESS"

    # Team  [Gap #24 — check before create]
    $existingTeam = gh api "orgs/$org/teams/$($Names.TeamName)" 2>$null
    if (!$existingTeam) {
        gh api -X POST "orgs/$org/teams" -f name="$($Names.TeamName)" -f privacy="closed" `
            -f description="Approvers for AKS Application Landing Zone deployments" 2>$null
    }
    Write-Log "Team: $($Names.TeamName)" -Severity "SUCCESS"

    # Add approvers
    $approvers = $Config.apply_approvers
    if ($approvers -is [string]) { $approvers = @($approvers) }
    foreach ($approver in $approvers) {
        $a = "$approver".Trim()
        if (![string]::IsNullOrEmpty($a)) {
            gh api -X PUT "orgs/$org/teams/$($Names.TeamName)/memberships/$a" 2>$null
            Write-Log "Added $a to $($Names.TeamName)" -Severity "SUCCESS"
        }
    }

    # Team repo access
    gh api -X PUT "orgs/$org/teams/$($Names.TeamName)/repos/$org/$($Names.RepoName)" -f permission="admin" 2>$null
    gh api -X PUT "orgs/$org/teams/$($Names.TeamName)/repos/$org/$($Names.TemplateRepoName)" -f permission="admin" 2>$null
    Write-Log "Team granted admin on both repositories" -Severity "SUCCESS"

    # Environments
    gh api -X PUT "repos/$org/$($Names.RepoName)/environments/$($Names.PlanEnvironment)" 2>$null
    Write-Log "Environment: $($Names.PlanEnvironment)" -Severity "SUCCESS"

    $teamSlug = $Names.TeamName
    $teamInfo = gh api "orgs/$org/teams/$teamSlug" 2>$null | ConvertFrom-Json
    if ($teamInfo) {
        $envPayload = @{
            reviewers = @( @{ type = "Team"; id = $teamInfo.id } )
        } | ConvertTo-Json -Depth 3 -Compress
        $envPayload | gh api -X PUT "repos/$org/$($Names.RepoName)/environments/$($Names.ApplyEnvironment)" --input - 2>$null
    } else {
        gh api -X PUT "repos/$org/$($Names.RepoName)/environments/$($Names.ApplyEnvironment)" 2>$null
    }
    Write-Log "Environment: $($Names.ApplyEnvironment) (protected - requires team approval)" -Severity "SUCCESS"

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

    # Branch protection
    $bp = @{
        required_status_checks = @{ strict = $true; contexts = @("CI / Plan with Terraform") }
        required_pull_request_reviews = @{ required_approving_review_count = 1 }
        enforce_admins = $true
        restrictions   = $null
    } | ConvertTo-Json -Depth 3 -Compress
    $bp | gh api -X PUT "repos/$org/$($Names.RepoName)/branches/main/protection" --input - 2>$null
    Write-Log "Branch protection on main (require PR + CI pass)" -Severity "SUCCESS"

    if ($Config.use_self_hosted_runners -eq $true) {
        Write-Host ""
        Write-Log "Self-hosted runners enabled — configure runner group in GitHub org settings: $org" -Severity "WARNING"
        if ($Config.use_private_networking -eq $true) {
            Write-Log "Private networking enabled — deploy runners in the spoke VNet or a peered VNet" -Severity "WARNING"
        }
    }
    Write-Host ""
}

# =============================================================================
# Step 4: Push Terraform Code
# =============================================================================
function Push-TerraformCode {
    param([hashtable]$Config, [hashtable]$Names, [hashtable]$Backend, [string]$TargetRoot)

    Write-Log "Pushing Terraform code to $($Config.github_organization_name)/$($Names.RepoName)..." -Severity "INFO"

    $org = $Config.github_organization_name
    $pat = if ($env:TF_VAR_github_personal_access_token) { $env:TF_VAR_github_personal_access_token } else { $env:GH_TOKEN }
    $tempDir = Join-Path $env:TEMP "aksapplz-push-$(Get-Random)"

    git clone "https://x-access-token:${pat}@github.com/$org/$($Names.RepoName).git" $tempDir 2>$null

    # Copy Terraform files
    $terraformSource = Join-Path $TargetRoot "terraform"
    if (Test-Path $terraformSource) {
        Copy-Item -Path "$terraformSource\*" -Destination $tempDir -Recurse -Force
    }

    # Copy tfvars
    $tfvarsSource = Join-Path $TargetRoot "config\aks-landing-zone.tfvars"
    if (Test-Path $tfvarsSource) {
        Copy-Item $tfvarsSource -Destination (Join-Path $tempDir "aks-landing-zone.auto.tfvars") -Force
    }

    # Copy caller workflows
    $workflowDir = Join-Path $tempDir ".github\workflows"
    New-Item -ItemType Directory -Path $workflowDir -Force | Out-Null
    $workflowSource = Join-Path $TargetRoot "workflows"
    if (Test-Path $workflowSource) {
        Copy-Item -Path (Join-Path $workflowSource "ci.yaml") -Destination $workflowDir -Force -ErrorAction SilentlyContinue
        Copy-Item -Path (Join-Path $workflowSource "cd.yaml") -Destination $workflowDir -Force -ErrorAction SilentlyContinue
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

    Push-Location $tempDir
    git add -A
    git commit -m "Initial AKS Application Landing Zone configuration" 2>$null
    git push origin main 2>$null
    Pop-Location

    Write-Log "Terraform code pushed to $org/$($Names.RepoName)" -Severity "SUCCESS"
    Write-Host ""

    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Step 5: Push CI/CD Templates
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
    git commit -m "Initial CI/CD workflow templates" 2>$null
    git push origin main 2>$null
    Pop-Location

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
    $runnerType = if ($Config.use_self_hosted_runners -eq $true) { "Self-hosted" } else { "GitHub-hosted" }
    $netType    = if ($Config.use_private_networking -eq $true)  { "Private" }      else { "Public" }

    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║              Bootstrap Complete!                            ║" -ForegroundColor Green
    Write-Host "  ╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Green
    Write-Host "  ║                                                            ║" -ForegroundColor Green
    Write-Host "  ║  GitHub Repository:    $org/$($Names.RepoName)" -ForegroundColor White
    Write-Host "  ║  Templates Repository: $org/$($Names.TemplateRepoName)" -ForegroundColor White
    Write-Host "  ║  Approver Team:        $($Names.TeamName)" -ForegroundColor White
    Write-Host "  ║  Plan Environment:     $($Names.PlanEnvironment)" -ForegroundColor White
    Write-Host "  ║  Apply Environment:    $($Names.ApplyEnvironment) (protected)" -ForegroundColor White
    Write-Host "  ║                                                            ║" -ForegroundColor Green
    Write-Host "  ║  TF State RG:          $($Backend.ResourceGroupName)" -ForegroundColor White
    Write-Host "  ║  TF State Storage:     $($Backend.StorageAccountName)" -ForegroundColor White
    Write-Host "  ║  Managed Identity:     $($Names.ManagedIdentityName)" -ForegroundColor White
    Write-Host "  ║  Client ID:            $($Identity.ClientId)" -ForegroundColor White
    Write-Host "  ║  Authentication:       OIDC (Federated Credentials)" -ForegroundColor White
    Write-Host "  ║                                                            ║" -ForegroundColor Green
    Write-Host "  ║  Runners:              $runnerType ($netType networking)" -ForegroundColor White
    Write-Host "  ║                                                            ║" -ForegroundColor Green
    Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Next steps (Phase 3 - Run):" -ForegroundColor Yellow
    Write-Host "  1. Review the Terraform code in https://github.com/$org/$($Names.RepoName)"
    Write-Host "  2. Update aks-landing-zone.auto.tfvars with your specific values"
    Write-Host "  3. Create a branch, commit changes, and open a Pull Request"
    Write-Host "  4. CI will automatically run 'terraform plan'"
    Write-Host "  5. Merge the PR to main -> CD will run plan -> wait for approval -> apply"
    Write-Host ""
    if ($Config.use_self_hosted_runners -eq $true) {
        Write-Log "Self-hosted runners: Register your runners in the GitHub org before triggering any workflows." -Severity "WARNING"
        if ($Config.use_private_networking -eq $true) {
            Write-Log "Private networking: Deploy runners inside the spoke VNet or a peered VNet to reach the private AKS API server." -Severity "WARNING"
        }
        Write-Host ""
    }
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
# ████████  MAIN EXECUTION  ████████
# =============================================================================

Show-Banner

# --- Destroy mode ---
if ($Destroy) {
    Invoke-Destroy
    exit 0
}

# --- Prerequisites (always run) ---
$account = Test-SoftwareRequirements

$isAdvanced = ![string]::IsNullOrEmpty($InputConfigPath)

# =============================================================================
# MODE A: EXECUTION (with -InputConfigPath)
# =============================================================================
if ($isAdvanced) {
    Write-Log "Input configuration file provided: $InputConfigPath" -Severity "INFO"
    Write-Log "For more information, see: https://aka.ms/alz/acc/phase2" -Severity "INFO"
    Write-Host ""

    if (!(Test-Path $InputConfigPath)) {
        Write-Log "Configuration file not found: $InputConfigPath" -Severity "ERROR"
        exit 1
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
            exit 1
        }
    }
    if ($config.github_runners_personal_access_token -like "*Set via*" -or [string]::IsNullOrEmpty($config.github_runners_personal_access_token)) {
        if ($env:TF_VAR_github_runners_personal_access_token) {
            $config.github_runners_personal_access_token = $env:TF_VAR_github_runners_personal_access_token
        }
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

    $proceed = Read-Host "Proceed with bootstrap? (yes/no)"
    if ($proceed -ne "yes") {
        Write-Log "Cancelled." -Severity "WARNING"
        exit 0
    }
    Write-Host ""

    # ── Execute 5-step bootstrap ──
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  Step 1/5: Terraform Backend" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    $backend = New-TerraformBackend -Config $config -Names $names

    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  Step 2/5: Managed Identity + OIDC" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    $identity = New-ManagedIdentity -Config $config -Names $names -Backend $backend

    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  Step 3/5: GitHub Bootstrap" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    New-GitHubBootstrap -Config $config -Names $names -Backend $backend -Identity $identity

    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  Step 4/5: Push Terraform Code" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Push-TerraformCode -Config $config -Names $names -Backend $backend -TargetRoot $targetRoot

    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  Step 5/5: Push CI/CD Templates" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Push-TemplateWorkflows -Config $config -Names $names -TargetRoot $targetRoot

    Show-Summary -Config $config -Names $names -Backend $backend -Identity $identity
}

# =============================================================================
# MODE B: INTERACTIVE (no -InputConfigPath)  [Gap #14, #15, #16]
# =============================================================================
else {
    Write-Log "No input configuration files provided. Let's set up the accelerator folder structure first..." -Severity "SUCCESS"
    Write-Log "For more information, see: https://aka.ms/alz/acc/phase2" -Severity "INFO"
    Write-Host ""

    # ── Target folder prompt  [Gap #3, #4] ──
    Write-Log "Enter the target folder path for the accelerator files:" -Severity "INPUT REQUIRED"
    Write-Host "Default: ~/aksapplz"
    $targetInput = Read-Host "Target folder path"
    $targetPath  = if ([string]::IsNullOrEmpty($targetInput)) {
        Join-Path $HOME "aksapplz"
    } else {
        [System.IO.Path]::GetFullPath($targetInput)
    }
    Write-Host ""

    # ── Overwrite detection  [Gap #5] ──
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

    # ── "Configure interactively?" prompt  [Gap #6] ──
    Write-Log "Would you like to configure the input values interactively now?" -Severity "INPUT REQUIRED"
    Write-Host "Default: yes"
    $interactive = Read-Host "Enter '[y]es' for interactive mode or '[n]o' to update the file manually later"

    if ($interactive -eq "n" -or $interactive -eq "no") {
        # Write template files with defaults/placeholders and stop
        Write-Log "Skipping interactive configuration. Update the files manually:" -Severity "INFO"

        # Copy the template inputs.yaml from project if it exists
        $templateInputs = Join-Path $script:ProjectRoot "config\inputs.yaml"
        $outputInputs   = Join-Path $configDir "inputs.yaml"
        if ((Test-Path $templateInputs) -and !(Test-Path $outputInputs)) {
            Copy-Item $templateInputs -Destination $outputInputs -Force
            Write-Log "Template inputs.yaml copied to $outputInputs" -Severity "SUCCESS"
        } elseif (!(Test-Path $outputInputs)) {
            # Generate a minimal template
            $minConfig = @{
                bootstrap_location = "swedencentral"; aks_landing_zone_subscription_id = ""
                connectivity_subscription_id = ""; hub_vnet_resource_id = ""; hub_firewall_private_ip = ""
                spoke_vnet_address_space = "10.10.0.0/16"
                subnet_address_prefix_aks_nodes = "10.10.0.0/20"; subnet_address_prefix_aks_api_server = "10.10.16.0/28"
                subnet_address_prefix_app_gateway = "10.10.17.0/24"; subnet_address_prefix_private_endpoints = "10.10.18.0/24"
                subnet_address_prefix_ingress = "10.10.19.0/24"
                kubernetes_version = "1.31"; aks_sku_tier = "Standard"; aks_private_cluster = $true
                aks_admin_group_object_ids = @(); bootstrap_subscription_id = ""
                service_name = "aksapplz"; environment_name = "prod"; postfix_number = 1
                use_self_hosted_runners = $true; use_private_networking = $true
                github_personal_access_token = "Set via environment variable TF_VAR_github_personal_access_token"
                github_runners_personal_access_token = "Set via environment variable TF_VAR_github_runners_personal_access_token"
                github_organization_name = ""; apply_approvers = @()
                enable_defender = $true; enable_keda = $true; enable_prometheus = $true
                enable_grafana = $true; enable_app_gateway = $true; enable_acr = $true; enable_key_vault = $true
            }
            Write-InputsYaml -Config $minConfig -OutputPath $outputInputs
        }

        $templateTfvars = Join-Path $script:ProjectRoot "config\aks-landing-zone.tfvars"
        $outputTfvars   = Join-Path $configDir "aks-landing-zone.tfvars"
        if ((Test-Path $templateTfvars) -and !(Test-Path $outputTfvars)) {
            Copy-Item $templateTfvars -Destination $outputTfvars -Force
            Write-Log "Template aks-landing-zone.tfvars copied to $outputTfvars" -Severity "SUCCESS"
        }

        Write-Host ""
        Write-Log "Edit these files, then re-run:" -Severity "INFO"
        Write-Host "  .\Deploy-AKSLandingZone.ps1 -InputConfigPath `"$outputInputs`"" -ForegroundColor White
        Write-Host ""

        # ── Open in VS Code  [Gap #15] ──
        Write-Log "Would you like to open the config folder in VS Code?" -Severity "INPUT REQUIRED"
        Write-Host "Default: yes"
        $openVSCode = Read-Host "Enter '[y]es' to open or '[n]o' to continue without opening"
        if ($openVSCode -ne "n" -and $openVSCode -ne "no") {
            code $configDir 2>$null
        }
        exit 0
    }

    # ── Interactive configuration ──
    Write-Log "Querying Azure for subscriptions and regions..." -Severity "INFO"
    $azureContext = Get-AzureContext

    $config = Get-InteractiveInputs -AzureContext $azureContext

    # ── Write config files  [Gap #14] ──
    $inputsPath = Join-Path $configDir "inputs.yaml"
    $tfvarsPath = Join-Path $configDir "aks-landing-zone.tfvars"

    Write-InputsYaml -Config $config -OutputPath $inputsPath
    Write-TfvarsFile -Config $config -OutputPath $tfvarsPath

    # ── Sensitive value warning  [Gap #13] ──
    Write-Host ""
    $sensitiveFields = @()
    if ($config.github_personal_access_token -and
        $env:TF_VAR_github_personal_access_token -eq $config.github_personal_access_token) {
        $sensitiveFields += "  github_personal_access_token -> TF_VAR_github_personal_access_token"
    }
    if ($config.github_runners_personal_access_token -and
        $env:TF_VAR_github_runners_personal_access_token -eq $config.github_runners_personal_access_token) {
        $sensitiveFields += "  github_runners_personal_access_token -> TF_VAR_github_runners_personal_access_token"
    }

    if ($sensitiveFields.Count -gt 0) {
        Write-Log "Sensitive values have been set as environment variables:" -Severity "WARNING"
        foreach ($sf in $sensitiveFields) { Write-Host $sf -ForegroundColor Yellow }
        Write-Log "These environment variables are set for the current process only." -Severity "INFO"
        Write-Log "The config file contains placeholders indicating the values are set via environment variables." -Severity "INFO"
    }
    Write-Host ""

    # ── Next steps  [Gap #16 — STOP here, do not execute bootstrap] ──
    Write-Log "Configuration files generated successfully." -Severity "SUCCESS"
    Write-Host ""
    Write-Host "  Files generated:" -ForegroundColor White
    Write-Host "    $inputsPath" -ForegroundColor White
    Write-Host "    $tfvarsPath" -ForegroundColor White
    Write-Host ""
    Write-Host "  Review and customize these files, then run the bootstrap:" -ForegroundColor White
    Write-Host "  .\Deploy-AKSLandingZone.ps1 -InputConfigPath `"$inputsPath`"" -ForegroundColor Cyan
    Write-Host ""

    # ── Open in VS Code  [Gap #15] ──
    Write-Log "Would you like to open the config folder in VS Code?" -Severity "INPUT REQUIRED"
    Write-Host "Default: yes"
    $openVSCode = Read-Host "Enter '[y]es' to open or '[n]o' to continue without opening"
    if ($openVSCode -ne "n" -and $openVSCode -ne "no") {
        code $configDir 2>$null
    }
}
