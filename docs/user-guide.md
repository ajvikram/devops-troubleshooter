# User guide

This kit’s job is to **find the issue, write an RCA, and recommend what would
address the cause**. It does not apply changes.

You run the **DevOps Troubleshooter** in a local agent (GitHub Copilot Chat, Cursor,
or Copilot CLI) with read-only Kubernetes MCP. You do not need to know MCP tool
names — the agent does.

For install and harness detection, see [init.md](init.md). Global (every repo):
[user-install.md](user-install.md). For VS Code Copilot specifics, see
[copilot-vscode.md](copilot-vscode.md). Several clusters: [clusters.md](clusters.md).
Token use: [token-use.md](token-use.md). macOS: [macos.md](macos.md).
Windows: [windows.md](windows.md).

## 1. First-time setup (once)

```bash
./scripts/init.sh
```

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\init.ps1
```

Init discovers your OS, IDE, and agent harness, **asks workspace vs global**,
then which MCP servers to download, fetches those binaries, and writes MCP config.
Use `--scope global` / `-Scope global` so the agent is available in every repo.

Then:

1. **Workspace** scope: open this folder (or copy `.github/` + MCP config into the app repo). **Global** scope: open any repo — the agent and user MCP come from `~/.copilot`. Reload the window once.
2. Start **kubernetes-inspect** (VS Code: Command Palette → **MCP: List Servers**). Trust it.
3. Open chat in **Agent** mode (not Ask).
4. Choose **DevOps Troubleshooter**, or type `/` and pick a prompt:
   `investigate`, `scan-namespace`, `from-alert`, `use-cluster`, `clarify`.

If Kubernetes tools never appear, the MCP server is not started or not trusted.
Ask mode cannot call tools. Cloud Copilot on github.com cannot use your laptop kubeconfig.

## 2. How to ask

Give **impact + where**, not a Kubernetes object name. Copilot also ships slash
prompts in `.github/prompts/`:

| Prompt | Use |
|--------|-----|
| `/investigate` | Named incident → full RCA |
| `/scan-namespace` | “Something is wrong in ns X” → findings table, then RCA |
| `/from-alert` | Paste Alertmanager / Grafana / PagerDuty JSON |
| `/use-cluster` | Several kube contexts or kubeconfig files — pick first |
| `/clarify` | Vague prompt — agent lists options and waits |

**Good**

- `Checkout is failing in staging. Namespace payments. Started after the 14:00 deploy.`
- `payments-api looks up but we get 502s from the ingress.`
- `Pods in ns auth keep restarting. Context is kind-dto-e2e.`

**Weak** (the agent should **ask**, not guess)

- `why is this pod crashlooping` → which cluster, namespace, pod?
- `fix prod` → which of the `*prod*` contexts, which namespace?

If cluster, namespace, or workload is missing or matches more than one object,
the agent lists **numbered choices** and waits. That is intentional. Wrong
cluster is the most common false RCA.

Optional gaps (when it started, user impact): one question, then it continues
with **unknown start** / inferred symptom if you skip.

Full cluster / kubeconfig guide: [clusters.md](clusters.md).

## 3. What a good RCA looks like

The troubleshooter must follow the `rca` skill. You should see:

| Section | What to expect |
|---------|----------------|
| **Symptom** | User-facing impact, not “CrashLoopBackOff” |
| **Timeline** | Deploy / image / first Warning event / your report |
| **What we checked** | Pods, events, previous logs, spec, Service/Endpoints, Helm, chart — and gaps |
| **Hypotheses** | 2–4, each kept or rejected with evidence |
| **Evidence ledger** | Each causal claim → tool + object + quote (uncited claims are dropped) |
| **Root cause** | Class + cause + confidence. CrashLoopBackOff is not a cause |
| **Blast radius** | What else is healthy |
| **Recommendations** | What would address the cause (chart, TLS, quota, git). Not executed. Restart = mitigation |
| **Proposed change** | Unified diff against the workspace chart when the cause is in git. Never committed. |

**Running ≠ Ready ≠ reachable.** If the app is “down” but pods are Running, the
agent should inspect Service selectors and Endpoints, not only container logs.

Restart is a mitigation. If Endpoints are empty because of a selector mismatch,
restarting pods will not fix it — the RCA should say that.

## 4. Example session

You: `payments-api in namespace dto-e2e is down.`

Agent should:

1. Read `.github/memory/INDEX.md` (past incidents).
2. If cluster/namespace is missing or `dto-e2e` is not unique, **ask** (`clarify`) with numbered options.
3. List kube contexts; you pick one (`kube-context`). Later calls pass `context=`.
4. List **all** pods (not only `!=Running`), Warning events. If you named no workload, `cluster-scan` first.
5. Classify Crash / Not Ready / Unreachable.
6. Pull current **and previous** logs if restart count > 0.
7. Get Deployment, Service, Endpoints.
8. If a host/URL is involved: Ingress backend + TLS secret (`ingress-tls`).
9. `helm history --kube-context …` / git / `gh` for what changed (`change-correlation`).
10. Write the RCA: hypotheses, timeline, **evidence ledger**, recommendations, **proposed git diff** (not executed).

You may save to memory. The agent does not apply cluster changes.

## 5. Skills (when they apply)

| Skill | When |
|-------|------|
| `rca` | Every investigation (required write-up) |
| `token-thrift` | INDEX-only memory, tail=80 logs, at most two evidence skills |
| `clarify` | Missing or ambiguous cluster / namespace / workload — numbered questions |
| `kube-context` | Several clusters/files — list contexts, you pick |
| `cluster-scan` | Namespace health table before diving into one pod |
| `alert-intake` | Pasted Prometheus / Grafana / PagerDuty alert |
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
Token budget: [token-use.md](token-use.md) (`token-thrift` skill).

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

When the cause is in this repo, the RCA also includes **Proposed change**: a
unified diff against the chart/values. The agent never `git commit`s or
`gh pr create`s. If the fix is a cert or cluster quota outside git, it says
**no repo patch**.

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
If you have several kube contexts, pick `kind-dto-e2e` when the agent lists them
(`/use-cluster`). A vague `fix prod` should get clarifying questions, not a scan
of the wrong cluster.

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
| Agent asks instead of investigating | Intended when cluster/namespace/workload is ambiguous. Answer with a number. [clusters.md](clusters.md) |
| Wrong cluster | Step 1 / `/use-cluster`: pick from the context list; do not `kubectl config use-context` |
| Several kubeconfig files | Merge with `KUBECONFIG=a:b` (Unix) or `a;b` (Windows), restart kubernetes-inspect. [clusters.md](clusters.md) |
| Agent dumps huge YAML / values | It should summarize. See [token-use.md](token-use.md). Ask it to follow `token-thrift`. |
| 128-tool cap | Disable unused MCP servers (do not enable all DBs + Grafana at once) |

## 10. Security reminders

- Troubleshooter is read-only. It recommends; it does not apply.
- Use a `view` kubeconfig for investigation when you can.
- Database users: SELECT only. Grafana MCP: `--disable-write`.
- Never paste kubeconfig, tokens, or dump Secret data into chat.
