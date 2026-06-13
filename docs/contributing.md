# Contributing

!!! info "This site is for users of the accelerator."
    If you're here to **deploy** AKS, head to the **[Quickstart](get-started/quickstart.md)**.
    The rest of this page is for **developers** who want to contribute to the accelerator itself.

The source code, tests, and contribution workflow live in the GitHub repository:

[:octicons-mark-github-16: github.com/abengtss-max/aksapplz](https://github.com/abengtss-max/aksapplz)

## Repository layout

| Path | Purpose |
|---|---|
| `ALZ.AKS/` | The PowerShell module (`Deploy-AKSLandingZone`) and the embedded Terraform/workflow templates. The published release. |
| `terraform/` | The canonical Terraform composition (root + region module). |
| `bootstrap/` | Legacy standalone bootstrap script (superseded by the module). |
| `docs/` | This documentation site (MkDocs Material). |
| `config/` | Example `inputs.*.yaml` and `*.tfvars` per scenario. |
| `.github/workflows/` | CI, scenario tests, docs deploy, and release automation. |

## Local development

```powershell
git clone https://github.com/abengtss-max/aksapplz.git
cd aksapplz
Import-Module .\ALZ.AKS\ALZ.AKS.psd1 -Force
```

Run the Terraform validation and Pester tests as described in
[`TEST.md`](https://github.com/abengtss-max/aksapplz/blob/main/TEST.md).

## Previewing the docs site

```bash
pip install -r requirements-docs.txt
mkdocs serve
```

Then open <http://127.0.0.1:8000>. The site auto-deploys to GitHub Pages on merge to `main`.

## Cutting a release

1. Bump `ModuleVersion` in `ALZ.AKS/ALZ.AKS.psd1`.
2. Tag the commit `vX.Y.Z` and push the tag.
3. The release workflow validates the version, packages the module, and publishes a GitHub Release.

See [Releases & versions](releases.md) for how customers consume releases.

## Code of conduct & security

- [Code of Conduct](https://github.com/abengtss-max/aksapplz/blob/main/CODE_OF_CONDUCT.md)
- [Security policy](https://github.com/abengtss-max/aksapplz/blob/main/SECURITY.md)
