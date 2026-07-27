# Cluster autoscaler tuning

The AKS **cluster autoscaler** adds and removes nodes so your node pools match pending
pod demand. Its behaviour is controlled by a cluster-wide **autoscaler profile** — a set of
thresholds and timers that trade **scale-down aggressiveness (cost)** against **headroom and
stability (performance)**.

!!! info "The accelerator keeps the native AKS defaults on purpose"
    We do **not** ship an opinionated autoscaler profile. The profile is **cluster-wide**
    (it affects the system pool too), and the right values are **workload-specific** — the
    same settings that save money on a steady web app cause disruptive node churn on a
    bursty batch platform. So the accelerator leaves the profile unset (native AKS defaults)
    and **exposes it as an opt-in variable** for you to tune when — and only when — your
    workload calls for it.

This mirrors Microsoft's own guidance: fine-tuning the profile is a deliberate,
per-workload performance-versus-cost decision, not a default.
See [Optimizing the cluster autoscaler profile](https://learn.microsoft.com/azure/aks/cluster-autoscaler-overview#optimizing-the-cluster-autoscaler-profile).

## When should you tune it?

Consider tuning **after** your workload has a stable baseline, typically when:

- **Azure Advisor** raises a cost recommendation for underused AKS nodes.
- Nodes stay half-empty for long periods before scaling down (wasted spend).
- Conversely, scale-up is too slow for a bursty/batch workload and pods sit `Pending`.

If none of these apply, **leave it unset** — the defaults are a sensible starting point.

## The trade-off at a glance

| You want… | Push these direction |
|---|---|
| **Lower cost** (drain idle nodes faster) | shorter `scale_down_unneeded_time`, shorter `scale_down_delay_after_add`, **higher** `scale_down_utilization_threshold`, larger `max_empty_bulk_delete` |
| **More performance / stability** (keep headroom) | longer `scale_down_unneeded_time`, longer `scale_down_delay_after_add`, lower `scale_down_utilization_threshold` |

The **risk** of an aggressive cost profile is **node thrash**: nodes are removed quickly, then
must be re-provisioned moments later, causing pod rescheduling disruption and cold-start latency.
Because the profile is cluster-wide, overly aggressive values can also destabilise the system pool.

## AKS defaults (what you get when unset)

| Parameter | Default |
|---|---|
| `scan_interval` | `10s` |
| `scale_down_delay_after_add` | `10m` |
| `scale_down_delay_after_delete` | scan interval |
| `scale_down_delay_after_failure` | `3m` |
| `scale_down_unneeded_time` | `10m` |
| `scale_down_unready_time` | `20m` |
| `scale_down_utilization_threshold` | `0.5` |
| `max_graceful_termination_sec` | `600` |
| `max_node_provision_time` | `15m` |
| `max_empty_bulk_delete` | `10` |
| `ok_total_unready_count` | `3` |
| `max_total_unready_percentage` | `45` |
| `new_pod_scale_up_delay` | `0s` |
| `expander` | `random` |
| `skip_nodes_with_local_storage` | `true` |
| `skip_nodes_with_system_pods` | `true` |

## How to tune it

The profile is exposed as the Terraform variable `auto_scaler_profile`. It defaults to
`null` (native AKS defaults). Set **only** the keys you want to override in your workload's
`*.tfvars` — everything you omit falls back to the AKS default above. The change is applied
on the next `Deploy-AKSLandingZone` run (or `terraform apply`).

=== "Optimize for cost"

    ```hcl
    # Drain idle nodes faster and pack workloads tighter.
    # Best for steady-state workloads that tolerate slightly slower scale-up.
    auto_scaler_profile = {
      expander                         = "least-waste"
      scale_down_unneeded_time         = "5m"
      scale_down_delay_after_add       = "5m"
      scale_down_utilization_threshold = "0.6"
      max_empty_bulk_delete            = "50"
      skip_nodes_with_local_storage    = "false"
      ok_total_unready_count           = "5"
      max_total_unready_percentage     = "60"
    }
    ```

=== "Optimize for performance"

    ```hcl
    # Keep headroom and scale up quickly for bursty / latency-sensitive workloads.
    auto_scaler_profile = {
      expander                         = "random"
      scale_down_unneeded_time         = "15m"
      scale_down_delay_after_add       = "15m"
      scale_down_utilization_threshold = "0.4"
      max_graceful_termination_sec     = "600"
    }
    ```

=== "Keep defaults (recommended start)"

    ```hcl
    # Leave the variable unset (or explicitly null) to use native AKS defaults.
    # auto_scaler_profile = null
    ```

!!! warning "Validate cluster-wide impact"
    Because the profile applies to every node pool including the system pool, roll changes
    out to a non-production environment first and watch node count, pod eviction rate and
    scale-up latency before promoting them.

`expander` must be one of `least-waste`, `most-pods`, `priority`, or `random`
(the accelerator validates this at plan time).

## Reference

- [Cluster autoscaler overview](https://learn.microsoft.com/azure/aks/cluster-autoscaler-overview)
- [Optimizing the cluster autoscaler profile (Microsoft's example profiles)](https://learn.microsoft.com/azure/aks/cluster-autoscaler-overview#optimizing-the-cluster-autoscaler-profile)
