# Corporate proxy and SSL inspection

This kit has to work on machines that cannot talk to the internet directly.
There are **three separate TLS stacks**. Fixing only Copilot is not enough.

macOS setup: [macos.md](macos.md). Windows-specific setup (`.exe`, `npx.cmd`, execution policy): [windows.md](windows.md).

| Traffic | Stack | What it needs |
|---------|--------|----------------|
| GitHub Copilot Chat | VS Code / Electron | `http.proxy` + system CA or `NODE_EXTRA_CA_CERTS` |
| `npx` MCP servers | Node.js | `HTTPS_PROXY` + `NODE_EXTRA_CA_CERTS` (Node does **not** use the OS trust store well) |
| `kubernetes-mcp-server` / `toolbox` binaries | Go | `HTTPS_PROXY` + OS trust store (Windows/macOS) or `SSL_CERT_FILE` |
| `scripts/init.sh` / `init.ps1` and `setup.sh` / `setup.ps1` downloads | curl / curl.exe | `--proxy` / `-Proxy` + `--cacert` / `-CaCert` |
| Cluster API and databases | usually internal | Must be on `NO_PROXY` so they do **not** go through the internet proxy |

Copilot does **not** support an `https://` proxy URL. Use `http://proxy.example.com:8080`.

Do **not** set `NODE_TLS_REJECT_UNAUTHORIZED=0` or `http.proxyStrictSSL: false` as a permanent fix. That disables certificate checks. Use the corporate root CA as a PEM file instead.

## 1. Get the corporate root CA

Ask IT for the SSL-inspection / forward-proxy **root** certificate in PEM format (`.pem` / `.crt`).

You can also export it yourself from the OS trust store:

**macOS**
```bash
security find-certificate -a -p /Library/Keychains/System.keychain > ~/certs/corp-ca.pem
```

**Windows (PowerShell)** — export the issuing CA from `certmgr.msc` as Base-64 X.509, or:
```powershell
Get-ChildItem Cert:\LocalMachine\Root |
  Where-Object { $_.Subject -match 'YourCorp' } |
  ForEach-Object {
    $pem = "-----BEGIN CERTIFICATE-----`n" +
           [Convert]::ToBase64String($_.RawData, 'InsertLineBreaks') +
           "`n-----END CERTIFICATE-----"
    Set-Content -Path $env:USERPROFILE\certs\corp-ca.pem -Value $pem
  }
```

## 2. VS Code + GitHub Copilot (the chat model)

Copy [`.vscode/settings.example.json`](../.vscode/settings.example.json) values into **User** settings (not the shared workspace, if the proxy is personal):

```json
{
  "http.proxy": "http://proxy.corp.example.com:8080",
  "http.proxySupport": "override",
  "http.proxyStrictSSL": true,
  "http.systemCertificates": true
}
```

Then either:

- Install the corporate CA into the OS trust store (preferred), **or**
- Launch VS Code from a shell that has `NODE_EXTRA_CA_CERTS` set:

```bash
export NODE_EXTRA_CA_CERTS="$HOME/certs/corp-ca.pem"
export HTTPS_PROXY="http://proxy.corp.example.com:8080"
export HTTP_PROXY="$HTTPS_PROXY"
code .
```

**Windows**
```powershell
$env:NODE_EXTRA_CA_CERTS="$env:USERPROFILE\certs\corp-ca.pem"
$env:HTTPS_PROXY="http://proxy.corp.example.com:8080"
code .
```

If Copilot still fails, check **Output** → **GitHub Copilot Log**. Typical errors:

- `UNABLE_TO_VERIFY_LEAF_SIGNATURE` / `unable to get local issuer certificate` → CA not trusted by Node
- `ECONNREFUSED` / `ETIMEDOUT` → proxy URL wrong or Copilot endpoints blocked
- `407` → proxy needs basic auth in the URL (`http://user:pass@proxy:8080`)

Allowlist (ask network team):

- `api.github.com`
- `api.githubcopilot.com`
- `copilot-proxy.githubusercontent.com`
- `*.githubusercontent.com`

Kerberos proxy: set `http.proxyKerberosServicePrincipal` in VS Code settings (see [GitHub Copilot network settings](https://docs.github.com/en/copilot/how-tos/configure-personal-settings/configure-network-settings?tool=vscode)).

## 3. MCP servers (npx and binaries)

MCP child processes do not always inherit proxy/CA variables. This kit loads them from `.vscode/mcp.env`.

```bash
cp .vscode/mcp.env.example .vscode/mcp.env
```
```powershell
Copy-Item .vscode\mcp.env.example .vscode\mcp.env
```

Uncomment and set at least:

```
HTTPS_PROXY=http://proxy.corp.example.com:8080
HTTP_PROXY=http://proxy.corp.example.com:8080
NO_PROXY=localhost,127.0.0.1,::1,.svc,.cluster.local,.internal.example.com
NODE_USE_ENV_PROXY=1
```

**macOS/Linux CA paths**
```
NODE_EXTRA_CA_CERTS=/Users/you/certs/corp-ca.pem
SSL_CERT_FILE=/Users/you/certs/corp-ca.pem
CURL_CA_BUNDLE=/Users/you/certs/corp-ca.pem
NPM_CONFIG_CAFILE=/Users/you/certs/corp-ca.pem
```

**Windows CA paths**
```
NODE_EXTRA_CA_CERTS=C:\Users\you\certs\corp-ca.pem
SSL_CERT_FILE=C:\Users\you\certs\corp-ca.pem
CURL_CA_BUNDLE=C:\Users\you\certs\corp-ca.pem
NPM_CONFIG_CAFILE=C:\Users\you\certs\corp-ca.pem
```

Then **MCP: List Servers** → Restart `kubernetes-inspect`.

`NO_PROXY` must include Kubernetes API hosts and database hosts. If those go through the internet proxy, log fetch and SQL will fail.

## 4. Binary downloads (`setup.sh` / `setup.ps1`)

```bash
./scripts/setup.sh --proxy http://proxy.corp:8080 --cacert "$HOME/certs/corp-ca.pem"
```

```powershell
.\scripts\setup.ps1 -Proxy http://proxy.corp:8080 -CaCert $env:USERPROFILE\certs\corp-ca.pem
```

The scripts also read `HTTPS_PROXY` and `SSL_CERT_FILE` if the flags are omitted.

## 5. npm / npx (Option B)

```bash
npm config set proxy http://proxy.corp.example.com:8080
npm config set https-proxy http://proxy.corp.example.com:8080
npm config set cafile "$HOME/certs/corp-ca.pem"
```

```powershell
npm config set proxy http://proxy.corp.example.com:8080
npm config set https-proxy http://proxy.corp.example.com:8080
npm config set cafile "$env:USERPROFILE\certs\corp-ca.pem"
```

On Windows, VS Code must spawn `npx.cmd` (`.vscode/mcp.npx.windows.json`). Prefer **Option A (native binaries)** on locked-down laptops so you can skip npm.

## 6. Kubernetes API TLS vs proxy TLS

These are different problems:

| Error when talking to the cluster | Cause |
|-----------------------------------|--------|
| `x509: certificate signed by unknown authority` to `api.github.com` / npm | Corporate proxy CA missing (`NODE_EXTRA_CA_CERTS` / `SSL_CERT_FILE`) |
| `x509: certificate signed by unknown authority` to your API server | kubeconfig cluster CA is wrong, or a proxy is intercepting **cluster** traffic — add the API host to `NO_PROXY` |
| `proxyconnect tcp: ...` against `10.x` or `*.svc` | Internal address is going through the proxy — fix `NO_PROXY` |

The Kubernetes MCP server uses your kubeconfig. It does not need the corporate CA to talk to an in-cluster API **if** that traffic is excluded from the proxy.

## 7. Quick verification

1. Copilot Chat replies to "hello" in Agent mode.
2. **MCP: List Servers** → `kubernetes-inspect` is Running (not a TLS error in **Show Output**).
3. In DevOps Troubleshooter: "list my kube contexts" returns names, not a certificate error.
   If several names appear, pick one (`/use-cluster`). The agent should **ask**, not guess.
   See [clusters.md](clusters.md).
