<#
.SYNOPSIS
    Government Exam Photo, Signature, and PDF Resizer & Optimizer
    Meets official upload criteria for Central (UPSC, SSC, IBPS, RRB, NTA) and State (MPSC, MahaDBT, UPPSC, BPSC, etc.) Exams.

.EXAMPLE
    # Compress SSC photo between 20 KB and 50 KB (200x230 px)
    .\Resize-GovtExamFiles.ps1 -InputPath "photo.jpg" -Preset "SSC_Photo" -OutputPath "photo_ssc.jpg"

    # Compress UPSC / SSC PDF document between 100 KB and 300 KB
    .\Resize-GovtExamFiles.ps1 -InputPath "caste_certificate.pdf" -Preset "UPSC_PDF" -OutputPath "doc_upsc.pdf"

    # Convert multiple scanned images into single Exam PDF
    .\Resize-GovtExamFiles.ps1 -InputImages @("page1.jpg", "page2.jpg") -MinKB 100 -MaxKB 300 -OutputPath "combined.pdf"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$InputPath,

    [Parameter(Mandatory = $false)]
    [string[]]$InputImages,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [ValidateSet("SSC_Photo", "SSC_Signature", "UPSC_Photo", "UPSC_Signature", "UPSC_PDF", "IBPS_Thumb", "IBPS_Declaration", "NTA_Photo", "NTA_Signature", "MPSC_Photo", "MPSC_Signature", "MPSC_PDF", "Custom")]
    [string]$Preset = "SSC_Photo",

    [Parameter(Mandatory = $false)]
    [long]$MinKB = 20,

    [Parameter(Mandatory = $false)]
    [long]$MaxKB = 50,

    [Parameter(Mandatory = $false)]
    [int]$Width = 200,

    [Parameter(Mandatory = $false)]
    [int]$Height = 230,

    [Parameter(Mandatory = $false)]
    [float]$DPI = 96
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction SilentlyContinue

try {
    [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Pdf.PdfDocument, Windows.Data.Pdf, ContentType = WindowsRuntime] | Out-Null
    [Windows.Storage.Streams.InMemoryRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime] | Out-Null
} catch {}

# C# Engine
$csharp = @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Collections.Generic;
using System.Text;

public class CliGovtExamEngine
{
    public static ImageCodecInfo GetEncoder(ImageFormat format)
    {
        foreach (ImageCodecInfo codec in ImageCodecInfo.GetImageEncoders())
        {
            if (codec.FormatID == format.Guid) return codec;
        }
        return null;
    }

    public static byte[] CompressExamImage(Image original, int targetW, int targetH, long minBytes, long maxBytes, float dpi)
    {
        int finalW = targetW > 0 ? targetW : original.Width;
        int finalH = targetH > 0 ? targetH : original.Height;

        using (Bitmap canvas = new Bitmap(finalW, finalH, PixelFormat.Format24bppRgb))
        {
            canvas.SetResolution(dpi, dpi);
            using (Graphics g = Graphics.FromImage(canvas))
            {
                g.Clear(Color.White);
                g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.HighQuality;
                g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
                g.CompositingQuality = System.Drawing.Drawing2D.CompositingQuality.HighQuality;
                g.DrawImage(original, new Rectangle(0, 0, finalW, finalH));
            }

            ImageCodecInfo jpgEncoder = GetEncoder(ImageFormat.Jpeg);
            long lowQ = 5;
            long highQ = 98;
            byte[] bestBytes = null;

            for (int step = 0; step < 8; step++)
            {
                long midQ = (lowQ + highQ) / 2;
                EncoderParameters encParams = new EncoderParameters(1);
                encParams.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, midQ);

                byte[] testBytes;
                using (MemoryStream ms = new MemoryStream())
                {
                    canvas.Save(ms, jpgEncoder, encParams);
                    testBytes = ms.ToArray();
                }

                if (testBytes.Length <= maxBytes)
                {
                    bestBytes = testBytes;
                    if (testBytes.Length >= minBytes)
                    {
                        lowQ = midQ + 1;
                    }
                    else
                    {
                        lowQ = midQ + 1;
                    }
                }
                else
                {
                    highQ = midQ - 1;
                }
            }

            if (bestBytes == null)
            {
                EncoderParameters encParams = new EncoderParameters(1);
                encParams.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, 5L);
                using (MemoryStream ms = new MemoryStream())
                {
                    canvas.Save(ms, jpgEncoder, encParams);
                    bestBytes = ms.ToArray();
                }
            }

            return bestBytes;
        }
    }

    public static byte[] BuildExamPdf(List<Bitmap> pages, long minBytes, long maxBytes, float dpi)
    {
        if (pages == null || pages.Count == 0) return new byte[0];

        long lowQ = 5;
        long highQ = 95;
        byte[] bestPdf = null;
        ImageCodecInfo jpgEncoder = GetEncoder(ImageFormat.Jpeg);

        for (int step = 0; step < 8; step++)
        {
            long midQ = (lowQ + highQ) / 2;
            List<byte[]> jpgList = new List<byte[]>();
            List<Size> sizeList = new List<Size>();

            EncoderParameters encParams = new EncoderParameters(1);
            encParams.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, midQ);

            foreach (Bitmap page in pages)
            {
                using (MemoryStream ms = new MemoryStream())
                {
                    page.Save(ms, jpgEncoder, encParams);
                    jpgList.Add(ms.ToArray());
                    int ptW = (int)Math.Max(1, Math.Round(page.Width * 72.0f / dpi));
                    int ptH = (int)Math.Max(1, Math.Round(page.Height * 72.0f / dpi));
                    sizeList.Add(new Size(ptW, ptH));
                }
            }

            byte[] pdfBytes = AssemblePdf(jpgList, sizeList, pages);

            if (pdfBytes.Length <= maxBytes)
            {
                bestPdf = pdfBytes;
                if (pdfBytes.Length >= minBytes)
                {
                    lowQ = midQ + 1;
                }
                else
                {
                    lowQ = midQ + 1;
                }
            }
            else
            {
                highQ = midQ - 1;
            }
        }

        if (bestPdf == null)
        {
            List<byte[]> jpgList = new List<byte[]>();
            List<Size> sizeList = new List<Size>();
            EncoderParameters encParams = new EncoderParameters(1);
            encParams.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, 5L);

            foreach (Bitmap page in pages)
            {
                using (MemoryStream ms = new MemoryStream())
                {
                    page.Save(ms, jpgEncoder, encParams);
                    jpgList.Add(ms.ToArray());
                    int ptW = (int)Math.Max(1, Math.Round(page.Width * 72.0f / dpi));
                    int ptH = (int)Math.Max(1, Math.Round(page.Height * 72.0f / dpi));
                    sizeList.Add(new Size(ptW, ptH));
                }
            }
            bestPdf = AssemblePdf(jpgList, sizeList, pages);
        }

        return bestPdf;
    }

    private static byte[] AssemblePdf(List<byte[]> jpegImages, List<Size> pageSizes, List<Bitmap> pixelSizes)
    {
        using (MemoryStream ms = new MemoryStream())
        {
            List<long> offsets = new List<long>();
            StreamWriter writer = new StreamWriter(ms, Encoding.ASCII);
            writer.Write("%PDF-1.4\r\n%\xE2\xE3\xCF\xD3\r\n");
            writer.Flush();

            int numPages = jpegImages.Count;
            offsets.Add(0);

            offsets.Add(ms.Position);
            writer.Write("1 0 obj\r\n<< /Type /Catalog /Pages 2 0 R >>\r\nendobj\r\n");
            writer.Flush();

            offsets.Add(ms.Position);
            StringBuilder kids = new StringBuilder();
            for (int i = 0; i < numPages; i++) kids.Append((3 + i * 3) + " 0 R ");
            writer.Write("2 0 obj\r\n<< /Type /Pages /Kids [" + kids.ToString().Trim() + "] /Count " + numPages + " >>\r\nendobj\r\n");
            writer.Flush();

            for (int i = 0; i < numPages; i++)
            {
                int pageObjId = 3 + i * 3;
                int imgObjId = 4 + i * 3;
                int contentObjId = 5 + i * 3;
                Size ptSz = pageSizes[i];
                Bitmap pxBmp = pixelSizes[i];
                byte[] imgData = jpegImages[i];

                offsets.Add(ms.Position);
                writer.Write(pageObjId + " 0 obj\r\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 " + ptSz.Width + " " + ptSz.Height + "] /Resources << /XObject << /Im" + i + " " + imgObjId + " 0 R >> >> /Contents " + contentObjId + " 0 R >>\r\nendobj\r\n");
                writer.Flush();

                offsets.Add(ms.Position);
                writer.Write(imgObjId + " 0 obj\r\n<< /Type /XObject /Subtype /Image /Width " + pxBmp.Width + " /Height " + pxBmp.Height + " /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length " + imgData.Length + " >>\r\nstream\r\n");
                writer.Flush();
                ms.Write(imgData, 0, imgData.Length);
                writer.Write("\r\nendstream\r\nendobj\r\n");
                writer.Flush();

                string content = string.Format(System.Globalization.CultureInfo.InvariantCulture, "q {0} 0 0 {1} 0 0 cm /Im{2} Do Q", ptSz.Width, ptSz.Height, i);
                byte[] contentBytes = Encoding.ASCII.GetBytes(content);
                offsets.Add(ms.Position);
                writer.Write(contentObjId + " 0 obj\r\n<< /Length " + contentBytes.Length + " >>\r\nstream\r\n" + content + "\r\nendstream\r\nendobj\r\n");
                writer.Flush();
            }

            long xrefOffset = ms.Position;
            int totalObjs = 2 + numPages * 3;
            writer.Write("xref\r\n0 " + (totalObjs + 1) + "\r\n");
            writer.Write("0000000000 65535 f \r\n");
            for (int i = 1; i <= totalObjs; i++) writer.Write(offsets[i].ToString("D10") + " 00000 n \r\n");
            writer.Write("trailer\r\n<< /Size " + (totalObjs + 1) + " /Root 1 0 R >>\r\nstartxref\r\n" + xrefOffset + "\r\n%%EOF\r\n");
            writer.Flush();

            return ms.ToArray();
        }
    }
}
"@

Add-Type -TypeDefinition $csharp -ReferencedAssemblies "System.Drawing"

# Apply Preset Settings
$isPdf = $false
switch ($Preset) {
    "SSC_Photo"        { $MinKB = 20;  $MaxKB = 50;  $Width = 200;  $Height = 230; $isPdf = $false }
    "SSC_Signature"    { $MinKB = 10;  $MaxKB = 20;  $Width = 140;  $Height = 60;  $isPdf = $false }
    "UPSC_Photo"       { $MinKB = 20;  $MaxKB = 300; $Width = 550;  $Height = 700; $isPdf = $false }
    "UPSC_Signature"   { $MinKB = 20;  $MaxKB = 300; $Width = 600;  $Height = 300; $isPdf = $false }
    "UPSC_PDF"         { $MinKB = 100; $MaxKB = 300; $Width = 1200; $Height = 1600; $isPdf = $true }
    "IBPS_Thumb"       { $MinKB = 20;  $MaxKB = 50;  $Width = 240;  $Height = 240; $isPdf = $false }
    "IBPS_Declaration" { $MinKB = 50;  $MaxKB = 100; $Width = 800;  $Height = 400; $isPdf = $false }
    "NTA_Photo"        { $MinKB = 10;  $MaxKB = 200; $Width = 400;  $Height = 500; $isPdf = $false }
    "NTA_Signature"    { $MinKB = 4;   $MaxKB = 30;  $Width = 200;  $Height = 100; $isPdf = $false }
    "MPSC_Photo"       { $MinKB = 20;  $MaxKB = 50;  $Width = 160;  $Height = 200; $isPdf = $false }
    "MPSC_Signature"   { $MinKB = 10;  $MaxKB = 20;  $Width = 256;  $Height = 64;  $isPdf = $false }
    "MPSC_PDF"         { $MinKB = 100; $MaxKB = 500; $Width = 1200; $Height = 1600; $isPdf = $true }
}

$minBytes = $MinKB * 1024
$maxBytes = $MaxKB * 1024

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " GOVERNMENT EXAM PHOTO & PDF RESIZER" -ForegroundColor White
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Preset: $Preset | Target Size: $MinKB KB - $MaxKB KB | Resolution: ${Width}x${Height} px" -ForegroundColor Gray

if ($isPdf -or ($InputPath -and $InputPath.EndsWith(".pdf")) -or ($InputImages -and $InputImages.Count -gt 0)) {
    # PDF generation or PDF recompression
    $pageBitmaps = [System.Collections.Generic.List[System.Drawing.Bitmap]]::new()
    
    if ($InputImages -and $InputImages.Count -gt 0) {
        foreach ($imgFile in $InputImages) {
            if (Test-Path $imgFile) {
                $img = [System.Drawing.Image]::FromFile($imgFile)
                $bmp = New-Object System.Drawing.Bitmap $img
                $pageBitmaps.Add($bmp)
                $img.Dispose()
            }
        }
    } elseif ($InputPath -and $InputPath.EndsWith(".pdf")) {
        $asTaskOp = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
            $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetGenericArguments().Length -eq 1 -and $_.GetParameters().Length -eq 1
        })[0]
        $asTaskAction = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
            $_.Name -eq 'AsTask' -and (-not $_.IsGenericMethod) -and $_.GetParameters().Length -eq 1
        })[0]
        $netStreamMethod = [System.IO.WindowsRuntimeStreamExtensions].GetMethod('AsStreamForRead', [Type[]]@([Windows.Storage.Streams.IInputStream]))

        $fileOp = [Windows.Storage.StorageFile]::GetFileFromPathAsync((Convert-Path $InputPath))
        $storageFile = $asTaskOp.MakeGenericMethod([Windows.Storage.StorageFile]).Invoke($null, @($fileOp)).Result
        $docOp = [Windows.Data.Pdf.PdfDocument]::LoadFromFileAsync($storageFile)
        $pdfDoc = $asTaskOp.MakeGenericMethod([Windows.Data.Pdf.PdfDocument]).Invoke($null, @($docOp)).Result

        for ($i = 0; $i -lt $pdfDoc.PageCount; $i++) {
            $page = $pdfDoc.GetPage($i)
            $stream = [Windows.Storage.Streams.InMemoryRandomAccessStream]::new()
            $options = [Windows.Data.Pdf.PdfPageRenderOptions]::new()
            $options.DestinationWidth = [uint32]$Width
            $renderOp = $page.RenderToStreamAsync($stream, $options)
            $asTaskAction.Invoke($null, @($renderOp)).Wait()
            $netStream = $netStreamMethod.Invoke($null, @($stream))
            $bmp = [System.Drawing.Bitmap]::FromStream($netStream)
            $pageBitmaps.Add((New-Object System.Drawing.Bitmap $bmp))
            $bmp.Dispose(); $netStream.Dispose(); $stream.Dispose(); $page.Dispose()
        }
    }

    if ($pageBitmaps.Count -eq 0) {
        Write-Error "No valid pages or images provided to create PDF."
        return
    }

    $outBytes = [CliGovtExamEngine]::BuildExamPdf($pageBitmaps, $minBytes, $maxBytes, 150)
    foreach ($b in $pageBitmaps) { $b.Dispose() }

    if (-not $OutputPath) { $OutputPath = "GovtExam_Optimized.pdf" }
    [System.IO.File]::WriteAllBytes($OutputPath, $outBytes)
    $finalKB = [Math]::Round($outBytes.Length / 1KB, 1)
    Write-Host "[SUCCESS] Generated PDF: $OutputPath ($finalKB KB)" -ForegroundColor Green
} else {
    if (-not $InputPath -or -not (Test-Path $InputPath)) {
        Write-Error "Please provide a valid -InputPath"
        return
    }
    $raw = [System.IO.File]::ReadAllBytes($InputPath)
    $ms = [System.IO.MemoryStream]::new($raw)
    $img = [System.Drawing.Image]::FromStream($ms)
    $outBytes = [CliGovtExamEngine]::CompressExamImage($img, $Width, $Height, $minBytes, $maxBytes, $DPI)
    $img.Dispose()
    $ms.Dispose()

    if (-not $OutputPath) { $OutputPath = "GovtExam_Optimized.jpg" }
    [System.IO.File]::WriteAllBytes($OutputPath, $outBytes)
    $finalKB = [Math]::Round($outBytes.Length / 1KB, 1)
    Write-Host "[SUCCESS] Generated Image: $OutputPath ($finalKB KB)" -ForegroundColor Green
}
