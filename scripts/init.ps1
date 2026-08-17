#Requires -Version 5.1
<#
.SYNOPSIS
    Discover OS / IDE / agent harness and write MCP configs for Windows.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\init.ps1
    .\scripts\init.ps1 -DiscoverOnly
    .\scripts\init.ps1 -WithObservability
    .\scripts\init.ps1 -Ide vscode,cursor,cli
#>

param(
    [switch]$DiscoverOnly,
    [switch]$WithObservability,
    [switch]$WithDatabases,
    [string]$Mcp = "",
    [switch]$Yes,
    [string]$Ide = "",
    [string]$Proxy = "",
    [string]$CaCert = "",
    [switch]$Help
)

if ($Help) {
    Write-Host @"
Usage: .\scripts\init.ps1 [options]

Discover platform, IDEs, and agent harnesses, then write MCP configs.

  -DiscoverOnly         Print discovery report only (no downloads, no writes)
  -Ide vscode,cursor,cli  Limit config writes (aliases: vs, cli, jb, claude)
  -Mcp grafana,postgres,mongodb
                          Non-interactive MCP pick. Always includes kubernetes.
  -Yes                  Skip the MCP prompt (kubernetes only, plus -Mcp / -With* / mcp.env)
  -WithObservability    Add Grafana MCP (same as including grafana in -Mcp)
  -WithDatabases        Download mcp-toolbox (still pick engines via prompt or -Mcp)
  -Proxy URL            HTTP proxy for binary download
  -CaCert PEM           Corporate CA for binary download
"@
    exit 0
}

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$BinDir = Join-Path $RootDir "bin"
$VsCodeDir = Join-Path $RootDir ".vscode"
$Report = Join-Path $RootDir ".devops-troubleshooter-init.json"
$K8sBin = Join-Path $BinDir "kubernetes-mcp-server.exe"
$ToolboxBin = Join-Path $BinDir "toolbox.exe"

function Test-Cmd($name) {
    return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

function Add-Unique([ref]$list, $item) {
    if ($item -and ($list.Value -notcontains $item)) {
        $list.Value += $item
    }
}

function Write-Utf8NoBom($path, $content) {
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($path, $content.TrimEnd() + "`n", $utf8)
}

function Normalize-Ide($name) {
    switch ($name.Trim().ToLowerInvariant()) {
        { $_ -in @("vs", "vscode") } { return "vscode" }
        "cursor" { return "cursor" }
        { $_ -in @("cli", "copilot-cli", "copilot") } { return "copilot-cli" }
        { $_ -in @("jb", "jetbrains") } { return "jetbrains" }
        { $_ -in @("visualstudio", "vs-ide") } { return "visualstudio" }
        { $_ -in @("claude", "claude-code") } { return "claude-code" }
        default { return $name.Trim().ToLowerInvariant() }
    }
}

$os = "windows"
$arch = "amd64"
try {
    switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture) {
        "Arm64" { $arch = "arm64" }
        default { $arch = "amd64" }
    }
} catch {
    if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { $arch = "arm64" }
}

$session = "unknown"
if ($env:CURSOR_TRACE_ID -or $env:CURSOR_AGENT) { $session = "cursor" }
elseif ($env:VSCODE_PID -or $env:VSCODE_INJECTION -or $env:TERM_PROGRAM -eq "vscode") { $session = "vscode" }
elseif ($env:JETBRAINS_IDE -or $env:IDEA_INITIAL_DIRECTORY) { $session = "jetbrains" }

$ides = @()
if (Test-Cmd "code") { Add-Unique ([ref]$ides) "vscode" }
if (Test-Cmd "cursor") { Add-Unique ([ref]$ides) "cursor" }
if (Test-Cmd "copilot") { Add-Unique ([ref]$ides) "copilot-cli" }
if (Test-Cmd "claude") { Add-Unique ([ref]$ides) "claude-code" }
if (Test-Path (Join-Path $RootDir ".vscode")) { Add-Unique ([ref]$ides) "vscode" }
if (Test-Path (Join-Path $RootDir ".cursor")) { Add-Unique ([ref]$ides) "cursor" }
if (Test-Path (Join-Path $RootDir ".idea")) { Add-Unique ([ref]$ides) "jetbrains" }
if (Test-Path (Join-Path $RootDir ".claude")) { Add-Unique ([ref]$ides) "claude-code" }
if (Get-ChildItem -Path $RootDir -Filter *.sln -ErrorAction SilentlyContinue) { Add-Unique ([ref]$ides) "visualstudio" }
if ($session -ne "unknown") { Add-Unique ([ref]$ides) $session }
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) { Add-Unique ([ref]$ides) "visualstudio" }

$harness = @()
if ($ides -contains "vscode") { $harness += "github-copilot-vscode" }
if ($ides -contains "cursor") { $harness += "cursor-agent" }
if ($ides -contains "copilot-cli") { $harness += "github-copilot-cli" }
if ($ides -contains "claude-code") { $harness += "claude-code" }
if ($ides -contains "jetbrains") { $harness += "github-copilot-jetbrains" }
if ($ides -contains "visualstudio") { $harness += "github-copilot-visualstudio" }
$settings = Join-Path $VsCodeDir "settings.json"
if ((Test-Path $settings) -and (Select-String -Path $settings -Pattern "agentHost|Agent Host|chat.agentHost" -Quiet)) {
    $harness += "vscode-agent-host"
}
if (Test-Path "$env:USERPROFILE\.copilot") { $harness += "copilot-user-profile" }

$kubeconfig = $env:KUBECONFIG
if (-not $kubeconfig) { $kubeconfig = Join-Path $env:USERPROFILE ".kube\config" }

$grafana = $WithObservability
$envFile = Join-Path $VsCodeDir "mcp.env"
if (Test-Path $envFile) {
    if (Select-String -Path $envFile -Pattern '^\s*GRAFANA_URL=' -Quiet) { $grafana = $true }
}

$report = [ordered]@{
    platform = @{ os = $os; arch = $arch }
    workspace = $RootDir
    session = $session
    ides = ($ides -join ",")
    harness = ($harness -join ",")
    kubeconfig = $kubeconfig
    kubeconfig_exists = (Test-Path $kubeconfig)
    helm = (Test-Cmd "helm")
    kubectl = (Test-Cmd "kubectl")
    uvx = (Test-Cmd "uvx")
    npx = (Test-Cmd "npx")
    observability = $grafana
    binaries = @{
        "kubernetes-mcp-server" = (Test-Path $K8sBin)
        toolbox = (Test-Path $ToolboxBin)
    }
}

Write-Host "DevOps Troubleshooter init"
Write-Host "  platform:   $os/$arch"
Write-Host "  session:    $session"
Write-Host "  IDEs:       $($ides -join ', ')"
Write-Host "  harness:    $($harness -join ', ')"
Write-Host "  kubeconfig: $kubeconfig $(if (Test-Path $kubeconfig) { '[found]' } else { '[missing]' })"
Write-Host "  helm:       $(Test-Cmd 'helm')   kubectl: $(Test-Cmd 'kubectl')"
Write-Host ""

Write-Utf8NoBom $Report ($report | ConvertTo-Json -Depth 5)

if ($DiscoverOnly) {
    Write-Host "Discovery only. Report: $Report"
    exit 0
}

$setup = Join-Path $RootDir "scripts\setup.ps1"
$setupArgs = @{ }
if ($Proxy) { $setupArgs.Proxy = $Proxy }
if ($CaCert) { $setupArgs.CaCert = $CaCert }

if (-not (Test-Path $envFile) -and (Test-Path (Join-Path $VsCodeDir "mcp.env.example"))) {
    Copy-Item (Join-Path $VsCodeDir "mcp.env.example") $envFile
}

function Test-McpEnv($name) {
    if (-not (Test-Path $envFile)) { return $false }
    $hits = Select-String -Path $envFile -Pattern ("^\s*" + [regex]::Escape($name) + "=.+") -ErrorAction SilentlyContinue
    foreach ($h in $hits) {
        if ($h.Line -notmatch '^\s*#') { return $true }
    }
    return $false
}

$wantGrafana = $grafana
$wantPg = Test-McpEnv "POSTGRES_HOST"
$wantMy = Test-McpEnv "MYSQL_HOST"
$wantOr = Test-McpEnv "ORACLE_CONNECTION_STRING"
$wantMs = Test-McpEnv "MSSQL_HOST"
$wantSqlite = Test-McpEnv "SQLITE_DATABASE"
$wantCh = Test-McpEnv "CLICKHOUSE_HOST"
$wantEs = Test-McpEnv "ELASTICSEARCH_HOST"
$wantNeo = Test-McpEnv "NEO4J_URI"
$wantSf = Test-McpEnv "SNOWFLAKE_ACCOUNT"
$wantMongo = Test-McpEnv "MDB_MCP_CONNECTION_STRING"

function Mark-Mcp($token) {
    switch -Regex ($token.Trim().ToLowerInvariant()) {
        '^(k8s|kubernetes|inspect)$' { }
        '^(1|grafana|obs|observability)$' { $script:wantGrafana = $true }
        '^(2|postgres|postgresql|pg)$' { $script:wantPg = $true }
        '^(3|mysql|mariadb)$' { $script:wantMy = $true }
        '^(4|oracle|oracledb)$' { $script:wantOr = $true }
        '^(5|mssql|sqlserver|sql-server)$' { $script:wantMs = $true }
        '^(6|sqlite)$' { $script:wantSqlite = $true }
        '^(7|clickhouse)$' { $script:wantCh = $true }
        '^(8|elasticsearch|elastic|es)$' { $script:wantEs = $true }
        '^(9|neo4j)$' { $script:wantNeo = $true }
        '^(10|snowflake)$' { $script:wantSf = $true }
        '^(11|mongodb|mongo)$' { $script:wantMongo = $true }
        '^all$' {
            $script:wantGrafana = $true
            $script:wantPg = $true; $script:wantMy = $true; $script:wantOr = $true
            $script:wantMs = $true; $script:wantSqlite = $true; $script:wantCh = $true
            $script:wantEs = $true; $script:wantNeo = $true; $script:wantSf = $true
            $script:wantMongo = $true
            Write-Host "Warning: enabling every DB plus Grafana can exceed Copilot's 128-tool cap."
        }
        '^none$' { }
        default { if ($token.Trim()) { Write-Host "Unknown MCP choice: $token (ignored)" } }
    }
}

function Apply-McpList($raw) {
    foreach ($tok in ($raw -split '[, ]+')) { Mark-Mcp $tok }
}

function Flag($b) { if ($b) { '*' } else { ' ' } }

$skipPrompt = $Yes -or $Mcp -or $env:GITHUB_ACTIONS -or $env:CI
try {
    if ([Console]::IsInputRedirected) { $skipPrompt = $true }
} catch { }

if ($Mcp) {
    Apply-McpList $Mcp
    Write-Host "MCP selection (-Mcp): $Mcp"
} elseif ($Yes) {
    Write-Host "Skipping MCP prompt (-Yes). kubernetes-inspect plus any flags / mcp.env."
} elseif ($skipPrompt) {
    Write-Host "Non-interactive session: kubernetes-inspect plus any flags / mcp.env."
    Write-Host "  To choose MCPs: .\scripts\init.ps1 -Mcp grafana,postgres,mongodb"
} else {
    Write-Host ""
    Write-Host "Choose optional MCP servers to download and wire. kubernetes-inspect is always installed."
    Write-Host "  [*] = already selected from flags or .vscode\mcp.env"
    Write-Host ""
    Write-Host ("  {0}  1) grafana         Prometheus + Loki via Grafana (uvx)" -f (Flag $wantGrafana))
    Write-Host ("  {0}  2) postgres" -f (Flag $wantPg))
    Write-Host ("  {0}  3) mysql" -f (Flag $wantMy))
    Write-Host ("  {0}  4) oracle" -f (Flag $wantOr))
    Write-Host ("  {0}  5) mssql           SQL Server" -f (Flag $wantMs))
    Write-Host ("  {0}  6) sqlite" -f (Flag $wantSqlite))
    Write-Host ("  {0}  7) clickhouse" -f (Flag $wantCh))
    Write-Host ("  {0}  8) elasticsearch" -f (Flag $wantEs))
    Write-Host ("  {0}  9) neo4j" -f (Flag $wantNeo))
    Write-Host ("  {0} 10) snowflake" -f (Flag $wantSf))
    Write-Host ("  {0} 11) mongodb         official MCP, --readOnly" -f (Flag $wantMongo))
    Write-Host ""
    Write-Host "Comma-separated numbers or names. Examples: 1,2,11   grafana,postgres,mongodb   all"
    Write-Host "Empty keeps the [*] selections (kubernetes only if none are marked)."
    $ans = Read-Host "MCPs to install"
    if ($ans) { Apply-McpList $ans }
}

if ($wantGrafana) { $grafana = $true }

$chosen = @("kubernetes-inspect")
if ($wantGrafana) { $chosen += "grafana" }
if ($wantPg) { $chosen += "postgres" }
if ($wantMy) { $chosen += "mysql" }
if ($wantOr) { $chosen += "oracle" }
if ($wantMs) { $chosen += "mssql" }
if ($wantSqlite) { $chosen += "sqlite" }
if ($wantCh) { $chosen += "clickhouse" }
if ($wantEs) { $chosen += "elasticsearch" }
if ($wantNeo) { $chosen += "neo4j" }
if ($wantSf) { $chosen += "snowflake" }
if ($wantMongo) { $chosen += "mongodb" }
Write-Host "Will install: $($chosen -join ', ')"
Write-Host ""

if (-not (Test-Path $K8sBin)) {
    Write-Host "Downloading kubernetes-mcp-server..."
    & $setup @setupArgs -K8sOnly
}

$wantToolbox = ($wantPg -or $wantMy -or $wantOr -or $wantMs -or $wantSqlite -or $wantCh -or $wantEs -or $wantNeo -or $wantSf)
if ($WithDatabases -or $wantToolbox) {
    if (-not (Test-Path $ToolboxBin)) {
        Write-Host "Downloading mcp-toolbox (selected databases)..."
        try {
            & $setup @setupArgs -DbOnly -SkipMcpConfig
        } catch {
            Write-Host "Warning: toolbox download failed. Use .vscode/mcp.databases.npx.windows.json (npx.cmd)."
        }
    }
}

$envFileJson = $envFile.Replace('\', '\\')
$k8sJson = $K8sBin.Replace('\', '\\')
$grafanaArgs = '["mcp-grafana", "--disable-write", "--enabled-tools", "datasource,prometheus,loki"]'

$dbCmd = "npx.cmd"
$dbArgsPrefix = '["-y", "@toolbox-sdk/server", "--prebuilt='
$dbArgsSuffix = '", "--stdio"]'
if (Test-Path $ToolboxBin) {
    $dbCmd = $ToolboxBin.Replace('\', '\\')
    $dbArgsPrefix = '["--prebuilt='
    $dbArgsSuffix = '", "--stdio"]'
}

$dbBlock = ""
function Add-DbServer($name, $prebuilt) {
    $script:dbBlock += @"

,
    "$name": {
      "type": "stdio",
      "command": "$dbCmd",
      "args": $($dbArgsPrefix)$prebuilt$($dbArgsSuffix),
      "envFile": "$envFileJson"
    }
"@
}
if ($wantPg) { Add-DbServer "db-postgres" "postgres" }
if ($wantMy) { Add-DbServer "db-mysql" "mysql" }
if ($wantOr) { Add-DbServer "db-oracle" "oracle" }
if ($wantMs) { Add-DbServer "db-mssql" "mssql" }
if ($wantSqlite) { Add-DbServer "db-sqlite" "sqlite" }
if ($wantCh) { Add-DbServer "db-clickhouse" "clickhouse" }
if ($wantEs) { Add-DbServer "db-elasticsearch" "elasticsearch" }
if ($wantNeo) { Add-DbServer "db-neo4j" "neo4j" }
if ($wantSf) { Add-DbServer "db-snowflake" "snowflake" }
if ($wantMongo) {
    $script:dbBlock += @"

,
    "db-mongodb": {
      "type": "stdio",
      "command": "npx.cmd",
      "args": ["-y", "mongodb-mcp-server@latest", "--readOnly"],
      "envFile": "$envFileJson"
    }
"@
}
if ($wantPg -and -not (Test-McpEnv "POSTGRES_HOST")) { Write-Host "  Reminder: set POSTGRES_HOST in .vscode\mcp.env" }
if ($wantMy -and -not (Test-McpEnv "MYSQL_HOST")) { Write-Host "  Reminder: set MYSQL_HOST in .vscode\mcp.env" }
if ($wantOr -and -not (Test-McpEnv "ORACLE_CONNECTION_STRING")) { Write-Host "  Reminder: set ORACLE_CONNECTION_STRING in .vscode\mcp.env" }
if ($wantMs -and -not (Test-McpEnv "MSSQL_HOST")) { Write-Host "  Reminder: set MSSQL_HOST in .vscode\mcp.env" }
if ($wantSqlite -and -not (Test-McpEnv "SQLITE_DATABASE")) { Write-Host "  Reminder: set SQLITE_DATABASE in .vscode\mcp.env" }
if ($wantCh -and -not (Test-McpEnv "CLICKHOUSE_HOST")) { Write-Host "  Reminder: set CLICKHOUSE_HOST in .vscode\mcp.env" }
if ($wantEs -and -not (Test-McpEnv "ELASTICSEARCH_HOST")) { Write-Host "  Reminder: set ELASTICSEARCH_HOST in .vscode\mcp.env" }
if ($wantNeo -and -not (Test-McpEnv "NEO4J_URI")) { Write-Host "  Reminder: set NEO4J_URI in .vscode\mcp.env" }
if ($wantSf -and -not (Test-McpEnv "SNOWFLAKE_ACCOUNT")) { Write-Host "  Reminder: set SNOWFLAKE_ACCOUNT in .vscode\mcp.env" }
if ($wantMongo -and -not (Test-McpEnv "MDB_MCP_CONNECTION_STRING")) { Write-Host "  Reminder: set MDB_MCP_CONNECTION_STRING in .vscode\mcp.env" }
if ($wantGrafana -and -not (Test-McpEnv "GRAFANA_URL")) { Write-Host "  Reminder: set GRAFANA_URL and GRAFANA_SERVICE_ACCOUNT_TOKEN in .vscode\mcp.env" }
if ($wantMongo) { Write-Host "  MongoDB package downloads via npx.cmd the first time you start db-mongodb." }
if ($wantGrafana) { Write-Host "  Grafana package downloads via uvx the first time you start grafana." }

$grafanaBlock = ""
if ($grafana -and (Test-Cmd "uvx")) {
    $grafanaBlock = @"
,
    "grafana": {
      "type": "stdio",
      "command": "uvx",
      "args": $grafanaArgs,
      "envFile": "$envFileJson"
    }
"@
} elseif ($grafana) {
    Write-Host "Note: -WithObservability needs uvx (https://docs.astral.sh/uv/). Skipping Grafana MCP."
}

$extraBlock = "$dbBlock$grafanaBlock"

function Write-CopilotMcp($dest) {
    Write-Utf8NoBom $dest @"
{
  "servers": {
    "kubernetes-inspect": {
      "type": "stdio",
      "command": "$k8sJson",
      "args": ["--read-only", "--toolsets", "core,config,helm"],
      "envFile": "$envFileJson"
    }$extraBlock
  }
}
"@
}

function Want-Ide($name) {
    if (-not $Ide) {
        return ($ides -contains $name)
    }
    foreach ($part in $Ide.Split(",")) {
        if ((Normalize-Ide $part) -eq $name) { return $true }
    }
    return $false
}

Write-CopilotMcp (Join-Path $RootDir ".mcp.json")
Write-Host "Wrote .mcp.json (Copilot CLI, Agent Host, Visual Studio, JetBrains workspace)"

if ((Want-Ide "vscode") -or (-not $Ide)) {
    Write-CopilotMcp (Join-Path $VsCodeDir "mcp.json")
    Write-Host "Wrote .vscode\mcp.json"
}

if ((Want-Ide "jetbrains") -or (Test-Path (Join-Path $RootDir ".idea"))) {
    Write-CopilotMcp (Join-Path $RootDir ".github\mcp.json")
    Write-Host "Wrote .github\mcp.json (JetBrains Copilot workspace MCP)"
}

if ((Want-Ide "cursor") -or ($session -eq "cursor") -or (Test-Path (Join-Path $RootDir ".cursor"))) {
    $cursorDir = Join-Path $RootDir ".cursor"
    $kubeJson = $kubeconfig.Replace('\', '\\')
    $g = ""
    if ($grafanaBlock) {
        $g = @"
,
    "grafana": {
      "command": "uvx",
      "args": ["mcp-grafana", "--disable-write", "--enabled-tools", "datasource,prometheus,loki"]
    }
"@
    }
    Write-Utf8NoBom (Join-Path $cursorDir "mcp.json") @"
{
  "mcpServers": {
    "kubernetes-inspect": {
      "command": "$k8sJson",
      "args": ["--read-only", "--toolsets", "core,config,helm"],
      "env": { "KUBECONFIG": "$kubeJson" }
    }$dbBlock$g
  }
}
"@
    Write-Host "Wrote .cursor\mcp.json (Cursor mcpServers format)"
}

$copilotUser = Join-Path $env:USERPROFILE ".copilot\mcp-config.json"
if ((Want-Ide "copilot-cli") -or ((-not $Ide) -and (Test-Cmd "copilot"))) {
    if (-not (Test-Path $copilotUser)) {
        Write-CopilotMcp $copilotUser
        Write-Host "Wrote $copilotUser"
    } else {
        Write-Host "Left existing $copilotUser unchanged"
    }
}

if (-not (Test-Cmd "helm")) {
    Write-Host ""
    Write-Host "Warning: helm.exe not on PATH. helm history / helm get values will not work until you install Helm."
    Write-Host "  winget install Helm.Helm   or   choco install kubernetes-helm"
}
if (-not (Test-Path $kubeconfig)) {
    Write-Host "Warning: kubeconfig not found at $kubeconfig"
}

Write-Host ""
Write-Host "Init complete. Report: $Report"
Write-Host "Next: open Copilot/Cursor Agent mode and choose DevOps Troubleshooter."
Write-Host "      MCP: start kubernetes-inspect (and grafana / db-* if enabled)."
