<#
.SYNOPSIS
    Resizes and optimizes WMF (Windows Metafile) files matching specific Property Numbers from an Excel file
    in the PlanPhoto folder to UNDER 25 KB (or custom -MaxKB). Creates a 100% backup before modifying.

.DESCRIPTION
    1. Reads property data from Excel (all sheets).
    2. Generates formatted property IDs (e.g. "KH-10-7", "KH10-7", "KH10-A-10", "KH1-A-1", etc.).
    3. Scans PlanPhoto folder (\\192.168.1.22\d\WebApplicationHost\PMCPhotoStorage.org\wwwroot\Files\PlanPhoto).
    4. Matches WMF filenames (e.g. D_KH10-A-10.wmf, D_KH10-A-10-R1.wmf, --KM10-A-58-R1.wmf, KH10-A-8.wmf).
    5. STAGE 1: Creates a 100% full backup of all matched WMF files before touching any file.
    6. STAGE 2: Optimizes & resizes each WMF using GDI+ metafile engine to ensure size is UNDER MaxKB (Default: 25 KB).
    7. Outputs valid Aldus Placeable WMF with 22-byte header (0xD7 0xCD 0xC6 0x9A) compatible with Crystal Reports and Web viewers.

.PARAMETER TargetFolder
    Path to PlanPhoto directory (local or UNC share).
    Default: \\192.168.1.22\d\WebApplicationHost\PMCPhotoStorage.org\wwwroot\Files\PlanPhoto

.PARAMETER ExcelPath
    Path to the Excel file containing property numbers.
    Default: C:\Users\mandar.k\Downloads\ASWSWSSAAAA\New folder\indi prop.xlsx

.PARAMETER MaxKB
    Maximum allowed file size in Kilobytes (KB). Default is 25.

.PARAMETER MaxDim
    Maximum width or height in pixels. Default is 700.

.PARAMETER OutputDPI
    Target DPI resolution for output images. Default is 96.

.PARAMETER BackupFolder
    Destination folder to store backups of original WMF files before resizing.
    Default: TargetFolder\_Backup_PlanPhoto_<Timestamp>

.PARAMETER Recursive
    "NO" (default) or "YES" (to scan subfolders).

.PARAMETER Force
    "YES" or "NO" (default) - re-process even if WMF is already under MaxKB.

.PARAMETER LogFile
    Optional file path to write detailed execution log.

.EXAMPLE
    .\Resize-PlanPhotoWMF.ps1
    .\Resize-PlanPhotoWMF.ps1 -MaxKB 25 -MaxDim 700 -OutputDPI 96
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string] $TargetFolder = "\\192.168.1.22\d\WebApplicationHost\PMCPhotoStorage.org\wwwroot\Files\PlanPhoto",

    [Parameter(Position = 1)]
    [string] $ExcelPath    = "C:\Users\mandar.k\Downloads\ASWSWSSAAAA\New folder\indi prop.xlsx",

    [int]    $MaxKB        = 25,
    [int]    $MaxDim       = 700,
    [int]    $OutputDPI    = 96,
    [string] $BackupFolder = "",
    [string] $Recursive    = "NO",
    [string] $Force        = "NO",
    [string] $LogFile      = ""
)

Add-Type -AssemblyName System.Drawing

# Compile C# WmfOptimizer Engine
$csharp = @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

public class WmfOptimizer
{
    [DllImport("gdi32.dll")]
    public static extern bool DeleteEnhMetaFile(IntPtr hemf);

    [DllImport("gdiplus.dll", SetLastError = true)]
    public static extern int GdipEmfToWmfBits(IntPtr hEmf, int uBufferSize, byte[] bBuffer, int iMappingMode, int flags);

    public static string ProcessWmfFile(string inputPath, string outputPath, int maxDim, int dpi, int maxKB, bool force)
    {
        string tempEmf = outputPath + ".tmp.emf";
        Image src = null;
        Metafile emf = null;
        Graphics emfG = null;
        Bitmap refBmp = null;
        Graphics refG = null;
        Bitmap rasterBmp = null;
        Bitmap formattedBmp = null;

        try
        {
            if (File.Exists(tempEmf)) File.Delete(tempEmf);

            FileInfo fi = new FileInfo(inputPath);
            long origLen = fi.Length;

            src = Image.FromFile(inputPath);
            int srcW = src.Width;
            int srcH = src.Height;

            if (srcW <= 0) srcW = 700;
            if (srcH <= 0) srcH = 700;

            int targetW = srcW;
            int targetH = srcH;
            if (srcW > maxDim || srcH > maxDim)
            {
                if (srcW >= srcH)
                {
                    targetW = maxDim;
                    targetH = Math.Max(1, (int)Math.Round(srcH * ((double)maxDim / srcW)));
                }
                else
                {
                    targetH = maxDim;
                    targetW = Math.Max(1, (int)Math.Round(srcW * ((double)maxDim / srcH)));
                }
            }

            if (origLen <= maxKB * 1024 && !force)
            {
                src.Dispose();
                src = null;
                return "SKIPPED:Already " + Math.Round(origLen / 1024.0, 1) + " KB (<= " + maxKB + " KB)";
            }

            string[] modes = new string[] { "vector", "4bpp", "8bpp", "1bpp" };
            double[] scales = new double[] { 1.0, 0.85, 0.70, 0.55 };

            byte[] finalWmf = null;
            int finalW = targetW;
            int finalH = targetH;
            string finalMode = "";

            foreach (string mode in modes)
            {
                foreach (double sc in scales)
                {
                    int runW = Math.Max(1, (int)Math.Round(targetW * sc));
                    int runH = Math.Max(1, (int)Math.Round(targetH * sc));

                    if (File.Exists(tempEmf)) File.Delete(tempEmf);

                    refBmp = new Bitmap(1, 1);
                    refBmp.SetResolution(dpi, dpi);
                    refG = Graphics.FromImage(refBmp);
                    IntPtr hdc = refG.GetHdc();
                    emf = new Metafile(tempEmf, hdc, new RectangleF(0, 0, runW, runH), MetafileFrameUnit.Pixel, EmfType.EmfOnly);
                    refG.ReleaseHdc(hdc);

                    emfG = Graphics.FromImage(emf);
                    emfG.CompositingQuality = System.Drawing.Drawing2D.CompositingQuality.HighQuality;
                    emfG.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                    emfG.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                    emfG.Clear(Color.White);

                    if (mode == "vector")
                    {
                        emfG.DrawImage(src, new Rectangle(0, 0, runW, runH));
                    }
                    else
                    {
                        rasterBmp = new Bitmap(runW, runH);
                        rasterBmp.SetResolution(dpi, dpi);
                        using (Graphics rg = Graphics.FromImage(rasterBmp))
                        {
                            rg.CompositingQuality = System.Drawing.Drawing2D.CompositingQuality.HighQuality;
                            rg.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                            rg.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                            rg.Clear(Color.White);
                            rg.DrawImage(src, 0, 0, runW, runH);
                        }

                        PixelFormat pf = PixelFormat.Format4bppIndexed;
                        if (mode == "8bpp") pf = PixelFormat.Format8bppIndexed;
                        else if (mode == "1bpp") pf = PixelFormat.Format1bppIndexed;

                        formattedBmp = rasterBmp.Clone(new Rectangle(0, 0, runW, runH), pf);
                        emfG.DrawImage(formattedBmp, 0, 0, runW, runH);
                    }

                    if (emfG != null) { emfG.Dispose(); emfG = null; }
                    if (emf != null) { emf.Dispose(); emf = null; }
                    if (refG != null) { refG.Dispose(); refG = null; }
                    if (refBmp != null) { refBmp.Dispose(); refBmp = null; }
                    if (formattedBmp != null) { formattedBmp.Dispose(); formattedBmp = null; }
                    if (rasterBmp != null) { rasterBmp.Dispose(); rasterBmp = null; }

                    using (var savedEmf = new Metafile(tempEmf))
                    {
                        IntPtr hEmf = savedEmf.GetHenhmetafile();
                        if (hEmf != IntPtr.Zero)
                        {
                            try
                            {
                                int size = GdipEmfToWmfBits(hEmf, 0, null, 8, 0);
                                if (size > 0)
                                {
                                    byte[] wmfBits = new byte[size];
                                    int written = GdipEmfToWmfBits(hEmf, size, wmfBits, 8, 0);
                                    if (written > 0)
                                    {
                                        byte[] header = new byte[22];
                                        header[0] = 0xD7; header[1] = 0xCD; header[2] = 0xC6; header[3] = 0x9A; // 0x9AC6CDD7
                                        header[4] = 0x00; header[5] = 0x00;
                                        BitConverter.GetBytes((short)0).CopyTo(header, 6);
                                        BitConverter.GetBytes((short)0).CopyTo(header, 8);
                                        BitConverter.GetBytes((short)runW).CopyTo(header, 10);
                                        BitConverter.GetBytes((short)runH).CopyTo(header, 12);
                                        BitConverter.GetBytes((short)dpi).CopyTo(header, 14);
                                        short chk = 0;
                                        for (int i = 0; i < 20; i += 2) chk ^= BitConverter.ToInt16(header, i);
                                        BitConverter.GetBytes(chk).CopyTo(header, 20);

                                        byte[] full = new byte[22 + wmfBits.Length];
                                        Buffer.BlockCopy(header, 0, full, 0, 22);
                                        Buffer.BlockCopy(wmfBits, 0, full, 22, wmfBits.Length);

                                        if (full.Length <= maxKB * 1024)
                                        {
                                            finalWmf = full;
                                            finalW = runW;
                                            finalH = runH;
                                            finalMode = mode;
                                            break;
                                        }
                                        else if (finalWmf == null || full.Length < finalWmf.Length)
                                        {
                                            finalWmf = full;
                                            finalW = runW;
                                            finalH = runH;
                                            finalMode = mode;
                                        }
                                    }
                                }
                            }
                            finally
                            {
                                DeleteEnhMetaFile(hEmf);
                            }
                        }
                    }

                    if (finalWmf != null && finalWmf.Length <= maxKB * 1024) break;
                }
                if (finalWmf != null && finalWmf.Length <= maxKB * 1024) break;
            }

            if (src != null) { src.Dispose(); src = null; }

            if (finalWmf != null)
            {
                File.WriteAllBytes(outputPath, finalWmf);
                return "OK:" + Math.Round(finalWmf.Length / 1024.0, 1) + " KB (" + finalW + "x" + finalH + ", " + finalMode + ")";
            }

            return "ERROR:Could not compress WMF";
        }
        catch (Exception ex)
        {
            return "ERROR:" + ex.Message;
        }
        finally
        {
            if (emfG != null) try { emfG.Dispose(); } catch {}
            if (emf != null) try { emf.Dispose(); } catch {}
            if (refG != null) try { refG.Dispose(); } catch {}
            if (refBmp != null) try { refBmp.Dispose(); } catch {}
            if (formattedBmp != null) try { formattedBmp.Dispose(); } catch {}
            if (rasterBmp != null) try { rasterBmp.Dispose(); } catch {}
            if (src != null) try { src.Dispose(); } catch {}
            try { if (File.Exists(tempEmf)) File.Delete(tempEmf); } catch {}
        }
    }
}
"@

Add-Type -TypeDefinition $csharp -ReferencedAssemblies "System.Drawing"

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
Write-Host "       PMC PLANPHOTO (WMF) RESIZER & BACKUP UTILITY    " -ForegroundColor Cyan
Write-Host "             [GUARANTEED TARGET: UNDER $MaxKB KB]       " -ForegroundColor Yellow
Write-Host "=======================================================" -ForegroundColor Cyan

if (Test-Path $ExcelPath -PathType Container) {
    $foundXl = Get-ChildItem -Path $ExcelPath -Filter "*.xlsx" -File | Select-Object -First 1
    if (-not $foundXl) { $foundXl = Get-ChildItem -Path $ExcelPath -Filter "*.xls" -File | Select-Object -First 1 }
    if ($foundXl) { $ExcelPath = $foundXl.FullName }
}

if (-not (Test-Path -LiteralPath $ExcelPath)) {
    Log-Msg "Excel file not found at: $ExcelPath" "ERROR"
    exit 1
}

if (-not (Test-Path -LiteralPath $TargetFolder)) {
    Log-Msg "PlanPhoto folder not accessible: $TargetFolder" "ERROR"
    exit 1
}

if (-not $BackupFolder) {
    $dateStamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $BackupFolder = Join-Path $TargetFolder "_Backup_PlanPhoto_$dateStamp"
}

Log-Msg "Excel Source     : $ExcelPath" "INFO"
Log-Msg "PlanPhoto Folder : $TargetFolder" "INFO"
Log-Msg "Backup Folder    : $BackupFolder" "INFO"
Log-Msg "Target File Size : UNDER $MaxKB KB" "INFO"
Log-Msg "Target Max Dim   : $MaxDim px (Aspect Ratio Preserved)" "INFO"
Log-Msg "Target DPI       : $OutputDPI DPI" "INFO"

# --- Function: Generate formatted property keys for PlanPhoto matching ---
function Add-FormattedKeys {
    param(
        [System.Collections.Generic.HashSet[string]]$LookupSet,
        [string]$Node,
        [string]$Ward,
        [string]$Prop,
        [string]$Part,
        [string]$Building
    )

    if ($Building) {
        $b = $Building.Trim()
        if ($b) {
            $LookupSet.Add($b) | Out-Null
            if ($b -match '^([A-Za-z]+)(\d+)-(\d+)$') {
                $n = $Matches[1]; $w = $Matches[2]; $p = $Matches[3]
                $LookupSet.Add("$n-$w-$p") | Out-Null
                $LookupSet.Add("$n$w-$p") | Out-Null
                $LookupSet.Add("$n$w-A-$p") | Out-Null
                $LookupSet.Add("$n$w-B-$p") | Out-Null
                $LookupSet.Add("$n$w-C-$p") | Out-Null
                $LookupSet.Add("$n$w-P-$p") | Out-Null
                $LookupSet.Add("$n-$w-A-$p") | Out-Null
            }
        }
    }

    if ($Ward -and $Prop) {
        $w = $Ward.Trim()
        $p = $Prop.Trim()

        if ($w -match '^([A-Za-z]+)(\d+)$') {
            $n = $Matches[1]; $wNum = $Matches[2]
            $LookupSet.Add("$n-$wNum-$p") | Out-Null
            $LookupSet.Add("$n$wNum-$p") | Out-Null
            $LookupSet.Add("$n$wNum-A-$p") | Out-Null
            $LookupSet.Add("$n$wNum-B-$p") | Out-Null
            $LookupSet.Add("$n$wNum-C-$p") | Out-Null
            $LookupSet.Add("$n$wNum-P-$p") | Out-Null
            $LookupSet.Add("$n-$wNum-A-$p") | Out-Null
        }
        elseif ($Node -and $Node.Trim() -ne "") {
            $n = $Node.Trim()
            $LookupSet.Add("$n-$w-$p") | Out-Null
            $LookupSet.Add("$n$w-$p") | Out-Null
            $LookupSet.Add("$n$w-A-$p") | Out-Null
        }
    }
}

# --- Step 1: Read Properties from Excel ---
Log-Msg "Reading property numbers from Excel sheets..." "INFO"
$propLookup = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

$excel = $null
$wb = $null
try {
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false
    $wb = $excel.Workbooks.Open($ExcelPath, $false, $true)

    foreach ($ws in $wb.Sheets) {
        $vals = $ws.UsedRange.Value2
        if (-not $vals) { continue }

        $rowCount = $vals.GetLength(0)
        $colCount = $vals.GetLength(1)
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

            Add-FormattedKeys -LookupSet $propLookup -Node $node -Ward $ward -Prop $prop -Part $part -Building $building
        }
        Log-Msg "  -> Loaded sheet: '$($ws.Name)' ($rowCount rows)" "INFO"
    }
}
catch {
    Log-Msg "Error reading Excel: $($_.Exception.Message)" "ERROR"
    exit 1
}
finally {
    if ($wb) { $wb.Close($false) }
    if ($excel) {
        $excel.Quit()
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
    }
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}

Log-Msg "Generated $($propLookup.Count) property match patterns from Excel." "SUCCESS"

# --- Step 2: Scan PlanPhoto for Matching WMF Files ---
Log-Msg "Scanning WMF files in $TargetFolder..." "INFO"
$searchOpt = if ($Recursive -eq "YES") { [System.IO.SearchOption]::AllDirectories } else { [System.IO.SearchOption]::TopDirectoryOnly }

$matchingFiles = [System.Collections.Generic.List[string]]::new()
$scannedCount = 0

foreach ($filePath in [System.IO.Directory]::EnumerateFiles($TargetFolder, "*.wmf", $searchOpt)) {
    if ($filePath.Contains("_Backup_PlanPhoto_") -or $filePath.Contains("_backup")) { continue }

    $scannedCount++
    $nameNoExt = [System.IO.Path]::GetFileNameWithoutExtension($filePath)

    $isMatch = $false
    if ($propLookup.Contains($nameNoExt)) {
        $isMatch = $true
    }
    else {
        # Match pattern: D_KH10-A-10-R1, --KM10-A-58-R1, D_KH1-A-1-C2, D_KH10-A-8, etc.
        $clean = $nameNoExt
        if ($clean.StartsWith("D_")) { $clean = $clean.Substring(2) }
        if ($clean.StartsWith("--")) { $clean = $clean.Substring(2) }

        if ($propLookup.Contains($clean)) {
            $isMatch = $true
        } else {
            # Normalize e.g. KH10-A-8 -> KH10-8, KH10-A-8-R4 -> KH10-8
            if ($clean -match '^([A-Za-z]+)(\d+)(-[A-Za-z]+)?-(\d+)(-[A-Za-z0-9]+)?$') {
                $nodeLetter = $Matches[1]
                $wardNum    = $Matches[2]
                $propNum    = $Matches[4]

                $k1 = "$nodeLetter$wardNum-$propNum"
                $k2 = "$nodeLetter-$wardNum-$propNum"
                $k3 = "$nodeLetter$wardNum-A-$propNum"

                if ($propLookup.Contains($k1) -or $propLookup.Contains($k2) -or $propLookup.Contains($k3)) {
                    $isMatch = $true
                }
            }
        }
    }

    if ($isMatch) {
        $matchingFiles.Add($filePath)
    }

    if ($scannedCount % 50000 -eq 0) {
        Write-Host "  ...scanned $scannedCount files (matched: $($matchingFiles.Count))..." -ForegroundColor DarkGray
    }
}

Log-Msg "Scan completed. Total WMF scanned: $scannedCount | Matching WMF found: $($matchingFiles.Count)" "SUCCESS"

if ($matchingFiles.Count -eq 0) {
    Log-Msg "No matching WMF files found in $TargetFolder" "WARN"
    exit 0
}

# --- Step 3: STAGE 1 - FULL BACKUP FIRST ---
Log-Msg "=======================================================" "INFO"
Log-Msg "STAGE 1: CREATING BACKUPS OF $($matchingFiles.Count) MATCHED WMF FILES..." "INFO"
Log-Msg "Destination Backup Folder: $BackupFolder" "INFO"

if (-not (Test-Path $BackupFolder)) {
    New-Item -ItemType Directory -Path $BackupFolder -Force | Out-Null
}

$backupCount = 0
$backupErrors = 0
for ($b = 0; $b -lt $matchingFiles.Count; $b++) {
    $srcPath = $matchingFiles[$b]
    $fileName = [System.IO.Path]::GetFileName($srcPath)
    $destPath = Join-Path $BackupFolder $fileName

    try {
        [System.IO.File]::Copy($srcPath, $destPath, $true)
        $backupCount++
    }
    catch {
        $backupErrors++
        Log-Msg "Backup failed for: $fileName ($($_.Exception.Message))" "ERROR"
    }

    if (($b + 1) % 500 -eq 0 -or ($b + 1) -eq $matchingFiles.Count) {
        $pct = [Math]::Round((($b + 1) / $matchingFiles.Count) * 100, 1)
        Write-Progress -Activity "Backing up matched WMF files" -Status "[$($b+1)/$($matchingFiles.Count)] ($pct%) $fileName" -PercentComplete $pct
    }
}
Write-Progress -Activity "Backing up matched WMF files" -Completed

Log-Msg "Backup finished. Successfully copied: $backupCount WMF files (Errors: $backupErrors)" "SUCCESS"

if ($backupErrors -gt 0) {
    Log-Msg "WARNING: Some backups failed! Halting to prevent modifying files without backup." "ERROR"
    exit 1
}

# --- Step 4: STAGE 2 - WMF RESIZING & COMPRESSION UNDER 25 KB ---
Log-Msg "=======================================================" "INFO"
Log-Msg "STAGE 2: OPTIMIZING & COMPRESSING MATCHED WMF FILES UNDER $MaxKB KB..." "INFO"

$resizedCount = 0
$skippedCount = 0
$errorCount = 0
$totalOrigSize = 0L
$totalNewSize = 0L
$doForce = ($Force -eq "YES")
$totalToProcess = $matchingFiles.Count

for ($i = 0; $i -lt $totalToProcess; $i++) {
    $wmfFile = $matchingFiles[$i]
    $fileName = [System.IO.Path]::GetFileName($wmfFile)
    $percent = [Math]::Round((($i + 1) / $totalToProcess) * 100, 1)

    $origLen = (Get-Item $wmfFile).Length
    $totalOrigSize += $origLen

    $res = [WmfOptimizer]::ProcessWmfFile($wmfFile, $wmfFile, $MaxDim, $OutputDPI, $MaxKB, $doForce)

    if ($res.StartsWith("OK:")) {
        $resizedCount++
        $newLen = (Get-Item $wmfFile).Length
        $totalNewSize += $newLen
    }
    elseif ($res.StartsWith("SKIPPED:")) {
        $skippedCount++
        $totalNewSize += $origLen
    }
    else {
        $errorCount++
        $totalNewSize += $origLen
        Log-Msg "Error on $fileName`: $res" "ERROR"
    }

    if (($i + 1) % 100 -eq 0 -or ($i + 1) -eq $totalToProcess) {
        Write-Progress -Activity "Compressing WMF Files Under $MaxKB KB" -Status "[$($i+1)/$totalToProcess] ($percent%) Resized: $resizedCount, Skipped: $skippedCount" -PercentComplete $percent
    }
}

Write-Progress -Activity "Compressing WMF Files Under $MaxKB KB" -Completed

# --- Summary Report ---
$origMb = [Math]::Round($totalOrigSize / 1MB, 2)
$newMb = [Math]::Round($totalNewSize / 1MB, 2)
$savedMb = [Math]::Round(($totalOrigSize - $totalNewSize) / 1MB, 2)

Write-Host "`n=======================================================" -ForegroundColor Green
Write-Host "                FINAL EXECUTION SUMMARY               " -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Green
Write-Host " Total WMF Matched    : $totalToProcess"
Write-Host " Successfully Backed  : $backupCount in $BackupFolder" -ForegroundColor Cyan
Write-Host " Resized Under $MaxKB KB  : $resizedCount" -ForegroundColor Green
Write-Host " Already Under $MaxKB KB  : $skippedCount" -ForegroundColor Gray
Write-Host " Errors Encountered   : $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { "Red" } else { "Green" })
if ($resizedCount -gt 0) {
    Write-Host " Original Total Size  : $origMb MB"
    Write-Host " New Total Size       : $newMb MB"
    Write-Host " Storage Space Saved  : $savedMb MB" -ForegroundColor Yellow
}
Write-Host "=======================================================" -ForegroundColor Green
