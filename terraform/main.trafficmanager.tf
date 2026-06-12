# -----------------------------------------------------------------------------
# Root - Azure Traffic Manager (global DNS-based load balancer) - AVM
# Selected when global_lb_type = "traffic_manager". Uses Priority routing
# (primary first, secondary as failover). Each region's App Gateway public IP
# is wired in as an Azure endpoint (requires a DNS label on the public IP).
# Ref: https://learn.microsoft.com/azure/architecture/reference-architectures/containers/aks-multi-region/aks-multi-cluster
# -----------------------------------------------------------------------------
module "traffic_manager" {
  count = local.use_traffic_mgr && var.enable_app_gateway ? 1 : 0

  source  = "Azure/avm-res-network-trafficmanagerprofile/azurerm"
  version = "0.1.0"

  name                   = local.traffic_manager_name
  resource_group_name    = azurerm_resource_group.global[0].name
  traffic_routing_method = "Priority"
  tags                   = local.default_tags

  dns_config = {
    relative_name = local.traffic_manager_dns_name
    ttl           = 60
  }

  monitor_config = {
    protocol = "HTTP"
    port     = 80
    path     = "/"
  }

  # One endpoint per region (static keys from local.regions; target IP resolved
  # after apply). Requires enable_app_gateway = true for a public IP target.
  azure_endpoints = {
    for k, r in local.regions : k => {
      name               = "ep-${k}"
      target_resource_id = module.region[k].app_gateway_public_ip_id
      enabled            = true
      priority           = k == "primary" ? 1 : 2
      weight             = 100
    }
  }
}
