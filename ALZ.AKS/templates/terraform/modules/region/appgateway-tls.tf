# -----------------------------------------------------------------------------
# Region module - Application Gateway self-signed TLS certificate (dev/test)
# -----------------------------------------------------------------------------
# When appgw_tls_mode = "self_signed" the accelerator generates a self-signed
# certificate INSIDE Key Vault. The private key is created by Key Vault and
# never leaves it: nothing sensitive is written to the Git repository or to
# Terraform state. The Application Gateway reads the certificate through the AKS
# user-assigned identity (already granted Key Vault Secrets User) over the
# vault's private endpoint, and the versionless secret URL lets the gateway
# auto-pick up renewals.
#
# REQUIREMENTS for self_signed mode (dev/test only):
#   1. The deploying identity must reach the Key Vault DATA plane. In the
#      accelerator's recommended posture the vault is private and the CD job
#      runs on the VNet-injected self-hosted runner, which satisfies this. A
#      GitHub-hosted runner cannot reach a private (or deny-by-default) vault.
#   2. The deploying identity needs Key Vault Certificates Officer to create the
#      certificate. That role is granted below for the duration of the run.
#
# Production must instead use a customer-provided certificate (appgw_tls_mode =
# keyvault via appgw_tls_key_vault_secret_id); a precondition on the gateway
# enforces this.

locals {
  # Principals allowed to create the self-signed certificate. Mirrors the
  # plan-vs-apply identity handling used for the AKS RBAC reader grant: grant
  # every CD identity supplied by the bootstrap (plan + apply), falling back to
  # the current (plan-time) identity for standalone `terraform apply` runs.
  deployer_kv_cert_principal_ids = local.appgw_self_signed_tls ? toset(
    length(var.cd_identity_principal_ids) > 0
    ? var.cd_identity_principal_ids
    : [data.azurerm_client_config.current.object_id]
  ) : toset([])
}

# Data-plane permission to create the self-signed certificate in Key Vault.
resource "azurerm_role_assignment" "deployer_kv_cert_officer" {
  for_each = local.deployer_kv_cert_principal_ids

  scope                = module.key_vault.resource_id
  role_definition_name = "Key Vault Certificates Officer"
  principal_id         = each.value
}

# Self-signed certificate generated and stored entirely inside Key Vault.
resource "azurerm_key_vault_certificate" "appgw_self_signed" {
  count = local.appgw_self_signed_tls ? 1 : 0

  name         = "appgw-self-signed-${local.name_prefix}"
  key_vault_id = module.key_vault.resource_id
  tags         = local.default_tags

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      # Application Gateway requires an exportable private key to serve TLS.
      exportable = true
      key_type   = "RSA"
      key_size   = 2048
      reuse_key  = true
    }

    lifetime_action {
      action {
        action_type = "AutoRenew"
      }
      trigger {
        days_before_expiry = 30
      }
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      key_usage = [
        "digitalSignature",
        "keyEncipherment",
      ]
      extended_key_usage = ["1.3.6.1.5.5.7.3.1"] # serverAuth
      subject            = coalesce(var.appgw_self_signed_subject, "CN=${local.app_gateway_name}")
      validity_in_months = 12

      subject_alternative_names {
        dns_names = compact([
          local.app_gateway_name,
          try(azurerm_public_ip.app_gateway[0].fqdn, ""),
        ])
      }
    }
  }

  # The certificate cannot be created until the deploying identity has the
  # Certificates Officer data-plane role.
  depends_on = [azurerm_role_assignment.deployer_kv_cert_officer]
}
