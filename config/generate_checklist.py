"""
Generate the AKS Application Landing Zone Accelerator planning checklist (checklist.xlsx).
Mirrors the ALZ accelerator checklist format with tabs for Bootstrap and AKS Landing Zone decisions.
"""

import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.datavalidation import DataValidation

wb = openpyxl.Workbook()

# ============================================================================
# Styles
# ============================================================================
header_font = Font(name="Segoe UI", size=11, bold=True, color="FFFFFF")
header_fill = PatternFill(start_color="0078D4", end_color="0078D4", fill_type="solid")  # Azure blue
section_font = Font(name="Segoe UI", size=11, bold=True, color="0078D4")
section_fill = PatternFill(start_color="DEEBF7", end_color="DEEBF7", fill_type="solid")  # Light blue
normal_font = Font(name="Segoe UI", size=10)
input_fill = PatternFill(start_color="FFF2CC", end_color="FFF2CC", fill_type="solid")  # Light yellow (user input)
note_font = Font(name="Segoe UI", size=9, italic=True, color="666666")
title_font = Font(name="Segoe UI", size=14, bold=True, color="0078D4")
subtitle_font = Font(name="Segoe UI", size=10, italic=True, color="555555")

thin_border = Border(
    left=Side(style="thin", color="D9D9D9"),
    right=Side(style="thin", color="D9D9D9"),
    top=Side(style="thin", color="D9D9D9"),
    bottom=Side(style="thin", color="D9D9D9"),
)

wrap_alignment = Alignment(wrap_text=True, vertical="top")
center_alignment = Alignment(horizontal="center", vertical="center")


def style_header_row(ws, row, max_col):
    for col in range(1, max_col + 1):
        cell = ws.cell(row=row, column=col)
        cell.font = header_font
        cell.fill = header_fill
        cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
        cell.border = thin_border


def style_section_row(ws, row, max_col):
    for col in range(1, max_col + 1):
        cell = ws.cell(row=row, column=col)
        cell.font = section_font
        cell.fill = section_fill
        cell.border = thin_border


def style_data_row(ws, row, max_col, is_input_col=None):
    for col in range(1, max_col + 1):
        cell = ws.cell(row=row, column=col)
        cell.font = normal_font
        cell.alignment = wrap_alignment
        cell.border = thin_border
        if is_input_col and col == is_input_col:
            cell.fill = input_fill


# ============================================================================
# TAB 1: Accelerator - Bootstrap
# ============================================================================
ws1 = wb.active
ws1.title = "Accelerator - Bootstrap"

# Title
ws1.merge_cells("A1:F1")
ws1["A1"].value = "AKS Application Landing Zone Accelerator - Bootstrap Decisions"
ws1["A1"].font = title_font
ws1["A1"].alignment = Alignment(vertical="center")
ws1.row_dimensions[1].height = 30

ws1.merge_cells("A2:F2")
ws1["A2"].value = "Fill in the 'Your Value' column (yellow) for each decision. Each decision maps to a setting in config/inputs.yaml."
ws1["A2"].font = subtitle_font
ws1.row_dimensions[2].height = 20

# Headers (row 4)
headers = ["Decision #", "Setting", "Description", "Options / Guidance", "Default", "Your Value"]
for col, h in enumerate(headers, 1):
    ws1.cell(row=4, column=col, value=h)
style_header_row(ws1, 4, 6)

# Column widths
ws1.column_dimensions["A"].width = 12
ws1.column_dimensions["B"].width = 40
ws1.column_dimensions["C"].width = 50
ws1.column_dimensions["D"].width = 55
ws1.column_dimensions["E"].width = 20
ws1.column_dimensions["F"].width = 30

# --- Decision rows ---
decisions = [
    # (decision#, setting, description, options, default)
    ("", "BOOTSTRAP CONFIGURATION", "", "", ""),  # Section header

    ("1", "bootstrap_location",
     "Azure region for bootstrap resources (state storage, managed identity).",
     "Any valid Azure region. E.g.: swedencentral, westeurope, northeurope, eastus, eastus2",
     "swedencentral"),

    ("2", "aks_landing_zone_subscription_id",
     "The subscription where the AKS cluster and supporting resources will be deployed.",
     "Azure subscription ID (GUID format). Leave empty to use the subscription connected to Azure CLI.",
     "(current CLI subscription)"),

    ("3", "connectivity_subscription_id",
     "The subscription containing the hub VNet and firewall (deployed by ALZ accelerator).",
     "Azure subscription ID (GUID). This is the connectivity subscription from your ALZ deployment.",
     ""),

    ("", "HUB NETWORKING", "", "", ""),  # Section header

    ("4a", "hub_vnet_resource_id",
     "Full ARM resource ID of the hub VNet for VNet peering.",
     "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Network/virtualNetworks/{name}",
     ""),

    ("4b", "hub_firewall_private_ip",
     "Private IP of the hub firewall. Used for UDR to route egress from AKS nodes.",
     "IP address. E.g.: 10.0.0.4",
     ""),

    ("", "SPOKE NETWORKING", "", "", ""),  # Section header

    ("5a", "spoke_vnet_address_space",
     "Address space for the spoke VNet. Must not overlap with hub or other spokes.",
     "CIDR notation. Ensure /16 or larger for AKS scalability.",
     "10.10.0.0/16"),

    ("5b", "subnet_address_prefix_aks_nodes",
     "Subnet for AKS node pools. Needs to be large enough for max node count.",
     "CIDR notation. /20 supports ~4000 nodes with Azure CNI Overlay.",
     "10.10.0.0/20"),

    ("5c", "subnet_address_prefix_aks_api_server",
     "Subnet for AKS API Server VNet Integration (private API server access).",
     "CIDR notation. Minimum /28 required by Azure.",
     "10.10.16.0/28"),

    ("5d", "subnet_address_prefix_app_gateway",
     "Subnet for Application Gateway WAF v2. Dedicated subnet required by Azure.",
     "CIDR notation. /24 recommended.",
     "10.10.17.0/24"),

    ("5e", "subnet_address_prefix_private_endpoints",
     "Subnet for private endpoints (ACR, Key Vault).",
     "CIDR notation. /24 recommended.",
     "10.10.18.0/24"),

    ("5f", "subnet_address_prefix_ingress",
     "Subnet for ingress controller internal load balancer.",
     "CIDR notation. /24 recommended.",
     "10.10.19.0/24"),

    ("", "AKS CONFIGURATION", "", "", ""),  # Section header

    ("6a", "kubernetes_version",
     "Kubernetes version for the AKS cluster.",
     "Check available versions: az aks get-versions -l <region> -o table",
     "1.31"),

    ("6b", "aks_sku_tier",
     "AKS pricing tier. Standard includes SLA, Premium adds more features.",
     "Free | Standard | Premium",
     "Standard"),

    ("6c", "aks_private_cluster",
     "Enable private cluster with API Server VNet Integration.",
     "true = API server accessible only via private network.\nfalse = API server has public endpoint.",
     "true"),

    ("6d", "aks_admin_group_object_ids",
     "Entra ID group Object ID(s) for Kubernetes cluster admin RBAC binding.",
     "List of GUIDs. E.g.: [\"xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx\"].\nCreate group in Entra ID first.",
     "[]"),

    ("", "BOOTSTRAP RESOURCE SUBSCRIPTION", "", "", ""),  # Section header

    ("7", "bootstrap_subscription_id",
     "Subscription for Terraform state storage and managed identity.",
     "Azure subscription ID (GUID). Leave empty to use the AKS landing zone subscription.",
     "(same as Decision 2)"),

    ("", "BOOTSTRAP RESOURCE NAMING", "", "", ""),  # Section header

    ("8a", "service_name",
     "Service name used in resource naming convention: {service_name}-{environment_name}-{postfix}.",
     "Short alphanumeric string. E.g.: aksapplz, myapp, workload1",
     "aksapplz"),

    ("8b", "environment_name",
     "Environment name used in resource naming convention.",
     "E.g.: prod, staging, dev, test",
     "prod"),

    ("8c", "postfix_number",
     "Numeric postfix for resource uniqueness. Formatted as 3-digit: 001, 002, etc.",
     "Integer. E.g.: 1, 2, 444",
     "1"),

    ("", "BOOTSTRAP NETWORKING AND AGENTS", "", "", ""),  # Section header

    ("9a", "use_self_hosted_runners",
     "Use self-hosted GitHub Actions runners instead of GitHub-hosted runners.",
     "true = Self-hosted (required for private clusters).\nfalse = GitHub-hosted (simpler, but no private network access).",
     "true"),

    ("9b", "use_private_networking",
     "Deploy runners with private networking (VNet-connected).",
     "true = Runners deployed in spoke VNet (required for private cluster).\nfalse = Runners use public networking.\nOnly applies when use_self_hosted_runners = true.",
     "true"),

    ("", "VERSION CONTROL SYSTEM SETTINGS", "", "", ""),  # Section header

    ("10a", "github_personal_access_token",
     "GitHub PAT for repository and team management. Set via environment variable.",
     "Set $env:TF_VAR_github_personal_access_token = \"ghp_...\"\nRequired scopes: repo, admin:org, workflow",
     "(environment variable)"),

    ("10b", "github_runners_personal_access_token",
     "GitHub PAT for self-hosted runner registration. Only needed if use_self_hosted_runners = true.",
     "Set $env:TF_VAR_github_runners_personal_access_token = \"ghp_...\"\nRequired scopes: admin:org",
     "(environment variable)"),

    ("10c", "github_organization_name",
     "GitHub organization where repositories will be created.",
     "Your GitHub org name. E.g.: abengtss-max-org, contoso",
     ""),

    ("10d", "apply_approvers",
     "GitHub usernames who can approve deployments in the apply environment.",
     "List format: [\"user1\", \"user2\"]. These users are added to the approver team.",
     "[]"),

    ("", "FEATURES", "", "", ""),  # Section header

    ("11a", "enable_defender",
     "Enable Microsoft Defender for Containers on the AKS cluster.",
     "true | false",
     "true"),

    ("11b", "enable_keda",
     "Enable KEDA (Kubernetes Event-Driven Autoscaling) addon.",
     "true | false",
     "true"),

    ("11c", "enable_prometheus",
     "Enable Azure Managed Prometheus for metrics collection.",
     "true | false",
     "true"),

    ("11d", "enable_grafana",
     "Enable Azure Managed Grafana for dashboards and visualization.",
     "true | false",
     "true"),

    ("11e", "enable_app_gateway",
     "Enable Application Gateway with WAF v2 (OWASP 3.2 + Bot Manager rules).",
     "true | false",
     "true"),

    ("11f", "enable_acr",
     "Enable Azure Container Registry (Premium SKU with private endpoint).",
     "true | false",
     "true"),

    ("11g", "enable_key_vault",
     "Enable Azure Key Vault (RBAC mode with private endpoint and purge protection).",
     "true | false",
     "true"),

    ("", "BASIC INPUTS (DO NOT MODIFY)", "", "", ""),  # Section header

    ("—", "iac_type",
     "Infrastructure as Code type. Fixed to terraform.",
     "terraform",
     "terraform"),

    ("—", "bootstrap_module_name",
     "Bootstrap module identifier.",
     "aksapplz_github",
     "aksapplz_github"),

    ("—", "starter_module_name",
     "Starter module identifier.",
     "aks_landing_zone",
     "aks_landing_zone"),
]

row = 5
for d in decisions:
    decision_num, setting, description, options, default = d

    if decision_num == "":
        # Section header row
        ws1.cell(row=row, column=1, value="")
        ws1.merge_cells(start_row=row, start_column=2, end_row=row, end_column=6)
        ws1.cell(row=row, column=2, value=setting)
        style_section_row(ws1, row, 6)
    else:
        ws1.cell(row=row, column=1, value=decision_num)
        ws1.cell(row=row, column=2, value=setting)
        ws1.cell(row=row, column=3, value=description)
        ws1.cell(row=row, column=4, value=options)
        ws1.cell(row=row, column=5, value=default)
        ws1.cell(row=row, column=6, value="")  # User input
        style_data_row(ws1, row, 6, is_input_col=6)
        ws1.cell(row=row, column=1).alignment = center_alignment

    row += 1

# Add data validation for some cells
# SKU tier dropdown
for r in range(5, row):
    if ws1.cell(row=r, column=2).value == "aks_sku_tier":
        dv = DataValidation(type="list", formula1='"Free,Standard,Premium"', allow_blank=True)
        dv.error = "Please select Free, Standard, or Premium"
        dv.errorTitle = "Invalid SKU"
        ws1.add_data_validation(dv)
        dv.add(ws1.cell(row=r, column=6))

    if ws1.cell(row=r, column=2).value in ("aks_private_cluster", "use_self_hosted_runners",
                                             "use_private_networking", "enable_defender",
                                             "enable_keda", "enable_prometheus", "enable_grafana",
                                             "enable_app_gateway", "enable_acr", "enable_key_vault"):
        dv = DataValidation(type="list", formula1='"true,false"', allow_blank=True)
        ws1.add_data_validation(dv)
        dv.add(ws1.cell(row=r, column=6))


# ============================================================================
# TAB 2: Accelerator - AKS Landing Zone
# ============================================================================
ws2 = wb.create_sheet("Accelerator - AKS Landing Zone")

# Title
ws2.merge_cells("A1:F1")
ws2["A1"].value = "AKS Application Landing Zone - Scenario and Options Decisions"
ws2["A1"].font = title_font
ws2["A1"].alignment = Alignment(vertical="center")
ws2.row_dimensions[1].height = 30

ws2.merge_cells("A2:F2")
ws2["A2"].value = "Choose your AKS landing zone scenario and configure options. These map to settings in config/aks-landing-zone.tfvars."
ws2["A2"].font = subtitle_font
ws2.row_dimensions[2].height = 20

# Headers
headers2 = ["Category", "Setting", "Description", "Options / Guidance", "Default", "Your Value"]
for col, h in enumerate(headers2, 1):
    ws2.cell(row=4, column=col, value=h)
style_header_row(ws2, 4, 6)

ws2.column_dimensions["A"].width = 18
ws2.column_dimensions["B"].width = 38
ws2.column_dimensions["C"].width = 50
ws2.column_dimensions["D"].width = 55
ws2.column_dimensions["E"].width = 20
ws2.column_dimensions["F"].width = 30

# AKS Landing Zone options
options_data = [
    ("", "SCENARIO", "", "", ""),

    ("Scenario", "deployment_topology",
     "The network topology for the AKS landing zone.",
     "hub_spoke = Spoke VNet peered to existing ALZ hub with UDR to firewall.\nThis is the only supported scenario for aksapplz.",
     "hub_spoke"),

    ("", "COMPUTE - SYSTEM NODE POOL", "", "", ""),

    ("Compute", "system_node_pool_vm_size",
     "VM SKU for the system node pool (runs critical system pods).",
     "Standard_D4ds_v5, Standard_D8ds_v5, Standard_D4s_v5, etc.\nMust support ephemeral OS disks.",
     "Standard_D4ds_v5"),

    ("Compute", "system_node_pool_min_count",
     "Minimum number of nodes in the system pool (autoscaler lower bound).",
     "Integer >= 2 for production high availability.",
     "2"),

    ("Compute", "system_node_pool_max_count",
     "Maximum number of nodes in the system pool.",
     "Integer. Typically 3-5 for system workloads.",
     "5"),

    ("Compute", "system_node_pool_os_disk_type",
     "OS disk type for system nodes.",
     "Ephemeral = Local SSD (faster, no cost).\nManaged = Azure managed disk.",
     "Ephemeral"),

    ("", "COMPUTE - USER NODE POOL", "", "", ""),

    ("Compute", "user_node_pool_vm_size",
     "VM SKU for the user node pool (runs application workloads).",
     "Standard_D4ds_v5, Standard_D8ds_v5, Standard_D16ds_v5, etc.\nChoose based on application requirements.",
     "Standard_D4ds_v5"),

    ("Compute", "user_node_pool_min_count",
     "Minimum number of nodes in the user pool.",
     "Integer >= 2 for production. KEDA/HPA will autoscale above this.",
     "2"),

    ("Compute", "user_node_pool_max_count",
     "Maximum number of nodes in the user pool (autoscaler upper bound).",
     "Integer. Set based on peak workload requirements.",
     "20"),

    ("Compute", "user_node_pool_os_disk_type",
     "OS disk type for user nodes.",
     "Ephemeral | Managed",
     "Ephemeral"),

    ("", "NETWORKING", "", "", ""),

    ("Networking", "network_plugin",
     "Kubernetes network plugin for pod networking.",
     "azure (Azure CNI Overlay) = Pods get overlay IPs, no VNet IP exhaustion.\nkubenet = Basic networking (not recommended for production).",
     "azure"),

    ("Networking", "network_plugin_mode",
     "Network plugin mode when using Azure CNI.",
     "overlay = Recommended. Separates pod IPs from VNet IPs.",
     "overlay"),

    ("Networking", "network_dataplane",
     "Network dataplane technology.",
     "cilium = eBPF-based (better performance, network policies).\nazure = Standard Azure networking.",
     "azure"),

    ("Networking", "service_cidr",
     "CIDR for Kubernetes services. Must not overlap with any VNet ranges.",
     "CIDR notation. E.g.: 172.16.0.0/16",
     "172.16.0.0/16"),

    ("Networking", "dns_service_ip",
     "IP for the Kubernetes DNS service. Must be within service_cidr.",
     "IP address. E.g.: 172.16.0.10",
     "172.16.0.10"),

    ("", "SECURITY", "", "", ""),

    ("Security", "acr_sku",
     "Azure Container Registry SKU. Premium required for private endpoints and geo-replication.",
     "Premium (recommended) | Standard | Basic",
     "Premium"),

    ("Security", "acr_zone_redundancy",
     "Enable zone redundancy for ACR. Premium SKU only.",
     "true | false",
     "true"),

    ("Security", "key_vault_purge_protection",
     "Enable purge protection on Key Vault. Prevents permanent deletion.",
     "true (recommended for production) | false",
     "true"),

    ("Security", "key_vault_soft_delete_days",
     "Number of days to retain soft-deleted Key Vault items.",
     "7 - 90 days.",
     "30"),

    ("", "APPLICATION GATEWAY WAF", "", "", ""),

    ("App Gateway", "app_gateway_sku",
     "Application Gateway SKU.",
     "WAF_v2 (recommended — includes Web Application Firewall).\nStandard_v2 (no WAF).",
     "WAF_v2"),

    ("App Gateway", "app_gateway_min_capacity",
     "Minimum autoscale capacity for Application Gateway.",
     "Integer >= 1.",
     "1"),

    ("App Gateway", "app_gateway_max_capacity",
     "Maximum autoscale capacity for Application Gateway.",
     "Integer. Set based on expected traffic.",
     "10"),

    ("App Gateway", "waf_rule_set_type",
     "WAF managed rule set type.",
     "OWASP (standard web protection rules).",
     "OWASP"),

    ("App Gateway", "waf_rule_set_version",
     "WAF managed rule set version.",
     "3.2 (latest recommended) | 3.1 | 3.0",
     "3.2"),

    ("", "MONITORING", "", "", ""),

    ("Monitoring", "log_analytics_retention_days",
     "Log retention period in Log Analytics workspace.",
     "30 - 730 days. Longer retention increases cost.",
     "30"),

    ("Monitoring", "grafana_sku",
     "Azure Managed Grafana SKU.",
     "Standard (includes all features, 10 users free).",
     "Standard"),

    ("", "AKS ADVANCED", "", "", ""),

    ("AKS", "auto_upgrade_channel",
     "AKS auto-upgrade channel for Kubernetes patches.",
     "patch = Auto-apply patch versions (e.g., 1.31.1 → 1.31.2).\nstable = Auto-apply stable versions.\nnone = Manual upgrades only.",
     "patch"),

    ("AKS", "image_cleaner_enabled",
     "Enable Image Cleaner to remove unused container images from nodes.",
     "true | false",
     "true"),

    ("AKS", "image_cleaner_interval_hours",
     "How often Image Cleaner runs (in hours).",
     "Integer. E.g.: 48, 24, 168",
     "48"),

    ("AKS", "azure_policy_enabled",
     "Enable Azure Policy addon for AKS governance.",
     "true (recommended) | false",
     "true"),

    ("AKS", "workload_identity_enabled",
     "Enable Workload Identity for pod-level Azure authentication.",
     "true (recommended — eliminates stored credentials) | false",
     "true"),

    ("AKS", "oidc_issuer_enabled",
     "Enable OIDC issuer for federated identity scenarios.",
     "true (required for Workload Identity) | false",
     "true"),
]

row2 = 5
for d in options_data:
    cat, setting, description, opts, default = d

    if cat == "":
        ws2.cell(row=row2, column=1, value="")
        ws2.merge_cells(start_row=row2, start_column=2, end_row=row2, end_column=6)
        ws2.cell(row=row2, column=2, value=setting)
        style_section_row(ws2, row2, 6)
    else:
        ws2.cell(row=row2, column=1, value=cat)
        ws2.cell(row=row2, column=2, value=setting)
        ws2.cell(row=row2, column=3, value=description)
        ws2.cell(row=row2, column=4, value=opts)
        ws2.cell(row=row2, column=5, value=default)
        ws2.cell(row=row2, column=6, value="")
        style_data_row(ws2, row2, 6, is_input_col=6)

    row2 += 1

# Add dropdowns for boolean fields in tab 2
for r in range(5, row2):
    setting_val = ws2.cell(row=r, column=2).value
    if setting_val in ("acr_zone_redundancy", "key_vault_purge_protection",
                       "image_cleaner_enabled", "azure_policy_enabled",
                       "workload_identity_enabled", "oidc_issuer_enabled"):
        dv = DataValidation(type="list", formula1='"true,false"', allow_blank=True)
        ws2.add_data_validation(dv)
        dv.add(ws2.cell(row=r, column=6))

    if setting_val == "system_node_pool_os_disk_type" or setting_val == "user_node_pool_os_disk_type":
        dv = DataValidation(type="list", formula1='"Ephemeral,Managed"', allow_blank=True)
        ws2.add_data_validation(dv)
        dv.add(ws2.cell(row=r, column=6))

    if setting_val == "acr_sku":
        dv = DataValidation(type="list", formula1='"Premium,Standard,Basic"', allow_blank=True)
        ws2.add_data_validation(dv)
        dv.add(ws2.cell(row=r, column=6))

    if setting_val == "app_gateway_sku":
        dv = DataValidation(type="list", formula1='"WAF_v2,Standard_v2"', allow_blank=True)
        ws2.add_data_validation(dv)
        dv.add(ws2.cell(row=r, column=6))

    if setting_val == "auto_upgrade_channel":
        dv = DataValidation(type="list", formula1='"patch,stable,none"', allow_blank=True)
        ws2.add_data_validation(dv)
        dv.add(ws2.cell(row=r, column=6))


# ============================================================================
# TAB 3: Instructions
# ============================================================================
ws3 = wb.create_sheet("Instructions")

ws3.column_dimensions["A"].width = 80

instructions = [
    ("AKS Application Landing Zone Accelerator - Planning Checklist", title_font),
    ("", normal_font),
    ("This workbook helps you plan your AKS Application Landing Zone deployment.", normal_font),
    ("It mirrors the Azure Landing Zone Accelerator Phase 0 planning process.", normal_font),
    ("", normal_font),
    ("HOW TO USE THIS WORKBOOK", section_font),
    ("", normal_font),
    ("1. Start with the 'Accelerator - Bootstrap' tab.", normal_font),
    ("   Fill in the yellow 'Your Value' column for each decision.", normal_font),
    ("   Each decision number maps to a decision in config/inputs.yaml.", normal_font),
    ("", normal_font),
    ("2. Then go to the 'Accelerator - AKS Landing Zone' tab.", normal_font),
    ("   Review and customize the AKS-specific settings.", normal_font),
    ("   These map to settings in config/aks-landing-zone.tfvars.", normal_font),
    ("", normal_font),
    ("3. Use your completed checklist when running the bootstrap:", normal_font),
    ("   - Interactive mode: Use the values as reference while prompted", normal_font),
    ("   - Advanced mode: Copy values directly into config/inputs.yaml", normal_font),
    ("", normal_font),
    ("DEPLOYMENT PHASES", section_font),
    ("", normal_font),
    ("Phase 0 - Planning (this checklist)", normal_font),
    ("  Choose bootstrapping options, AKS scenario, and customization options.", normal_font),
    ("", normal_font),
    ("Phase 1 - Prerequisites", normal_font),
    ("  - Azure CLI login (az login)", normal_font),
    ("  - GitHub PATs set as environment variables", normal_font),
    ("  - Entra ID admin group created for AKS cluster access", normal_font),
    ("  - Subscriptions available (AKS landing zone + connectivity)", normal_font),
    ("", normal_font),
    ("Phase 2 - Bootstrap", normal_font),
    ("  Run: .\\bootstrap\\Deploy-AKSLandingZone.ps1", normal_font),
    ("  Or:  .\\bootstrap\\Deploy-AKSLandingZone.ps1 -InputConfigPath .\\config\\inputs.yaml", normal_font),
    ("", normal_font),
    ("Phase 3 - Run", normal_font),
    ("  Create PR → CI runs plan → Merge → CD runs plan → Approve → Apply", normal_font),
    ("", normal_font),
    ("REQUIRED GITHUB PAT SCOPES", section_font),
    ("", normal_font),
    ("github_personal_access_token:", normal_font),
    ("  - repo (Full control of private repositories)", normal_font),
    ("  - admin:org → Members (Read and Write)", normal_font),
    ("  - workflow (Update GitHub Action workflows)", normal_font),
    ("", normal_font),
    ("github_runners_personal_access_token (only if use_self_hosted_runners = true):", normal_font),
    ("  - admin:org (Full control of orgs and teams)", normal_font),
    ("", normal_font),
    ("NAMING CONVENTION", section_font),
    ("", normal_font),
    ("Bootstrap resources are named: {service_name}-{environment_name}-{location_shortcode}-{postfix}", normal_font),
    ("Example: aksapplz-prod-sc-001", normal_font),
    ("", normal_font),
    ("Resource Group:      rg-aksapplz-prod-sc-001", normal_font),
    ("Storage Account:     staksapplzprodsc001", normal_font),
    ("Managed Identity:    id-aksapplz-prod-sc-001", normal_font),
    ("GitHub Repository:   aksapplz-prod", normal_font),
    ("Templates Repo:      aksapplz-prod-templates", normal_font),
    ("GitHub Team:          aksapplz-prod-approvers", normal_font),
    ("Plan Environment:    aksapplz-plan", normal_font),
    ("Apply Environment:   aksapplz-apply", normal_font),
]

for i, (text, font) in enumerate(instructions, 1):
    cell = ws3.cell(row=i, column=1, value=text)
    cell.font = font
    cell.alignment = Alignment(wrap_text=True, vertical="top")

# Move Instructions tab to front
wb.move_sheet("Instructions", offset=-2)

# ============================================================================
# Save
# ============================================================================
output_path = r"c:\Users\alibengtsson\aksapplz\config\checklist.xlsx"
wb.save(output_path)
print(f"Checklist saved to: {output_path}")
