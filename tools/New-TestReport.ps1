<#
.SYNOPSIS
    Aggregate Pester NUnit XML results into a single Markdown report.

.DESCRIPTION
    Scans one or more directories for NUnit-format XML files (as emitted by
    Pester 5 `TestResult.OutputFormat = 'NUnitXml'`), tallies pass/fail/skip
    counts per file, lists every failing test with its message, and renders a
    Markdown summary.

    Designed for GitHub Actions: when $env:GITHUB_STEP_SUMMARY is set the report
    is appended there so it renders on the workflow run page. A copy is always
    written to -OutputPath for upload as an artifact.

    Exit code is 0 unless -FailOnError is supplied and at least one test failed,
    in which case it is 1 — letting the workflow gate on the aggregated result.

.PARAMETER Path
    One or more directories (searched recursively) or explicit .xml files.

.PARAMETER OutputPath
    File to write the Markdown report to. Default: ./test-report.md

.PARAMETER Title
    Heading for the report.

.PARAMETER FailOnError
    Return exit code 1 when any test failed.

.EXAMPLE
    ./tools/New-TestReport.ps1 -Path ./ALZ.AKS/tests/results -FailOnError
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]] $Path,

    [string] $OutputPath = './test-report.md',

    [string] $Title = 'AKS Landing Zone — Validation Report',

    [switch] $FailOnError
)

$ErrorActionPreference = 'Stop'

function Get-NUnitFiles {
    param([string[]] $Paths)
    $files = [System.Collections.Generic.List[string]]::new()
    foreach ($p in $Paths) {
        if (-not (Test-Path $p)) { continue }
        $item = Get-Item $p
        if ($item.PSIsContainer) {
            Get-ChildItem -Path $p -Recurse -Filter '*.xml' -File |
                ForEach-Object { $files.Add($_.FullName) }
        } elseif ($item.Extension -eq '.xml') {
            $files.Add($item.FullName)
        }
    }
    $files | Sort-Object -Unique
}

$xmlFiles = Get-NUnitFiles -Paths $Path

$suites   = [System.Collections.Generic.List[object]]::new()
$failures = [System.Collections.Generic.List[object]]::new()

$total = 0; $passed = 0; $failed = 0; $skipped = 0

foreach ($file in $xmlFiles) {
    try {
        [xml]$doc = Get-Content -Path $file -Raw
    } catch {
        Write-Warning "Could not parse '$file': $($_.Exception.Message)"
        continue
    }

    $cases = $doc.SelectNodes('//test-case')
    if (-not $cases -or $cases.Count -eq 0) { continue }

    $sPass = 0; $sFail = 0; $sSkip = 0
    foreach ($c in $cases) {
        $total++
        $result = "$($c.result)"
        # NUnit 2.5 (Pester): Success | Failure | Ignored | Inconclusive | Skipped
        switch -Regex ($result) {
            'Success|Passed'                    { $passed++;  $sPass++ }
            'Failure|Failed|Error'              {
                $failed++; $sFail++
                $msg = ''
                $fnode = $c.SelectSingleNode('failure/message')
                if ($fnode) { $msg = ($fnode.InnerText).Trim() }
                $failures.Add([pscustomobject]@{
                    Suite   = [System.IO.Path]::GetFileName($file)
                    Test    = "$($c.name)"
                    Message = if ($msg.Length -gt 300) { $msg.Substring(0, 300) + '…' } else { $msg }
                })
            }
            default                             { $skipped++; $sSkip++ }  # Ignored/Skipped/Inconclusive
        }
    }

    $suites.Add([pscustomobject]@{
        File    = [System.IO.Path]::GetFileName($file)
        Total   = $sPass + $sFail + $sSkip
        Passed  = $sPass
        Failed  = $sFail
        Skipped = $sSkip
    })
}

$status = if ($failed -gt 0) { '❌ FAILED' } elseif ($total -eq 0) { '⚠️ NO TESTS' } else { '✅ PASSED' }
$stamp  = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss') + ' UTC'

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("# $Title")
[void]$sb.AppendLine()
[void]$sb.AppendLine("**Status:** $status  ")
[void]$sb.AppendLine("**Generated:** $stamp  ")
[void]$sb.AppendLine("**Totals:** $total tests — ✅ $passed passed · ❌ $failed failed · ⏭️ $skipped skipped")
[void]$sb.AppendLine()

if ($suites.Count -gt 0) {
    [void]$sb.AppendLine('## Suites')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('| Result file | Total | Passed | Failed | Skipped |')
    [void]$sb.AppendLine('| --- | ---: | ---: | ---: | ---: |')
    foreach ($s in $suites) {
        $icon = if ($s.Failed -gt 0) { '❌' } else { '✅' }
        [void]$sb.AppendLine("| $icon $($s.File) | $($s.Total) | $($s.Passed) | $($s.Failed) | $($s.Skipped) |")
    }
    [void]$sb.AppendLine()
} else {
    [void]$sb.AppendLine('> No NUnit result files were found.')
    [void]$sb.AppendLine()
}

if ($failures.Count -gt 0) {
    [void]$sb.AppendLine('## Failures')
    [void]$sb.AppendLine()
    foreach ($f in $failures) {
        [void]$sb.AppendLine("- **$($f.Test)** _(in $($f.Suite))_")
        if ($f.Message) {
            [void]$sb.AppendLine("  - $($f.Message -replace '\r?\n', ' ')")
        }
    }
    [void]$sb.AppendLine()
}

$report = $sb.ToString()

# Write artifact copy
$outDir = Split-Path -Parent $OutputPath
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$report | Set-Content -Path $OutputPath -Encoding utf8

# Append to the GitHub Actions step summary when running in CI
if ($env:GITHUB_STEP_SUMMARY) {
    Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $report -Encoding utf8
}

# Also echo to the console log
Write-Host $report

if ($FailOnError -and $failed -gt 0) {
    exit 1
}
exit 0
