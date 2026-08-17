---
app: mismatch
issue_type: Unreachable
namespace: dto-e2e
cluster: kind-dto-e2e
date: 2026-08-12
severity: high
confidence: high
resolved: true
resolution_type: config-fix
time_to_resolve: 15m
---

# mismatch: Unreachable (2026-08-12)

Example record from the kit (Service selector vs pod labels). Test this hypothesis
when pods are Ready but the app is still unreachable.

## Symptom
Users got no backends / empty Endpoints while pods looked Running and Ready.

## Timeline
- Pods Ready=True
- Service `mismatch` selector `app=payments`
- Pods labeled `app=payments-api`

## What we checked
Service selector, pod labels, Endpoints (no ready addresses).

## Hypotheses
- Selector mismatch — CONFIRMED
- Readiness probe — REJECTED (Ready=True)
- Ingress TLS — not applicable for this object (no host in that incident)

## Root Cause
Class Unreachable. Service selector does not match pod labels. Confidence high.

## Blast radius
Service `mismatch` only. Restarting pods does not change labels vs selector.

## Resolution
Align Service selector with pod template labels (chart/config).

## Lessons Learned
Running ≠ reachable. Always get Endpoints.

## Related
e2e fixture `tests/fixtures/03-selector-mismatch.yaml`
