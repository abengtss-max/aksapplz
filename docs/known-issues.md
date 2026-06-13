# Known issues

This page summarizes what's GA versus tech preview. For the authoritative, continuously updated
list, see
[`KNOWN-ISSUES.md`](https://github.com/abengtss-max/aksapplz/blob/main/KNOWN-ISSUES.md) in the repo.

## GA — production ready

| Capability | Status |
|---|---|
| `standalone` topology (single + multi-region) | ✅ GA |
| `hub_and_spoke` topology (single region) | ✅ GA |
| Single-region baseline scenario | ✅ GA |
| Multi-region baseline (Front Door / Traffic Manager, Fleet Manager, geo-ACR) | ✅ GA |
| Application Gateway WAF v2 ingress | ✅ GA |
| Application Gateway for Containers (`enable_agc`) infrastructure | ✅ GA |
| Workload Identity, Azure RBAC, Defender for Containers | ✅ GA |

## Tech preview — not in the GA validation matrix

| Capability | Notes |
|---|---|
| `spoke` topology (peer to existing hub) | Available but not in the current validation matrix |
| Regulated scenarios (PCI-DSS 4.0.1) | Hardening is implemented; end-to-end validation is in progress |
| Multi-region `hub_and_spoke` | Tech preview |

!!! warning "Regulated state storage"
    A `403 AuthorizationFailure` on the Terraform state storage account during a regulated-scenario
    bootstrap is a known preview limitation. See the repo `KNOWN-ISSUES.md` for the current
    workaround.

## Reporting a problem

Found something not listed here? Please
[open an issue](https://github.com/abengtss-max/aksapplz/issues/new) with the scenario, topology,
and the command you ran.
