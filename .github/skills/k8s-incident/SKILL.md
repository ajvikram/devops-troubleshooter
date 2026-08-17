---
name: k8s-incident
description: >
  Systematic triage of Kubernetes workload failures: CrashLoopBackOff,
  ImagePullBackOff, OOMKilled, probe Unhealthy, CreateContainerConfigError,
  Pending/FailedScheduling, node pressure. Use when containers are crashing,
  not starting, or not becoming Ready. For 502s with Running pods, also use service-path.
---

# Kubernetes Incident Triage

Follow this procedure to investigate a failing workload. Gather evidence before
conclusions. Read-only MCP only. Feed results into the **`rca` skill** — this
playbook is evidence collection, not the RCA write-up.

**Running ≠ Ready.** A pod in `Running` with Ready=False is a probe/config problem;
use this skill plus **`service-path`**.

## 1. Establish context

```
Tool: configuration_contexts_list
```

Confirm kube context with the user.

## 2. List pods — all of them

```
Tool: pods_list_in_namespace
Args: namespace=<target>
```

Do not only query `status.phase!=Running`. Not-Ready Running pods would disappear.

| Symptom | What to look for |
|---------|-----------------|
| CrashLoopBackOff | High restart count, `waiting` reason `CrashLoopBackOff` |
| ImagePullBackOff | `ImagePullBackOff` / `ErrImagePull` |
| OOMKilled | lastState `OOMKilled`, exit 137 |
| Error / exit 1 | lastState terminated, check logs (config, panic, missing file) |
| Pending | FailedScheduling, PVC, affinity, taints — follow **`saturation`** |
| CreateContainerConfigError | missing ConfigMap/Secret/volume |
| Running + Ready False | readiness/startup probe — go to probes + `service-path` |

Record restart count, `startTime`, and **lastState** (reason, exit code, finishedAt).

## 3. Check events

```
Tool: events_list
Args: namespace=<target>, fieldSelector="type=Warning"
```

- `FailedScheduling` — CPU/memory, affinity, taints
- `FailedMount` / `FailedAttachVolume` — PVC or Secret
- `Unhealthy` — readiness or liveness probe
- `BackOff` — crash loop
- `Failed` — image pull
- `FailedCreate` / `CreateContainerConfigError` — missing refs

## 4. Logs (current and previous)

```
Tool: pods_log
Args: name=<pod>, namespace=<ns>, tail=200
```

If restart count > 0, always also:

```
Tool: pods_log
Args: name=<pod>, namespace=<ns>, previous=true, tail=200
```

Scan for stack traces, `connection refused`, `permission denied`, config parse errors,
`OOM` before kernel kill, probe-related 404s on the health path.

## 5. Exit codes (decode lastState)

| Exit | Typical meaning |
|------|-----------------|
| 137 | SIGKILL — often OOM or liveness kill |
| 139 | SIGSEGV |
| 1 / 2 | Application error or bad config |
| 127 | Command/binary not found |
| 126 | Permission / not executable |

OOM vs liveness both can be 137: distinguish with `reason: OOMKilled` vs probe `Unhealthy` then restart.

## 6. Inspect the workload spec

```
Tool: resources_get
Args: apiVersion=apps/v1, kind=Deployment (or StatefulSet/DaemonSet/Job), name=<name>, namespace=<ns>
```

- **image** vs workspace chart
- **resources.requests / limits**
- **readinessProbe / livenessProbe / startupProbe** — port, path, delays
- **env / envFrom** — ConfigMaps and Secrets exist? (`resources_get` them; never print secret data)
- **volumeMounts** — PVCs Bound?
- **nodeSelector / tolerations / affinity**

## 7. Node health (Pending or eviction)

```
Tool: nodes_top
```

```
Tool: resources_get
Args: apiVersion=v1, kind=Node, name=<node>
```

NotReady, MemoryPressure, DiskPressure, PIDPressure, unschedulable.

## 8. Correlate with workspace code

Helm `Chart.yaml`, `values*.yaml`, `templates/deployment.yaml`. Flag image, probes, limits, env drift. Then `helm-drift` if a chart exists.

## 9. Hand off to RCA

Do **not** stop at "CrashLoopBackOff." Name the cause (OOM at limit, missing Secret, bad image tag, probe path). List hypotheses you rejected (e.g. not ImagePull because events show OOMKilled). Follow the **`rca`** output format.
