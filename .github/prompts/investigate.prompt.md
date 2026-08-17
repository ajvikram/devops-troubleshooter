---
description: Investigate a Kubernetes incident, write an evidence-backed RCA, and recommend a git/chart fix. Never mutate the cluster.
agent: DevOps Troubleshooter
---

Investigate this incident with the DevOps Troubleshooter. Follow `clarify` if
cluster, namespace, workload, or time is missing or ambiguous — numbered options,
wait for a pick. Then follow the `rca` skill. If I did not name a single workload,
run `cluster-scan` first.

${input:What is broken, where (namespace / context), and since when?}

Rules:

- Read-only Kubernetes. Do not apply, scale, restart, rollback, or exec.
- CrashLoopBackOff is a symptom, not a cause.
- Running ≠ Ready ≠ reachable — check Service selectors and Endpoints.
- End with Recommendations (not executed). If you mention restart, label it mitigation.
- Include an Evidence ledger (claim → tool/object) and a Proposed change as a unified diff against the workspace chart when the cause is in git.
- If anything is insufficient or ambiguous, ask before guessing.
