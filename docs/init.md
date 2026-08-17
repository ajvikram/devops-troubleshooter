# Init: discover platform, IDE, and agent harness

`scripts/init.sh` (macOS/Linux) and `scripts/init.ps1` (Windows) detect where
this kit is running, download MCP binaries if needed, and write the MCP config
shape each harness expects.

Run this **first** in a new clone. You can still call `setup.sh` / `setup.ps1`
directly if you only want binaries.

Platform notes: [macos.md](macos.md) · [windows.md](windows.md).
Several kubeconfigs: [clusters.md](clusters.md).

## Quick start

```bash
./scripts/init.sh
```

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\init.ps1
```

On a terminal, init **asks workspace vs global**, then which MCP servers to download and wire. `kubernetes-inspect` is always installed. Optional: Grafana, Postgres, MySQL, Oracle, SQL Server, SQLite, ClickHouse, Elasticsearch, Neo4j, Snowflake, MongoDB.

| Scope | Where it lands |
|-------|----------------|
| **workspace** (default for `--yes` / CI) | This repo: `.vscode/mcp.json`, `.mcp.json`, `.github/agents` already in git |
| **global** | Every workspace: `~/.copilot` agents/skills/prompts + user MCP. Binaries and `mcp.env` under `~/.local/share/devops-troubleshooter` (Windows: `%LOCALAPPDATA%\devops-troubleshooter`) |

```bash
./scripts/init.sh --scope global
./scripts/init.sh --scope workspace --yes
```

```powershell
.\scripts\init.ps1 -Scope global
.\scripts\init.ps1 -Scope workspace -Yes
```

Non-interactive (CI, scripts, empty Enter = keep pre-selected). `--yes` / `-Yes` skips both prompts and uses **workspace**:

```bash
./scripts/init.sh --yes
./scripts/init.sh --mcp grafana,postgres,mongodb
```

```powershell
.\scripts\init.ps1 -Yes
.\scripts\init.ps1 -Mcp grafana,postgres,mongodb
```

Discovery only (no downloads, no config writes):

```bash
./scripts/init.sh --discover-only
```

```powershell
.\scripts\init.ps1 -DiscoverOnly
```

Optional Prometheus + Loki via Grafana:

```bash
./scripts/init.sh --with-observability
```

```powershell
.\scripts\init.ps1 -WithObservability
```

Then set `GRAFANA_URL` and `GRAFANA_SERVICE_ACCOUNT_TOKEN` in `.vscode/mcp.env` (workspace) or the global `mcp.env`.
Requires [`uv`](https://docs.astral.sh/uv/) (`uvx` on PATH). macOS: `brew install uv`.
`uvx` downloads `mcp-grafana` on first start — no separate binary.

Optional databases (Postgres / MySQL / Oracle):

```bash
./scripts/setup.sh --db-only
# or, if a DB connection var is set in mcp.env (POSTGRES_HOST, MYSQL_HOST,
# ORACLE_CONNECTION_STRING, MSSQL_HOST, SQLITE_DATABASE, CLICKHOUSE_HOST,
# ELASTICSEARCH_HOST, NEO4J_URI, SNOWFLAKE_ACCOUNT, MDB_MCP_CONNECTION_STRING):
./scripts/init.sh --with-databases
```

```powershell
.\scripts\setup.ps1 -DbOnly
.\scripts\init.ps1 -WithDatabases
```

linux/arm64 has **no** toolbox binary; use npx `.vscode/mcp.databases.json`.

Limit which IDE configs are written:

```bash
./scripts/init.sh --ide vscode,cursor
./scripts/init.sh --ide cli
```

```powershell
.\scripts\init.ps1 -Ide vscode,cursor
.\scripts\init.ps1 -Ide cli
```

Several kubeconfig files (merged; pick a context in chat after):

```bash
./scripts/init.sh --kubeconfig "$HOME/.kube/config:$HOME/.kube/prod.config"
```

```powershell
.\scripts\init.ps1 -Kubeconfig "$env:USERPROFILE\.kube\config;$env:USERPROFILE\.kube\prod.config"
```

Writes `KUBECONFIG` into `.vscode/mcp.env` (workspace) or the global `mcp.env`. Restart **kubernetes-inspect**. See [user-install.md](user-install.md#managing-multiple-clusters).

Behind a proxy, pass the same flags as setup:

```bash
./scripts/init.sh --proxy http://proxy.corp:8080 --cacert "$HOME/certs/corp-ca.pem"
```

```powershell
.\scripts\init.ps1 -Proxy http://proxy.corp:8080 -CaCert $env:USERPROFILE\certs\corp-ca.pem
```

## What it discovers

| Signal | How |
|--------|-----|
| OS / arch | `uname` or Windows `RuntimeInformation` (`darwin`/`linux`/`windows`, `amd64`/`arm64`) |
| Current session | Env: `CURSOR_TRACE_ID` / `CURSOR_AGENT` → Cursor; `VSCODE_PID` / `TERM_PROGRAM=vscode` → VS Code; `JETBRAINS_IDE` → JetBrains |
| Installed IDEs | CLIs on PATH (`code`, `cursor`, `copilot`, `claude`, JetBrains) plus workspace markers (`.vscode`, `.cursor`, `.idea`, `*.sln`) |
| Agent harness | Mapped from IDEs + `~/.copilot` + Agent Host hints in `.vscode/settings.json` |
| Cluster tools | kubeconfig path (supports `:` / `;` lists), `helm`, `kubectl` |
| Kube contexts | `kubectl config get-contexts` when kubectl is on PATH (`kube_contexts`, `kube_current_context` in the report) |
| Observability | `--with-observability` / `-WithObservability` or `GRAFANA_URL` already in `mcp.env` |
| Scope | `--scope workspace\|global` / `-Scope`; TTY prompt otherwise |

A JSON report is written to `.devops-troubleshooter-init.json` (gitignored).

### Harness labels

| Label | Typical product |
|-------|-----------------|
| `github-copilot-vscode` | VS Code Copilot Chat (Agent mode) |
| `github-copilot-visualstudio` | Visual Studio Copilot |
| `github-copilot-jetbrains` | JetBrains Copilot plugin |
| `github-copilot-cli` | Copilot CLI (`copilot` / `gh copilot`) |
| `vscode-agent-host` | VS Code Agent Host / Copilot harness |
| `copilot-user-profile` | `~/.copilot` user-level agents, skills, MCP |
| `cursor-agent` | Cursor Agent |
| `claude-code` | Claude Code |

## What it writes

### Workspace (`--scope workspace`)

| File | Schema | Used by |
|------|--------|---------|
| `.mcp.json` | Copilot `servers` | Copilot CLI, Agent Host, Visual Studio, JetBrains workspace |
| `.vscode/mcp.json` | Copilot `servers` | VS Code Copilot Chat |
| `.github/mcp.json` | Copilot `servers` | JetBrains Copilot (workspace) |
| `.cursor/mcp.json` | Cursor `mcpServers` | Cursor |
| `~/.copilot/mcp-config.json` | Copilot `servers` | Copilot CLI — **only if the file does not already exist** |

Generated MCP files use **absolute** paths to this clone’s `bin/kubernetes-mcp-server` (`.exe` on
Windows). Do not commit them. A portable template lives at
[`.mcp.json.example`](../.mcp.json.example).

Init copies `.vscode/mcp.env.example` → `.vscode/mcp.env` when missing,
and calls `setup.sh` / `setup.ps1` if the Kubernetes MCP binary is not in `bin/`.
`--kubeconfig` / `-Kubeconfig` upserts `KUBECONFIG=` in that `mcp.env`.

### Global (`--scope global`)

Does **not** write workspace `.mcp.json` / `.vscode/mcp.json` (avoids two `kubernetes-inspect` servers).

| Path | What |
|------|------|
| `~/.copilot/agents/devops-troubleshooter.agent.md` | Agent (remediator is not copied) |
| `~/.copilot/skills/*/SKILL.md` | All identification skills |
| `~/.copilot/prompts/*.prompt.md` | `/investigate` and the other slash prompts |
| `~/.copilot/mcp-config.json` | User MCP — **merges** `kubernetes-inspect` (and any DBs you picked) |
| VS Code **User** `mcp.json` | Same servers, merged, if VS Code is detected |
| `~/.cursor/mcp.json` + `~/.cursor/skills/` | If Cursor is detected |
| `~/.local/share/devops-troubleshooter/` (Windows `%LOCALAPPDATA%\devops-troubleshooter`) | MCP binaries + `mcp.env` so other repos do not depend on this clone |

Reload the IDE window after a global install. Details: [user-install.md](user-install.md).

## After init

1. Start **kubernetes-inspect** in your IDE (VS Code: Command Palette → **MCP: List Servers**). After a **global** install, reload the window and open any workspace.
2. Open Agent mode and choose **DevOps Troubleshooter** (or `/investigate` / `/use-cluster`).
3. If you have several contexts, pick one in chat. The agent will **ask** if the name is ambiguous. See [clusters.md](clusters.md).
4. Install **Helm** on PATH if you want `helm history` in RCAs:
   - macOS: `brew install helm`
   - Windows: `winget install Helm.Helm`
   - Linux: see [helm.sh](https://helm.sh/docs/intro/install/)
5. Merge database servers only if you need SQL evidence:
   - macOS/Linux binary: `.vscode/mcp.databases.binary.json` (after `./scripts/setup.sh --db-only`)
   - macOS/Linux npx: `.vscode/mcp.databases.json`
   - Windows binary: `.vscode/mcp.databases.windows.json`
   - Windows npx: `.vscode/mcp.databases.npx.windows.json` (`npx.cmd`)
   Copy **only the `db-*` servers you need** (Postgres, MySQL, Oracle, SQL Server, SQLite, ClickHouse, Elasticsearch, Neo4j, Snowflake, MongoDB).

Cloud Copilot on github.com cannot use laptop kubeconfig. This kit is local-first.
