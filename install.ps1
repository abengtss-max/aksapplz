<#
.SYNOPSIS
    Installs and imports the ALZ.AKS module from a GitHub Release, then exposes
    the Deploy-AKSLandingZone command.

.DESCRIPTION
    This is the customer entrypoint for the AKS Application Landing Zone Accelerator.
    By default it resolves the LATEST published GitHub Release; pass -Release to pin
    an exact version for reproducible deploys.

    Each version is cached under ~/.alz-aks/<version>/ so re-running is fast and
    switching versions never re-downloads something you already have.

.PARAMETER Release
    The release to install: 'latest' (default) or an exact tag such as 'v1.4.0'.

.PARAMETER Repository
    The GitHub repository in 'owner/name' form. Defaults to the official repo.

.PARAMETER Force
    Re-download and re-extract even if the version is already cached.

.EXAMPLE
    # Always install & import the latest release
    & ([scriptblock]::Create((Invoke-RestMethod https://raw.githubusercontent.com/abengtss-max/aksapplz/main/install.ps1)))
    Deploy-AKSLandingZone

.EXAMPLE
    # Pin a specific release
    & ([scriptblock]::Create((Invoke-RestMethod https://raw.githubusercontent.com/abengtss-max/aksapplz/main/install.ps1))) -Release v1.4.0
    Deploy-AKSLandingZone
#>
[CmdletBinding()]
param(
    [string]$Release = 'latest',
    [string]$Repository = 'abengtss-max/aksapplz',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message, [string]$Color = 'Cyan')
    Write-Host "[ALZ.AKS] $Message" -ForegroundColor $Color
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7+ is required. Current version: $($PSVersionTable.PSVersion). Install with: winget install Microsoft.PowerShell"
}

# GitHub API requires a User-Agent. Use a token if present to lift rate limits.
$headers = @{ 'User-Agent' = 'alz-aks-installer'; 'Accept' = 'application/vnd.github+json' }
if ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $env:GITHUB_TOKEN" }

$apiBase = "https://api.github.com/repos/$Repository/releases"
$apiUrl = if ($Release -eq 'latest') { "$apiBase/latest" } else { "$apiBase/tags/$Release" }

Write-Step "Resolving release '$Release' from $Repository ..."
try {
    $rel = Invoke-RestMethod -Uri $apiUrl -Headers $headers
}
catch {
    throw "Could not resolve release '$Release' for '$Repository'. Verify the tag exists at https://github.com/$Repository/releases. Underlying error: $($_.Exception.Message)"
}

$tag = $rel.tag_name
$version = $tag.TrimStart('v')
Write-Step "Selected $tag"

# Pick the module zip asset (prefer ALZ.AKS-*.zip, else the first .zip).
$asset = $rel.assets | Where-Object { $_.name -like 'ALZ.AKS-*.zip' } | Select-Object -First 1
if (-not $asset) { $asset = $rel.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1 }
if (-not $asset) {
    throw "Release '$tag' has no .zip asset to install. Check the release at https://github.com/$Repository/releases/tag/$tag"
}

$cacheRoot = Join-Path $HOME '.alz-aks'
$versionDir = Join-Path $cacheRoot $version
$manifestPath = Join-Path $versionDir 'ALZ.AKS/ALZ.AKS.psd1'

if ($Force -and (Test-Path $versionDir)) {
    Remove-Item -Recurse -Force $versionDir
}

if (-not (Test-Path $manifestPath)) {
    New-Item -ItemType Directory -Force -Path $versionDir | Out-Null
    $zipPath = Join-Path $cacheRoot $asset.name
    Write-Step "Downloading $($asset.name) ..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -Headers $headers
    Write-Step "Extracting ..."
    Expand-Archive -Path $zipPath -DestinationPath $versionDir -Force
    Remove-Item -Force $zipPath
}
else {
    Write-Step "Using cached version $version"
}

if (-not (Test-Path $manifestPath)) {
    throw "Module manifest not found after extraction at '$manifestPath'. The release asset layout may be unexpected."
}

# Reload cleanly so the requested version wins.
Get-Module ALZ.AKS | Remove-Module -Force -ErrorAction SilentlyContinue
Import-Module $manifestPath -Force

$imported = Get-Module ALZ.AKS
Write-Step "ALZ.AKS $($imported.Version) is ready." 'Green'
Write-Host ""
Write-Host "  Next step:" -ForegroundColor White
Write-Host "    Deploy-AKSLandingZone" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Docs: https://abengtss-max.github.io/aksapplz/" -ForegroundColor DarkGray
