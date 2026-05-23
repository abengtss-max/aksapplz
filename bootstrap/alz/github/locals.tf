locals {
  # Default name templates. Wizard / user can override individual entries via var.resource_names.
  default_resource_names = {
    resource_group_state    = "rg-{{service_name}}-{{environment_name}}-state-{{azure_location_short}}-{{postfix_number}}"
    resource_group_identity = "rg-{{service_name}}-{{environment_name}}-identity-{{azure_location_short}}-{{postfix_number}}"
    resource_group_network  = "rg-{{service_name}}-{{environment_name}}-net-{{azure_location_short}}-{{postfix_number}}"
    resource_group_agents   = "rg-{{service_name}}-{{environment_name}}-agents-{{azure_location_short}}-{{postfix_number}}"

    storage_account                  = "st{{service_name_short}}{{environment_name_short}}{{azure_location_short}}{{postfix_number}}{{random_string}}"
    storage_container                = "tfstate"
    storage_account_private_endpoint = "pe-st-{{service_name}}-{{environment_name}}-{{azure_location_short}}-{{postfix_number}}"

    container_registry                  = "cr{{service_name_short}}{{environment_name_short}}{{azure_location_short}}{{postfix_number}}{{random_string}}"
    container_registry_private_endpoint = "pe-cr-{{service_name}}-{{environment_name}}-{{azure_location_short}}-{{postfix_number}}"
    container_image_name                = "github-runner"

    virtual_network            = "vnet-{{service_name}}-{{environment_name}}-{{azure_location_short}}-{{postfix_number}}"
    subnet_container_instances = "snet-aci"
    subnet_private_endpoints   = "snet-pe"
    public_ip                  = "pip-natgw-{{service_name}}-{{environment_name}}-{{azure_location_short}}-{{postfix_number}}"
    nat_gateway                = "natgw-{{service_name}}-{{environment_name}}-{{azure_location_short}}-{{postfix_number}}"

    container_instance_managed_identity = "id-aci-runner-{{service_name}}-{{environment_name}}-{{azure_location_short}}-{{postfix_number}}"
    managed_identity_plan               = "id-plan-{{service_name}}-{{environment_name}}-{{azure_location_short}}-{{postfix_number}}"
    managed_identity_apply              = "id-apply-{{service_name}}-{{environment_name}}-{{azure_location_short}}-{{postfix_number}}"

    version_control_system_repository   = "{{service_name}}-{{environment_name}}"
    version_control_system_team         = "{{service_name}}-{{environment_name}}-approvers"
    version_control_system_runner_group = "{{service_name}}-{{environment_name}}-runners"
  }

  # GitHub Actions environments configured on the workload repo.
  environments = {
    plan = {
      reviewers_users = []
      wait_timer      = 0
    }
    apply = {
      reviewers_users = var.apply_approvers
      wait_timer      = 0
    }
  }
}
