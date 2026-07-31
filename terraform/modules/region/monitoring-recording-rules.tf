# -----------------------------------------------------------------------------
# Region module - Managed Prometheus default recording rules
#
# Azure Managed Prometheus does NOT create any recording rules on its own. The
# out-of-the-box Grafana dashboards that ship with Azure Managed Grafana
# (the "Kubernetes / Compute Resources / *" kubernetes-mixin dashboards) are
# built on pre-aggregated recording-rule metrics such as
#   node_namespace_pod_container:container_cpu_usage_seconds_total:sum_irate,
#   cluster:namespace:pod_cpu:active:kube_pod_container_resource_requests,
#   :node_memory_MemAvailable_bytes:sum, cluster:node_cpu:ratio_rate5m, ...
# Without these rule groups those dashboards render "No data" even though the
# raw metrics are being ingested.
#
# These two groups are the Linux Node + Kubernetes recording rules that the
# Azure portal "Recording rules" experience deploys, mirrored from
#   github.com/Azure/prometheus-collector
#     GeneratedMonitoringArtifacts/Default/DefaultRecordingRules.json
# (the Windows groups are omitted; they ship disabled and there are no Windows
# node pools in this accelerator).
# -----------------------------------------------------------------------------

locals {
  # Node-level recording rules (job="node" / node-exporter series).
  node_recording_rules = [
    {
      record = "instance:node_num_cpu:sum"
      expression = trimspace(<<-EOT
        count without (cpu, mode) (node_cpu_seconds_total{job="node",mode="idle"})
      EOT
      )
      labels = null
    },
    {
      record = "instance:node_cpu_utilisation:rate5m"
      expression = trimspace(<<-EOT
        1 - avg without (cpu) (sum without (mode) (rate(node_cpu_seconds_total{job="node", mode=~"idle|iowait|steal"}[5m])))
      EOT
      )
      labels = null
    },
    {
      record = "instance:node_load1_per_cpu:ratio"
      expression = trimspace(<<-EOT
        (node_load1{job="node"} / instance:node_num_cpu:sum{job="node"})
      EOT
      )
      labels = null
    },
    {
      record = "instance:node_memory_utilisation:ratio"
      expression = trimspace(<<-EOT
        1 - ((node_memory_MemAvailable_bytes{job="node"} or (node_memory_Buffers_bytes{job="node"} + node_memory_Cached_bytes{job="node"} + node_memory_MemFree_bytes{job="node"} + node_memory_Slab_bytes{job="node"})) / node_memory_MemTotal_bytes{job="node"})
      EOT
      )
      labels = null
    },
    {
      record = "instance:node_vmstat_pgmajfault:rate5m"
      expression = trimspace(<<-EOT
        rate(node_vmstat_pgmajfault{job="node"}[5m])
      EOT
      )
      labels = null
    },
    {
      record = "instance_device:node_disk_io_time_seconds:rate5m"
      expression = trimspace(<<-EOT
        rate(node_disk_io_time_seconds_total{job="node", device!=""}[5m])
      EOT
      )
      labels = null
    },
    {
      record = "instance_device:node_disk_io_time_weighted_seconds:rate5m"
      expression = trimspace(<<-EOT
        rate(node_disk_io_time_weighted_seconds_total{job="node", device!=""}[5m])
      EOT
      )
      labels = null
    },
    {
      record = "instance:node_network_receive_bytes_excluding_lo:rate5m"
      expression = trimspace(<<-EOT
        sum without (device) (rate(node_network_receive_bytes_total{job="node", device!="lo"}[5m]))
      EOT
      )
      labels = null
    },
    {
      record = "instance:node_network_transmit_bytes_excluding_lo:rate5m"
      expression = trimspace(<<-EOT
        sum without (device) (rate(node_network_transmit_bytes_total{job="node", device!="lo"}[5m]))
      EOT
      )
      labels = null
    },
    {
      record = "instance:node_network_receive_drop_excluding_lo:rate5m"
      expression = trimspace(<<-EOT
        sum without (device) (rate(node_network_receive_drop_total{job="node", device!="lo"}[5m]))
      EOT
      )
      labels = null
    },
    {
      record = "instance:node_network_transmit_drop_excluding_lo:rate5m"
      expression = trimspace(<<-EOT
        sum without (device) (rate(node_network_transmit_drop_total{job="node", device!="lo"}[5m]))
      EOT
      )
      labels = null
    },
  ]

  # Kubernetes (kube-state-metrics + cAdvisor) recording rules consumed by the
  # "Kubernetes / Compute Resources" dashboards.
  kubernetes_recording_rules = [
    {
      record = "node_namespace_pod_container:container_cpu_usage_seconds_total:sum_irate"
      expression = trimspace(<<-EOT
        sum by (cluster, namespace, pod, container) (irate(container_cpu_usage_seconds_total{job="cadvisor", image!=""}[5m])) * on (cluster, namespace, pod) group_left(node) topk by (cluster, namespace, pod) (1, max by(cluster, namespace, pod, node) (kube_pod_info{node!=""}))
      EOT
      )
      labels = null
    },
    {
      record = "node_namespace_pod_container:container_memory_working_set_bytes"
      expression = trimspace(<<-EOT
        container_memory_working_set_bytes{job="cadvisor", image!=""} * on (namespace, pod) group_left(node) topk by(namespace, pod) (1, max by(namespace, pod, node) (kube_pod_info{node!=""}))
      EOT
      )
      labels = null
    },
    {
      record = "node_namespace_pod_container:container_memory_rss"
      expression = trimspace(<<-EOT
        container_memory_rss{job="cadvisor", image!=""} * on (namespace, pod) group_left(node) topk by(namespace, pod) (1, max by(namespace, pod, node) (kube_pod_info{node!=""}))
      EOT
      )
      labels = null
    },
    {
      record = "node_namespace_pod_container:container_memory_cache"
      expression = trimspace(<<-EOT
        container_memory_cache{job="cadvisor", image!=""} * on (namespace, pod) group_left(node) topk by(namespace, pod) (1, max by(namespace, pod, node) (kube_pod_info{node!=""}))
      EOT
      )
      labels = null
    },
    {
      record = "node_namespace_pod_container:container_memory_swap"
      expression = trimspace(<<-EOT
        container_memory_swap{job="cadvisor", image!=""} * on (namespace, pod) group_left(node) topk by(namespace, pod) (1, max by(namespace, pod, node) (kube_pod_info{node!=""}))
      EOT
      )
      labels = null
    },
    {
      record = "cluster:namespace:pod_memory:active:kube_pod_container_resource_requests"
      expression = trimspace(<<-EOT
        kube_pod_container_resource_requests{resource="memory",job="kube-state-metrics"} * on (namespace, pod, cluster) group_left() max by (namespace, pod, cluster) ((kube_pod_status_phase{phase=~"Pending|Running"} == 1))
      EOT
      )
      labels = null
    },
    {
      record = "namespace_memory:kube_pod_container_resource_requests:sum"
      expression = trimspace(<<-EOT
        sum by (namespace, cluster) (sum by (namespace, pod, cluster) (max by (namespace, pod, container, cluster) (kube_pod_container_resource_requests{resource="memory",job="kube-state-metrics"}) * on(namespace, pod, cluster) group_left() max by (namespace, pod, cluster) (kube_pod_status_phase{phase=~"Pending|Running"} == 1)))
      EOT
      )
      labels = null
    },
    {
      record = "cluster:namespace:pod_cpu:active:kube_pod_container_resource_requests"
      expression = trimspace(<<-EOT
        kube_pod_container_resource_requests{resource="cpu",job="kube-state-metrics"} * on (namespace, pod, cluster) group_left() max by (namespace, pod, cluster) ((kube_pod_status_phase{phase=~"Pending|Running"} == 1))
      EOT
      )
      labels = null
    },
    {
      record = "namespace_cpu:kube_pod_container_resource_requests:sum"
      expression = trimspace(<<-EOT
        sum by (namespace, cluster) (sum by (namespace, pod, cluster) (max by (namespace, pod, container, cluster) (kube_pod_container_resource_requests{resource="cpu",job="kube-state-metrics"}) * on(namespace, pod, cluster) group_left() max by (namespace, pod, cluster) (kube_pod_status_phase{phase=~"Pending|Running"} == 1)))
      EOT
      )
      labels = null
    },
    {
      record = "cluster:namespace:pod_memory:active:kube_pod_container_resource_limits"
      expression = trimspace(<<-EOT
        kube_pod_container_resource_limits{resource="memory",job="kube-state-metrics"} * on (namespace, pod, cluster) group_left() max by (namespace, pod, cluster) ((kube_pod_status_phase{phase=~"Pending|Running"} == 1))
      EOT
      )
      labels = null
    },
    {
      record = "namespace_memory:kube_pod_container_resource_limits:sum"
      expression = trimspace(<<-EOT
        sum by (namespace, cluster) (sum by (namespace, pod, cluster) (max by (namespace, pod, container, cluster) (kube_pod_container_resource_limits{resource="memory",job="kube-state-metrics"}) * on(namespace, pod, cluster) group_left() max by (namespace, pod, cluster) (kube_pod_status_phase{phase=~"Pending|Running"} == 1)))
      EOT
      )
      labels = null
    },
    {
      record = "cluster:namespace:pod_cpu:active:kube_pod_container_resource_limits"
      expression = trimspace(<<-EOT
        kube_pod_container_resource_limits{resource="cpu",job="kube-state-metrics"} * on (namespace, pod, cluster) group_left() max by (namespace, pod, cluster) ((kube_pod_status_phase{phase=~"Pending|Running"} == 1))
      EOT
      )
      labels = null
    },
    {
      record = "namespace_cpu:kube_pod_container_resource_limits:sum"
      expression = trimspace(<<-EOT
        sum by (namespace, cluster) (sum by (namespace, pod, cluster) (max by (namespace, pod, container, cluster) (kube_pod_container_resource_limits{resource="cpu",job="kube-state-metrics"}) * on(namespace, pod, cluster) group_left() max by (namespace, pod, cluster) (kube_pod_status_phase{phase=~"Pending|Running"} == 1)))
      EOT
      )
      labels = null
    },
    {
      record = "namespace_workload_pod:kube_pod_owner:relabel"
      expression = trimspace(<<-EOT
        max by (cluster, namespace, workload, pod) (label_replace(label_replace(kube_pod_owner{job="kube-state-metrics", owner_kind="ReplicaSet"}, "replicaset", "$1", "owner_name", "(.*)") * on(replicaset, namespace) group_left(owner_name) topk by(replicaset, namespace) (1, max by (replicaset, namespace, owner_name) (kube_replicaset_owner{job="kube-state-metrics"})), "workload", "$1", "owner_name", "(.*)"))
      EOT
      )
      labels = { workload_type = "deployment" }
    },
    {
      record = "namespace_workload_pod:kube_pod_owner:relabel"
      expression = trimspace(<<-EOT
        max by (cluster, namespace, workload, pod) (label_replace(kube_pod_owner{job="kube-state-metrics", owner_kind="DaemonSet"}, "workload", "$1", "owner_name", "(.*)"))
      EOT
      )
      labels = { workload_type = "daemonset" }
    },
    {
      record = "namespace_workload_pod:kube_pod_owner:relabel"
      expression = trimspace(<<-EOT
        max by (cluster, namespace, workload, pod) (label_replace(kube_pod_owner{job="kube-state-metrics", owner_kind="StatefulSet"}, "workload", "$1", "owner_name", "(.*)"))
      EOT
      )
      labels = { workload_type = "statefulset" }
    },
    {
      record = "namespace_workload_pod:kube_pod_owner:relabel"
      expression = trimspace(<<-EOT
        max by (cluster, namespace, workload, pod) (label_replace(kube_pod_owner{job="kube-state-metrics", owner_kind="Job"}, "workload", "$1", "owner_name", "(.*)"))
      EOT
      )
      labels = { workload_type = "job" }
    },
    {
      record = ":node_memory_MemAvailable_bytes:sum"
      expression = trimspace(<<-EOT
        sum(node_memory_MemAvailable_bytes{job="node"} or (node_memory_Buffers_bytes{job="node"} + node_memory_Cached_bytes{job="node"} + node_memory_MemFree_bytes{job="node"} + node_memory_Slab_bytes{job="node"})) by (cluster)
      EOT
      )
      labels = null
    },
    {
      record = "cluster:node_cpu:ratio_rate5m"
      expression = trimspace(<<-EOT
        sum(rate(node_cpu_seconds_total{job="node",mode!="idle",mode!="iowait",mode!="steal"}[5m])) by (cluster) / count(sum(node_cpu_seconds_total{job="node"}) by (cluster, instance, cpu)) by (cluster)
      EOT
      )
      labels = null
    },
  ]
}

# Node recording rules rule group (scoped to the AMW; associated with the AKS
# cluster via cluster_name for the portal Recording rules view).
resource "azurerm_monitor_alert_prometheus_rule_group" "node_recording" {
  count = var.enable_managed_prometheus ? 1 : 0

  name                = "NodeRecordingRulesRuleGroup-${local.aks_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  cluster_name        = local.aks_name
  scopes              = [azurerm_monitor_workspace.main[0].id]
  rule_group_enabled  = true
  interval            = "PT1M"
  tags                = local.default_tags

  dynamic "rule" {
    for_each = local.node_recording_rules
    content {
      record     = rule.value.record
      expression = rule.value.expression
      labels     = rule.value.labels
    }
  }
}

# Kubernetes recording rules rule group.
resource "azurerm_monitor_alert_prometheus_rule_group" "kubernetes_recording" {
  count = var.enable_managed_prometheus ? 1 : 0

  name                = "KubernetesRecordingRulesRuleGroup-${local.aks_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  cluster_name        = local.aks_name
  scopes              = [azurerm_monitor_workspace.main[0].id]
  rule_group_enabled  = true
  interval            = "PT1M"
  tags                = local.default_tags

  dynamic "rule" {
    for_each = local.kubernetes_recording_rules
    content {
      record     = rule.value.record
      expression = rule.value.expression
      labels     = rule.value.labels
    }
  }
}
