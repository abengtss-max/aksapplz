<#
.SYNOPSIS
    Regression test: verify that resources subject to short Azure name limits
    use the length-safe sha256-suffix pattern in templates/terraform/locals.tf.

    The pattern is:
        length(<full>) <= <max> ? <full> : "<prefix>-<substr(name_prefix,0,N)><substr(sha256(name_prefix),0,3)>"

    Adding a new resource with a tight name limit? Either:
      - Add it to $Script:ProtectedResources below with its max length, and
        implement the same length-safe pattern in locals.tf, OR
      - Document a justified exception here.

    Defence-in-depth on top of the var.environment_short opt-in (commit c638d93).
#>

BeforeDiscovery {
    $Script:RepoRoot      = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $Script:LocalsFiles   = @(
        Join-Path $Script:RepoRoot 'terraform\locals.tf'
        Join-Path $Script:RepoRoot 'ALZ.AKS\templates\terraform\locals.tf'
    )
    $Script:ProtectedResources = @(
        @{ Name = 'key_vault_name';      Max = 24 }
        @{ Name = 'grafana_name';        Max = 23 }
        @{ Name = 'dce_prometheus_name'; Max = 44 }
        @{ Name = 'dcr_prometheus_name'; Max = 64 }
    )
}

Describe 'Naming length safety (regression)' {
    Context 'locals.tf files exist' {
        It 'has <_>' -ForEach $Script:LocalsFiles {
            Test-Path $_ | Should -BeTrue
        }
    }

    Context 'protected resource <_.Name> in <file>' -ForEach @(
        foreach ($file in $Script:LocalsFiles) {
            foreach ($r in $Script:ProtectedResources) {
                @{ Name = $r.Name; Max = $r.Max; file = $file }
            }
        }
    ) {
        BeforeAll {
            $Script:Content = Get-Content -Raw -Path $file
        }

        It 'declares <Name>' {
            $Script:Content | Should -Match "(?m)^\s*$Name\s*="
        }

        It '<Name> uses length-safe ternary capped at <Max>' {
            # Extract the line for this local
            $line = ($Script:Content -split "`n") | Where-Object { $_ -match "^\s*$Name\s*=" } | Select-Object -First 1
            $line | Should -Not -BeNullOrEmpty
            $line | Should -Match 'length\('
            $line | Should -Match "<=\s*$Max\s*\?"
            $line | Should -Match 'sha256\(local\.name_prefix\)'
        }
    }
}
