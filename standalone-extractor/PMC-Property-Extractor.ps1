<#
.SYNOPSIS
    PMC Property Asset & WMF Plan Extractor (Desktop Standalone Edition) v5.5
    Self-contained, zero-dependency extractor for Panvel Municipal Corporation.
    Extracts property photos and WMF vector plans from Server 11, 22, 19 or local folders
    directly to Desktop with automatic ward flattening and Crystal Reports <25 KB optimization.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"

# 1. Load Required .NET Assemblies
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.Xml.Linq

# 2. Compile High-Performance C# WMF/JPG Engine
$csharp = @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class StandaloneWmfOptimizer
{
    [DllImport("gdi32.dll")]
    public static extern bool DeleteEnhMetaFile(IntPtr hemf);

    [DllImport("gdiplus.dll", SetLastError = true)]
    public static extern int GdipEmfToWmfBits(IntPtr hEmf, int uBufferSize, byte[] bBuffer, int iMappingMode, int flags);

    public static string ProcessWmf(string inputPath, string outputPath, int maxDim, int dpi, int maxKB, bool force)
    {
        byte[] inBytes = File.ReadAllBytes(inputPath);
        long limitBytes = (maxKB > 0) ? (maxKB * 1024) : (25 * 1024);

        if (!force && inBytes.Length <= limitBytes)
        {
            if (!string.Equals(inputPath, outputPath, StringComparison.OrdinalIgnoreCase))
            {
                File.Copy(inputPath, outputPath, true);
            }
            return "SKIPPED:Already " + Math.Round(inBytes.Length / 1024.0, 1) + " KB";
        }

        byte[] outBytes = ConvertBlobToCrystalReportWmf(inBytes, maxDim, dpi, maxKB, force);
        if (outBytes != null && outBytes.Length > 0)
        {
            File.WriteAllBytes(outputPath, outBytes);
            return "OK:" + Math.Round(outBytes.Length / 1024.0, 1) + " KB";
        }
        return "ERROR:Optimization failed";
    }

    public static byte[] ConvertBlobToCrystalReportWmf(byte[] rawBytes, int maxDim, int dpi, int maxKB, bool force)
    {
        long limitBytes = (maxKB > 0) ? (maxKB * 1024) : (25 * 1024);
        if (!force && rawBytes.Length <= limitBytes)
        {
            return rawBytes;
        }

        string tempEmf = Path.GetTempFileName() + ".emf";
        Image src = null;
        Metafile emf = null;
        Graphics emfG = null;
        Bitmap refBmp = null;
        Graphics refG = null;
        Bitmap solidBmp = null;
        Graphics solidG = null;

        try
        {
            using (MemoryStream inMs = new MemoryStream(rawBytes))
            {
                src = Image.FromStream(inMs);
            }

            int srcW = src.Width > 0 ? src.Width : 700;
            int srcH = src.Height > 0 ? src.Height : 700;

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

            double[] scales = new double[] { 1.0, 0.85, 0.70, 0.55, 0.40 };
            byte[] bestWmf = null;

            foreach (double sc in scales)
            {
                int runW = Math.Max(1, (int)Math.Round(targetW * sc));
                int runH = Math.Max(1, (int)Math.Round(targetH * sc));

                if (File.Exists(tempEmf)) File.Delete(tempEmf);

                solidBmp = new Bitmap(runW, runH, PixelFormat.Format24bppRgb);
                solidBmp.SetResolution(dpi, dpi);
                solidG = Graphics.FromImage(solidBmp);
                solidG.CompositingQuality = System.Drawing.Drawing2D.CompositingQuality.HighQuality;
                solidG.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                solidG.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;

                using (SolidBrush wb = new SolidBrush(Color.White))
                {
                    solidG.FillRectangle(wb, 0, 0, runW, runH);
                }
                solidG.DrawImage(src, 0, 0, runW, runH);

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

                using (SolidBrush wb = new SolidBrush(Color.White))
                {
                    emfG.FillRectangle(wb, 0, 0, runW, runH);
                }
                emfG.DrawImage(solidBmp, 0, 0, runW, runH);

                emfG.Dispose(); emfG = null;
                emf.Dispose(); emf = null;
                refG.Dispose(); refG = null;
                refBmp.Dispose(); refBmp = null;
                solidG.Dispose(); solidG = null;
                solidBmp.Dispose(); solidBmp = null;

                if (File.Exists(tempEmf))
                {
                    using (Metafile readEmf = new Metafile(tempEmf))
                    {
                        IntPtr hEmf = readEmf.GetHenhmetafile();
                        try
                        {
                            int bufSize = GdipEmfToWmfBits(hEmf, 0, null, 8, 0);
                            if (bufSize > 0)
                            {
                                byte[] rawWmf = new byte[bufSize];
                                GdipEmfToWmfBits(hEmf, bufSize, rawWmf, 8, 0);

                                byte[] header = new byte[] {
                                    0xD7, 0xCD, 0xC6, 0x9A, 0x00, 0x00, 0x00, 0x00,
                                    0x00, 0x00, (byte)(runW & 0xFF), (byte)((runW >> 8) & 0xFF),
                                    (byte)(runH & 0xFF), (byte)((runH >> 8) & 0xFF),
                                    (byte)(dpi & 0xFF), (byte)((dpi >> 8) & 0xFF),
                                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00
                                };

                                int checksum = 0;
                                checksum ^= 0xCDD7; checksum ^= 0x9AC6;
                                checksum ^= (runW & 0xFFFF); checksum ^= (runH & 0xFFFF);
                                checksum ^= (dpi & 0xFFFF);
                                header[20] = (byte)(checksum & 0xFF);
                                header[21] = (byte)((checksum >> 8) & 0xFF);

                                byte[] full = new byte[header.Length + rawWmf.Length];
                                Buffer.BlockCopy(header, 0, full, 0, header.Length);
                                Buffer.BlockCopy(rawWmf, 0, full, header.Length, rawWmf.Length);

                                if (full.Length <= maxKB * 1024)
                                {
                                    return full;
                                }
                                else if (bestWmf == null || full.Length < bestWmf.Length)
                                {
                                    bestWmf = full;
                                }
                            }
                        }
                        finally
                        {
                            DeleteEnhMetaFile(hEmf);
                        }
                    }
                }

                if (bestWmf != null && bestWmf.Length <= maxKB * 1024) break;
            }

            return bestWmf;
        }
        catch
        {
            return null;
        }
        finally
        {
            if (src != null) try { src.Dispose(); } catch {}
            if (emfG != null) try { emfG.Dispose(); } catch {}
            if (emf != null) try { emf.Dispose(); } catch {}
            if (refG != null) try { refG.Dispose(); } catch {}
            if (refBmp != null) try { refBmp.Dispose(); } catch {}
            if (solidG != null) try { solidG.Dispose(); } catch {}
            if (solidBmp != null) try { solidBmp.Dispose(); } catch {}
            try { if (File.Exists(tempEmf)) File.Delete(tempEmf); } catch {}
        }
    }

    public static byte[] ConvertBlobToCrystalReportJpg(byte[] rawBytes, int maxDim, int dpi, int maxKB)
    {
        try
        {
            using (MemoryStream inMs = new MemoryStream(rawBytes))
            using (Image src = Image.FromStream(inMs))
            {
                int srcW = src.Width > 0 ? src.Width : 700;
                int srcH = src.Height > 0 ? src.Height : 700;

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

                ImageCodecInfo jpegCodec = null;
                foreach (ImageCodecInfo c in ImageCodecInfo.GetImageEncoders())
                {
                    if (c.MimeType == "image/jpeg") { jpegCodec = c; break; }
                }

                int[] qualities = new int[] { 85, 75, 65, 55, 45, 35 };
                double[] scales = new double[] { 1.0, 0.85, 0.70, 0.55 };

                byte[] bestJpg = null;

                foreach (double sc in scales)
                {
                    int runW = Math.Max(1, (int)Math.Round(targetW * sc));
                    int runH = Math.Max(1, (int)Math.Round(targetH * sc));

                    using (Bitmap bmp = new Bitmap(runW, runH, PixelFormat.Format24bppRgb))
                    {
                        bmp.SetResolution(dpi, dpi);
                        using (Graphics g = Graphics.FromImage(bmp))
                        {
                            g.CompositingQuality = System.Drawing.Drawing2D.CompositingQuality.HighQuality;
                            g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;

                            using (SolidBrush wb = new SolidBrush(Color.White))
                            {
                                g.FillRectangle(wb, 0, 0, runW, runH);
                            }
                            g.DrawImage(src, 0, 0, runW, runH);
                        }

                        foreach (int q in qualities)
                        {
                            using (MemoryStream outMs = new MemoryStream())
                            using (EncoderParameters ep = new EncoderParameters(1))
                            {
                                ep.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, (long)q);
                                bmp.Save(outMs, jpegCodec, ep);
                                byte[] bytes = outMs.ToArray();

                                if (bytes.Length <= maxKB * 1024)
                                {
                                    return bytes;
                                }
                                else if (bestJpg == null || bytes.Length < bestJpg.Length)
                                {
                                    bestJpg = bytes;
                                }
                            }
                        }
                    }
                }

                return bestJpg;
            }
        }
        catch
        {
            return null;
        }
    }
}
"@

try {
    Add-Type -TypeDefinition $csharp -ReferencedAssemblies "System.Drawing.dll" -ErrorAction SilentlyContinue
} catch {}

# 3. Core Logic: Spreadsheet Property Extractor
function Get-SpreadsheetProperties($excelPath) {
    $propList = [System.Collections.Generic.List[string]]::new()
    $tokenToPrimary = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    function Add-TokenAlias($primary, $alias) {
        if ([string]::IsNullOrWhiteSpace($alias) -or $alias -eq "#N/A") { return }
        $a = $alias.Trim()
        if (-not $tokenToPrimary.ContainsKey($a)) { $tokenToPrimary[$a] = $primary }
    }

    function Process-ItemRow($rowVals) {
        $building = ""; $node = ""; $ward = ""; $prop = ""; $part = ""; $ownerId = ""; $generic = ""
        foreach ($k in $rowVals.Keys) {
            $v = [string]$rowVals[$k]
            if ([string]::IsNullOrWhiteSpace($v) -or $v -eq "#N/A") { continue }
            $v = $v.Trim()
            $kL = $k.ToLower()
            if ($kL -match '^building') { $building = $v }
            elseif ($kL -match '^node') { $node = $v }
            elseif ($kL -match '(newward|ward)') { $ward = $v }
            elseif ($kL -match '(newprop|propertyno|property_no|property|propno|prop_no)') { $prop = $v }
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
        if ($prop -and $ward) { $primary = "$ward-$prop" }
        elseif ($prop) { $primary = $prop }
        elseif ($ownerId) { $primary = $ownerId }
        elseif ($building) { $primary = $building }
        elseif ($generic) { $primary = $generic }
        else {
            foreach ($v in $rowVals.Values) {
                if (-not [string]::IsNullOrWhiteSpace($v) -and $v -ne "#N/A") { $primary = $v.Trim(); break }
            }
        }

        if (-not $primary) { return }
        if (-not $propList.Contains($primary)) { $propList.Add($primary) }
        Add-TokenAlias $primary $primary

        if ($prop) { Add-TokenAlias $primary $prop }
        if ($building) { Add-TokenAlias $primary $building }
        if ($ownerId) { Add-TokenAlias $primary $ownerId }
        if ($generic) { Add-TokenAlias $primary $generic }

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
                Add-TokenAlias $primary "$wItem-$pItem"
                Add-TokenAlias $primary "$wItem`_$pItem"
                Add-TokenAlias $primary "$wItem$pItem"
                Add-TokenAlias $primary "$wItem-A-$pItem"
                Add-TokenAlias $primary "$wItem-B-$pItem"
                Add-TokenAlias $primary "$wItem-P-$pItem"
                Add-TokenAlias $primary "$wItem`_A`_$pItem"
                Add-TokenAlias $primary "$wItem`_B`_$pItem"
                Add-TokenAlias $primary "$wItem`_P`_$pItem"
                if ($part) {
                    Add-TokenAlias $primary "$wItem-$pItem-$part"
                    Add-TokenAlias $primary "$wItem-$pItem`_$part"
                }
            }
        }
    }

    $ext = [System.IO.Path]::GetExtension($excelPath).ToLower()
    if ($ext -eq ".xlsx") {
        try {
            $zip = [System.IO.Compression.ZipFile]::OpenRead($excelPath)
            $sharedStrings = [System.Collections.Generic.List[string]]::new()
            $ssEntry = @($zip.Entries | Where-Object { $_.FullName.Replace('\', '/') -eq "xl/sharedStrings.xml" }) | Select-Object -First 1
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
            $sheetEntries = @($zip.Entries | Where-Object { $_.FullName.Replace('\', '/') -like "xl/worksheets/sheet*.xml" })
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
                    else { if ($rowVals.Count -gt 0) { Process-ItemRow -rowVals $rowVals } }
                }
            }
            $zip.Dispose()
        } catch { }
    }

    # Plain text / CSV fallback
    if ($propList.Count -eq 0 -and ($ext -eq ".csv" -or $ext -eq ".txt" -or $ext -eq ".tsv")) {
        try {
            $lines = [System.IO.File]::ReadAllLines($excelPath)
            if ($lines.Length -gt 0) {
                $delim = if ($lines[0].Contains("`t")) { "`t" } elseif ($lines[0].Contains(";")) { ";" } else { "," }
                foreach ($line in $lines) {
                    $cols = $line.Split($delim) | ForEach-Object { $_.Trim('"', ' ') }
                    $rowVals = @{}
                    for ($c = 0; $c -lt $cols.Length; $c++) { $rowVals["Col_$c"] = $cols[$c] }
                    Process-ItemRow -rowVals $rowVals
                }
            }
        } catch { }
    }

    return [PSCustomObject]@{
        PropList = $propList
        TokenMap = $tokenToPrimary
    }
}

# 4. Intelligent Matching Algorithm
function Find-MatchedPropertyKey($fileName, $tokenMap) {
    if (-not $tokenMap -or $tokenMap.Count -eq 0) { return $null }
    $nameNoExt = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
    if ($tokenMap.ContainsKey($nameNoExt)) { return $tokenMap[$nameNoExt] }

    $clean = $nameNoExt -replace '^(D_|DIMAJOR_|MAJOR_|MINOR_|WARD_|PRABHAG_|ZONE_|PHOTO_|PROP_|PLAN_|WMF_|PMC[-_]|IMG[-_]|PIC[-_]|--+)', ''
    if ($tokenMap.ContainsKey($clean)) { return $tokenMap[$clean] }

    foreach ($tok in $tokenMap.Keys) {
        if ($tok.Length -ge 2) {
            if ($nameNoExt.StartsWith("$tok`_", [System.StringComparison]::OrdinalIgnoreCase) -or
                $nameNoExt.StartsWith("$tok-", [System.StringComparison]::OrdinalIgnoreCase) -or
                $clean.StartsWith("$tok`_", [System.StringComparison]::OrdinalIgnoreCase) -or
                $clean.StartsWith("$tok-", [System.StringComparison]::OrdinalIgnoreCase)) {
                return $tokenMap[$tok]
            }
        }
    }

    $noSuffix = $clean -replace '([_\-\.]+(?:BK|R\d+|C\d+|REV\d*|front|rear|side|inside|outside|road|meter|top|back|plan|wmf|photo|img|pic|\d+|[A-Za-z]))*$', ''
    if ($noSuffix -and $tokenMap.ContainsKey($noSuffix)) { return $tokenMap[$noSuffix] }

    $dashClean = $clean -replace '[_\s]+', '-'
    if ($tokenMap.ContainsKey($dashClean)) { return $tokenMap[$dashClean] }

    if ($dashClean -match '^([A-Za-z0-9]+)[-_](\d+)') {
        $wCand = $Matches[1]; $pCand = $Matches[2]
        if ($tokenMap.ContainsKey("$wCand-$pCand")) { return $tokenMap["$wCand-$pCand"] }
        if ($pCand -match '^\d+$') {
            $pInt = [int]$pCand
            if ($tokenMap.ContainsKey("$wCand-$($pInt)")) { return $tokenMap["$wCand-$($pInt)"] }
        }
    }

    return $null
}

# 5. Build Desktop WPF User Interface
$desktopDir = [Environment]::GetFolderPath("Desktop")
$defaultDest = Join-Path $desktopDir "Collected_Property_Photos"

$xamlString = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PMC Property Asset &amp; WMF Plan Extractor (Desktop Standalone) v5.5"
        Width="920" Height="700" WindowStartupLocation="CenterScreen"
        Background="#060A14" Foreground="#F8FAFC" FontFamily="Segoe UI">
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Border Grid.Row="0" Background="#0B132B" CornerRadius="10" Padding="14,10" Margin="0,0,0,10" BorderBrush="#00F0FF" BorderThickness="1.5">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0">
                    <TextBlock Text="PMC PROPERTY ASSET &amp; WMF PLAN EXTRACTOR" FontSize="14" FontWeight="Bold" Foreground="#00F0FF"/>
                    <TextBlock Text="Direct Multi-Server / Ward Extraction to Desktop - Crystal Reports &lt;25KB Solid White Canvas" FontSize="10.5" Foreground="#94A3B8"/>
                </StackPanel>
                <Border Grid.Column="1" Background="#065F46" CornerRadius="4" Padding="8,4" VerticalAlignment="Center">
                    <TextBlock Text="STANDALONE DESKTOP EDITION" FontSize="10" FontWeight="Bold" Foreground="#34D399"/>
                </Border>
            </Grid>
        </Border>

        <!-- Step 1: Mode Selection -->
        <Border Grid.Row="1" Background="#0F172A" CornerRadius="8" Padding="12,8" Margin="0,0,0,8" BorderBrush="#1E293B" BorderThickness="1">
            <StackPanel>
                <TextBlock Text="1. EXTRACTION MODE" FontSize="11" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,6"/>
                <StackPanel Orientation="Horizontal">
                    <RadioButton x:Name="rbModePhotos" Content="Property Photos Only (.jpg, .png)" IsChecked="True" Foreground="White" FontWeight="SemiBold" Margin="0,0,16,0"/>
                    <RadioButton x:Name="rbModeWmf" Content="WMF Vector Plans Only (.wmf, .emf)" Foreground="White" FontWeight="SemiBold" Margin="0,0,16,0"/>
                    <RadioButton x:Name="rbModeBoth" Content="Both Photos &amp; WMF Plans" Foreground="White" FontWeight="SemiBold"/>
                </StackPanel>
            </StackPanel>
        </Border>

        <!-- Step 2: Source Server / Folder -->
        <Border Grid.Row="2" Background="#0F172A" CornerRadius="8" Padding="12,8" Margin="0,0,0,8" BorderBrush="#1E293B" BorderThickness="1">
            <StackPanel>
                <Grid Margin="0,0,0,4">
                    <TextBlock Text="2. SOURCE SERVER / NETWORK IMAGE FOLDER" FontSize="11" FontWeight="Bold" Foreground="#38BDF8"/>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                        <Button x:Name="btnPreset11" Content="Server 11 (Wards)" Background="#0D9488" Foreground="White" FontWeight="Bold" FontSize="9.5" Padding="6,2" Margin="0,0,4,0" BorderThickness="0" Cursor="Hand"/>
                        <Button x:Name="btnPreset22" Content="Server 22 (PMC)" Background="#0284C7" Foreground="White" FontWeight="Bold" FontSize="9.5" Padding="6,2" Margin="0,0,4,0" BorderThickness="0" Cursor="Hand"/>
                        <Button x:Name="btnPreset19" Content="Server 19 (Files)" Background="#4F46E5" Foreground="White" FontWeight="Bold" FontSize="9.5" Padding="6,2" BorderThickness="0" Cursor="Hand"/>
                    </StackPanel>
                </Grid>
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBox x:Name="txtSource" Grid.Column="0" Height="28" VerticalContentAlignment="Center" Background="#060A14" Foreground="#00F0FF" BorderBrush="#334155" Padding="6,2" FontSize="11" FontFamily="Consolas" Text="\\192.168.1.11\Panvel_PMC_All_Ward_Wise_Photo_Plan"/>
                    <Button x:Name="btnBrowseSource" Grid.Column="1" Content="Browse..." Background="#0284C7" Foreground="White" FontWeight="Bold" FontSize="10" Padding="12,2" Margin="6,0,0,0" BorderThickness="0" Cursor="Hand"/>
                </Grid>
            </StackPanel>
        </Border>

        <!-- Step 3 & 4: Excel Sheet & Output Folder -->
        <Grid Grid.Row="3" Margin="0,0,0,8">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="8"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- Excel Source -->
            <Border Grid.Column="0" Background="#0F172A" CornerRadius="8" Padding="12,8" BorderBrush="#1E293B" BorderThickness="1">
                <StackPanel>
                    <TextBlock Text="3. EXCEL / CSV WITH PROPERTY NUMBERS" FontSize="11" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,4"/>
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="txtExcel" Grid.Column="0" Height="28" VerticalContentAlignment="Center" Background="#060A14" Foreground="#FDE047" BorderBrush="#334155" Padding="6,2" FontSize="11" FontFamily="Consolas"/>
                        <Button x:Name="btnBrowseExcel" Grid.Column="1" Content="Browse..." Background="#0D9488" Foreground="White" FontWeight="Bold" FontSize="10" Padding="12,2" Margin="6,0,0,0" BorderThickness="0" Cursor="Hand"/>
                    </Grid>
                </StackPanel>
            </Border>

            <!-- Destination Folder -->
            <Border Grid.Column="2" Background="#0F172A" CornerRadius="8" Padding="12,8" BorderBrush="#1E293B" BorderThickness="1">
                <StackPanel>
                    <Grid Margin="0,0,0,4">
                        <TextBlock Text="4. OUTPUT DESTINATION FOLDER" FontSize="11" FontWeight="Bold" Foreground="#38BDF8"/>
                        <Button x:Name="btnResetDest" Content="Reset Desktop" Background="#334155" Foreground="#94A3B8" FontSize="9" Padding="4,1" HorizontalAlignment="Right" BorderThickness="0" Cursor="Hand"/>
                    </Grid>
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="txtDest" Grid.Column="0" Height="28" VerticalContentAlignment="Center" Background="#060A14" Foreground="#34D399" BorderBrush="#334155" Padding="6,2" FontSize="11" FontFamily="Consolas"/>
                        <Button x:Name="btnBrowseDest" Grid.Column="1" Content="Browse..." Background="#059669" Foreground="White" FontWeight="Bold" FontSize="10" Padding="12,2" Margin="6,0,0,0" BorderThickness="0" Cursor="Hand"/>
                    </Grid>
                </StackPanel>
            </Border>
        </Grid>

        <!-- Advanced Options & Counters -->
        <Border Grid.Row="4" Background="#0B1226" CornerRadius="8" Padding="12,6" Margin="0,0,0,8" BorderBrush="#1E3252" BorderThickness="1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                    <CheckBox x:Name="chkRecursive" Content="Scan Ward Folders Recursively" IsChecked="True" Foreground="#CBD5E1" FontWeight="SemiBold" Margin="0,0,12,0"/>
                    <CheckBox x:Name="chkSubfolders" Content="Create Property Subfolders" IsChecked="False" Foreground="#CBD5E1" FontWeight="SemiBold" Margin="0,0,12,0" ToolTip="Uncheck to dump all photos/plans directly into one flat desktop folder"/>
                    <CheckBox x:Name="chkWhiteCanvas" Content="Solid White Canvas &lt;25KB" IsChecked="True" Foreground="#34D399" FontWeight="Bold"/>
                </StackPanel>
                <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right">
                    <TextBlock Text="Total Excel: " Foreground="#94A3B8" FontSize="11"/>
                    <TextBlock x:Name="lblTotalProp" Text="0" Foreground="#FDE047" FontWeight="Bold" FontSize="11" Margin="0,0,10,0"/>
                    <TextBlock Text="Found: " Foreground="#94A3B8" FontSize="11"/>
                    <TextBlock x:Name="lblFoundProp" Text="0" Foreground="#34D399" FontWeight="Bold" FontSize="11" Margin="0,0,10,0"/>
                    <TextBlock Text="Collected: " Foreground="#94A3B8" FontSize="11"/>
                    <TextBlock x:Name="lblCollected" Text="0" Foreground="#00F0FF" FontWeight="Bold" FontSize="11"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Execution Log Console -->
        <Border Grid.Row="5" Background="#060A14" CornerRadius="8" BorderBrush="#1E293B" BorderThickness="1">
            <TextBox x:Name="txtLogs" Background="#060A14" Foreground="#E2E8F0" FontFamily="Consolas" FontSize="11"
                     IsReadOnly="True" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
                     BorderThickness="0" Padding="8" TextWrapping="NoWrap"/>
        </Border>

        <!-- Action Bar & Progress -->
        <Grid Grid.Row="6" Margin="0,8,0,0">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <ProgressBar x:Name="prgBar" Grid.Row="0" Height="6" Background="#1E293B" Foreground="#00F0FF" BorderThickness="0" Value="0" Margin="0,0,0,8"/>
            <Grid Grid.Row="1">
                <TextBlock x:Name="lblStatus" Text="Ready. Choose Excel file and click 'START EXTRACTION TO DESKTOP'." Foreground="#94A3B8" VerticalAlignment="Center" FontSize="11"/>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                    <Button x:Name="btnOpenReport" Content="OPEN REPORT" Background="#334155" Foreground="White" FontWeight="Bold" FontSize="10.5" Padding="12,6" Margin="0,0,6,0" BorderThickness="0" Cursor="Hand"/>
                    <Button x:Name="btnOpenDesktop" Content="OPEN OUTPUT FOLDER" Background="#0284C7" Foreground="White" FontWeight="Bold" FontSize="10.5" Padding="14,6" Margin="0,0,6,0" BorderThickness="0" Cursor="Hand"/>
                    <Button x:Name="btnStart" Content="START EXTRACTION TO DESKTOP" Background="#10B981" Foreground="White" FontWeight="Bold" FontSize="11.5" Padding="18,6" BorderThickness="0" Cursor="Hand"/>
                </StackPanel>
            </Grid>
        </Grid>
    </Grid>
</Window>
"@

$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xamlString))
$win = [System.Windows.Markup.XamlReader]::Load($reader)

# Get UI Control References
$rbModePhotos    = $win.FindName("rbModePhotos")
$rbModeWmf       = $win.FindName("rbModeWmf")
$rbModeBoth      = $win.FindName("rbModeBoth")
$txtSource       = $win.FindName("txtSource")
$btnBrowseSource = $win.FindName("btnBrowseSource")
$btnPreset11     = $win.FindName("btnPreset11")
$btnPreset22     = $win.FindName("btnPreset22")
$btnPreset19     = $win.FindName("btnPreset19")
$txtExcel        = $win.FindName("txtExcel")
$btnBrowseExcel  = $win.FindName("btnBrowseExcel")
$txtDest         = $win.FindName("txtDest")
$btnBrowseDest   = $win.FindName("btnBrowseDest")
$btnResetDest    = $win.FindName("btnResetDest")
$chkRecursive    = $win.FindName("chkRecursive")
$chkSubfolders   = $win.FindName("chkSubfolders")
$chkWhiteCanvas  = $win.FindName("chkWhiteCanvas")
$lblTotalProp    = $win.FindName("lblTotalProp")
$lblFoundProp    = $win.FindName("lblFoundProp")
$lblCollected    = $win.FindName("lblCollected")
$txtLogs         = $win.FindName("txtLogs")
$prgBar          = $win.FindName("prgBar")
$lblStatus       = $win.FindName("lblStatus")
$btnStart        = $win.FindName("btnStart")
$btnOpenDesktop  = $win.FindName("btnOpenDesktop")
$btnOpenReport   = $win.FindName("btnOpenReport")

$txtDest.Text = $defaultDest
$script:LastReportPath = $null

function Append-Log($msg) {
    $ts = (Get-Date).ToString("HH:mm:ss")
    $txtLogs.Dispatcher.Invoke([Action]{
        $txtLogs.AppendText("[$ts] $msg`r`n")
        $txtLogs.ScrollToEnd()
    })
}

# Presets
$btnPreset11.Add_Click({ $txtSource.Text = "\\192.168.1.11\Panvel_PMC_All_Ward_Wise_Photo_Plan"; Append-Log "Loaded Server 11 (All Ward Wise Photos & Plans)" })
$btnPreset22.Add_Click({ $txtSource.Text = "\\192.168.1.22\PMC_Photo_22\PropertyImage"; Append-Log "Loaded Server 22 (PMC Photos)" })
$btnPreset19.Add_Click({ $txtSource.Text = "\\192.168.1.19\Files\PropertyImage"; Append-Log "Loaded Server 19 (Files Master)" })

$btnBrowseSource.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Select Source Server / Network Image Folder"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $txtSource.Text = $dlg.SelectedPath }
})

$btnBrowseExcel.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "Select Excel / CSV File with Property Numbers"
    $dlg.Filter = "Excel & CSV Files (*.xlsx;*.xls;*.csv;*.txt)|*.xlsx;*.xls;*.csv;*.txt|All Files (*.*)|*.*"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $txtExcel.Text = $dlg.FileName }
})

$btnBrowseDest.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Select Destination Output Folder on Desktop"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $txtDest.Text = $dlg.SelectedPath }
})

$btnResetDest.Add_Click({
    $dt = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $txtDest.Text = Join-Path $desktopDir "Collected_Property_Photos_$dt"
})

$btnOpenDesktop.Add_Click({
    if (Test-Path -LiteralPath $txtDest.Text) { Start-Process "explorer.exe" -ArgumentList "`"$($txtDest.Text)`"" }
    else { [System.Windows.MessageBox]::Show("Destination folder does not exist yet.", "Notice", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) }
})

$btnOpenReport.Add_Click({
    if ($script:LastReportPath -and (Test-Path -LiteralPath $script:LastReportPath)) { Start-Process $script:LastReportPath }
    else { [System.Windows.MessageBox]::Show("Report not generated yet.", "Notice", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) }
})

# Start Extraction Engine
$btnStart.Add_Click({
    $src = $txtSource.Text.Trim()
    $excel = $txtExcel.Text.Trim()
    $dest = $txtDest.Text.Trim()

    if (-not $src -or -not (Test-Path -LiteralPath $src)) {
        [System.Windows.MessageBox]::Show("Source folder is not accessible:`n$src", "Folder Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }
    if (-not $excel -or -not (Test-Path -LiteralPath $excel)) {
        [System.Windows.MessageBox]::Show("Please select a valid Excel/CSV file with property numbers.", "Excel Required", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }
    if (-not (Test-Path -LiteralPath $dest)) {
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
    }

    $btnStart.IsEnabled = $false
    $txtLogs.Clear()
    $prgBar.Value = 5
    $lblStatus.Text = "Status: Parsing Excel property numbers..."
    [System.Windows.Forms.Application]::DoEvents()

    $mode = if ($rbModeWmf.IsChecked -eq $true) { "WMF" } elseif ($rbModeBoth.IsChecked -eq $true) { "Both" } else { "Photos" }
    Append-Log "======================================================="
    Append-Log "PMC DESKTOP PROPERTY EXTRACTOR STARTED ($mode Mode)"
    Append-Log "Source Folder  : $src"
    Append-Log "Excel File     : $excel"
    Append-Log "Destination    : $dest"
    Append-Log "Flat Directory : $(if (-not $chkSubfolders.IsChecked) {'YES (All photos directly into desktop folder)'} else {'Subfolders per property'})"
    Append-Log "======================================================="

    $pData = Get-SpreadsheetProperties $excel
    $propList = $pData.PropList
    $tokenMap = $pData.TokenMap

    $lblTotalProp.Text = $propList.Count.ToString()
    Append-Log "Loaded $($propList.Count) unique property identifiers ($($tokenMap.Count) search variations)."

    if ($propList.Count -eq 0) {
        [System.Windows.MessageBox]::Show("No property numbers found in Excel file.", "No Data", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        $btnStart.IsEnabled = $true
        return
    }

    $exts = if ($mode -eq "WMF") { @('.wmf', '.emf') }
            elseif ($mode -eq "Both") { @('.jpg', '.jpeg', '.png', '.bmp', '.tif', '.tiff', '.webp', '.wmf', '.emf') }
            else { @('.jpg', '.jpeg', '.png', '.bmp', '.tif', '.tiff', '.webp') }

    $prgBar.Value = 20
    $lblStatus.Text = "Status: Scanning server folders (including all ward folders)..."
    [System.Windows.Forms.Application]::DoEvents()

    $q = [System.Collections.Generic.Queue[string]]::new()
    $q.Enqueue($src)
    $visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $visited.Add($src) | Out-Null

    $matched = [System.Collections.Generic.List[PSCustomObject]]::new()
    $foundPropSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $scanCount = 0

    while ($q.Count -gt 0) {
        $curr = $q.Dequeue()
        $files = @()
        try { $files = [System.IO.Directory]::GetFiles($curr, "*.*") } catch { continue }

        foreach ($fl in $files) {
            $fExt = [System.IO.Path]::GetExtension($fl).ToLower()
            if (-not ($exts -contains $fExt)) { continue }

            $scanCount++
            $fn = [System.IO.Path]::GetFileName($fl)
            $pKey = Find-MatchedPropertyKey -fileName $fn -tokenMap $tokenMap

            if ($pKey) {
                $matched.Add([PSCustomObject]@{
                    SourcePath = $fl
                    FileName   = $fn
                    PropertyKey= $pKey
                    IsWmf      = ($fExt -eq ".wmf" -or $fExt -eq ".emf")
                })
                $foundPropSet.Add($pKey) | Out-Null
            }

            if ($scanCount % 250 -eq 0) {
                $lblStatus.Text = "Scanning server files ($scanCount scanned, $($matched.Count) matched)..."
                $lblCollected.Text = $matched.Count.ToString()
                $lblFoundProp.Text = $foundPropSet.Count.ToString()
                [System.Windows.Forms.Application]::DoEvents()
            }
        }

        if ($chkRecursive.IsChecked -eq $true) {
            try {
                foreach ($sd in [System.IO.Directory]::GetDirectories($curr)) {
                    $sdName = [System.IO.Path]::GetFileName($sd)
                    if ($sdName -notmatch '(?i)backup' -and -not $sdName.StartsWith('.') -and -not $visited.Contains($sd)) {
                        $visited.Add($sd) | Out-Null
                        $q.Enqueue($sd)
                    }
                }
            } catch {}
        }
    }

    Append-Log "Scan finished! Scanned $scanCount files. Found $($matched.Count) matching files across $($foundPropSet.Count) properties."
    $lblFoundProp.Text = $foundPropSet.Count.ToString()
    $lblCollected.Text = $matched.Count.ToString()

    if ($matched.Count -eq 0) {
        $lblStatus.Text = "Status: 0 matching files found."
        $prgBar.Value = 100
        [System.Windows.MessageBox]::Show("No matching photos/plans found in source folder for Excel properties.", "No Matches", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        $btnStart.IsEnabled = $true
        return
    }

    # Step 3: Copy Files to Desktop
    $lblStatus.Text = "Status: Copying and optimizing files to Desktop..."
    $copied = 0
    $total = $matched.Count

    for ($i = 0; $i -lt $total; $i++) {
        $item = $matched[$i]
        $targetDir = $dest
        if ($chkSubfolders.IsChecked -eq $true) {
            $targetDir = Join-Path $dest $item.PropertyKey
        }
        if (-not (Test-Path -LiteralPath $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }

        $destFile = Join-Path $targetDir $item.FileName
        if (Test-Path -LiteralPath $destFile) {
            $b = [System.IO.Path]::GetFileNameWithoutExtension($item.FileName)
            $e = [System.IO.Path]::GetExtension($item.FileName)
            $destFile = Join-Path $targetDir "${b}_$([System.Guid]::NewGuid().ToString().Substring(0,4))$e"
        }

        try {
            if ($item.IsWmf -and ($chkWhiteCanvas.IsChecked -eq $true)) {
                $flen = (Get-Item -LiteralPath $item.SourcePath).Length
                if ($flen -gt (25 * 1024)) {
                    $res = [StandaloneWmfOptimizer]::ProcessWmf($item.SourcePath, $destFile, 700, 96, 25, $true)
                    if ($res -and -not $res.StartsWith("ERROR")) { $copied++; continue }
                }
            }
            [System.IO.File]::Copy($item.SourcePath, $destFile, $true)
            $copied++
        } catch {
            Append-Log "Warning copying $($item.FileName): $($_.Exception.Message)"
        }

        if ($i % 50 -eq 0) {
            $pct = [int](20 + (($i / $total) * 75))
            $prgBar.Value = $pct
            $lblStatus.Text = "Copying files ($copied / $total)..."
            [System.Windows.Forms.Application]::DoEvents()
        }
    }

    $prgBar.Value = 100
    $lblStatus.Text = "Extraction Complete! $copied files saved to Desktop."
    Append-Log "SUCCESS! Extracted $copied files to Desktop destination folder."

    # Generate Summary Report
    $dtStr = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $repFile = Join-Path $dest "Extraction_Report_$dtStr.txt"
    $repContent = @"
======================================================================
PMC PROPERTY ASSET EXTRACTION SUMMARY REPORT
Generated At: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
======================================================================
Source Folder       : $src
Excel Sheet         : $excel
Destination         : $dest
Total in Excel      : $($propList.Count)
Found on Server     : $($foundPropSet.Count)
Files Collected     : $copied
======================================================================
"@
    [System.IO.File]::WriteAllText($repFile, $repContent)
    $script:LastReportPath = $repFile

    $btnStart.IsEnabled = $true
    $choice = [System.Windows.MessageBox]::Show("EXTRACTION COMPLETE!`r`n`r`nTotal Files Collected: $copied`r`nOutput Folder: $dest`r`n`r`nWould you like to open the output folder now?", "Extraction Finished", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Information)
    if ($choice -eq [System.Windows.MessageBoxResult]::Yes) {
        Start-Process "explorer.exe" -ArgumentList "`"$dest`""
    }
})

# Show Window
[void]$win.ShowDialog()
