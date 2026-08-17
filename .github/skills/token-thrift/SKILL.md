---
name: token-thrift
description: >
  Keep investigations token-cheap: INDEX-only memory, one evidence skill after
  classify, small log/event tails, no YAML dumps in the RCA. Use on every session.
---

# Token-thrift (do not flood the context)

Copilot/Cursor bills **prompt + tool results + skills**. A full-namespace YAML
dump or opening every `SKILL.md` burns the budget before the RCA. Follow this
on every investigation.

## 1. What stays in context (always)

- This agent file (already loaded).
- `.github/memory/INDEX.md` — **one-line** entries only. Never glob `memory/**`.
- `rca` when you write the RCA.

Do **not** open every skill. After you classify the failure, open **at most two**
evidence skills (example: `k8s-incident` + `service-path`). Skip the rest.

## 2. Memory (cheap recall)

1. Read **INDEX.md only**.
2. If one INDEX line matches app or issue type, you may read **that one file**.
   Read **Symptom + Root Cause** only. Do not load the rest of the record.
3. If nothing matches, say so. Do not open example records “just in case”
   (`crashloop--2026-08-10` is an e2e fixture, not this cluster).
4. Prior cause = **hypothesis to test**, not the answer.
5. When saving: keep the new file scannable (~60 lines). Quote **≤3** log lines.
   INDEX stays one line per incident. No tool transcripts.

## 3. Tool budget (first pass)

| Call | First pass | Only if needed |
|------|------------|----------------|
| `pods_list_in_namespace` | Once per namespace | — |
| `events_list` | Warning, recent; do not page forever | Older window if timeline empty |
| `pods_log` | **One** pod per ReplicaSet, `tail=80` | `previous=true` if restart > 0; `tail=200` only if 80 missed the error |
| `resources_get` | Deployment/Service/Endpoints **or** the one object the event names | Full spec YAML never pasted into chat |
| Helm | `helm_list` + `helm history` | `helm get values` for **image/probes/env names** only — do not paste the whole values file |
| `git log` | `-8 --oneline` | `-p` on the one file that drifted |
| `gh run list` | `--limit 8` | `gh run view` one failing run |
| Grafana | Skip unless MCP is up **and** class needs metrics | One PromQL / one Loki query, bounded |
| DB | Skip unless logs point at data | `LIMIT 20`, one engine |
| `web` | Skip | Unknown error string after cluster evidence |

Do not re-fetch an object you already have. Do not `resources_get` every pod.
Do not list all namespaces if the user already named one.

`configuration_view` is forbidden (tokens + huge YAML).

## 4. What you paste into the RCA

- Ledger: **≤8 rows**. Quote a **short** field or one log line, not a wall of text.
- Hypotheses: 2–4 lines, not tool dumps.
- Proposed change: a **small** unified diff, not the whole chart.

If a tool returned a large payload, **summarize** (restart count, exit code,
selector vs labels). The user does not need the raw JSON.

## 5. Optional MCP servers

Default tools are Kubernetes inspect + workspace read. **Do not start** Grafana
or extra `db-*` servers for a Crash/Not-Ready investigation. Each extra MCP
server adds tool schemas (Copilot **128 tools** cap) and large results.

When a DB or Grafana server **is** running, call it only for Data layer /
metrics gaps — one query, then stop.
