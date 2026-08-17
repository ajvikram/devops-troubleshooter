# macOS (and Linux)

This kit is first-class on **macOS** (Apple Silicon and Intel) and **Linux**.
Use the bash scripts. Windows: [windows.md](windows.md).

Product: **identify issues and recommend** — never apply cluster changes.
Day-to-day: [user-guide.md](user-guide.md).

## 1. Prerequisites

```bash
# kubectl + Helm (recommended for helm history in RCAs)
brew install kubectl helm

# Optional: kind + Docker Desktop or Colima, for ./tests/e2e.sh
brew install kind
# Docker Desktop, or: brew install colima docker && colima start

# Optional Grafana MCP
brew install uv
```

Linux: install `kubectl`, `helm`, and `kind` from your distro or upstream binaries.
`scripts/setup.sh` supports `linux/amd64` and `linux/arm64`.

Kubeconfig default: `~/.kube/config` (override with `KUBECONFIG` in `.vscode/mcp.env`).

## 2. Init

```bash
./scripts/init.sh
# asks which optional MCPs to download (grafana, postgres, mongodb, …)
./scripts/init.sh --mcp grafana,postgres,mongodb
./scripts/init.sh --yes
```

Init downloads `bin/kubernetes-mcp-server` for `darwin/arm64`, `darwin/amd64`,
or `linux/*`, and writes `.vscode/mcp.json` with that absolute path.
Optional DBs: `./scripts/setup.sh --db-only` then copy only the `db-*` keys you need from `.vscode/mcp.databases.binary.json` (Postgres, MySQL, Oracle, SQL Server, SQLite, ClickHouse, Elasticsearch, Neo4j, Snowflake). MongoDB uses `npx mongodb-mcp-server --readOnly` (`MDB_MCP_CONNECTION_STRING`).
On **linux/arm64**, toolbox has no binary — use `.vscode/mcp.databases.json` (npx).
Optional Grafana: `./scripts/init.sh --with-observability` (`brew install uv`; `uvx` fetches `mcp-grafana`).

Apple Silicon: the binary must be `arm64`. If MCP fails with `Bad CPU type`,
re-run `./scripts/setup.sh --k8s-only` on the Mac that will run Copilot (do not
copy an amd64 binary from a CI amd64 runner).

## 3. VS Code / Copilot / Cursor

1. Open this folder.
2. Start **kubernetes-inspect** (**MCP: List Servers**). Trust it.
3. Agent mode → **DevOps Troubleshooter**.
4. Chat: `Ctrl+Cmd+I` (VS Code on Mac).

Cursor uses `.cursor/mcp.json` (`mcpServers`) written by init when Cursor is detected.

Behind SSL inspection: [proxy-ssl.md](proxy-ssl.md). macOS prefers the **system
keychain** for Go binaries; Node/`npx` still needs `NODE_EXTRA_CA_CERTS`.

## 4. Tests

```bash
./tests/kit.sh
./tests/e2e.sh --keep-cluster
```

kind needs a running container engine (Docker Desktop or Colima).

## 5. Helm and openssl

The troubleshooter’s allowlisted `execute` uses `helm` and `openssl` from PATH
(`helm history`, cert `notAfter`). Install with Homebrew as above.
`helm rollback` is **not** used.

## 6. npx (optional)

Default committed `.vscode/mcp.json` uses `npx` (works on macOS/Linux). Init
overwrites it with the binary. To stay on npx, skip init binaries or restore
from git. Prefer binaries on corporate laptops.

## 7. User-level install

Agents and skills can live in `~/.copilot/` for every workspace: [user-install.md](user-install.md).
