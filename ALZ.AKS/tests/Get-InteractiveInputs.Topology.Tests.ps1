# =============================================================================
# Pester tests — Get-InteractiveInputs topology branches
# =============================================================================
# Covers the three branches of Decision 2.5 (topology) in Get-InteractiveInputs:
#   1. standalone     — connectivity_subscription_id + hub_* must be empty
#   2. hub_and_spoke  — connectivity_subscription_id set, hub_vnet_address_space
#                       + hub_firewall_subnet_address_prefix + hub_deploy_firewall
#                       + hub_firewall_sku_tier populated; hub_vnet_* still empty
#                       (filled later from terraform output)
#   3. spoke          — connectivity_subscription_id set, hub_vnet_resource_id
#                       parsed into hub_vnet_name + hub_vnet_resource_group_name,
#                       hub_firewall_private_ip set
#
# Run from repo root:
#   Invoke-Pester -Path .\ALZ.AKS\tests\Get-InteractiveInputs.Topology.Tests.ps1
# =============================================================================

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\ALZ.AKS.psd1'
    Import-Module $modulePath -Force

    # PAT env vars must be set so the PAT prompts don't try to read input.
    $env:TF_VAR_github_personal_access_token         = 'github_pat_FAKE_FOR_TESTS_0000000000000000000000000000000000000000'
    $env:TF_VAR_github_runners_personal_access_token = 'github_pat_FAKE_FOR_TESTS_0000000000000000000000000000000000000001'

    # Shared fake Azure context used by every test
    $script:FakeAzureContext = @{
        Locations = @(
            [pscustomobject]@{ name = 'swedencentral'; displayName = 'Sweden Central' }
            [pscustomobject]@{ name = 'westeurope';    displayName = 'West Europe' }
        )
        Subscriptions = @(
            [pscustomobject]@{ id = '00000000-0000-0000-0000-000000000001'; name = 'sub-landing-zone' }
            [pscustomobject]@{ id = '00000000-0000-0000-0000-000000000002'; name = 'sub-connectivity' }
        )
        CurrentAccount = [pscustomobject]@{
            id   = '00000000-0000-0000-0000-000000000001'
            name = 'sub-landing-zone'
        }
        AZRegionNames = @('swedencentral', 'westeurope')
    }
}

Describe 'Get-InteractiveInputs — topology branches' {

    Context 'topology = standalone' {

        It 'sets connectivity_subscription_id and hub_* fields to empty string' {
            InModuleScope ALZ.AKS -Parameters @{ FakeAzureContext = $script:FakeAzureContext } -ScriptBlock {
                param($FakeAzureContext)
                # Silence prompts & logging
                Mock Write-Log  { } -ModuleName ALZ.AKS
                Mock Write-Host { } -ModuleName ALZ.AKS
                Mock Show-NumberedList { } -ModuleName ALZ.AKS

                # Driver for numbered prompts — returns based on what is being chosen
                Mock Read-NumberedSelection {
                    param($Items, $ValueProperty, $DefaultIndex, $PromptLabel)
                    $values = @($Items | ForEach-Object { if ($ValueProperty) { $_.$ValueProperty } else { "$_" } })

                    # Scenario list
                    if ($values -contains 'single_region_baseline') { return 'single_region_baseline' }
                    # Topology list — the one we're testing
                    if ($values -contains 'standalone')              { return 'standalone' }
                    # AKS SKU tier
                    if ($values -contains 'Free' -and $values -contains 'Premium') { return 'Standard' }
                    # Locations
                    if ($values -contains 'swedencentral')           { return 'swedencentral' }
                    # Subscriptions
                    if ($values -contains '00000000-0000-0000-0000-000000000001') { return '00000000-0000-0000-0000-000000000001' }
                    # AKS versions
                    return $values[0]
                } -ModuleName ALZ.AKS

                # Read-Host driver — defaults for almost everything, org name when prompt is bare "Enter value"
                Mock Read-Host {
                    param($Prompt)
                    if ($Prompt -match 'PAT')                { return '' }       # keep env var
                    if ($Prompt -eq 'Enter value')           { return 'test-org' } # github_organization_name
                    return ''                                                     # accept defaults
                } -ModuleName ALZ.AKS

                # az shouldn't be called in standalone flow, but make it safe just in case
                Mock az { return '[]' } -ModuleName ALZ.AKS

                $cfg = Get-InteractiveInputs -AzureContext $FakeAzureContext

                $cfg.topology                       | Should -Be 'standalone'
                $cfg.connectivity_subscription_id   | Should -Be ''
                $cfg.hub_vnet_resource_id           | Should -Be ''
                $cfg.hub_vnet_name                  | Should -Be ''
                $cfg.hub_vnet_resource_group_name   | Should -Be ''
                $cfg.hub_firewall_private_ip        | Should -Be ''
            }
        }
    }

    Context 'topology = hub_and_spoke' {

        It 'sets hub provisioning inputs and leaves hub_vnet_* empty for post-apply population' {
            InModuleScope ALZ.AKS -Parameters @{ FakeAzureContext = $script:FakeAzureContext } -ScriptBlock {
                param($FakeAzureContext)
                Mock Write-Log  { } -ModuleName ALZ.AKS
                Mock Write-Host { } -ModuleName ALZ.AKS
                Mock Show-NumberedList { } -ModuleName ALZ.AKS

                Mock Read-NumberedSelection {
                    param($Items, $ValueProperty, $DefaultIndex, $PromptLabel)
                    $values = @($Items | ForEach-Object { if ($ValueProperty) { $_.$ValueProperty } else { "$_" } })

                    if ($values -contains 'single_region_baseline') { return 'single_region_baseline' }
                    if ($values -contains 'hub_and_spoke')           { return 'hub_and_spoke' }
                    if ($values -contains 'Free' -and $values -contains 'Premium' -and $values -contains 'Standard') {
                        # Same shape used by AKS SKU AND firewall SKU. Both should be 'Standard'.
                        return 'Standard'
                    }
                    if ($values -contains 'Standard' -and $values -contains 'Premium') {
                        # Firewall SKU (just 2 entries)
                        return 'Standard'
                    }
                    if ($values -contains 'swedencentral')           { return 'swedencentral' }
                    if ($values -contains '00000000-0000-0000-0000-000000000002') { return '00000000-0000-0000-0000-000000000002' }
                    if ($values -contains '00000000-0000-0000-0000-000000000001') { return '00000000-0000-0000-0000-000000000001' }
                    return $values[0]
                } -ModuleName ALZ.AKS

                Mock Read-Host {
                    param($Prompt)
                    if ($Prompt -match 'PAT')      { return '' }
                    if ($Prompt -eq 'Enter value') { return 'test-org' }
                    # All hub_and_spoke text prompts (CIDRs, firewall y/n) → accept defaults
                    return ''
                } -ModuleName ALZ.AKS

                Mock az { return '[]' } -ModuleName ALZ.AKS

                $cfg = Get-InteractiveInputs -AzureContext $FakeAzureContext

                $cfg.topology                          | Should -Be 'hub_and_spoke'
                $cfg.connectivity_subscription_id      | Should -Not -BeNullOrEmpty
                $cfg.hub_vnet_address_space            | Should -Contain '10.0.0.0/16'
                $cfg.hub_firewall_subnet_address_prefix| Should -Be '10.0.0.0/26'
                $cfg.hub_deploy_firewall               | Should -BeTrue
                $cfg.hub_firewall_sku_tier             | Should -Be 'Standard'

                # These get filled later from `terraform output` after the hub apply
                $cfg.hub_vnet_resource_id              | Should -Be ''
                $cfg.hub_vnet_name                     | Should -Be ''
                $cfg.hub_vnet_resource_group_name      | Should -Be ''
                $cfg.hub_firewall_private_ip           | Should -Be ''
            }
        }
    }

    Context 'topology = spoke (peer existing hub)' {

        It 'parses hub_vnet_name + hub_vnet_resource_group_name from selected VNet resource ID' {
            $hubVnetIdLocal = '/subscriptions/00000000-0000-0000-0000-000000000002/resourceGroups/rg-hub-swc/providers/Microsoft.Network/virtualNetworks/vnet-hub-swc'
            InModuleScope ALZ.AKS -Parameters @{ FakeAzureContext = $script:FakeAzureContext; HubVnetId = $hubVnetIdLocal } -ScriptBlock {
                param($FakeAzureContext, $HubVnetId)
                # Stash into module scope so mocks (which run in module scope) can see it
                $script:HubVnetId = $HubVnetId
                Mock Write-Log  { } -ModuleName ALZ.AKS
                Mock Write-Host { } -ModuleName ALZ.AKS
                Mock Show-NumberedList { } -ModuleName ALZ.AKS

                Mock Read-NumberedSelection {
                    param($Items, $ValueProperty, $DefaultIndex, $PromptLabel)
                    $values = @($Items | ForEach-Object { if ($ValueProperty) { $_.$ValueProperty } else { "$_" } })

                    if ($values -contains 'single_region_baseline') { return 'single_region_baseline' }
                    if ($values -contains 'spoke')                   { return 'spoke' }
                    if ($values -contains 'Free' -and $values -contains 'Premium') { return 'Standard' }
                    if ($values -contains 'swedencentral')           { return 'swedencentral' }
                    if ($values -contains $script:HubVnetId)   { return $script:HubVnetId }
                    if ($values -contains '00000000-0000-0000-0000-000000000002') { return '00000000-0000-0000-0000-000000000002' }
                    if ($values -contains '00000000-0000-0000-0000-000000000001') { return '00000000-0000-0000-0000-000000000001' }
                    return $values[0]
                } -ModuleName ALZ.AKS

                Mock Read-Host {
                    param($Prompt)
                    if ($Prompt -match 'PAT')      { return '' }
                    if ($Prompt -eq 'Enter value') { return 'test-org' }
                    return ''
                } -ModuleName ALZ.AKS

                # az network vnet list → return one VNet so we go through the parsing path
                Mock az {
                    $args0 = $args -join ' '
                    if ($args0 -match 'network vnet list') {
                        return (@(
                            @{
                                id   = $script:HubVnetId
                                name = 'vnet-hub-swc'
                                addressSpace = @{ addressPrefixes = @('10.0.0.0/16') }
                            }
                        ) | ConvertTo-Json -Depth 5)
                    }
                    return '[]'
                } -ModuleName ALZ.AKS

                $cfg = Get-InteractiveInputs -AzureContext $FakeAzureContext

                $cfg.topology                         | Should -Be 'spoke'
                $cfg.connectivity_subscription_id     | Should -Be '00000000-0000-0000-0000-000000000002'
                $cfg.hub_vnet_resource_id             | Should -Be $HubVnetId
                $cfg.hub_vnet_name                    | Should -Be 'vnet-hub-swc'
                $cfg.hub_vnet_resource_group_name     | Should -Be 'rg-hub-swc'
                $cfg.hub_firewall_private_ip          | Should -Be '10.0.0.4'
            }
        }
    }
}
