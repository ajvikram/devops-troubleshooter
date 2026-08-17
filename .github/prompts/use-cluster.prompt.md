---
description: Pin a kube context (cluster) then investigate. Use when you have several contexts or kubeconfig files.
agent: DevOps Troubleshooter
---

Follow `kube-context`. List contexts, pick the one I name (or ask if I did not), then investigate with `context=` on every Kubernetes MCP call and `--kube-context` on Helm. Never kubectl config use-context. Never mutate the cluster.

${input:Context name (or leave blank to list) and what is broken}
