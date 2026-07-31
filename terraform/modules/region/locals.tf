# -----------------------------------------------------------------------------
# Region module - local values (naming + derived settings)
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

  env_short = var.environment_short != "" ? var.environment_short : var.environment

  # Naming convention: {resource_type}-{workload_name}-{env_short}-{location_short}
  name_prefix = "${var.workload_name}-${local.env_short}-${local.loc_short}"

  resource_group_name = "rg-${local.name_prefix}"
  vnet_name           = "vnet-${local.name_prefix}"
  aks_name            = "aks-${local.name_prefix}"
  # Key Vault names are globally unique across Azure. A 3-char random suffix
  # (see random_string.kv_suffix below) is generated on the first apply and
  # preserved in state, so re-plans yield the same name. On a fresh apply
  # after `terraform destroy` (or state loss) a NEW suffix is generated,
  # which is required in policy-governed subscriptions where soft-deleted
  # vaults cannot be purged manually and would otherwise block reuse of a
  # deterministic name for up to 90 days. Cap prefix at 17 chars so
  # `kv-{<=17}-{3}` always fits the 24-char KV name limit.
  _kv_prefix              = length(local.name_prefix) <= 17 ? local.name_prefix : substr(local.name_prefix, 0, 17)
  key_vault_name          = "kv-${local._kv_prefix}-${random_string.kv_suffix.result}"
  app_gateway_name        = "agw-${local.name_prefix}"
  appgw_backend_pool_name = "ingress-backend-pool"
  # --- Application Gateway edge TLS -------------------------------------------
  # A supplied Key Vault secret ID always means "keyvault" (customer-provided
  # certificate) for backward compatibility; otherwise the selected
  # var.appgw_tls_mode applies ("self_signed" | "keyvault" | "disabled").
  appgw_tls_mode_effective = var.appgw_tls_key_vault_secret_id != "" ? "keyvault" : var.appgw_tls_mode
  appgw_self_signed_tls    = var.enable_app_gateway && local.appgw_tls_mode_effective == "self_signed"
  appgw_tls_enabled        = var.enable_app_gateway && contains(["keyvault", "self_signed"], local.appgw_tls_mode_effective)
  # Certificate the HTTPS listener reads: the Key Vault-generated self-signed
  # cert (versionless, so App Gateway auto-picks up renewals) or the customer
  # certificate secret. Empty string keeps an HTTP-only listener.
  appgw_tls_secret_id = local.appgw_self_signed_tls ? try(azurerm_key_vault_certificate.appgw_self_signed[0].versionless_secret_id, "") : var.appgw_tls_key_vault_secret_id
  # Production must use a customer-provided certificate: Microsoft guidance says
  # production workloads must never use self-signed certs, and PCI-DSS 4.0.1
  # Req 4.1 requires strong, trusted TLS for data in transit.
  appgw_is_production = contains(["prod", "production", "prd"], lower(var.environment)) || contains(["prod", "production", "prd"], lower(var.environment_short))
  waf_policy_name     = "waf-${local.name_prefix}"
  log_analytics_name     = "log-${local.name_prefix}"
  monitor_workspace_name = "amon-${local.name_prefix}"
  grafana_name           = length("grf-${local.name_prefix}") <= 23 ? "grf-${local.name_prefix}" : "grf-${substr(local.name_prefix, 0, 16)}${substr(sha256(local.name_prefix), 0, 3)}"
  # Data Collection Endpoint max length = 44; DCR max length = 64.
  _dce_full           = "dce-prometheus-${local.name_prefix}"
  dce_prometheus_name = length(local._dce_full) <= 44 ? local._dce_full : "dce-prometheus-${substr(local.name_prefix, 0, 26)}${substr(sha256(local.name_prefix), 0, 3)}"
  _dcr_full           = "dcr-prometheus-${local.name_prefix}"
  dcr_prometheus_name = length(local._dcr_full) <= 64 ? local._dcr_full : "dcr-prometheus-${substr(local.name_prefix, 0, 46)}${substr(sha256(local.name_prefix), 0, 3)}"
  # Container Insights logs DCR (max length = 64).
  _dcr_ci_full                = "dcr-ci-${local.name_prefix}"
  dcr_container_insights_name = length(local._dcr_ci_full) <= 64 ? local._dcr_ci_full : "dcr-ci-${substr(local.name_prefix, 0, 54)}${substr(sha256(local.name_prefix), 0, 3)}"
  route_table_name            = "rt-${local.name_prefix}"
  nsg_appgw_name              = "nsg-agw-${local.name_prefix}"
  nsg_agc_name                = "nsg-agc-${local.name_prefix}"
  nsg_pe_name                 = "nsg-pe-${local.name_prefix}"
  managed_identity_name       = "id-${local.name_prefix}"
  nsg_aks_system_name         = "nsg-aks-system-${local.name_prefix}"
  nsg_aks_user_name           = "nsg-aks-user-${local.name_prefix}"
  nsg_apiserver_name          = "nsg-aks-apiserver-${local.name_prefix}"
  nsg_jumpbox_name            = "nsg-jbx-${local.name_prefix}"
  nsg_bastion_name            = "nsg-bas-${local.name_prefix}"

  # Management access (opt-in Azure Bastion + jumpbox VM)
  enable_jumpbox = var.enable_management_jumpbox
  # Default outbound access was retired (2025-09-30), so a no-public-IP VM has no
  # implicit internet egress. In a STANDALONE spoke there is no hub firewall to
  # route through, so the jumpbox subnet needs a NAT gateway for outbound access
  # (Entra SSH extension install, apt, and operator tooling). In a corp/ALZ
  # topology egress is provided by the hub firewall via the AKS route table, so
  # no NAT gateway is created there.
  enable_jumpbox_nat   = var.enable_management_jumpbox && !local.is_corp
  bastion_name         = "bas-${local.name_prefix}"
  bastion_pip_name     = "pip-bas-${local.name_prefix}"
  jumpbox_vm_name      = "vm-jbx-${local.name_prefix}"
  jumpbox_nic_name     = "nic-jbx-${local.name_prefix}"
  jumpbox_disk_name    = "osdisk-jbx-${local.name_prefix}"
  jumpbox_natgw_name   = "natgw-jbx-${local.name_prefix}"
  jumpbox_nat_pip_name = "pip-natgw-jbx-${local.name_prefix}"

  backup_storage_account_name = "stbkp${substr(md5(local.name_prefix), 0, 18)}"

  # Subnet configurations — system and user node pools on separate subnets
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
    agc = {
      name             = "snet-agc-${local.name_prefix}"
      address_prefixes = [var.subnet_address_prefixes.agc]
    }
    private_endpoints = {
      name             = "snet-pe-${local.name_prefix}"
      address_prefixes = [var.subnet_address_prefixes.private_endpoints]
    }
    ingress = {
      name             = "snet-ingress-${local.name_prefix}"
      address_prefixes = [var.subnet_address_prefixes.ingress]
    }
    jumpbox = {
      name             = "snet-jbx-${local.name_prefix}"
      address_prefixes = [var.subnet_address_prefixes.jumpbox]
    }
    # Azure Bastion requires the subnet to be named exactly "AzureBastionSubnet"
    # and be at least a /26.
    bastion = {
      name             = "AzureBastionSubnet"
      address_prefixes = [var.subnet_address_prefixes.bastion]
    }
  }
  default_tags = merge(var.tags, {
    workload    = var.workload_name
    environment = var.environment
    managed_by  = "terraform"
    project     = "aksapplz"
  })

  # Hub firewall private IP for UDR (only used in Corp)
  hub_firewall_private_ip = var.hub_firewall_private_ip != "" ? var.hub_firewall_private_ip : "0.0.0.0"

  # Topology is derived from inputs: when hub_vnet_resource_id is supplied,
  # this is a spoke landing zone (UDR + VNet peering). When empty, standalone.
  is_corp = var.hub_vnet_resource_id != ""

  # Private endpoints are used in corp (hub) topology, or when explicitly
  # enabled in standalone via enable_private_endpoints.
  use_private_endpoints = local.is_corp || var.enable_private_endpoints

  # Standalone self-managed private DNS: create + link the privatelink zones to
  # the spoke VNet when private endpoints are enabled without a hub. In corp the
  # zones are supplied from the hub via *_private_dns_zone_ids.
  manage_private_dns = var.enable_private_endpoints && !local.is_corp

  # Grafana is private whenever private endpoints are in use (corp topology or
  # standalone + enable_private_endpoints). The explicit grafana_public_access
  # variable overrides this when set to a non-null value.
  grafana_public_access_effective = var.grafana_public_access != null ? var.grafana_public_access : !local.use_private_endpoints

  # Private DNS zone ids for the Grafana private endpoint: the self-managed zone
  # in standalone, or hub-supplied ids in corp topology.
  grafana_private_dns_zone_ids = local.manage_private_dns && var.enable_managed_grafana ? [azurerm_private_dns_zone.grafana[0].id] : var.grafana_private_dns_zone_ids
}
