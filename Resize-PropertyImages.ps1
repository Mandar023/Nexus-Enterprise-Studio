<#
.SYNOPSIS
    Resizes and compresses images to UNDER 25 KB with or without Excel filtering.

.PARAMETER TargetFolder
    Path to image directory (local or UNC share).

.PARAMETER ExcelPath
    Path to Excel file (leave empty "" or omit if processing all images without Excel).

.PARAMETER Property
    Optional specific property ID or comma-separated list (e.g. "KH-10-7, KH10") when not using Excel.

.PARAMETER All
    Switch to process ALL images in the target folder without filtering.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string] $TargetFolder = "\\192.168.1.22\d\WebApplicationHost\PMCPhotoStorage.org\wwwroot\Files\PropertyImage",

    [Parameter(Position = 1)]
    [string] $ExcelPath    = "",

    [string] $Property     = "",
    [switch] $All,

    [int]    $MaxKB        = 25,
    [int]    $MaxDim       = 700,
    [int]    $OutputDPI    = 96,
    [string] $BackupFolder = "",
    [string] $Recursive    = "NO",
    [string] $Force        = "NO",
    [string] $LogFile      = ""
)

Add-Type -AssemblyName System.Drawing

function Log-Msg {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $formatted = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        "SUCCESS" { Write-Host $formatted -ForegroundColor Green }
        "WARN"    { Write-Host $formatted -ForegroundColor Yellow }
        "ERROR"   { Write-Host $formatted -ForegroundColor Red }
        "INFO"    { Write-Host $formatted -ForegroundColor Cyan }
        default   { Write-Host $formatted }
    }

    if ($LogFile) {
        try { Add-Content -Path $LogFile -Value $formatted -ErrorAction SilentlyContinue } catch {}
    }
}

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "       PMC PROPERTY IMAGE RESIZER & BACKUP UTILITY     " -ForegroundColor Cyan
Write-Host "             [GUARANTEED TARGET: UNDER $MaxKB KB]       " -ForegroundColor Yellow
Write-Host "=======================================================" -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $TargetFolder)) {
    Log-Msg "Target image folder not accessible: $TargetFolder" "ERROR"
    exit 1
}

if (-not $BackupFolder) {
    $dateStamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $BackupFolder = Join-Path $TargetFolder "_Backup_Originals_$dateStamp"
}

Log-Msg "Target Folder    : $TargetFolder" "INFO"
Log-Msg "Backup Folder    : $BackupFolder" "INFO"
Log-Msg "Target File Size : UNDER $MaxKB KB" "INFO"
Log-Msg "Target Max Dim   : $MaxDim px | DPI: $OutputDPI" "INFO"

$propLookup = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$filterMode = "NONE"

if ($Property -and $Property.Trim() -ne "") {
    $filterMode = "PROPERTY"
    $items = $Property -split '[,;|\r\n]+'
    foreach ($it in $items) {
        $t = $it.Trim()
        if ($t) {
            $propLookup.Add($t) | Out-Null
            if ($t -match '^([A-Za-z]+)(\d+)-(\d+)$') {
                $propLookup.Add("$($Matches[1])-$($Matches[2])-$($Matches[3])") | Out-Null
                $propLookup.Add("$($Matches[1])$($Matches[2])-A-$($Matches[3])") | Out-Null
            }
        }
    }
    Log-Msg "Filtering by specific property: $Property" "INFO"
}
elseif ($ExcelPath -and (Test-Path -LiteralPath $ExcelPath)) {
    $filterMode = "EXCEL"
    Log-Msg "Reading property numbers from Excel: $ExcelPath" "INFO"
    $excel = $null; $wb = $null
    try {
        $excel = New-Object -ComObject Excel.Application
        $excel.Visible = $false
        $excel.DisplayAlerts = $false
        $wb = $excel.Workbooks.Open($ExcelPath, $false, $true)

        foreach ($ws in $wb.Sheets) {
            $vals = $ws.UsedRange.Value2
            if (-not $vals) { continue }
            $rowCount = $vals.GetLength(0); $colCount = $vals.GetLength(1)
            if ($rowCount -lt 2) { continue }

            $headers = @{}
            for ($c = 1; $c -le $colCount; $c++) {
                $h = [string]($vals[1, $c])
                if ($h) { $headers[$h.Trim()] = $c }
            }

            for ($r = 2; $r -le $rowCount; $r++) {
                $building = if ($headers.ContainsKey("Building")) { [string]($vals[$r, $headers["Building"]]) } else { "" }
                $node     = if ($headers.ContainsKey("Node")) { [string]($vals[$r, $headers["Node"]]) } else { "" }
                $ward     = if ($headers.ContainsKey("NewWardNo")) { [string]($vals[$r, $headers["NewWardNo"]]) } else { "" }
                $prop     = if ($headers.ContainsKey("NewPropertyNo")) { [string]($vals[$r, $headers["NewPropertyNo"]]) } else { "" }
                $part     = if ($headers.ContainsKey("NewPartitionNo")) { [string]($vals[$r, $headers["NewPartitionNo"]]) } else { "" }

                if ($building) {
                    $b = $building.Trim()
                    $propLookup.Add($b) | Out-Null
                    if ($b -match '^([A-Za-z]+)(\d+)-(\d+)$') {
                        $n = $Matches[1]; $w = $Matches[2]; $p = $Matches[3]
                        $propLookup.Add("$n-$w-$p") | Out-Null
                        $propLookup.Add("$n$w-A-$p") | Out-Null
                        $propLookup.Add("$n$w-B-$p") | Out-Null
                        $propLookup.Add("$n$w-C-$p") | Out-Null
                        $propLookup.Add("$n-$w-A-$p") | Out-Null
                    }
                }
                if ($ward -and $prop) {
                    $w = $ward.Trim(); $p = $prop.Trim()
                    if ($w -match '^([A-Za-z]+)(\d+)$') {
                        $n = $Matches[1]; $wNum = $Matches[2]
                        $propLookup.Add("$n-$wNum-$p") | Out-Null
                        $propLookup.Add("$n$wNum-$p") | Out-Null
                        $propLookup.Add("$n$wNum-A-$p") | Out-Null
                        $propLookup.Add("$n-$wNum-A-$p") | Out-Null
                    } elseif ($node) {
                        $n = $node.Trim()
                        $propLookup.Add("$n-$w-$p") | Out-Null
                        $propLookup.Add("$n$w-$p") | Out-Null
                        $propLookup.Add("$n$w-A-$p") | Out-Null
                    }
                }
            }
            Log-Msg "  -> Loaded sheet: '$($ws.Name)' ($rowCount rows)" "INFO"
        }
    } catch {
        Log-Msg "Error reading Excel: $($_.Exception.Message)" "ERROR"
        exit 1
    } finally {
        if ($wb) { $wb.Close($false) }
        if ($excel) { $excel.Quit(); [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null }
        [System.GC]::Collect()
    }
    Log-Msg "Loaded $($propLookup.Count) property patterns from Excel." "SUCCESS"
}
else {
    $filterMode = "ALL"
    Log-Msg "No Excel provided: Processing ALL images in folder." "INFO"
}

# Scan Images
$imageExtensions = @('.jpg', '.jpeg', '.png', '.bmp', '.tif', '.tiff', '.gif', '.wmf', '.emf', '.webp')
$searchOpt = if ($Recursive -eq "YES") { [System.IO.SearchOption]::AllDirectories } else { [System.IO.SearchOption]::TopDirectoryOnly }
$matchingImages = [System.Collections.Generic.List[string]]::new()
$scannedCount = 0

foreach ($filePath in [System.IO.Directory]::EnumerateFiles($TargetFolder, "*.*", $searchOpt)) {
    if ($filePath.Contains("_Backup_Originals_") -or $filePath.Contains("_backup")) { continue }

    $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
    if ($imageExtensions -contains $ext) {
        $scannedCount++

        if ($filterMode -eq "ALL") {
            $matchingImages.Add($filePath)
        } else {
            $nameNoExt = [System.IO.Path]::GetFileNameWithoutExtension($filePath)
            $isMatch = $false

            if ($propLookup.Contains($nameNoExt)) {
                $isMatch = $true
            } else {
                if ($nameNoExt -match '^(D_|DIMAJOR_)?(.+?)(-[A-Za-z0-9]+)?$') {
                    $core = $Matches[2]
                    if ($propLookup.Contains($core)) { $isMatch = $true }
                }
                if (-not $isMatch) {
                    $clean = $nameNoExt.Replace("D_", "").Replace("-A", "").Replace("-B", "").Replace("-", "").Trim()
                    if ($propLookup.Contains($clean)) { $isMatch = $true }
                }
            }

            if ($isMatch) { $matchingImages.Add($filePath) }
        }
    }
}

Log-Msg "Total images matched to process: $($matchingImages.Count)" "SUCCESS"
if ($matchingImages.Count -eq 0) { exit 0 }

# Stage 1: Backup
if (-not (Test-Path $BackupFolder)) {
    New-Item -ItemType Directory -Path $BackupFolder -Force | Out-Null
}

$backupCount = 0
for ($b = 0; $b -lt $matchingImages.Count; $b++) {
    $srcPath = $matchingImages[$b]
    $destPath = Join-Path $BackupFolder ([System.IO.Path]::GetFileName($srcPath))
    try {
        [System.IO.File]::Copy($srcPath, $destPath, $true)
        $backupCount++
    } catch {}
}
Log-Msg "Stage 1: Successfully created backup of $backupCount images." "SUCCESS"

# Stage 2: Resize & Compress
function Resize-ImageToMaxKB {
    param([string]$FilePath, [int]$TargetMaxKB, [int]$MaxDimension, [int]$TargetDPI, [bool]$ForceResize)
    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    $origLen = $bytes.Length
    $targetBytes = $TargetMaxKB * 1024
    $ms = New-Object System.IO.MemoryStream($bytes, 0, $bytes.Length)
    $origImg = $null

    try {
        $origImg = [System.Drawing.Image]::FromStream($ms)
        $origW = $origImg.Width; $origH = $origImg.Height

        if ($origLen -le $targetBytes -and $origW -le $MaxDimension -and $origH -le $MaxDimension -and -not $ForceResize) {
            return @{ Status = "SKIPPED"; OrigBytes = $origLen; NewBytes = $origLen }
        }

        $jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" }
        $finalBytes = $null
        $qualities = @(85, 75, 65, 55, 45, 35, 25)
        $dimScale = 1.0

        :outer while ($dimScale -ge 0.35) {
            $scaledMax = [int]($MaxDimension * $dimScale)
            if ($origW -gt $scaledMax -or $origH -gt $scaledMax) {
                if ($origW -ge $origH) {
                    $curW = $scaledMax
                    $curH = [Math]::Max(1, [int]($origH * ($scaledMax / [double]$origW)))
                } else {
                    $curH = $scaledMax
                    $curW = [Math]::Max(1, [int]($origW * ($scaledMax / [double]$origH)))
                }
            } else {
                $curW = [int]($origW * $dimScale); $curH = [int]($origH * $dimScale)
            }
            $curW = [Math]::Max(1, $curW); $curH = [Math]::Max(1, $curH)

            $bmp = New-Object System.Drawing.Bitmap($curW, $curH, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
            $bmp.SetResolution($TargetDPI, $TargetDPI)
            $gfx = [System.Drawing.Graphics]::FromImage($bmp)
            $gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $gfx.Clear([System.Drawing.Color]::White)
            $gfx.DrawImage($origImg, 0, 0, $curW, $curH)

            foreach ($q in $qualities) {
                $encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
                $encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]$q)
                $outMs = New-Object System.IO.MemoryStream
                $bmp.Save($outMs, $jpegCodec, $encoderParams)

                if ($outMs.Length -le $targetBytes) {
                    $finalBytes = $outMs.ToArray()
                    $outMs.Dispose(); $gfx.Dispose(); $bmp.Dispose()
                    break outer
                }
                $outMs.Dispose()
            }
            $gfx.Dispose(); $bmp.Dispose()
            $dimScale -= 0.12
        }

        if ($finalBytes) {
            [System.IO.File]::WriteAllBytes($FilePath, $finalBytes)
            return @{ Status = "RESIZED"; OrigBytes = $origLen; NewBytes = $finalBytes.Length }
        }
        return @{ Status = "SKIPPED"; OrigBytes = $origLen; NewBytes = $origLen }
    } catch {
        return @{ Status = "ERROR"; OrigBytes = $origLen; NewBytes = $origLen }
    } finally {
        if ($origImg) { $origImg.Dispose() }
        if ($ms) { $ms.Dispose() }
    }
}

$resizedCount = 0; $skippedCount = 0; $totalOrig = 0L; $totalNew = 0L

for ($i = 0; $i -lt $matchingImages.Count; $i++) {
    $img = $matchingImages[$i]
    $res = Resize-ImageToMaxKB -FilePath $img -TargetMaxKB $MaxKB -MaxDimension $MaxDim -TargetDPI $OutputDPI -ForceResize ($Force -eq "YES")
    $totalOrig += $res.OrigBytes
    $totalNew  += $res.NewBytes
    if ($res.Status -eq "RESIZED") { $resizedCount++ } else { $skippedCount++ }
}

$savedMb = [Math]::Round(($totalOrig - $totalNew) / 1MB, 2)
Write-Host "`n=======================================================" -ForegroundColor Green
Write-Host "                FINAL EXECUTION SUMMARY               " -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Green
Write-Host " Total Processed      : $($matchingImages.Count)"
Write-Host " Successfully Backed  : $backupCount in $BackupFolder" -ForegroundColor Cyan
Write-Host " Resized Under $MaxKB KB  : $resizedCount" -ForegroundColor Green
Write-Host " Storage Space Saved  : $savedMb MB" -ForegroundColor Yellow
Write-Host "=======================================================" -ForegroundColor Green
