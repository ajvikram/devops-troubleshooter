# Token use

Investigations must stay **small**. Copilot/Cursor send the agent file, skill
text, memory, and every MCP result in the prompt. A full Helm values dump or
opening every `SKILL.md` burns the budget before the RCA.

The agent follows the **`token-thrift`** skill. You should see a short RCA, not
raw `kubectl` YAML.

## What we already do

| Lever | Default |
|-------|---------|
| MCP servers | Kubernetes inspect only until you opt in (Copilot **128 tools** cap) |
| Grafana | `--disable-write`, Prometheus + Loki tools only |
| Memory | **INDEX.md** one-liners; at most **one** matching record (Symptom + Root Cause) |
| Skills | After classify, **at most two** evidence skills — not all of them |
| Logs | One pod per ReplicaSet, `tail=80` first |
| RCA | Evidence ledger ≤8 rows; small proposed diff |
| Saved incidents | ~60 lines, ≤3 quoted log lines |

## What you can do

1. Do **not** start Grafana and every `db-*` server for a CrashLoop. Each extra
   MCP server adds tool schemas and large payloads.
2. Give **context + namespace + app** so the agent does not scan every namespace.
3. Keep `INDEX.md` to one line per incident. Do not paste logs into the index.
4. Prefer binaries (`init`) over npx on corporate laptops — that does not change
   tokens, but avoids retries/errors that inflate the session.

## What the agent must not do

- Glob `.github/memory/**` at session start
- Open e2e example memory unless you are on `dto-e2e`
- `resources_get` every pod or paste Secret/Helm YAML into chat
- Call `configuration_view` (tokens + huge kubeconfig)
- Use `web` unless cluster evidence is not enough to name the error

Day-to-day: [user-guide.md](user-guide.md). Clusters: [clusters.md](clusters.md).
