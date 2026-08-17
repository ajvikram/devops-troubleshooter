# Multiple clusters and clarifying questions

The troubleshooter reads **whichever Kubernetes context you pick in chat**.
It does not run `kubectl config use-context` (that would rewrite your kubeconfig).
If the request is missing a cluster, namespace, or workload — or the name matches
more than one thing — it **asks** with a numbered list.

Day-to-day prompts: [user-guide.md](user-guide.md). Init flags: [init.md](init.md).
macOS: [macos.md](macos.md). Windows: [windows.md](windows.md).

## Pick a cluster in chat

1. Start **kubernetes-inspect**.
2. Agent mode → **DevOps Troubleshooter** (or `/use-cluster`).
3. The agent lists contexts from your kubeconfig. Reply with a **number** or a name.

After that, every Kubernetes MCP call uses `context: <name>`. Helm CLI uses
`--kube-context <name>`. The RCA **Symptom** line must include that context.

`/clarify` is the same idea when the prompt is vague (`fix prod`).

## When the agent must ask (blocking)

Wrong cluster = wrong RCA. It **stops** until you pick:

| Situation | What you see |
|-----------|----------------|
| Several kube contexts, no unique match | Numbered context table (current marked, not assumed) |
| `staging` / `prod` matches two context names | Only those rows; pick one |
| Namespace not given, several app namespaces | Namespace list (skips `kube-system` unless you asked) |
| Workload name hits two Deployments/Services | kind / name / namespace list |
| URL matches two Ingresses | hosts + backend Services |

Do not expect it to use kubeconfig `current-context` when more than one context exists.

## When it asks once, then continues

| Gap | If you skip |
|-----|-------------|
| When it started | Timeline: **unknown start** (first Warning / pod startTime) |
| User-facing impact | Symptom marked **inferred** from the object name |

At most **three questions** per turn. Blocking questions first.

## One kubeconfig, many contexts

Usual case. Nothing extra to configure.

```
~/.kube/config          # macOS / Linux
%USERPROFILE%\.kube\config   # Windows
```

Say `use context kind-dto-e2e` or pick from the list.

## Several kubeconfig files (merged)

The MCP process sees **one** `KUBECONFIG` value. Merge files, then **restart**
**kubernetes-inspect**.

**macOS / Linux** — colon:

```bash
# .vscode/mcp.env (gitignored)
KUBECONFIG=/Users/you/.kube/config:/Users/you/.kube/staging.config:/Users/you/.kube/prod.config
```

```bash
./scripts/init.sh --kubeconfig "$HOME/.kube/config:$HOME/.kube/prod.config"
```

**Windows** — **semicolon** (drive letters already use `:`):

```
KUBECONFIG=C:\Users\you\.kube\config;C:\Users\you\.kube\staging.config
```

```powershell
.\scripts\init.ps1 -Kubeconfig "$env:USERPROFILE\.kube\config;$env:USERPROFILE\.kube\prod.config"
```

Init writes `KUBECONFIG` into `.vscode/mcp.env`. Then pick a context in chat.

## Isolated MCP servers (prod must not mix with staging)

Copy [`.vscode/mcp.multi-cluster.example.json`](../.vscode/mcp.multi-cluster.example.json)
into `.vscode/mcp.json`. Point each server’s `--kubeconfig` at **one** file.
Start only the server you need. On Windows use `kubernetes-mcp-server.exe` (or
`npx.cmd`) as in the other Windows JSON files.

This is for process isolation. Prefer merged `KUBECONFIG` + `/use-cluster` unless
policy requires a separate MCP process for production.

## What the agent must never do

- `kubectl config use-context` / `kubectl config set-context`
- `configuration_view` (kubeconfig can contain tokens)
- Guess `default` namespace or the first pod when several match
- Dump kubeconfig contents into chat

## Init discovery

`./scripts/init.sh --discover-only` (or `.\scripts\init.ps1 -DiscoverOnly`) prints
the kubeconfig path, whether any file exists, context names (`kube_contexts`),
and `kube_current_context`. Current is informational only — chat pick still wins.
