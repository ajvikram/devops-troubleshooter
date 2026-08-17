---
description: Severity-tagged health scan of a Kubernetes namespace before a full RCA.
agent: DevOps Troubleshooter
---

Run a `cluster-scan` of this namespace. Produce the findings table (CRITICAL / WARNING / INFO), then investigate the highest-severity items and write the RCA with recommendations. Do not mutate the cluster.

${input:Namespace and kube context (optional)}
