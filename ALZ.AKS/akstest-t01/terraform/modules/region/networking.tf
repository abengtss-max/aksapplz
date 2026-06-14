# -----------------------------------------------------------------------------
# Region module - Networking (Spoke VNet, Subnets, NSGs, UDR, VNet Peering)
# -----------------------------------------------------------------------------

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.default_tags
}

# Route Table - UDR to hub firewall (Corp only)
resource "azurerm_route_table" "aks" {
  count = local.is_corp ? 1 : 0

  name                = local.route_table_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.default_tags

  route {
    name                   = "default-to-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = local.hub_firewall_private_ip
  }
}

# NSG - AKS System Node Pool Subnet
resource "azurerm_network_security_group" "aks_system_nodes" {
  name                = local.nsg_aks_system_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.default_tags
}

# NSG - AKS User Node Pool Subnet
resource "azurerm_network_security_group" "aks_user_nodes" {
  name                = local.nsg_aks_user_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.default_tags
}

# NSG - AKS API Server (VNet integration) Subnet
# Required because the ALZ "Deny-Subnet-Without-Nsg" policy denies any subnet
# without an NSG. The subnet is delegated to managedClusters; an empty NSG
# (default rules only) satisfies the policy without affecting API server traffic.
resource "azurerm_network_security_group" "aks_api_server" {
  name                = local.nsg_apiserver_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.default_tags
}

# NSG - Application Gateway Subnet
resource "azurerm_network_security_group" "app_gateway" {
  count = var.enable_app_gateway ? 1 : 0

  name                = local.nsg_appgw_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.default_tags

  # Required for Application Gateway v2
  security_rule {
    name                       = "AllowGatewayManager"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowAzureLoadBalancer"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

# NSG - Private Endpoints Subnet (Corp only — Online uses public endpoints)
resource "azurerm_network_security_group" "private_endpoints" {
  count = local.is_corp ? 1 : 0

  name                = local.nsg_pe_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.default_tags

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowVnetInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }
}

# NSG - Application Gateway for Containers (ALB) delegated subnet
# Required because the ALZ "Deny-Subnet-Without-Nsg" policy denies any subnet
# without an NSG. The subnet is delegated to trafficControllers and the data
# plane is managed by the in-cluster ALB Controller; an empty NSG (default
# rules only) satisfies the policy without affecting AGC traffic.
resource "azurerm_network_security_group" "agc" {
  count = var.enable_agc ? 1 : 0

  name                = local.nsg_agc_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.default_tags
}

# Spoke VNet using Azure Verified Module
module "spoke_vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "~> 0.7"

  name          = local.vnet_name
  parent_id     = azurerm_resource_group.main.id
  location      = azurerm_resource_group.main.location
  address_space = [var.vnet_address_space]
  tags          = local.default_tags

  subnets = merge(
    # AKS system node pool subnet — dedicated for system pods (CriticalAddonsOnly)
    {
      aks_system_nodes = {
        name             = local.subnets.aks_system_nodes.name
        address_prefixes = local.subnets.aks_system_nodes.address_prefixes
        # Storage service endpoint lets the backup extension reach the
        # default-deny backup storage account (only when backup is enabled).
        service_endpoints = var.enable_backup ? ["Microsoft.Storage"] : null
        network_security_group = {
          id = azurerm_network_security_group.aks_system_nodes.id
        }
        route_table = local.is_corp ? {
          id = azurerm_route_table.aks[0].id
        } : null
      }
    },
    # AKS user node pool subnet — dedicated for workload pods
    {
      aks_user_nodes = {
        name             = local.subnets.aks_user_nodes.name
        address_prefixes = local.subnets.aks_user_nodes.address_prefixes
        service_endpoints = var.enable_backup ? ["Microsoft.Storage"] : null
        network_security_group = {
          id = azurerm_network_security_group.aks_user_nodes.id
        }
        route_table = local.is_corp ? {
          id = azurerm_route_table.aks[0].id
        } : null
      }
    },
    # AKS API server subnet — always created (for VNet integration)
    {
      aks_api_server = {
        name             = local.subnets.aks_api_server.name
        address_prefixes = local.subnets.aks_api_server.address_prefixes
        network_security_group = {
          id = azurerm_network_security_group.aks_api_server.id
        }
        delegations = [{
          name = "Microsoft.ContainerService.managedClusters"
          service_delegation = {
            name = "Microsoft.ContainerService/managedClusters"
          }
        }]
      }
    },
    # App Gateway subnet — only if enabled
    var.enable_app_gateway ? {
      app_gateway = {
        name             = local.subnets.app_gateway.name
        address_prefixes = local.subnets.app_gateway.address_prefixes
        network_security_group = {
          id = azurerm_network_security_group.app_gateway[0].id
        }
      }
    } : {},
    # Application Gateway for Containers (ALB) delegated subnet — only if enabled.
    # Delegated to trafficControllers; the in-cluster ALB Controller creates and
    # manages the AGC resource and associates it with this subnet.
    var.enable_agc ? {
      agc = {
        name             = local.subnets.agc.name
        address_prefixes = local.subnets.agc.address_prefixes
        network_security_group = {
          id = azurerm_network_security_group.agc[0].id
        }
        delegations = [{
          name = "Microsoft.ServiceNetworking.trafficControllers"
          service_delegation = {
            name = "Microsoft.ServiceNetworking/trafficControllers"
          }
        }]
      }
    } : {},
    # Private endpoints subnet — Corp only
    local.is_corp ? {
      private_endpoints = {
        name             = local.subnets.private_endpoints.name
        address_prefixes = local.subnets.private_endpoints.address_prefixes
        network_security_group = {
          id = azurerm_network_security_group.private_endpoints[0].id
        }
      }
    } : {},
    # Ingress subnet — always created
    {
      ingress = {
        name             = local.subnets.ingress.name
        address_prefixes = local.subnets.ingress.address_prefixes
        network_security_group = {
          id = azurerm_network_security_group.aks_user_nodes.id
        }
      }
    }
  )
}

# =============================================================================
# VNet Peering (Corp only)
# =============================================================================

# VNet Peering: Spoke -> Hub
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  count = local.is_corp ? 1 : 0

  name                         = "peer-spoke-to-hub"
  resource_group_name          = azurerm_resource_group.main.name
  virtual_network_name         = module.spoke_vnet.name
  remote_virtual_network_id    = var.hub_vnet_resource_id
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = var.use_remote_gateways
  allow_virtual_network_access = true
}

# VNet Peering: Hub -> Spoke
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  count    = local.is_corp ? 1 : 0
  provider = azurerm.connectivity

  name                         = "peer-hub-to-${local.name_prefix}"
  resource_group_name          = var.hub_vnet_resource_group_name
  virtual_network_name         = var.hub_vnet_name
  remote_virtual_network_id    = module.spoke_vnet.resource_id
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false
  allow_virtual_network_access = true
}
