# Regression test: every CIDR in templates/scenarios/*.tfvars must be properly
# aligned to its prefix length. Caught a real bug on 2026-05-23 where
# aks_user_nodes=10.10.1.0/22 was rejected by Azure with InvalidCIDRNotation
# (a /22 must align on a /22 boundary).

BeforeDiscovery {
    $repoRoot     = (Resolve-Path "$PSScriptRoot\..").Path
    $scenariosDir = Join-Path $repoRoot 'templates\scenarios'

    $Script:CidrCases = @()
    if (Test-Path $scenariosDir) {
        $Script:CidrCases = Get-ChildItem -Path $scenariosDir -Filter '*.tfvars' | ForEach-Object {
            $fileName = $_.Name
            $lines    = Get-Content -LiteralPath $_.FullName
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $rx = [regex]::Matches($lines[$i], '"((?:\d{1,3}\.){3}\d{1,3}/\d{1,2})"')
                foreach ($m in $rx) {
                    @{
                        File = $fileName
                        Line = ($i + 1)
                        Cidr = $m.Groups[1].Value
                    }
                }
            }
        }
    }
}

Describe 'Scenario template CIDR alignment' {

    It '<File>:<Line> <Cidr> is aligned on its prefix boundary' -ForEach $Script:CidrCases {
        $parts = $Cidr -split '/'
        $ip    = $parts[0]
        [int]$prefix = $parts[1]

        $oArr = $ip -split '\.'
        [uint64]$ipInt = ([uint64]$oArr[0] * 16777216) + ([uint64]$oArr[1] * 65536) + ([uint64]$oArr[2] * 256) + [uint64]$oArr[3]

        [uint64]$blockSize = [uint64][math]::Pow(2, 32 - $prefix)
        [uint64]$remainder = $ipInt % $blockSize

        [uint64]$expectedNetInt = $ipInt - $remainder
        $expectedNet = "{0}.{1}.{2}.{3}/{4}" -f `
            ([math]::Floor($expectedNetInt / 16777216) % 256), `
            ([math]::Floor($expectedNetInt / 65536) % 256), `
            ([math]::Floor($expectedNetInt / 256) % 256), `
            ($expectedNetInt % 256), `
            $prefix

        $remainder | Should -Be 0 -Because "$Cidr in $File line $Line is not aligned on a /$prefix boundary; Azure will reject with InvalidCIDRNotation. Use $expectedNet instead."
    }
}
