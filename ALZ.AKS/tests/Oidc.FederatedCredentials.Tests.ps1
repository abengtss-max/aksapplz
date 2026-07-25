<#
.SYNOPSIS
    OIDC federated-credential regression test for the bootstrap composition.

    Guards the v1.11.0 fix: GitHub is rolling out IMMUTABLE OIDC subject claims
    (repo:<org>@<orgId>/<repo>@<repoId>:environment:<env>). Repositories enrolled
    in that rollout no longer match the legacy name-based federated credential,
    which broke the workload pipeline with AADSTS700213.

    The bootstrap must therefore register BOTH subjects per environment. This
    test asserts the composition (bootstrap/alz/github) and the modules render:
      - legacy name-based FICs        (fc-github-plan / fc-github-apply)
      - immutable ID-based FICs       (fc-github-plan-immutable / fc-github-apply-immutable)
      - moved blocks that adopt the pre-1.11.0 credentials in place
      - the numeric-id outputs the immutable subject depends on

    Fast, offline (no Azure/GitHub calls). Runs terraform validate only when
    terraform is available.

    Run:
      Invoke-Pester -Path .\ALZ.AKS\tests\Oidc.FederatedCredentials.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $Script:RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $Script:RootMain   = Join-Path $Script:RepoRoot 'bootstrap\alz\github\main.tf'
    $Script:AzureMi    = Join-Path $Script:RepoRoot 'bootstrap\modules\azure\managed_identity.tf'
    $Script:AzureOut   = Join-Path $Script:RepoRoot 'bootstrap\modules\azure\outputs.tf'
    $Script:GithubOut  = Join-Path $Script:RepoRoot 'bootstrap\modules\github\outputs.tf'

    $Script:RootMainTxt  = Get-Content $Script:RootMain  -Raw
    $Script:AzureMiTxt   = Get-Content $Script:AzureMi   -Raw
    $Script:AzureOutTxt  = Get-Content $Script:AzureOut  -Raw
    $Script:GithubOutTxt = Get-Content $Script:GithubOut -Raw
}

Describe 'OIDC federated credentials — composition renders dual subjects' {

    It 'the composition root defines the federated credential resource' {
        $Script:RootMainTxt | Should -Match 'resource\s+"azurerm_federated_identity_credential"\s+"github"'
    }

    It 'renders a legacy name-based subject prefix (repo:<org>/<repo>)' {
        $Script:RootMainTxt | Should -Match 'repo:\$\{var\.github_organization_name\}/\$\{local\.workload_repository_name\}'
    }

    It 'renders an immutable ID-based subject prefix (repo:<org>@<orgId>/<repo>@<repoId>)' {
        # org@orgId/repo@repoId — must reference the numeric database ids
        $Script:RootMainTxt | Should -Match 'repo:\$\{var\.github_organization_name\}@\$\{module\.github\.organization_database_id\}'
        $Script:RootMainTxt | Should -Match '@\$\{module\.github\.repository_database_id\}'
    }

    It 'builds credentials for BOTH plan and apply environments' {
        $Script:RootMainTxt | Should -Match '\["plan",\s*"apply"\]'
        $Script:RootMainTxt | Should -Match 'environment:\$\{env\}'
    }

    It 'names the immutable variants distinctly (fc-github-<env>-immutable)' {
        $Script:RootMainTxt | Should -Match 'fc-github-\$\{env\}-immutable'
    }

    It 'preserves the pre-1.11.0 credentials via moved blocks (no destroy on upgrade)' {
        $Script:RootMainTxt | Should -Match 'moved\s*\{'
        $Script:RootMainTxt | Should -Match 'module\.azure\.azurerm_federated_identity_credential\.github\["plan"\]'
        $Script:RootMainTxt | Should -Match 'module\.azure\.azurerm_federated_identity_credential\.github\["apply"\]'
    }

    It 'uses the correct issuer and audience' {
        $Script:RootMainTxt | Should -Match 'https://token\.actions\.githubusercontent\.com'
        $Script:RootMainTxt | Should -Match 'api://AzureADTokenExchange'
    }
}

Describe 'OIDC federated credentials — module contract' {

    It 'the azure module no longer creates the federated credential itself' {
        $Script:AzureMiTxt | Should -Not -Match 'resource\s+"azurerm_federated_identity_credential"'
    }

    It 'the azure module exposes managed_identity_resource_ids (FIC parent_id)' {
        $Script:AzureOutTxt | Should -Match 'output\s+"managed_identity_resource_ids"'
    }

    It 'the azure module exposes identity_resource_group_name' {
        $Script:AzureOutTxt | Should -Match 'output\s+"identity_resource_group_name"'
    }

    It 'the github module exposes the numeric repository database id' {
        $Script:GithubOutTxt | Should -Match 'output\s+"repository_database_id"'
        $Script:GithubOutTxt | Should -Match 'github_repository\.this\.repo_id'
    }

    It 'the github module exposes the numeric organization database id' {
        $Script:GithubOutTxt | Should -Match 'output\s+"organization_database_id"'
        $Script:GithubOutTxt | Should -Match 'data\.github_organization\.this\.id'
    }
}

Describe 'OIDC federated credentials — terraform validate' {

    BeforeAll {
        $Script:HasTf = [bool](Get-Command terraform -ErrorAction SilentlyContinue)
        $Script:BootstrapDir = Join-Path $Script:RepoRoot 'bootstrap\alz\github'
    }

    It 'bootstrap/alz/github passes terraform validate' {
        if (-not $Script:HasTf) { Set-ItResult -Skipped -Because 'terraform is not on PATH'; return }

        Push-Location $Script:BootstrapDir
        try {
            & terraform init -backend=false -input=false -no-color 2>&1 | Out-Null
            $out  = & terraform validate -no-color 2>&1 | Out-String
            $code = $LASTEXITCODE
        } finally {
            Pop-Location
        }
        $code | Should -Be 0 -Because "terraform validate output:`n$out"
    }
}
