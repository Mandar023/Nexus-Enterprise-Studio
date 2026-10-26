<#
.SYNOPSIS
    PMC SQL Proxy Service v3.0 - Multi-Server Middle-Tier API
.DESCRIPTION
    Network-wide REST API that proxies SQL connections to MULTIPLE SQL Servers.
    Clients specify which server profile + database per request.

    - Supports unlimited SQL Server connections (named profiles)
    - Uses dedicated service accounts per server
    - API Key authentication with Admin/ReadOnly roles
    - Per-client rate limiting, DDL blocking, audit logging
    - Listens on all network interfaces

.NOTES
    Author : PMC Nexus Team
    Version: 3.0.0
    Requires: PowerShell 5.1+, .NET Framework 4.6.1+
#>

param(
    [string]$ConfigPath = "$PSScriptRoot\pmc-proxy-config.json",
    [switch]$Install,
    [switch]$AddServer,
    [switch]$GenerateKey,
    [switch]$TestConnection,
    [int]$Port = 0
)

# ---------------------------------------------
# SECTION 1: Configuration & Setup
# ---------------------------------------------

Add-Type -AssemblyName System.Web

$script:ServiceVersion = "3.0.0"
$script:DefaultPort    = 9480
$script:LogDir         = "$PSScriptRoot\proxy-logs"
$script:ConfigFile     = $ConfigPath
$script:Running        = $false
$script:Listener       = $null
$script:Config         = $null

# -- Encryption helpers --
function Protect-Text {
    param([string]$PlainText)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($PlainText)
    $encrypted = [System.Security.Cryptography.ProtectedData]::Protect(
        $bytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    return [Convert]::ToBase64String($encrypted)
}

function Unprotect-Text {
    param([string]$CipherBase64)
    $encrypted = [Convert]::FromBase64String($CipherBase64)
    $bytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
        $encrypted, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function New-ApiKey {
    $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
    $keyBytes = New-Object byte[] 32
    $rng.GetBytes($keyBytes)
    $rng.Dispose()
    $key = [Convert]::ToBase64String($keyBytes) -replace '[+/=]',''
    return $key.Substring(0, [Math]::Min(40, $key.Length))
}

# -- Logging --
function Write-ProxyLog {
    param([string]$Level, [string]$Message, [string]$ClientIP = "", [string]$Endpoint = "")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $entry = [PSCustomObject]@{ Timestamp=$timestamp; Level=$Level; ClientIP=$ClientIP; Endpoint=$Endpoint; Message=$Message; PID=$PID }
    $line = $entry | ConvertTo-Json -Compress
    $logFile = Join-Path $script:LogDir "proxy-$(Get-Date -Format 'yyyy-MM-dd').log"
    try { $line | Out-File -Append -FilePath $logFile -Encoding utf8 -ErrorAction Stop }
    catch { Write-Host "[$Level] $Message" -ForegroundColor $(if ($Level -eq 'ERROR') {'Red'} elseif ($Level -eq 'WARN') {'Yellow'} else {'Gray'}) }
}

# ---------------------------------------------
# SECTION 2: Setup Wizard - Add Server Profile
# ---------------------------------------------

# -- Connection String Parser (intelligent auto-detect) --
function Parse-ConnectionString {
    param([string]$ConnStr)

    Add-Type -AssemblyName System.Data

    $result = @{
        SqlServer       = ""
        DefaultDatabase = ""
        UseWindowsAuth  = $false
        SqlUser         = ""
        SqlPassword     = ""
        Parsed          = $false
        Error           = ""
    }

    # Clean up input - handle various formats
    $cleaned = $ConnStr.Trim()

    # Strip JDBC prefix: jdbc:sqlserver://host;...
    if ($cleaned -match '^jdbc:sqlserver://') {
        $cleaned = $cleaned -replace '^jdbc:sqlserver://',''
        # JDBC uses ; separators and may have host:port at the start
        if ($cleaned -match '^([^;]+)(.*)$') {
            $hostPart = $Matches[1]
            $rest = $Matches[2]
            # Convert JDBC port syntax host:port -> host,port
            $hostPart = $hostPart -replace ':',','
            $cleaned = "Data Source=$hostPart$rest"
            # Normalize JDBC keys to ADO.NET keys
            $cleaned = $cleaned -replace 'databaseName=','Initial Catalog=' -replace 'user=','User ID=' -replace 'password=','Password=' -replace 'integratedSecurity=true','Integrated Security=true'
        }
    }

    # Strip Entity Framework prefix: metadata=...provider connection string="..."
    if ($cleaned -match 'provider connection string="([^"]+)"') {
        $cleaned = $Matches[1]
        # EF uses &quot; sometimes
        $cleaned = $cleaned -replace '&quot;','"'
    }
    if ($cleaned -match "provider connection string='([^']+)'") {
        $cleaned = $Matches[1]
    }

    # Strip ODBC Driver prefix and normalize
    if ($cleaned -match 'Driver=') {
        $cleaned = $cleaned -replace 'Driver=[^;]*;?',''
        $cleaned = $cleaned -replace 'Server=','Data Source=' -replace 'Database=','Initial Catalog=' -replace 'Uid=','User ID=' -replace 'Pwd=','Password=' -replace 'Trusted_Connection=Yes','Integrated Security=true'
    }

    # Normalize common aliases
    $cleaned = $cleaned -replace '(?i)server\s*=','Data Source=' -replace '(?i)database\s*=','Initial Catalog=' -replace '(?i)uid\s*=','User ID=' -replace '(?i)pwd\s*=','Password=' -replace '(?i)trusted_connection\s*=\s*yes','Integrated Security=true' -replace '(?i)trusted_connection\s*=\s*true','Integrated Security=true'

    try {
        $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder($cleaned)

        $result.SqlServer       = $builder["Data Source"]
        $result.DefaultDatabase = $builder["Initial Catalog"]
        $result.UseWindowsAuth  = [bool]$builder["Integrated Security"]
        $result.SqlUser         = $builder["User ID"]
        $result.SqlPassword     = $builder["Password"]
        $result.Parsed          = $true

        # Fallback: if Data Source is empty, try Server
        if (-not $result.SqlServer) { $result.SqlServer = $builder["Server"] }
        if (-not $result.DefaultDatabase) { $result.DefaultDatabase = $builder["Database"] }

    } catch {
        $result.Error = $_.Exception.Message

        # Manual regex fallback for weird formats
        if ($cleaned -match '(?i)(?:Data Source|Server)\s*=\s*([^;]+)') { $result.SqlServer = $Matches[1].Trim() }
        if ($cleaned -match '(?i)(?:Initial Catalog|Database)\s*=\s*([^;]+)') { $result.DefaultDatabase = $Matches[1].Trim() }
        if ($cleaned -match '(?i)(?:User ID|Uid)\s*=\s*([^;]+)') { $result.SqlUser = $Matches[1].Trim() }
        if ($cleaned -match '(?i)(?:Password|Pwd)\s*=\s*([^;]+)') { $result.SqlPassword = $Matches[1].Trim() }
        if ($cleaned -match '(?i)(?:Integrated Security|Trusted_Connection)\s*=\s*(true|yes|sspi)') { $result.UseWindowsAuth = $true }

        if ($result.SqlServer) { $result.Parsed = $true; $result.Error = "" }
    }

    return $result
}

function Add-ServerProfile {
    Write-Host ""
    Write-Host "  -- Add SQL Server Profile --" -ForegroundColor Cyan
    Write-Host ""

    $profileName = Read-Host "  Profile name (short label, e.g. PROD, DEV, REPORT)"
    $profileName = $profileName.Trim().ToUpper()
    if (-not $profileName) { Write-Host "  Cancelled." -ForegroundColor Yellow; return $null }

    Write-Host ""
    Write-Host "  How do you want to add this server?" -ForegroundColor Gray
    Write-Host "    1. Paste a connection string (auto-detect everything)" -ForegroundColor Gray
    Write-Host "    2. Enter details manually" -ForegroundColor Gray
    $inputMode = Read-Host "  Select 1 or 2"

    $sqlServer = ""
    $defaultDb = ""
    $sqlUser = ""
    $sqlPassEncrypted = ""
    $useWindowsAuth = $false

    if ($inputMode -eq "1") {
        # -- INTELLIGENT: Parse connection string --
        Write-Host ""
        Write-Host "  Paste your connection string (any format - ADO.NET, ODBC, JDBC, EF):" -ForegroundColor Gray
        $connStr = Read-Host "  ConnectionString"

        if (-not $connStr) { Write-Host "  Cancelled." -ForegroundColor Yellow; return $null }

        $parsed = Parse-ConnectionString $connStr

        if (-not $parsed.Parsed -or -not $parsed.SqlServer) {
            Write-Host "  [!] Could not parse connection string. Falling back to manual." -ForegroundColor Yellow
            $inputMode = "2"
        } else {
            $sqlServer = $parsed.SqlServer
            $defaultDb = $parsed.DefaultDatabase
            $useWindowsAuth = $parsed.UseWindowsAuth

            Write-Host ""
            Write-Host "  Auto-detected:" -ForegroundColor Green
            Write-Host "    Server:   $sqlServer" -ForegroundColor White
            Write-Host "    Database: $defaultDb" -ForegroundColor White
            Write-Host "    Auth:     $(if ($useWindowsAuth) {'Windows Auth'} else {'SQL Login'})" -ForegroundColor White
            if (-not $useWindowsAuth -and $parsed.SqlUser) {
                Write-Host "    User:     $parsed.SqlUser" -ForegroundColor White
                Write-Host "    Password: ********" -ForegroundColor White
            }
            Write-Host ""

            # Let user correct if needed
            $confirm = Read-Host "  Looks correct? Y/N"
            if ($confirm -ne 'Y' -and $confirm -ne 'y') {
                # Allow overrides
                $override = Read-Host "  Server [$sqlServer]"
                if ($override) { $sqlServer = $override }
                $override = Read-Host "  Database [$defaultDb]"
                if ($override) { $defaultDb = $override }
            }

            if (-not $useWindowsAuth) {
                $sqlUser = $parsed.SqlUser
                if ($parsed.SqlPassword) {
                    $sqlPassEncrypted = Protect-Text $parsed.SqlPassword
                } else {
                    $sqlPass = Read-Host "  Password not found - enter it now" -AsSecureString
                    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sqlPass)
                    $plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
                    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
                    $sqlPassEncrypted = Protect-Text $plainPass
                    $plainPass = $null
                }
                if (-not $sqlUser) {
                    $sqlUser = Read-Host "  Username not found - enter it now"
                }
            }

            Write-Host "  -> Parsed and encrypted successfully" -ForegroundColor Green
        }
    }

    if ($inputMode -ne "1") {
        # -- MANUAL entry --
        $sqlServer = Read-Host "  SQL Server hostname or IP"
        $defaultDb = Read-Host "  Default database name"

        Write-Host "  Auth: 1=SQL Login  2=Windows Auth" -ForegroundColor Gray
        $authMode = Read-Host "  Select 1 or 2"

        if ($authMode -eq "2") {
            $useWindowsAuth = $true
            Write-Host "  -> Windows Auth selected" -ForegroundColor Green
        } else {
            $sqlUser = Read-Host "  SQL username"
            $sqlPass = Read-Host "  SQL password" -AsSecureString
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sqlPass)
            $plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            $sqlPassEncrypted = Protect-Text $plainPass
            $plainPass = $null
            Write-Host "  -> Password encrypted" -ForegroundColor Green
        }
    }

    $profile = @{
        SqlServer        = $sqlServer
        DefaultDatabase  = $defaultDb
        UseWindowsAuth   = $useWindowsAuth
        SqlUser          = $sqlUser
        SqlPasswordDPAPI = $sqlPassEncrypted
    }

    Write-Host "  -> Profile '$profileName' added: $sqlServer / $defaultDb" -ForegroundColor Green
    return @{ Name = $profileName; Profile = $profile }
}

function Initialize-ProxyConfig {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "    PMC SQL Proxy v3.0 -- Multi-Server Setup                " -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    # 1. Add server profiles
    Write-Host "[1/4] SQL Server Profiles" -ForegroundColor Yellow
    Write-Host "  Add one or more SQL Server connections." -ForegroundColor Gray
    Write-Host ""

    $servers = @{}
    $defaultProfile = ""

    $keepAdding = $true
    while ($keepAdding) {
        $result = Add-ServerProfile
        if ($result) {
            $servers[$result.Name] = $result.Profile
            if (-not $defaultProfile) { $defaultProfile = $result.Name }
        }

        Write-Host ""
        $more = Read-Host "  Add another server? Y/N"
        if ($more -ne 'Y' -and $more -ne 'y') { $keepAdding = $false }
    }

    if ($servers.Count -eq 0) {
        Write-Host "  No servers added. Exiting." -ForegroundColor Red
        return $null
    }

    Write-Host ""
    Write-Host "  Servers configured: $($servers.Count)" -ForegroundColor Green
    foreach ($name in $servers.Keys) {
        $s = $servers[$name]
        Write-Host "    [$name] $($s.SqlServer) / $($s.DefaultDatabase)" -ForegroundColor Gray
    }

    # 2. Port
    Write-Host ""
    Write-Host "[2/4] API Port" -ForegroundColor Yellow
    $portInput = Read-Host "  Port number - default $script:DefaultPort"
    $apiPort = if ($portInput -and $portInput -match '^\d+$') { [int]$portInput } else { $script:DefaultPort }

    # 3. API keys
    Write-Host ""
    Write-Host "[3/4] API Keys" -ForegroundColor Yellow
    $adminKey = New-ApiKey
    $readOnlyKey = New-ApiKey
    Write-Host "  -> Admin Key:     $adminKey" -ForegroundColor Green
    Write-Host "  -> Read-Only Key: $readOnlyKey" -ForegroundColor Green
    Write-Host ""
    Write-Host "  SAVE THESE KEYS NOW! They cannot be retrieved later." -ForegroundColor Red

    # 4. Rate limit
    Write-Host ""
    Write-Host "[4/4] Rate Limit" -ForegroundColor Yellow
    $rateInput = Read-Host "  Max requests/min per client - default 120"
    $rateLimit = if ($rateInput -and $rateInput -match '^\d+$') { [int]$rateInput } else { 120 }

    $config = @{
        Version              = $script:ServiceVersion
        CreatedAt            = (Get-Date -Format "o")
        Port                 = $apiPort
        DefaultServer        = $defaultProfile
        Servers              = $servers
        ConnectionTimeoutSec = 30
        CommandTimeoutSec    = 120
        ApiKeys              = @{
            Admin    = Protect-Text $adminKey
            ReadOnly = Protect-Text $readOnlyKey
        }
        BlockedProcedures    = @("xp_cmdshell", "xp_regread", "xp_regwrite", "sp_configure", "sp_addlogin", "sp_droplogin", "sp_addsrvrolemember")
        RateLimitPerMinute   = $rateLimit
        AllowedOrigins       = @("*")
        LogRetentionDays     = 30
    }

    $config | ConvertTo-Json -Depth 5 | Set-Content -Path $script:ConfigFile -Encoding UTF8
    Write-Host ""
    Write-Host "[OK] Config saved: $script:ConfigFile" -ForegroundColor Green
    return $config
}

# ---------------------------------------------
# SECTION 3: SQL Connection Factory
# ---------------------------------------------

function Get-ServerProfile {
    param([hashtable]$cfg, [string]$ServerName)

    if (-not $ServerName) { $ServerName = $cfg.DefaultServer }
    $ServerName = $ServerName.Trim().ToUpper()

    if ($cfg.Servers.ContainsKey($ServerName)) {
        return $cfg.Servers[$ServerName]
    }

    # Try case-insensitive match
    foreach ($key in $cfg.Servers.Keys) {
        if ($key.ToUpper() -eq $ServerName) {
            return $cfg.Servers[$key]
        }
    }

    return $null
}

function New-SqlConnection {
    param([hashtable]$serverProfile, [string]$Database = "", [int]$Timeout = 30)

    Add-Type -AssemblyName System.Data
    $dbName = if ($Database) { $Database } else { $serverProfile.DefaultDatabase }

    $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $builder["Data Source"]      = $serverProfile.SqlServer
    $builder["Initial Catalog"]  = $dbName
    $builder["Connect Timeout"]  = $Timeout
    $builder["Application Name"] = ".Net SqlClient Data Provider"
    $builder["Workstation ID"]   = "."

    if ($serverProfile.UseWindowsAuth) {
        $builder["Integrated Security"] = $true
    } else {
        $builder["User ID"]  = $serverProfile.SqlUser
        $builder["Password"] = Unprotect-Text $serverProfile.SqlPasswordDPAPI
        $builder["Integrated Security"] = $false
    }

    return New-Object System.Data.SqlClient.SqlConnection($builder.ConnectionString)
}

function Invoke-SqlOperation {
    param(
        [hashtable]$cfg,
        [string]$ServerName,
        [string]$Database,
        [string]$CommandText,
        [string]$CommandType,  # "StoredProcedure", "Text", "NonQuery"
        [hashtable]$Parameters = @{}
    )

    $profile = Get-ServerProfile $cfg $ServerName
    if (-not $profile) {
        return @{ Success=$false; Data=@(); RowCount=0; RowsAffected=0; Error="Server profile '$ServerName' not found. Available: $($cfg.Servers.Keys -join ', ')"; Messages=@() }
    }

    $conn = $null; $cmd = $null; $reader = $null
    $result = @{ Success=$false; Data=@(); RowCount=0; RowsAffected=0; Error=""; Messages=@() }
    $msgList = [System.Collections.Generic.List[string]]::new()

    try {
        $conn = New-SqlConnection $profile $Database $cfg.ConnectionTimeoutSec
        $conn.add_InfoMessage({ param($s,$e); $msgList.Add($e.Message) })
        $conn.FireInfoMessageEventOnUserErrors = $true
        $conn.Open()

        $cmd = $conn.CreateCommand()
        $cmd.CommandTimeout = $cfg.CommandTimeoutSec
        $cmd.CommandText = $CommandText

        if ($CommandType -eq "StoredProcedure") {
            $cmd.CommandType = [System.Data.CommandType]::StoredProcedure
        } else {
            $cmd.CommandType = [System.Data.CommandType]::Text
        }

        foreach ($key in $Parameters.Keys) {
            $pn = if ($key.StartsWith("@")) { $key } else { "@$key" }
            $val = $Parameters[$key]
            if ($null -eq $val) { [void]$cmd.Parameters.AddWithValue($pn, [DBNull]::Value) }
            else { [void]$cmd.Parameters.AddWithValue($pn, $val) }
        }

        if ($CommandType -eq "NonQuery") {
            $result.RowsAffected = $cmd.ExecuteNonQuery()
            $result.Success = $true
        } else {
            $reader = $cmd.ExecuteReader()
            $allSets = @()
            do {
                $rows = @()
                while ($reader.Read()) {
                    $row = [ordered]@{}
                    for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                        $cn = $reader.GetName($i)
                        $cv = if ($reader.IsDBNull($i)) { $null } else { $reader.GetValue($i) }
                        if ($cv -is [datetime])  { $cv = $cv.ToString("yyyy-MM-ddTHH:mm:ss") }
                        elseif ($cv -is [byte[]])  { $cv = [Convert]::ToBase64String($cv) }
                        elseif ($cv -is [guid])    { $cv = $cv.ToString() }
                        $row[$cn] = $cv
                    }
                    $rows += [PSCustomObject]$row
                }
                if ($rows.Count -gt 0) { $allSets += ,@($rows) }
            } while ($reader.NextResult())

            $result.Success = $true
            if ($allSets.Count -eq 1) { $result.Data = $allSets[0]; $result.RowCount = $allSets[0].Count }
            elseif ($allSets.Count -gt 1) { $result.Data = $allSets; $result.RowCount = ($allSets | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum }
            else { $result.Data = @(); $result.RowCount = 0 }
        }

        $result.Messages = @($msgList)

    } catch {
        $result.Error = $_.Exception.Message
    } finally {
        if ($reader) { try { $reader.Close(); $reader.Dispose() } catch {} }
        if ($cmd)    { try { $cmd.Dispose() } catch {} }
        if ($conn)   { try { $conn.Close(); $conn.Dispose() } catch {} }
    }

    return $result
}

# ---------------------------------------------
# SECTION 4: Rate Limiter
# ---------------------------------------------

$script:RateTracker = @{}
$script:LastCleanup = [datetime]::Now

function Test-RateLimit {
    param([string]$ClientIP, [int]$MaxPerMinute)
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $windowStart = $now - 60
    if (-not $script:RateTracker.ContainsKey($ClientIP)) {
        $script:RateTracker[$ClientIP] = [System.Collections.Generic.List[long]]::new()
    }
    $pruned = [System.Collections.Generic.List[long]]::new()
    foreach ($ts in $script:RateTracker[$ClientIP]) { if ($ts -ge $windowStart) { $pruned.Add($ts) } }
    $pruned.Add($now)
    $script:RateTracker[$ClientIP] = $pruned
    return ($pruned.Count -le $MaxPerMinute)
}

function Invoke-RateCleanup {
    if (([datetime]::Now - $script:LastCleanup).TotalMinutes -ge 5) {
        $cutoff = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 120
        $remove = @()
        foreach ($ip in $script:RateTracker.Keys) {
            $any = $script:RateTracker[$ip] | Where-Object { $_ -ge $cutoff }
            if (-not $any) { $remove += $ip }
        }
        foreach ($k in $remove) { $script:RateTracker.Remove($k) }
        $script:LastCleanup = [datetime]::Now
    }
}

# ---------------------------------------------
# SECTION 5: Authentication
# ---------------------------------------------

function Test-ApiKey {
    param([string]$ProvidedKey, [hashtable]$cfg)
    if (-not $ProvidedKey) { return $null }
    try { if ($ProvidedKey -eq (Unprotect-Text $cfg.ApiKeys.Admin)) { return "Admin" } } catch {}
    try { if ($ProvidedKey -eq (Unprotect-Text $cfg.ApiKeys.ReadOnly)) { return "ReadOnly" } } catch {}
    return $null
}

function Test-AllowedOrigin {
    param([string]$ClientIP, [hashtable]$cfg)
    $o = $cfg.AllowedOrigins
    if (-not $o -or $o.Count -eq 0 -or $o -contains "*") { return $true }
    if ($o -contains $ClientIP) { return $true }
    if (@("127.0.0.1","::1") -contains $ClientIP -and $o -contains "localhost") { return $true }
    return $false
}

function Test-BlockedProcedure {
    param([string]$ProcName, [hashtable]$cfg)
    $lp = $ProcName.ToLower()
    foreach ($b in $cfg.BlockedProcedures) {
        if ($lp -eq $b.ToLower() -or $lp.EndsWith(".$($b.ToLower())")) { return $true }
    }
    return $false
}

# ---------------------------------------------
# SECTION 6: JSON Response Helper
# ---------------------------------------------

function Send-JsonResponse {
    param([System.Net.HttpListenerResponse]$Response, [int]$StatusCode, [object]$Body)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = "application/json; charset=utf-8"
    $Response.Headers.Add("X-Powered-By", "PMC-Proxy/$script:ServiceVersion")
    $Response.Headers.Add("X-Content-Type-Options", "nosniff")
    $Response.Headers.Add("Access-Control-Allow-Origin", "*")
    $Response.Headers.Add("Access-Control-Allow-Headers", "Content-Type, X-API-Key")
    $Response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    $json = $Body | ConvertTo-Json -Depth 10 -Compress
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Response.ContentLength64 = $buffer.Length
    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Response.OutputStream.Close()
}

function Read-RequestBody {
    param([System.Net.HttpListenerRequest]$Request)
    $sr = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
    $text = $sr.ReadToEnd()
    $sr.Close()
    $Request.InputStream.Close()
    return $text
}

# -- DDL check --
$script:BlockedKeywords = @("DROP ","TRUNCATE ","GRANT ","REVOKE ","DENY ","xp_","sp_configure","SHUTDOWN","BACKUP ","RESTORE ")

function Test-DangerousQuery {
    param([string]$Query)
    $upper = $Query.ToUpper()
    foreach ($b in $script:BlockedKeywords) {
        if ($upper.Contains($b.ToUpper())) { return $b.Trim() }
    }
    return $null
}

# ---------------------------------------------
# SECTION 7: HTTP Server & Router
# ---------------------------------------------

function Start-ProxyServer {
    param([hashtable]$cfg)

    $port = if ($Port -gt 0) { $Port } else { $cfg.Port }
    if (-not (Test-Path $script:LogDir)) { New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null }

    $script:Listener = [System.Net.HttpListener]::new()
    $script:Listener.Prefixes.Add("http://+:$port/")

    try {
        $script:Listener.Start()
    } catch {
        Write-Host "  [!] Cannot bind to all interfaces. Trying localhost..." -ForegroundColor Yellow
        Write-Host "  [!] For network access, run as Admin or:" -ForegroundColor Yellow
        Write-Host "      netsh http add urlacl url=http://+:$port/ user=Everyone" -ForegroundColor Gray
        $script:Listener = [System.Net.HttpListener]::new()
        $script:Listener.Prefixes.Add("http://localhost:$port/")
        $script:Listener.Prefixes.Add("http://127.0.0.1:$port/")
        $script:Listener.Start()
    }

    $script:Running = $true

    # Show server list
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "    PMC SQL Proxy v3.0 -- MULTI-SERVER MODE                 " -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "  Listening:      http://+:$port/" -ForegroundColor Green
    Write-Host "  Default Server: $($cfg.DefaultServer)" -ForegroundColor Green
    Write-Host "  Rate Limit:     $($cfg.RateLimitPerMinute) req/min" -ForegroundColor Green
    Write-Host "------------------------------------------------------------" -ForegroundColor Green
    Write-Host "  Connected Servers:" -ForegroundColor Green
    foreach ($name in $cfg.Servers.Keys) {
        $s = $cfg.Servers[$name]
        $authType = if ($s.UseWindowsAuth) { "WinAuth" } else { "SQL:$($s.SqlUser)" }
        $marker = if ($name -eq $cfg.DefaultServer) { " [DEFAULT]" } else { "" }
        Write-Host "    [$name] $($s.SqlServer) / $($s.DefaultDatabase) ($authType)$marker" -ForegroundColor Green
    }
    Write-Host "------------------------------------------------------------" -ForegroundColor Green
    Write-Host "  Ctrl+C to stop" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""

    Write-ProxyLog "INFO" "Service v3.0 started on port $port with $($cfg.Servers.Count) server(s)"

    try {
        while ($script:Running) {
            $task = $script:Listener.GetContextAsync()
            while (-not $task.AsyncWaitHandle.WaitOne(500)) {
                if (-not $script:Running) { return }
                Invoke-RateCleanup
            }

            $ctx = $task.GetAwaiter().GetResult()
            $req = $ctx.Request; $res = $ctx.Response
            $clientIP = $req.RemoteEndPoint.Address.ToString()
            $method = $req.HttpMethod; $path = $req.Url.AbsolutePath.TrimEnd('/')

            try {
                # CORS preflight
                if ($method -eq "OPTIONS") {
                    $res.StatusCode = 204
                    $res.Headers.Add("Access-Control-Allow-Origin","*")
                    $res.Headers.Add("Access-Control-Allow-Headers","Content-Type, X-API-Key")
                    $res.Headers.Add("Access-Control-Allow-Methods","GET, POST, OPTIONS")
                    $res.ContentLength64 = 0; $res.OutputStream.Close()
                    continue
                }

                # IP check
                if (-not (Test-AllowedOrigin $clientIP $cfg)) {
                    Send-JsonResponse $res 403 @{ error="Forbidden"; message="IP not allowed." }
                    continue
                }

                # Rate limit
                if (-not (Test-RateLimit $clientIP $cfg.RateLimitPerMinute)) {
                    Send-JsonResponse $res 429 @{ error="Too Many Requests" }
                    continue
                }

                # --- HEALTH (no auth) ---
                if ($path -eq "/health" -or $path -eq "/api/health") {
                    $serverList = @()
                    foreach ($n in $cfg.Servers.Keys) {
                        $serverList += "$n=$($cfg.Servers[$n].SqlServer)"
                    }
                    Send-JsonResponse $res 200 @{
                        status="healthy"; version=$script:ServiceVersion; mode="multi-server"
                        default_server=$cfg.DefaultServer; servers=$serverList
                        uptime_min=[Math]::Round(([datetime]::Now - $script:StartTime).TotalMinutes,1)
                    }
                    continue
                }

                # --- AUTH ---
                $apiKey = $req.Headers["X-API-Key"]
                if (-not $apiKey) { $apiKey = $req.QueryString["apiKey"] }
                $role = Test-ApiKey $apiKey $cfg
                if (-not $role) {
                    Write-ProxyLog "WARN" "Auth failed" $clientIP $path
                    Send-JsonResponse $res 401 @{ error="Unauthorized"; message="Invalid API key." }
                    continue
                }

                # --- LIST SERVERS ---
                if ($path -eq "/api/servers" -and $method -eq "GET") {
                    $list = @()
                    foreach ($n in $cfg.Servers.Keys) {
                        $s = $cfg.Servers[$n]
                        $list += @{ name=$n; host=$s.SqlServer; default_db=$s.DefaultDatabase; auth=if($s.UseWindowsAuth){"Windows"}else{"SQL"} }
                    }
                    Send-JsonResponse $res 200 @{ servers=$list; count=$list.Count; default=$cfg.DefaultServer }
                    continue
                }

                # --- LIST DATABASES (on a specific server) ---
                if ($path -eq "/api/databases" -and $method -eq "GET") {
                    $srvParam = $req.QueryString["server"]
                    $dbResult = Invoke-SqlOperation $cfg $srvParam "master" "SELECT name FROM sys.databases WHERE state_desc='ONLINE' AND name NOT IN ('tempdb') ORDER BY name" "Text"
                    if ($dbResult.Success) {
                        $dbNames = $dbResult.Data | ForEach-Object { $_.name }
                        Send-JsonResponse $res 200 @{ server=if($srvParam){$srvParam}else{$cfg.DefaultServer}; databases=$dbNames; count=$dbNames.Count }
                    } else {
                        Send-JsonResponse $res 500 @{ error=$dbResult.Error }
                    }
                    continue
                }

                # --- EXECUTE STORED PROCEDURE ---
                if ($path -eq "/api/execute" -and $method -eq "POST") {
                    $bodyText = Read-RequestBody $req
                    $body = $null
                    try { $body = $bodyText | ConvertFrom-Json } catch {
                        Send-JsonResponse $res 400 @{ error="Bad Request"; message="Invalid JSON." }; continue
                    }

                    $procName = $body.procedure
                    $server   = if ($body.server) { $body.server } else { "" }
                    $database = if ($body.database) { $body.database } else { "" }

                    if (-not $procName) {
                        Send-JsonResponse $res 400 @{ error="Bad Request"; message="Missing 'procedure'." }; continue
                    }

                    if (Test-BlockedProcedure $procName $cfg) {
                        Write-ProxyLog "WARN" "BLOCKED: $procName" $clientIP $path
                        Send-JsonResponse $res 403 @{ error="Forbidden"; message="'$procName' is blocked." }; continue
                    }

                    if ($role -eq "ReadOnly") {
                        $writeOps = @("Save","Update","Insert","Delete","Approve","Discard","Drop","Create","Alter","Truncate")
                        foreach ($op in $writeOps) {
                            if ($procName -match $op) {
                                Send-JsonResponse $res 403 @{ error="Forbidden"; message="ReadOnly key cannot run write procedures." }
                                $procName = $null; break
                            }
                        }
                        if (-not $procName) { continue }
                    }

                    $params = @{}
                    if ($body.parameters -and $body.parameters -is [PSCustomObject]) {
                        $body.parameters.PSObject.Properties | ForEach-Object { $params[$_.Name] = $_.Value }
                    }

                    $srvLabel = if ($server) { $server } else { $cfg.DefaultServer }
                    $dbLabel  = if ($database) { $database } else { "default" }
                    Write-ProxyLog "AUDIT" "EXEC [$srvLabel/$dbLabel].$procName ($($params.Count) params) role=$role" $clientIP $path

                    $sw = [System.Diagnostics.Stopwatch]::StartNew()
                    $result = Invoke-SqlOperation $cfg $server $database $procName "StoredProcedure" $params
                    $sw.Stop()

                    if ($result.Success) {
                        Write-ProxyLog "INFO" "OK: $procName -> $($result.RowCount) rows ($($sw.ElapsedMilliseconds)ms)" $clientIP $path
                        Send-JsonResponse $res 200 @{
                            success=$true; server=$srvLabel; database=$dbLabel; procedure=$procName
                            rowCount=$result.RowCount; data=$result.Data; messages=$result.Messages
                            elapsed_ms=$sw.ElapsedMilliseconds
                        }
                    } else {
                        Write-ProxyLog "ERROR" "FAIL: $procName -> $($result.Error)" $clientIP $path
                        Send-JsonResponse $res 500 @{ success=$false; server=$srvLabel; procedure=$procName; error=$result.Error }
                    }
                    continue
                }

                # --- RAW QUERY (Admin) ---
                if ($path -eq "/api/query" -and $method -eq "POST") {
                    if ($role -ne "Admin") { Send-JsonResponse $res 403 @{ error="Forbidden" }; continue }

                    $bodyText = Read-RequestBody $req
                    $body = $null
                    try { $body = $bodyText | ConvertFrom-Json } catch {
                        Send-JsonResponse $res 400 @{ error="Bad Request" }; continue
                    }
                    if (-not $body.query) { Send-JsonResponse $res 400 @{ error="Missing 'query'." }; continue }

                    $blocked = Test-DangerousQuery $body.query
                    if ($blocked) {
                        Send-JsonResponse $res 403 @{ error="Forbidden"; message="Blocked: $blocked" }; continue
                    }

                    $server   = if ($body.server) { $body.server } else { "" }
                    $database = if ($body.database) { $body.database } else { "" }
                    $params = @{}
                    if ($body.parameters -and $body.parameters -is [PSCustomObject]) {
                        $body.parameters.PSObject.Properties | ForEach-Object { $params[$_.Name] = $_.Value }
                    }

                    $srvLabel = if ($server) { $server } else { $cfg.DefaultServer }
                    Write-ProxyLog "AUDIT" "QUERY [$srvLabel]: $($body.query.Substring(0,[Math]::Min(150,$body.query.Length)))" $clientIP $path

                    $sw = [System.Diagnostics.Stopwatch]::StartNew()
                    $result = Invoke-SqlOperation $cfg $server $database $body.query "Text" $params
                    $sw.Stop()

                    if ($result.Success) {
                        Send-JsonResponse $res 200 @{ success=$true; server=$srvLabel; rowCount=$result.RowCount; data=$result.Data; elapsed_ms=$sw.ElapsedMilliseconds }
                    } else {
                        Send-JsonResponse $res 500 @{ success=$false; error=$result.Error }
                    }
                    continue
                }

                # --- NON-QUERY (Admin) ---
                if ($path -eq "/api/execute-sql" -and $method -eq "POST") {
                    if ($role -ne "Admin") { Send-JsonResponse $res 403 @{ error="Forbidden" }; continue }

                    $bodyText = Read-RequestBody $req
                    $body = $null
                    try { $body = $bodyText | ConvertFrom-Json } catch {
                        Send-JsonResponse $res 400 @{ error="Bad Request" }; continue
                    }
                    if (-not $body.sql) { Send-JsonResponse $res 400 @{ error="Missing 'sql'." }; continue }

                    $blocked = Test-DangerousQuery $body.sql
                    if ($blocked) { Send-JsonResponse $res 403 @{ error="Forbidden"; message="Blocked: $blocked" }; continue }

                    $server   = if ($body.server) { $body.server } else { "" }
                    $database = if ($body.database) { $body.database } else { "" }
                    $params = @{}
                    if ($body.parameters -and $body.parameters -is [PSCustomObject]) {
                        $body.parameters.PSObject.Properties | ForEach-Object { $params[$_.Name] = $_.Value }
                    }

                    $srvLabel = if ($server) { $server } else { $cfg.DefaultServer }
                    Write-ProxyLog "AUDIT" "EXEC-SQL [$srvLabel]: $($body.sql.Substring(0,[Math]::Min(150,$body.sql.Length)))" $clientIP $path

                    $sw = [System.Diagnostics.Stopwatch]::StartNew()
                    $result = Invoke-SqlOperation $cfg $server $database $body.sql "NonQuery" $params
                    $sw.Stop()

                    if ($result.Success) {
                        Send-JsonResponse $res 200 @{ success=$true; server=$srvLabel; rowsAffected=$result.RowsAffected; elapsed_ms=$sw.ElapsedMilliseconds }
                    } else {
                        Send-JsonResponse $res 500 @{ success=$false; error=$result.Error }
                    }
                    continue
                }

                # --- STATUS (Admin) ---
                if ($path -eq "/api/status" -and $method -eq "GET") {
                    if ($role -ne "Admin") { Send-JsonResponse $res 403 @{ error="Forbidden" }; continue }
                    $up = [datetime]::Now - $script:StartTime
                    Send-JsonResponse $res 200 @{
                        status="running"; version=$script:ServiceVersion; mode="multi-server"
                        uptime_hours=[Math]::Round($up.TotalHours,2)
                        server_count=$cfg.Servers.Count; default_server=$cfg.DefaultServer
                        rate_limit=$cfg.RateLimitPerMinute; active_clients=$script:RateTracker.Count
                    }
                    continue
                }

                # --- LOGS (Admin) ---
                if ($path -eq "/api/logs" -and $method -eq "GET") {
                    if ($role -ne "Admin") { Send-JsonResponse $res 403 @{ error="Forbidden" }; continue }
                    $nP = $req.QueryString["n"]
                    $tailN = if ($nP -and $nP -match '^\d+$') { [Math]::Min([int]$nP, 500) } else { 50 }
                    $lf = Join-Path $script:LogDir "proxy-$(Get-Date -Format 'yyyy-MM-dd').log"
                    $entries = @()
                    if (Test-Path $lf) {
                        $entries = Get-Content $lf -Tail $tailN | ForEach-Object { try { $_ | ConvertFrom-Json } catch { @{raw=$_} } }
                    }
                    Send-JsonResponse $res 200 @{ count=$entries.Count; entries=$entries }
                    continue
                }

                # --- 404 ---
                Send-JsonResponse $res 404 @{
                    error="Not Found"; message="$method $path"
                    routes=@(
                        "GET  /health        - Health check",
                        "GET  /api/servers   - List all server profiles",
                        "GET  /api/databases?server=X - List databases",
                        "POST /api/execute   - Run stored procedure",
                        "POST /api/query     - Run SELECT (Admin)",
                        "POST /api/execute-sql - Run INSERT/UPDATE (Admin)",
                        "GET  /api/status    - Service status (Admin)",
                        "GET  /api/logs      - Audit logs (Admin)"
                    )
                }
            } catch {
                Write-ProxyLog "ERROR" $_.Exception.Message $clientIP $path
                try { Send-JsonResponse $res 500 @{ error="Internal Server Error"; message=$_.Exception.Message } } catch {}
            }
        }
    } finally {
        if ($script:Listener) { $script:Listener.Stop(); $script:Listener.Close() }
        Write-ProxyLog "INFO" "Service stopped"
        Write-Host "`n[STOPPED] PMC SQL Proxy stopped." -ForegroundColor Red
    }
}

# ---------------------------------------------
# SECTION 8: Entry Point
# ---------------------------------------------

try { [Console]::TreatControlCAsInput = $false } catch {}
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { $script:Running = $false } -ErrorAction SilentlyContinue

Add-Type -AssemblyName System.Security

if ($GenerateKey) {
    Write-Host "`n  New API Key: $(New-ApiKey)`n" -ForegroundColor Green; return
}

# Add a server to existing config
if ($AddServer -and (Test-Path $script:ConfigFile)) {
    $raw = Get-Content $script:ConfigFile -Raw | ConvertFrom-Json
    $cfg = @{}
    $raw.PSObject.Properties | ForEach-Object {
        if ($_.Value -is [PSCustomObject]) {
            $inner = @{}
            $_.Value.PSObject.Properties | ForEach-Object {
                if ($_.Value -is [PSCustomObject]) {
                    $inner2 = @{}; $_.Value.PSObject.Properties | ForEach-Object { $inner2[$_.Name] = $_.Value }
                    $inner[$_.Name] = $inner2
                } else { $inner[$_.Name] = $_.Value }
            }
            $cfg[$_.Name] = $inner
        } elseif ($_.Value -is [System.Object[]]) { $cfg[$_.Name] = @($_.Value) }
        else { $cfg[$_.Name] = $_.Value }
    }

    $result = Add-ServerProfile
    if ($result) {
        $cfg.Servers[$result.Name] = $result.Profile
        $cfg | ConvertTo-Json -Depth 5 | Set-Content -Path $script:ConfigFile -Encoding UTF8
        Write-Host "`n  [OK] Server '$($result.Name)' added. Total: $($cfg.Servers.Count) servers.`n" -ForegroundColor Green
    }
    return
}

if ($Install -or -not (Test-Path $script:ConfigFile)) {
    $script:Config = Initialize-ProxyConfig
    if (-not $script:Config) { return }
    Write-Host ""
    $sn = Read-Host "Start the proxy now? Y/N"
    if ($sn -ne 'Y' -and $sn -ne 'y') { return }
} else {
    $raw = Get-Content $script:ConfigFile -Raw | ConvertFrom-Json
    $script:Config = @{}
    $raw.PSObject.Properties | ForEach-Object {
        if ($_.Value -is [PSCustomObject]) {
            $inner = @{}
            $_.Value.PSObject.Properties | ForEach-Object {
                if ($_.Value -is [PSCustomObject]) {
                    $inner2 = @{}; $_.Value.PSObject.Properties | ForEach-Object { $inner2[$_.Name] = $_.Value }
                    $inner[$_.Name] = $inner2
                } else { $inner[$_.Name] = $_.Value }
            }
            $script:Config[$_.Name] = $inner
        } elseif ($_.Value -is [System.Object[]]) { $script:Config[$_.Name] = @($_.Value) }
        else { $script:Config[$_.Name] = $_.Value }
    }
}

if ($TestConnection) {
    Write-Host "`n  Testing all server connections..." -ForegroundColor Yellow
    foreach ($name in $script:Config.Servers.Keys) {
        $p = $script:Config.Servers[$name]
        try {
            $c = New-SqlConnection $p "" $script:Config.ConnectionTimeoutSec
            $c.Open(); $c.Close(); $c.Dispose()
            Write-Host "  [OK] $name -> $($p.SqlServer) / $($p.DefaultDatabase)" -ForegroundColor Green
        } catch {
            Write-Host "  [FAIL] $name -> $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Write-Host ""; return
}

$script:StartTime = [datetime]::Now
Start-ProxyServer $script:Config
