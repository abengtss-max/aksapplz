@{
    # Module manifest for ALZ.AKS
    # AKS Application Landing Zone Accelerator - PowerShell Module

    # Script module file associated with this manifest
    RootModule        = 'ALZ.AKS.psm1'

    # Version number of this module
    ModuleVersion     = '1.5.0'

    # ID used to uniquely identify this module
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'

    # Author of this module
    Author            = 'Platform Team'

    # Company or vendor of this module
    CompanyName       = 'abengtss-max'

    # Copyright statement for this module
    Copyright         = '(c) 2026 abengtss-max. All rights reserved.'

    # Description of the functionality provided by this module
    Description       = 'AKS Application Landing Zone Accelerator. Deploys a production-ready AKS cluster into an existing Azure Landing Zone using a Terraform composition (AVM-first), following the upstream ALZ accelerator pattern. Run Deploy-AKSLandingZone to bootstrap.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.0'

    # Functions to export from this module
    FunctionsToExport = @('Deploy-AKSLandingZone')

    # Cmdlets to export from this module
    CmdletsToExport   = @()

    # Variables to export from this module
    VariablesToExport  = @()

    # Aliases to export from this module
    AliasesToExport    = @()

    # Private data to pass to the module specified in RootModule
    PrivateData = @{
        PSData = @{
            # Tags applied to this module for PSGallery discovery
            Tags         = @('Azure', 'AKS', 'Kubernetes', 'Landing-Zone', 'Accelerator', 'Terraform', 'ALZ', 'Infrastructure-as-Code')

            # A URL to the license for this module
            LicenseUri   = 'https://github.com/abengtss-max/aksapplz/blob/main/LICENSE'

            # A URL to the main website for this project
            ProjectUri   = 'https://github.com/abengtss-max/aksapplz'

            # ReleaseNotes of this module
            ReleaseNotes = @'
## 1.5.0
- Application Gateway for Containers (enable_agc): delegated subnet + NSG per region (ALB Controller managed)
- Customer documentation site (MkDocs Material) published to GitHub Pages
- Versioned GitHub Releases with install.ps1 entrypoint and -Release pinning (default latest)
- Non-blocking newer-release check in Deploy-AKSLandingZone (-SkipUpdateCheck)
- Multi-region GA: Front Door / Traffic Manager, Fleet Manager, geo-replicated ACR

## 1.0.0
- Initial release
- Interactive wizard matching ALZ Deploy-Accelerator pattern
- Azure Verified Modules for AKS, VNet, ACR, Key Vault, App Gateway, Grafana
- Two-phase deployment: interactive config generation + execution
- OIDC/Federated credentials for GitHub Actions
- Self-hosted runner support
'@

            # Prerelease string — empty for a GA release.
            Prerelease = ''
        }
    }
}
