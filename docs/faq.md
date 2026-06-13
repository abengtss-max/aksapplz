# FAQ

### Do I need a GitHub organization?

Yes. The accelerator creates a workload repo with environments, OIDC, and protected approvals —
features that require a GitHub **organization**. Personal accounts aren't supported. A free org
works for evaluation (note: free orgs can only create public repos).

### Does it store any cloud secrets in GitHub?

No. The generated pipelines authenticate to Azure with **OIDC federated credentials** — there are
no long-lived cloud secrets in the repo. The only secret involved is the GitHub PAT used during
local bootstrap, which you can also source from Key Vault (`-PatFromKeyVault`) or avoid entirely
with `-OidcOnly`.

### How long does a deploy take?

Roughly **40–60 minutes** end-to-end: ~10–15 min local bootstrap, then ~25–40 min for AKS to
provision via the pipeline. `hub_and_spoke` and multi-region take longer.

### Can I deploy more than one environment?

Yes. Each environment has its own config file, Terraform state, and workload repo. Use
`-Environment <name>`. See [Advanced](advanced.md#multiple-environments).

### How do I pin a version for reproducible deploys?

Pass `-Release <tag>` to the install one-liner. See [Releases & versions](releases.md).

### What's the difference between `enable_app_gateway` and `enable_agc`?

`enable_app_gateway` deploys Application Gateway WAF v2 (a managed L7 gateway with a firewall).
`enable_agc` provisions the delegated subnet and NSG for **Application Gateway for Containers**
(ALB), whose data plane is managed by the in-cluster ALB Controller. They can coexist. See
[Topologies → Ingress](concepts/topologies.md#ingress-options).

### Is this the same as the Azure Landing Zone Accelerator?

It follows the same **pattern** (phased bootstrap, scenarios, OIDC pipelines) and is purpose-built
for **AKS application landing zones**. It complements, rather than replaces, the platform-level
[Azure Landing Zone Accelerator](https://azure.github.io/Azure-Landing-Zones/).

### How do I tear everything down?

```powershell
Deploy-AKSLandingZone -Environment <env> -Action destroy -AutoApprove
```

### Where do I report bugs or request features?

[Open an issue](https://github.com/abengtss-max/aksapplz/issues/new) on the repo.
