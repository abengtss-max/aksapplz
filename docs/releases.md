# Releases & versions

The accelerator ships as **versioned GitHub Releases**. Each release is an immutable, tested
snapshot of the PowerShell module and its embedded Terraform templates.

- :material-tag: **Release notes & downloads:**
  [github.com/abengtss-max/aksapplz/releases](https://github.com/abengtss-max/aksapplz/releases)

## Always use the latest release (default)

The install one-liner resolves the newest published release automatically:

```powershell
& ([scriptblock]::Create((Invoke-RestMethod https://raw.githubusercontent.com/abengtss-max/aksapplz/main/install.ps1)))
Deploy-AKSLandingZone
```

## Pin a specific release

Pass `-Release <tag>` to lock to an exact version — recommended for production and CI so deploys
are reproducible:

```powershell
& ([scriptblock]::Create((Invoke-RestMethod https://raw.githubusercontent.com/abengtss-max/aksapplz/main/install.ps1))) -Release v1.4.0
Deploy-AKSLandingZone
```

## How versioning works

- Releases follow [Semantic Versioning](https://semver.org/): `vMAJOR.MINOR.PATCH`.
  - **MAJOR** — breaking changes to inputs or behavior.
  - **MINOR** — new backward-compatible features and options.
  - **PATCH** — fixes and small improvements.
- Pre-releases (e.g. `v1.4.0-rc5`) are published for validation and are **not** selected by
  "latest" unless you pin them explicitly.
- The module caches each version under `~/.alz-aks/`, so switching or pinning never re-downloads a
  version you already have.

## Checking your installed version

```powershell
(Get-Module ALZ.AKS).Version
```

When a newer release is available, `Deploy-AKSLandingZone` prints a non-blocking notice at startup.
Suppress it for unattended runs:

```powershell
$env:ALZAKS_SKIP_UPDATE_CHECK = '1'
```

## Upgrading

Re-run the install one-liner (without `-Release`) to move to the latest, then re-run
`Deploy-AKSLandingZone -Environment <env>`. Review the release notes for any breaking changes
before upgrading a production environment.
