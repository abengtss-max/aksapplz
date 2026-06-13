# Planning checklist

Before you run `Deploy-AKSLandingZone`, fill in the planning workbook with your team. It lists
**every decision the wizard asks** — one yellow cell per prompt — so you can agree on names, network
ranges, scenario, topology, and add-ons up front instead of mid-deployment.

[:material-microsoft-excel: Download the checklist (.xlsx)](../assets/aks-landing-zone-checklist-v2.xlsx){ .md-button .md-button--primary download="aks-landing-zone-checklist.xlsx" }

## What's inside

| Tab | Use it for |
|---|---|
| **Bootstrap Decisions** | Everything the wizard prompts for: scenario, topology, global load balancer, subscriptions, hub & spoke networking (including the Application Gateway for Containers subnet), cluster settings, naming, runners, GitHub, and the add-on toggles. |
| **Advanced Cluster Settings** | Node pool sizes, in-cluster networking (service/pod CIDRs), upgrade channels, Application Gateway, and log retention. Most teams leave this tab alone — it's driven by the scenario you pick. |
| **How to use** | Step-by-step instructions, the GitHub token scopes you need, and the resource-naming pattern. |

## How to use it

1. Open the **Bootstrap Decisions** tab and fill in every yellow cell.
2. Pick a **scenario** first (row `0a`) — it sets sensible defaults for everything else.
3. Pick a **topology** (row `0c`):
    - `spoke` — peer to an existing Azure Landing Zone hub.
    - `hub_and_spoke` — greenfield; this run also creates a new hub VNet (+ optional Azure Firewall).
    - `standalone` — no hub, NAT-gateway egress only (skips Decisions 3 & 4).
4. For **multi-region** scenarios, choose a global load balancer (row `0d`): `front_door` or `traffic_manager`.
5. Decide your **add-ons** (section 11), including `enable_agc` for [Application Gateway for Containers](../reference/configuration.md).

!!! warning "Don't put GitHub tokens in the workbook"
    The wizard prompts for tokens with hidden input. Keep secrets out of the spreadsheet.

When you're done, the values map 1:1 to the wizard prompts and to `config/inputs.yaml`. Keep the
filled-in workbook for your records.

---

Next: **[Quickstart](quickstart.md)**.
