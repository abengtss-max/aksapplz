# -----------------------------------------------------------------------------
# AKS Application Landing Zone - Local Values
# -----------------------------------------------------------------------------

locals {
  # Location shortcodes for naming
  location_short = {
    swedencentral = "swc"
    westeurope    = "weu"
    northeurope   = "neu"
    eastus        = "eus"
    eastus2       = "eu2"
  }

  loc_short = lookup(local.location_short, var.location, substr(var.location, 0, 3))

  # Naming convention: {resource_type}-{workload_name}-{environment}-{location_short}
  name_prefix = "${var.workload_name}-${var.environment}-${local.loc_short}"

  # Resource names
  # NOTE: Resources with short Azure-imposed name limits use a length-safe pattern:
  #   <prefix>-<truncated name_prefix><3-char sha256(name_prefix)>
  # See https://learn.microsoft.com/azure/azure-resource-manager/management/resource-name-rules
  resource_group_name    = "rg-${local.name_prefix}"
  vnet_name              = "vnet-${local.name_prefix}"
  aks_name               = "aks-${local.name_prefix}"
  acr_name               = replace("acr${var.workload_name}${var.environment}${local.loc_short}", "-", "")
  # Key Vault max length = 24. Truncate + append 3-char deterministic hash when over.
  _kv_full               = "kv-${local.name_prefix}"
  key_vault_name         = length(local._kv_full) <= 24 ? local._kv_full : "kv-${substr(local.name_prefix, 0, 17)}${substr(sha256(local.name_prefix), 0, 3)}"
  app_gateway_name       = "agw-${local.name_prefix}"
  waf_policy_name        = "waf-${local.name_prefix}"
  log_analytics_name     = "log-${local.name_prefix}"
  monitor_workspace_name = "amon-${local.name_prefix}"
  grafana_name           = length("grf-${local.name_prefix}") <= 23 ? "grf-${local.name_prefix}" : "grf-${substr(local.name_prefix, 0, 16)}${substr(sha256(local.name_prefix), 0, 3)}"
  # Data Collection Endpoint max length = 44; DCR max length = 64.
  # "dce-prometheus-" prefix is 15 chars, leaving 29 for name_prefix before hashing.
  _dce_full              = "dce-prometheus-${local.name_prefix}"
  dce_prometheus_name    = length(local._dce_full) <= 44 ? local._dce_full : "dce-prometheus-${substr(local.name_prefix, 0, 26)}${substr(sha256(local.name_prefix), 0, 3)}"
  _dcr_full              = "dcr-prometheus-${local.name_prefix}"
  dcr_prometheus_name    = length(local._dcr_full) <= 64 ? local._dcr_full : "dcr-prometheus-${substr(local.name_prefix, 0, 46)}${substr(sha256(local.name_prefix), 0, 3)}"
  route_table_name       = "rt-${local.name_prefix}"
  nsg_appgw_name         = "nsg-agw-${local.name_prefix}"
  nsg_pe_name            = "nsg-pe-${local.name_prefix}"
  managed_identity_name  = "id-${local.name_prefix}"
  nsg_aks_system_name    = "nsg-aks-system-${local.name_prefix}"
  nsg_aks_user_name      = "nsg-aks-user-${local.name_prefix}"

  # Subnet configurations — system and user node pools on separate subnets (AKS baseline best practice)
  subnets = {
    aks_system_nodes = {
      name             = "snet-aks-system-${local.name_prefix}"
      address_prefixes = [var.subnet_address_prefixes.aks_system_nodes]
    }
    aks_user_nodes = {
      name             = "snet-aks-user-${local.name_prefix}"
      address_prefixes = [var.subnet_address_prefixes.aks_user_nodes]
    }
    aks_api_server = {
      name             = "snet-aks-apiserver-${local.name_prefix}"
      address_prefixes = [var.subnet_address_prefixes.aks_api_server]
      delegation = {
        aks = {
          name = "Microsoft.ContainerService/managedClusters"
          actions = [
            "Microsoft.Network/virtualNetworks/subnets/join/action"
          ]
        }
      }
    }
    app_gateway = {
      name             = "snet-agw-${local.name_prefix}"
      address_prefixes = [var.subnet_address_prefixes.app_gateway]
    }
    private_endpoints = {
      name             = "snet-pe-${local.name_prefix}"
      address_prefixes = [var.subnet_address_prefixes.private_endpoints]
    }
    ingress = {
      name             = "snet-ingress-${local.name_prefix}"
      address_prefixes = [var.subnet_address_prefixes.ingress]
    }
  }

  # Tags
  default_tags = merge(var.tags, {
    workload    = var.workload_name
    environment = var.environment
    managed_by  = "terraform"
    project     = "aksapplz"
  })

  # Hub firewall private IP for UDR (only used in Corp)
  hub_firewall_private_ip = var.hub_firewall_private_ip != "" ? var.hub_firewall_private_ip : "0.0.0.0"

  # DNS zone names for private endpoints
  private_dns_zones = {
    acr      = "privatelink.azurecr.io"
    keyvault = "privatelink.vaultcore.azure.net"
    aks      = "privatelink.${var.location}.azmk8s.io"
  }
}
