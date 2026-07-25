<#
.SYNOPSIS
    Regression test: verify that resources subject to short Azure name limits
    use a length-safe naming pattern in the region module locals
    (modules/region/locals.tf).

    Two length-safe styles are in use:
      - ternary : length(<full>) <= <max> ? <full> : "<prefix>-<substr(name_prefix,0,N)><substr(sha256(name_prefix),0,3)>"
      - random  : key_vault_name only — a pre-truncated prefix (_kv_prefix, capped
                  at 17) plus a 3-char random_string suffix, so kv-{<=17}-{3} always
                  fits the 24-char Key Vault limit while staying globally unique.

    Adding a new resource with a tight name limit? Either:
      - Add it to $Script:ProtectedResources below with its max length + style,
        and implement the matching pattern in modules/region/locals.tf, OR
      - Document a justified exception here.

    Defence-in-depth on top of the var.environment_short opt-in (commit c638d93).
#>

BeforeDiscovery {
    $Script:RepoRoot      = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $Script:LocalsFiles   = @(
        Join-Path $Script:RepoRoot 'terraform\modules\region\locals.tf'
        Join-Path $Script:RepoRoot 'ALZ.AKS\templates\terraform\modules\region\locals.tf'
    )
    $Script:ProtectedResources = @(
        @{ Name = 'key_vault_name';      Max = 24; Style = 'random'  }
        @{ Name = 'grafana_name';        Max = 23; Style = 'ternary' }
        @{ Name = 'dce_prometheus_name'; Max = 44; Style = 'ternary' }
        @{ Name = 'dcr_prometheus_name'; Max = 64; Style = 'ternary' }
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
                @{ Name = $r.Name; Max = $r.Max; Style = $r.Style; file = $file }
            }
        }
    ) {
        BeforeAll {
            $Script:Content = Get-Content -Raw -Path $file
        }

        It 'declares <Name>' {
            $Script:Content | Should -Match "(?m)^\s*$Name\s*="
        }

        It '<Name> uses a length-safe pattern capped at <Max>' {
            # Extract the line for this local
            $line = ($Script:Content -split "`n") | Where-Object { $_ -match "^\s*$Name\s*=" } | Select-Object -First 1
            $line | Should -Not -BeNullOrEmpty

            if ($Style -eq 'random') {
                # kv-{<=17}-{3-char random}. Prefix truncated via _kv_prefix so the
                # 24-char Key Vault limit always holds; suffix keeps it globally unique.
                $Script:Content | Should -Match '_kv_prefix\s*=\s*length\(local\.name_prefix\)\s*<=\s*17\s*\?'
                $line | Should -Match 'local\._kv_prefix'
                $line | Should -Match 'random_string\.kv_suffix'
            } else {
                $line | Should -Match 'length\('
                $line | Should -Match "<=\s*$Max\s*\?"
                $line | Should -Match 'sha256\(local\.name_prefix\)'
            }
        }
    }
}
