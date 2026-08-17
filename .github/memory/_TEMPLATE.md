---
app: <application-name>
issue_type: <CrashLoopBackOff|OOMKilled|ImagePullBackOff|Pending|NotReady|Unreachable|IngressBackend|TLSExpired|ConnectionRefused|HelmDrift|ProbeFailure|ConfigError|SchemaMismatch|ReplicationLag|Other>
namespace: <kubernetes-namespace>
cluster: <cluster-context-name>
date: <YYYY-MM-DD>
severity: <critical|high|medium|low>
confidence: <high|medium|low>
resolved: <true|false>
resolution_type: <pod-restart|scale-up|helm-rollback|config-fix|code-fix|infra-fix|manual|none>
time_to_resolve: <duration, e.g. 15m, 2h>
---

# <app>: <issue_type> (<date>)

<!-- Keep ~60 lines. Quote ≤3 log lines. No raw MCP dumps (token-thrift). -->

## Symptom
<!-- User-facing impact, not just the Kubernetes object state -->


## Timeline
<!-- Evidence-backed timestamps: deploy, image change, first event, user report -->


## What we checked
<!-- Pods, events, logs (incl. previous), spec, Service/Endpoints, Helm, chart, DB, metrics -->
<!-- Also list what we did not check -->


## Hypotheses
<!-- Kept vs rejected, each with evidence -->
<!-- - H1 … CONFIRMED/REJECTED — evidence -->


## Evidence ledger
<!-- ID | claim | tool + object | quote. Every Root Cause clause needs a row. -->


## Root Cause
<!-- Class + underlying reason + confidence. Cite ledger IDs. Not "CrashLoopBackOff". -->


## Blast radius
<!-- Replicas, namespaces, user flows still healthy vs affected -->


## Recommendations
<!-- What would address the cause. Not executed. Restart = mitigation if mentioned. -->


## Proposed change
<!-- Unified diff against the workspace chart, or "no repo patch" if the fix is outside git. -->


## Resolution
<!-- What humans actually did later, if known -->


## Lessons Learned
<!-- Alerts, chart changes, code fixes, runbook updates -->


## Related
<!-- PRs, tickets, other incident records -->
