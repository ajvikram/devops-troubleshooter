---
name: observability
description: >
  Correlate Kubernetes incidents with Prometheus metrics and Loki logs via the
  Grafana MCP server. Use when investigating latency, error-rate spikes, OOM,
  CPU throttle, missing metrics, or when pod logs are insufficient.
---

# Observability (Prometheus + Loki via Grafana)

Use this skill only when the `grafana` MCP server is running. If Grafana tools
are missing, say so and continue with Kubernetes logs/events — do not invent
metric or log values.

This kit enables a **read-only, slim** Grafana MCP (`--disable-write` and
`--enabled-tools datasource,prometheus,loki`) so Copilot stays under the 128-tool cap.

## 1. Find datasources

```
Tool: grafana/list_datasources  (name may vary; use the grafana MCP datasource list tool)
```

Identify the Prometheus and Loki datasource UIDs. Confirm with the user if more
than one of each exists (prod vs staging).

If listing fails, the Grafana URL/token in `.vscode/mcp.env` is wrong, or the
MCP server was not started.

## 2. Prometheus — symptoms to queries

Prefer the live metric names from `list_prometheus_metric_names` over guessing.
Typical starters (replace labels with the workload under investigation):

| Question | PromQL sketch |
|----------|----------------|
| Is the pod restarting? | `increase(kube_pod_container_status_restarts_total{namespace="…",pod=~"app-.*"}[15m])` |
| OOM / memory vs limit | `container_memory_working_set_bytes{namespace="…"}` vs `kube_pod_container_resource_limits` |
| CPU throttle | `rate(container_cpu_cfs_throttled_seconds_total{namespace="…"}[5m])` |
| Error rate (RED) | `sum(rate(http_requests_total{status=~"5.."}[5m]))` |
| Saturation | queue depth, connection pool wait, disk fill |

Use `query_prometheus` with a bounded time range around the incident. Record
the query, datasource UID, and a short reading of the result as evidence.

## 3. Loki — logs beyond kubectl

Pod logs from `pods_log` are the first source. Use Loki when you need:

- Logs from crashed containers that have already rotated
- Multi-pod aggregation (all replicas)
- Cluster/node components (kubelet, ingress) not available via `pods_log`

```
Tool: query_loki_logs
LogQL sketch: {namespace="…", app="…"} |= "error" | limit 100
```

Stay under a small line limit. Redact tokens, passwords, and PII before quoting
log lines in the RCA.

Label discovery: `list_loki_label_names` / `list_loki_label_values` if the
stream selector is unknown.

## 4. Correlate with cluster evidence

Do not treat metrics as root cause by themselves. Tie them to:

- Kubernetes events (`events_list`)
- Container state (OOMKilled, CrashLoopBackOff)
- Helm/image drift from the workspace chart
- Database errors if the data layer is in play

Example: a memory graph that hits the limit **plus** `OOMKilled` in the pod
status is strong evidence; a CPU bump with healthy probes is usually not.

Feed metrics into the **`rca`** timeline and hypotheses. Metrics without events/specs
are not a root cause.

## 5. What you must never do

- Do not create/update Grafana dashboards, folders, incidents, or alert rules
  (write tools are disabled; do not try to work around that).
- Do not dump unbounded Loki results.
- Do not print `GRAFANA_SERVICE_ACCOUNT_TOKEN` or other secrets.
- Do not skip Kubernetes investigation just because Grafana is connected.
