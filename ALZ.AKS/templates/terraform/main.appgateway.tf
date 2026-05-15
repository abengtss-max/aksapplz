# -----------------------------------------------------------------------------
# Application Gateway with WAF v2
# Best Practices: WAF_v2 SKU, OWASP 3.2, Autoscaling, Diagnostic Logging
# -----------------------------------------------------------------------------

# Public IP for Application Gateway
resource "azurerm_public_ip" "app_gateway" {
  count = var.enable_app_gateway ? 1 : 0

  name                = "pip-${local.app_gateway_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.availability_zones
  tags                = local.default_tags
}

# WAF Policy
resource "azurerm_web_application_firewall_policy" "main" {
  count = var.enable_app_gateway ? 1 : 0

  name                = local.waf_policy_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.default_tags

  policy_settings {
    enabled                     = true
    mode                        = var.waf_mode # "Prevention" for production
    request_body_check          = true
    file_upload_limit_in_mb     = 100
    max_request_body_size_in_kb = 128
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }

    managed_rule_set {
      type    = "Microsoft_BotManagerRuleSet"
      version = "1.0"
    }
  }
}

# Application Gateway
resource "azurerm_application_gateway" "main" {
  count = var.enable_app_gateway ? 1 : 0

  name                = local.app_gateway_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.default_tags
  zones               = var.availability_zones
  enable_http2        = true
  firewall_policy_id  = azurerm_web_application_firewall_policy.main[0].id

  sku {
    name = "WAF_v2"
    tier = "WAF_v2"
  }

  autoscale_configuration {
    min_capacity = var.app_gateway_min_capacity
    max_capacity = var.app_gateway_max_capacity
  }

  gateway_ip_configuration {
    name      = "gateway-ip-config"
    subnet_id = module.spoke_vnet.subnets["app_gateway"].resource_id
  }

  frontend_ip_configuration {
    name                 = "frontend-ip-public"
    public_ip_address_id = azurerm_public_ip.app_gateway[0].id
  }

  frontend_port {
    name = "https"
    port = 443
  }

  frontend_port {
    name = "http"
    port = 80
  }

  # Default backend pool (will be configured by AGIC or manually)
  backend_address_pool {
    name = "default-backend-pool"
  }

  backend_http_settings {
    name                  = "default-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 30
    probe_name            = "default-health-probe"
  }

  probe {
    name                = "default-health-probe"
    protocol            = "Http"
    path                = "/healthz"
    host                = "127.0.0.1"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }

  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "frontend-ip-public"
    frontend_port_name             = "http"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "default-routing-rule"
    priority                   = 100
    rule_type                  = "Basic"
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "default-backend-pool"
    backend_http_settings_name = "default-http-settings"
  }

  # Ignore changes made by AGIC (Application Gateway Ingress Controller)
  lifecycle {
    ignore_changes = [
      backend_address_pool,
      backend_http_settings,
      frontend_port,
      http_listener,
      probe,
      request_routing_rule,
      redirect_configuration,
      ssl_certificate,
      url_path_map,
    ]
  }
}

# Diagnostic settings for Application Gateway
resource "azurerm_monitor_diagnostic_setting" "app_gateway" {
  count = var.enable_app_gateway && var.enable_diagnostic_settings ? 1 : 0

  name                       = "diag-${local.app_gateway_name}"
  target_resource_id         = azurerm_application_gateway.main[0].id
  log_analytics_workspace_id = module.log_analytics.resource_id

  enabled_log {
    category = "ApplicationGatewayAccessLog"
  }

  enabled_log {
    category = "ApplicationGatewayPerformanceLog"
  }

  enabled_log {
    category = "ApplicationGatewayFirewallLog"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
