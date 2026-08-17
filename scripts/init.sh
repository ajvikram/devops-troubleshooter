#!/usr/bin/env bash
set -euo pipefail

# Discover OS / IDE / agent harness and write MCP + agent config for this machine.
#
#   ./scripts/init.sh
#   ./scripts/init.sh --mcp grafana,postgres,mongodb
#   ./scripts/init.sh --yes
#   ./scripts/init.sh --discover-only
#   ./scripts/init.sh --ide vscode,cursor,cli
#   ./scripts/init.sh --with-observability
#   ./scripts/init.sh --proxy http://proxy.corp:8080 --cacert /path/ca.pem

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="${ROOT_DIR}/bin"
VSCODE_DIR="${ROOT_DIR}/.vscode"
REPORT="${ROOT_DIR}/.devops-troubleshooter-init.json"

DISCOVER_ONLY=false
WITH_OBS=false
WITH_DB=false
ASSUME_YES=false
MCP_SELECT=""
IDE_FILTER=""
PROXY="${HTTPS_PROXY:-${https_proxy:-${HTTP_PROXY:-${http_proxy:-}}}}"
CACERT="${SSL_CERT_FILE:-${CURL_CA_BUNDLE:-}}"

while [ $# -gt 0 ]; do
  case "$1" in
    --discover-only) DISCOVER_ONLY=true ;;
    --with-observability|--with-grafana) WITH_OBS=true ;;
    --with-databases|--with-db) WITH_DB=true ;;
    --yes|-y) ASSUME_YES=true ;;
    --mcp) MCP_SELECT="${2:-}"; shift ;;
    --mcp=*) MCP_SELECT="${1#--mcp=}" ;;
    --ide) IDE_FILTER="${2:-}"; shift ;;
    --ide=*) IDE_FILTER="${1#--ide=}" ;;
    --proxy) PROXY="${2:-}"; shift ;;
    --proxy=*) PROXY="${1#--proxy=}" ;;
    --cacert) CACERT="${2:-}"; shift ;;
    --cacert=*) CACERT="${1#--cacert=}" ;;
    --help|-h)
      cat <<'EOF'
Usage: ./scripts/init.sh [options]

Discover platform, IDEs, and agent harnesses, then write MCP configs.

  --discover-only         Print discovery report only (no downloads, no writes)
  --ide vscode,cursor,cli,jetbrains  Limit config writes (aliases: vs, cli, jb, claude)
  --mcp LIST              Non-interactive MCP pick (comma-separated). Always includes kubernetes.
                          Names: grafana,postgres,mysql,oracle,mssql,sqlite,clickhouse,
                          elasticsearch,neo4j,snowflake,mongodb  (or: all)
  --yes, -y               Skip the MCP prompt (kubernetes only, plus --mcp / --with-* / mcp.env)
  --with-observability    Add Grafana MCP (same as including grafana in --mcp)
  --with-databases        Download mcp-toolbox (still pick engines via prompt or --mcp)
  --proxy URL             HTTP proxy for binary download
  --cacert PEM            Corporate CA for binary download

On a TTY, init asks which optional MCPs to download and wire. CI / pipes skip the prompt.
EOF
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

have() { command -v "$1" >/dev/null 2>&1; }

os_name="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch_raw="$(uname -m)"
case "$arch_raw" in
  x86_64)  arch="amd64" ;;
  aarch64|arm64) arch="arm64" ;;
  *) arch="$arch_raw" ;;
esac
case "$os_name" in
  darwin) os="darwin" ;;
  linux)  os="linux" ;;
  mingw*|msys*|cygwin*) os="windows" ;;
  *) os="$os_name" ;;
esac

if [ "$os" = "windows" ]; then
  echo "Use scripts/init.ps1 on Windows." >&2
  exit 1
fi

EXE=""
K8S_BIN="${BIN_DIR}/kubernetes-mcp-server"
TOOLBOX_BIN="${BIN_DIR}/toolbox"

# --- session / IDE detection ---
session="unknown"
if [ -n "${CURSOR_TRACE_ID:-}" ] || [ -n "${CURSOR_AGENT:-}" ]; then
  session="cursor"
elif [ -n "${VSCODE_PID:-}" ] || [ -n "${VSCODE_INJECTION:-}" ] || [ "${TERM_PROGRAM:-}" = "vscode" ]; then
  session="vscode"
elif [ -n "${JETBRAINS_IDE:-}" ] || [ -n "${IDEA_INITIAL_DIRECTORY:-}" ]; then
  session="jetbrains"
fi

ides=""
add_ide() {
  case ",$ides," in
    *",$1,"*) ;;
    *) ides="${ides:+$ides,}$1" ;;
  esac
}

have code && add_ide vscode
have cursor && add_ide cursor
have copilot && add_ide copilot-cli
have claude && add_ide claude-code
have idea && add_ide jetbrains
have phpstorm && add_ide jetbrains
have pycharm && add_ide jetbrains
have goland && add_ide jetbrains
have webstorm && add_ide jetbrains
[ -d "${ROOT_DIR}/.vscode" ] && add_ide vscode
[ -d "${ROOT_DIR}/.cursor" ] && add_ide cursor
[ -d "${ROOT_DIR}/.idea" ] && add_ide jetbrains
[ -d "${ROOT_DIR}/.claude" ] && add_ide claude-code
ls "${ROOT_DIR}"/*.sln >/dev/null 2>&1 && add_ide visualstudio || true
[ "$session" != "unknown" ] && add_ide "$session"

harness=""
add_h() {
  case ",$harness," in
    *",$1,"*) ;;
    *) harness="${harness:+$harness,}$1" ;;
  esac
}
case ",$ides," in *",vscode,"*) add_h github-copilot-vscode ;; esac
case ",$ides," in *",cursor,"*) add_h cursor-agent ;; esac
case ",$ides," in *",copilot-cli,"*) add_h github-copilot-cli ;; esac
case ",$ides," in *",claude-code,"*) add_h claude-code ;; esac
case ",$ides," in *",jetbrains,"*) add_h github-copilot-jetbrains ;; esac
case ",$ides," in *",visualstudio,"*) add_h github-copilot-visualstudio ;; esac
[ -f "${ROOT_DIR}/.vscode/settings.json" ] && grep -q "agentHost\|Agent Host\|chat.agentHost" "${ROOT_DIR}/.vscode/settings.json" 2>/dev/null && add_h vscode-agent-host || true
[ -d "${HOME}/.copilot" ] && add_h copilot-user-profile

kubeconfig="${KUBECONFIG:-${HOME}/.kube/config}"
helm_ok="false"
have helm && helm_ok="true"
kubectl_ok="false"
have kubectl && kubectl_ok="true"
uvx_ok="false"
have uvx && uvx_ok="true"
npx_ok="false"
have npx && npx_ok="true"

grafana="false"
if [ -f "${VSCODE_DIR}/mcp.env" ] && grep -qE '^[[:space:]]*GRAFANA_URL=' "${VSCODE_DIR}/mcp.env"; then
  grafana="true"
fi
[ "$WITH_OBS" = true ] && grafana="true"

print_report() {
  cat <<EOF
{
  "platform": {"os": "$os", "arch": "$arch"},
  "workspace": "$ROOT_DIR",
  "session": "$session",
  "ides": "$ides",
  "harness": "$harness",
  "kubeconfig": "$kubeconfig",
  "kubeconfig_exists": $([ -f "$kubeconfig" ] && echo true || echo false),
  "helm": $helm_ok,
  "kubectl": $kubectl_ok,
  "uvx": $uvx_ok,
  "npx": $npx_ok,
  "observability": $grafana,
  "binaries": {
    "kubernetes-mcp-server": $([ -x "$K8S_BIN" ] && echo true || echo false),
    "toolbox": $([ -x "$TOOLBOX_BIN" ] && echo true || echo false)
  }
}
EOF
}

echo "DevOps Troubleshooter init"
echo "  platform:  $os/$arch"
echo "  session:   $session"
echo "  IDEs:      ${ides:-none}"
echo "  harness:   ${harness:-none}"
echo "  kubeconfig: $kubeconfig $([ -f "$kubeconfig" ] && echo '[found]' || echo '[missing]')"
echo "  helm:      $helm_ok   kubectl: $kubectl_ok"
echo ""

print_report > "$REPORT"

if [ "$DISCOVER_ONLY" = true ]; then
  echo "Discovery only. Report: $REPORT"
  exit 0
fi

# --- binaries ---
setup_args=()
[ -n "$PROXY" ] && setup_args+=(--proxy "$PROXY")
[ -n "$CACERT" ] && setup_args+=(--cacert "$CACERT")

[ -f "${VSCODE_DIR}/mcp.env" ] || cp "${VSCODE_DIR}/mcp.env.example" "${VSCODE_DIR}/mcp.env"

env_has() {
  [ -f "${VSCODE_DIR}/mcp.env" ] && grep -qE "^[[:space:]]*$1=.+" "${VSCODE_DIR}/mcp.env"
}

want_grafana=false
want_postgres=false
want_mysql=false
want_oracle=false
want_mssql=false
want_sqlite=false
want_clickhouse=false
want_elasticsearch=false
want_neo4j=false
want_snowflake=false
want_mongodb=false

[ "$WITH_OBS" = true ] && want_grafana=true
[ "$grafana" = true ] && want_grafana=true
env_has POSTGRES_HOST && want_postgres=true
env_has MYSQL_HOST && want_mysql=true
env_has ORACLE_CONNECTION_STRING && want_oracle=true
env_has MSSQL_HOST && want_mssql=true
env_has SQLITE_DATABASE && want_sqlite=true
env_has CLICKHOUSE_HOST && want_clickhouse=true
env_has ELASTICSEARCH_HOST && want_elasticsearch=true
env_has NEO4J_URI && want_neo4j=true
env_has SNOWFLAKE_ACCOUNT && want_snowflake=true
env_has MDB_MCP_CONNECTION_STRING && want_mongodb=true

mark_mcp() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d ' ')" in
    ""|k8s|kubernetes|inspect) ;;
    1|grafana|obs|observability) want_grafana=true ;;
    2|postgres|postgresql|pg) want_postgres=true ;;
    3|mysql|mariadb) want_mysql=true ;;
    4|oracle|oracledb) want_oracle=true ;;
    5|mssql|sqlserver|sql-server) want_mssql=true ;;
    6|sqlite) want_sqlite=true ;;
    7|clickhouse) want_clickhouse=true ;;
    8|elasticsearch|elastic|es) want_elasticsearch=true ;;
    9|neo4j) want_neo4j=true ;;
    10|snowflake) want_snowflake=true ;;
    11|mongodb|mongo) want_mongodb=true ;;
    all)
      want_grafana=true want_postgres=true want_mysql=true want_oracle=true
      want_mssql=true want_sqlite=true want_clickhouse=true want_elasticsearch=true
      want_neo4j=true want_snowflake=true want_mongodb=true
      echo "Warning: enabling every DB plus Grafana can exceed Copilot's 128-tool cap."
      ;;
    none) ;;
    *) echo "Unknown MCP choice: $1 (ignored)" ;;
  esac
}

apply_mcp_list() {
  local raw="$1" tok
  raw="$(printf '%s' "$raw" | tr ',' ' ')"
  for tok in $raw; do
    mark_mcp "$tok"
  done
}

print_mcp_menu() {
  flag() { [ "$1" = true ] && printf '*' || printf ' '; }
  cat <<EOF

Choose optional MCP servers to download and wire. kubernetes-inspect is always installed.
  [*] = already selected from flags or .vscode/mcp.env

  $(flag "$want_grafana")  1) grafana         Prometheus + Loki via Grafana (uvx)
  $(flag "$want_postgres")  2) postgres
  $(flag "$want_mysql")  3) mysql
  $(flag "$want_oracle")  4) oracle
  $(flag "$want_mssql")  5) mssql           SQL Server
  $(flag "$want_sqlite")  6) sqlite
  $(flag "$want_clickhouse")  7) clickhouse
  $(flag "$want_elasticsearch")  8) elasticsearch
  $(flag "$want_neo4j")  9) neo4j
  $(flag "$want_snowflake") 10) snowflake
  $(flag "$want_mongodb") 11) mongodb         official MCP, --readOnly

Comma-separated numbers or names. Examples: 1,2,11   grafana,postgres,mongodb   all
Empty keeps the [*] selections (kubernetes only if none are marked).
EOF
}

if [ -n "$MCP_SELECT" ]; then
  apply_mcp_list "$MCP_SELECT"
  echo "MCP selection (--mcp): $MCP_SELECT"
elif [ "$ASSUME_YES" = true ]; then
  echo "Skipping MCP prompt (--yes). kubernetes-inspect plus any flags / mcp.env."
elif [ -n "${GITHUB_ACTIONS:-}${CI:-}" ] || [ ! -t 0 ]; then
  echo "Non-interactive session: kubernetes-inspect plus any flags / mcp.env."
  echo "  To choose MCPs: ./scripts/init.sh --mcp grafana,postgres,mongodb"
else
  print_mcp_menu
  printf 'MCPs to install: '
  mcp_ans=""
  read -r mcp_ans || true
  if [ -n "$mcp_ans" ]; then
    apply_mcp_list "$mcp_ans"
  fi
fi

if [ "$want_grafana" = true ]; then
  grafana=true
fi

echo "Will install: kubernetes-inspect$( [ "$want_grafana" = true ] && printf ', grafana' )$( [ "$want_postgres" = true ] && printf ', postgres' )$( [ "$want_mysql" = true ] && printf ', mysql' )$( [ "$want_oracle" = true ] && printf ', oracle' )$( [ "$want_mssql" = true ] && printf ', mssql' )$( [ "$want_sqlite" = true ] && printf ', sqlite' )$( [ "$want_clickhouse" = true ] && printf ', clickhouse' )$( [ "$want_elasticsearch" = true ] && printf ', elasticsearch' )$( [ "$want_neo4j" = true ] && printf ', neo4j' )$( [ "$want_snowflake" = true ] && printf ', snowflake' )$( [ "$want_mongodb" = true ] && printf ', mongodb' )"
echo ""

if [ ! -x "$K8S_BIN" ]; then
  echo "Downloading kubernetes-mcp-server..."
  "${ROOT_DIR}/scripts/setup.sh" --k8s-only "${setup_args[@]+"${setup_args[@]}"}"
fi
if [ ! -x "$K8S_BIN" ]; then
  echo "kubernetes-mcp-server binary missing. Run ./scripts/setup.sh --k8s-only" >&2
  exit 1
fi

want_toolbox=false
if [ "$want_postgres" = true ] || [ "$want_mysql" = true ] || [ "$want_oracle" = true ] \
  || [ "$want_mssql" = true ] || [ "$want_sqlite" = true ] || [ "$want_clickhouse" = true ] \
  || [ "$want_elasticsearch" = true ] || [ "$want_neo4j" = true ] || [ "$want_snowflake" = true ]; then
  want_toolbox=true
fi
if [ "$WITH_DB" = true ] || [ "$want_toolbox" = true ]; then
  if [ ! -x "$TOOLBOX_BIN" ]; then
    echo "Downloading mcp-toolbox (selected databases)..."
    "${ROOT_DIR}/scripts/setup.sh" --db-only "${setup_args[@]+"${setup_args[@]}"}" || true
  fi
fi

normalize_ide() {
  case "$1" in
    vs|vscode) echo vscode ;;
    cursor) echo cursor ;;
    cli|copilot-cli|copilot) echo copilot-cli ;;
    jb|jetbrains) echo jetbrains ;;
    visualstudio|vs-ide) echo visualstudio ;;
    claude|claude-code) echo claude-code ;;
    *) echo "$1" ;;
  esac
}

want_ide() {
  local name="$1"
  if [ -z "$IDE_FILTER" ]; then
    case ",$ides," in *",$name,"*) return 0 ;; *) return 1 ;; esac
  fi
  local token mapped
  local IFS=','
  for token in $IDE_FILTER; do
    mapped="$(normalize_ide "$(printf '%s' "$token" | tr -d ' ' | tr '[:upper:]' '[:lower:]')")"
    [ "$mapped" = "$name" ] && return 0
  done
  return 1
}

# Always write portable Copilot .mcp.json (CLI, Agent Host, VS, JetBrains)
write_copilot_mcp() {
  local dest="$1"
  local k8s="$2"
  local extra="$3"
  mkdir -p "$(dirname "$dest")"
  cat > "$dest" <<EOF
{
  "servers": {
    "kubernetes-inspect": {
      "type": "stdio",
      "command": "$k8s",
      "args": ["--read-only", "--toolsets", "core,config,helm"],
      "envFile": "${VSCODE_DIR}/mcp.env"
    }${extra}
  }
}
EOF
}

DB_CMD="npx"
DB_PREFIX='["-y", "@toolbox-sdk/server", "--prebuilt='
DB_SUFFIX='", "--stdio"]'
if [ -x "$TOOLBOX_BIN" ]; then
  DB_CMD="$TOOLBOX_BIN"
  DB_PREFIX='["--prebuilt='
  DB_SUFFIX='", "--stdio"]'
fi

DB_BLOCK=""
add_db_server() {
  local name="$1" prebuilt="$2"
  DB_BLOCK+=$(cat <<EOF
,
    "$name": {
      "type": "stdio",
      "command": "$DB_CMD",
      "args": ${DB_PREFIX}${prebuilt}${DB_SUFFIX},
      "envFile": "${VSCODE_DIR}/mcp.env"
    }
EOF
)
}
[ "$want_postgres" = true ] && add_db_server db-postgres postgres
[ "$want_mysql" = true ] && add_db_server db-mysql mysql
[ "$want_oracle" = true ] && add_db_server db-oracle oracle
[ "$want_mssql" = true ] && add_db_server db-mssql mssql
[ "$want_sqlite" = true ] && add_db_server db-sqlite sqlite
[ "$want_clickhouse" = true ] && add_db_server db-clickhouse clickhouse
[ "$want_elasticsearch" = true ] && add_db_server db-elasticsearch elasticsearch
[ "$want_neo4j" = true ] && add_db_server db-neo4j neo4j
[ "$want_snowflake" = true ] && add_db_server db-snowflake snowflake
if [ "$want_mongodb" = true ]; then
  DB_BLOCK+=$(cat <<EOF
,
    "db-mongodb": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "mongodb-mcp-server@latest", "--readOnly"],
      "envFile": "${VSCODE_DIR}/mcp.env"
    }
EOF
)
fi
if [ "$want_postgres" = true ] && ! env_has POSTGRES_HOST; then echo "  Reminder: set POSTGRES_HOST (and related) in .vscode/mcp.env"; fi
if [ "$want_mysql" = true ] && ! env_has MYSQL_HOST; then echo "  Reminder: set MYSQL_HOST in .vscode/mcp.env"; fi
if [ "$want_oracle" = true ] && ! env_has ORACLE_CONNECTION_STRING; then echo "  Reminder: set ORACLE_CONNECTION_STRING in .vscode/mcp.env"; fi
if [ "$want_mssql" = true ] && ! env_has MSSQL_HOST; then echo "  Reminder: set MSSQL_HOST in .vscode/mcp.env"; fi
if [ "$want_sqlite" = true ] && ! env_has SQLITE_DATABASE; then echo "  Reminder: set SQLITE_DATABASE in .vscode/mcp.env"; fi
if [ "$want_clickhouse" = true ] && ! env_has CLICKHOUSE_HOST; then echo "  Reminder: set CLICKHOUSE_HOST in .vscode/mcp.env"; fi
if [ "$want_elasticsearch" = true ] && ! env_has ELASTICSEARCH_HOST; then echo "  Reminder: set ELASTICSEARCH_HOST in .vscode/mcp.env"; fi
if [ "$want_neo4j" = true ] && ! env_has NEO4J_URI; then echo "  Reminder: set NEO4J_URI in .vscode/mcp.env"; fi
if [ "$want_snowflake" = true ] && ! env_has SNOWFLAKE_ACCOUNT; then echo "  Reminder: set SNOWFLAKE_ACCOUNT in .vscode/mcp.env"; fi
if [ "$want_mongodb" = true ] && ! env_has MDB_MCP_CONNECTION_STRING; then echo "  Reminder: set MDB_MCP_CONNECTION_STRING in .vscode/mcp.env"; fi
if [ "$want_grafana" = true ] && ! env_has GRAFANA_URL; then echo "  Reminder: set GRAFANA_URL and GRAFANA_SERVICE_ACCOUNT_TOKEN in .vscode/mcp.env"; fi
if [ "$want_mongodb" = true ]; then echo "  MongoDB package downloads via npx the first time you start db-mongodb."; fi
if [ "$want_grafana" = true ]; then echo "  Grafana package downloads via uvx the first time you start grafana."; fi

GRAFANA_ARGS='["mcp-grafana", "--disable-write", "--enabled-tools", "datasource,prometheus,loki"]'
GRAFANA_BLOCK=""
if [ "$grafana" = true ]; then
  if have uvx; then
    GRAFANA_BLOCK=',
    "grafana": {
      "type": "stdio",
      "command": "uvx",
      "args": '"${GRAFANA_ARGS}"',
      "envFile": "'"${VSCODE_DIR}/mcp.env"'"
    }'
  else
    echo "Note: --with-observability needs uvx (https://docs.astral.sh/uv/). Skipping Grafana MCP."
  fi
fi

EXTRA_BLOCK="${DB_BLOCK}${GRAFANA_BLOCK}"

write_copilot_mcp "${ROOT_DIR}/.mcp.json" "$K8S_BIN" "$EXTRA_BLOCK"
echo "Wrote .mcp.json (Copilot CLI, Agent Host, Visual Studio, JetBrains workspace)"

if want_ide vscode || [ -z "$IDE_FILTER" ]; then
  write_copilot_mcp "${VSCODE_DIR}/mcp.json" "$K8S_BIN" "$EXTRA_BLOCK"
  echo "Wrote .vscode/mcp.json"
fi

if want_ide jetbrains || [ -d "${ROOT_DIR}/.idea" ]; then
  mkdir -p "${ROOT_DIR}/.github"
  write_copilot_mcp "${ROOT_DIR}/.github/mcp.json" "$K8S_BIN" "$EXTRA_BLOCK"
  echo "Wrote .github/mcp.json (JetBrains Copilot workspace MCP)"
fi

if want_ide cursor || [ "$session" = "cursor" ] || [ -d "${ROOT_DIR}/.cursor" ]; then
  mkdir -p "${ROOT_DIR}/.cursor"
  grafana_cursor=""
  if [ -n "$GRAFANA_BLOCK" ]; then
    grafana_cursor=',
    "grafana": {
      "command": "uvx",
      "args": ["mcp-grafana", "--disable-write", "--enabled-tools", "datasource,prometheus,loki"]
    }'
  fi
  cat > "${ROOT_DIR}/.cursor/mcp.json" <<EOF
{
  "mcpServers": {
    "kubernetes-inspect": {
      "command": "$K8S_BIN",
      "args": ["--read-only", "--toolsets", "core,config,helm"],
      "env": { "KUBECONFIG": "$kubeconfig" }
    }${DB_BLOCK}${grafana_cursor}
  }
}
EOF
  echo "Wrote .cursor/mcp.json (Cursor mcpServers format)"
fi

if want_ide copilot-cli || { [ -z "$IDE_FILTER" ] && have copilot; }; then
  mkdir -p "${HOME}/.copilot"
  if [ ! -f "${HOME}/.copilot/mcp-config.json" ]; then
    write_copilot_mcp "${HOME}/.copilot/mcp-config.json" "$K8S_BIN" "$EXTRA_BLOCK"
    echo "Wrote ~/.copilot/mcp-config.json"
  else
    echo "Left existing ~/.copilot/mcp-config.json unchanged"
  fi
fi

if [ "$helm_ok" != true ]; then
  echo ""
  echo "Warning: helm CLI not on PATH. helm history / helm get values will not work until you install Helm."
  echo "  macOS: brew install helm"
  echo "  Linux: https://helm.sh/docs/intro/install/"
fi
if [ ! -f "$kubeconfig" ]; then
  echo "Warning: kubeconfig not found at $kubeconfig"
fi

echo ""
echo "Init complete. Report: $REPORT"
echo "Next: open Copilot/Cursor Agent mode and choose DevOps Troubleshooter."
echo "      MCP: start kubernetes-inspect (and grafana / db-* if enabled)."
