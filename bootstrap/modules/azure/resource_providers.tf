# Microsoft.ContainerInstance must be registered on the bootstrap subscription.
# Registration is idempotent and best handled outside Terraform (the cmdlet runs
# `az provider register --namespace Microsoft.ContainerInstance` in preflight),
# because `azurerm_resource_provider_registration` errors if the RP is already
# registered at the subscription level by another tool.
