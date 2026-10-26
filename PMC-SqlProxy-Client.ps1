<#
.SYNOPSIS
    PMC SQL Proxy Client v3.0 - Multi-Server Helper Module
.DESCRIPTION
    PowerShell functions to call the PMC SQL Proxy v3.0.
    Supports targeting ANY server profile + ANY database per request.

    Usage:
        . .\PMC-SqlProxy-Client.ps1
        $proxy = Connect-PmcProxy -ApiKey "KEY" -BaseUrl "http://PROXY:9480"
        $data  = Invoke-ProxyProcedure -Client $proxy -Server "PROD" -Database "MyDB" -Procedure "MyProc"
#>

function New-ProxyClient {
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$ApiKey,
        [int]$TimeoutSec = 120
    )
    return @{ BaseUrl=$BaseUrl.TrimEnd('/'); ApiKey=$ApiKey; TimeoutSec=$TimeoutSec }
}

function Invoke-ProxyRequest {
    param([hashtable]$Client, [string]$Method, [string]$Endpoint, [object]$Body=$null)
    $url = "$($Client.BaseUrl)$Endpoint"
    $headers = @{ "X-API-Key"=$Client.ApiKey; "Content-Type"="application/json" }
    $p = @{ Uri=$url; Method=$Method; Headers=$headers; TimeoutSec=$Client.TimeoutSec; UseBasicParsing=$true; ErrorAction="Stop" }
    if ($Body) { $p["Body"] = [System.Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 10 -Compress)) }
    try {
        $resp = Invoke-WebRequest @p
        return ($resp.Content | ConvertFrom-Json)
    } catch {
        $errMsg = $_.Exception.Message
        if ($_.Exception.Response) {
            try { $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream()); $eb = $sr.ReadToEnd(); $sr.Close(); $eo = $eb | ConvertFrom-Json; $errMsg = "$($eo.error): $($eo.message)" } catch {}
        }
        throw "Proxy Error: $errMsg"
    }
}

function Test-ProxyHealth {
    param([Parameter(Mandatory)][hashtable]$Client)
    try { $r = Invoke-WebRequest -Uri "$($Client.BaseUrl)/health" -UseBasicParsing -TimeoutSec 5; return ($r.Content | ConvertFrom-Json).status -eq "healthy" } catch { return $false }
}

function Get-ProxyServers {
    <# Lists all configured SQL Server profiles. #>
    param([Parameter(Mandatory)][hashtable]$Client)
    return Invoke-ProxyRequest $Client "GET" "/api/servers"
}

function Get-ProxyDatabases {
    <# Lists databases on a specific server profile. #>
    param([Parameter(Mandatory)][hashtable]$Client, [string]$Server = "")
    $endpoint = "/api/databases"
    if ($Server) { $endpoint += "?server=$Server" }
    return Invoke-ProxyRequest $Client "GET" $endpoint
}

function Invoke-ProxyProcedure {
    <#
    .SYNOPSIS
        Executes a stored procedure on any server/database.
    .PARAMETER Server
        Server profile name (e.g. PROD, DEV). If omitted, uses default.
    .PARAMETER Database
        Target database. If omitted, uses server profile's default.
    .EXAMPLE
        $r = Invoke-ProxyProcedure -Client $proxy -Server "PROD" -Database "PMC_DB" `
             -Procedure "Payment.Prc_GetPaymentGatewayTransactionDetails" `
             -Parameters @{ Flag="GetAllTransactions" }
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Client,
        [Parameter(Mandatory)][string]$Procedure,
        [string]$Server = "",
        [string]$Database = "",
        [hashtable]$Parameters = @{}
    )
    $body = @{ procedure=$Procedure; parameters=$Parameters }
    if ($Server)   { $body["server"]   = $Server }
    if ($Database) { $body["database"] = $Database }
    return Invoke-ProxyRequest $Client "POST" "/api/execute" $body
}

function Invoke-ProxyQuery {
    <# Executes a SELECT query (Admin only). #>
    param(
        [Parameter(Mandatory)][hashtable]$Client,
        [Parameter(Mandatory)][string]$Query,
        [string]$Server = "",
        [string]$Database = "",
        [hashtable]$Parameters = @{}
    )
    $body = @{ query=$Query; parameters=$Parameters }
    if ($Server)   { $body["server"]   = $Server }
    if ($Database) { $body["database"] = $Database }
    return Invoke-ProxyRequest $Client "POST" "/api/query" $body
}

function Invoke-ProxySql {
    <# Executes INSERT/UPDATE/DELETE (Admin only). #>
    param(
        [Parameter(Mandatory)][hashtable]$Client,
        [Parameter(Mandatory)][string]$Sql,
        [string]$Server = "",
        [string]$Database = "",
        [hashtable]$Parameters = @{}
    )
    $body = @{ sql=$Sql; parameters=$Parameters }
    if ($Server)   { $body["server"]   = $Server }
    if ($Database) { $body["database"] = $Database }
    return Invoke-ProxyRequest $Client "POST" "/api/execute-sql" $body
}

function Get-ProxyStatus {
    param([Parameter(Mandatory)][hashtable]$Client)
    return Invoke-ProxyRequest $Client "GET" "/api/status"
}

function Get-ProxyLogs {
    param([Parameter(Mandatory)][hashtable]$Client, [int]$Tail=50)
    return Invoke-ProxyRequest $Client "GET" "/api/logs?n=$Tail"
}

function Connect-PmcProxy {
    <#
    .SYNOPSIS
        Connect to the PMC Proxy and show server info.
    .EXAMPLE
        $proxy = Connect-PmcProxy -ApiKey "mykey" -BaseUrl "http://192.168.1.50:9480"
    #>
    param(
        [Parameter(Mandatory)][string]$ApiKey,
        [string]$BaseUrl = "http://localhost:9480"
    )
    $client = New-ProxyClient -BaseUrl $BaseUrl -ApiKey $ApiKey
    if (Test-ProxyHealth $client) {
        Write-Host "  [OK] Connected to PMC SQL Proxy v3.0 at $BaseUrl" -ForegroundColor Green
        try {
            $info = (Invoke-WebRequest -Uri "$BaseUrl/health" -UseBasicParsing -TimeoutSec 5).Content | ConvertFrom-Json
            Write-Host "  Mode:    $($info.mode)" -ForegroundColor Gray
            Write-Host "  Default: $($info.default_server)" -ForegroundColor Gray
            Write-Host "  Servers: $($info.servers -join ', ')" -ForegroundColor Gray
        } catch {}
    } else {
        Write-Host "  [!] Proxy at $BaseUrl not responding." -ForegroundColor Yellow
    }
    return $client
}

Write-Host "  PMC SQL Proxy Client v3.0 loaded." -ForegroundColor Cyan
Write-Host "  Use: Connect-PmcProxy -ApiKey 'YOUR_KEY' -BaseUrl 'http://SERVER:9480'" -ForegroundColor Gray
