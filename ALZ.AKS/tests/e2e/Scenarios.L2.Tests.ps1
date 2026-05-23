<#
.SYNOPSIS
    Level 2 — Scenario terraform validate + plan tests.

    For each scenario YAML under tests/e2e/scenarios/:
      - Copy ALZ.AKS/templates/terraform/*.tf into a temp sandbox
      - Render the env tfvars from the scenario YAML (via Write-TfvarsFile)
      - Copy the matching templates/scenarios/<scenario>.tfvars into the sandbox
      - terraform init -backend=local + terraform validate + terraform plan (no apply)
      - Assert plan exit=0 and "Plan: N to add, 0 to change, 0 to destroy"

    Requires:
      - terraform on PATH
      - az login session with read access to ARM_SUBSCRIPTION_ID (provider auth)
      - $env:ALZ_AKS_E2E_SUB set to a real subscription ID
        (defaults to the scenario YAML's aks_landing_zone_subscription_id if env var unset)

    Cost: free (plan only, no apply). ~1-2 min per scenario.

    Run:
      Invoke-Pester -Path .\ALZ.AKS\tests\e2e\Scenarios.L2.Tests.ps1 -Output Detailed

    Limit to one scenario for fast iteration:
      Invoke-Pester -Path .\ALZ.AKS\tests\e2e\Scenarios.L2.Tests.ps1 -Output Detailed `
                    -FullNameFilter '*01-standalone-baseline*'
#>

BeforeDiscovery {
    $Script:RepoRoot     = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    $Script:ScenarioDir  = Join-Path $PSScriptRoot 'scenarios'
    # Optional discovery-time filter (env: ALZ_AKS_E2E_SCENARIO = wildcard against BaseName)
    $scenarioFilter      = if ($env:ALZ_AKS_E2E_SCENARIO) { $env:ALZ_AKS_E2E_SCENARIO } else { '*' }
    $Script:Scenarios    = Get-ChildItem -Path $Script:ScenarioDir -Filter '*.yaml' |
        Where-Object { $_.BaseName -like $scenarioFilter } |
        ForEach-Object {
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

    # Skip everything when terraform isn't installed
    if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
        Set-ItResult -Skipped -Because 'terraform is not on PATH'
    }
}

Describe 'L2: terraform plan — <Name>' -ForEach $Script:Scenarios {

    BeforeAll {
        $repoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $tplTfDir   = Join-Path $repoRoot 'ALZ.AKS\templates\terraform'
        $tplScenDir = Join-Path $repoRoot 'ALZ.AKS\templates\scenarios'

        # Sandbox
        $Script:Sandbox = Join-Path ([System.IO.Path]::GetTempPath()) "alz-l2-$Name-$(Get-Random)"
        New-Item -ItemType Directory -Path $Script:Sandbox -Force | Out-Null

        # Copy templates
        Copy-Item -Path (Join-Path $tplTfDir '*.tf') -Destination $Script:Sandbox -Force

        # Local backend override
        @"
terraform {
  backend "local" {}
}
"@ | Set-Content (Join-Path $Script:Sandbox 'override.tf')

        # Render env tfvars
        $envTfvars = Join-Path $Script:Sandbox 'aks-landing-zone.auto.tfvars'
        InModuleScope ALZ.AKS -Parameters @{ p = $Path; out = $envTfvars } -ScriptBlock {
            param($p, $out)
            $c = Read-FlatYaml -Path $p
            Write-TfvarsFile -Config $c -OutputPath $out
        }

        # Copy scenario tfvars overlay
        $scenSrc = Join-Path $tplScenDir "$Scenario.tfvars"
        if (Test-Path $scenSrc) {
            Copy-Item -Path $scenSrc -Destination (Join-Path $Script:Sandbox 'scenario.auto.tfvars') -Force
        }

        # Provider auth — derive subscription from env or YAML
        $sub = if ($env:ALZ_AKS_E2E_SUB) { $env:ALZ_AKS_E2E_SUB } else {
            InModuleScope ALZ.AKS -Parameters @{ p = $Path } -ScriptBlock {
                param($p) (Read-FlatYaml -Path $p).aks_landing_zone_subscription_id
            }
        }
        $env:ARM_SUBSCRIPTION_ID                   = $sub
        $env:TF_VAR_github_personal_access_token   = 'dummy_plan_only'

        # init
        Push-Location $Script:Sandbox
        try {
            $Script:InitLog = & terraform init -reconfigure -input=false 2>&1 | Out-String
            $Script:InitExit = $LASTEXITCODE
        } finally {
            Pop-Location
        }
    }

    AfterAll {
        Remove-Item -Recurse -Force $Script:Sandbox -ErrorAction SilentlyContinue
    }

    It 'templates/terraform copied to sandbox' {
        (Get-ChildItem -Path $Script:Sandbox -Filter '*.tf').Count | Should -BeGreaterThan 5
    }

    It 'env tfvars rendered' {
        Test-Path (Join-Path $Script:Sandbox 'aks-landing-zone.auto.tfvars') | Should -BeTrue
    }

    It 'terraform init succeeded' {
        $Script:InitExit | Should -Be 0 -Because "terraform init log: $($Script:InitLog -split "`n" | Select-Object -Last 5 | Out-String)"
    }

    It 'terraform validate passes' {
        Push-Location $Script:Sandbox
        try {
            $out  = & terraform validate -no-color 2>&1 | Out-String
            $exit = $LASTEXITCODE
        } finally {
            Pop-Location
        }
        $exit | Should -Be 0 -Because $out
    }

    It 'terraform plan succeeds with N>0 resources to add and 0 to change/destroy' {
        Push-Location $Script:Sandbox
        try {
            $planLog = Join-Path $Script:Sandbox 'plan.log'
            & terraform plan -refresh=false -lock=false -input=false -no-color 2>&1 > $planLog
            $exit = $LASTEXITCODE
            $tail = Get-Content $planLog | Select-Object -Last 50 | Out-String
            $planLine = (Get-Content $planLog | Where-Object { $_ -match '^Plan:\s+\d+' } | Select-Object -Last 1)
        } finally {
            Pop-Location
        }
        $exit | Should -Be 0 -Because $tail
        $planLine | Should -Match 'Plan:\s+\d+\s+to add,\s+0\s+to change,\s+0\s+to destroy'
    }
}
