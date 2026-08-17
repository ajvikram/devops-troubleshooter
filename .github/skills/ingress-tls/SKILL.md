---
name: ingress-tls
description: >
  Identify why an app is unreachable at Ingress/HTTPRoute despite Ready pods:
  wrong backend Service, missing Service, TLS secret missing or expired, DNS
  name mismatch. Use for 502/504, certificate errors, HTTPS failures. Read-only.
---

# Ingress / TLS (edge unreachable)

Use after **`service-path`** has shown the intended Service either has Ready
Endpoints **or** you already know the user hits a URL/host, not ClusterIP.

Do not blame Ingress until you have listed backend Service + Endpoints.

Identification only. Never create certificates, edit Ingress, or print PEM/keys.

## 1. Find edge objects

In the target namespace (and `resources_list` Ingress cluster-wide if the host
is known but the namespace is not):

- `Ingress` (`networking.k8s.io/v1`)
- `HTTPRoute` / `Gateway` (if present)
- `VirtualService` / `IngressRoute` (if present) — get and read spec; do not invent CRDs

For each rule note: **host**, **path**, **backend Service name**, **port**.

If the user gave a URL, match `host` + `path` first.

## 2. Backend Service must exist and have Endpoints

`resources_get` the backend Service in the **same namespace as the Ingress**
(unless a cross-namespace ref is explicit).

| Observation | Identified issue |
|-------------|------------------|
| Service not found | Ingress backend name is wrong (typo, wrong release name) |
| Service exists, no ready Endpoints | Problem is Service/pods — return to `service-path` |
| Service + Endpoints OK, still 502 | Continue to TLS, Ingress controller, DNS |

Quote the backend `service.name` from the Ingress spec in the RCA.

## 3. TLS secret

From `spec.tls[].secretName` (and cert-manager `Certificate` if present):

`resources_get` Secret. **Never print `tls.key` or the PEM body.**

| Observation | Identified issue |
|-------------|------------------|
| Secret not found | Missing TLS secret — browser/client TLS errors, Ingress events `Failed to fetch secret` |
| Type not `kubernetes.io/tls` | Wrong secret |
| `tls.crt` present | Decode **notBefore / notAfter / CN / SAN only** |

Decode dates via allowlisted `execute` (no files committed, no key):

```
openssl x509 -noout -subject -dates -ext subjectAltName
```

Pass only the certificate PEM (from `tls.crt`), never `tls.key`.

- **Expired** (`notAfter` in the past) → class Unreachable / TLS; high confidence
- **Not yet valid** (`notBefore` in the future)
- **CN/SAN does not include Ingress host** → cert/host mismatch

Also `events_list` for `Failed to fetch secret`, `Sync`, `Invalid`.

## 4. Ingress controller (only if backend is healthy)

List controller pods (common: `ingress-nginx`, `contour`, `traefik`, `istio-gateway`
in their namespaces). If they are not Ready, the edge is down for **all** hosts —
say that. If they are Ready, do not stop at “ingress is broken”; keep the backend
or TLS finding.

You cannot curl the LoadBalancer from here unless the user asks and network allows.
Prefer object evidence over live HTTP.

## 5. DNS (name vs Ingress host)

If logs or the user show `NXDOMAIN` / wrong site:

- Ingress `spec.rules[].host` vs the URL they typed
- In-cluster: Service FQDN `name.ns.svc.cluster.local` exists
- CoreDNS pods in `kube-system` Ready (list only)

## 6. Feed the RCA

Class is usually **Unreachable**. Examples:

- Ingress backend Service `does-not-exist`; pods/Service `mismatch` are fine
- TLS secret `payments-tls` missing; HTTP might work, HTTPS fails
- Certificate `notAfter=2020-01-02` for host `payments.example.test`

Restarting app pods will **not** fix a wrong backend name or an expired cert.
Say that explicitly. Do not apply a new certificate.
