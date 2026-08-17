# User-Level Install

This guide sets up the DevOps Troubleshooter agent, skills, and MCP servers
in your user profile so they are available in **every workspace** —
no need to copy files into each repo.

Prefer workspace [init](init.md) when you only need this kit in one repo.
Init can write `~/.copilot/mcp-config.json` if that file does not already exist.

Primary usage is still **Copilot Chat → Agent mode**. See [copilot-vscode.md](copilot-vscode.md).
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
for s in k8s-incident service-path ingress-tls change-correlation gitops saturation rca helm-drift db-evidence observability incident-memory; do
  mkdir -p ~/.copilot/skills/$s
  cp .github/skills/$s/SKILL.md ~/.copilot/skills/$s/
done
```

**Windows (PowerShell):**
```powershell
$skills = "$env:USERPROFILE\.copilot\skills"
foreach ($s in @("k8s-incident","service-path","ingress-tls","change-correlation","gitops","saturation","rca","helm-drift","db-evidence","observability","incident-memory")) {
    New-Item -ItemType Directory -Force -Path "$skills\$s"
    Copy-Item ".github\skills\$s\SKILL.md" "$skills\$s\"
}
```

Skills loaded from `~/.copilot/skills/` (or `%USERPROFILE%\.copilot\skills\`
on Windows) are auto-discovered by Copilot in all workspaces.

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
5. Ask it to list your kube contexts to confirm connectivity.

## Managing multiple clusters

### Option A: Context switching (recommended)

Use a single kubeconfig with multiple contexts. The troubleshooter will
list all contexts and let you pick the right one at investigation time.

### Option B: Separate kubeconfig files

Point `KUBECONFIG` in `mcp.env` (or the OS environment) at different files for
different clusters. Restart the MCP server after switching, or configure multiple
MCP server entries (e.g., `kubernetes-inspect-prod`, `kubernetes-inspect-staging`).

## Security notes

- **Never commit credentials.** Put proxy URLs and DB passwords in `mcp.env` or OS environment variables, not in git.
- **Use a restricted kubeconfig.** Create a kubeconfig with a ServiceAccount bound to the `view` ClusterRole. See [deploy/rbac-troubleshooter-view.yaml](../deploy/rbac-troubleshooter-view.yaml).
- **Database users must be read-only.** Grant only `SELECT` and `CONNECT`.
- **Oracle Instant Client.** Install Instant Client. Set `ORACLE_HOME`. On Linux use `LD_LIBRARY_PATH`; on macOS `DYLD_LIBRARY_PATH`; on Windows add the Instant Client folder to **PATH**.

## Updating

**macOS / Linux:**
```bash
cp .github/agents/devops-troubleshooter.agent.md ~/.copilot/agents/
for s in k8s-incident service-path ingress-tls change-correlation gitops saturation rca helm-drift db-evidence observability incident-memory; do
  cp .github/skills/$s/SKILL.md ~/.copilot/skills/$s/
done
```

**Windows (PowerShell):**
```powershell
Copy-Item .github\agents\devops-troubleshooter.agent.md "$env:USERPROFILE\.copilot\agents\"
foreach ($s in @("k8s-incident","service-path","ingress-tls","change-correlation","gitops","saturation","rca","helm-drift","db-evidence","observability","incident-memory")) {
    Copy-Item ".github\skills\$s\SKILL.md" "$env:USERPROFILE\.copilot\skills\$s\"
}
```

Reload your VS Code window to pick up changes.

## Uninstalling

**macOS / Linux:**
```bash
rm -f ~/.copilot/agents/devops-troubleshooter.agent.md
rm -f ~/.copilot/agents/devops-remediator.agent.md
for s in k8s-incident service-path ingress-tls change-correlation gitops saturation rca helm-drift db-evidence observability incident-memory; do
  rm -rf ~/.copilot/skills/$s
done
```

**Windows (PowerShell):**
```powershell
Remove-Item "$env:USERPROFILE\.copilot\agents\devops-troubleshooter.agent.md" -ErrorAction SilentlyContinue
Remove-Item "$env:USERPROFILE\.copilot\agents\devops-remediator.agent.md" -ErrorAction SilentlyContinue
foreach ($s in @("k8s-incident","service-path","ingress-tls","change-correlation","gitops","saturation","rca","helm-drift","db-evidence","observability","incident-memory")) {
    Remove-Item -Recurse -Force "$env:USERPROFILE\.copilot\skills\$s" -ErrorAction SilentlyContinue
}
```

Remove the server entries from your user MCP configuration via
`MCP: Open User Configuration`.
