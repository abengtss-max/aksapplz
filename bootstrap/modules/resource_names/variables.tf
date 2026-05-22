variable "azure_location" {
  description = "Azure region where bootstrap resources will be deployed (e.g. 'swedencentral')."
  type        = string
}

variable "environment_name" {
  description = "Environment name token used in resource naming (e.g. 'prod')."
  type        = string
}

variable "service_name" {
  description = "Service name token used in resource naming (e.g. 'aksapplz')."
  type        = string
}

variable "postfix_number" {
  description = "Numeric postfix appended to resource names for uniqueness."
  type        = number
  default     = 1
}

variable "resource_names" {
  description = <<-EOT
    Map of resource-name templates. Tokens are substituted at render time:
      {{service_name}}, {{service_name_short}},
      {{environment_name}}, {{environment_name_short}},
      {{azure_location}}, {{azure_location_short}},
      {{postfix_number}}, {{postfix_number_plus_1}},
      {{random_string}}
  EOT
  type        = map(string)
}
