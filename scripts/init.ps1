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
    [string]$Kubeconfig = "",
    [string]$Scope = "",
    [switch]$Help
)

if ($Help) {
    Write-Host @"
Usage: .\scripts\init.ps1 [options]

Discover platform, IDEs, and agent harnesses, then write MCP configs.

  -DiscoverOnly         Print discovery report only (no downloads, no writes)
  -Scope workspace|global
                        workspace = this repo only (default for -Yes / CI)
                        global    = every workspace (%USERPROFILE%\.copilot + user MCP)
  -Ide vscode,cursor,cli  Limit config writes (aliases: vs, cli, jb, claude)
  -Mcp grafana,postgres,mongodb
                          Non-interactive MCP pick. Always includes kubernetes.
  -Yes                  Skip scope + MCP prompts (workspace, kubernetes only, plus -Mcp / -With* / mcp.env)
  -WithObservability    Add Grafana MCP (same as including grafana in -Mcp)
  -WithDatabases        Download mcp-toolbox (still pick engines via prompt or -Mcp)
  -Proxy URL            HTTP proxy for binary download
  -CaCert PEM           Corporate CA for binary download
  -Kubeconfig PATHS     KUBECONFIG for MCP (one file, or semicolon-separated files)
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
$GlobalRoot = if ($env:DTO_HOME) { $env:DTO_HOME } else { Join-Path $env:LOCALAPPDATA "devops-troubleshooter" }
$CopilotUser = Join-Path $env:USERPROFILE ".copilot"
$CursorUser = Join-Path $env:USERPROFILE ".cursor"
$VsCodeUserMcp = Join-Path $env:APPDATA "Code\User\mcp.json"

function Normalize-Scope($name) {
    switch -Regex ([string]$name) {
        '^(workspace|repo|local)$' { return "workspace" }
        '^(global|user|profile)$' { return "global" }
        '^$' { return "" }
        default { throw "Unknown -Scope: $name (use workspace or global)" }
    }
}
$Scope = Normalize-Scope $Scope

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

$kubeconfig = $Kubeconfig
if (-not $kubeconfig) { $kubeconfig = $env:KUBECONFIG }
if (-not $kubeconfig) { $kubeconfig = Join-Path $env:USERPROFILE ".kube\config" }

function Test-KubeconfigSpec($spec) {
    if ([string]::IsNullOrWhiteSpace($spec)) { return $false }
    foreach ($part in ($spec -split ';')) {
        $p = $part.Trim()
        if ($p -and (Test-Path -LiteralPath $p)) { return $true }
    }
    return $false
}

$kubeconfigExists = Test-KubeconfigSpec $kubeconfig
$kubeContexts = @()
$kubeCurrent = ""
if (Test-Cmd "kubectl") {
    $savedKube = $env:KUBECONFIG
    $env:KUBECONFIG = $kubeconfig
    try {
        $kubeCurrent = (kubectl config current-context 2>$null | Out-String).Trim()
        $kubeContexts = @(kubectl config get-contexts -o name 2>$null | Where-Object { $_.Trim() })
    } catch {
        $kubeCurrent = ""
        $kubeContexts = @()
    } finally {
        if ($null -eq $savedKube -or $savedKube -eq "") {
            Remove-Item Env:\KUBECONFIG -ErrorAction SilentlyContinue
        } else {
            $env:KUBECONFIG = $savedKube
        }
    }
}

$grafana = $WithObservability
$envFile = Join-Path $VsCodeDir "mcp.env"
if (Test-Path $envFile) {
    if (Select-String -Path $envFile -Pattern '^\s*GRAFANA_URL=' -Quiet) { $grafana = $true }
}

$report = [ordered]@{
    platform = @{ os = $os; arch = $arch }
    workspace = $RootDir
    scope = $(if ($Scope) { $Scope } else { "workspace" })
    global_root = $GlobalRoot
    session = $session
    ides = ($ides -join ",")
    harness = ($harness -join ",")
    kubeconfig = $kubeconfig
    kubeconfig_exists = $kubeconfigExists
    kube_contexts = $kubeContexts
    kube_current_context = $kubeCurrent
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
Write-Host "  kubeconfig: $kubeconfig $(if ($kubeconfigExists) { '[found]' } else { '[missing]' })"
if ($kubeContexts.Count -gt 0) {
    Write-Host "  contexts:   $($kubeContexts -join ', ')"
    Write-Host "  current:    $(if ($kubeCurrent) { $kubeCurrent } else { 'none' })"
}
Write-Host "  helm:       $(Test-Cmd 'helm')   kubectl: $(Test-Cmd 'kubectl')"
Write-Host ""

Write-Utf8NoBom $Report ($report | ConvertTo-Json -Depth 5)

if ($DiscoverOnly) {
    Write-Host "Discovery only. Report: $Report"
    exit 0
}

function Resolve-Scope {
    if ($script:Scope) {
        Write-Host "Install scope: $($script:Scope) (-Scope)"
        return
    }
    $nonInteractive = $Yes -or $env:GITHUB_ACTIONS -or $env:CI
    try { if ([Console]::IsInputRedirected) { $nonInteractive = $true } } catch { }
    if ($nonInteractive) {
        $script:Scope = "workspace"
        Write-Host "Install scope: workspace (non-interactive default)"
        return
    }
    Write-Host ""
    Write-Host "Install scope:"
    Write-Host "  1) workspace — this repo only (.vscode\mcp.json, .github\agents)"
    Write-Host "  2) global    — every workspace ($env:USERPROFILE\.copilot + user MCP)"
    Write-Host ""
    $ans = Read-Host "Scope [workspace]"
    switch -Regex ($ans.Trim().ToLowerInvariant()) {
        '^(2|g|global|user|profile)$' { $script:Scope = "global" }
        default { $script:Scope = "workspace" }
    }
    Write-Host "Install scope: $($script:Scope)"
}

Resolve-Scope
$report.scope = $Scope
Write-Utf8NoBom $Report ($report | ConvertTo-Json -Depth 5)

$setup = Join-Path $RootDir "scripts\setup.ps1"
$setupArgs = @{ }
if ($Proxy) { $setupArgs.Proxy = $Proxy }
if ($CaCert) { $setupArgs.CaCert = $CaCert }

$exampleEnv = Join-Path $VsCodeDir "mcp.env.example"
if ($Scope -eq "global") {
    if (-not (Test-Path $GlobalRoot)) {
        New-Item -ItemType Directory -Force -Path $GlobalRoot | Out-Null
    }
    $envFile = Join-Path $GlobalRoot "mcp.env"
    if (-not (Test-Path $envFile)) {
        if (Test-Path (Join-Path $VsCodeDir "mcp.env")) {
            Copy-Item (Join-Path $VsCodeDir "mcp.env") $envFile
        } elseif (Test-Path $exampleEnv) {
            Copy-Item $exampleEnv $envFile
        }
    }
} else {
    if (-not (Test-Path $envFile) -and (Test-Path $exampleEnv)) {
        Copy-Item $exampleEnv $envFile
    }
}

if ($Kubeconfig) {
    if (-not (Test-Path $envFile) -and (Test-Path $exampleEnv)) {
        Copy-Item $exampleEnv $envFile
    }
    if (Test-Path $envFile) {
        $lines = Get-Content $envFile | Where-Object { $_ -notmatch '^\s*#?\s*KUBECONFIG=' }
        $lines += "KUBECONFIG=$kubeconfig"
        Write-Utf8NoBom $envFile ($lines -join "`n")
        Write-Host "Wrote KUBECONFIG to $envFile (restart kubernetes-inspect after init)"
    }
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
    Write-Host "  [*] = already selected from flags or mcp.env"
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

$K8sUse = $K8sBin
$ToolboxUse = $ToolboxBin
if ($Scope -eq "global") {
    $shareBin = Join-Path $GlobalRoot "bin"
    New-Item -ItemType Directory -Force -Path $shareBin | Out-Null
    Copy-Item $K8sBin (Join-Path $shareBin "kubernetes-mcp-server.exe") -Force
    $K8sUse = Join-Path $shareBin "kubernetes-mcp-server.exe"
    if (Test-Path $ToolboxBin) {
        Copy-Item $ToolboxBin (Join-Path $shareBin "toolbox.exe") -Force
        $ToolboxUse = Join-Path $shareBin "toolbox.exe"
    }
    Write-Host "Installed MCP binaries under $shareBin"
}

$envFileJson = $envFile.Replace('\', '\\')
$k8sJson = $K8sUse.Replace('\', '\\')
$grafanaArgs = '["mcp-grafana", "--disable-write", "--enabled-tools", "datasource,prometheus,loki"]'

$dbCmd = "npx.cmd"
$dbArgsPrefix = '["-y", "@toolbox-sdk/server", "--prebuilt='
$dbArgsSuffix = '", "--stdio"]'
if (Test-Path $ToolboxUse) {
    $dbCmd = $ToolboxUse.Replace('\', '\\')
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
if ($wantPg -and -not (Test-McpEnv "POSTGRES_HOST")) { Write-Host "  Reminder: set POSTGRES_HOST in $envFile" }
if ($wantMy -and -not (Test-McpEnv "MYSQL_HOST")) { Write-Host "  Reminder: set MYSQL_HOST in $envFile" }
if ($wantOr -and -not (Test-McpEnv "ORACLE_CONNECTION_STRING")) { Write-Host "  Reminder: set ORACLE_CONNECTION_STRING in $envFile" }
if ($wantMs -and -not (Test-McpEnv "MSSQL_HOST")) { Write-Host "  Reminder: set MSSQL_HOST in $envFile" }
if ($wantSqlite -and -not (Test-McpEnv "SQLITE_DATABASE")) { Write-Host "  Reminder: set SQLITE_DATABASE in $envFile" }
if ($wantCh -and -not (Test-McpEnv "CLICKHOUSE_HOST")) { Write-Host "  Reminder: set CLICKHOUSE_HOST in $envFile" }
if ($wantEs -and -not (Test-McpEnv "ELASTICSEARCH_HOST")) { Write-Host "  Reminder: set ELASTICSEARCH_HOST in $envFile" }
if ($wantNeo -and -not (Test-McpEnv "NEO4J_URI")) { Write-Host "  Reminder: set NEO4J_URI in $envFile" }
if ($wantSf -and -not (Test-McpEnv "SNOWFLAKE_ACCOUNT")) { Write-Host "  Reminder: set SNOWFLAKE_ACCOUNT in $envFile" }
if ($wantMongo -and -not (Test-McpEnv "MDB_MCP_CONNECTION_STRING")) { Write-Host "  Reminder: set MDB_MCP_CONNECTION_STRING in $envFile" }
if ($wantGrafana -and -not (Test-McpEnv "GRAFANA_URL")) { Write-Host "  Reminder: set GRAFANA_URL and GRAFANA_SERVICE_ACCOUNT_TOKEN in $envFile" }
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

function Write-CursorMcp($dest) {
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
    Write-Utf8NoBom $dest @"
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
}

function Merge-McpJson($dest, $key, $srcPath) {
    $new = Get-Content -Raw $srcPath | ConvertFrom-Json
    $incoming = $new.$key
    if (-not $incoming) { $incoming = $new.servers }
    if (-not $incoming) { $incoming = $new.mcpServers }
    $old = $null
    if (Test-Path $dest) {
        try { $old = Get-Content -Raw $dest | ConvertFrom-Json } catch { $old = $null }
    }
    $targetKey = $key
    if ($old -and -not $old.PSObject.Properties[$key] -and $old.PSObject.Properties["mcpServers"] -and -not $old.PSObject.Properties["servers"]) {
        $targetKey = "mcpServers"
    }
    $merged = [ordered]@{}
    if ($old) {
        foreach ($p in $old.PSObject.Properties) {
            if ($p.Name -ne $targetKey) { $merged[$p.Name] = $p.Value }
        }
    }
    $servers = [ordered]@{}
    if ($old -and $old.PSObject.Properties[$targetKey] -and $old.$targetKey) {
        foreach ($p in $old.$targetKey.PSObject.Properties) { $servers[$p.Name] = $p.Value }
    }
    if ($incoming) {
        foreach ($p in $incoming.PSObject.Properties) { $servers[$p.Name] = $p.Value }
    }
    $merged[$targetKey] = [pscustomobject]$servers
    Write-Utf8NoBom $dest (($merged | ConvertTo-Json -Depth 8))
}

function Install-GlobalKitFiles {
    $agentDir = Join-Path $CopilotUser "agents"
    $skillRoot = Join-Path $CopilotUser "skills"
    $promptDir = Join-Path $CopilotUser "prompts"
    New-Item -ItemType Directory -Force -Path $agentDir, $skillRoot, $promptDir | Out-Null
    Copy-Item (Join-Path $RootDir ".github\agents\devops-troubleshooter.agent.md") $agentDir -Force
    Get-ChildItem (Join-Path $RootDir ".github\skills") -Directory | ForEach-Object {
        $src = Join-Path $_.FullName "SKILL.md"
        if (Test-Path $src) {
            $destDir = Join-Path $skillRoot $_.Name
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
            Copy-Item $src $destDir -Force
        }
    }
    Get-ChildItem (Join-Path $RootDir ".github\prompts") -Filter "*.prompt.md" -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item $_.FullName $promptDir -Force
    }
    Write-Host "Copied agent, skills, and prompts to $CopilotUser"
    if ((Want-Ide "cursor") -or ($session -eq "cursor") -or (Test-Path $CursorUser)) {
        $cursorSkills = Join-Path $CursorUser "skills"
        Get-ChildItem (Join-Path $RootDir ".github\skills") -Directory | ForEach-Object {
            $src = Join-Path $_.FullName "SKILL.md"
            if (Test-Path $src) {
                $destDir = Join-Path $cursorSkills $_.Name
                New-Item -ItemType Directory -Force -Path $destDir | Out-Null
                Copy-Item $src $destDir -Force
            }
        }
        Write-Host "Copied skills to $cursorSkills"
    }
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

if ($Scope -eq "global") {
    Install-GlobalKitFiles
    $tmpMcp = Join-Path $env:TEMP "dto-mcp-$PID.json"
    Write-CopilotMcp $tmpMcp
    Merge-McpJson (Join-Path $CopilotUser "mcp-config.json") "servers" $tmpMcp
    Write-Host "Wrote $(Join-Path $CopilotUser 'mcp-config.json')"
    if ((Want-Ide "vscode") -or (-not $Ide)) {
        $vsUserDir = Split-Path -Parent $VsCodeUserMcp
        if ((Test-Path $vsUserDir) -or (Want-Ide "vscode")) {
            Merge-McpJson $VsCodeUserMcp "servers" $tmpMcp
            Write-Host "Wrote $VsCodeUserMcp"
        }
    }
    Remove-Item $tmpMcp -ErrorAction SilentlyContinue
    if ((Want-Ide "cursor") -or ($session -eq "cursor") -or (Test-Path $CursorUser)) {
        $tmpCursor = Join-Path $env:TEMP "dto-cursor-mcp-$PID.json"
        Write-CursorMcp $tmpCursor
        Merge-McpJson (Join-Path $CursorUser "mcp.json") "mcpServers" $tmpCursor
        Remove-Item $tmpCursor -ErrorAction SilentlyContinue
        Write-Host "Wrote $(Join-Path $CursorUser 'mcp.json')"
    }
    Write-Host "Global install does not write workspace .mcp.json / .vscode\mcp.json"
} else {
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
        Write-CursorMcp (Join-Path $RootDir ".cursor\mcp.json")
        Write-Host "Wrote .cursor\mcp.json (Cursor mcpServers format)"
    }

    $copilotUserMcp = Join-Path $CopilotUser "mcp-config.json"
    if ((Want-Ide "copilot-cli") -or ((-not $Ide) -and (Test-Cmd "copilot"))) {
        if (-not (Test-Path $copilotUserMcp)) {
            Write-CopilotMcp $copilotUserMcp
            Write-Host "Wrote $copilotUserMcp"
        } else {
            Write-Host "Left existing $copilotUserMcp unchanged"
        }
    }
}

if (-not (Test-Cmd "helm")) {
    Write-Host ""
    Write-Host "Warning: helm.exe not on PATH. helm history / helm get values will not work until you install Helm."
    Write-Host "  winget install Helm.Helm   or   choco install kubernetes-helm"
}
if (-not $kubeconfigExists) {
    Write-Host "Warning: kubeconfig not found at $kubeconfig"
    Write-Host "  Multiple files: KUBECONFIG=file1;file2;file3  (Unix: file1:file2)"
}

Write-Host ""
Write-Host "Init complete ($Scope). Report: $Report"
if ($Scope -eq "global") {
    Write-Host "Next: open any workspace → Copilot/Cursor Agent mode → DevOps Troubleshooter."
    Write-Host "      Reload the window if the agent is missing. MCP: start kubernetes-inspect."
} else {
    Write-Host "Next: open this repo in Copilot/Cursor Agent mode and choose DevOps Troubleshooter."
    Write-Host "      MCP: start kubernetes-inspect (and grafana / db-* if enabled)."
}
