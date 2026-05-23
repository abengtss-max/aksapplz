output "hub_vnet_resource_id" {
  description = "Resource ID of the hub VNet (for spoke peering)."
  value       = azurerm_virtual_network.hub.id
}

output "hub_vnet_name" {
  description = "Name of the hub VNet."
  value       = azurerm_virtual_network.hub.name
}

output "hub_vnet_resource_group_name" {
  description = "Resource group containing the hub VNet."
  value       = azurerm_resource_group.hub.name
}

output "hub_firewall_private_ip" {
  description = "Private IP of the hub Azure Firewall (empty if firewall was not deployed)."
  value       = var.deploy_firewall ? azurerm_firewall.hub[0].ip_configuration[0].private_ip_address : ""
}

output "hub_firewall_public_ip" {
  description = "Public IP of the hub Azure Firewall (empty if firewall was not deployed)."
  value       = var.deploy_firewall ? azurerm_public_ip.firewall[0].ip_address : ""
}
