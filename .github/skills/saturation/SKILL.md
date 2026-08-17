---
name: saturation
description: >
  Identify why a workload cannot run or is starving: FailedScheduling, ResourceQuota,
  LimitRange, PVC Pending, HPA at max, PodDisruptionBudget, node NotReady or pressure.
  Use for Pending pods, evictions, “not enough CPU,” HPA stuck. Read-only.
---

# Saturation and scheduling

Use when pods are **Pending**, **evicted**, HPA is pegged, or the user reports
capacity/latency without a crash. CrashLoop still belongs in `k8s-incident` first.

Identification only. Never scale, drain, or delete PVCs.

## 1. Pending — read the event, then the object

`events_list` Warning in the namespace. Map `FailedScheduling` / `FailedCreate`
messages:

| Message fragment | Next object |
|------------------|-------------|
| `exceeded quota` | ResourceQuota in the namespace |
| `Insufficient cpu` / `memory` | Node allocatable vs requests; `nodes_top` |
| `didn't match Pod's node affinity` / taint | nodeSelector, tolerations, affinity on the pod |
| `persistentvolumeclaim ... not found` / unbound | PVC, StorageClass |
| `0/N nodes are available: ... pod has unbound immediate PersistentVolumeClaims` | PVC |
| `blocked by pod disruption budget` (during eviction) | PDB |

Then `resources_get` that object. Quote the quota **used/hard** or PVC
`status.phase`.

## 2. ResourceQuota and LimitRange

List ResourceQuotas in the namespace. For each, compare `status.used` vs
`status.hard` (pods, cpu, memory, pvcs).

If `used.pods == hard.pods`, a new replica **cannot schedule** — that is the
cause, not “the app is crashlooping” (the new pod may never start).

LimitRange: default/max memory vs the pod’s request/limit. A LimitRange max
below the chart’s request is a high-confidence config cause.

## 3. PVC and storage

For pods with volumes:

- PVC `status.phase` Pending vs Bound
- `spec.storageClassName` exists (`resources_get` StorageClass)
- Events `ProvisioningFailed`, `FailedBinding`

Pending PVC ⇒ pod stays Pending. Do not create volumes.

## 4. HPA (HorizontalPodAutoscaler)

`resources_get` HPA for the workload:

- `spec.minReplicas` / `maxReplicas`
- `status.currentReplicas` vs `desiredReplicas`
- `status.conditions` ScalingLimited / AbleToScale
- Current metric vs target (CPU %)

If `currentReplicas == maxReplicas` and utilization still above target, the
identified issue is **HPA ceiling**, not a missing replica. Combine with
`observability` if Grafana is up. Do not raise maxReplicas.

## 5. PodDisruptionBudget

If rolling update is stuck or evictions fail: list PDBs. `status.disruptionsAllowed=0`
with `currentHealthy <= minAvailable` explains “cannot drain / cannot rollout.”
That is identification of a rollout stall, not a crash.

## 6. Nodes

```
Tool: nodes_top
```

`resources_get` the node for a Pending pod (`spec.nodeName` empty until scheduled).

Conditions: Ready=False, MemoryPressure, DiskPressure, PIDPressure, NetworkUnavailable.
Taints vs pod tolerations. Cordoned (`unschedulable: true`).

If the node is fine and quota is exceeded, the node is not the cause.

## 7. Feed the RCA

Class is **Saturation** (or Pending as a symptom). Examples:

- ResourceQuota `tiny` hard pods=3, used=3; Deployment `pending-quota` never schedules
- PVC `data` Pending, StorageClass `does-not-exist-sc`
- HPA `payments` 8/8 replicas, CPU 90% vs target 70% — ceiling hit

Restarting existing pods does not free quota or bind a PVC. Say that.
