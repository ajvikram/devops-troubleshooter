---
name: clarify
description: >
  Stop and ask when the request is missing or ambiguous (cluster, namespace,
  workload, env, time, impact). Use before guessing. Numbered choices from
  cluster evidence. Blocking vs optional questions.
---

# Ask when information is insufficient or ambiguous

Wrong cluster, wrong namespace, or the wrong workload produces a confident
**false RCA**. If the request is incomplete or could mean more than one thing,
**ask**. Do not invent the missing field.

Follow this skill at the start of every session and whenever a later step
forks (two workloads, two CRITICAL findings, two equally likely causes).

## How to ask

- **Numbered options** taken from tools (`configuration_contexts_list`,
  namespaces, Deployments), not an essay.
- At most **three questions** per turn. Blocking first.
- One sentence of **why** you are asking (what a wrong pick would break).
- If they answer with a number, a name, or “2 and scan payments” — proceed.
- Never dump kubeconfig, tokens, or Secret data while asking.

Template:

```
Need a choice before I read the cluster (wrong cluster = wrong RCA).

**Cluster**
1. `gke_proj_us-east1_staging` (kubeconfig current)
2. `gke_proj_us-east1_prod`

**Namespace** (on the cluster you pick)
1. `payments`
2. `payments-canary`
3. Scan all namespaces that have Warning events

Which cluster and namespace?
```

## Blocking (do not investigate yet)

Stop and ask. Do not default to `current-context`, `default` namespace, or
the first pod.

| Gap | You have | Ask |
|-----|----------|-----|
| **Cluster** | 0 contexts | How to set `KUBECONFIG` / start MCP. Stop. |
| **Cluster** | 2+ contexts, no unique match to their words | Numbered context list. `/use-cluster`. |
| **Cluster** | Word `staging` / `prod` matches **two** context names | Show the matches; ask which. |
| **Namespace** | Not given, and the context has more than one non-system namespace | List app namespaces (skip `kube-system`, `kube-public`, `kube-node-lease` unless they asked). Ask. |
| **Workload** | Name matches two Deployments/StatefulSets/CronJobs | List kind/name/namespace. Ask. |
| **Host / TLS** | They gave a URL that hits two Ingresses | List hosts + backend Services. Ask. |

“Fix prod” with several `*prod*` contexts is **blocking**.

If they say **“scan everything”** / **“you pick”**:

- Multiple contexts: ask once more — “Scan all N contexts one by one?” If yes,
  investigate each and **label every finding with its context**. Do not merge
  them into one RCA without saying they are different clusters.
- Multiple namespaces, one context: `cluster-scan` namespaces that have
  Warning events first; say which you skipped.

## Ask once, then continue (optional)

Ask in the same turn if you already have blocking answers. If they ignore
the optional questions, **state the assumption** and continue. Do not stall
the RCA forever.

| Gap | Default if they skip | Still write in RCA |
|-----|----------------------|--------------------|
| When it started | **unknown start**; use first Warning / pod `startTime` | Timeline: unknown start |
| User impact | Restate from object name; mark as inferred | Symptom: inferred |
| Which CRITICAL finding first | Highest severity, then name | What we checked |
| Database engine | Follow log strings; if only “DB” | Skip `db-evidence` or ask |
| Grafana window | Last 1h if Grafana MCP is up | Gap if MCP is down |

## What is not ambiguous (do not nag)

- One kube context in the list — name it and go.
- Exact context + namespace + workload already in the prompt.
- They pasted an alert with `labels.namespace` and a unique context match.
- You can disambiguate with a cheap read (list namespaces, see one `payments*`).

Cheap reads **before** asking are required: list contexts, list namespaces,
list workloads matching their string. Ask only about the remainder.

## Ambiguous evidence later

If two root causes remain equally likely after evidence:

- Do **not** pick a winner.
- RCA: **undetermined** with both hypotheses kept.
- Ask: “Which user flow is broken (checkout vs admin), or should I keep both?”

If `cluster-scan` returns several CRITICALs that do not share a deploy time,
ask which symptom they care about, or investigate all and separate blast radius
per workload.

## Never

- Guess cluster, namespace, or workload to look productive.
- Ask more than three questions when one blocking question would do.
- Treat silence as consent to use `current-context` when multiple contexts exist.
