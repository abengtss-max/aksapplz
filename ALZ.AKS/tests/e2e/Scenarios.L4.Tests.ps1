<#
.SYNOPSIS
    Level 4 — wizard end-to-end (bootstrap + workload plan) via Deploy-AKSLandingZone.

    Exercises the public Deploy-AKSLandingZone cmdlet across the scenario matrix.
    Default mode is -PlanOnly (no real resources, ≈ 1-2 min/scenario, needs Azure
    provider auth). Full apply+destroy mode is gated by ALZ_AKS_E2E_L4_FULL=1.

    Gating:
        $env:ALZ_AKS_E2E_L4       = '1'   # required to run any L4 test
        $env:ALZ_AKS_E2E_L4_FULL  = '1'   # additionally, run full apply+destroy
        $env:ALZ_AKS_E2E_SUB      = <sub> # subscription for provider auth
        $env:TF_VAR_github_personal_access_token         = <pat>
        $env:TF_VAR_github_runners_personal_access_token = <pat>
        $env:ALZ_AKS_E2E_SCENARIO = <wildcard>           # optional filter

    Behaviour:
      - Mirrors the repo to a temp dir (bootstrap/, terraform/, ALZ.AKS/, config/)
      - Drops scenario YAML into config/inputs.<env>.yaml
      - Invokes Deploy-AKSLandingZone -InputConfigPath ... -AutoApprove -SkipPreflight
        (plus -PlanOnly unless ALZ_AKS_E2E_L4_FULL=1)
      - Asserts cmdlet succeeds without throwing
#>

BeforeDiscovery {
    $Script:L4Gated     = ($env:ALZ_AKS_E2E_L4 -eq '1')
    $Script:L4Full      = ($env:ALZ_AKS_E2E_L4_FULL -eq '1')
    $Script:ScenarioDir = Join-Path $PSScriptRoot 'scenarios'
    $scenarioFilter     = if ($env:ALZ_AKS_E2E_SCENARIO) { $env:ALZ_AKS_E2E_SCENARIO } else { '*' }
    $Script:Scenarios   = Get-ChildItem -Path $Script:ScenarioDir -Filter '*.yaml' |
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
    $Script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    Import-Module (Join-Path $Script:RepoRoot 'ALZ.AKS\ALZ.AKS.psd1') -Force
    if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
        throw 'terraform is required for L4 tests'
    }
    if (-not $Script:L4Gated) {
        Write-Warning 'ALZ_AKS_E2E_L4 is not set to 1 — L4 tests will be skipped.'
    }
}

Describe 'L4: wizard end-to-end — <Name>' -ForEach $Script:Scenarios -Skip:(-not $Script:L4Gated) {

    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $Script:Sandbox = Join-Path ([System.IO.Path]::GetTempPath()) "alz-l4-$Name-$([guid]::NewGuid().ToString('N').Substring(0,4))"
        New-Item -ItemType Directory -Path $Script:Sandbox -Force | Out-Null

        # Mirror minimum subset (avoid .git, node_modules, etc.)
        foreach ($dir in @('ALZ.AKS', 'bootstrap', 'terraform', 'config')) {
            $src = Join-Path $repoRoot $dir
            if (Test-Path $src) {
                Copy-Item -Recurse -Force $src (Join-Path $Script:Sandbox $dir)
            }
        }

        # Read scenario YAML, write as config/inputs.<env>.yaml inside sandbox
        $cfg = InModuleScope ALZ.AKS -Parameters @{ p = $Path } -ScriptBlock {
            param($p) Read-FlatYaml -Path $p
        }
        $envName = $cfg.environment_name
        $Script:InputsPath = Join-Path $Script:Sandbox "config\inputs.$envName.yaml"
        Copy-Item -Force $Path $Script:InputsPath

        # Provider auth
        $sub = if ($env:ALZ_AKS_E2E_SUB) { $env:ALZ_AKS_E2E_SUB } else { $cfg.aks_landing_zone_subscription_id }
        $env:ARM_SUBSCRIPTION_ID = $sub

        $Script:DeployOK    = $false
        $Script:DeployError = $null
    }

    AfterAll {
        # If we did a full apply, attempt cleanup (best-effort)
        if ($Script:L4Full -and $Script:DeployOK) {
            try {
                $tfDir = Join-Path $Script:Sandbox 'terraform'
                Push-Location $tfDir
                try {
                    & terraform destroy -auto-approve -input=false -no-color -refresh=false 2>&1 |
                        Out-File (Join-Path $Script:Sandbox 'l4-destroy.log')
                } finally { Pop-Location }
            } catch {
                Write-Warning ("L4 destroy failed for {0}: {1}" -f $Name, $_)
            }
        }
        if ($Script:DeployOK) {
            Remove-Item -Recurse -Force $Script:Sandbox -ErrorAction SilentlyContinue
        } else {
            Write-Host "Sandbox kept for debugging: $Script:Sandbox" -ForegroundColor Yellow
        }
    }

    It 'Deploy-AKSLandingZone completes without throwing' {
        $logPath = Join-Path $Script:Sandbox 'l4-deploy.log'
        $planOnlyFlag = -not $Script:L4Full
        try {
            Push-Location $Script:Sandbox
            try {
                $params = @{
                    InputConfigPath = $Script:InputsPath
                    BootstrapRoot   = $Script:Sandbox
                    AutoApprove     = $true
                    SkipPreflight   = $true
                }
                if ($planOnlyFlag) { $params['PlanOnly'] = $true }
                Deploy-AKSLandingZone @params *>&1 | Tee-Object -FilePath $logPath | Out-Null
                $Script:DeployOK = $true
            } finally { Pop-Location }
        } catch {
            $Script:DeployError = $_
            throw "Deploy-AKSLandingZone failed: $_`nLast log lines:`n$((Get-Content $logPath -ErrorAction SilentlyContinue | Select-Object -Last 30) -join "`n")"
        }
    }

    It 'bootstrap rendered workload terraform' {
        $rendered = Join-Path $Script:Sandbox 'terraform\aks-landing-zone.auto.tfvars'
        Test-Path $rendered | Should -BeTrue
    }
}
