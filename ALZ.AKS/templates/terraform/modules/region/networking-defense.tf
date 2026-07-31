# -----------------------------------------------------------------------------
# Region module - Network defense-in-depth (#23)
#
# Two independent, opt-in (default off) controls so they can be enabled and
# live-validated without risk to a running cluster:
#
#   1. enable_node_nsg_rules  - explicit inbound allow/deny baseline on the
#      AKS node-pool NSGs. Only Virtual Network and Azure Load Balancer inbound
#      is allowed; everything else is explicitly denied. Node-to-node / pod
#      traffic (VirtualNetwork) and health probes (AzureLoadBalancer) are
#      preserved, so required AKS communication keeps working. Outbound is left
#      at the platform defaults (AKS needs broad egress). Cross-pool
#      segmentation is intentionally NOT applied because overlay pod traffic is
#      node-to-node inside the VNet.
#
#   2. enable_nsg_flow_logs   - Network Watcher NSG flow logs for the node,
#      API-server, App Gateway, private-endpoint, AGC and jumpbox NSGs, written
#      to a dedicated storage account with Traffic Analytics into the region
#      Log Analytics workspace. Also gated on enable_diagnostic_settings.
# -----------------------------------------------------------------------------

variable "enable_node_nsg_rules" {
  type    = bool
  default = false
}

variable "enable_nsg_flow_logs" {
  type    = bool
  default = false
}

# --- Part 1: explicit node-pool NSG rules -----------------------------------
# The node NSGs (aks_system_nodes / aks_user_nodes) carry no inline rules, so
# standalone rule resources are safe to attach here without conflicts.

locals {
  node_nsgs = {
    system = azurerm_network_security_group.aks_system_nodes.name
    user   = azurerm_network_security_group.aks_user_nodes.name
  }
}

resource "azurerm_network_security_rule" "node_allow_vnet_inbound" {
  for_each = var.enable_node_nsg_rules ? local.node_nsgs : {}

  name                        = "AllowVnetInbound"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "VirtualNetwork"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = each.value
}

resource "azurerm_network_security_rule" "node_allow_lb_inbound" {
  for_each = var.enable_node_nsg_rules ? local.node_nsgs : {}

  name                        = "AllowAzureLoadBalancerInbound"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "AzureLoadBalancer"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = each.value
}

resource "azurerm_network_security_rule" "node_deny_all_inbound" {
  for_each = var.enable_node_nsg_rules ? local.node_nsgs : {}

  name                        = "DenyAllInbound"
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = each.value
}

# --- Part 2: NSG flow logs + Traffic Analytics ------------------------------

locals {
  enable_flow_logs = var.enable_nsg_flow_logs && var.enable_diagnostic_settings

  # Storage account name: <=24 lowercase alphanumeric, deterministic.
  flow_log_sa_name = lower(substr("stfl${substr(sha256(local.name_prefix), 0, 20)}", 0, 24))

  # NSGs to onboard (conditionally include the ones that are created).
  flow_log_nsgs = merge(
    {
      "aks-system" = azurerm_network_security_group.aks_system_nodes.id
      "aks-user"   = azurerm_network_security_group.aks_user_nodes.id
      "aks-api"    = azurerm_network_security_group.aks_api_server.id
    },
    var.enable_app_gateway ? { "appgw" = azurerm_network_security_group.app_gateway[0].id } : {},
    local.use_private_endpoints ? { "pe" = azurerm_network_security_group.private_endpoints[0].id } : {},
    var.enable_agc ? { "agc" = azurerm_network_security_group.agc[0].id } : {},
    local.enable_jumpbox ? { "jumpbox" = azurerm_network_security_group.jumpbox[0].id } : {},
  )
}

resource "azurerm_network_watcher" "main" {
  count = local.enable_flow_logs ? 1 : 0

  name                = "nw-${local.name_prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.default_tags
}

resource "azurerm_storage_account" "flow_logs" {
  count = local.enable_flow_logs ? 1 : 0

  name                            = local.flow_log_sa_name
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  tags                            = local.default_tags
}

resource "azurerm_network_watcher_flow_log" "nsg" {
  for_each = local.enable_flow_logs ? local.flow_log_nsgs : {}

  name                      = "fl-${each.key}-${local.name_prefix}"
  network_watcher_name      = azurerm_network_watcher.main[0].name
  resource_group_name       = azurerm_resource_group.main.name
  network_security_group_id = each.value
  storage_account_id        = azurerm_storage_account.flow_logs[0].id
  enabled                   = true

  retention_policy {
    enabled = true
    days    = 30
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = module.log_analytics.resource.workspace_id
    workspace_region      = azurerm_resource_group.main.location
    workspace_resource_id = module.log_analytics.resource_id
    interval_in_minutes   = 10
  }
}
