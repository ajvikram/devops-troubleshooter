# Using this kit in VS Code with GitHub Copilot

Day-to-day usage (prompts, RCA format, demo cluster): [user-guide.md](user-guide.md).
Several kube contexts or kubeconfig files: [clusters.md](clusters.md).

This is the primary path for **VS Code**. Custom agents, skills, and MCP servers are loaded by
**GitHub Copilot Chat in Agent mode** — not by Ask mode, and not by Copilot completions.

For other IDEs and CLIs, run [init.md](init.md) first. Agents have no `target: vscode` lock,
so the same `.github/agents` files work in Copilot CLI, Visual Studio, JetBrains, and Cursor.
macOS: [macos.md](macos.md). Windows: [windows.md](windows.md).

## What you need

- VS Code (Stable or Insiders)
- Extensions: **GitHub Copilot** and **GitHub Copilot Chat** (see `.vscode/extensions.json`)
- A Copilot subscription whose org policy allows **MCP** and **Agent mode**
- Setting `chat.mcp.access` not set to `none`

## First-run checklist

1. From the repo root, run init (asks **workspace vs global**, then which MCPs):
   ```bash
   ./scripts/init.sh
   ./scripts/init.sh --scope global    # every workspace
   ```
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\init.ps1
   .\scripts\init.ps1 -Scope global
   ```
   Or `--discover-only` / `-DiscoverOnly` to inspect detection without writing. See [init.md](init.md).
2. **Workspace:** open this folder (or copy `.github/` and `.vscode/` into the app repo). **Global:** open any folder; reload the window so **DevOps Troubleshooter** appears.
3. Secrets live in `mcp.env` (gitignored). Workspace: `.vscode/mcp.env`. Global: `~/.local/share/devops-troubleshooter/mcp.env` (Windows: `%LOCALAPPDATA%\devops-troubleshooter\mcp.env`). Init copies the example when the file is missing.
   On Windows workspace init, `init.ps1` points `.vscode\mcp.json` at `bin\*.exe`. See [windows.md](windows.md).
4. Behind a corporate proxy, follow [proxy-ssl.md](proxy-ssl.md) **before** starting MCP servers.
5. Command Palette → **MCP: List Servers** → start **kubernetes-inspect**.
   Trust the server when VS Code asks. If it fails, **Show Output** on that server.
6. Open **Copilot Chat** (`Ctrl+Cmd+I` on macOS, `Ctrl+Alt+I` on Windows).
7. Set the mode to **Agent** (not Ask, not Edit).
8. Open the **agents** dropdown and choose **DevOps Troubleshooter**.
   Or type `/` and pick **investigate**, **scan-namespace**, **from-alert**,
   **use-cluster**, or **clarify**.
9. Prompt example: `payments-api in staging is CrashLooping, namespace payments, after the 14:00 deploy.`
   If staging matches more than one kube context, the agent lists them and waits.
   That is intended — [clusters.md](clusters.md).

If the agent dropdown does not list DevOps Troubleshooter:

- Confirm `.github/agents/devops-troubleshooter.agent.md` exists in this workspace
- Command Palette → **Chat: Open Customizations** → Agents tab
- Reload the window

If Kubernetes tools never appear:

- The MCP server is not started, or was not trusted
- Copilot Chat is in Ask mode (no tools)
- Org policy blocked MCP
- You hit the **128 tools per request** cap — disable unused MCP servers in the tools picker (do not enable every `db-*` server plus Grafana at once)

## What you get

| In Copilot Chat | What happens |
|-----------------|--------------|
| **DevOps Troubleshooter** | Find the issue. RCA + **recommendations**. Never mutates the cluster. |

## Agent Host / Copilot harness

If **Agent Host** is enabled, VS Code does **not** send `${input:...}` MCP configs to the harness.

This kit's default `.vscode/mcp.json` has **no** `${input:}` variables so it can be forwarded. Put kubeconfig, proxy, and DB secrets in `.vscode/mcp.env` or in the OS environment instead.

Workspace init writes `.mcp.json` (and user `~/.copilot/mcp-config.json` if missing) in the Copilot `servers` schema. Cursor gets `.cursor/mcp.json` (`mcpServers`). JetBrains Copilot can use `.github/mcp.json`.

`./scripts/init.sh --scope global` installs the agent, skills, prompts, and user MCP so **every** workspace sees **DevOps Troubleshooter**. Reload the window after that install.

Cloud Copilot on github.com **cannot** use your laptop kubeconfig. This kit is local IDE first.

## Optional databases

Default MCP config is **kubernetes-inspect only** (read-only; keeps the tool list small).

To add Postgres / MySQL / Oracle, copy the `servers` keys from one of:

- [`.vscode/mcp.databases.binary.json`](../.vscode/mcp.databases.binary.json) — macOS/Linux `bin/toolbox` (`./scripts/setup.sh --db-only`)
- [`.vscode/mcp.databases.json`](../.vscode/mcp.databases.json) — macOS/Linux `npx`
- [`.vscode/mcp.databases.windows.json`](../.vscode/mcp.databases.windows.json) — Windows `bin\toolbox.exe`
- [`.vscode/mcp.databases.npx.windows.json`](../.vscode/mcp.databases.npx.windows.json) — Windows `npx.cmd`

into the existing `servers` object in `.vscode/mcp.json`. Do not replace the whole file. linux/arm64 has no toolbox binary — use the npx file.

Official connection variables (uncomment in `.vscode/mcp.env`; do **not** enable every server at once):

- Postgres: `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_DATABASE`, `POSTGRES_USER`, `POSTGRES_PASSWORD`
- MySQL: `MYSQL_HOST`, `MYSQL_PORT`, `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD`
- Oracle: `ORACLE_CONNECTION_STRING`, `ORACLE_USERNAME`, `ORACLE_PASSWORD`
- SQL Server: `MSSQL_HOST`, `MSSQL_PORT`, `MSSQL_DATABASE`, `MSSQL_USER`, `MSSQL_PASSWORD`
- SQLite: `SQLITE_DATABASE` (file path)
- ClickHouse: `CLICKHOUSE_HOST`, `CLICKHOUSE_PORT`, `CLICKHOUSE_USER`, `CLICKHOUSE_PASSWORD`, `CLICKHOUSE_DATABASE`, `CLICKHOUSE_PROTOCOL`
- Elasticsearch: `ELASTICSEARCH_HOST`, `ELASTICSEARCH_APIKEY`
- Neo4j: `NEO4J_URI`, `NEO4J_DATABASE`, `NEO4J_USERNAME`, `NEO4J_PASSWORD`
- Snowflake: `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`, `SNOWFLAKE_PASSWORD`, `SNOWFLAKE_DATABASE`, `SNOWFLAKE_SCHEMA`, `SNOWFLAKE_WAREHOUSE`, `SNOWFLAKE_ROLE`
- MongoDB: `MDB_MCP_CONNECTION_STRING` (official `mongodb-mcp-server`, always `--readOnly`)

## Optional Grafana (Prometheus / Loki)

```bash
./scripts/init.sh --with-observability
```

```powershell
.\scripts\init.ps1 -WithObservability
```

Or merge [`.vscode/mcp.grafana.json`](../.vscode/mcp.grafana.json) into `.vscode/mcp.json`. Set `GRAFANA_URL` and `GRAFANA_SERVICE_ACCOUNT_TOKEN` in `.vscode/mcp.env`. Requires `uvx`. The Grafana server is `--disable-write` and limited to datasource, Prometheus, and Loki tools (Copilot **128 tools** cap). Start **grafana** next to **kubernetes-inspect**.

## Slash prompts

Files in `.github/prompts/` show up when you type `/` in Copilot Chat (Agent mode):

| Prompt | Use |
|--------|-----|
| `/investigate` | Named incident → RCA + recommendations + proposed git diff |
| `/scan-namespace` | Namespace health table, then RCA |
| `/from-alert` | Paste Alertmanager / Grafana / PagerDuty JSON |
| `/use-cluster` | Pin a kube context first |
| `/clarify` | Vague prompt — numbered options, then investigate |

The agent also asks without `/clarify` when cluster, namespace, or workload is
ambiguous. Reply with a number. Do not run `kubectl config use-context`.

## Skills and memory

Skills in `.github/skills/` load on demand. Memory lives in `.github/memory/`.
The troubleshooter searches `INDEX.md` first and offers to save an incident after the RCA.
RCA write-up includes an **evidence ledger** and a **proposed change** (diff only).
Keep sessions small: [token-use.md](token-use.md) (`token-thrift` — INDEX-only memory, `tail=80`).
