#!/usr/bin/env bash
set -euo pipefail

# Fast contract tests: agents, skills, JSON, init discovery. No cluster required.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
fail=0

ok() { printf '  OK  %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fail=1; }

echo "== kit contract"

# --- required files ---
required=(
  README.md
  docs/user-guide.md
  docs/init.md
  docs/copilot-vscode.md
  docs/macos.md
  docs/windows.md
  docs/images/hero.png
  docs/images/architecture.png
  docs/images/rca-flow.png
  docs/proxy-ssl.md
  docs/user-install.md
  docs/clusters.md
  docs/token-use.md
  .github/agents/devops-troubleshooter.agent.md
  .github/agents/devops-remediator.agent.md
  .github/skills/rca/SKILL.md
  .github/skills/cluster-scan/SKILL.md
  .github/skills/alert-intake/SKILL.md
  .github/skills/kube-context/SKILL.md
  .github/skills/clarify/SKILL.md
  .github/skills/token-thrift/SKILL.md
  .github/prompts/investigate.prompt.md
  .github/prompts/scan-namespace.prompt.md
  .github/prompts/from-alert.prompt.md
  .github/prompts/use-cluster.prompt.md
  .github/prompts/clarify.prompt.md
  .github/skills/k8s-incident/SKILL.md
  .github/skills/service-path/SKILL.md
  .github/skills/ingress-tls/SKILL.md
  .github/skills/change-correlation/SKILL.md
  .github/skills/gitops/SKILL.md
  .github/skills/saturation/SKILL.md
  .github/skills/helm-drift/SKILL.md
  .github/skills/db-evidence/SKILL.md
  .github/skills/observability/SKILL.md
  .github/skills/incident-memory/SKILL.md
  .github/memory/INDEX.md
  .github/memory/_TEMPLATE.md
  .vscode/mcp.json
  .vscode/mcp.binary.json
  .vscode/mcp.env.example
  .mcp.json.example
  scripts/init.sh
  scripts/init.ps1
  tests/kit.ps1
  tests/e2e.ps1
  tests/fixtures/01-crashloop.yaml
  tests/fixtures/04-ingress.yaml
  tests/fixtures/chart/dto-hist/Chart.yaml
  tests/fixtures/saturation/05-quota.yaml
  deploy/rbac-troubleshooter-view.yaml
  .github/memory/INDEX.md
)
for f in "${required[@]}"; do
  if [ -f "$f" ]; then ok "exists $f"; else bad "missing $f"; fi
done

# --- JSON ---
json_files=(
  .vscode/mcp.json
  .vscode/mcp.binary.json
  .vscode/mcp.binary.windows.json
  .vscode/mcp.npx.windows.json
  .vscode/mcp.databases.json
  .vscode/mcp.databases.binary.json
  .vscode/mcp.databases.windows.json
  .vscode/mcp.databases.npx.windows.json
  .vscode/mcp.grafana.json
  .vscode/mcp.remediate.json
  .vscode/mcp.remediate.windows.json
  .vscode/mcp.multi-cluster.example.json
  .mcp.json.example
  .vscode/extensions.json
)
for f in "${json_files[@]}"; do
  if python3 -m json.tool "$f" >/dev/null 2>&1; then
    ok "json $f"
  else
    bad "invalid json $f"
  fi
done

# --- agent frontmatter ---
if grep -q '^name: DevOps Troubleshooter' .github/agents/devops-troubleshooter.agent.md; then
  ok "troubleshooter name"
else
  bad "troubleshooter missing name"
fi
if grep -q 'target: vscode' .github/agents/*.agent.md; then
  bad "agents still lock target: vscode"
else
  ok "agents are portable (no target: vscode)"
fi
if grep -q 'user-invocable: false' .github/agents/devops-remediator.agent.md; then
  ok "remediator hidden from picker"
else
  bad "remediator should be user-invocable: false"
fi
if grep -q 'db-mongodb' .vscode/mcp.databases.json .vscode/mcp.databases.windows.json \
  && grep -q 'mongodb-mcp-server' .vscode/mcp.databases.json \
  && grep -q -- '--readOnly' .vscode/mcp.databases.json; then
  ok "mongodb MCP is read-only in database configs"
else
  bad "mongodb MCP missing or not --readOnly"
fi
if grep -q 'db-mssql' .vscode/mcp.databases.json \
  && grep -q 'db-sqlite' .vscode/mcp.databases.json \
  && grep -q 'db-clickhouse' .vscode/mcp.databases.json \
  && grep -q 'db-elasticsearch' .vscode/mcp.databases.json \
  && grep -q 'db-neo4j' .vscode/mcp.databases.json \
  && grep -q 'db-snowflake' .vscode/mcp.databases.json; then
  ok "extra toolbox DB servers present"
else
  bad "missing extra toolbox DB servers"
fi
if grep -q 'db-mongodb/\*' .github/agents/devops-troubleshooter.agent.md \
  && grep -q 'db-mssql/\*' .github/agents/devops-troubleshooter.agent.md; then
  ok "troubleshooter allowlists extra db MCP servers"
else
  bad "troubleshooter missing extra db tools"
fi
if grep -q 'kubernetes-inspect/\*' .github/agents/devops-troubleshooter.agent.md; then
  ok "troubleshooter inspect tools"
else
  bad "troubleshooter missing kubernetes-inspect/*"
fi
if grep -q 'pods_delete' .github/agents/devops-remediator.agent.md; then
  ok "remediator allowlists pods_delete"
else
  bad "remediator missing pods_delete"
fi
if grep -q 'Apply Remediations' .github/agents/devops-troubleshooter.agent.md; then
  bad "troubleshooter still hands off Apply Remediations"
else
  ok "troubleshooter has no remediations handoff"
fi
if grep -q '### Recommendations' .github/skills/rca/SKILL.md \
  && grep -q '### Evidence ledger' .github/skills/rca/SKILL.md \
  && grep -q '### Proposed change' .github/skills/rca/SKILL.md; then
  ok "rca skill requires Recommendations, Evidence ledger, Proposed change"
else
  bad "rca skill missing Recommendations / Evidence ledger / Proposed change"
fi
if grep -q -- '- execute' .github/agents/devops-troubleshooter.agent.md \
  && grep -q 'helm history' .github/agents/devops-troubleshooter.agent.md \
  && grep -q 'never install, upgrade, rollback' .github/agents/devops-troubleshooter.agent.md; then
  ok "troubleshooter execute is read-only helm/git/gh"
else
  bad "troubleshooter missing allowlisted read-only execute"
fi
if grep -q 'Ask when insufficient or ambiguous' .github/agents/devops-troubleshooter.agent.md \
  && grep -q 'Blocking' .github/skills/clarify/SKILL.md \
  && grep -q 'Numbered options' .github/skills/clarify/SKILL.md; then
  ok "clarify skill asks on insufficient or ambiguous input"
else
  bad "missing clarify / ask-when-ambiguous behavior"
fi
if grep -q 'token-thrift' .github/agents/devops-troubleshooter.agent.md \
  && grep -q 'INDEX-only' .github/agents/devops-troubleshooter.agent.md \
  && grep -q 'tail=80' .github/agents/devops-troubleshooter.agent.md \
  && grep -q 'at most two' .github/skills/token-thrift/SKILL.md; then
  ok "token-thrift: INDEX-only memory, tail=80, skill budget"
else
  bad "missing token-thrift / cheap memory / log tail budget"
fi
if grep -q 'kube-context' .github/agents/devops-troubleshooter.agent.md \
  && grep -q 'context: <picked>' .github/agents/devops-troubleshooter.agent.md \
  && grep -q 'config use-context' .github/agents/devops-troubleshooter.agent.md \
  && grep -q -- '--kube-context' .github/skills/change-correlation/SKILL.md \
  && grep -q 'Never call `configuration_view`' .github/skills/kube-context/SKILL.md; then
  ok "kube-context pick is per-call, not kubectl use-context"
else
  bad "missing kube-context pin / helm --kube-context / configuration_view ban"
fi
if grep -q 'change-correlation' .github/agents/devops-troubleshooter.agent.md \
  && grep -q 'ingress-tls' .github/agents/devops-troubleshooter.agent.md \
  && grep -q 'saturation' .github/agents/devops-troubleshooter.agent.md \
  && grep -q 'gitops' .github/agents/devops-troubleshooter.agent.md \
  && grep -q 'cluster-scan' .github/agents/devops-troubleshooter.agent.md \
  && grep -q 'alert-intake' .github/agents/devops-troubleshooter.agent.md \
  && grep -q 'kube-context' .github/agents/devops-troubleshooter.agent.md \
  && grep -q 'clarify' .github/agents/devops-troubleshooter.agent.md; then
  ok "troubleshooter uses identification skills including gitops, saturation, cluster-scan"
else
  bad "troubleshooter missing identification skills"
fi

# --- inspect server is read-only in committed configs ---
for f in .vscode/mcp.json .vscode/mcp.binary.json .vscode/mcp.binary.windows.json .vscode/mcp.npx.windows.json .mcp.json.example; do
  if python3 - "$f" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
servers = data.get("servers") or data.get("mcpServers") or {}
insp = servers.get("kubernetes-inspect") or {}
args = insp.get("args") or []
joined = " ".join(args)
if "--read-only" not in joined:
    sys.exit(1)
PY
  then
    ok "read-only inspect in $f"
  else
    bad "kubernetes-inspect missing --read-only in $f"
  fi
done

# --- default MCP is inspect-only (no mutating remediator server) ---
for f in .vscode/mcp.json .vscode/mcp.binary.json .vscode/mcp.binary.windows.json .vscode/mcp.npx.windows.json .mcp.json.example; do
  if grep -q 'kubernetes-remediate' "$f"; then
    bad "default MCP $f still includes kubernetes-remediate"
  else
    ok "inspect-only MCP in $f"
  fi
done
if grep -q 'kubernetes-remediate' .vscode/mcp.remediate.json .vscode/mcp.remediate.windows.json; then
  ok "optional mcp.remediate.json kept for leftover remediator"
else
  bad "mcp.remediate.json missing kubernetes-remediate"
fi
if grep -q 'disable-destructive' .vscode/mcp.remediate.json .vscode/mcp.remediate.windows.json; then
  bad "optional remediator MCP uses --disable-destructive (hides pods_delete)"
else
  ok "optional remediator MCP has no --disable-destructive"
fi

if grep -q -- '--mcp' scripts/init.sh && grep -q -- '-Mcp' scripts/init.ps1 \
  && grep -q 'Choose optional MCP' scripts/init.sh && grep -q 'Choose optional MCP' scripts/init.ps1; then
  ok "init prompts for which MCPs to download"
else
  bad "init missing MCP picker prompt"
fi
if grep -q -- '--kubeconfig' scripts/init.sh && grep -q '\$Kubeconfig' scripts/init.ps1; then
  ok "init accepts --kubeconfig / -Kubeconfig"
else
  bad "init missing --kubeconfig / -Kubeconfig"
fi
if grep -q -- '--k8s-only' scripts/init.sh && grep -q -- '-K8sOnly' scripts/init.ps1; then
  ok "init downloads kubernetes-mcp-server only by default"
else
  bad "init should call setup --k8s-only / -K8sOnly"
fi
if grep -q 'kubernetes-remediate' scripts/init.sh scripts/init.ps1; then
  bad "init still writes kubernetes-remediate"
else
  ok "init does not wire remediator MCP"
fi
bash -n scripts/init.sh && ok "bash -n init.sh" || bad "init.sh syntax"
bash -n scripts/setup.sh && ok "bash -n setup.sh" || bad "setup.sh syntax"
bash -n tests/e2e.sh && ok "bash -n e2e.sh" || bad "e2e.sh syntax"

# --- init discover ---
if ./scripts/init.sh --discover-only >/tmp/dto-init-out.txt; then
  ok "init.sh --discover-only"
  if python3 -m json.tool .devops-troubleshooter-init.json >/dev/null; then
    ok "init report json"
  else
    bad "init report not json"
  fi
  if grep -q '"os"' .devops-troubleshooter-init.json; then
    ok "init report has platform"
  else
    bad "init report missing os"
  fi
  if grep -q 'kube_contexts' .devops-troubleshooter-init.json; then
    ok "init report lists kube_contexts"
  else
    bad "init report missing kube_contexts"
  fi
else
  bad "init.sh --discover-only failed"
  cat /tmp/dto-init-out.txt || true
fi

# --- fixtures mention expected RCA strings ---
grep -q 'CONFIG_ERROR: missing PAYMENTS_DSN' tests/fixtures/01-crashloop.yaml \
  && ok "crashloop fixture has log signature" || bad "crashloop fixture signature"
grep -q 'app: payments' tests/fixtures/03-selector-mismatch.yaml \
  && grep -q 'app: payments-api' tests/fixtures/03-selector-mismatch.yaml \
  && ok "mismatch fixture has selector drift" || bad "mismatch fixture labels"
if grep -q 'crashloop--2026-08-10' .github/memory/INDEX.md \
  && grep -q 'unreachable--2026-08-12' .github/memory/INDEX.md; then
  ok "incident memory has example records"
else
  bad "memory INDEX missing example records"
fi

if [ "$fail" -ne 0 ]; then
  echo "== kit FAILED"
  exit 1
fi
echo "== kit PASSED"
exit 0
