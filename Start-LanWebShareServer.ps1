# Nexus Gigabit LAN Web Share Server (Port 80 and Port 52825)
# Serves D:\Share and Desktop files to anyone on the local network (Chrome / Edge / Phone)
param(
    [string]$ShareDir = "D:\Share"
)

$ErrorActionPreference = "SilentlyContinue"

if (-not (Test-Path $ShareDir)) {
    try { New-Item -ItemType Directory -Path $ShareDir -Force | Out-Null } catch {}
}

# Ensure standalone zip is in D:\Share
$desktopZip = Join-Path ([Environment]::GetFolderPath("Desktop")) "PMC-Property-Extractor-Standalone.zip"
if (Test-Path $desktopZip) {
    try { Copy-Item -Path $desktopZip -Destination (Join-Path $ShareDir "PMC-Property-Extractor-Standalone.zip") -Force } catch {}
}

$listener80 = $null
try {
    $listener80 = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, 80)
    $listener80.Start()
    Write-Host "[NEXUS WEB SHARE] Port 80 (Standard Web) Active: http://192.168.1.190/"
} catch {
    Write-Host "[NEXUS WEB SHARE] Port 80 not available, using 52825"
}

$listener52825 = $null
try {
    $listener52825 = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, 52825)
    $listener52825.Start()
    Write-Host "[NEXUS WEB SHARE] Port 52825 Active: http://192.168.1.190:52825/"
} catch {}

function Format-FileSize([int64]$bytes) {
    if ($bytes -ge 1GB) { return "{0:N2} GB" -f ($bytes / 1GB) }
    if ($bytes -ge 1MB) { return "{0:N2} MB" -f ($bytes / 1MB) }
    if ($bytes -ge 1KB) { return "{0:N1} KB" -f ($bytes / 1KB) }
    return "$bytes B"
}

function Build-HtmlIndex {
    $items = @()
    if (Test-Path $ShareDir) {
        $items += Get-ChildItem -Path $ShareDir -File -ErrorAction SilentlyContinue
    }
    
    $fileRows = ""
    if ($items.Count -eq 0) {
        $fileRows = "<tr><td colspan='3' style='text-align:center;color:#64748B;padding:25px;'>No files currently in D:\Share. Add files to share them instantly.</td></tr>"
    } else {
        foreach ($it in $items) {
            $encName = [System.Uri]::EscapeDataString($it.Name)
            $sz = Format-FileSize $it.Length
            $fileRows += "<tr>
                <td style='padding:14px 18px;font-weight:600;color:#F8FAFC;font-size:14px;'>$($it.Name)</td>
                <td style='padding:14px 18px;color:#94A3B8;font-family:monospace;font-size:13px;'>$sz</td>
                <td style='padding:14px 18px;text-align:right;'>
                    <a href='/download?name=$encName' style='display:inline-block;background:#0284C7;color:#FFF;padding:9px 20px;border-radius:6px;text-decoration:none;font-weight:bold;font-size:13px;'>DOWNLOAD</a>
                </td>
            </tr>"
        }
    }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Nexus LAN Share Portal - Mandar PC</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background: #060A13; color: #F8FAFC; padding: 25px; }
  .container { max-width: 900px; margin: 0 auto; }
  .header { display: flex; align-items: center; justify-content: space-between; padding-bottom: 20px; border-bottom: 1px solid #1E293B; margin-bottom: 25px; }
  .logo-title { display: flex; align-items: center; gap: 12px; }
  .badge { background: #059669; color: #FFF; font-size: 11px; padding: 4px 10px; border-radius: 4px; font-weight: bold; }
  .card { background: #0C1322; border: 1px solid #1E293B; border-radius: 10px; overflow: hidden; margin-bottom: 25px; }
  .card-hdr { background: #131E35; padding: 14px 20px; font-size: 13px; font-weight: bold; color: #38BDF8; letter-spacing: 0.5px; border-bottom: 1px solid #1E293B; }
  table { width: 100%; border-collapse: collapse; font-size: 13px; }
  th { text-align: left; padding: 12px 18px; color: #64748B; font-weight: 600; border-bottom: 1px solid #1E293B; font-size: 11px; text-transform: uppercase; }
  tr:not(:last-child) td { border-bottom: 1px solid #131E35; }
  .info-box { background: #0F172A; border-left: 4px solid #0284C7; padding: 16px 20px; border-radius: 6px; font-size: 13px; color: #CBD5E1; line-height: 1.6; }
  .smb-link { color: #38BDF8; font-family: monospace; background: #020617; padding: 3px 8px; border-radius: 4px; }
</style>
</head>
<body>
<div class="container">
  <div class="header">
    <div class="logo-title">
      <div style="font-size:24px;font-weight:800;color:#38BDF8;letter-spacing:1px;">NEXUS DIRECT LAN SHARE</div>
      <span class="badge">DIRECT PC-TO-PC GIGABIT SPEED</span>
    </div>
    <div style="font-size:12px;color:#94A3B8;">Host: <strong>192.168.1.190</strong></div>
  </div>

  <div class="card">
    <div class="card-hdr">SHARED FILES READY FOR 1-CLICK DOWNLOAD</div>
    <table>
      <thead>
        <tr>
          <th>File Name</th>
          <th>Size</th>
          <th style="text-align:right;">Action</th>
        </tr>
      </thead>
      <tbody>
        $fileRows
      </tbody>
    </table>
  </div>

  <div class="info-box">
    <strong style="color:#FFF;">FAST DIRECT WINDOWS ACCESS:</strong><br>
    On any computer in the office, press <kbd>Win + R</kbd> and paste <span class="smb-link">\\192.168.1.190\D\Share</span> to open this shared folder directly inside Windows File Explorer without downloading!
  </div>
</div>
</body>
</html>
"@
    return $html
}

function Handle-Request ($tcpClient) {
    try {
        $tcpClient.ReceiveTimeout = 4000
        $tcpClient.SendTimeout = 15000
        $stream = $tcpClient.GetStream()
        
        $headerBytes = New-Object System.Collections.Generic.List[byte]
        while ($true) {
            $b = $stream.ReadByte()
            if ($b -eq -1) { break }
            $headerBytes.Add([byte]$b)
            $len = $headerBytes.Count
            if ($len -ge 4 -and $headerBytes[$len-4] -eq 13 -and $headerBytes[$len-3] -eq 10 -and $headerBytes[$len-2] -eq 13 -and $headerBytes[$len-1] -eq 10) {
                break
            }
        }
        if ($headerBytes.Count -eq 0) { $tcpClient.Close(); return }

        $headerStr = [System.Text.Encoding]::ASCII.GetString($headerBytes.ToArray())
        $firstLine = ($headerStr -split "`r`n")[0]
        $parts = $firstLine -split '\s+'
        if ($parts.Length -lt 2) { $tcpClient.Close(); return }

        $method = $parts[0].ToUpperInvariant()
        $rawUrl = $parts[1]

        # 1. FILE DOWNLOAD (CHECK FIRST)
        if ($method -eq "GET" -and $rawUrl -match '(?i)^/download\?name=(.+)$') {
            $reqName = [System.Uri]::UnescapeDataString($matches[1])
            $reqName = [System.IO.Path]::GetFileName($reqName)
            $targetPath = Join-Path $ShareDir $reqName
            if (-not (Test-Path $targetPath)) {
                $targetPath = Join-Path ([Environment]::GetFolderPath("Desktop")) $reqName
            }

            if (Test-Path $targetPath) {
                $fi = Get-Item $targetPath
                $fileLen = $fi.Length
                $resHdr = "HTTP/1.1 200 OK`r`nContent-Type: application/octet-stream`r`nContent-Disposition: attachment; filename=`"$($fi.Name)`"`r`nContent-Length: $fileLen`r`nConnection: close`r`n`r`n"
                $hdrB = [System.Text.Encoding]::ASCII.GetBytes($resHdr)
                $stream.Write($hdrB, 0, $hdrB.Length)

                $fs = [System.IO.File]::OpenRead($targetPath)
                $buf = New-Object byte[] 65536
                while (($read = $fs.Read($buf, 0, $buf.Length)) -gt 0) {
                    $stream.Write($buf, 0, $read)
                }
                $fs.Close()
                $stream.Flush()
            } else {
                $notFound = "HTTP/1.1 404 Not Found`r`nContent-Length: 9`r`nConnection: close`r`n`r`nNot Found"
                $nb = [System.Text.Encoding]::ASCII.GetBytes($notFound)
                $stream.Write($nb, 0, $nb.Length)
            }
        # 2. HTML INDEX PORTAL
        } elseif ($method -eq "GET" -and ($rawUrl -eq "/" -or $rawUrl -match '^\/\?')) {
            $html = Build-HtmlIndex
            $htmlBytes = [System.Text.Encoding]::UTF8.GetBytes($html)
            $resHdr = "HTTP/1.1 200 OK`r`nContent-Type: text/html; charset=utf-8`r`nContent-Length: $($htmlBytes.Length)`r`nConnection: close`r`n`r`n"
            $hdrB = [System.Text.Encoding]::ASCII.GetBytes($resHdr)
            $stream.Write($hdrB, 0, $hdrB.Length)
            $stream.Write($htmlBytes, 0, $htmlBytes.Length)
            $stream.Flush()
        } else {
            $badReq = "HTTP/1.1 400 Bad Request`r`nContent-Length: 0`r`nConnection: close`r`n`r`n"
            $bb = [System.Text.Encoding]::ASCII.GetBytes($badReq)
            $stream.Write($bb, 0, $bb.Length)
        }
    } catch {} finally {
        try { $tcpClient.Close() } catch {}
    }
}

try {
    while ($true) {
        $served = $false
        if ($listener80 -and $listener80.Pending()) {
            $cl = $listener80.AcceptTcpClient()
            Handle-Request $cl
            $served = $true
        }
        if ($listener52825 -and $listener52825.Pending()) {
            $cl = $listener52825.AcceptTcpClient()
            Handle-Request $cl
            $served = $true
        }
        if (-not $served) {
            Start-Sleep -Milliseconds 15
        }
    }
} finally {
    try { if ($listener80) { $listener80.Stop() } } catch {}
    try { if ($listener52825) { $listener52825.Stop() } } catch {}
}
