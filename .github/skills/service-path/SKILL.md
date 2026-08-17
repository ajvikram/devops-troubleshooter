---
name: service-path
description: >
  Trace why a Kubernetes Service is unreachable even when pods look Running:
  Ready vs Running, selectors vs labels, empty Endpoints, probes, Ingress,
  NetworkPolicy. Use for 502, timeouts, no-route, "app is down" with healthy-looking pods.
---

# Service path (Running is not reachable)

Use this skill when the user reports **cannot reach the app**, **502/504**,
**timeouts**, **intermittent failures**, or pods that are **Running but not Ready**.
CrashLoop/OOM/ImagePull still belong in `k8s-incident` first; come here after
containers stay up or the failure is at the Service/Ingress layer.

Gather evidence only. Do not mutate the cluster.

## 1. Ready vs Running

List pods in the namespace (no phase filter). For the target workload note:

| Field | Meaning |
|-------|---------|
| Phase `Running` | Process started. Does **not** mean it serves traffic. |
| Ready `False` | Removed from Service Endpoints. Clients get 502/no backends. |
| Restart count | Rising with Ready True can still be a leak or kill from liveness. |

If Ready is False, inspect `status.containerStatuses` and events for `Unhealthy`
(probe) before blaming the Ingress controller.

## 2. Workload availability

`resources_get` the Deployment/StatefulSet:

- `spec.replicas` vs `status.readyReplicas` vs `status.availableReplicas`
- `status.conditions` (Progressing, ReplicaFailure)
- New ReplicaSet vs old (rollout stuck)

A rollout that never becomes available is often a **readiness probe** or
**missing config**, not "the Service is wrong."

## 3. Service selector vs pod labels

`resources_get` Service, then compare:

- `spec.selector` must match **pod template labels** (and live pod labels)
- `spec.ports[].targetPort` must match container `ports.containerPort` (name or number)
- Headless vs ClusterIP vs LoadBalancer — know which the client uses

Mismatch here is a high-confidence root cause: Endpoints stay empty while pods run.

## 4. Endpoints / EndpointSlice

`resources_get` Endpoints (or EndpointSlice) for the Service.

| Observation | Typical cause |
|-------------|----------------|
| No subsets / empty addresses | Selector mismatch, or all pods unready |
| Addresses exist, wrong port | targetPort mismatch |
| Only some pods listed | Those pods Ready=False (probe, not "random 502") |

Quote the Endpoints object in the RCA. Do not infer emptiness from the Service spec alone.

## 5. Probes (the usual Ready=False cause)

From the live pod/deployment spec:

- **readinessProbe** — failure takes the pod out of Endpoints (user-facing 502)
- **livenessProbe** — failure **kills** the container (restarts; looks like CrashLoop)
- **startupProbe** — slow apps killed if startupProbe missing and liveness is aggressive

Check path, port, scheme, `initialDelaySeconds`, `timeoutSeconds`, `failureThreshold`.
Diff against the workspace Helm template. A chart that changed probe path on the
last revision is a classic RCA.

Confirm with `pods_log` and Warning events `Unhealthy`.

## 6. Ingress / HTTPRoute / Service mesh (if in play)

If the user hits a URL, not ClusterIP:

- Ingress/HTTPRoute backend Service name + port
- TLS secret exists (events: `Failed to fetch secret`) — do not print cert private keys
- Ingress controller pods/logs only if the backend Service already has Endpoints

Do not blame Ingress until Endpoints are proven populated and Ready.
Then follow the **`ingress-tls`** skill (backend Service name, TLS secret, cert dates).

## 7. NetworkPolicy (only if present)

List NetworkPolicies in the namespace. If none, skip.
If present, check whether they allow the Ingress controller / client namespace
to the pod port. You cannot packet-capture; state this as **possible** unless
events or mesh metrics confirm drops.

## 8. DNS (in-cluster)

If logs show `no such host` / `i/o timeout` to a k8s Service DNS name:

- Confirm the Service exists in the **same or FQDN namespace** (`svc.ns.svc.cluster.local`)
- Check kube-dns/CoreDNS pods in `kube-system` are Ready (list only; do not exec)

## 9. Feed the RCA skill

Return to `rca`:

- Class is usually **Not Ready** or **Unreachable**
- Root cause examples: "Service selector `app=pay` vs pods labeled `app=payments-api`" /
  "readinessProbe `/ready` 404 after image `v2.3.1`" /
  "Endpoints empty because 0/3 Ready"
- Restarting pods will **not** fix selector or probe-path mismatch. Say that explicitly.
