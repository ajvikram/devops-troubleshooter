#!/usr/bin/env bash
set -euo pipefail

# Downloads pre-built Go binaries for the DevOps Troubleshooter MCP servers.
# Honors corporate proxy and custom CA bundles.
#
# Usage:
#   ./scripts/setup.sh
#   ./scripts/setup.sh --k8s-only
#   ./scripts/setup.sh --db-only
#   ./scripts/setup.sh --proxy http://proxy.corp:8080 --cacert /path/corp-ca.pem

K8S_VERSION="${K8S_MCP_VERSION:-0.0.66}"
TOOLBOX_VERSION="${TOOLBOX_VERSION:-1.9.0}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="${ROOT_DIR}/bin"

K8S_ONLY=false
DB_ONLY=false
PROXY="${HTTPS_PROXY:-${https_proxy:-${HTTP_PROXY:-${http_proxy:-}}}}"
CACERT="${SSL_CERT_FILE:-${CURL_CA_BUNDLE:-}}"

while [ $# -gt 0 ]; do
  case "$1" in
    --k8s-only) K8S_ONLY=true ;;
    --db-only)  DB_ONLY=true ;;
    --proxy)
      PROXY="${2:-}"
      shift
      ;;
    --proxy=*) PROXY="${1#--proxy=}" ;;
    --cacert)
      CACERT="${2:-}"
      shift
      ;;
    --cacert=*) CACERT="${1#--cacert=}" ;;
    --help|-h)
      echo "Usage: $0 [--k8s-only] [--db-only] [--proxy URL] [--cacert PEM]"
      echo ""
      echo "Environment variables:"
      echo "  K8S_MCP_VERSION   kubernetes-mcp-server version (default: $K8S_VERSION)"
      echo "  TOOLBOX_VERSION   mcp-toolbox version (default: $TOOLBOX_VERSION)"
      echo "  HTTPS_PROXY       corporate HTTP proxy URL"
      echo "  SSL_CERT_FILE     PEM bundle for SSL inspection (also CURL_CA_BUNDLE)"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
  shift
done

detect_platform() {
  local os arch
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"

  case "$os" in
    darwin) ;;
    linux)  ;;
    *)      echo "Unsupported OS: $os (use setup.ps1 for Windows)" >&2; exit 1 ;;
  esac

  case "$arch" in
    x86_64)  arch="amd64" ;;
    aarch64) arch="arm64" ;;
    arm64)   arch="arm64" ;;
    *)       echo "Unsupported architecture: $arch" >&2; exit 1 ;;
  esac

  echo "$os" "$arch"
}

curl_download() {
  local url="$1"
  local dest="$2"
  local args=(-fSL --progress-bar --connect-timeout 30 --retry 3 -o "$dest" "$url")

  if [ -n "$PROXY" ]; then
    args+=(--proxy "$PROXY")
    echo "  using proxy: $PROXY"
  fi
  if [ -n "$CACERT" ]; then
    args+=(--cacert "$CACERT")
    echo "  using CA bundle: $CACERT"
  fi

  curl "${args[@]}" || return 1
}

read -r OS ARCH <<< "$(detect_platform)"
echo "Platform: ${OS}/${ARCH}"
mkdir -p "$BIN_DIR"

if [ ! -f "${ROOT_DIR}/.vscode/mcp.env" ]; then
  cp "${ROOT_DIR}/.vscode/mcp.env.example" "${ROOT_DIR}/.vscode/mcp.env"
  echo "Created .vscode/mcp.env from example (fill in proxy/CA if needed)"
fi

if [ "$DB_ONLY" = false ]; then
  K8S_BINARY="kubernetes-mcp-server"
  K8S_URL="https://github.com/containers/kubernetes-mcp-server/releases/download/v${K8S_VERSION}/kubernetes-mcp-server-${OS}-${ARCH}"

  echo ""
  echo "Downloading kubernetes-mcp-server v${K8S_VERSION}..."
  curl_download "$K8S_URL" "${BIN_DIR}/${K8S_BINARY}"
  chmod +x "${BIN_DIR}/${K8S_BINARY}"
  echo "Installed: ${BIN_DIR}/${K8S_BINARY}"
fi

if [ "$K8S_ONLY" = false ]; then
  TOOLBOX_BINARY="toolbox"
  TOOLBOX_URL="https://storage.googleapis.com/mcp-toolbox-for-databases/v${TOOLBOX_VERSION}/${OS}/${ARCH}/toolbox"

  echo ""
  if [ "$OS" = "linux" ] && [ "$ARCH" = "arm64" ]; then
    echo "Note: mcp-toolbox v${TOOLBOX_VERSION} has no linux/arm64 binary."
    echo "      Use npx @toolbox-sdk/server — see .vscode/mcp.databases.json"
    if [ "$DB_ONLY" = true ]; then
      exit 1
    fi
  else
    echo "Downloading mcp-toolbox v${TOOLBOX_VERSION}..."
    if curl_download "$TOOLBOX_URL" "${BIN_DIR}/${TOOLBOX_BINARY}"; then
      chmod +x "${BIN_DIR}/${TOOLBOX_BINARY}"
      echo "Installed: ${BIN_DIR}/${TOOLBOX_BINARY}"
    else
      echo "Warning: toolbox download failed for ${OS}/${ARCH}."
      echo "         Use npx @toolbox-sdk/server — see .vscode/mcp.databases.json"
      if [ "$DB_ONLY" = true ]; then
        exit 1
      fi
    fi
  fi
fi

echo ""
echo "Setup complete. Binaries are in: ${BIN_DIR}/"
ls -lh "$BIN_DIR"/
echo ""
echo "Next steps:"
echo "  1. Prefer ./scripts/init.sh to write MCP configs (inspect-only + absolute binary path)"
echo "     or: cp .vscode/mcp.binary.json .vscode/mcp.json"
echo "  2. Optional DBs: copy servers from .vscode/mcp.databases.binary.json (or mcp.databases.json for npx)"
echo "  3. Optional Grafana: ./scripts/init.sh --with-observability (needs uvx)"
echo "  4. If you are behind a corporate proxy, edit .vscode/mcp.env (see docs/proxy-ssl.md)"
echo "  5. Open VS Code → Copilot Chat → Agent mode → DevOps Troubleshooter"
echo "  6. Command Palette → MCP: List Servers → start kubernetes-inspect"
