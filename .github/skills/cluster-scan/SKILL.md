---
name: cluster-scan
description: >
  Severity-tagged namespace (or cluster) health scan before diving into one
  workload. Use when the user is vague ("something is wrong in ns X"), pasted
  an alert without a pod name, or you need a findings table first. Read-only.
---

# Cluster / namespace scan

Borrowed from K8sGPT analyzers and kube-doctor `diagnose_namespace`: **scan
first, then investigate**. This skill produces a findings table. It is not the
RCA. After the table, pick the highest-severity items and follow `k8s-incident`,
`saturation`, `service-path`, or `ingress-tls`.

Do not mutate. Do not stop at "pods are CrashLoopBackOff" — that is a finding,
not a cause.

## When to run

- User did not name a single workload.
- User said "namespace X is unhealthy" / "look at dto-e2e".
- After `alert-intake`, to see whether the alert is one of several failures.
- Before declaring blast radius.

Skip a full scan only when the user named one workload **and** you already have
its pods, events, and Service in hand.

## 1. Scope

1. Follow **`kube-context`**. Pin `context=<picked>` on every later call.
2. If the user did not name a namespace, follow **`clarify`**: list non-system namespaces and ask. Do not assume `default` or scan every namespace unless they said to.
3. List pods in the namespace (all phases, not `!=Running`).
4. `events_list` Warning events in the namespace (recent only).
5. List Services; note those with **no Endpoints** / empty EndpointSlices. Do not `resources_get` every Service.
6. If Ingress/HTTPRoute objects exist, list **names + backend Service** only.
7. If events mention quota/PVC/HPA, `resources_get` **that** object (do not scale).

If the namespace is empty, say so and stop. Empty is not an incident.

## 2. Findings table (required)

Tag every row. One row per distinct issue, not per replica unless they differ.

| Sev | Object | Finding | Next skill |
|-----|--------|---------|------------|
| CRITICAL | `crashloop` Deploy | Restarts; lastState Error exit 1 | `k8s-incident` |
| CRITICAL | Service `mismatch` | Endpoints empty; selector ≠ pod labels | `service-path` |
| WARNING | Ingress `payments` | backend Service does not exist | `ingress-tls` |
| WARNING | Pod `pending-quota-*` | FailedScheduling / quota | `saturation` |
| INFO | Helm `dto-hist` | 2 revisions present | `change-correlation` |

Severity:

- **CRITICAL** — user traffic is failing now (crash, 0 Ready, empty Endpoints, missing TLS for HTTPS).
- **WARNING** — degraded or will fail on next scale/deploy (quota 3/3, probe flapping, OutOfSync).
- **INFO** — context only (Helm history exists, GitOps present, extra healthy workloads).

Do not invent rows. If MCP failed, one row: severity WARNING, finding "scan incomplete".

## 3. Choose where to dive

- Investigate **CRITICAL** first, then WARNING.
- If several CRITICALs share a deploy time, treat them as one incident with
  contributing factors — still one RCA, not three.
- Tell the user the scan result in 5–10 lines, then proceed into evidence
  collection. Do not dump raw `kubectl`-style YAML.

## 4. What this skill must not do

- Recommend restart as the scan output.
- Call remediator tools or apply YAML.
- Skip Service/Endpoints because every pod is `Running`.
