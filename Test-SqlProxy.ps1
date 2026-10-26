<#
.SYNOPSIS
    PMC SQL Proxy - Quick Test Script
.DESCRIPTION
    Tests if the SQL Proxy service is running and responds correctly.
    Run this AFTER starting the proxy service.
#>

param(
    [string]$BaseUrl = "http://localhost:9480",
    [string]$ApiKey  = ""
)

$passed = 0
$failed = 0

function Test-Step {
    param([string]$Name, [scriptblock]$Action)
    Write-Host ""
    Write-Host "  TEST: $Name" -ForegroundColor Yellow
    try {
        $result = & $Action
        if ($result) {
            Write-Host "  [PASS] $Name" -ForegroundColor Green
            $script:passed++
        } else {
            Write-Host "  [FAIL] $Name" -ForegroundColor Red
            $script:failed++
        }
    } catch {
        Write-Host "  [FAIL] $Name - $($_.Exception.Message)" -ForegroundColor Red
        $script:failed++
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "    PMC SQL Proxy - Connection Test Suite                    " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Target: $BaseUrl" -ForegroundColor Gray

# -----------------------------------------------
# TEST 1: Health Check (no auth needed)
# -----------------------------------------------
Test-Step "Health Check - GET /health" {
    $resp = Invoke-WebRequest -Uri "$BaseUrl/health" -UseBasicParsing -TimeoutSec 5
    $data = $resp.Content | ConvertFrom-Json
    Write-Host "    Status:     $($data.status)" -ForegroundColor Gray
    Write-Host "    Version:    $($data.version)" -ForegroundColor Gray
    Write-Host "    SQL Server: $($data.sql_server)" -ForegroundColor Gray
    Write-Host "    Default DB: $($data.default_db)" -ForegroundColor Gray
    Write-Host "    Mode:       $($data.mode)" -ForegroundColor Gray
    Write-Host "    Uptime:     $($data.uptime_min) minutes" -ForegroundColor Gray
    return ($data.status -eq "healthy")
}

# -----------------------------------------------
# TEST 2: 404 on unknown route
# -----------------------------------------------
Test-Step "404 Response - GET /unknown" {
    try {
        $resp = Invoke-WebRequest -Uri "$BaseUrl/unknown" -UseBasicParsing -TimeoutSec 5
        return $false  # Should have thrown
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        Write-Host "    Status Code: $statusCode (expected 404)" -ForegroundColor Gray
        return ($statusCode -eq 404)
    }
}

# -----------------------------------------------
# TEST 3: Auth rejection (no key)
# -----------------------------------------------
Test-Step "Auth Rejection - No API Key" {
    try {
        $resp = Invoke-WebRequest -Uri "$BaseUrl/api/status" -UseBasicParsing -TimeoutSec 5
        return $false
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        Write-Host "    Status Code: $statusCode (expected 401)" -ForegroundColor Gray
        return ($statusCode -eq 401)
    }
}

# -----------------------------------------------
# TEST 4: Auth rejection (bad key)
# -----------------------------------------------
Test-Step "Auth Rejection - Bad API Key" {
    try {
        $headers = @{ "X-API-Key" = "invalid-key-12345" }
        $resp = Invoke-WebRequest -Uri "$BaseUrl/api/status" -Headers $headers -UseBasicParsing -TimeoutSec 5
        return $false
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        Write-Host "    Status Code: $statusCode (expected 401)" -ForegroundColor Gray
        return ($statusCode -eq 401)
    }
}

# -----------------------------------------------
# TEST 5+: Authenticated tests (only if ApiKey provided)
# -----------------------------------------------
if ($ApiKey) {
    $headers = @{
        "X-API-Key"    = $ApiKey
        "Content-Type" = "application/json"
    }

    # TEST 5: List databases
    Test-Step "List Databases - GET /api/databases" {
        $resp = Invoke-WebRequest -Uri "$BaseUrl/api/databases" -Headers $headers -UseBasicParsing -TimeoutSec 10
        $data = $resp.Content | ConvertFrom-Json
        Write-Host "    Found $($data.count) databases:" -ForegroundColor Gray
        foreach ($db in $data.databases) {
            Write-Host "      - $db" -ForegroundColor Gray
        }
        return ($data.count -gt 0)
    }

    # TEST 6: Service status
    Test-Step "Service Status - GET /api/status" {
        $resp = Invoke-WebRequest -Uri "$BaseUrl/api/status" -Headers $headers -UseBasicParsing -TimeoutSec 5
        $data = $resp.Content | ConvertFrom-Json
        Write-Host "    Version:    $($data.version)" -ForegroundColor Gray
        Write-Host "    Mode:       $($data.mode)" -ForegroundColor Gray
        Write-Host "    Uptime:     $($data.uptime_hours) hours" -ForegroundColor Gray
        Write-Host "    Auth Mode:  $($data.auth_mode)" -ForegroundColor Gray
        Write-Host "    Rate Limit: $($data.rate_limit) req/min" -ForegroundColor Gray
        Write-Host "    Clients:    $($data.active_clients)" -ForegroundColor Gray
        return ($data.status -eq "running")
    }

    # TEST 7: Execute a simple query
    Test-Step "Simple Query - SELECT @@VERSION" {
        $body = @{ query = "SELECT @@VERSION AS SqlVersion, GETDATE() AS ServerTime, DB_NAME() AS CurrentDB" } | ConvertTo-Json
        $resp = Invoke-WebRequest -Uri "$BaseUrl/api/query" -Method POST -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing -TimeoutSec 10
        $data = $resp.Content | ConvertFrom-Json
        if ($data.success) {
            Write-Host "    SQL Version: $($data.data[0].SqlVersion.Substring(0, [Math]::Min(80, $data.data[0].SqlVersion.Length)))..." -ForegroundColor Gray
            Write-Host "    Server Time: $($data.data[0].ServerTime)" -ForegroundColor Gray
            Write-Host "    Current DB:  $($data.data[0].CurrentDB)" -ForegroundColor Gray
            Write-Host "    Elapsed:     $($data.elapsed_ms) ms" -ForegroundColor Gray
        }
        return $data.success
    }

    # TEST 8: DDL blocking
    Test-Step "DDL Blocking - DROP TABLE should be rejected" {
        try {
            $body = @{ query = "DROP TABLE TestTable" } | ConvertTo-Json
            $resp = Invoke-WebRequest -Uri "$BaseUrl/api/query" -Method POST -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing -TimeoutSec 5
            return $false  # Should have been blocked
        } catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            Write-Host "    Status Code: $statusCode (expected 403 - blocked)" -ForegroundColor Gray
            return ($statusCode -eq 403)
        }
    }

    # TEST 9: View audit logs
    Test-Step "Audit Logs - GET /api/logs" {
        $resp = Invoke-WebRequest -Uri "$BaseUrl/api/logs?n=5" -Headers $headers -UseBasicParsing -TimeoutSec 5
        $data = $resp.Content | ConvertFrom-Json
        Write-Host "    Log entries: $($data.count)" -ForegroundColor Gray
        if ($data.entries -and $data.entries.Count -gt 0) {
            $last = $data.entries[-1]
            Write-Host "    Latest: [$($last.Level)] $($last.Message)" -ForegroundColor Gray
        }
        return ($data.count -ge 0)
    }

} else {
    Write-Host ""
    Write-Host "  --------------------------------------------------------" -ForegroundColor Gray
    Write-Host "  Skipping authenticated tests (no API key provided)." -ForegroundColor Yellow
    Write-Host "  To run full tests, use:" -ForegroundColor Yellow
    Write-Host "    .\Test-SqlProxy.ps1 -ApiKey 'YOUR_ADMIN_KEY'" -ForegroundColor White
    Write-Host "  --------------------------------------------------------" -ForegroundColor Gray
}

# -----------------------------------------------
# Summary
# -----------------------------------------------
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  RESULTS: $passed PASSED / $failed FAILED" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

if ($failed -eq 0) {
    Write-Host "  All tests passed! The proxy service is working correctly." -ForegroundColor Green
} else {
    Write-Host "  Some tests failed. Check the service is running:" -ForegroundColor Red
    Write-Host "    powershell -File PMC-SqlProxy-Service.ps1" -ForegroundColor Gray
}
Write-Host ""
