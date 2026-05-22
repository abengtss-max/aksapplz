data "azurerm_client_config" "current" {}

data "http" "my_ip" {
  count = var.use_private_networking ? 1 : 0
  url   = "https://api.ipify.org"
}
