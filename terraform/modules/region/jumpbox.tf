# -----------------------------------------------------------------------------
# Region module - Management access (opt-in)
#
# Provisions an Azure Bastion host and a hardened, no-public-IP Linux jumpbox
# VM for secure operator access to a PRIVATE AKS cluster and its private
# endpoints. Everything in this file is gated on var.enable_management_jumpbox
# (default false), so a standard deployment creates ZERO of these resources.
#
# Design highlights (aligned with the AKS baseline / WAF guidance):
#   - No public IP on the VM; the only public IP belongs to Azure Bastion.
#   - Microsoft Entra ID SSH login (AADSSHLoginForLinux); password auth off.
#   - System-assigned managed identity with least-privilege AKS read roles.
#   - Auto-shutdown schedule to cap idle cost.
#   - Locked-down NSGs (see networking.tf).
#   - Operator tooling (az, kubectl, kubelogin, helm) pre-installed via cloud-init.
#
# Intended for STANDALONE deployments. In ALZ/corp topologies the platform team
# normally provides centralized Bastion/VPN in the connectivity hub, so leave
# this disabled there.
# -----------------------------------------------------------------------------

# Ephemeral SSH key pair. Interactive login is via Microsoft Entra ID, so this
# local key exists only to satisfy the VM's admin_ssh_key requirement and is not
# distributed. It is regenerated on a fresh apply and kept in state.
resource "tls_private_key" "jumpbox" {
  count = local.enable_jumpbox ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

# --- Azure Bastion ---------------------------------------------------------

resource "azurerm_public_ip" "bastion" {
  count = local.enable_jumpbox ? 1 : 0

  name                = local.bastion_pip_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.availability_zones
  tags                = local.default_tags
}

resource "azurerm_bastion_host" "main" {
  count = local.enable_jumpbox ? 1 : 0

  name                = local.bastion_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.bastion_sku
  # Native-client tunneling (az network bastion ssh/tunnel) requires Standard.
  tunneling_enabled = var.bastion_sku == "Standard"
  tags              = local.default_tags

  ip_configuration {
    name                 = "bastion-ipconfig"
    subnet_id            = module.spoke_vnet.subnets["bastion"].resource_id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }
}

# --- Jumpbox outbound egress (NAT gateway, standalone only) ----------------
#
# The jumpbox VM has no public IP, and Azure retired default outbound access
# (2025-09-30). Without explicit egress the AADSSHLoginForLinux extension and
# cloud-init tooling install fail ("Network is unreachable"). A NAT gateway
# gives the subnet deterministic, secure outbound access while keeping the VM
# private. Only created for STANDALONE deployments — in corp/ALZ topologies the
# jumpbox subnet egresses via the hub firewall using the AKS route table.
resource "azurerm_public_ip" "jumpbox_nat" {
  count = local.enable_jumpbox_nat ? 1 : 0

  name                = local.jumpbox_nat_pip_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.default_tags
}

resource "azurerm_nat_gateway" "jumpbox" {
  count = local.enable_jumpbox_nat ? 1 : 0

  name                    = local.jumpbox_natgw_name
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 4
  tags                    = local.default_tags
}

resource "azurerm_nat_gateway_public_ip_association" "jumpbox" {
  count = local.enable_jumpbox_nat ? 1 : 0

  nat_gateway_id       = azurerm_nat_gateway.jumpbox[0].id
  public_ip_address_id = azurerm_public_ip.jumpbox_nat[0].id
}

# --- Jumpbox VM ------------------------------------------------------------

resource "azurerm_network_interface" "jumpbox" {
  count = local.enable_jumpbox ? 1 : 0

  name                = local.jumpbox_nic_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.default_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = module.spoke_vnet.subnets["jumpbox"].resource_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "jumpbox" {
  count = local.enable_jumpbox ? 1 : 0

  name                = local.jumpbox_vm_name
  computer_name       = "jumpbox"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = var.jumpbox_vm_size
  admin_username      = var.jumpbox_admin_username
  network_interface_ids = [
    azurerm_network_interface.jumpbox[0].id
  ]
  tags = local.default_tags

  # Entra ID login only — no password authentication.
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.jumpbox_admin_username
    public_key = tls_private_key.jumpbox[0].public_key_openssh
  }

  # Bootstrap operator tooling (az, kubectl, kubelogin, helm).
  custom_data = base64encode(<<-CLOUDINIT
    #cloud-config
    package_update: true
    runcmd:
      - curl -sL https://aka.ms/InstallAzureCLIDeb | bash
      - az aks install-cli
      - curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  CLOUDINIT
  )

  os_disk {
    name                 = local.jumpbox_disk_name
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # System-assigned identity for passwordless az/kubectl against AKS.
  identity {
    type = "SystemAssigned"
  }
}

# Microsoft Entra ID SSH login extension.
resource "azurerm_virtual_machine_extension" "aad_login" {
  count = local.enable_jumpbox ? 1 : 0

  name                       = "AADSSHLoginForLinux"
  virtual_machine_id         = azurerm_linux_virtual_machine.jumpbox[0].id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADSSHLoginForLinux"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
}

# --- RBAC ------------------------------------------------------------------

# Operators authenticate to the VM over Bastion using Microsoft Entra ID. Grant
# the "Virtual Machine Administrator Login" role to the same admin groups that
# administer the cluster so they can Entra-login to the jumpbox.
resource "azurerm_role_assignment" "jumpbox_admin_login" {
  for_each = local.enable_jumpbox ? toset(var.aks_admin_group_object_ids) : toset([])

  scope                = azurerm_linux_virtual_machine.jumpbox[0].id
  role_definition_name = "Virtual Machine Administrator Login"
  principal_id         = each.value
}

# The jumpbox's managed identity needs the Cluster User role to pull a kubeconfig
# via `az aks get-credentials`.
resource "azurerm_role_assignment" "jumpbox_aks_cluster_user" {
  count = local.enable_jumpbox ? 1 : 0

  scope                = module.aks.resource_id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = azurerm_linux_virtual_machine.jumpbox[0].identity[0].principal_id
}

# When Azure RBAC for Kubernetes is enabled, also grant the jumpbox identity the
# in-cluster RBAC Reader role so kubectl has (read-only) authorization by default.
resource "azurerm_role_assignment" "jumpbox_aks_rbac_reader" {
  count = local.enable_jumpbox && var.enable_azure_rbac ? 1 : 0

  scope                = module.aks.resource_id
  role_definition_name = "Azure Kubernetes Service RBAC Reader"
  principal_id         = azurerm_linux_virtual_machine.jumpbox[0].identity[0].principal_id
}

# --- Cost control ----------------------------------------------------------

resource "azurerm_dev_test_global_vm_shutdown_schedule" "jumpbox" {
  count = local.enable_jumpbox ? 1 : 0

  virtual_machine_id = azurerm_linux_virtual_machine.jumpbox[0].id
  location           = azurerm_resource_group.main.location
  enabled            = true

  daily_recurrence_time = var.jumpbox_auto_shutdown_time
  timezone              = var.jumpbox_auto_shutdown_timezone

  notification_settings {
    enabled = false
  }

  tags = local.default_tags
}
