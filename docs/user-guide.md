# User guide

This kit’s job is to **find the issue, write an RCA, and recommend what would
address the cause**. It does not apply changes.

You run the **DevOps Troubleshooter** in a local agent (GitHub Copilot Chat, Cursor,
or Copilot CLI) with read-only Kubernetes MCP. You do not need to know MCP tool
names — the agent does.

For install and harness detection, see [init.md](init.md). For VS Code Copilot
specifics, see [copilot-vscode.md](copilot-vscode.md). macOS: [macos.md](macos.md).
Windows: [windows.md](windows.md).

## 1. First-time setup (once)

```bash
./scripts/init.sh
```

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\init.ps1
```

Init discovers your OS, IDE, and agent harness, **asks which MCP servers to
download**, fetches those binaries, and writes MCP config.

Then:

1. Open this folder (or an app repo you copied `.github/` + MCP config into).
2. Start **kubernetes-inspect** (VS Code: Command Palette → **MCP: List Servers**). Trust it.
3. Open chat in **Agent** mode (not Ask).
4. Choose **DevOps Troubleshooter**.

If Kubernetes tools never appear, the MCP server is not started or not trusted.
Ask mode cannot call tools. Cloud Copilot on github.com cannot use your laptop kubeconfig.

## 2. How to ask

Give **impact + where**, not a Kubernetes object name.

**Good**

- `Checkout is failing in staging. Namespace payments. Started after the 14:00 deploy.`
- `payments-api looks up but we get 502s from the ingress.`
- `Pods in ns auth keep restarting. Context is kind-dto-e2e.`

**Weak** (the agent can still work, but you lose timeline)

- `why is this pod crashlooping`
- `fix prod`

Confirm context and namespace when the agent lists kube contexts. Wrong cluster
is the most common false RCA.

## 3. What a good RCA looks like

The troubleshooter must follow the `rca` skill. You should see:

| Section | What to expect |
|---------|----------------|
| **Symptom** | User-facing impact, not “CrashLoopBackOff” |
| **Timeline** | Deploy / image / first Warning event / your report |
| **What we checked** | Pods, events, previous logs, spec, Service/Endpoints, Helm, chart — and gaps |
| **Hypotheses** | 2–4, each kept or rejected with evidence |
| **Root cause** | Class + cause + confidence. CrashLoopBackOff is not a cause |
| **Blast radius** | What else is healthy |
| **Recommendations** | What would address the cause (chart, TLS, quota, git). Not executed. Restart = mitigation |

**Running ≠ Ready ≠ reachable.** If the app is “down” but pods are Running, the
agent should inspect Service selectors and Endpoints, not only container logs.

Restart is a mitigation. If Endpoints are empty because of a selector mismatch,
restarting pods will not fix it — the RCA should say that.

## 4. Example session

You: `payments-api in namespace dto-e2e is down.`

Agent should:

1. Read `.github/memory/INDEX.md` (past incidents).
2. List kube contexts; you confirm.
3. List **all** pods (not only `!=Running`), Warning events.
4. Classify Crash / Not Ready / Unreachable.
5. Pull current **and previous** logs if restart count > 0.
6. Get Deployment, Service, Endpoints.
7. If a host/URL is involved: Ingress backend + TLS secret (`ingress-tls`).
8. `helm history` / git / `gh` for what changed (`change-correlation`).
9. Write the RCA with hypotheses, a timeline, and **recommendations** (not executed).

You may save to memory. The agent does not apply cluster changes.

## 5. Skills (when they apply)

| Skill | When |
|-------|------|
| `rca` | Every investigation (required write-up) |
| `k8s-incident` | CrashLoop, ImagePull, OOM, probes, Pending |
| `service-path` | 502s, Running but not Ready, empty Endpoints |
| `ingress-tls` | Public URL / HTTPS: wrong backend Service, missing or expired cert |
| `change-correlation` | Helm `history` / git / `gh` — what changed before the symptom |
| `gitops` | Argo/Flux OutOfSync or suspended vs live |
| `saturation` | Pending: ResourceQuota, PVC, HPA at max, nodes |
| `helm-drift` | Live spec ≠ workspace chart |
| `db-evidence` | Logs point at Postgres/MySQL/Oracle/SQL Server/Mongo/… |
| `observability` | Grafana MCP running (Prom/Loki) |
| `incident-memory` | Start (recall) and end (save, if you confirm) |

Optional MCP: copy **one** `db-*` server from `.vscode/mcp.databases.json` (macOS/Linux) or
`.vscode/mcp.databases.windows.json` (Windows), or run
`./scripts/init.sh --with-observability` / `.\scripts\init.ps1 -WithObservability`
and set `GRAFANA_URL` + `GRAFANA_SERVICE_ACCOUNT_TOKEN` in `.vscode/mcp.env`.

Start only the servers you need. Copilot has a **128 tools per request** cap.

## 6. Incident memory

After the RCA, the agent asks to save. Say yes if you want the next similar
incident to see the prior cause as a **hypothesis to test**, not as the answer.

Records live in `.github/memory/<app>/` and `INDEX.md`. No secrets or PII.
The kit ships two **example** records (`crashloop`, `mismatch`) so recall is not empty.

## 7. Recommendations (not remediations)

The last RCA section is **Recommendations**. Examples:

| Cause | Recommendation | Not a recommendation |
|-------|----------------|----------------------|
| Missing `PAYMENTS_DSN` | Set the env in the chart/values | Restart the crashing pod |
| Selector `app=payments` vs `payments-api` | Align Service selector with pod labels | Delete pods |
| Ingress backend `does-not-exist` | Point Ingress at the real Service name | Scale the app |
| TLS secret missing | Create/rotate the named TLS secret (human/certs) | Restart ingress pods first |
| Quota 3/3 pods | Raise quota or free a replica **in git/policy** | Restart existing pods |

Restart, if mentioned, is labeled **mitigation** and must say what stays broken.

## 8. Demo cluster (e2e fixtures)

To practice RCA without touching a real cluster:

**macOS / Linux**

```bash
./tests/e2e.sh --keep-cluster
```

**Windows (PowerShell)** — Docker Desktop + kind + kubectl + Python 3:

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\e2e.ps1 -KeepCluster
```

That creates a `kind` cluster named `dto-e2e`, deploys known failures, and
checks that kubectl (and the Kubernetes MCP server, if downloaded) can see them.

| Workload | Expected cause |
|----------|----------------|
| `crashloop` | Process exits 1; logs contain `CONFIG_ERROR: missing PAYMENTS_DSN` |
| `not-ready` | Running, Ready=False; readiness TCP probe on closed port 9999 |
| `mismatch` | Pods Ready; Service selector does not match; Endpoints empty |
| Ingress `payments` | Backend Service `does-not-exist`; TLS secret `payments-tls-missing` absent |
| Helm `dto-hist` | Two revisions (`note=rev1` then `rev2`) — `helm history` for the timeline |
| `pending-quota` | ResourceQuota `tiny` already 3/3 pods — replica cannot schedule |

Then in Copilot: `Something is wrong in namespace dto-e2e. Investigate all workloads.`

Tear down:

```bash
kind delete cluster --name dto-e2e
```

The `--keep-cluster` / `-KeepCluster` flags leave `dto-e2e` running so you can chat against it.

Kit-only tests (no Docker):

```bash
./tests/kit.sh
```

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\kit.ps1
```

## 9. Kit not working

| Problem | What to do |
|---------|------------|
| Agent missing from dropdown | File is `.github/agents/devops-troubleshooter.agent.md`; reload window |
| No Kubernetes tools | Start `kubernetes-inspect`; Agent mode; org MCP policy |
| MCP start fails (TLS) | [proxy-ssl.md](proxy-ssl.md); prefer binaries from `init` over npx |
| Windows `npx` spawn error | Use `init.ps1` / `.exe`, or `mcp.npx.windows.json` (`npx.cmd`) |
| Apple Silicon `Bad CPU type` | Re-run `./scripts/setup.sh --k8s-only` on the Mac (need `darwin/arm64`) |
| Wrong cluster | Step 1: confirm context from `configuration_contexts_list` |
| 128-tool cap | Disable unused MCP servers (do not enable all DBs + Grafana at once) |

## 10. Security reminders

- Troubleshooter is read-only. It recommends; it does not apply.
- Use a `view` kubeconfig for investigation when you can.
- Database users: SELECT only. Grafana MCP: `--disable-write`.
- Never paste kubeconfig, tokens, or dump Secret data into chat.
