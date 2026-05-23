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
