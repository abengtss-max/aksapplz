# -----------------------------------------------------------------------------
# Root - Global resource group for cross-region services
# Hosts the global load balancer (Front Door or Traffic Manager) and the
# Fleet Manager. Only created when one of those features is enabled.
# -----------------------------------------------------------------------------
resource "azurerm_resource_group" "global" {
  count = local.need_global_rg ? 1 : 0

  name     = local.resource_group_name_global
  location = var.location
  tags     = local.default_tags
}

# -----------------------------------------------------------------------------
# Root - Azure Front Door (global HTTP(S) load balancer) - Azure Verified Module
# Selected when global_lb_type = "front_door". Each region's Application Gateway
# public IP is wired in as an origin (priority-based: primary first).
# Ref: https://learn.microsoft.com/azure/architecture/reference-architectures/containers/aks-multi-region/aks-multi-cluster
# -----------------------------------------------------------------------------
module "front_door" {
  count = local.use_front_door && var.enable_app_gateway ? 1 : 0

  source  = "Azure/avm-res-cdn-profile/azurerm"
  version = "0.1.9"

  name                = local.frontdoor_profile_name
  location            = var.location
  resource_group_name = azurerm_resource_group.global[0].name
  sku                 = "Premium_AzureFrontDoor"
  tags                = local.default_tags

  front_door_endpoints = {
    primary_ep = {
      name = local.frontdoor_endpoint_name
    }
  }

  front_door_origin_groups = {
    aks = {
      name = "og-aks"
      health_probe = {
        hp = {
          interval_in_seconds = 30
          path                = "/"
          protocol            = "Http"
          request_type        = "HEAD"
        }
      }
      load_balancing = {
        lb = {
          additional_latency_in_milliseconds = 50
          sample_size                        = 4
          successful_samples_required        = 3
        }
      }
    }
  }

  # One origin per region, pointing at that region's App Gateway public IP.
  # Keys are derived statically from local.regions (known at plan time); only
  # the host_name is resolved after apply. Requires enable_app_gateway = true.
  front_door_origins = {
    for k, r in local.regions : "origin_${k}" => {
      name                           = "origin-${k}"
      origin_group_key               = "aks"
      host_name                      = module.region[k].app_gateway_public_ip_address
      certificate_name_check_enabled = false
      enabled                        = true
      http_port                      = 80
      https_port                     = 443
      priority                       = k == "primary" ? 1 : 2
      weight                         = 500
    }
  }

  front_door_routes = {
    aks = {
      name                   = "route-aks"
      origin_group_key       = "aks"
      origin_keys            = [for k, r in local.regions : "origin_${k}"]
      endpoint_key           = "primary_ep"
      forwarding_protocol    = "HttpOnly"
      supported_protocols    = ["Http", "Https"]
      patterns_to_match      = ["/*"]
      https_redirect_enabled = false
      link_to_default_domain = true
    }
  }
}
