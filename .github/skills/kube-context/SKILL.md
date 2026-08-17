---
name: kube-context
description: >
  Pick which Kubernetes cluster to investigate when the kubeconfig has multiple
  contexts or KUBECONFIG lists several files. Use at the start of every session.
  Pass context= on every later inspect call. Never kubectl config use-context.
---

# Pick the Kubernetes cluster

The user often has **many clusters** in one kubeconfig, or **several kubeconfig
files**. Investigating the wrong one produces a confident false RCA.

`kubernetes-inspect` is multi-cluster. After the user picks a context, pass
`context: <name>` on **every** later Kubernetes MCP tool. Do **not** change
the kubeconfig’s `current-context` on disk.

## 1. List what the MCP can see

```
Tool: configuration_contexts_list
```

Show a numbered table. Include which row is the kubeconfig default (current),
but do **not** assume that is the incident cluster.

| # | Context | Notes |
|---|---------|--------|
| 1 | `kind-dto-e2e` | local kind |
| 2 | `gke_proj_us-east1_staging` | **current** in kubeconfig |
| 3 | `prod-payments` | |

If the list is empty: MCP cannot see a kubeconfig. Tell the user to set
`KUBECONFIG` in `.vscode/mcp.env` (or the OS env), restart **kubernetes-inspect**,
and stop. Do not invent cluster state.

Never call `configuration_view` — it can dump tokens.

## 2. Let the user pick

Match, in order:

1. A context name they already typed (exact, then case-insensitive).
2. A cluster/env word they used (`staging`, `prod`, `kind-dto-e2e`) against context names.
3. If **one** context exists, name it and proceed.
4. If several remain, **ask** (`clarify`). Numbered list. Do not default to `current-context` when more than one exists.
5. Word `staging` / `prod` matching **two** names → show those rows only and ask. Blocking.

Pin the choice for the rest of this chat:

> Using kube context `staging` for all cluster reads. Say if that is wrong.

If they change their mind later, switch the pin and say so. Still no
`kubectl config use-context`.

## 3. Pass `context` on every inspect call

All `kubernetes-inspect` tools that talk to the API (pods, events, logs,
resources, helm_list, …) take an optional `context` argument when multiple
contexts exist. Always set it after Step 2.

```
Tool: pods_list_in_namespace
Args: namespace=payments, context=staging
```

Helm CLI (allowlisted `execute`) must target the same cluster:

```
helm history payments -n payments --kube-context staging
helm get values payments -n payments --kube-context staging --revision 12
```

`helm_list` (MCP) also gets `context: staging`.

## 4. Multiple kubeconfig files

The MCP process sees whatever `KUBECONFIG` it was started with.

| Setup | What to do |
|-------|------------|
| One file, many contexts | This skill. No MCP restart. |
| Several files merged | Unix: `KUBECONFIG=file1:file2:file3`. Windows: `file1;file2;file3` (semicolon — drive letters use `:`). Put that in `.vscode/mcp.env`, **restart kubernetes-inspect**, then list contexts. |
| Isolated prod vs staging servers | Optional extra MCP servers, each with `--kubeconfig` pointing at one file (see `.vscode/mcp.multi-cluster.example.json`). Prefer that when the user must not mix prod into a staging investigation. |

Do not concatenate kubeconfig YAML yourself. Do not copy kubeconfig contents into chat.

## 5. What you must never do

- `kubectl config use-context` / `kubectl config set-context` (writes the user’s kubeconfig).
- `execute` of any `kubectl` command — use MCP + Helm only.
- Investigate without naming the context in the RCA **Symptom** line.
- Quietly use the default context when the list has more than one entry.
