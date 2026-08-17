---
name: alert-intake
description: >
  Start an RCA from a pasted Prometheus / Alertmanager / Grafana / PagerDuty
  alert. Extract namespace, workload, and window; then scan and investigate.
  Use when the user pastes an alert JSON, screenshot text, or Slack page.
---

# Alert intake

Borrowed from HolmesGPT / Klarsicht: the ticket often **is** the alert, not a
pod name. Parse what they pasted, then investigate live. The alert is a
**symptom + timestamp**, never the root cause.

Read-only. Do not silence, acknowledge, or resolve the alert.

## 1. Extract fields

From JSON, YAML, Slack paste, or Grafana screenshot text, record:

| Field | Where it usually lives | If missing |
|-------|------------------------|------------|
| Alert name | `alertname`, `labels.alertname`, title | Ask; do not invent |
| Namespace | `namespace`, `labels.namespace` | **`clarify`**: ask, or scan if they named the cluster and one app namespace |
| Workload / pod | `pod`, `deployment`, `labels.pod` | Run `cluster-scan` on the namespace |
| Cluster / context | `cluster`, `labels.cluster` | **`clarify`** + `configuration_contexts_list`. Blocking if 2+ match |
| Firing since | `startsAt`, `activeAt`, Grafana window | Timeline = **unknown start** until events |
| Severity | `severity`, `labels.severity` | Default to the user's urgency |
| PromQL / log query | `generatorURL`, panel query | Optional; use `observability` only if Grafana MCP is up |

Redact tokens, webhook URLs with secrets, and PagerDuty routing keys in output.

## 2. Classify the alert (hypothesis, not cause)

Map the **name** to a failure class you will test:

| Alert name pattern | Start with |
|--------------------|------------|
| `KubePodCrashLooping`, `CrashLoop*` | `k8s-incident` |
| `KubePodNotReady`, `ContainerWaiting` | `k8s-incident` + `service-path` |
| `KubeDeploymentReplicasMismatch` | `saturation` + `k8s-incident` |
| `KubePersistentVolume*`, `Quota*` | `saturation` |
| `Ingress*`, `Certificate*`, `TLS*` | `service-path` then `ingress-tls` |
| `TargetDown`, `5xx`, `HighLatency` | `service-path`; Grafana if available |
| `Postgres*`, `Mysql*`, `Mongo*` | `k8s-incident` logs, then `db-evidence` |

If the name is unknown, run `cluster-scan` on the namespace and let findings
drive the class.

## 3. Investigate live (do not trust the alert body)

Alerts lag and misfire. Always:

1. Confirm kube context with the user (`kube-context`). Do not assume `current-context`.
2. `cluster-scan` the namespace (or the named pod if unique).
3. Build a timeline from **cluster events / Helm / git**, not only `startsAt`.
4. Follow `rca`. The root cause must cite cluster or chart evidence.
5. If Grafana MCP is running, use `observability` to confirm the window — metrics
   support the timeline; they do not replace logs and specs.

Reject the alert as the cause: e.g. `KubePodCrashLooping` is the **class
pointer**, the cause is `CONFIG_ERROR: missing PAYMENTS_DSN` (or whatever
evidence shows).

## 4. Recommendations

Same as `rca`: durable git/chart/TLS/quota fixes. Do not "ack the alert" as a
fix. If the alert is a false positive, recommend the **rule/threshold change**
as a separate item, with evidence that the workload is healthy.
