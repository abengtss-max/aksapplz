# Security Policy

## Supported versions

| Version | Status |
|---------|--------|
| 1.4.x (preview / rc) | Active — security fixes only |
| 1.3.x | Active — security fixes only |
| < 1.3 | Unsupported |

## Reporting a vulnerability

Please **do not** open public GitHub issues for security findings.

Instead, email the maintainers privately (`SECURITY-CONTACT-PLACEHOLDER@yourdomain.tld`)
with:

- A description of the issue and its impact
- Steps to reproduce
- Affected version (e.g. `1.3.0`, commit SHA)
- Any suggested mitigation

We aim to acknowledge within **3 business days** and provide a fix or
mitigation within **30 days** for critical issues.

## Scope

In scope:
- Code in `ALZ.AKS/` (PowerShell module, Terraform templates, scenario tfvars)
- GitHub Actions workflows under `.github/workflows/`
- Bootstrap composition under `bootstrap/`

Out of scope:
- Vulnerabilities in upstream dependencies (Azure Verified Modules, Terraform
  providers, third-party Helm charts) — please report upstream
- Misconfigurations in your own deployment (network rules, RBAC, IAM)

## Hardening guidance

This accelerator ships with **dev-friendly defaults** for the `standalone`
topology (public API server, open authorized IP ranges, system DNS zone, NAT
gateway egress). For production, follow:

- [ALZ.AKS/docs/scenarios-and-options.md](ALZ.AKS/docs/scenarios-and-options.md) — security defaults & trade-offs
- [ALZ.AKS/docs/deployment-checklist.md](ALZ.AKS/docs/deployment-checklist.md) — pre-deployment review

## Disclosures

Past security advisories will be listed here once published.

## Security scanning

The accelerator and every repository it generates are scanned with three
complementary tools. The same policy runs locally, in the accelerator's CI, and
in each generated workload repo's CI, so results are deterministic and the gate
is never flaky.

### Scanners

| Layer | Tool | What it catches |
|-------|------|-----------------|
| PowerShell | PSScriptAnalyzer + [InjectionHunter](https://www.powershellgallery.com/packages/InjectionHunter) | Code-injection patterns, unsafe escaping, dangerous cmdlet usage |
| Infrastructure (Terraform) | [Checkov](https://www.checkov.io/) | Misconfigured Azure resources (WAF, NSG, firewall, identity, encryption) |
| Secrets | [detect-secrets](https://github.com/Yelp/detect-secrets) | Hard-coded credentials, tokens, keys |

### Run it locally

```powershell
pwsh ./tools/Invoke-SecurityScan.ps1          # advisory PowerShell, gating IaC + secrets
pwsh ./tools/Invoke-SecurityScan.ps1 -StrictPS # also gate on PowerShell warnings
```

Prerequisites: `Install-Module PSScriptAnalyzer, InjectionHunter` and
`pip install checkov detect-secrets`.

### In CI

- **Accelerator** — [.github/workflows/static-analysis.yml](.github/workflows/static-analysis.yml)
  runs all three scanners on every PR touching PowerShell / Terraform / bootstrap
  code and uploads Checkov SARIF to GitHub code scanning.
- **Generated workload repos** — the reusable `ci-template.yaml` includes a
  `security` job that runs Checkov against the workload's Terraform using the
  shipped `.checkov.yaml`, so customer PRs are gated with the identical policy.

### Triage policy (`.checkov.yaml`)

All Checkov suppressions live in [.checkov.yaml](.checkov.yaml), each with an
inline justification. Every entry is a reviewed **false positive** or an
explicitly **accepted, by-design** control — there are no real, unaddressed
findings.

| Check | Disposition | Rationale |
|-------|-------------|-----------|
| `CKV_TF_1` | False positive | Modules are version-pinned registry AVMs + local path modules; no git sources |
| `CKV_AZURE_120` | False positive | WAF **is** enabled (WAF_v2 SKU + dedicated `firewall_policy_id`) |
| `CKV_AZURE_217` / `CKV_AZURE_218` | By design | Placeholder HTTP listener; AGIC injects real HTTPS listeners/certs at runtime |
| `CKV_AZURE_160` | By design | App Gateway v2 needs port 80 for client traffic / HTTP→HTTPS redirect; pod traffic is mTLS via Istio |
| `CKV_AZURE_235` | False positive | Runner token uses `secure_environment_variables`; only non-sensitive values are plaintext |
| `CKV_AZURE_216` | False positive | `threat_intelligence_mode = "Deny"` set on the firewall **policy** (required for policy-based firewalls) |
| `CKV_AZURE_220` | Accepted | IDPS is Premium-tier only; hub firewall defaults to Standard (threat intel set to Deny instead) |
| `CKV_GIT_3` | False positive | Vulnerability alerts enabled via dedicated `github_repository_vulnerability_alerts` resource |
| `CKV_GIT_5` | By design | Single-approver model for small platform teams; raise in `github/repository.tf` as needed |
| `CKV_GIT_6` | By design | Bootstrap pushes unsigned commits via automation; signed-commit enforcement would break provisioning |

Secret-scan false positives (GitHub Actions `secrets: inherit` directives) are
recorded in [.secrets.baseline](.secrets.baseline). PowerShell injection
warnings are accepted dynamic-property-name patterns over controlled,
hard-coded inputs (see code review notes in the relevant functions).
