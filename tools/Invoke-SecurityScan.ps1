#Requires -Version 7.0
<#
.SYNOPSIS
    One-shot security scan for the AKS Application Landing Zone Accelerator.

.DESCRIPTION
    Runs the same three scanners the CI pipeline uses, against both the
    accelerator source and the templates that ship to customer repos:

      1. PowerShell      - PSScriptAnalyzer + InjectionHunter (injection rules)
      2. Infrastructure  - Checkov over every Terraform tree, using the shared,
                           documented policy in .checkov.yaml
      3. Secrets         - detect-secrets diffed against .secrets.baseline

    Checkov and detect-secrets are gating (non-zero exit on a *new* finding).
    PowerShell analysis is advisory by default (errors gate; use -StrictPS to
    also gate on warnings) because the codebase has reviewed, accepted
    dynamic-property-name patterns. Full triage: SECURITY.md "Security scanning".

.PARAMETER StrictPS
    Treat PSScriptAnalyzer *warnings* as failures too (errors always fail).

.PARAMETER SkipPowerShell
.PARAMETER SkipTerraform
.PARAMETER SkipSecrets
    Skip an individual scanner.

.EXAMPLE
    pwsh ./tools/Invoke-SecurityScan.ps1

.EXAMPLE
    pwsh ./tools/Invoke-SecurityScan.ps1 -StrictPS
#>
[CmdletBinding()]
param(
    [switch]$StrictPS,
    [switch]$SkipPowerShell,
    [switch]$SkipTerraform,
    [switch]$SkipSecrets
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Repo root = parent of this script's folder (tools/).
$RepoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $RepoRoot
$exitCode = 0
$summary = [System.Collections.Generic.List[string]]::new()

function Write-Section($Title) {
    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ('=' * 72) -ForegroundColor Cyan
}

# Terraform trees scanned by Checkov (root, customer template, bootstrap modules).
$TerraformDirs = @(
    'terraform',
    'ALZ.AKS/templates/terraform',
    'bootstrap/modules'
) | Where-Object { Test-Path (Join-Path $RepoRoot $_) }

try {
    # ------------------------------------------------------------------ PowerShell
    if (-not $SkipPowerShell) {
        Write-Section 'PowerShell - PSScriptAnalyzer + InjectionHunter'
        if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
            Write-Host 'Installing PSScriptAnalyzer (CurrentUser)...' -ForegroundColor Yellow
            Install-Module PSScriptAnalyzer -Force -SkipPublisherCheck -Scope CurrentUser
        }
        Import-Module PSScriptAnalyzer

        $analyzerArgs = @{
            Path        = $RepoRoot
            Recurse     = $true
            Severity    = @('Warning', 'Error')
            # Vendored Terraform provider scripts are not ours to fix.
            ExcludeRule = @(
                'PSAvoidUsingWriteHost',
                'PSUseShouldProcessForStateChangingFunctions',
                'PSAvoidUsingConvertToSecureStringWithPlainText',
                'PSUseDeclaredVarsMoreThanAssignments'
            )
        }

        # InjectionHunter adds code-injection-specific rules when available.
        $ih = Get-Module -ListAvailable -Name InjectionHunter | Select-Object -First 1
        if ($ih) {
            # -CustomRulePath must point at the .psd1 manifest, not the folder.
            $analyzerArgs['CustomRulePath'] = Join-Path $ih.ModuleBase 'InjectionHunter.psd1'
            Write-Host "InjectionHunter rules: $($analyzerArgs['CustomRulePath'])" -ForegroundColor DarkGray
        }
        else {
            Write-Host 'InjectionHunter not installed - skipping injection rules (Install-Module InjectionHunter).' -ForegroundColor Yellow
        }

        $findings = @(Invoke-ScriptAnalyzer @analyzerArgs |
            Where-Object { $_.ScriptPath -notmatch '[\\/]\.terraform[\\/]' })

        $errors = @($findings | Where-Object { $_.Severity -eq 'Error' })
        $warnings = @($findings | Where-Object { $_.Severity -eq 'Warning' })

        if ($findings.Count -gt 0) {
            $findings | Format-Table RuleName, Severity,
                @{ N = 'File'; E = { Resolve-Path -Relative $_.ScriptPath } }, Line -AutoSize |
                Out-String | Write-Host
        }
        Write-Host ("PowerShell: {0} error(s), {1} warning(s)." -f $errors.Count, $warnings.Count)

        $psFail = ($errors.Count -gt 0) -or ($StrictPS -and $warnings.Count -gt 0)
        if ($psFail) {
            $exitCode = 1
            $summary.Add("FAIL  PowerShell  ($($errors.Count) error, $($warnings.Count) warning)")
        }
        else {
            $summary.Add("PASS  PowerShell  ($($errors.Count) error, $($warnings.Count) warning - advisory)")
        }
    }

    # ------------------------------------------------------------------- Terraform
    if (-not $SkipTerraform) {
        Write-Section 'Infrastructure - Checkov (.checkov.yaml policy)'
        $checkovOk = $true
        foreach ($dir in $TerraformDirs) {
            Write-Host "--- $dir ---" -ForegroundColor DarkGray
            python -m checkov.main -d $dir --config-file .checkov.yaml
            if ($LASTEXITCODE -ne 0) { $checkovOk = $false }
        }
        if ($checkovOk) {
            $summary.Add('PASS  Checkov     (all Terraform trees clean)')
        }
        else {
            $exitCode = 1
            $summary.Add('FAIL  Checkov     (new finding - triage or add to .checkov.yaml)')
        }
    }

    # --------------------------------------------------------------------- Secrets
    if (-not $SkipSecrets) {
        Write-Section 'Secrets - detect-secrets (vs .secrets.baseline)'
        if (-not (Test-Path '.secrets.baseline')) {
            Write-Host '.secrets.baseline missing - run: python -m detect_secrets scan > .secrets.baseline' -ForegroundColor Yellow
            $exitCode = 1
            $summary.Add('FAIL  Secrets     (.secrets.baseline missing)')
        }
        else {
            # Scan into a temp baseline and compare only the *results* (the
            # baseline's generated_at timestamp changes every run, so a raw file
            # diff would be noisy and non-deterministic).
            $tmp = New-TemporaryFile
            python -m detect_secrets scan `
                --exclude-files '\.terraform/|\.venv|site/|/results/|\.git/|\.secrets\.baseline' |
                Set-Content -Path $tmp
            $baseResults = (Get-Content '.secrets.baseline' -Raw | ConvertFrom-Json).results | ConvertTo-Json -Depth 10
            $newResults = (Get-Content $tmp -Raw | ConvertFrom-Json).results | ConvertTo-Json -Depth 10
            Remove-Item $tmp -Force
            if ($baseResults -ne $newResults) {
                Write-Host 'Secret findings differ from the reviewed baseline.' -ForegroundColor Red
                Write-Host 'Review/refresh with: python -m detect_secrets scan > .secrets.baseline; python -m detect_secrets audit .secrets.baseline' -ForegroundColor Yellow
                $exitCode = 1
                $summary.Add('FAIL  Secrets     (findings differ from baseline)')
            }
            else {
                Write-Host 'No new secrets beyond the reviewed baseline.' -ForegroundColor Green
                $summary.Add('PASS  Secrets     (no new findings)')
            }
        }
    }

    # --------------------------------------------------------------------- Summary
    Write-Section 'Summary'
    $summary | ForEach-Object {
        $color = if ($_ -like 'FAIL*') { 'Red' } else { 'Green' }
        Write-Host "  $_" -ForegroundColor $color
    }
    Write-Host ''
    if ($exitCode -eq 0) {
        Write-Host 'Security scan PASSED.' -ForegroundColor Green
    }
    else {
        Write-Host 'Security scan FAILED - see findings above.' -ForegroundColor Red
    }
}
finally {
    Pop-Location
}

exit $exitCode
