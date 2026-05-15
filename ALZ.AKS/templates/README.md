# AKS Application Landing Zone

This repository contains the Terraform configuration for your AKS Application Landing Zone, deployed using the [ALZ.AKS Accelerator](https://github.com/Azure/ALZ-PowerShell-Module).

## What Was Deployed?

The accelerator bootstrapped a production-ready AKS environment with:

- **AKS Cluster** — Kubernetes cluster with system and user node pools on separate subnets
- **Spoke VNet** — Peered to your hub VNet with UDR through the hub firewall
- **Azure Container Registry** — Premium SKU with private endpoints (corp mode)
- **Azure Key Vault** — For secrets management with RBAC and purge protection
- **Log Analytics + Prometheus + Grafana** — Full observability stack
- **Application Gateway WAF v2** — Web application firewall (if enabled)
- **GitHub Actions CI/CD** — Automated plan/apply with approval gates

All infrastructure is managed as code. Changes go through Pull Requests.

---

## Quick Start (5 minutes)

### Step 1: Make a Change

```bash
# Clone this repository to your local machine
git clone https://github.com/<your-org>/<your-repo>.git
cd <your-repo>

# Create a new branch for your change
git checkout -b my-change

# Edit the configuration file with your text editor
# This is the ONLY file you need to edit for most changes
code aks-landing-zone.auto.tfvars
```

### Step 2: Open a Pull Request

```bash
# Save your changes, commit, and push
git add aks-landing-zone.auto.tfvars
git commit -m "Describe what you changed"
git push origin my-change
```

Then go to GitHub and click **"Create Pull Request"**. The CI pipeline will automatically run `terraform plan` and show you what will change.

### Step 3: Review and Merge

1. Check the **CI job output** in the Pull Request — it shows exactly what resources will be created, changed, or destroyed
2. If the plan looks correct, **merge the Pull Request**
3. The CD pipeline will run automatically:
   - First it runs `terraform plan` again
   - Then it **pauses and waits for your team's approval**
   - A team member from the approvers team must approve in the GitHub Environment screen
   - After approval, `terraform apply` runs and deploys the changes

> **Important:** You cannot push directly to `main`. All changes must go through a Pull Request. This ensures every change is reviewed, planned, and approved before deployment.

### Step 4: Verify

After the CD pipeline completes, verify the deployment:

```bash
# Check the workflow run status in GitHub Actions
# Or connect to your AKS cluster (see "Accessing Your AKS Cluster" below)
```

---

## Accessing Your AKS Cluster

### Prerequisites

Install these tools on your local machine:

```bash
# Install Azure CLI (if not already installed)
# Windows: winget install Microsoft.AzureCLI
# macOS: brew install azure-cli
# Linux: curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Install kubectl (the Kubernetes command-line tool)
az aks install-cli
```

### Connect to the Cluster

```bash
# 1. Log in to Azure with your Entra ID account
az login

# 2. Set the subscription where your AKS cluster is deployed
az account set --subscription "<your-aks-subscription-id>"

# 3. Download the AKS credentials to your local kubeconfig
#    Replace the resource group and cluster name with your actual values
#    (check the Terraform outputs or Azure Portal for exact names)
az aks get-credentials \
  --resource-group "rg-<workload>-<env>-<region>" \
  --name "aks-<workload>-<env>-<region>"

# 4. Verify the connection — you should see your cluster nodes
kubectl get nodes
```

> **Private Cluster Note:** If your cluster is private (corp landing zone), you must connect from a network that can reach the private API server. Options:
> - Connect via **VPN** or **ExpressRoute** to the hub VNet
> - Use a **jump box** (VM) in the hub or spoke VNet
> - Use **Azure Cloud Shell** with VNet integration
> - Use `az aks command invoke` to run commands without direct network access:
>   ```bash
>   az aks command invoke \
>     --resource-group "rg-<workload>-<env>-<region>" \
>     --name "aks-<workload>-<env>-<region>" \
>     --command "kubectl get nodes"
>   ```

### Your First Deployment to AKS

```bash
# Create a namespace for your application
kubectl create namespace my-app

# Deploy a simple test workload
kubectl run nginx --image=nginx --namespace=my-app

# Check that the pod is running
kubectl get pods -n my-app

# Expose it as a service (ClusterIP — internal only)
kubectl expose pod nginx --port=80 --namespace=my-app

# View all services
kubectl get svc -n my-app

# Clean up when done testing
kubectl delete namespace my-app
```

### Common Commands Reference

| What you want to do | Command |
|---------------------|---------|
| List all nodes | `kubectl get nodes` |
| List all pods | `kubectl get pods -A` |
| List all services | `kubectl get svc -A` |
| View cluster info | `kubectl cluster-info` |
| Check node resource usage | `kubectl top nodes` |
| Check pod resource usage | `kubectl top pods -A` |
| View pod logs | `kubectl logs <pod-name> -n <namespace>` |
| Describe a resource | `kubectl describe pod <pod-name> -n <namespace>` |

---

## How Deployments Work

```
  Developer          GitHub              Azure
  ─────────          ──────              ─────
  1. Create branch
  2. Edit tfvars
  3. Open PR ──────> CI runs plan
                     (automatic)
  4. Review plan
  5. Merge PR ─────> CD runs plan
                     ↓
                     Wait for approval
                     ↓
                     Team approves ───> terraform apply
                                        (resources deployed)
```

### Manual Deployment (workflow_dispatch)

You can also trigger deployments manually:

1. Go to **Actions** tab in GitHub
2. Select **02 AKS Landing Zone Continuous Delivery**
3. Click **Run workflow**
4. Select action: `apply` to deploy, or `destroy` to tear down
5. Approve when prompted

---

## Destroying Infrastructure

> **Warning:** This permanently deletes all AKS resources including your cluster, data, and networking.

**Option A: Via GitHub Actions (recommended)**
1. Go to **Actions** → **02 AKS Landing Zone Continuous Delivery**
2. Click **Run workflow** → Select `destroy`
3. Approve the destruction when prompted

**Option B: Via command line**
```bash
# Clone the repo and initialize Terraform
git clone https://github.com/<your-org>/<your-repo>.git
cd <your-repo>
terraform init \
  -backend-config="resource_group_name=<your-backend-rg>" \
  -backend-config="storage_account_name=<your-storage-account>" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=<your-state-key>"

# Preview what will be destroyed
terraform plan -destroy

# Destroy (requires confirmation)
terraform destroy
```

---

## What Can I Change?

Edit `aks-landing-zone.auto.tfvars` to change any of these settings:

| Setting | Example Change |
|---------|---------------|
| Node pool size | Change `min_count`, `max_count`, `node_count` |
| VM size | Change `vm_size` in `system_node_pool` or `user_node_pool` |
| Kubernetes version | Update `kubernetes_version` |
| Enable/disable features | Toggle `enable_*` variables (`true`/`false`) |
| Network addressing | Modify `subnet_address_prefixes` (requires destroy/recreate) |
| WAF mode | Change `waf_mode` between `"Detection"` and `"Prevention"` |
| Scaling limits | Adjust `app_gateway_min_capacity`, `app_gateway_max_capacity` |

> **Tip:** Do not edit `.tf` files unless you are adding new Terraform resources. All configuration goes in `aks-landing-zone.auto.tfvars`.

---

## Repository Structure

| File | Purpose | Edit? |
|------|---------|-------|
| `aks-landing-zone.auto.tfvars` | **Your configuration** — edit this to change settings | Yes |
| `variables.tf` | Variable definitions with descriptions and defaults | Rarely |
| `main.networking.tf` | Spoke VNet, subnets, NSGs, UDR, VNet peering | No |
| `main.aks.tf` | AKS cluster, node pools, features | No |
| `main.security.tf` | ACR and Key Vault | No |
| `main.monitoring.tf` | Log Analytics, Prometheus, Grafana | No |
| `main.appgateway.tf` | Application Gateway with WAF v2 | No |
| `terraform.tf` | Provider configuration and backend | No |
| `locals.tf` | Naming conventions and derived values | No |
| `outputs.tf` | Resource IDs and endpoints as outputs | No |
| `.github/workflows/` | CI/CD pipelines | No |

---

## Keeping Things Up-to-Date

### Kubernetes Version Upgrades
The cluster uses auto-upgrade channel `patch` — patch versions are applied automatically. For **minor version upgrades** (e.g., 1.30 → 1.31), update `kubernetes_version` in the tfvars file and open a PR.

### Module Updates
AVM module versions are pinned in `terraform.tf`. Check [Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/) periodically for updates. Update version constraints and test with `terraform plan` in a PR.

### Security
- **Never commit secrets** to this repository — all credentials use OIDC federated credentials
- **Review terraform plans carefully** before approving applies
- **Branch protection** prevents unauthorized changes to `main`
- Access is governed through **Entra ID groups** configured in `aks_admin_group_object_ids`

---

## Cost Management

Key cost drivers:
| Resource | Approximate Impact |
|----------|--------------------|
| AKS node pools | Largest — depends on VM size and count |
| Application Gateway WAF v2 | Fixed cost per gateway unit |
| Log Analytics | Based on data ingestion volume |
| ACR Premium | Fixed, higher for zone-redundant |
| Grafana Standard | Fixed monthly |

To reduce costs in non-production environments, consider:
- Reducing node pool `min_count` and `max_count`
- Using `Free` AKS SKU tier instead of `Standard`
- Disabling Grafana zone redundancy
- Disabling Application Gateway if not needed

---

## Getting Help

- [AKS Documentation](https://learn.microsoft.com/azure/aks/)
- [AKS Baseline Architecture](https://learn.microsoft.com/azure/architecture/reference-architectures/containers/aks/baseline-aks)
- [Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/)
- [Terraform AzureRM Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
