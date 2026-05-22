resource "random_string" "this" {
  length  = 4
  special = false
  upper   = false
  numeric = false
}

resource "time_static" "this" {}

locals {
  location_short_map = {
    swedencentral      = "sc"
    westeurope         = "weu"
    northeurope        = "neu"
    uksouth            = "uks"
    eastus             = "eus"
    eastus2            = "eus2"
    westus2            = "wus2"
    westus3            = "wus3"
    centralus          = "cus"
    germanywestcentral = "gwc"
  }

  azure_location_short = try(local.location_short_map[var.azure_location], substr(var.azure_location, 0, 3))

  formatted_postfix_number        = format("%03d", var.postfix_number)
  formatted_postfix_number_plus_1 = format("%03d", var.postfix_number + 1)

  random_string = random_string.this.result

  resource_names = merge({
    for key, value in var.resource_names : key => replace(replace(replace(replace(replace(replace(replace(replace(replace(value,
      "{{service_name}}", var.service_name),
      "{{service_name_short}}", substr(var.service_name, 0, 4)),
      "{{environment_name}}", var.environment_name),
      "{{environment_name_short}}", substr(var.environment_name, 0, 4)),
      "{{azure_location}}", var.azure_location),
      "{{azure_location_short}}", local.azure_location_short),
      "{{postfix_number}}", local.formatted_postfix_number),
      "{{postfix_number_plus_1}}", local.formatted_postfix_number_plus_1),
    "{{random_string}}", local.random_string)
    }, {
    unique_postfix       = local.random_string
    azure_location_short = local.azure_location_short
    time_stamp           = time_static.this.rfc3339
  })
}
