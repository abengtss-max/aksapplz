<#
.SYNOPSIS
    Level 3 — REAL terraform apply + destroy per scenario.

    DOES create live Azure resources. ALWAYS gated by env var:
        $env:ALZ_AKS_E2E_APPLY = '1'

    Otherwise every It is skipped.

    Required env:
        ALZ_AKS_E2E_APPLY                    = '1'             (required to opt in)
        ALZ_AKS_E2E_SUB                      = <subscription>  (required if not in YAML)
        TF_VAR_github_personal_access_token  = <pat>           (workload module needs it)
        TF_VAR_github_runners_personal_access_token = <pat>
        ALZ_AKS_E2E_SCENARIO                 = <wildcard>      (optional discovery filter)
        ALZ_AKS_E2E_SUFFIX                   = <2-3 chars>     (optional run suffix, default random)

    Behaviour:
      - Copies templates/terraform to sandbox + override.tf (local backend)
      - Renders aks-landing-zone.auto.tfvars from scenario YAML, with environment_name
        appended with a random 2-char suffix to avoid collisions
      - terraform init + apply (≈ 15-25 min for AKS)
      - terraform destroy — runs unconditionally (AfterAll), even on failure
      - Tags resources with createdBy=e2e-l3, runId, scenario (janitor-friendly)

    Run locally:
        $env:ALZ_AKS_E2E_APPLY = '1'
        $env:ALZ_AKS_E2E_SUB   = '<sub>'
        $env:ALZ_AKS_E2E_SCENARIO = '01-standalone-baseline'   # one at a time recommended
        Invoke-Pester ./ALZ.AKS/tests/e2e/Scenarios.L3.Tests.ps1 -Output Detailed
#>

BeforeDiscovery {
    $Script:ApplyGated   = ($env:ALZ_AKS_E2E_APPLY -eq '1')
    $Script:ScenarioDir  = Join-Path $PSScriptRoot 'scenarios'
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
    if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
        throw 'terraform is required for L3 tests'
    }
    if ($env:ALZ_AKS_E2E_APPLY -ne '1') {
        Write-Warning 'ALZ_AKS_E2E_APPLY is not set to 1 — L3 tests will be skipped.'
    }
}

Describe 'L3: apply+destroy — <Name>' -ForEach $Script:Scenarios -Skip:(-not $Script:ApplyGated) {

    BeforeAll {
        $repoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $tplTfDir   = Join-Path $repoRoot 'ALZ.AKS\templates\terraform'
        $tplScenDir = Join-Path $repoRoot 'ALZ.AKS\templates\scenarios'

        $suffix = if ($env:ALZ_AKS_E2E_SUFFIX) { $env:ALZ_AKS_E2E_SUFFIX } else {
            ([guid]::NewGuid().ToString('N').Substring(0,2))
        }

        # Sandbox
        $Script:Sandbox = Join-Path ([System.IO.Path]::GetTempPath()) "alz-l3-$Name-$suffix"
        New-Item -ItemType Directory -Path $Script:Sandbox -Force | Out-Null

        Copy-Item -Path (Join-Path $tplTfDir '*.tf') -Destination $Script:Sandbox -Force

        @"
terraform {
  backend "local" {}
}
"@ | Set-Content (Join-Path $Script:Sandbox 'override.tf')

        # Read YAML and mutate env name with suffix for uniqueness
        $envTfvars = Join-Path $Script:Sandbox 'aks-landing-zone.auto.tfvars'
        InModuleScope ALZ.AKS -Parameters @{ p = $Path; out = $envTfvars; sfx = $suffix } -ScriptBlock {
            param($p, $out, $sfx)
            $c = Read-FlatYaml -Path $p
            # Append suffix to environment_name to avoid collisions when re-running
            $base = $c.environment_name
            $maxBase = 4 - $sfx.Length
            if ($maxBase -lt 1) { $maxBase = 1 }
            $c.environment_name = ($base.Substring(0, [Math]::Min($base.Length, $maxBase)) + $sfx).ToLower()
            Write-TfvarsFile -Config $c -OutputPath $out
        }

        $scenSrc = Join-Path $tplScenDir "$Scenario.tfvars"
        if (Test-Path $scenSrc) {
            Copy-Item -Path $scenSrc -Destination (Join-Path $Script:Sandbox 'scenario.auto.tfvars') -Force
        }

        # Tagging overlay
        $tagSnippet = @"
tags = {
  createdBy = "e2e-l3"
  scenario  = "$Name"
  suffix    = "$suffix"
  ttlHours  = "6"
}
"@
        Set-Content -Path (Join-Path $Script:Sandbox 'tags.auto.tfvars') -Value $tagSnippet

        # Provider env
        $sub = if ($env:ALZ_AKS_E2E_SUB) { $env:ALZ_AKS_E2E_SUB } else {
            InModuleScope ALZ.AKS -Parameters @{ p = $Path } -ScriptBlock {
                param($p) (Read-FlatYaml -Path $p).aks_landing_zone_subscription_id
            }
        }
        $env:ARM_SUBSCRIPTION_ID = $sub

        Push-Location $Script:Sandbox
        try {
            $Script:InitLog  = & terraform init -reconfigure -input=false 2>&1 | Out-String
            $Script:InitExit = $LASTEXITCODE
        } finally { Pop-Location }

        $Script:ApplyOK    = $false
        $Script:DestroyOK  = $false
    }

    AfterAll {
        # ALWAYS destroy if anything was created
        if ($Script:ApplyOK) {
            Push-Location $Script:Sandbox
            try {
                Write-Host "Destroying sandbox $Script:Sandbox ..." -ForegroundColor Yellow
                & terraform destroy -auto-approve -input=false -no-color -refresh=false 2>&1 |
                    Tee-Object -FilePath (Join-Path $Script:Sandbox 'destroy.log') |
                    Out-Null
                $Script:DestroyOK = ($LASTEXITCODE -eq 0)
                if (-not $Script:DestroyOK) {
                    Write-Warning "Destroy failed for $Name — janitor must reap by tag (createdBy=e2e-l3)."
                }
            } finally { Pop-Location }
        }
        # Keep sandbox dir on failure for debugging; remove on full success
        if ($Script:DestroyOK) {
            Remove-Item -Recurse -Force $Script:Sandbox -ErrorAction SilentlyContinue
        } else {
            Write-Host "Sandbox kept for debugging: $Script:Sandbox" -ForegroundColor Yellow
        }
    }

    It 'terraform init succeeded' {
        $Script:InitExit | Should -Be 0 -Because $Script:InitLog
    }

    It 'terraform apply succeeds' {
        Push-Location $Script:Sandbox
        try {
            & terraform apply -auto-approve -input=false -no-color 2>&1 |
                Tee-Object -FilePath (Join-Path $Script:Sandbox 'apply.log') |
                Out-Null
            $exit = $LASTEXITCODE
        } finally { Pop-Location }
        $Script:ApplyOK = ($exit -eq 0)
        $tail = (Get-Content (Join-Path $Script:Sandbox 'apply.log') | Select-Object -Last 30) -join "`n"
        $exit | Should -Be 0 -Because $tail
    }

    It 'cluster name output is non-empty' -Skip:(-not $Script:ApplyOK) {
        Push-Location $Script:Sandbox
        try {
            $name = (& terraform output -raw aks_cluster_name 2>&1) | Out-String
        } finally { Pop-Location }
        $name.Trim() | Should -Not -BeNullOrEmpty
    }
}
