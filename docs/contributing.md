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

## Live-validating a feature branch

Before a feature branch is merged and released, validate it with a **real deployment** from the
branch. The critical gotcha: `Deploy-AKSLandingZone` comes from the `ALZ.AKS` **module**, and the
wizard renders Terraform from the module's *embedded* `ALZ.AKS/templates/terraform` — **not** from
the repo's top-level `terraform/`. The public `install.ps1` installs the module from a published
**GitHub Release** (cached under `~/.alz-aks/<version>/`), which tracks *releases, not your branch*.
So switching the git branch alone changes nothing unless the **imported module is the branch
checkout**.

Follow these steps for any feature branch.

### 1. Check out the branch

```powershell
cd <repo-root>
git switch <feature-branch>
git pull
git log --oneline -1          # confirm you're on the expected commit
```

### 2. Import the module from the checkout (not a cached release)

```powershell
Remove-Module ALZ.AKS -Force -ErrorAction SilentlyContinue
Import-Module .\ALZ.AKS\ALZ.AKS.psd1 -Force
```

### 3. Prove you're running the branch module

```powershell
# Must resolve to your checkout, NOT ~/.alz-aks/<version>/
(Get-Command Deploy-AKSLandingZone).Module.Path

# Spot-check that the branch's change is present in the EMBEDDED template
# (adjust the pattern/file to whatever the branch changes)
Select-String '<expected-change>' .\ALZ.AKS\templates\terraform\...
```

If the module path points at `~/.alz-aks/...`, you are still on a released copy — repeat step 2.

!!! warning "Validate the embedded template, not just `terraform/`"
    A branch change only reaches a real deploy if it is mirrored into
    `ALZ.AKS/templates/terraform/`. The top-level `terraform/` tree is the canonical composition,
    but the wizard deploys the embedded copy. Always grep the `ALZ.AKS/templates/terraform/` path
    in step 3.

### 4. Deploy (bootstrap → CD)

```powershell
Deploy-AKSLandingZone -InputConfigPath .\config\inputs.yaml
```

`Deploy-AKSLandingZone` provisions the **bootstrap** layer (Terraform state storage + the CI/CD
managed identity), renders the embedded templates into the workload repo, and triggers the CD
pipeline. The bootstrap resource groups (`-state-`, `-identity-`) are *not* the workload resource
groups — those are created by the CD Terraform apply.

### 5. Validate at the CD **Plan** stage (before anything is created)

The CD pipeline is a two-stage gate: a **Terraform Plan** job, then an **Apply** job bound to a
protected GitHub Environment. Read the plan output *before* approving:

```powershell
gh run list --repo <owner>/<workload-repo> --limit 5
gh run view <runId> --repo <owner>/<workload-repo> --log | Select-String "<expected-plan-change>"
```

Optionally confirm the workload repo received the branch's Terraform:

```powershell
gh api repos/<owner>/<workload-repo>/contents/terraform/<path> --jq '.content' |
  % { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) } |
  Select-String '<expected-change>'
```

### 6. Approve Apply, then confirm live

```powershell
az group list --query "[?starts_with(name,'rg-<prefix>')].name" -o tsv
az resource list -g <rg> --query "[].{n:name,t:type}" -o table
```

Then run the branch-specific functional checks (cluster health, the feature under test, teardown
behaviour). Record the result on the tracking issue so the branch has an auditable validation
before merge.

### 7. Clean up

```powershell
# Tear down the test environment when done
Deploy-AKSLandingZone -InputConfigPath .\config\inputs.yaml -Action destroy -AutoApprove
```

Only after a branch passes this live validation should it be merged and released.

## Cutting a release

1. Bump `ModuleVersion` in `ALZ.AKS/ALZ.AKS.psd1`.
2. Tag the commit `vX.Y.Z` and push the tag.
3. The release workflow validates the version, packages the module, and publishes a GitHub Release.

See [Releases & versions](releases.md) for how customers consume releases.

## Code of conduct & security

- [Code of Conduct](https://github.com/abengtss-max/aksapplz/blob/main/CODE_OF_CONDUCT.md)
- [Security policy](https://github.com/abengtss-max/aksapplz/blob/main/SECURITY.md)
