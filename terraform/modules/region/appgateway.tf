# -----------------------------------------------------------------------------
# Region module - Application Gateway with WAF v2
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
  # A public DNS label is required when this IP is used as an Azure endpoint
  # behind Traffic Manager. Left null for single-region deployments so existing
  # public IPs are unchanged.
  domain_name_label = var.assign_public_dns_label ? var.public_dns_label : null
  tags              = local.default_tags

  lifecycle {
    # The provider reports a spurious `ip_tags` diff on refresh which would
    # otherwise force replacement of this public IP while it is still attached
    # to the Application Gateway (delete fails with a 400). We never set
    # ip_tags, so it is safe to ignore drift on it and keep re-applies idempotent.
    ignore_changes = [ip_tags]
  }
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
  http2_enabled       = true
  firewall_policy_id  = azurerm_web_application_firewall_policy.main[0].id

  sku {
    name = "WAF_v2"
    tier = "WAF_v2"
  }

  autoscale_configuration {
    min_capacity = var.app_gateway_min_capacity
    max_capacity = var.app_gateway_max_capacity
  }

  # Enforce a modern TLS floor on the edge. The default predefined policy
  # requires a minimum of TLS 1.2 (PCI-DSS 4.0.1 Req 4.1 / Microsoft strong
  # crypto). This is an App Gateway resource property, not Azure Policy.
  ssl_policy {
    policy_type = "Predefined"
    policy_name = var.appgw_ssl_policy_name
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

  # Backend pool for the in-cluster ingress controller, reached over its internal
  # load balancer private IP. Left empty here: for ingress_controller = "istio"
  # the CD pipeline discovers the managed Istio internal gateway's LB IP and
  # updates this pool out of band (Terraform ignores changes to its addresses -
  # see lifecycle below); for "manual" the customer wires their own controller's
  # IP. An optional seed IP can be supplied via ingress_backend_ip.
  backend_address_pool {
    name         = local.appgw_backend_pool_name
    ip_addresses = var.ingress_backend_ip != "" ? [var.ingress_backend_ip] : null
  }

  backend_http_settings {
    name                  = "ingress-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 30
    probe_name            = "ingress-health-probe"
  }

  probe {
    name                                      = "ingress-health-probe"
    protocol                                  = "Http"
    path                                      = var.ingress_health_probe_path
    pick_host_name_from_backend_http_settings = false
    host                                      = "127.0.0.1"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    match {
      # Any HTTP response proves the ingress controller is reachable. The
      # controller returns 404 for unknown hosts until real Ingress/Gateway
      # resources exist, which must still be treated as healthy.
      status_code = ["200-499"]
    }
  }

  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "frontend-ip-public"
    frontend_port_name             = "http"
    protocol                       = "Http"
  }

  # --- TLS (optional): activated when a Key Vault certificate secret is set. --
  # The gateway reads the certificate with the AKS user-assigned identity, which
  # already holds Key Vault Secrets User on this region's vault.
  dynamic "identity" {
    for_each = local.appgw_tls_enabled ? [1] : []
    content {
      type         = "UserAssigned"
      identity_ids = [azurerm_user_assigned_identity.aks.id]
    }
  }

  dynamic "ssl_certificate" {
    for_each = local.appgw_tls_enabled ? [1] : []
    content {
      name                = "appgw-tls-cert"
      key_vault_secret_id = local.appgw_tls_secret_id
    }
  }

  dynamic "http_listener" {
    for_each = local.appgw_tls_enabled ? [1] : []
    content {
      name                           = "https-listener"
      frontend_ip_configuration_name = "frontend-ip-public"
      frontend_port_name             = "https"
      protocol                       = "Https"
      ssl_certificate_name           = "appgw-tls-cert"
    }
  }

  dynamic "redirect_configuration" {
    for_each = local.appgw_tls_enabled && !var.appgw_https_only ? [1] : []
    content {
      name                 = "http-to-https"
      redirect_type        = "Permanent"
      target_listener_name = "https-listener"
      include_path         = true
      include_query_string = true
    }
  }

  # TLS on: HTTPS serves the backend; HTTP:80 permanently redirects to HTTPS.
  dynamic "request_routing_rule" {
    for_each = local.appgw_tls_enabled ? [1] : []
    content {
      name                       = "https-routing-rule"
      priority                   = 100
      rule_type                  = "Basic"
      http_listener_name         = "https-listener"
      backend_address_pool_name  = local.appgw_backend_pool_name
      backend_http_settings_name = "ingress-http-settings"
    }
  }

  dynamic "request_routing_rule" {
    for_each = local.appgw_tls_enabled && !var.appgw_https_only ? [1] : []
    content {
      name                        = "http-redirect-rule"
      priority                    = 110
      rule_type                   = "Basic"
      http_listener_name          = "http-listener"
      redirect_configuration_name = "http-to-https"
    }
  }

  # TLS off: HTTP:80 serves the backend directly.
  dynamic "request_routing_rule" {
    for_each = local.appgw_tls_enabled ? [] : [1]
    content {
      name                       = "http-routing-rule"
      priority                   = 100
      rule_type                  = "Basic"
      http_listener_name         = "http-listener"
      backend_address_pool_name  = local.appgw_backend_pool_name
      backend_http_settings_name = "ingress-http-settings"
    }
  }

  lifecycle {
    # The backend pool addresses are managed out of band by the CD pipeline,
    # which discovers the internal ingress LB IP after the controller is
    # deployed. Everything else (listeners, routing, TLS, probe) is owned by
    # Terraform.
    ignore_changes = [
      backend_address_pool,
    ]

    # Production must terminate TLS with a customer-provided (trusted) Key Vault
    # certificate. Microsoft guidance states production workloads must never use
    # self-signed certificates, and PCI-DSS 4.0.1 Req 4.1 requires strong,
    # trusted TLS for data in transit.
    precondition {
      condition     = !(local.appgw_is_production && local.appgw_tls_mode_effective != "keyvault")
      error_message = "Production Application Gateway requires a customer-provided Key Vault certificate. Set appgw_tls_key_vault_secret_id (mode 'keyvault'). Self-signed or disabled TLS is not permitted in production (Microsoft: production workloads must never use self-signed certificates; PCI-DSS 4.0.1 Req 4.1 requires strong, trusted TLS)."
    }
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
