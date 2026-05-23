<#
.SYNOPSIS
    Level 1 — Scenario render tests.

    For each scenario YAML under tests/e2e/scenarios/:
      - Parse with Read-FlatYaml
      - Generate aks-landing-zone.auto.tfvars via Write-TfvarsFile
      - Assert topology- and scenario-specific structure

    Fast (<1s/scenario). No Azure calls, no terraform.

    Run:
      Invoke-Pester -Path .\ALZ.AKS\tests\e2e\Scenarios.L1.Tests.ps1 -Output Detailed
#>

BeforeDiscovery {
    $Script:RepoRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    $Script:ScenarioDir  = Join-Path $PSScriptRoot 'scenarios'
    $Script:Scenarios    = Get-ChildItem -Path $Script:ScenarioDir -Filter '*.yaml' | ForEach-Object {
        $raw       = Get-Content $_.FullName -Raw
        $topology  = if ($raw -match '(?m)^topology:\s*"([^"]+)"') { $Matches[1] } else { 'unknown' }
        $scenario  = if ($raw -match '(?m)^scenario:\s*"([^"]+)"') { $Matches[1] } else { 'unknown' }
        @{
            Name     = $_.BaseName
            Path     = $_.FullName
            Topology = $topology
            Scenario = $scenario
        }
    }
}

BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    Import-Module (Join-Path $repoRoot 'ALZ.AKS\ALZ.AKS.psd1') -Force
}

Describe 'L1: scenario render — <Name>' -ForEach $Script:Scenarios {

    BeforeAll {
        $Script:Config = InModuleScope ALZ.AKS -Parameters @{ p = $Path } -ScriptBlock {
            param($p) Read-FlatYaml -Path $p
        }
        $Script:TfvarsPath = Join-Path ([System.IO.Path]::GetTempPath()) "alz-l1-$Name-$(Get-Random).tfvars"
        InModuleScope ALZ.AKS -Parameters @{ c = $Script:Config; out = $Script:TfvarsPath } -ScriptBlock {
            param($c, $out) Write-TfvarsFile -Config $c -OutputPath $out
        }
        $Script:Tfvars = Get-Content $Script:TfvarsPath -Raw
    }

    AfterAll {
        Remove-Item $Script:TfvarsPath -Force -ErrorAction SilentlyContinue
    }

    It 'parses inputs YAML into a non-empty config' {
        $Script:Config | Should -Not -BeNullOrEmpty
        $Script:Config.topology | Should -Not -BeNullOrEmpty
        $Script:Config.scenario | Should -Not -BeNullOrEmpty
    }

    It 'renders a non-empty tfvars file' {
        Test-Path $Script:TfvarsPath | Should -BeTrue
        $Script:Tfvars.Length | Should -BeGreaterThan 100
    }

    It 'tfvars contains scenario marker' {
        $Script:Tfvars | Should -Match "scenario\s*=\s*`"$($Script:Config.scenario)`""
    }

    It 'tfvars contains environment marker' {
        $Script:Tfvars | Should -Match "environment\s+=\s+`"$($Script:Config.environment_name)`""
    }

    It 'tfvars contains workload_name marker' {
        $Script:Tfvars | Should -Match "workload_name\s+=\s+`"$($Script:Config.service_name)`""
    }

    Context 'topology=standalone gates' -Skip:($Topology -ne 'standalone') {
        It 'hub_vnet_resource_id is empty' {
            $Script:Config.hub_vnet_resource_id | Should -BeNullOrEmpty
        }
        It 'connectivity_subscription_id is empty in YAML (workload tf falls back to subscription_id)' {
            $Script:Config.connectivity_subscription_id | Should -BeNullOrEmpty
        }
    }

    Context 'topology=spoke gates' -Skip:($Topology -ne 'spoke') {
        It 'hub_vnet_resource_id is populated' {
            $Script:Config.hub_vnet_resource_id | Should -Not -BeNullOrEmpty
        }
        It 'hub_firewall_private_ip is populated' {
            $Script:Config.hub_firewall_private_ip | Should -Not -BeNullOrEmpty
        }
        It 'connectivity_subscription_id is populated' {
            $Script:Config.connectivity_subscription_id | Should -Not -BeNullOrEmpty
        }
    }

    Context 'topology=hub_and_spoke gates' -Skip:($Topology -ne 'hub_and_spoke') {
        It 'hub_vnet_address_space is set (hub bootstrap input)' {
            $Script:Config.hub_vnet_address_space | Should -Not -BeNullOrEmpty
        }
        It 'hub_firewall_sku_tier is Standard or Premium' {
            $Script:Config.hub_firewall_sku_tier | Should -BeIn @('Standard','Premium')
        }
        It 'hub_vnet_resource_id pre-populated for L2 (simulates post-hub-apply)' {
            $Script:Config.hub_vnet_resource_id | Should -Not -BeNullOrEmpty
        }
    }

    Context 'scenario=*_regulated' -Skip:($Scenario -notmatch 'regulated') {
        It 'tfvars wires regulated network policy (azure)' {
            # Write-TfvarsFile picks network_policy=azure when scenario matches regulated
            $Script:Tfvars | Should -Match 'network_policy\s*=\s*"azure"'
        }
        It 'tfvars wires regulated node pool min_count=3' {
            $Script:Tfvars | Should -Match 'min_count\s*=\s*3'
        }
        It 'tfvars wires regulated compliance label' {
            $Script:Tfvars | Should -Match '"compliance"\s*=\s*"pci-dss"'
        }
    }

    Context 'scenario=*_baseline' -Skip:($Scenario -notmatch 'baseline') {
        It 'tfvars wires baseline network policy (calico)' {
            $Script:Tfvars | Should -Match 'network_policy\s*=\s*"calico"'
        }
    }
}
