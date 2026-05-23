output "hub_vnet_resource_id" {
  description = "Resource ID of the hub VNet."
  value       = module.hub.hub_vnet_resource_id
}

output "hub_vnet_name" {
  description = "Name of the hub VNet."
  value       = module.hub.hub_vnet_name
}

output "hub_vnet_resource_group_name" {
  description = "Resource group of the hub VNet."
  value       = module.hub.hub_vnet_resource_group_name
}

output "hub_firewall_private_ip" {
  description = "Private IP of the hub Azure Firewall (empty if not deployed)."
  value       = module.hub.hub_firewall_private_ip
}

output "hub_firewall_public_ip" {
  description = "Public IP of the hub Azure Firewall (empty if not deployed)."
  value       = module.hub.hub_firewall_public_ip
}
