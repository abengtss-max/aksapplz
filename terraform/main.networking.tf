# -----------------------------------------------------------------------------
# Networking - Spoke VNet, Subnets, NSGs, UDR, VNet Peering
# Uses Azure Verified Module: avm-res-network-virtualnetwork
# -----------------------------------------------------------------------------

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.default_tags
}

# Route Table - UDR to hub firewall
resource "azurerm_route_table" "aks" {
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

# NSG - AKS Nodes Subnet
resource "azurerm_network_security_group" "aks_nodes" {
  name                = local.nsg_aks_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.default_tags
}

# NSG - Application Gateway Subnet
resource "azurerm_network_security_group" "app_gateway" {
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

# NSG - Private Endpoints Subnet
resource "azurerm_network_security_group" "private_endpoints" {
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

# Spoke VNet using Azure Verified Module
module "spoke_vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "~> 0.7"

  name                = local.vnet_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = [var.vnet_address_space]
  tags                = local.default_tags

  subnets = {
    aks_nodes = {
      name             = local.subnets.aks_nodes.name
      address_prefixes = local.subnets.aks_nodes.address_prefixes
      network_security_group = {
        id = azurerm_network_security_group.aks_nodes.id
      }
      route_table = {
        id = azurerm_route_table.aks.id
      }
    }

    aks_api_server = {
      name             = local.subnets.aks_api_server.name
      address_prefixes = local.subnets.aks_api_server.address_prefixes
      delegation = [{
        name = "Microsoft.ContainerService.managedClusters"
        service_delegation = {
          name = "Microsoft.ContainerService/managedClusters"
          actions = [
            "Microsoft.Network/virtualNetworks/subnets/join/action"
          ]
        }
      }]
    }

    app_gateway = {
      name             = local.subnets.app_gateway.name
      address_prefixes = local.subnets.app_gateway.address_prefixes
      network_security_group = {
        id = azurerm_network_security_group.app_gateway.id
      }
    }

    private_endpoints = {
      name             = local.subnets.private_endpoints.name
      address_prefixes = local.subnets.private_endpoints.address_prefixes
      network_security_group = {
        id = azurerm_network_security_group.private_endpoints.id
      }
    }

    ingress = {
      name             = local.subnets.ingress.name
      address_prefixes = local.subnets.ingress.address_prefixes
      network_security_group = {
        id = azurerm_network_security_group.aks_nodes.id
      }
    }
  }
}

# VNet Peering: Spoke -> Hub
resource "azurerm_virtual_network_peering" "spoke_to_hub" {
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
