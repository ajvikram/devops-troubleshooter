#Requires -Version 5.1
# Kit contract tests for Windows. Pair of tests/kit.sh.
#   powershell -ExecutionPolicy Bypass -File .\tests\kit.ps1

$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $PSNativeCommandUseErrorActionPreference = $false
}
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root
$fail = 0

function Ok($m) { Write-Host "  OK  $m" }
function Bad($m) { Write-Host "  FAIL $m"; $script:fail = 1 }

Write-Host "== kit contract (Windows)"

$required = @(
  "README.md",
  "docs/user-guide.md",
  "docs/macos.md",
  "docs/windows.md",
  "docs/init.md",
  "docs/clusters.md",
  "docs/token-use.md",
  ".github/agents/devops-troubleshooter.agent.md",
  ".github/skills/rca/SKILL.md",
  ".github/skills/cluster-scan/SKILL.md",
  ".github/skills/alert-intake/SKILL.md",
  ".github/skills/kube-context/SKILL.md",
  ".github/skills/clarify/SKILL.md",
  ".github/skills/token-thrift/SKILL.md",
  ".github/prompts/investigate.prompt.md",
  ".github/skills/change-correlation/SKILL.md",
  ".github/skills/ingress-tls/SKILL.md",
  "scripts/init.ps1",
  "scripts/setup.ps1",
  "tests/e2e.ps1",
  ".vscode/mcp.binary.windows.json",
  ".vscode/mcp.npx.windows.json",
  "deploy/rbac-troubleshooter-view.yaml"
)
foreach ($f in $required) {
  if (Test-Path $f) { Ok "exists $f" } else { Bad "missing $f" }
}

$jsonFiles = @(
  ".vscode/mcp.json",
  ".vscode/mcp.binary.windows.json",
  ".vscode/mcp.npx.windows.json",
  ".vscode/mcp.databases.windows.json",
  ".vscode/mcp.databases.binary.json",
  ".vscode/mcp.databases.npx.windows.json",
  ".mcp.json.example"
)
foreach ($f in $jsonFiles) {
  try {
    Get-Content -Raw $f | ConvertFrom-Json | Out-Null
    Ok "json $f"
  } catch {
    Bad "invalid json $f"
  }
}

$t = Get-Content ".github/agents/devops-troubleshooter.agent.md" -Raw
if ($t -match 'name: DevOps Troubleshooter') { Ok "troubleshooter name" } else { Bad "troubleshooter name" }
if ($t -match 'target: vscode') { Bad "agents lock target: vscode" } else { Ok "portable agents" }
if ($t -match 'Apply Remediations') { Bad "troubleshooter still hands off remediations" } else { Ok "no remediations handoff" }
if ($t -match 'Recommendations') { Ok "troubleshooter mentions recommendations" } else { Bad "missing recommendations" }
if ($t -match 'kube-context') { Ok "troubleshooter kube-context skill" } else { Bad "missing kube-context" }
if ($t -match 'config use-context') { Ok "forbids kubectl use-context" } else { Bad "missing use-context ban" }
if ($t -match 'Ask when insufficient or ambiguous') { Ok "asks when ambiguous" } else { Bad "missing clarify principle" }
if ($t -match 'token-thrift') { Ok "token-thrift" } else { Bad "missing token-thrift" }
if ($t -match 'INDEX-only') { Ok "INDEX-only memory" } else { Bad "missing INDEX-only memory" }

$defaults = @(
  ".vscode/mcp.json",
  ".vscode/mcp.binary.windows.json",
  ".vscode/mcp.npx.windows.json",
  ".mcp.json.example"
)
foreach ($f in $defaults) {
  $raw = Get-Content $f -Raw
  if ($raw -match 'kubernetes-remediate') { Bad "default MCP $f still includes kubernetes-remediate" }
  else { Ok "inspect-only MCP in $f" }
}

$rca = Get-Content ".github/skills/rca/SKILL.md" -Raw
if ($rca -match '### Recommendations') { Ok "rca Recommendations section" } else { Bad "rca missing Recommendations" }
if ($rca -match '### Evidence ledger') { Ok "rca Evidence ledger" } else { Bad "rca missing Evidence ledger" }
if ($rca -match '### Proposed change') { Ok "rca Proposed change" } else { Bad "rca missing Proposed change" }

$inspect = Get-Content ".vscode/mcp.binary.windows.json" -Raw | ConvertFrom-Json
$args = $inspect.servers.'kubernetes-inspect'.args -join ' '
if ($args -match '--read-only') { Ok "windows binary inspect is read-only" } else { Bad "inspect missing --read-only" }

& "$Root\scripts\init.ps1" -DiscoverOnly | Out-Null
if (Test-Path ".devops-troubleshooter-init.json") {
  Get-Content -Raw ".devops-troubleshooter-init.json" | ConvertFrom-Json | Out-Null
  Ok "init.ps1 -DiscoverOnly"
} else {
  Bad "init.ps1 did not write report"
}

if ($fail -ne 0) {
  Write-Host "== kit FAILED"
  exit 1
}
Write-Host "== kit PASSED"
exit 0
