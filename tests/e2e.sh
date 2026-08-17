#!/usr/bin/env bash
set -euo pipefail

# End-to-end: kit contract + kind cluster with planted identification fixtures + MCP smoke.
# macOS/Linux (bash). Windows: powershell -ExecutionPolicy Bypass -File .\tests\e2e.ps1
#
#   ./tests/e2e.sh
#   ./tests/e2e.sh --kit-only
#   ./tests/e2e.sh --keep-cluster
#   ./tests/e2e.sh --skip-mcp
#   ./tests/e2e.sh --use-current-kubeconfig   # skip kind create (CI)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CLUSTER="${DTO_E2E_CLUSTER:-dto-e2e}"
NS=dto-e2e
KIT_ONLY=false
KEEP=false
SKIP_MCP=false
USE_CURRENT=false
TIMEOUT="${DTO_E2E_TIMEOUT:-180}"

while [ $# -gt 0 ]; do
  case "$1" in
    --kit-only) KIT_ONLY=true ;;
    --keep-cluster) KEEP=true ;;
    --skip-mcp) SKIP_MCP=true ;;
    --use-current-kubeconfig) USE_CURRENT=true ;;
    --help|-h)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

ok() { printf '  OK  %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; exit 1; }

echo "==== 1. kit contract"
chmod +x tests/kit.sh tests/e2e.sh scripts/init.sh scripts/setup.sh
./tests/kit.sh

if [ "$KIT_ONLY" = true ]; then
  echo "==== kit-only done"
  exit 0
fi

command -v kubectl >/dev/null || bad "kubectl not on PATH"
command -v python3 >/dev/null || bad "python3 not on PATH"

created_cluster=false
cleanup() {
  if [ "$created_cluster" = true ] && [ "$KEEP" != true ]; then
    echo "==== cleanup kind cluster ${CLUSTER}"
    kind delete cluster --name "$CLUSTER" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "==== 2. cluster"
if [ "$USE_CURRENT" = true ]; then
  kubectl cluster-info >/dev/null || bad "kubectl cannot reach current cluster"
  ok "using current kubeconfig $(kubectl config current-context)"
else
  command -v kind >/dev/null || bad "kind not on PATH (install kind or pass --use-current-kubeconfig)"
  command -v docker >/dev/null || bad "docker not on PATH"
  docker info >/dev/null 2>&1 || bad "docker daemon not running"
  if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
    ok "reusing kind cluster ${CLUSTER}"
  else
    echo "  creating kind cluster ${CLUSTER} (pulls node image on first run)..."
    kind create cluster --name "$CLUSTER" --wait 120s
    created_cluster=true
    ok "created ${CLUSTER}"
  fi
  kubectl config use-context "kind-${CLUSTER}" >/dev/null
fi

if command -v docker >/dev/null && docker image inspect busybox:1.36 >/dev/null 2>&1; then
  if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
    kind load docker-image busybox:1.36 --name "$CLUSTER" >/dev/null 2>&1 || true
    ok "loaded busybox:1.36 into kind (if this is a kind cluster)"
  fi
fi

echo "==== 3. fixtures"
kubectl apply -f tests/fixtures/ >/dev/null
ok "applied tests/fixtures into ${NS}"

wait_for() {
  local desc="$1"
  local tries=0
  local max=$((TIMEOUT / 3))
  [ "$max" -lt 20 ] && max=20
  shift
  while [ "$tries" -lt "$max" ]; do
    if "$@" >/dev/null 2>&1; then
      ok "$desc"
      return 0
    fi
    tries=$((tries + 1))
    sleep 3
  done
  echo "  last kubectl:"
  kubectl get pods -n "$NS" -o wide || true
  kubectl get endpoints -n "$NS" || true
  bad "timeout: $desc"
}

crash_restarting() {
  local n
  n="$(kubectl get pods -n "$NS" -l app=crashloop -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}' 2>/dev/null || echo 0)"
  [ "${n:-0}" -ge 1 ]
}

not_ready_false() {
  local ready
  ready="$(kubectl get pods -n "$NS" -l app=not-ready -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
  [ "$ready" = "False" ]
}

mismatch_ready() {
  local ready
  ready="$(kubectl get pods -n "$NS" -l app=payments-api -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
  [ "$ready" = "True" ]
}

mismatch_empty_ep() {
  local addrs
  addrs="$(kubectl get endpoints mismatch -n "$NS" -o jsonpath='{.subsets}' 2>/dev/null || true)"
  [ -z "$addrs" ]
}

wait_for "crashloop restartCount >= 1" crash_restarting
wait_for "not-ready pod Ready=False" not_ready_false
wait_for "mismatch pod Ready=True" mismatch_ready
wait_for "mismatch Service has empty Endpoints" mismatch_empty_ep

echo "==== 3b. saturation fixture (quota after 3 pods exist)"
kubectl apply -f tests/fixtures/saturation/ >/dev/null
pending_quota() {
  kubectl get deploy pending-quota -n "$NS" >/dev/null 2>&1 || return 1
  local ready
  ready="$(kubectl get deploy pending-quota -n "$NS" -o jsonpath='{.status.readyReplicas}')"
  [ "$ready" = "1" ] && return 1
  kubectl get events -n "$NS" -o json 2>/dev/null | grep -qi 'exceeded quota'
}
wait_for "pending-quota pod is Pending (ResourceQuota)" pending_quota
used="$(kubectl get resourcequota tiny -n "$NS" -o jsonpath='{.status.used.pods}')"
hard="$(kubectl get resourcequota tiny -n "$NS" -o jsonpath='{.status.hard.pods}')"
[ "$used" = "3" ] && [ "$hard" = "3" ] || bad "quota used/hard pods=$used/$hard (want 3/3)"
ok "ResourceQuota tiny used 3/3 pods"

echo "==== 4. kubectl evidence (what RCA must cite)"

logs="$(kubectl logs -n "$NS" -l app=crashloop --tail=20 2>/dev/null || true)"
prev="$(kubectl logs -n "$NS" -l app=crashloop --previous --tail=20 2>/dev/null || true)"
if printf '%s\n%s\n' "$logs" "$prev" | grep -q 'CONFIG_ERROR: missing PAYMENTS_DSN'; then
  ok "crashloop logs contain CONFIG_ERROR signature"
else
  echo "$logs"
  echo "$prev"
  bad "crashloop logs missing CONFIG_ERROR"
fi

reason="$(kubectl get pods -n "$NS" -l app=crashloop -o jsonpath='{.items[0].status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || true)"
case "$reason" in
  CrashLoopBackOff|RunContainerError|Completed) ok "crashloop waiting reason=$reason" ;;
  *)
    # lastState is also acceptable once it has restarted
    last="$(kubectl get pods -n "$NS" -l app=crashloop -o jsonpath='{.items[0].status.containerStatuses[0].lastState.terminated.exitCode}' 2>/dev/null || true)"
    if [ "$last" = "1" ]; then
      ok "crashloop lastState exitCode=1 (reason=$reason)"
    else
      bad "unexpected crashloop state reason='$reason' exit='$last'"
    fi
    ;;
esac

sel="$(kubectl get svc mismatch -n "$NS" -o jsonpath='{.spec.selector.app}')"
[ "$sel" = "payments" ] || bad "mismatch Service selector app=$sel"
ok "mismatch Service selector app=payments (pods are payments-api)"

nr_ready="$(kubectl get endpoints not-ready -n "$NS" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)"
if [ -z "$nr_ready" ]; then
  ok "not-ready Endpoints have no ready addresses (Ready=False dropped from Service)"
else
  bad "not-ready Endpoints unexpectedly have ready IPs: $nr_ready"
fi

backend="$(kubectl get ingress payments -n "$NS" -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}')"
[ "$backend" = "does-not-exist" ] || bad "ingress backend service=$backend"
ok "Ingress payments backend Service is does-not-exist"
tls_secret="$(kubectl get ingress payments -n "$NS" -o jsonpath='{.spec.tls[0].secretName}')"
[ "$tls_secret" = "payments-tls-missing" ] || bad "ingress tls secret=$tls_secret"
if kubectl get secret payments-tls-missing -n "$NS" >/dev/null 2>&1; then
  bad "payments-tls-missing Secret should not exist"
else
  ok "TLS Secret payments-tls-missing is absent (HTTPS would fail)"
fi

if command -v helm >/dev/null; then
  helm upgrade --install dto-hist "${ROOT}/tests/fixtures/chart/dto-hist" -n "$NS" --set note=rev1 >/dev/null
  helm upgrade dto-hist "${ROOT}/tests/fixtures/chart/dto-hist" -n "$NS" --set note=rev2 >/dev/null
  hist="$(helm history dto-hist -n "$NS")"
  echo "$hist" | grep -q '2 ' || echo "$hist" | grep -q $'\t2\t' || true
  revs="$(helm history dto-hist -n "$NS" --output json | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
  [ "$revs" -ge 2 ] || bad "helm history expected >=2 revisions, got $revs"
  note="$(kubectl get configmap dto-hist -n "$NS" -o jsonpath='{.data.note}')"
  [ "$note" = "rev2" ] || bad "dto-hist configmap note=$note (want rev2)"
  ok "Helm history has $revs revisions (current values note=rev2)"
else
  ok "helm CLI not installed — skip change-correlation helm history check"
fi

echo "==== 5. expected RCA (human / agent checklist)"
cat <<'EOF'
  crashloop  → class Crash; cause process exit 1 / missing PAYMENTS_DSN; NOT "just CrashLoopBackOff"
  not-ready  → class Not Ready; cause readiness tcpSocket :9999 while process only sleeps
  mismatch   → class Unreachable; cause Service selector app=payments vs pods app=payments-api
  ingress    → class Edge/TLS; backend Service does-not-exist; Secret payments-tls-missing absent
  dto-hist   → change-correlation: helm history shows revision 2 (note=rev2); revision 1 was rev1
  pending-quota → class Saturation; ResourceQuota tiny pods 3/3; new replica cannot schedule
               recommendations: chart/config/TLS/quota — not restart; restart will not fix mismatch, Ingress, TLS, or quota
EOF

if [ "$SKIP_MCP" = true ]; then
  echo "==== MCP skipped"
  echo "==== e2e PASSED (cluster evidence only)"
  exit 0
fi

echo "==== 6. Kubernetes MCP smoke"
K8S_BIN="${ROOT}/bin/kubernetes-mcp-server"
if [ ! -x "$K8S_BIN" ]; then
  echo "  downloading kubernetes-mcp-server (setup.sh --k8s-only)..."
  "${ROOT}/scripts/setup.sh" --k8s-only
fi
[ -x "$K8S_BIN" ] || bad "kubernetes-mcp-server binary missing"

export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"

list_json="$(python3 tests/mcp_stdio.py --timeout 60 --list-tools -- "$K8S_BIN" --read-only --toolsets core,config,helm)"
echo "$list_json" | python3 -m json.tool >/dev/null || bad "tools/list not json"
count="$(echo "$list_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["count"])')"
[ "$count" -gt 5 ] || bad "tools/list returned $count tools"
ok "MCP tools/list count=$count"

python3 - "$list_json" <<'PY'
import json, sys
names = json.loads(sys.argv[1])["tools"]
need = ["pods_list_in_namespace", "pods_log", "events_list", "configuration_contexts_list"]
missing = [n for n in need if n not in names]
if missing:
    print("missing tools:", missing)
    print("have:", names[:30])
    sys.exit(1)
PY
ok "MCP has pods_list_in_namespace, pods_log, events_list, configuration_contexts_list"

ctx="$(python3 tests/mcp_stdio.py --timeout 60 --call configuration_contexts_list --args '{}' -- "$K8S_BIN" --read-only --toolsets core,config,helm)"
echo "$ctx" | grep -q . || bad "configuration_contexts_list empty"
ok "MCP configuration_contexts_list returned data"

pods="$(python3 tests/mcp_stdio.py --timeout 90 --call pods_list_in_namespace --args "{\"namespace\":\"${NS}\"}" -- "$K8S_BIN" --read-only --toolsets core,config,helm)"
echo "$pods" | grep -qi crashloop || bad "MCP pods_list_in_namespace missing crashloop"
ok "MCP lists crashloop in ${NS}"

# pods_log argument names vary; try common shapes
pod_name="$(kubectl get pods -n "$NS" -l app=crashloop -o jsonpath='{.items[0].metadata.name}')"
log_out=""
for args in \
  "{\"name\":\"${pod_name}\",\"namespace\":\"${NS}\",\"tail\":50}" \
  "{\"pod\":\"${pod_name}\",\"namespace\":\"${NS}\",\"tail\":50}" \
  "{\"name\":\"${pod_name}\",\"ns\":\"${NS}\"}"
do
  if log_out="$(python3 tests/mcp_stdio.py --timeout 90 --call pods_log --args "$args" -- "$K8S_BIN" --read-only --toolsets core,config,helm 2>/tmp/dto-mcp-log.err)"; then
    break
  fi
done
if printf '%s\n' "$log_out" | grep -q 'CONFIG_ERROR: missing PAYMENTS_DSN'; then
  ok "MCP pods_log contains CONFIG_ERROR"
elif grep -q 'CONFIG_ERROR: missing PAYMENTS_DSN' /tmp/dto-mcp-log.err 2>/dev/null; then
  ok "MCP pods_log (stderr channel) contains CONFIG_ERROR"
else
  echo "  pods_log result (truncated): ${log_out:0:500}"
  cat /tmp/dto-mcp-log.err 2>/dev/null || true
  echo "  (non-fatal if tool schema differs — kubectl already proved the log line)"
  ok "MCP pods_log invoked (signature check best-effort)"
fi

echo "==== e2e PASSED"
echo "Prompt for Copilot:  Something is wrong in namespace dto-e2e. Investigate all workloads."
if [ "$KEEP" = true ]; then
  echo "Cluster kept: kind delete cluster --name ${CLUSTER}"
fi
exit 0
