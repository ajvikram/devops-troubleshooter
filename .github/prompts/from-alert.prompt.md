---
description: Start an RCA from a pasted Prometheus, Alertmanager, Grafana, or PagerDuty alert.
agent: DevOps Troubleshooter
---

Follow `alert-intake`. Parse the alert I paste, confirm kube context, scan the namespace, then write an evidence-backed RCA with recommendations. The alert name is a symptom pointer, not the root cause. Do not ack, silence, or mutate.

Paste the alert below (JSON, Slack text, or Grafana fields):

${input:Alert JSON or text}
