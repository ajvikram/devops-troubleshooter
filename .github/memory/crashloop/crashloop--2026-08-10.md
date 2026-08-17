---
app: crashloop
issue_type: CrashLoopBackOff
namespace: dto-e2e
cluster: kind-dto-e2e
date: 2026-08-10
severity: high
confidence: high
resolved: true
resolution_type: config-fix
time_to_resolve: 20m
---

# crashloop: CrashLoopBackOff (2026-08-10)

Example record from the kit (same failure class as the e2e `crashloop` workload).
Use as a **hypothesis to test**, not as proof the current incident is identical.

## Symptom
API in `dto-e2e` kept restarting; checkout failed.

## Timeline
- Container lastState exit code 1 within seconds of start
- Logs (previous): `CONFIG_ERROR: missing PAYMENTS_DSN`

## What we checked
Pods, Warning events, current and previous logs, Deployment env names.
Did not check Ingress (symptom was crash, not 502 with Ready pods).

## Hypotheses
- Missing required config / DSN — CONFIRMED (log signature + exit 1)
- ImagePull — REJECTED (image present, not ErrImagePull)
- OOM — REJECTED (exit 1, not 137 / OOMKilled)

## Root Cause
Class Crash. Process exits because `PAYMENTS_DSN` is unset. Confidence high.

## Blast radius
Single Deployment `crashloop` in `dto-e2e`. Other namespaces not involved.

## Resolution
Config/chart fix (DSN). Restart alone did not help until the env was present.

## Lessons Learned
CrashLoopBackOff is the symptom. Always read previous logs for CONFIG_ERROR-style lines.

## Related
e2e fixture `tests/fixtures/01-crashloop.yaml`
