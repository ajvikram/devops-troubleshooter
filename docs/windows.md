# Windows (VS Code + GitHub Copilot)

This kit is first-class on Windows. Use **PowerShell** (Windows PowerShell 5.1 or PowerShell 7). Do not use Command Prompt for setup.

Product: **identify issues and recommend** — never apply cluster changes.
Day-to-day: [user-guide.md](user-guide.md). Several clusters: [clusters.md](clusters.md).
macOS: [macos.md](macos.md).

## 1. Run init (recommended)

From the repo root:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\init.ps1
```

Init discovers OS, IDE, and harness, **asks workspace vs global**, then which MCP servers to download.
Workspace writes `.mcp.json` plus `.vscode\mcp.json` with `.exe` paths.
Global (`-Scope global`) writes `%USERPROFILE%\.copilot` and `%LOCALAPPDATA%\devops-troubleshooter`.

```powershell
.\scripts\init.ps1 -Scope global
.\scripts\init.ps1 -Mcp grafana,postgres,mongodb
.\scripts\init.ps1 -Yes
.\scripts\init.ps1 -Kubeconfig "$env:USERPROFILE\.kube\config;$env:USERPROFILE\.kube\prod.config"
```

Discovery only:

```powershell
.\scripts\init.ps1 -DiscoverOnly
```

With Grafana (Prometheus + Loki):

```powershell
.\scripts\init.ps1 -WithObservability
```

Binaries-only (no harness detection):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1
```

`setup.ps1`:

- Downloads `bin\kubernetes-mcp-server.exe` (always) and `bin\toolbox.exe` unless `-K8sOnly`
- Use `-K8sOnly` / `-DbOnly` to fetch one server
- Unblocks the files (Windows marks internet downloads as unsafe)
- Copies `.vscode\mcp.binary.windows.json` → `.vscode\mcp.json` (`.exe` paths)
- Creates `.vscode\mcp.env` if it is missing
- Uses `curl.exe` when present, TLS 1.2, and the Windows proxy/credentials when needed

Behind a corporate proxy:

```powershell
.\scripts\init.ps1 -Proxy http://proxy.corp:8080 -CaCert $env:USERPROFILE\certs\corp-ca.pem
# binaries only:
.\scripts\setup.ps1 -Proxy http://proxy.corp:8080 -CaCert $env:USERPROFILE\certs\corp-ca.pem
```

## 2. Open in VS Code

1. File → Open Folder → this repo (or your app repo with `.github` + `.vscode` copied in).
2. Install the recommended extensions (**GitHub Copilot**, **GitHub Copilot Chat**).
3. Command Palette → **MCP: List Servers** → start **kubernetes-inspect**. Trust it.
4. Copilot Chat (`Ctrl+Alt+I`) → **Agent** mode → **DevOps Troubleshooter**, or `/investigate` / `/use-cluster` / `/clarify`.

Kubeconfig default on Windows is `%USERPROFILE%\.kube\config`. Several files — **semicolon** (not colon):

```
KUBECONFIG=C:\Users\you\.kube\config;C:\Users\you\.kube\staging.config
```

Restart **kubernetes-inspect** after editing `mcp.env`. In chat, pick a context (`/use-cluster`).
The agent **asks** if `staging`/`prod` matches more than one name. It must not run
`kubectl config use-context`. Details: [clusters.md](clusters.md).

## 3. If you insist on npx (Node.js)

VS Code on Windows must spawn `npx.cmd`, not `npx`.

```powershell
Copy-Item .vscode\mcp.npx.windows.json .vscode\mcp.json -Force
```

Node 18+ must be on PATH. Corporate SSL inspection still needs `NODE_EXTRA_CA_CERTS` in `.vscode\mcp.env`. Prefer the `.exe` path above.

## 4. Optional databases and Grafana

Merge `.vscode\mcp.databases.windows.json` into `.vscode\mcp.json` (toolbox `.exe` from `.\scripts\setup.ps1 -DbOnly`). Copy **only the `db-*` keys you need** (Postgres, MySQL, Oracle, SQL Server, SQLite, ClickHouse, Elasticsearch, Neo4j, Snowflake, MongoDB). Set matching vars in `.vscode\mcp.env`, or re-run `.\scripts\init.ps1 -WithDatabases`.

If you stay on npx, merge `.vscode\mcp.databases.npx.windows.json` (`npx.cmd`).

Oracle: install Instant Client and add it to **PATH** (not `LD_LIBRARY_PATH`).

Grafana (Prometheus + Loki): install `uv` so `uvx` is on PATH, then `.\scripts\init.ps1 -WithObservability`, or merge `.vscode\mcp.grafana.json`.

## 5. Proxy and SSL on Windows

See [proxy-ssl.md](proxy-ssl.md). Windows-specific notes:

| Item | Windows |
|------|---------|
| Proxy | `http.proxy` in User settings, plus `HTTPS_PROXY` in `mcp.env` |
| NTLM / Kerberos proxy | `setup.ps1` uses default Windows credentials with `Invoke-WebRequest`; Copilot may need `http.proxyKerberosServicePrincipal` |
| Corporate CA | Install in **Local Machine\Root**, or export PEM to `NODE_EXTRA_CA_CERTS` and `SSL_CERT_FILE` |
| PEM paths in `mcp.env` | Use backslashes or forward slashes, e.g. `C:\Users\you\certs\corp-ca.pem` |
| Blocked `.exe` | `setup.ps1` runs `Unblock-File`. If MCP still fails: Properties → Unblock on the file |

Launch VS Code from PowerShell so it inherits env vars:

```powershell
$env:NODE_EXTRA_CA_CERTS="$env:USERPROFILE\certs\corp-ca.pem"
$env:HTTPS_PROXY="http://proxy.corp.example.com:8080"
$env:HTTP_PROXY=$env:HTTPS_PROXY
code .
```

## 6. Helm CLI (read-only)

The troubleshooter uses `helm history` / `helm get values` via allowlisted `execute`.
Install Helm and ensure `helm.exe` is on PATH:

```powershell
winget install Helm.Helm
```

Copilot's Windows terminal is PowerShell, not `cmd.exe`. It does not run `helm rollback`.

## 7. Tests

Kit contract (no Docker):

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\kit.ps1
```

Full kind cluster e2e (Docker Desktop + [kind](https://kind.sigs.k8s.io/) + kubectl + Python 3):

```powershell
winget install Kubernetes.kubectl Kubernetes.kind Python.Python.3.12
powershell -ExecutionPolicy Bypass -File .\tests\e2e.ps1 -KeepCluster
```

Git Bash can also run `./tests/e2e.sh` if those tools are on PATH.

## 8. Execution policy

If you see `running scripts is disabled on this system`:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\init.ps1
```

Do not change machine policy unless IT allows it.

## 9. User-level install

`.\scripts\init.ps1 -Scope global` copies the agent and skills to `%USERPROFILE%\.copilot\` and MCP binaries to `%LOCALAPPDATA%\devops-troubleshooter`. Full commands: [user-install.md](user-install.md).
