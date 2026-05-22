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
  resource_group_name    = "rg-${local.name_prefix}"
  vnet_name              = "vnet-${local.name_prefix}"
  aks_name               = "aks-${local.name_prefix}"
  acr_name               = replace("acr${var.workload_name}${var.environment}${local.loc_short}", "-", "")
  key_vault_name         = "kv-${local.name_prefix}"
  app_gateway_name       = "agw-${local.name_prefix}"
  waf_policy_name        = "waf-${local.name_prefix}"
  log_analytics_name     = "log-${local.name_prefix}"
  monitor_workspace_name = "amon-${local.name_prefix}"
  grafana_name           = "grf-${local.name_prefix}"
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
