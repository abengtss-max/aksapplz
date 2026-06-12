# =============================================================================
# azd NO-OP Terraform shim — NOT the accelerator's real infrastructure.
# =============================================================================
# The ALZ.AKS accelerator does all of its provisioning from the interactive
# `Deploy-AKSLandingZone` wizard (launched by the azd `preprovision` hook in
# ../azure.yaml). This module deliberately creates ZERO Azure resources; it
# exists only so that `azd up` / `azd provision` has a valid Terraform root to
# "apply" after the wizard has finished, allowing the azd pipeline to complete
# without error.
#
# The accelerator's actual Terraform lives in:
#   - bootstrap/   (state backend, managed identities, GitHub repo)
#   - terraform/   (the AKS workload landing zone, run by the workload repo CD)
#
# Do not add real resources here. To provision the landing zone, use the
# wizard (or `azd up`, which calls it for you).
# =============================================================================

terraform {
  required_version = ">= 1.9"
}

# azd injects these as TF_VAR_* values from the azd environment. Declaring them
# (unused) keeps `terraform apply` free of "value for undeclared variable"
# warnings during the azd provision step.
variable "environment_name" {
  type        = string
  default     = ""
  description = "azd environment name (unused by this no-op shim)."
}

variable "location" {
  type        = string
  default     = ""
  description = "azd location (unused by this no-op shim)."
}

output "AZURE_LOCATION" {
  value       = var.location
  description = "Echoed back so azd can persist it; no resources are created."
}
