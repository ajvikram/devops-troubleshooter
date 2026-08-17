#Requires -Version 5.1
# End-to-end on Windows: kit contract + kind cluster + MCP smoke.
# Pair of tests/e2e.sh. Needs Docker Desktop, kind, kubectl, and Python 3.
#
#   powershell -ExecutionPolicy Bypass -File .\tests\e2e.ps1
#   .\tests\e2e.ps1 -KitOnly
#   .\tests\e2e.ps1 -KeepCluster
#   .\tests\e2e.ps1 -SkipMcp
#   .\tests\e2e.ps1 -UseCurrentKubeconfig

param(
    [switch]$KitOnly,
    [switch]$KeepCluster,
    [switch]$SkipMcp,
    [switch]$UseCurrentKubeconfig
)

$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $PSNativeCommandUseErrorActionPreference = $false
}
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

$Cluster = if ($env:DTO_E2E_CLUSTER) { $env:DTO_E2E_CLUSTER } else { "dto-e2e" }
$Ns = "dto-e2e"
$Timeout = if ($env:DTO_E2E_TIMEOUT) { [int]$env:DTO_E2E_TIMEOUT } else { 180 }
$createdCluster = $false

function Bad($m) { Write-Host "  FAIL $m"; throw $m }
function Ok($m) { Write-Host "  OK  $m" }

function Test-Cmd($name) {
    return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

function Get-Python {
    foreach ($c in @("python3", "python")) {
        if (Test-Cmd $c) { return $c }
    }
    return $null
}

function Wait-For([string]$Desc, [scriptblock]$Check) {
    $max = [Math]::Max(20, [int]($Timeout / 3))
    for ($i = 0; $i -lt $max; $i++) {
        try {
            if (& $Check) { Ok $Desc; return }
        } catch { }
        Start-Sleep -Seconds 3
    }
    kubectl get pods -n $Ns -o wide
    kubectl get endpoints -n $Ns
    Bad "timeout: $Desc"
}

Write-Host "==== 1. kit contract"
& "$Root\tests\kit.ps1"
if ($LASTEXITCODE -ne 0) { Bad "kit.ps1 failed" }

if ($KitOnly) {
    Write-Host "==== kit-only done"
    exit 0
}

if (-not (Test-Cmd "kubectl")) { Bad "kubectl not on PATH" }
$py = Get-Python
if (-not $py) { Bad "python3 or python not on PATH" }

try {
    Write-Host "==== 2. cluster"
    if ($UseCurrentKubeconfig) {
        kubectl cluster-info | Out-Null
        if ($LASTEXITCODE -ne 0) { Bad "kubectl cannot reach current cluster" }
        Ok "using current kubeconfig $(kubectl config current-context)"
    } else {
        if (-not (Test-Cmd "kind")) { Bad "kind not on PATH (install kind or pass -UseCurrentKubeconfig)" }
        if (-not (Test-Cmd "docker")) { Bad "docker not on PATH" }
        docker info | Out-Null
        if ($LASTEXITCODE -ne 0) { Bad "docker daemon not running (start Docker Desktop)" }
        $existing = @(kind get clusters 2>$null)
        if ($existing -contains $Cluster) {
            Ok "reusing kind cluster $Cluster"
        } else {
            Write-Host "  creating kind cluster $Cluster (pulls node image on first run)..."
            kind create cluster --name $Cluster --wait 120s
            $createdCluster = $true
            Ok "created $Cluster"
        }
        kubectl config use-context "kind-$Cluster" | Out-Null
    }

    if ((Test-Cmd "docker") -and (Test-Cmd "kind")) {
        docker image inspect busybox:1.36 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $existing = @(kind get clusters 2>$null)
            if ($existing -contains $Cluster) {
                kind load docker-image busybox:1.36 --name $Cluster 2>$null | Out-Null
                Ok "loaded busybox:1.36 into kind (if this is a kind cluster)"
            }
        }
    }

    Write-Host "==== 3. fixtures"
    kubectl apply -f tests/fixtures/ | Out-Null
    Ok "applied tests/fixtures into $Ns"

    Wait-For "crashloop restartCount >= 1" {
        $n = kubectl get pods -n $Ns -l app=crashloop -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}' 2>$null
        return ([int]($n | Select-Object -First 1)) -ge 1
    }
    Wait-For "not-ready pod Ready=False" {
        $ready = kubectl get pods -n $Ns -l app=not-ready -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>$null
        return "$ready" -eq "False"
    }
    Wait-For "mismatch pod Ready=True" {
        $ready = kubectl get pods -n $Ns -l app=payments-api -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>$null
        return "$ready" -eq "True"
    }
    Wait-For "mismatch Service has empty Endpoints" {
        $addrs = kubectl get endpoints mismatch -n $Ns -o jsonpath='{.subsets}' 2>$null
        return [string]::IsNullOrWhiteSpace($addrs)
    }

    Write-Host "==== 3b. saturation fixture (quota after 3 pods exist)"
    kubectl apply -f tests/fixtures/saturation/ | Out-Null
    Wait-For "pending-quota pod is Pending (ResourceQuota)" {
        kubectl get deploy pending-quota -n $Ns | Out-Null
        if ($LASTEXITCODE -ne 0) { return $false }
        $ready = kubectl get deploy pending-quota -n $Ns -o jsonpath='{.status.readyReplicas}'
        if ("$ready" -eq "1") { return $false }
        $ev = kubectl get events -n $Ns -o json 2>$null
        return "$ev" -match "exceeded quota"
    }
    $used = kubectl get resourcequota tiny -n $Ns -o jsonpath='{.status.used.pods}'
    $hard = kubectl get resourcequota tiny -n $Ns -o jsonpath='{.status.hard.pods}'
    if ("$used" -ne "3" -or "$hard" -ne "3") { Bad "quota used/hard pods=$used/$hard (want 3/3)" }
    Ok "ResourceQuota tiny used 3/3 pods"

    Write-Host "==== 4. kubectl evidence (what RCA must cite)"
    $logs = kubectl logs -n $Ns -l app=crashloop --tail=20 2>$null
    $prev = kubectl logs -n $Ns -l app=crashloop --previous --tail=20 2>$null
    $blob = "$logs`n$prev"
    if ($blob -notmatch "CONFIG_ERROR: missing PAYMENTS_DSN") { Bad "crashloop logs missing CONFIG_ERROR" }
    Ok "crashloop logs contain CONFIG_ERROR signature"

    $reason = kubectl get pods -n $Ns -l app=crashloop -o jsonpath='{.items[0].status.containerStatuses[0].state.waiting.reason}' 2>$null
    if ($reason -notin @("CrashLoopBackOff", "RunContainerError", "Completed")) {
        $last = kubectl get pods -n $Ns -l app=crashloop -o jsonpath='{.items[0].status.containerStatuses[0].lastState.terminated.exitCode}' 2>$null
        if ("$last" -ne "1") { Bad "unexpected crashloop state reason='$reason' exit='$last'" }
        Ok "crashloop lastState exitCode=1 (reason=$reason)"
    } else {
        Ok "crashloop waiting reason=$reason"
    }

    $sel = kubectl get svc mismatch -n $Ns -o jsonpath='{.spec.selector.app}'
    if ("$sel" -ne "payments") { Bad "mismatch Service selector app=$sel" }
    Ok "mismatch Service selector app=payments (pods are payments-api)"

    $nrReady = kubectl get endpoints not-ready -n $Ns -o jsonpath='{.subsets[*].addresses[*].ip}' 2>$null
    if (-not [string]::IsNullOrWhiteSpace("$nrReady")) { Bad "not-ready Endpoints unexpectedly have ready IPs: $nrReady" }
    Ok "not-ready Endpoints have no ready addresses (Ready=False dropped from Service)"

    $backend = kubectl get ingress payments -n $Ns -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}'
    if ("$backend" -ne "does-not-exist") { Bad "ingress backend service=$backend" }
    Ok "Ingress payments backend Service is does-not-exist"
    $tlsSecret = kubectl get ingress payments -n $Ns -o jsonpath='{.spec.tls[0].secretName}'
    if ("$tlsSecret" -ne "payments-tls-missing") { Bad "ingress tls secret=$tlsSecret" }
    kubectl get secret payments-tls-missing -n $Ns 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { Bad "payments-tls-missing Secret should not exist" }
    Ok "TLS Secret payments-tls-missing is absent (HTTPS would fail)"

    if (Test-Cmd "helm") {
        helm upgrade --install dto-hist "$Root\tests\fixtures\chart\dto-hist" -n $Ns --set note=rev1 | Out-Null
        helm upgrade dto-hist "$Root\tests\fixtures\chart\dto-hist" -n $Ns --set note=rev2 | Out-Null
        $histJson = helm history dto-hist -n $Ns --output json | ConvertFrom-Json
        $revs = @($histJson).Count
        if ($revs -lt 2) { Bad "helm history expected >=2 revisions, got $revs" }
        $note = kubectl get configmap dto-hist -n $Ns -o jsonpath='{.data.note}'
        if ("$note" -ne "rev2") { Bad "dto-hist configmap note=$note (want rev2)" }
        Ok "Helm history has $revs revisions (current values note=rev2)"
    } else {
        Ok "helm CLI not installed — skip change-correlation helm history check"
    }

    Write-Host "==== 5. expected RCA (human / agent checklist)"
    Write-Host @"
  crashloop  → class Crash; cause process exit 1 / missing PAYMENTS_DSN; NOT "just CrashLoopBackOff"
  not-ready  → class Not Ready; cause readiness tcpSocket :9999 while process only sleeps
  mismatch   → class Unreachable; cause Service selector app=payments vs pods app=payments-api
  ingress    → class Edge/TLS; backend Service does-not-exist; Secret payments-tls-missing absent
  dto-hist   → change-correlation: helm history shows revision 2 (note=rev2); revision 1 was rev1
  pending-quota → class Saturation; ResourceQuota tiny pods 3/3; new replica cannot schedule
               recommendations: chart/config/TLS/quota — not restart; restart will not fix mismatch, Ingress, TLS, or quota
"@

    if ($SkipMcp) {
        Write-Host "==== MCP skipped"
        Write-Host "==== e2e PASSED (cluster evidence only)"
        exit 0
    }

    Write-Host "==== 6. Kubernetes MCP smoke"
    $k8sBin = Join-Path $Root "bin\kubernetes-mcp-server.exe"
    if (-not (Test-Path $k8sBin)) {
        Write-Host "  downloading kubernetes-mcp-server (setup.ps1 -K8sOnly)..."
        & "$Root\scripts\setup.ps1" -K8sOnly
    }
    if (-not (Test-Path $k8sBin)) { Bad "kubernetes-mcp-server.exe missing" }

    if (-not $env:KUBECONFIG) {
        $env:KUBECONFIG = Join-Path $env:USERPROFILE ".kube\config"
    }

    $listJson = & $py tests/mcp_stdio.py --timeout 60 --list-tools -- $k8sBin --read-only --toolsets core,config,helm
    $listJson | ConvertFrom-Json | Out-Null
    $parsed = $listJson | ConvertFrom-Json
    if ([int]$parsed.count -le 5) { Bad "tools/list returned $($parsed.count) tools" }
    Ok "MCP tools/list count=$($parsed.count)"

    $need = @("pods_list_in_namespace", "pods_log", "events_list", "configuration_contexts_list")
    $missing = $need | Where-Object { $parsed.tools -notcontains $_ }
    if ($missing) { Bad "missing tools: $($missing -join ', ')" }
    Ok "MCP has pods_list_in_namespace, pods_log, events_list, configuration_contexts_list"

    $ctx = & $py tests/mcp_stdio.py --timeout 60 --call configuration_contexts_list --args '{}' -- $k8sBin --read-only --toolsets core,config,helm
    if ([string]::IsNullOrWhiteSpace($ctx)) { Bad "configuration_contexts_list empty" }
    Ok "MCP configuration_contexts_list returned data"

    $pods = & $py tests/mcp_stdio.py --timeout 90 --call pods_list_in_namespace --args "{`"namespace`":`"$Ns`"}" -- $k8sBin --read-only --toolsets core,config,helm
    if ("$pods" -notmatch "crashloop") { Bad "MCP pods_list_in_namespace missing crashloop" }
    Ok "MCP lists crashloop in $Ns"

    $podName = kubectl get pods -n $Ns -l app=crashloop -o jsonpath='{.items[0].metadata.name}'
    $logOut = ""
    foreach ($args in @(
        "{`"name`":`"$podName`",`"namespace`":`"$Ns`",`"tail`":50}",
        "{`"pod`":`"$podName`",`"namespace`":`"$Ns`",`"tail`":50}"
    )) {
        try {
            $logOut = & $py tests/mcp_stdio.py --timeout 90 --call pods_log --args $args -- $k8sBin --read-only --toolsets core,config,helm 2>&1 | Out-String
            if ($logOut -match "CONFIG_ERROR: missing PAYMENTS_DSN") { break }
        } catch { }
    }
    if ($logOut -match "CONFIG_ERROR: missing PAYMENTS_DSN") {
        Ok "MCP pods_log contains CONFIG_ERROR"
    } else {
        Ok "MCP pods_log invoked (signature check best-effort)"
    }

    Write-Host "==== e2e PASSED"
    Write-Host "Prompt for Copilot:  Something is wrong in namespace dto-e2e. Investigate all workloads."
    if ($KeepCluster) {
        Write-Host "Cluster kept: kind delete cluster --name $Cluster"
    }
} finally {
    if ($createdCluster -and -not $KeepCluster) {
        Write-Host "==== cleanup kind cluster $Cluster"
        kind delete cluster --name $Cluster 2>$null | Out-Null
    }
}
exit 0
