---
name: change-correlation
description: >
  Identify what changed before the incident: Helm revision history and values,
  git history on charts/code, GitHub PRs and Actions runs. Read-only. Use when
  building the RCA timeline or when the user says it broke after a deploy.
---

# Change correlation (what changed)

Identification only. Never install, upgrade, rollback, or mutate git/GitHub.

A cause without a **trigger** is often incomplete. This skill finds the trigger:
which Helm revision, git commit, or CI run lines up with the first symptom.

`kubernetes-inspect` has `helm_list` (current revision only). Full history needs
the Helm CLI via `execute`. Git/GitHub need `git` / `gh` via `execute`.

If `helm`, `git`, or `gh` is missing, record that as an RCA **gap** and continue.

## Allowlisted commands only

```
helm history <release> -n <namespace> --kube-context <context>
helm status <release> -n <namespace> --kube-context <context>
helm get values <release> -n <namespace> --kube-context <context>
helm get values <release> -n <namespace> --kube-context <context> --revision <N>
helm get metadata <release> -n <namespace> --kube-context <context>
git log -8 --oneline -- <path>
git log -5 -p -- <path>
git blame -L <range> <file>
gh run list --limit 8
gh run view <id> --json conclusion,displayTitle,headBranch,updatedAt,url
gh pr list --search "<app OR namespace>" --limit 10
gh pr view <n>
```

Never: `helm install|upgrade|rollback|uninstall`, `git push|commit`, `gh pr create`,
`kubectl apply`, anything that writes.

## 1. Helm — current vs history

```
Tool: helm_list   (MCP)
```

Match the failing workload to a release (name, namespace, chart, **revision**, status).

Then:

```
execute: helm history <release> -n <namespace> --kube-context <context>
```

Record for the last several revisions: revision number, status, chart version,
app version, updated timestamp, description.

Hypothesis pattern:

| Evidence | Likely trigger |
|----------|----------------|
| First Warning events start just after revision N | Revision N introduced the fault |
| Image tag in live spec equals values of revision N, not N-1 | Bad image/config in N |
| Revision N failed (`failed` / `pending-rollback`) | Deploy itself did not finish |

```
execute: helm get values <release> -n <namespace> --kube-context <context> --revision <N>
execute: helm get values <release> -n <namespace> --kube-context <context> --revision <N-1>
```

Diff **image**, probes, env **names**, replicaCount, ingress host. Quote the
changed keys in the RCA. Do not dump entire values files if they may contain secrets
(look for `password`, `token`, `key` — redact).

A revision bump is a **trigger**, not automatically the root cause. Combine with
`k8s-incident` / `service-path` / `helm-drift`.

## 2. Workspace git

If this repo contains the chart or app:

```
execute: git log -20 --oneline -- charts/ <chart-path> values.yaml
```

Match commit timestamps to Helm `updated` and to event `firstTimestamp`.
If the user named a PR or SHA, `git show` / `gh pr view` that only.

## 3. GitHub Actions / PRs (if `gh` works)

Use when the user said “after the pipeline” or the Helm description looks like
a CI deploy (`Open in browser`, `GitHub Actions`, `argocd`).

```
execute: gh run list --limit 15
```

Find a failed or recent success on the same app/environment near the timeline.
`gh run view` for the job that deployed. Do not download logs unbounded; prefer
failed-step names and the SHA.

If `gh` is not authenticated, say so. Do not scrape github.com with invented tokens.

## 4. Feed the RCA

Timeline must include at least one of: Helm revision + time, git SHA + time, or
**unknown change** (helm/git/gh unavailable).

Example root-cause sentence:

> Trigger: Helm revision 12 at 14:02 (`payments-api` `0.4.2`, image `v2.3.1`).
> Cause: readiness path `/ready` in that revision; Endpoints empty. Revision 11
> had `/healthz`. Confidence high.
