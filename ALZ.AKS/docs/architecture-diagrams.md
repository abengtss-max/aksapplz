# Architecture Diagrams — Per Topology

Visual reference for the three topologies supported by `Deploy-AKSLandingZone`
v1.4.0-rc1. For per-scenario tfvars details see
[scenarios-and-options.md](scenarios-and-options.md).

---

## Topology 1: `standalone`

Cheapest path — no hub, NAT egress only, public API server (dev-friendly default).

Scenarios: **01**, **04**, **07**, **11**

```mermaid
flowchart LR
    subgraph subWl["Workload subscription"]
        subgraph rgwl["rg-<workload>-&lt;env&gt;-&lt;region&gt;"]
            vnetwl["VNet<br/>10.10.0.0/16"]
            subgraph snets["subnets"]
                snSys["aks-system-nodes<br/>10.10.0.0/24"]
                snUser["aks-user-nodes<br/>10.10.16.0/22"]
                snApi["aks-api-server<br/>10.10.20.0/28"]
                snAg["app-gateway<br/>10.10.21.0/24"]
                snPe["private-endpoints<br/>10.10.22.0/24"]
            end
            aks["AKS cluster<br/>(public API)"]
            ag["App Gateway"]
            acr["ACR"]
            kv["Key Vault"]
            la["Log Analytics + Prometheus"]
            graf["Managed Grafana"]
            nat["NAT Gateway<br/>+ Public IP"]
        end
    end
    Internet((Internet))
    aks -- node pools --> snSys
    aks -- node pools --> snUser
    aks -- API VNet integ --> snApi
    aks -.acr pull (public).-> acr
    aks -.workload identity.-> kv
    ag --> snAg
    snSys -- egress --> nat
    snUser -- egress --> nat
    nat --> Internet
    Internet -.Authorized IPs.-> aks
    ag --> Internet
```

**Key properties**:
- `is_corp = false` (no private endpoints, no UDR, no private DNS zone)
- API server reachable from the public internet (gated by authorized IP ranges)
- Egress via NAT Gateway (predictable SNAT IP, no SNAT exhaustion)

---

## Topology 2: `spoke`

Brownfield — connects to an **existing** ALZ hub VNet, forced egress via hub firewall, private cluster.

Scenarios: **02**, **05**, **08**, **12**

```mermaid
flowchart LR
    subgraph subConn["Connectivity subscription"]
        subgraph rghub["rg-hub-&lt;region&gt; (existing)"]
            vnethub["Hub VNet"]
            afw["Azure Firewall<br/>10.0.0.4"]
            azfwSn["AzureFirewallSubnet"]
        end
    end
    subgraph subWl["Workload subscription"]
        subgraph rgwl["rg-<workload>-&lt;env&gt;-&lt;region&gt;"]
            vnetwl["Spoke VNet<br/>10.10.0.0/16"]
            udr["Route Table<br/>0.0.0.0/0 → AFW"]
            aks["AKS cluster<br/>(PRIVATE API)"]
            ag["App Gateway"]
            acr["ACR + Private Endpoint"]
            kv["Key Vault + Private Endpoint"]
            pdns["Private DNS Zones<br/>(privatelink.*)"]
        end
    end
    Internet((Internet))
    vnetwl -. peering .- vnethub
    aks --> vnetwl
    vnetwl --> udr
    udr --> afw
    afw -- egress --> Internet
    aks -. private endpoint .-> acr
    aks -. private endpoint .-> kv
    pdns -. resolves .- acr
    pdns -. resolves .- kv
```

**Key properties**:
- `is_corp = true` (private endpoints, UDR, private DNS, private cluster)
- Hub already exists in `connectivity_subscription_id`
- All egress forced through the hub firewall (compliance / inspection)

---

## Topology 3: `hub_and_spoke`

Greenfield — wizard creates the **hub first**, then the spoke consumes hub outputs.

Scenarios: **03**, **06**, **09**, **10**

```mermaid
flowchart LR
    subgraph subConn["Connectivity subscription"]
        subgraph rghub["rg-hub-&lt;env&gt;-&lt;region&gt; (created by wizard)"]
            vnethub["Hub VNet<br/>10.0.0.0/16"]
            afw["Azure Firewall<br/>(Standard or Premium)"]
            azfwSn["AzureFirewallSubnet<br/>10.0.0.0/26"]
            afwpip["Firewall Public IP<br/>(zonal)"]
            afwpol["Firewall Policy<br/>(empty - users add rules)"]
        end
    end
    subgraph subWl["Workload subscription"]
        subgraph rgwl["rg-<workload>-&lt;env&gt;-&lt;region&gt;"]
            vnetwl["Spoke VNet<br/>10.10.0.0/16"]
            udr["Route Table<br/>0.0.0.0/0 → AFW"]
            aks["AKS cluster (PRIVATE API)"]
            ag["App Gateway"]
            acr["ACR + Private Endpoint"]
            kv["Key Vault + Private Endpoint"]
            pdns["Private DNS Zones"]
        end
    end
    Internet((Internet))
    Wizard{{Wizard<br/>Deploy-AKSLandingZone}}
    Wizard --1. apply hub--> rghub
    Wizard --2. capture outputs--> Wizard
    Wizard --3. render + apply spoke--> rgwl
    vnetwl -. peering .- vnethub
    udr --> afw
    afw --> afwpip
    afwpip --> Internet
```

**Key properties**:
- Two-phase apply: hub composition (separate state) then spoke
- Hub state lives in `bootstrap/alz/hub/terraform.tfstate.d/<env>/` (local for now; remote state migration planned post-v1.4)
- Firewall policy ships empty — operators must add rule collections post-deploy
- Same `is_corp = true` posture as `spoke`

---

## Multi-region overlay (scenarios 07-10)

Setting `secondary_location` adds a complete second regional stack to any of the
three topologies, plus an opt-in global load balancer in front of both regions:

```mermaid
flowchart TB
    user[(End users)]
    glb["Global LB (opt-in)<br/>Front Door OR Traffic Manager<br/>priority failover + health probes"]
    subgraph primary["Primary region (e.g. swedencentral)"]
        agw1["App Gateway (WAF)"]
        aks1["AKS cluster"]
        kv1["Key Vault"]
        agw1 --> aks1
    end
    subgraph secondary["Secondary region (e.g. westeurope)"]
        agw2["App Gateway (WAF)"]
        aks2["AKS cluster"]
        kv2["Key Vault"]
        agw2 --> aks2
    end
    subgraph shared["Shared"]
        acr["ACR (geo-replicated)"]
        fleet["Fleet Manager (opt-in)"]
    end
    user --> glb
    glb -->|priority 1| agw1
    glb -. failover .-> agw2
    aks1 -. pulls .-> acr
    aks2 -. pulls .-> acr
    fleet -. manages .-> aks1
    fleet -. manages .-> aks2
```

**Shipped**: both full regional stacks (AKS + App Gateway + VNet + Key Vault +
monitoring) from one run, Azure Front Door **or** Traffic Manager wired to both
App Gateways, Fleet Manager auto-joining both clusters, geo-replicated ACR, plus
Flux / VPA / Backup. Per-region availability zones via `availability_zones` and
`secondary_availability_zones`.

---

## Resource count per scenario (terraform plan)

| Scenario | Topology | Plan: to add |
|---|---|---|
| 01-standalone-baseline | standalone | ~28 |
| 02-spoke-baseline | spoke | ~42 |
| 03-hub-and-spoke-baseline | hub_and_spoke (spoke side only) | ~42 |
| 04-standalone-regulated | standalone | ~32 |
| 05-spoke-regulated | spoke | ~46 |
| 06-hub-and-spoke-regulated | hub_and_spoke | ~46 |
| 07-multi-region-baseline-standalone | standalone + multi-region | ~33 |
| 08-multi-region-baseline-spoke | spoke + multi-region | ~47 |
| 09-multi-region-baseline-hub-and-spoke | hub_and_spoke + multi-region | ~47 |
| 10-multi-region-regulated-hub-and-spoke | hub_and_spoke + multi-region + regulated | ~50 |
| 11-features-minimal-standalone | standalone (min) | ~18 |
| 12-features-maximal-spoke | spoke (max) | ~58 |

Numbers are indicative — exact counts depend on AVM module versions and may shift ±5 between releases.
