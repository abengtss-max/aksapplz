# Changelog

All notable changes to the `ALZ.AKS` PowerShell module are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - 2026-05-23

### Added
- **Standalone topology** option for the AKS landing zone.
  - New wizard prompt (Decision 2.5): choose `spoke` (peer to an existing ALZ hub, default) or `standalone` (no hub, NAT gateway egress only).
  - When `standalone` is selected, the wizard skips Decisions 3 (connectivity subscription) and 4 (hub VNet / hub firewall).
  - Workload Terraform now derives the internal `is_corp` flag from `hub_vnet_resource_id != ""`, so the route table, UDR, and spoke↔hub VNet peerings are only created when a hub is configured.
- New `topology` field in `config/inputs.yaml` (defaults to `spoke` for back-compat).
- Excel checklist: new row **Decision 0c — topology** with a dropdown (`spoke` / `standalone`).
- Topology coverage in [README.md](README.md), [ALZ.AKS/docs/deployment-checklist.md](ALZ.AKS/docs/deployment-checklist.md) and [ALZ.AKS/docs/scenarios-and-options.md](ALZ.AKS/docs/scenarios-and-options.md).
- Pre-flight validation:
  - Fails fast if `topology` is missing or not one of `spoke` / `standalone`.
  - Enforces all hub_* / `connectivity_subscription_id` fields are set when `topology: spoke`.
  - Auto-clears any leftover hub_* values and warns when `topology: standalone`.

### Changed
- `Deploy-AKSLandingZone` is the only exported cmdlet; the legacy `Invoke-AKSLandingZoneTerraform` name is no longer exported.
- When invoked without `-InputConfigPath`, `Deploy-AKSLandingZone` now runs the interactive wizard by default.

### Notes
- Older `inputs.yaml` files without a `topology` field are still accepted; pre-flight defaults them to `spoke` and emits a warning.

## [1.0.0] - 2026-05-22

### Added
- Initial public version. Single cmdlet `Deploy-AKSLandingZone` renders the `bootstrap/alz/github/` Terraform composition and applies it. End-to-end tested against a spoke landing zone in `swedencentral`.
