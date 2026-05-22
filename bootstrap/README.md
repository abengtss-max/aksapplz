# AKS Application Landing Zone — Bootstrap (Terraform)

This folder contains the Terraform composition applied by the `Deploy-AKSLandingZone` cmdlet (in `ALZ.AKS/ALZ.AKS.psm1`).

It is modelled on the official
[Azure Landing Zones Terraform Accelerator](https://github.com/Azure/alz-terraform-accelerator)
folder pattern (see `c:\Users\alibengtsson\accelerator\output\bootstrap\v7.2.1`
for the reference layout), adapted for the AKS Application Landing Zone scenario.

## Layout

```
bootstrap/
├── modules/
│   ├── resource_names/      Logic-only naming (locals + outputs)
│   ├── azure/               All Azure bootstrap resources, file-per-concern
│   └── github/              All GitHub bootstrap resources, file-per-concern
└── alz/
    └── github/              Root composition (init/plan/apply target)
```

## Provider strategy: AVM-first hybrid

* AVM modules (`Azure/avm-res-*`) for: storage account, user-assigned identity,
  container registry, virtual network, NAT gateway, public IP, private endpoint,
  private DNS zone.
* Bare `azurerm_*` / `azapi_*` for: AAD-only storage container, federated identity
  credentials, container groups (ACI runners), resource provider registration,
  role assignments at subscription scope.

## Usage

```pwsh
Import-Module .\ALZ.AKS\ALZ.AKS.psd1 -Force
Deploy-AKSLandingZone -InputConfigPath .\config\inputs.yaml -AutoApprove
```

The cmdlet:
1. Loads `config/inputs.yaml`.
2. Renders `bootstrap/alz/github/terraform.tfvars.json`.
3. Runs `terraform init` + `terraform apply` in `bootstrap/alz/github/`.
4. Migrates state from local to the bootstrap storage account.
