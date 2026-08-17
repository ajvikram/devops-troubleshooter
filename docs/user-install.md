# User-Level Install

This guide sets up the DevOps Troubleshooter agent, skills, and MCP servers
in your user profile so they are available in **every workspace** —
no need to copy files into each repo.

**Preferred:** from this clone, let init do it:

```bash
./scripts/init.sh --scope global
```

```powershell
.\scripts\init.ps1 -Scope global
```

On a TTY, `./scripts/init.sh` (no flags) **asks** workspace vs global, then which MCPs.
`--yes` / `-Yes` stays **workspace** so CI does not write to your home directory.

Prefer workspace [init](init.md) when you only need this kit in one repo.
The rest of this page is the same layout if you want to copy files by hand.

Primary usage is still **Copilot Chat → Agent mode**. See [copilot-vscode.md](copilot-vscode.md).
Several kubeconfigs: [clusters.md](clusters.md).
Behind a corporate proxy, do [proxy-ssl.md](proxy-ssl.md) first.
macOS: [macos.md](macos.md). Windows: [windows.md](windows.md).

The product is **identify + RCA + recommendations**. Do not copy or start a
mutating Kubernetes MCP server.

## 1. Copy the agent profile

Copy **only** the troubleshooter. The remediator file in the repo is leftover
and hidden (`user-invocable: false`); skip it.

**macOS / Linux:**
```bash
mkdir -p ~/.copilot/agents
cp .github/agents/devops-troubleshooter.agent.md ~/.copilot/agents/
```

**Windows (PowerShell):**
```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.copilot\agents"
Copy-Item .github\agents\devops-troubleshooter.agent.md "$env:USERPROFILE\.copilot\agents\"
```

After copying, open VS Code and confirm **DevOps Troubleshooter** appears in the
Copilot Chat agents dropdown. If VS Code is already running, reload the window
(Command Palette → `Developer: Reload Window`).

## 2. Copy skills

**macOS / Linux:**
```bash
mkdir -p ~/.copilot/skills
for s in k8s-incident kube-context clarify token-thrift cluster-scan alert-intake service-path ingress-tls change-correlation gitops saturation rca helm-drift db-evidence observability incident-memory; do
  mkdir -p ~/.copilot/skills/$s
  cp .github/skills/$s/SKILL.md ~/.copilot/skills/$s/
done
```

**Windows (PowerShell):**
```powershell
$skills = "$env:USERPROFILE\.copilot\skills"
foreach ($s in @("k8s-incident","kube-context","clarify","token-thrift","cluster-scan","alert-intake","service-path","ingress-tls","change-correlation","gitops","saturation","rca","helm-drift","db-evidence","observability","incident-memory")) {
    New-Item -ItemType Directory -Force -Path "$skills\$s"
    Copy-Item ".github\skills\$s\SKILL.md" "$skills\$s\"
}
```

Skills loaded from `~/.copilot/skills/` (or `%USERPROFILE%\.copilot\skills\`
on Windows) are auto-discovered by Copilot in all workspaces.

Slash prompts (`/investigate`, `/use-cluster`, `/clarify`, …) are copied to
`~/.copilot/prompts/` on a global init. If your Copilot build only loads
workspace prompts, also copy `.github/prompts/` into the app repo you debug.

## 3. Configure MCP servers (user level)

Instead of using the workspace `.vscode/mcp.json`, add the servers to your
user-level MCP configuration:

1. Open the Command Palette → `MCP: Open User Configuration`
2. Add **kubernetes-inspect** only (see below)

The user MCP config file lives at `~/.copilot/mcp-config.json` (macOS/Linux) or
`%USERPROFILE%\.copilot\mcp-config.json` (Windows), or in VS Code user profile
data (**MCP: Open User Configuration**). It uses the same JSON format.

### Option A: Native binaries (no Node.js)

**macOS / Linux** — run `./scripts/setup.sh`, then point user MCP config at the binaries in `./bin/` or copy them to `~/.local/share/devops-troubleshooter/bin/`.

```json
{
  "servers": {
    "kubernetes-inspect": {
      "type": "stdio",
      "command": "/Users/YOU/.local/share/devops-troubleshooter/bin/kubernetes-mcp-server",
      "args": ["--read-only", "--toolsets", "core,config,helm"],
      "envFile": "/Users/YOU/.local/share/devops-troubleshooter/mcp.env"
    }
  }
}
```

**Windows** — from the repo root:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1
$dest = "$env:LOCALAPPDATA\devops-troubleshooter\bin"
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item .\bin\kubernetes-mcp-server.exe $dest
Copy-Item .\bin\toolbox.exe $dest -ErrorAction SilentlyContinue
```

Then in **MCP: Open User Configuration**:

```json
{
  "servers": {
    "kubernetes-inspect": {
      "type": "stdio",
      "command": "C:\\Users\\YOU\\AppData\\Local\\devops-troubleshooter\\bin\\kubernetes-mcp-server.exe",
      "args": ["--read-only", "--toolsets", "core,config,helm"],
      "envFile": "C:\\Users\\YOU\\AppData\\Local\\devops-troubleshooter\\mcp.env"
    }
  }
}
```

Replace `YOU` with your username. Copy `mcp.env.example` to that `mcp.env` path.

### Option B: npx (requires Node.js 18+)

**macOS / Linux:** `"command": "npx"`

```json
{
  "servers": {
    "kubernetes-inspect": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "kubernetes-mcp-server@latest", "--read-only", "--toolsets", "core,config,helm"]
    }
  }
}
```

**Windows:** `"command": "npx.cmd"` (required — `npx` will fail when VS Code spawns the process).

```json
{
  "servers": {
    "kubernetes-inspect": {
      "type": "stdio",
      "command": "npx.cmd",
      "args": ["-y", "kubernetes-mcp-server@latest", "--read-only", "--toolsets", "core,config,helm"]
    }
  }
}
```

Prefer Option A on corporate laptops (SSL inspection). See [proxy-ssl.md](proxy-ssl.md).

### Adding database or Grafana servers

Merge the `db-*` servers you need from `.vscode/mcp.databases.binary.json` (macOS/Linux `bin/toolbox`), `.vscode/mcp.databases.json` (npx), `.vscode/mcp.databases.windows.json` (`toolbox.exe`), or `.vscode/mcp.databases.npx.windows.json` (`npx.cmd`). Engines: Postgres, MySQL, Oracle, SQL Server, SQLite, ClickHouse, Elasticsearch, Neo4j, Snowflake, MongoDB (`mongodb-mcp-server --readOnly`). Put connection settings in `mcp.env`. linux/arm64: npx only. Do not enable every DB at once.

Grafana: merge `.vscode/mcp.grafana.json` and set `GRAFANA_URL` + `GRAFANA_SERVICE_ACCOUNT_TOKEN`. Requires `uvx`. Do not enable every server at once (Copilot **128 tools** cap).

## 4. Verify setup

1. Open any workspace in VS Code.
2. Command Palette → `MCP: List Servers` — you should see **kubernetes-inspect**.
3. Start **kubernetes-inspect**. Default kubeconfig is `~/.kube/config` (macOS/Linux) or `%USERPROFILE%\.kube\config` (Windows).
4. Open Copilot Chat → **Agent** mode → **DevOps Troubleshooter**.
5. Ask it to list your kube contexts to confirm connectivity. If several match,
   pick a number — do not expect it to guess `current-context`. [clusters.md](clusters.md).

## Managing multiple clusters

Full guide: [clusters.md](clusters.md).

The troubleshooter **picks a kube context in chat**. It does not rewrite
`kubectl config current-context`. If `staging`/`prod` matches more than one
context, it **asks**.

### Option A: One kubeconfig, many contexts (usual)

Contexts live in `~/.kube/config` (or `%USERPROFILE%\.kube\config`). Start
**kubernetes-inspect**, choose **DevOps Troubleshooter**, and either:

- Say `use context staging` / `/use-cluster`
- Or let it list contexts and pick a number

Every later MCP call uses `context: <name>`. Helm uses `--kube-context <name>`.

### Option B: Separate kubeconfig files (merged)

Point `KUBECONFIG` at **all** files, then restart **kubernetes-inspect**:

- macOS/Linux: `KUBECONFIG=/Users/you/.kube/config:/Users/you/.kube/prod.config`
- Windows: `KUBECONFIG=C:\Users\you\.kube\config;C:\Users\you\.kube\prod.config`

Put that in `.vscode/mcp.env` (gitignored) or pass:

```bash
./scripts/init.sh --scope global --kubeconfig "$HOME/.kube/config:$HOME/.kube/prod.config"
```

```powershell
.\scripts\init.ps1 -Kubeconfig "$env:USERPROFILE\.kube\config;$env:USERPROFILE\.kube\prod.config"
```

Then pick a context in chat as in Option A.

### Option C: Isolated MCP servers (prod must not mix with staging)

Copy [`.vscode/mcp.multi-cluster.example.json`](../.vscode/mcp.multi-cluster.example.json)
into `.vscode/mcp.json`, point `--kubeconfig` at one file per server, start only
the server you need. On Windows use `kubernetes-mcp-server.exe` and `npx.cmd`
as in the other Windows JSON files.

## Security notes

- **Never commit credentials.** Put proxy URLs and DB passwords in `mcp.env` or OS environment variables, not in git.
- **Use a restricted kubeconfig.** Create a kubeconfig with a ServiceAccount bound to the `view` ClusterRole. See [deploy/rbac-troubleshooter-view.yaml](../deploy/rbac-troubleshooter-view.yaml).
- **Database users must be read-only.** Grant only `SELECT` and `CONNECT`.
- **Oracle Instant Client.** Install Instant Client. Set `ORACLE_HOME`. On Linux use `LD_LIBRARY_PATH`; on macOS `DYLD_LIBRARY_PATH`; on Windows add the Instant Client folder to **PATH**.

## Updating

Re-run `./scripts/init.sh --scope global` (Windows: `.\scripts\init.ps1 -Scope global`) from this clone. Or copy by hand:

**macOS / Linux:**
```bash
cp .github/agents/devops-troubleshooter.agent.md ~/.copilot/agents/
for s in k8s-incident kube-context clarify token-thrift cluster-scan alert-intake service-path ingress-tls change-correlation gitops saturation rca helm-drift db-evidence observability incident-memory; do
  cp .github/skills/$s/SKILL.md ~/.copilot/skills/$s/
done
```

**Windows (PowerShell):**
```powershell
Copy-Item .github\agents\devops-troubleshooter.agent.md "$env:USERPROFILE\.copilot\agents\"
foreach ($s in @("k8s-incident","kube-context","clarify","token-thrift","cluster-scan","alert-intake","service-path","ingress-tls","change-correlation","gitops","saturation","rca","helm-drift","db-evidence","observability","incident-memory")) {
    Copy-Item ".github\skills\$s\SKILL.md" "$env:USERPROFILE\.copilot\skills\$s\"
}
```

Reload your VS Code window to pick up changes.

## Uninstalling

**macOS / Linux:**
```bash
rm -f ~/.copilot/agents/devops-troubleshooter.agent.md
rm -f ~/.copilot/agents/devops-remediator.agent.md
for s in k8s-incident kube-context clarify token-thrift cluster-scan alert-intake service-path ingress-tls change-correlation gitops saturation rca helm-drift db-evidence observability incident-memory; do
  rm -rf ~/.copilot/skills/$s
done
```

**Windows (PowerShell):**
```powershell
Remove-Item "$env:USERPROFILE\.copilot\agents\devops-troubleshooter.agent.md" -ErrorAction SilentlyContinue
Remove-Item "$env:USERPROFILE\.copilot\agents\devops-remediator.agent.md" -ErrorAction SilentlyContinue
foreach ($s in @("k8s-incident","kube-context","clarify","token-thrift","cluster-scan","alert-intake","service-path","ingress-tls","change-correlation","gitops","saturation","rca","helm-drift","db-evidence","observability","incident-memory")) {
    Remove-Item -Recurse -Force "$env:USERPROFILE\.copilot\skills\$s" -ErrorAction SilentlyContinue
}
```

Also remove `~/.copilot/prompts/` (Windows: `%USERPROFILE%\.copilot\prompts`) and
`~/.local/share/devops-troubleshooter` (Windows: `%LOCALAPPDATA%\devops-troubleshooter`).
Remove the server entries from your user MCP configuration via
`MCP: Open User Configuration` (and `~/.cursor/mcp.json` if Cursor was installed).
