#!/usr/bin/env bash
set -euo pipefail

# Discover OS / IDE / agent harness and write MCP + agent config for this machine.
#
#   ./scripts/init.sh
#   ./scripts/init.sh --scope global
#   ./scripts/init.sh --scope workspace --yes
#   ./scripts/init.sh --mcp grafana,postgres,mongodb
#   ./scripts/init.sh --yes
#   ./scripts/init.sh --discover-only
#   ./scripts/init.sh --ide vscode,cursor,cli
#   ./scripts/init.sh --with-observability
#   ./scripts/init.sh --proxy http://proxy.corp:8080 --cacert /path/ca.pem
#   ./scripts/init.sh --kubeconfig "$HOME/.kube/config:$HOME/.kube/prod.config"

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
SCOPE=""
PROXY="${HTTPS_PROXY:-${https_proxy:-${HTTP_PROXY:-${http_proxy:-}}}}"
CACERT="${SSL_CERT_FILE:-${CURL_CA_BUNDLE:-}}"
KUBECONFIG_FLAG=""
GLOBAL_ROOT="${DTO_HOME:-${HOME}/.local/share/devops-troubleshooter}"
COPILOT_USER="${HOME}/.copilot"
CURSOR_USER="${HOME}/.cursor"

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
    --kubeconfig) KUBECONFIG_FLAG="${2:-}"; shift ;;
    --kubeconfig=*) KUBECONFIG_FLAG="${1#--kubeconfig=}" ;;
    --scope) SCOPE="${2:-}"; shift ;;
    --scope=*) SCOPE="${1#--scope=}" ;;
    --help|-h)
      cat <<'EOF'
Usage: ./scripts/init.sh [options]

Discover platform, IDEs, and agent harnesses, then write MCP configs.

  --discover-only         Print discovery report only (no downloads, no writes)
  --scope workspace|global
                          workspace = this repo only (default for --yes / CI)
                          global    = every workspace (~/.copilot + user MCP)
  --ide vscode,cursor,cli,jetbrains  Limit config writes (aliases: vs, cli, jb, claude)
  --mcp LIST              Non-interactive MCP pick (comma-separated). Always includes kubernetes.
                          Names: grafana,postgres,mysql,oracle,mssql,sqlite,clickhouse,
                          elasticsearch,neo4j,snowflake,mongodb  (or: all)
  --yes, -y               Skip scope + MCP prompts (workspace, kubernetes only, plus --mcp / --with-* / mcp.env)
  --with-observability    Add Grafana MCP (same as including grafana in --mcp)
  --with-databases        Download mcp-toolbox (still pick engines via prompt or --mcp)
  --proxy URL             HTTP proxy for binary download
  --cacert PEM            Corporate CA for binary download
  --kubeconfig PATHS      KUBECONFIG for MCP (one file, or colon-separated files on Unix)

On a TTY, init asks workspace vs global, then which optional MCPs to download.
EOF
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

have() { command -v "$1" >/dev/null 2>&1; }

normalize_scope() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d ' ')" in
    "" ) printf '' ;;
    workspace|repo|local|1) printf 'workspace' ;;
    global|user|profile|2) printf 'global' ;;
    *)
      echo "Unknown --scope: $1 (use workspace or global)" >&2
      exit 1
      ;;
  esac
}

SCOPE="$(normalize_scope "$SCOPE")"

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

if [ "$os" = "darwin" ]; then
  VSCODE_USER_MCP="${HOME}/Library/Application Support/Code/User/mcp.json"
else
  VSCODE_USER_MCP="${XDG_CONFIG_HOME:-${HOME}/.config}/Code/User/mcp.json"
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

kubeconfig="${KUBECONFIG_FLAG:-${KUBECONFIG:-${HOME}/.kube/config}}"

kubeconfig_any_exists() {
  local spec="$1"
  local f
  local IFS=':'
  for f in $spec; do
    [ -n "$f" ] && [ -f "$f" ] && return 0
  done
  return 1
}

kubeconfig_exists="false"
kubeconfig_any_exists "$kubeconfig" && kubeconfig_exists="true"

kube_contexts_json="[]"
kube_current=""
if have kubectl; then
  kube_current="$(KUBECONFIG="$kubeconfig" kubectl config current-context 2>/dev/null || true)"
  if have python3; then
    kube_contexts_json="$(
      { KUBECONFIG="$kubeconfig" kubectl config get-contexts -o name 2>/dev/null || true; } \
        | python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))'
    )" || kube_contexts_json="[]"
  fi
fi
[ -n "$kube_contexts_json" ] || kube_contexts_json="[]"
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
  "scope": "${SCOPE:-workspace}",
  "global_root": "$GLOBAL_ROOT",
  "session": "$session",
  "ides": "$ides",
  "harness": "$harness",
  "kubeconfig": "$kubeconfig",
  "kubeconfig_exists": $kubeconfig_exists,
  "kube_contexts": $kube_contexts_json,
  "kube_current_context": "$kube_current",
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

resolve_scope() {
  if [ -n "$SCOPE" ]; then
    echo "Install scope: $SCOPE (--scope)"
    return
  fi
  if [ "$ASSUME_YES" = true ] || [ -n "${GITHUB_ACTIONS:-}${CI:-}" ] || [ ! -t 0 ]; then
    SCOPE=workspace
    echo "Install scope: workspace (non-interactive default)"
    return
  fi
  cat <<'EOF'

Install scope:
  1) workspace — this repo only (.vscode/mcp.json, .github/agents)
  2) global    — every workspace (~/.copilot agents/skills + user MCP)

EOF
  printf 'Scope [workspace]: '
  local ans=""
  read -r ans || true
  case "$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]' | tr -d ' ')" in
    2|g|global|user|profile) SCOPE=global ;;
    *) SCOPE=workspace ;;
  esac
  echo "Install scope: $SCOPE"
}

echo "DevOps Troubleshooter init"
echo "  platform:  $os/$arch"
echo "  session:   $session"
echo "  IDEs:      ${ides:-none}"
echo "  harness:   ${harness:-none}"
echo "  kubeconfig: $kubeconfig $([ "$kubeconfig_exists" = true ] && echo '[found]' || echo '[missing]')"
if [ "$kube_contexts_json" != "[]" ]; then
  echo "  contexts:   $kube_contexts_json"
  echo "  current:    ${kube_current:-none}"
fi
echo "  helm:      $helm_ok   kubectl: $kubectl_ok"
echo ""

print_report > "$REPORT"

if [ "$DISCOVER_ONLY" = true ]; then
  echo "Discovery only. Report: $REPORT"
  exit 0
fi

resolve_scope
print_report > "$REPORT"

# --- binaries ---
setup_args=()
[ -n "$PROXY" ] && setup_args+=(--proxy "$PROXY")
[ -n "$CACERT" ] && setup_args+=(--cacert "$CACERT")

if [ "$SCOPE" = global ]; then
  mkdir -p "$GLOBAL_ROOT"
  if [ ! -f "${GLOBAL_ROOT}/mcp.env" ]; then
    if [ -f "${VSCODE_DIR}/mcp.env" ]; then
      cp "${VSCODE_DIR}/mcp.env" "${GLOBAL_ROOT}/mcp.env"
    else
      cp "${VSCODE_DIR}/mcp.env.example" "${GLOBAL_ROOT}/mcp.env"
    fi
  fi
  MCP_ENV_FILE="${GLOBAL_ROOT}/mcp.env"
else
  [ -f "${VSCODE_DIR}/mcp.env" ] || cp "${VSCODE_DIR}/mcp.env.example" "${VSCODE_DIR}/mcp.env"
  MCP_ENV_FILE="${VSCODE_DIR}/mcp.env"
fi

if [ -n "$KUBECONFIG_FLAG" ]; then
  envf="$MCP_ENV_FILE"
  tmp="${envf}.tmp"
  grep -vE '^[[:space:]]*#?[[:space:]]*KUBECONFIG=' "$envf" > "$tmp" || true
  printf 'KUBECONFIG=%s\n' "$kubeconfig" >> "$tmp"
  mv "$tmp" "$envf"
  echo "Wrote KUBECONFIG to $envf (restart kubernetes-inspect after init)"
fi

env_has() {
  [ -f "$MCP_ENV_FILE" ] && grep -qE "^[[:space:]]*$1=.+" "$MCP_ENV_FILE"
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
  [*] = already selected from flags or mcp.env

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

K8S_USE="$K8S_BIN"
TOOLBOX_USE="$TOOLBOX_BIN"
if [ "$SCOPE" = global ]; then
  mkdir -p "${GLOBAL_ROOT}/bin"
  cp -f "$K8S_BIN" "${GLOBAL_ROOT}/bin/kubernetes-mcp-server"
  chmod +x "${GLOBAL_ROOT}/bin/kubernetes-mcp-server"
  K8S_USE="${GLOBAL_ROOT}/bin/kubernetes-mcp-server"
  if [ -x "$TOOLBOX_BIN" ]; then
    cp -f "$TOOLBOX_BIN" "${GLOBAL_ROOT}/bin/toolbox"
    chmod +x "${GLOBAL_ROOT}/bin/toolbox"
    TOOLBOX_USE="${GLOBAL_ROOT}/bin/toolbox"
  fi
  echo "Installed MCP binaries under ${GLOBAL_ROOT}/bin"
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
  local envf="${4:-$MCP_ENV_FILE}"
  mkdir -p "$(dirname "$dest")"
  cat > "$dest" <<EOF
{
  "servers": {
    "kubernetes-inspect": {
      "type": "stdio",
      "command": "$k8s",
      "args": ["--read-only", "--toolsets", "core,config,helm"],
      "envFile": "${envf}"
    }${extra}
  }
}
EOF
}

merge_json_map() {
  local dest="$1" key="$2" src="$3"
  if have python3; then
    python3 - "$dest" "$key" "$src" <<'PY'
import json, os, sys
dest, key, src = sys.argv[1:4]
new = json.load(open(src, encoding="utf-8"))
old = {}
if os.path.exists(dest):
    try:
        old = json.load(open(dest, encoding="utf-8"))
    except Exception:
        old = {}
if not isinstance(old, dict):
    old = {}
incoming = new.get(key)
if incoming is None:
    incoming = new.get("servers") or new.get("mcpServers") or {}
if not isinstance(incoming, dict):
    incoming = {}
target_key = key
if key not in old and "mcpServers" in old and "servers" not in old:
    target_key = "mcpServers"
if target_key not in old or not isinstance(old.get(target_key), dict):
    old[target_key] = {}
old[target_key].update(incoming)
parent = os.path.dirname(dest)
if parent:
    os.makedirs(parent, exist_ok=True)
with open(dest, "w", encoding="utf-8") as f:
    json.dump(old, f, indent=2)
    f.write("\n")
PY
  else
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
  fi
}

install_global_kit_files() {
  mkdir -p "${COPILOT_USER}/agents" "${COPILOT_USER}/skills" "${COPILOT_USER}/prompts"
  cp -f "${ROOT_DIR}/.github/agents/devops-troubleshooter.agent.md" "${COPILOT_USER}/agents/"
  local skill
  for skill in "${ROOT_DIR}"/.github/skills/*/SKILL.md; do
    [ -f "$skill" ] || continue
    local name
    name="$(basename "$(dirname "$skill")")"
    mkdir -p "${COPILOT_USER}/skills/${name}"
    cp -f "$skill" "${COPILOT_USER}/skills/${name}/"
  done
  cp -f "${ROOT_DIR}"/.github/prompts/*.prompt.md "${COPILOT_USER}/prompts/" 2>/dev/null || true
  echo "Copied agent, skills, and prompts to ${COPILOT_USER}"
  if want_ide cursor || [ "$session" = "cursor" ] || [ -d "${ROOT_DIR}/.cursor" ] || [ -d "$CURSOR_USER" ]; then
    mkdir -p "${CURSOR_USER}/skills"
    for skill in "${ROOT_DIR}"/.github/skills/*/SKILL.md; do
      [ -f "$skill" ] || continue
      local name
      name="$(basename "$(dirname "$skill")")"
      mkdir -p "${CURSOR_USER}/skills/${name}"
      cp -f "$skill" "${CURSOR_USER}/skills/${name}/"
    done
    echo "Copied skills to ${CURSOR_USER}/skills"
  fi
}

DB_CMD="npx"
DB_PREFIX='["-y", "@toolbox-sdk/server", "--prebuilt='
DB_SUFFIX='", "--stdio"]'
if [ -x "$TOOLBOX_USE" ]; then
  DB_CMD="$TOOLBOX_USE"
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
      "envFile": "${MCP_ENV_FILE}"
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
      "envFile": "${MCP_ENV_FILE}"
    }
EOF
)
fi
if [ "$want_postgres" = true ] && ! env_has POSTGRES_HOST; then echo "  Reminder: set POSTGRES_HOST (and related) in $MCP_ENV_FILE"; fi
if [ "$want_mysql" = true ] && ! env_has MYSQL_HOST; then echo "  Reminder: set MYSQL_HOST in $MCP_ENV_FILE"; fi
if [ "$want_oracle" = true ] && ! env_has ORACLE_CONNECTION_STRING; then echo "  Reminder: set ORACLE_CONNECTION_STRING in $MCP_ENV_FILE"; fi
if [ "$want_mssql" = true ] && ! env_has MSSQL_HOST; then echo "  Reminder: set MSSQL_HOST in $MCP_ENV_FILE"; fi
if [ "$want_sqlite" = true ] && ! env_has SQLITE_DATABASE; then echo "  Reminder: set SQLITE_DATABASE in $MCP_ENV_FILE"; fi
if [ "$want_clickhouse" = true ] && ! env_has CLICKHOUSE_HOST; then echo "  Reminder: set CLICKHOUSE_HOST in $MCP_ENV_FILE"; fi
if [ "$want_elasticsearch" = true ] && ! env_has ELASTICSEARCH_HOST; then echo "  Reminder: set ELASTICSEARCH_HOST in $MCP_ENV_FILE"; fi
if [ "$want_neo4j" = true ] && ! env_has NEO4J_URI; then echo "  Reminder: set NEO4J_URI in $MCP_ENV_FILE"; fi
if [ "$want_snowflake" = true ] && ! env_has SNOWFLAKE_ACCOUNT; then echo "  Reminder: set SNOWFLAKE_ACCOUNT in $MCP_ENV_FILE"; fi
if [ "$want_mongodb" = true ] && ! env_has MDB_MCP_CONNECTION_STRING; then echo "  Reminder: set MDB_MCP_CONNECTION_STRING in $MCP_ENV_FILE"; fi
if [ "$want_grafana" = true ] && ! env_has GRAFANA_URL; then echo "  Reminder: set GRAFANA_URL and GRAFANA_SERVICE_ACCOUNT_TOKEN in $MCP_ENV_FILE"; fi
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
      "envFile": "'"${MCP_ENV_FILE}"'"
    }'
  else
    echo "Note: --with-observability needs uvx (https://docs.astral.sh/uv/). Skipping Grafana MCP."
  fi
fi

EXTRA_BLOCK="${DB_BLOCK}${GRAFANA_BLOCK}"

write_cursor_mcp() {
  local dest="$1"
  local k8s="$2"
  mkdir -p "$(dirname "$dest")"
  local grafana_cursor=""
  if [ -n "$GRAFANA_BLOCK" ]; then
    grafana_cursor=',
    "grafana": {
      "command": "uvx",
      "args": ["mcp-grafana", "--disable-write", "--enabled-tools", "datasource,prometheus,loki"]
    }'
  fi
  cat > "$dest" <<EOF
{
  "mcpServers": {
    "kubernetes-inspect": {
      "command": "$k8s",
      "args": ["--read-only", "--toolsets", "core,config,helm"],
      "env": { "KUBECONFIG": "$kubeconfig" }
    }${DB_BLOCK}${grafana_cursor}
  }
}
EOF
}

if [ "$SCOPE" = global ]; then
  install_global_kit_files
  tmp_mcp="$(mktemp)"
  write_copilot_mcp "$tmp_mcp" "$K8S_USE" "$EXTRA_BLOCK" "$MCP_ENV_FILE"
  merge_json_map "${COPILOT_USER}/mcp-config.json" servers "$tmp_mcp"
  echo "Wrote ${COPILOT_USER}/mcp-config.json"
  if want_ide vscode || [ -z "$IDE_FILTER" ]; then
    if [ -d "$(dirname "$VSCODE_USER_MCP")" ] || want_ide vscode; then
      merge_json_map "$VSCODE_USER_MCP" servers "$tmp_mcp"
      echo "Wrote $VSCODE_USER_MCP"
    fi
  fi
  rm -f "$tmp_mcp"
  if want_ide cursor || [ "$session" = "cursor" ] || [ -d "$CURSOR_USER" ]; then
    tmp_cursor="$(mktemp)"
    write_cursor_mcp "$tmp_cursor" "$K8S_USE"
    merge_json_map "${CURSOR_USER}/mcp.json" mcpServers "$tmp_cursor"
    rm -f "$tmp_cursor"
    echo "Wrote ${CURSOR_USER}/mcp.json"
  fi
  echo "Global install does not write workspace .mcp.json / .vscode/mcp.json"
else
  write_copilot_mcp "${ROOT_DIR}/.mcp.json" "$K8S_USE" "$EXTRA_BLOCK"
  echo "Wrote .mcp.json (Copilot CLI, Agent Host, Visual Studio, JetBrains workspace)"

  if want_ide vscode || [ -z "$IDE_FILTER" ]; then
    write_copilot_mcp "${VSCODE_DIR}/mcp.json" "$K8S_USE" "$EXTRA_BLOCK"
    echo "Wrote .vscode/mcp.json"
  fi

  if want_ide jetbrains || [ -d "${ROOT_DIR}/.idea" ]; then
    mkdir -p "${ROOT_DIR}/.github"
    write_copilot_mcp "${ROOT_DIR}/.github/mcp.json" "$K8S_USE" "$EXTRA_BLOCK"
    echo "Wrote .github/mcp.json (JetBrains Copilot workspace MCP)"
  fi

  if want_ide cursor || [ "$session" = "cursor" ] || [ -d "${ROOT_DIR}/.cursor" ]; then
    write_cursor_mcp "${ROOT_DIR}/.cursor/mcp.json" "$K8S_USE"
    echo "Wrote .cursor/mcp.json (Cursor mcpServers format)"
  fi

  if want_ide copilot-cli || { [ -z "$IDE_FILTER" ] && have copilot; }; then
    mkdir -p "${HOME}/.copilot"
    if [ ! -f "${HOME}/.copilot/mcp-config.json" ]; then
      write_copilot_mcp "${HOME}/.copilot/mcp-config.json" "$K8S_USE" "$EXTRA_BLOCK"
      echo "Wrote ~/.copilot/mcp-config.json"
    else
      echo "Left existing ~/.copilot/mcp-config.json unchanged"
    fi
  fi
fi

if [ "$helm_ok" != true ]; then
  echo ""
  echo "Warning: helm CLI not on PATH. helm history / helm get values will not work until you install Helm."
  echo "  macOS: brew install helm"
  echo "  Linux: https://helm.sh/docs/intro/install/"
fi
if [ "$kubeconfig_exists" != true ]; then
  echo "Warning: kubeconfig not found at $kubeconfig"
  echo "  Multiple files: KUBECONFIG=file1:file2:file3  (Windows: file1;file2)"
fi

echo ""
echo "Init complete ($SCOPE). Report: $REPORT"
if [ "$SCOPE" = global ]; then
  echo "Next: open any workspace → Copilot/Cursor Agent mode → DevOps Troubleshooter."
  echo "      Reload the window if the agent is missing. MCP: start kubernetes-inspect."
else
  echo "Next: open this repo in Copilot/Cursor Agent mode and choose DevOps Troubleshooter."
  echo "      MCP: start kubernetes-inspect (and grafana / db-* if enabled)."
fi
