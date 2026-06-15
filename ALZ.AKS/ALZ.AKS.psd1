@{
    # Module manifest for ALZ.AKS
    # AKS Application Landing Zone Accelerator - PowerShell Module

    # Script module file associated with this manifest
    RootModule        = 'ALZ.AKS.psm1'

    # Version number of this module
    ModuleVersion     = '1.6.3'

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
## 1.6.3
- Fix: AKS backup storage account creation failed with "Key based authentication is not permitted on this storage account" (403). The storage account is AAD-only (shared_access_key_enabled = false), so the azurerm provider now uses Azure AD for storage data-plane operations (storage_use_azuread = true) and the backup container waits on a deployer Storage Blob Data Contributor role assignment.

## 1.6.2
- Fix: AKS backup storage account failed with SubnetsHaveNoServiceEndpointsConfigured. The AVM subnet object uses service_endpoints_with_location (not service_endpoints); the node-subnet Microsoft.Storage endpoint is now applied correctly and the storage account waits for the subnet update via depends_on.

## 1.6.1
- Azure Backup for AKS (enable_backup): complete managed solution (Backup Vault, hardened storage datastore, extension, Trusted Access, daily 30-day policy and backup instance) replacing the non-functional bare extension
- Fix: Grafana major version default 11 -> 12 (Azure retired v11 for the Standard SKU)

## 1.6.0
- enable_agc, -PatFromKeyVault, -OidcOnly, azd integration; feature-registration in bootstrap preflight

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
