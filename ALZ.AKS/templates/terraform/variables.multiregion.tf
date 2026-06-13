# -----------------------------------------------------------------------------
# Variables - Multi-region & global load balancing
# (Single-region deployments leave these at their defaults.)
# -----------------------------------------------------------------------------

variable "global_lb_type" {
  description = <<-EOT
    Global load balancer to place in front of the regional clusters when
    multi-region is enabled (secondary_location set):
    - "none"           : no global load balancer (DNS/manual)
    - "front_door"     : Azure Front Door Premium (HTTP/S, WAF, anycast)
    - "traffic_manager": Azure Traffic Manager (DNS-based, Priority failover)
  EOT
  type        = string
  default     = "none"
  validation {
    condition     = contains(["none", "front_door", "traffic_manager"], var.global_lb_type)
    error_message = "global_lb_type must be one of: none, front_door, traffic_manager."
  }
}

variable "enable_fleet_manager" {
  description = "Enable Azure Kubernetes Fleet Manager and auto-join every regional cluster as a member (multi-region only)."
  type        = bool
  default     = false
}

# --- Secondary region networking (used only when secondary_location is set) ---
variable "secondary_vnet_address_space" {
  description = "The address space for the secondary region's spoke VNet. Must not overlap the primary VNet."
  type        = string
  default     = "10.20.0.0/16"
}

variable "secondary_availability_zones" {
  description = "Availability zones for the secondary region's AKS node pools. Empty list falls back to var.availability_zones. Set this when the secondary region/SKU supports different zones than the primary."
  type        = list(string)
  default     = []
}

variable "secondary_subnet_address_prefixes" {
  description = "Address prefixes for each subnet in the secondary region."
  type = object({
    aks_system_nodes  = string
    aks_user_nodes    = string
    aks_api_server    = string
    app_gateway       = string
    private_endpoints = string
    ingress           = string
    agc               = optional(string, "10.20.24.0/24")
  })
  default = {
    aks_system_nodes  = "10.20.0.0/24"
    aks_user_nodes    = "10.20.16.0/22"
    aks_api_server    = "10.20.20.0/28"
    app_gateway       = "10.20.21.0/24"
    private_endpoints = "10.20.22.0/24"
    ingress           = "10.20.23.0/24"
    agc               = "10.20.24.0/24"
  }
}

variable "secondary_hub_vnet_resource_id" {
  description = "Resource ID of the hub VNet to peer the secondary spoke with. Empty = standalone secondary."
  type        = string
  default     = ""
}

variable "secondary_hub_vnet_name" {
  description = "Name of the secondary hub VNet."
  type        = string
  default     = ""
}

variable "secondary_hub_vnet_resource_group_name" {
  description = "Resource group name of the secondary hub VNet."
  type        = string
  default     = ""
}

variable "secondary_hub_firewall_private_ip" {
  description = "Private IP of the secondary hub Azure Firewall (for UDR)."
  type        = string
  default     = ""
}
