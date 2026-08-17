#Requires -Version 5.1
<#
.SYNOPSIS
    Downloads Windows MCP binaries and applies the Windows Copilot MCP config.

    If scripts are blocked:
      powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1
#>

param(
    [switch]$K8sOnly,
    [switch]$DbOnly,
    [switch]$SkipMcpConfig,
    [string]$K8sVersion = "0.0.66",
    [string]$ToolboxVersion = "1.9.0",
    [string]$Proxy = "",
    [string]$CaCert = ""
)

$ErrorActionPreference = "Stop"

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch { }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir
$BinDir = Join-Path $RootDir "bin"
$VsCodeDir = Join-Path $RootDir ".vscode"

if (-not $Proxy) {
    foreach ($name in @("HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy", "ALL_PROXY")) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if ($value) { $Proxy = $value; break }
    }
}
if (-not $CaCert) {
    foreach ($name in @("SSL_CERT_FILE", "CURL_CA_BUNDLE", "NODE_EXTRA_CA_CERTS")) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if ($value) { $CaCert = $value; break }
    }
}

function Get-Architecture {
    try {
        $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
        switch ("$arch") {
            "X64"   { return "amd64" }
            "Arm64" { return "arm64" }
        }
    } catch { }

    switch ($env:PROCESSOR_ARCHITECTURE) {
        "AMD64" { return "amd64" }
        "ARM64" { return "arm64" }
        default {
            if ($env:PROCESSOR_ARCHITEW6432 -eq "AMD64") { return "amd64" }
            throw "Unsupported architecture: $env:PROCESSOR_ARCHITECTURE"
        }
    }
}

function Get-RemoteFile {
    param([string]$Url, [string]$Dest)

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        if ($Proxy) { Write-Host "  using proxy: $Proxy" }
        if ($CaCert) { Write-Host "  using CA bundle: $CaCert" }
        $curlArgs = @(
            "-fSL", "--connect-timeout", "30", "--retry", "3",
            "-o", $Dest, $Url
        )
        if ($Proxy) { $curlArgs += @("--proxy", $Proxy) }
        if ($CaCert) { $curlArgs += @("--cacert", $CaCert) }
        & curl.exe @curlArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Download failed ($LASTEXITCODE): $Url"
        }
        return
    }

    Write-Host "  curl.exe not found; using Invoke-WebRequest"
    $params = @{
        Uri = $Url
        OutFile = $Dest
        UseBasicParsing = $true
    }
    if ($Proxy) {
        $params.Proxy = $Proxy
        $params.ProxyUseDefaultCredentials = $true
        Write-Host "  using proxy: $Proxy (default Windows credentials)"
    }
    Invoke-WebRequest @params
}

$Arch = Get-Architecture
Write-Host "Platform: windows/$Arch"
Write-Host "PowerShell: $($PSVersionTable.PSVersion)"

if (-not (Test-Path $BinDir)) {
    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
}

$mcpEnv = Join-Path $VsCodeDir "mcp.env"
$mcpEnvExample = Join-Path $VsCodeDir "mcp.env.example"
if (-not (Test-Path $mcpEnv) -and (Test-Path $mcpEnvExample)) {
    Copy-Item $mcpEnvExample $mcpEnv
    Write-Host "Created .vscode\mcp.env from example"
}

if (-not $DbOnly) {
    $k8sDest = Join-Path $BinDir "kubernetes-mcp-server.exe"
    $k8sUrl = "https://github.com/containers/kubernetes-mcp-server/releases/download/v${K8sVersion}/kubernetes-mcp-server-windows-${Arch}.exe"
    Write-Host ""
    Write-Host "Downloading kubernetes-mcp-server v${K8sVersion}..."
    Get-RemoteFile -Url $k8sUrl -Dest $k8sDest
    Unblock-File -Path $k8sDest -ErrorAction SilentlyContinue
    Write-Host "Installed: $k8sDest"
}

if (-not $K8sOnly) {
    $toolboxDest = Join-Path $BinDir "toolbox.exe"
    $toolboxUrl = "https://storage.googleapis.com/mcp-toolbox-for-databases/v${ToolboxVersion}/windows/${Arch}/toolbox.exe"
    Write-Host ""
    Write-Host "Downloading mcp-toolbox v${ToolboxVersion}..."
    try {
        Get-RemoteFile -Url $toolboxUrl -Dest $toolboxDest
        Unblock-File -Path $toolboxDest -ErrorAction SilentlyContinue
        Write-Host "Installed: $toolboxDest"
    } catch {
        Write-Host "Warning: toolbox download failed for windows/$Arch."
        Write-Host "         Use npx.cmd @toolbox-sdk/server — see .vscode/mcp.databases.npx.windows.json"
        if ($DbOnly) { throw }
    }
}

if (-not $SkipMcpConfig) {
    $src = Join-Path $VsCodeDir "mcp.binary.windows.json"
    $dst = Join-Path $VsCodeDir "mcp.json"
    Copy-Item $src $dst -Force
    Write-Host ""
    Write-Host "Applied Windows MCP config: .vscode\mcp.json now points at bin\*.exe"
}

Write-Host ""
Write-Host "Setup complete. Binaries:"
Get-ChildItem $BinDir -Filter *.exe | Format-Table Name, Length -AutoSize

Write-Host @"

Next steps:
  1. If you are behind a corporate proxy, edit .vscode\mcp.env (see docs\windows.md)
  2. Open this folder in VS Code
  3. Copilot Chat -> Agent mode -> DevOps Troubleshooter
  4. Command Palette -> MCP: List Servers -> start kubernetes-inspect

If this script was blocked:
  powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1
"@
