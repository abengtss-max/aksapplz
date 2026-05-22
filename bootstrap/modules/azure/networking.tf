module "public_ip" {
  count   = var.use_private_networking && var.use_self_hosted_runners ? 1 : 0
  source  = "Azure/avm-res-network-publicipaddress/azurerm"
  version = "~> 0.2"

  name                = var.resource_names["public_ip"]
  resource_group_name = azurerm_resource_group.network[0].name
  location            = var.azure_location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  enable_telemetry    = false
  tags                = var.tags
}

module "nat_gateway" {
  count   = var.use_private_networking && var.use_self_hosted_runners ? 1 : 0
  source  = "Azure/avm-res-network-natgateway/azurerm"
  version = "~> 0.3"

  name                    = var.resource_names["nat_gateway"]
  parent_id               = azurerm_resource_group.network[0].id
  location                = var.azure_location
  sku_name                = "Standard"
  idle_timeout_in_minutes = 4
  zones                   = ["1"]
  public_ip_resource_ids  = [module.public_ip[0].resource_id]
  enable_telemetry        = false
  tags                    = var.tags
}

module "virtual_network" {
  count   = var.use_private_networking ? 1 : 0
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "~> 0.17"

  name             = var.resource_names["virtual_network"]
  parent_id        = azurerm_resource_group.network[0].id
  location         = var.azure_location
  address_space    = [var.virtual_network_address_space]
  enable_telemetry = false
  tags             = var.tags

  subnets = merge(
    {
      private_endpoints = {
        name             = var.resource_names["subnet_private_endpoints"]
        address_prefixes = [var.subnet_address_prefix_private_endpoints]
      }
    },
    var.use_self_hosted_runners ? {
      container_instances = {
        name             = var.resource_names["subnet_container_instances"]
        address_prefixes = [var.subnet_address_prefix_container_instances]
        nat_gateway = {
          id = module.nat_gateway[0].resource_id
        }
        delegations = [{
          name = "Microsoft.ContainerInstance.containerGroups"
          service_delegation = {
            name = "Microsoft.ContainerInstance/containerGroups"
          }
        }]
      }
    } : {}
  )
}
