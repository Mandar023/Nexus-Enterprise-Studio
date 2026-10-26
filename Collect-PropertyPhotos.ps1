<#
.SYNOPSIS
    Nexus Property Photo & PlanPhoto WMF Extractor (Server Collector to Desktop)
    Extracts photos and WMF/EMF files matching Property Numbers / Owner IDs from an Excel sheet and saves them to a folder on your Desktop.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $false)]
    [string]$ExcelPath = "",

    [Parameter(Position = 1, Mandatory = $false)]
    [string]$SourceFolder = "",

    [Parameter(Position = 2, Mandatory = $false)]
    [string]$OutputFolder = "",

    [ValidateSet("Photos", "WMF", "Both")]
    [string]$Mode = "Photos",

    [switch]$WhiteCanvas = $true,
    [switch]$OrganizeByProperty,
    [switch]$Recursive,
    [switch]$AutoResize,
    [int]$MaxKB = 25
)

Add-Type -AssemblyName System.IO.Compression.FileSystem, System.Xml.Linq, System.Drawing, Microsoft.VisualBasic

# Add C# WMF White Canvas Engine
$wmfCsharp = @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

public class ExtractorWmfHelper
{
    [DllImport("gdi32.dll")]
    public static extern bool DeleteEnhMetaFile(IntPtr hemf);

    [DllImport("gdiplus.dll", SetLastError = true)]
    public static extern int GdipEmfToWmfBits(IntPtr hEmf, int uBufferSize, byte[] bBuffer, int iMappingMode, int flags);

    public static bool ApplyWhiteCanvas(string inputPath, string outputPath, int maxDim, int dpi, int maxKB)
    {
        try
        {
            byte[] rawBytes = File.ReadAllBytes(inputPath);
            string tempEmf = Path.GetTempFileName() + ".emf";
            int targetW = 700;
            int targetH = 700;
            using (MemoryStream inMs = new MemoryStream(rawBytes))
            using (Image src = Image.FromStream(inMs))
            {
                int srcW = src.Width > 0 ? src.Width : 700;
                int srcH = src.Height > 0 ? src.Height : 700;
                double scale = Math.Min((double)maxDim / srcW, (double)maxDim / srcH);
                if (scale > 1.0) scale = 1.0;
                targetW = Math.Max(1, (int)Math.Round(srcW * scale));
                targetH = Math.Max(1, (int)Math.Round(srcH * scale));

                using (Bitmap refBmp = new Bitmap(1, 1, PixelFormat.Format32bppArgb))
                using (Graphics refG = Graphics.FromImage(refBmp))
                {
                    IntPtr hdc = refG.GetHdc();
                    try
                    {
                        Rectangle rect = new Rectangle(0, 0, targetW, targetH);
                        using (Metafile emf = new Metafile(tempEmf, hdc, rect, MetafileFrameUnit.Pixel, EmfType.EmfPlusDual))
                        using (Graphics emfG = Graphics.FromImage(emf))
                        {
                            emfG.Clear(Color.White);
                            emfG.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                            emfG.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.HighQuality;
                            emfG.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
                            emfG.DrawImage(src, 0, 0, targetW, targetH);
                        }
                    }
                    finally { refG.ReleaseHdc(hdc); }
                }
            }

            if (File.Exists(tempEmf))
            {
                using (Metafile readEmf = new Metafile(tempEmf))
                {
                    IntPtr hemf = readEmf.GetHenhmetafile();
                    if (hemf != IntPtr.Zero)
                    {
                        try
                        {
                            int bufSize = GdipEmfToWmfBits(hemf, 0, null, 8, 0);
                            if (bufSize > 0)
                            {
                                byte[] rawWmf = new byte[bufSize];
                                GdipEmfToWmfBits(hemf, bufSize, rawWmf, 8, 0);

                                byte[] header = new byte[] {
                                    0xD7, 0xCD, 0xC6, 0x9A, 0x00, 0x00, 0x00, 0x00,
                                    0x00, 0x00, (byte)(targetW & 0xFF), (byte)((targetW >> 8) & 0xFF),
                                    (byte)(targetH & 0xFF), (byte)((targetH >> 8) & 0xFF),
                                    (byte)(dpi & 0xFF), (byte)((dpi >> 8) & 0xFF),
                                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00
                                };

                                int checksum = 0;
                                checksum ^= 0xCDD7; checksum ^= 0x9AC6;
                                checksum ^= (targetW & 0xFFFF); checksum ^= (targetH & 0xFFFF);
                                checksum ^= (dpi & 0xFFFF);
                                header[20] = (byte)(checksum & 0xFF);
                                header[21] = (byte)((checksum >> 8) & 0xFF);

                                byte[] full = new byte[header.Length + rawWmf.Length];
                                Buffer.BlockCopy(header, 0, full, 0, header.Length);
                                Buffer.BlockCopy(rawWmf, 0, full, header.Length, rawWmf.Length);

                                File.WriteAllBytes(outputPath, full);
                                try { File.Delete(tempEmf); } catch {}
                                return true;
                            }
                        }
                        finally { DeleteEnhMetaFile(hemf); }
                    }
                }
                try { File.Delete(tempEmf); } catch {}
            }
        }
        catch {}
        return false;
    }
}
"@
try { Add-Type -TypeDefinition $wmfCsharp -ReferencedAssemblies System.Drawing } catch {}

function Show-Header {
    Write-Host "===============================================================================" -ForegroundColor Cyan
    Write-Host "   NEXUS PROPERTY PHOTO & PLANPHOTO (WMF) EXTRACTOR (TO DESKTOP)              " -ForegroundColor Cyan
    Write-Host "===============================================================================" -ForegroundColor Cyan
    Write-Host "  Modes Supported   : Property Photos (JPG) | PlanPhoto WMF (Solid White) | Both" -ForegroundColor Yellow
    Write-Host "  Formats Supported : C11-2573-3-A | Owner IDs | Building IDs | WMF PlanPhotos" -ForegroundColor Yellow
    Write-Host "  Destination       : Desktop Folder + CSV Missing / Found Report              " -ForegroundColor Yellow
    Write-Host "===============================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Log-Msg {
    param([string]$Message, [string]$Level = "INFO")
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    switch ($Level) {
        "SUCCESS" { Write-Host "[$ts] [SUCCESS] $Message" -ForegroundColor Green }
        "WARN"    { Write-Host "[$ts] [WARN]    $Message" -ForegroundColor Yellow }
        "ERROR"   { Write-Host "[$ts] [ERROR]   $Message" -ForegroundColor Red }
        "INFO"    { Write-Host "[$ts] [INFO]    $Message" -ForegroundColor Cyan }
        default   { Write-Host "[$ts] [INFO]    $Message" }
    }
}

Show-Header

# Default Source Folders
$defaultPhotoFolder = "\\192.168.1.22\d\WebApplicationHost\PMCPhotoStorage.org\wwwroot\Files\PropertyImage"
$defaultWmfFolder   = "\\192.168.1.22\d\WebApplicationHost\PMCPhotoStorage.org\wwwroot\Files\PlanPhoto"

if (-not $SourceFolder) {
    if ($Mode -eq "WMF") { $SourceFolder = $defaultWmfFolder }
    else { $SourceFolder = $defaultPhotoFolder }
}

# --- Interactive Prompts if parameters omitted ---
if (-not $ExcelPath -or -not (Test-Path -LiteralPath $ExcelPath)) {
    Write-Host "[?] Please select or enter the path to the Excel file (.xlsx / .xls / .csv):" -ForegroundColor White
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Select Excel File with Property Numbers / Owner IDs"
    $dialog.Filter = "Excel & CSV Files (*.xlsx;*.xls;*.csv)|*.xlsx;*.xls;*.csv|All Files (*.*)|*.*"
    $dialog.InitialDirectory = [Environment]::GetFolderPath("Desktop")
    
    try {
        Add-Type -AssemblyName System.Windows.Forms
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $ExcelPath = $dialog.FileName
        }
    } catch {}
    
    if (-not $ExcelPath) {
        $ExcelPath = Read-Host "Enter Excel File Path"
        $ExcelPath = $ExcelPath.Trim('"').Trim("'")
    }
}

if (-not $ExcelPath -or -not (Test-Path -LiteralPath $ExcelPath)) {
    Log-Msg "No valid Excel file provided. Exiting." "ERROR"
    exit 1
}

# Validate Source Folder
if (-not (Test-Path -LiteralPath $SourceFolder)) {
    Log-Msg "Default source folder not reachable ($SourceFolder)." "WARN"
    Write-Host "[?] Please enter the Source Image/WMF Folder path:" -ForegroundColor White
    $inputSrc = Read-Host "Source Image Folder"
    if ($inputSrc) { $SourceFolder = $inputSrc.Trim('"').Trim("'") }
}

if (-not (Test-Path -LiteralPath $SourceFolder)) {
    Log-Msg "Cannot access source folder: $SourceFolder" "ERROR"
    exit 1
}

# Auto-switch path if WMF mode is chosen but source folder points to PropertyImage
if ($Mode -eq "WMF" -and $SourceFolder -match '(?i)PropertyImage') {
    $candidatePlan = $SourceFolder -replace '(?i)PropertyImage', 'PlanPhoto'
    if (Test-Path -LiteralPath $candidatePlan) {
        $SourceFolder = $candidatePlan
        Log-Msg "[AI AUTO-REDIRECT] Switched to PlanPhoto directory: $SourceFolder" "SUCCESS"
    }
} elseif ($Mode -eq "Photos" -and $SourceFolder -match '(?i)PlanPhoto') {
    $candidateProp = $SourceFolder -replace '(?i)PlanPhoto', 'PropertyImage'
    if (Test-Path -LiteralPath $candidateProp) {
        $SourceFolder = $candidateProp
        Log-Msg "[AI AUTO-REDIRECT] Switched to PropertyImage directory: $SourceFolder" "SUCCESS"
    }
}

# Determine Output Folder on Desktop
if (-not $OutputFolder) {
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $dateStamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $excelName = [System.IO.Path]::GetFileNameWithoutExtension($ExcelPath)
    $prefix = if ($Mode -eq "WMF") { "Collected_WMF_Plans" } elseif ($Mode -eq "Both") { "Collected_Photos_And_WMF" } else { "Collected_Property_Photos" }
    $OutputFolder = Join-Path $desktopPath "${prefix}_${excelName}_${dateStamp}"
}

if (-not (Test-Path -LiteralPath $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}

Log-Msg "Mode            : $Mode $(if ($Mode -eq 'WMF') {'(PlanPhoto WMF Vector)'} elseif ($Mode -eq 'Both') {'(Photos + WMF)'} else {'(Property Photos JPG)'})" "INFO"
Log-Msg "Excel File Path : $ExcelPath" "INFO"
Log-Msg "Source Folder   : $SourceFolder" "INFO"
Log-Msg "Desktop Output  : $OutputFolder" "SUCCESS"
if ($Mode -eq "WMF" -or $Mode -eq "Both") {
    Log-Msg "Solid White Canvas : $(if ($WhiteCanvas) {'ENABLED (Crystal Reports Safe)'} else {'Disabled'})" "INFO"
}

# --- 1. Fast Excel Property Extraction ---
Log-Msg "Step 1: Reading property numbers from Excel..." "INFO"

$propertyList = [System.Collections.Generic.List[string]]::new()
$searchTokens = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$tokenToPrimaryProp = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)

function Register-PropVariation {
    param([string]$Primary, [string]$Variation)
    if (-not $Variation -or $Variation.Trim() -eq "" -or $Variation -eq "#N/A") { return }
    $v = $Variation.Trim()
    $searchTokens.Add($v) | Out-Null
    if (-not $tokenToPrimaryProp.ContainsKey($v)) {
        $tokenToPrimaryProp[$v] = $Primary
    }
}

function Process-ExcelRow {
    param($RowVals)
    $building = ""; $node = ""; $ward = ""; $prop = ""; $part = ""; $ownerId = ""; $generic = ""
    foreach ($k in $RowVals.Keys) {
        $v = [string]$RowVals[$k]
        if (-not $v -or $v.Trim() -eq "" -or $v -eq "#N/A") { continue }
        $v = $v.Trim()
        $kL = $k.ToLower()
        if ($kL -match '^building') { $building = $v }
        elseif ($kL -match '^node') { $node = $v }
        elseif ($kL -match '(newward|ward)') { $ward = $v }
        elseif ($kL -match '(newprop|propertyno|property_no|property|propno)') { $prop = $v }
        elseif ($kL -match '(partition|partno|part_no|part)') { $part = $v }
        elseif ($kL -match '(ownerid|owner_id|owner)') { $ownerId = $v }
        elseif ($kL -match '^(prop|id|flat|assessment|consumer)') { $generic = $v }
        elseif ($kL -match 'merchant' -or ($v -match 'W([A-Za-z0-9]+)P(\d+)')) {
            if ($v -match 'W([A-Za-z0-9]+)P(\d+)') {
                if (-not $ward) { $ward = $Matches[1] }
                if (-not $prop) { $prop = $Matches[2] }
            }
        }
    }

    $primary = ""
    if ($building) { $primary = $building }
    elseif ($ownerId) { $primary = $ownerId }
    elseif ($prop -and $ward) { $primary = "$ward-$prop" }
    elseif ($prop) { $primary = $prop }
    elseif ($generic) { $primary = $generic }
    else {
        foreach ($v in $RowVals.Values) {
            if ($v -and $v.Trim() -ne "" -and $v -ne "#N/A") { $primary = $v.Trim(); break }
        }
    }

    if (-not $primary) { return }
    if (-not $propertyList.Contains($primary)) { $propertyList.Add($primary) }
    Register-PropVariation -Primary $primary -Variation $primary

    if ($building) { Register-PropVariation -Primary $primary -Variation $building }
    if ($ownerId) { Register-PropVariation -Primary $primary -Variation $ownerId }

    # Numeric variations for Property Number
    $wList = [System.Collections.Generic.List[string]]::new()
    $pList = [System.Collections.Generic.List[string]]::new()

    if ($prop) {
        $pRaw = $prop.Trim()
        $pList.Add($pRaw)
        if ($pRaw -match '^\d+$') {
            $pInt = [int]$pRaw
            $pList.Add($pInt.ToString())
            $pList.Add($pInt.ToString("D2"))
            $pList.Add($pInt.ToString("D3"))
            $pList.Add($pInt.ToString("D4"))
            $pList.Add($pInt.ToString("D5"))
        }
    }

    if ($ward) {
        $wRaw = $ward.Trim()
        $wList.Add($wRaw)
        $wClean = $wRaw -replace '^(Major|Minor|Ward|Prabhag|Zone|Node)[\s\-_]*', ''
        if ($wClean -and -not $wList.Contains($wClean)) { $wList.Add($wClean) }

        if ($wRaw -match '([A-Za-z]+)[\s\-_]*(\d+)') {
            $n = $Matches[1]; $wNum = $Matches[2]
            $wList.Add("$n$wNum")
            $wList.Add("$n-$wNum")
            $wList.Add("$n_$wNum")
            $wList.Add($wNum)
        }
        if ($wClean -match '([A-Za-z]+)[\s\-_]*(\d+)') {
            $n = $Matches[1]; $wNum = $Matches[2]
            $wList.Add("$n$wNum")
            $wList.Add("$n-$wNum")
            $wList.Add("$n_$wNum")
            $wList.Add($wNum)
        }
    }

    if ($building -and $building -match '^([A-Za-z0-9]+)[\-_](\d+)') {
        $wB = $Matches[1]; $pB = $Matches[2]
        if (-not $wList.Contains($wB)) { $wList.Add($wB) }
        $pIntB = [int]$pB
        $pList.Add($pB)
        $pList.Add($pIntB.ToString())
        $pList.Add($pIntB.ToString("D2"))
        $pList.Add($pIntB.ToString("D3"))
        $pList.Add($pIntB.ToString("D4"))
        $pList.Add($pIntB.ToString("D5"))
    }

    foreach ($wItem in $wList) {
        foreach ($pItem in $pList) {
            Register-PropVariation -Primary $primary -Variation "$wItem-$pItem"
            Register-PropVariation -Primary $primary -Variation "$wItem`_$pItem"
            Register-PropVariation -Primary $primary -Variation "$wItem$pItem"
            Register-PropVariation -Primary $primary -Variation "$wItem-A-$pItem"
            Register-PropVariation -Primary $primary -Variation "$wItem-B-$pItem"
            Register-PropVariation -Primary $primary -Variation "$wItem-C-$pItem"
            Register-PropVariation -Primary $primary -Variation "$wItem-P-$pItem"
            Register-PropVariation -Primary $primary -Variation "$wItem-PL-$pItem"
            Register-PropVariation -Primary $primary -Variation "$wItem`_A`_$pItem"
            Register-PropVariation -Primary $primary -Variation "$wItem`_B`_$pItem"
            Register-PropVariation -Primary $primary -Variation "$wItem`_P`_$pItem"
            if ($part) {
                Register-PropVariation -Primary $primary -Variation "$wItem-$pItem-$part"
                Register-PropVariation -Primary $primary -Variation "$wItem-$pItem`_$part"
            }
        }
    }
}

function Get-MatchedPropKey($fileName) {
    $nameNoExt = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
    if ($tokenToPrimaryProp.ContainsKey($nameNoExt)) { return $tokenToPrimaryProp[$nameNoExt] }

    # 1. Strip known server prefixes
    $clean = $nameNoExt -replace '^(D_|DIMAJOR_|MAJOR_|MINOR_|WARD_|PRABHAG_|ZONE_|PHOTO_|PROP_|PLAN_|WMF_|PMC[-_]OP\d*[-_]|PMC[-_]|IMG[-_]|PIC[-_]|SCAN[-_]|FILE[-_]|--+)', ''
    if ($tokenToPrimaryProp.ContainsKey($clean)) { return $tokenToPrimaryProp[$clean] }

    # 2. Strip trailing photo sequence / orientation / revision / archive suffixes
    $noSuffix = $clean -replace '([_\-\.]+(?:BK|R\d+|C\d+|REV\d*|part\d*|front|rear|side|inside|outside|road|meter|top|back|latlong|plan|wmf|photo|img|pic|\d+|[A-Za-z]))*$', ''
    if ($noSuffix -and $tokenToPrimaryProp.ContainsKey($noSuffix)) { return $tokenToPrimaryProp[$noSuffix] }

    # 3. Delimiter normalization (_ to -)
    $dashClean = $clean -replace '[_\s]+', '-'
    if ($tokenToPrimaryProp.ContainsKey($dashClean)) { return $tokenToPrimaryProp[$dashClean] }

    $dashNoSuffix = $noSuffix -replace '[_\s]+', '-'
    if ($dashNoSuffix -and $tokenToPrimaryProp.ContainsKey($dashNoSuffix)) { return $tokenToPrimaryProp[$dashNoSuffix] }

    # 4. Infix pattern: Node + Ward + Infix + Prop (e.g. KH10-A-1-R1 -> KH10-1)
    if ($dashClean -match '^([A-Za-z0-9]+)[-_](?:[A-Za-z]+)[-_](\d+)') {
        $wCand = $Matches[1]; $pCand = $Matches[2]
        if ($tokenToPrimaryProp.ContainsKey("$wCand-$pCand")) { return $tokenToPrimaryProp["$wCand-$pCand"] }
        if ($pCand -match '^\d+$') {
            $pInt = [int]$pCand
            if ($tokenToPrimaryProp.ContainsKey("$wCand-$($pInt)")) { return $tokenToPrimaryProp["$wCand-$($pInt)"] }
        }
    }

    # 5. Ward + Prop pattern with numeric normalization
    if ($dashClean -match '^([A-Za-z0-9]+)[-_](\d+)') {
        $wCand = $Matches[1]; $pCand = $Matches[2]
        if ($tokenToPrimaryProp.ContainsKey("$wCand-$pCand")) { return $tokenToPrimaryProp["$wCand-$pCand"] }
        if ($pCand -match '^\d+$') {
            $pInt = [int]$pCand
            if ($tokenToPrimaryProp.ContainsKey("$wCand-$($pInt)")) { return $tokenToPrimaryProp["$wCand-$($pInt)"] }
        }
    }

    # 6. Progressive right-to-left segment trimming
    $curr = $dashClean.Trim('-')
    $safety = 0
    while ($safety -lt 10 -and $curr.Contains("-")) {
        $safety++
        $lastIdx = $curr.LastIndexOf('-')
        if ($lastIdx -le 0) { break }
        $curr = $curr.Substring(0, $lastIdx).TrimEnd('-')
        if ($curr -and $tokenToPrimaryProp.ContainsKey($curr)) { return $tokenToPrimaryProp[$curr] }
        if ($curr -match '^(.+)-(\d+)$') {
            $wPart = $Matches[1]; $pPart = [int]$Matches[2]
            if ($tokenToPrimaryProp.ContainsKey("$wPart-$pPart")) { return $tokenToPrimaryProp["$wPart-$pPart"] }
        }
    }

    return ""
}

$ext = [System.IO.Path]::GetExtension($ExcelPath).ToLower()
if ($ext -eq ".xlsx") {
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ExcelPath)
        $sharedStrings = [System.Collections.Generic.List[string]]::new()
        $ssEntry = $zip.GetEntry("xl/sharedStrings.xml")
        if ($ssEntry) {
            $sStream = $ssEntry.Open()
            $sDoc = [System.Xml.Linq.XDocument]::Load($sStream)
            $sStream.Dispose()
            $sNs = $sDoc.Root.Name.Namespace
            foreach ($si in $sDoc.Descendants($sNs + "si")) {
                $fullT = ""
                foreach ($t in $si.Descendants($sNs + "t")) { $fullT += $t.Value }
                $sharedStrings.Add($fullT)
            }
        }
        
        $sheetEntries = @($zip.Entries | Where-Object { $_.FullName -like "xl/worksheets/sheet*.xml" })
        foreach ($sEntry in $sheetEntries) {
            $wStream = $sEntry.Open()
            $wDoc = [System.Xml.Linq.XDocument]::Load($wStream)
            $wStream.Dispose()
            $wNs = $wDoc.Root.Name.Namespace
            $sheetDataList = @($wDoc.Descendants($wNs + "sheetData"))
            if ($sheetDataList.Count -eq 0) { continue }
            $sheetData = $sheetDataList[0]
            
            $headerMap = @{}
            $isHeader = $true
            
            foreach ($row in $sheetData.Elements($wNs + "row")) {
                $rowVals = @{}
                foreach ($c in $row.Elements($wNs + "c")) {
                    $cRef = $c.Attribute("r").Value
                    $colLetters = $cRef -replace '\d+', ''
                    $cType = if ($c.Attribute("t")) { $c.Attribute("t").Value } else { "" }
                    $vElem = $c.Element($wNs + "v")
                    $val = ""
                    if ($vElem) {
                        $rawV = $vElem.Value
                        if ($cType -eq "s") {
                            $idx = 0
                            if ([int]::TryParse($rawV, [ref]$idx) -and $idx -ge 0 -and $idx -lt $sharedStrings.Count) {
                                $val = $sharedStrings[$idx]
                            }
                        } elseif ($cType -eq "inlineStr") {
                            $isElem = $c.Element($wNs + "is")
                            if ($isElem) {
                                $tElem = $isElem.Element($wNs + "t")
                                if ($tElem) { $val = $tElem.Value }
                            }
                        } else {
                            $val = $rawV
                        }
                    }
                    $val = $val.Trim()
                    if ($isHeader) {
                        $headerMap[$colLetters] = $val
                    } else {
                        $hName = if ($headerMap.ContainsKey($colLetters) -and $headerMap[$colLetters]) { $headerMap[$colLetters] } else { "Col_$colLetters" }
                        $rowVals[$hName] = $val
                        $rowVals["Col_$colLetters"] = $val
                    }
                }
                if ($isHeader) { $isHeader = $false }
                else { if ($rowVals.Count -gt 0) { Process-ExcelRow -RowVals $rowVals } }
            }
        }
        $zip.Dispose()
    } catch {
        Log-Msg "OpenXML error: $($_.Exception.Message). Trying COM..." "WARN"
    }
}

if ($propertyList.Count -eq 0) {
    # Fallback to COM
    $excel = $null; $wb = $null
    try {
        $excel = New-Object -ComObject Excel.Application
        $excel.Visible = $false; $excel.DisplayAlerts = $false
        $wb = $excel.Workbooks.Open($ExcelPath, $false, $true)
        foreach ($ws in $wb.Sheets) {
            $vals = $ws.UsedRange.Value2
            if (-not $vals) { continue }
            $rowCount = $vals.GetLength(0); $colCount = $vals.GetLength(1)
            if ($rowCount -lt 2) { continue }
            $headers = @{}
            for ($c = 1; $c -le $colCount; $c++) {
                $h = [string]($vals[1, $c])
                if ($h) { $headers[$c] = $h.Trim() }
            }
            for ($r = 2; $r -le $rowCount; $r++) {
                $rowVals = @{}
                for ($c = 1; $c -le $colCount; $c++) {
                    $hName = if ($headers.ContainsKey($c)) { $headers[$c] } else { "Col_$c" }
                    $v = [string]($vals[$r, $c])
                    if ($v) { $rowVals[$hName] = $v.Trim() }
                }
                if ($rowVals.Count -gt 0) { Process-ExcelRow -RowVals $rowVals }
            }
        }
    } catch {
        Log-Msg "COM error: $($_.Exception.Message)" "ERROR"
    } finally {
        if ($wb) { $wb.Close($false) }
        if ($excel) { $excel.Quit(); [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null }
        [System.GC]::Collect()
    }
}

Log-Msg "Loaded $($propertyList.Count) unique properties ($($searchTokens.Count) matching search tokens)." "SUCCESS"
if ($propertyList.Count -eq 0) {
    Log-Msg "No property numbers found in Excel. Please check the file." "ERROR"
    exit 1
}

# --- 2. Scan Source Storage ---
Log-Msg "Step 2: Scanning source folder for matching files..." "INFO"

$imageExts = if ($Mode -eq "WMF") {
    @('.wmf', '.emf')
} elseif ($Mode -eq "Both") {
    @('.jpg', '.jpeg', '.png', '.bmp', '.tif', '.tiff', '.gif', '.wmf', '.emf', '.webp')
} else {
    @('.jpg', '.jpeg', '.png', '.bmp', '.tif', '.tiff', '.gif', '.webp')
}

$rootFolders = [System.Collections.Generic.List[string]]::new()
$rootFolders.Add($SourceFolder)

# Automatic Multi-Location Discovery (Photos + WMFs)
if ($Mode -eq "Both") {
    if ($SourceFolder -match '(?i)PropertyImage') {
        $planSibling = $SourceFolder -replace '(?i)PropertyImage', 'PlanPhoto'
        if ((Test-Path -LiteralPath $planSibling) -and -not $rootFolders.Contains($planSibling)) {
            $rootFolders.Add($planSibling)
            Log-Msg "[AI AUTO-DISCOVERY] Detected sibling PlanPhoto directory: $planSibling" "SUCCESS"
        }
    } elseif ($SourceFolder -match '(?i)PlanPhoto') {
        $propSibling = $SourceFolder -replace '(?i)PlanPhoto', 'PropertyImage'
        if ((Test-Path -LiteralPath $propSibling) -and -not $rootFolders.Contains($propSibling)) {
            $rootFolders.Add($propSibling)
            Log-Msg "[AI AUTO-DISCOVERY] Detected sibling PropertyImage directory: $propSibling" "SUCCESS"
        }
    }
    foreach ($subName in @("PropertyImage", "PlanPhoto", "Photos", "WMF", "Plans", "Images")) {
        $subPath = Join-Path $SourceFolder $subName
        if ((Test-Path -LiteralPath $subPath) -and -not $rootFolders.Contains($subPath)) {
            $rootFolders.Add($subPath)
            Log-Msg "[AI AUTO-DISCOVERY] Found subfolder '$subName': $subPath" "SUCCESS"
        }
    }
} elseif ($Mode -eq "WMF") {
    if ($SourceFolder -match '(?i)PropertyImage') {
        $planSibling = $SourceFolder -replace '(?i)PropertyImage', 'PlanPhoto'
        if (Test-Path -LiteralPath $planSibling) {
            $rootFolders.Clear()
            $rootFolders.Add($planSibling)
            Log-Msg "[AI AUTO-REDIRECT] Switched to PlanPhoto directory: $planSibling" "SUCCESS"
        }
    }
    $subPlan = Join-Path $SourceFolder "PlanPhoto"
    if ((Test-Path -LiteralPath $subPlan) -and -not $rootFolders.Contains($subPlan)) {
        $rootFolders.Add($subPlan)
    }
} elseif ($Mode -eq "Photos") {
    if ($SourceFolder -match '(?i)PlanPhoto') {
        $propSibling = $SourceFolder -replace '(?i)PlanPhoto', 'PropertyImage'
        if (Test-Path -LiteralPath $propSibling) {
            $rootFolders.Clear()
            $rootFolders.Add($propSibling)
            Log-Msg "[AI AUTO-REDIRECT] Switched to PropertyImage directory: $propSibling" "SUCCESS"
        }
    }
    $subProp = Join-Path $SourceFolder "PropertyImage"
    if ((Test-Path -LiteralPath $subProp) -and -not $rootFolders.Contains($subProp)) {
        $rootFolders.Add($subProp)
    }
}

$matchedFiles = [System.Collections.Generic.List[PSCustomObject]]::new()
$propFoundMap = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new([System.StringComparer]::OrdinalIgnoreCase)

foreach ($p in $propertyList) {
    $propFoundMap[$p] = [System.Collections.Generic.List[string]]::new()
}

# Fault-Tolerant Breadth-First Directory Crawler
$dirQueue = [System.Collections.Generic.Queue[string]]::new()
$visitedDirs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($rf in $rootFolders) {
    if (Test-Path -LiteralPath $rf) {
        $dirQueue.Enqueue($rf)
        $visitedDirs.Add($rf) | Out-Null
    }
}

$scanned = 0
while ($dirQueue.Count -gt 0) {
    $currentDir = $dirQueue.Dequeue()
    $dirFiles = @()
    try {
        $dirFiles = [System.IO.Directory]::GetFiles($currentDir, "*.*")
    } catch {
        Log-Msg "Skipped folder: $currentDir ($($_.Exception.Message))" "WARN"
        continue
    }

    foreach ($filePath in $dirFiles) {
        if ($filePath.Contains("_Backup_Originals_") -or $filePath.Contains("_Backup_PlanPhoto_") -or $filePath.Contains("_backup")) { continue }
        $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
        if (-not ($imageExts -contains $ext)) { continue }

        $scanned++
        $fileName = [System.IO.Path]::GetFileName($filePath)
        $matchedPrimaryProp = Get-MatchedPropKey $fileName

        if ($matchedPrimaryProp) {
            $matchedFiles.Add([PSCustomObject]@{
                SourcePath  = $filePath
                FileName    = $fileName
                PropertyKey = $matchedPrimaryProp
                IsWmf       = ($ext -eq ".wmf" -or $ext -eq ".emf")
            })

            if ($propFoundMap.ContainsKey($matchedPrimaryProp)) {
                $propFoundMap[$matchedPrimaryProp].Add($fileName)
            }
        }
    }

    if ($Recursive) {
        try {
            $subDirs = [System.IO.Directory]::GetDirectories($currentDir)
            foreach ($sd in $subDirs) {
                $sdName = [System.IO.Path]::GetFileName($sd)
                if ($sdName -match '(?i)backup' -or $sdName.StartsWith('.')) { continue }
                if (-not $visitedDirs.Contains($sd)) {
                    $visitedDirs.Add($sd) | Out-Null
                    $dirQueue.Enqueue($sd)
                }
            }
        } catch {}
    }
}

Log-Msg "Scanned $scanned total files across server directories." "INFO"

if ($matchedFiles.Count -eq 0) {
    Log-Msg "No matching files found for requested properties in source folder: $SourceFolder" "ERROR"
    Log-Msg "Please check: 1) Path is correct (PlanPhoto for WMF / PropertyImage for photos), 2) Use -Recursive switch if stored in ward folders." "WARN"
    exit 0
}

Log-Msg "Found $($matchedFiles.Count) matching files for requested properties!" "SUCCESS"

# --- 3. Copy Matched Files to Desktop Folder ---
Log-Msg "Step 3: Copying collected files to Desktop: $OutputFolder" "INFO"

$copiedCount = 0
$wmfFixedCount = 0
$copyErrors = 0

for ($i = 0; $i -lt $matchedFiles.Count; $i++) {
    $item = $matchedFiles[$i]
    $src = $item.SourcePath
    
    $destDir = $OutputFolder
    if ($OrganizeByProperty) {
        $destDir = Join-Path $OutputFolder $item.PropertyKey
    }
    if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    
    # Prevent collisions in flat output folder
    $dest = Join-Path $destDir $item.FileName
    if (Test-Path -LiteralPath $dest) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($item.FileName)
        $fExt = [System.IO.Path]::GetExtension($item.FileName)
        $colIdx = 2
        while (Test-Path -LiteralPath $dest) {
            $dest = Join-Path $destDir "${baseName}_$colIdx$fExt"
            $colIdx++
        }
    }

    try {
        if ($item.IsWmf -and $WhiteCanvas) {
            $wmfSuccess = [ExtractorWmfHelper]::ApplyWhiteCanvas($src, $dest, 700, 96, $MaxKB)
            if ($wmfSuccess) {
                $wmfFixedCount++
            } else {
                [System.IO.File]::Copy($src, $dest, $true)
            }
        } else {
            [System.IO.File]::Copy($src, $dest, $true)
        }
        $copiedCount++
    } catch {
        Log-Msg "Failed to copy '$($item.FileName)': $($_.Exception.Message)" "WARN"
        $copyErrors++
    }
}

# --- 4. Generate Reports ---
$reportPath = Join-Path $OutputFolder "Collection_Summary_Report.csv"
$missingPath = Join-Path $OutputFolder "Missing_Properties_Report.csv"

$reportRows = [System.Collections.Generic.List[PSCustomObject]]::new()
$missingList = [System.Collections.Generic.List[string]]::new()
$foundPropCount = 0

foreach ($p in $propertyList) {
    $files = $propFoundMap[$p]
    $isFound = ($files -and $files.Count -gt 0)
    if ($isFound) {
        $foundPropCount++
    } else {
        $missingList.Add($p)
    }
    
    $reportRows.Add([PSCustomObject]@{
        "Property_ID"       = $p
        "Status"            = if ($isFound) { "FOUND" } else { "MISSING" }
        "Files_Count"       = if ($files) { $files.Count } else { 0 }
        "Matched_Filenames" = if ($files) { $files -join "; " } else { "None" }
    })
}

$reportRows | Export-Csv -Path $reportPath -NoTypeInformation -Encoding UTF8
if ($missingList.Count -gt 0) {
    $missingList | ForEach-Object { [PSCustomObject]@{ "Missing_Property_ID" = $_ } } | 
        Export-Csv -Path $missingPath -NoTypeInformation -Encoding UTF8
}

Write-Host ""
Write-Host "===============================================================================" -ForegroundColor Green
Write-Host "                       COLLECTION SUMMARY RESULTS                              " -ForegroundColor Green
Write-Host "===============================================================================" -ForegroundColor Green
Write-Host "  * Mode                       : $Mode" -ForegroundColor White
Write-Host "  * Total Properties in Excel  : $($propertyList.Count)" -ForegroundColor White
Write-Host "  * Properties Found on Server : $foundPropCount" -ForegroundColor Green
Write-Host "  * Properties Missing Files   : $($missingList.Count)" -ForegroundColor $(if ($missingList.Count -gt 0) { "Yellow" } else { "Green" })
Write-Host "  * Total Files Collected      : $copiedCount" -ForegroundColor Cyan
if ($wmfFixedCount -gt 0) {
    Write-Host "  * WMF Solid White Background : $wmfFixedCount WMF files converted (Crystal Reports Safe)" -ForegroundColor Green
}
Write-Host "  * Output Folder on Desktop   : $OutputFolder" -ForegroundColor Yellow
Write-Host "  * Full Summary Report CSV    : $reportPath" -ForegroundColor White
if ($missingList.Count -gt 0) {
    Write-Host "  * Missing Properties CSV     : $missingPath" -ForegroundColor Yellow
}
Write-Host "===============================================================================" -ForegroundColor Green

# Open Destination Folder on Desktop
try {
    Start-Process "explorer.exe" -ArgumentList "`"$OutputFolder`""
} catch {}
