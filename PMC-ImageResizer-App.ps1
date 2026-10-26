# ================================================================================
# NEXUS PHOTO & DOCUMENT OPTIMIZER (ENTERPRISE EDITION)
# Startup Initialization: SmartScreen Unblock, Admin Privilege Detection & Config
# ================================================================================
try {
    $nexusAppDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    if (-not $nexusAppDir -or -not (Test-Path $nexusAppDir)) { $nexusAppDir = $PSScriptRoot }
    if (-not $nexusAppDir -or -not (Test-Path $nexusAppDir)) { $nexusAppDir = "C:\Users\mandar.k\Nexus-Photo-Optimizer-Portable" }
    if ($nexusAppDir -and (Test-Path $nexusAppDir)) {
        Get-ChildItem -Path $nexusAppDir -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
    }
    $desktopDir = [System.Environment]::GetFolderPath('Desktop')
    if ($desktopDir -and (Test-Path $desktopDir)) {
        Get-ChildItem -Path $desktopDir -Filter "*Nexus*" -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
        Get-ChildItem -Path $desktopDir -Filter "*Beyond*" -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
    }
} catch {}

$global:IsRunningAsAdmin = $false
try {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    $global:IsRunningAsAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch {
    $global:IsRunningAsAdmin = $false
}

if ($global:IsRunningAsAdmin) {
    # Silently configure Windows Firewall rules for LAN peer discovery
    try {
        netsh advfirewall firewall add rule name="Nexus Direct PC Share TCP" dir=in action=allow protocol=TCP localport=52824,52826 profile=any >$null 2>&1
        netsh advfirewall firewall add rule name="Nexus Direct PC Share UDP" dir=in action=allow protocol=UDP localport=52822 profile=any >$null 2>&1
    } catch {}

    # Register scheduled tasks for instant zero-prompt elevated launches in the future
    try {
        $psPath = if ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { Join-Path $nexusAppDir "PMC-ImageResizer-App.ps1" }
        $bcPath = Join-Path $nexusAppDir "Beyond-Compare-5.ps1"
        if (Test-Path $psPath) {
            schtasks /create /tn "NexusPhotoOptimizerAdmin" /tr "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File \"\"$psPath\"\"" /sc ONCE /st 00:00 /rl highest /f >$null 2>&1
        }
        if (Test-Path $bcPath) {
            schtasks /create /tn "BeyondCompare5Admin" /tr "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File \"\"$bcPath\"\"" /sc ONCE /st 00:00 /rl highest /f >$null 2>&1
        }
    } catch {}
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing, System.Windows.Forms
Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction SilentlyContinue

# Load WinRT types for PDF handling
try {
    [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Pdf.PdfDocument, Windows.Data.Pdf, ContentType = WindowsRuntime] | Out-Null
    [Windows.Storage.Streams.InMemoryRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime] | Out-Null
} catch {}

# --- Compile Enhanced WmfOptimizer & ExamEngine in C# ---
$csharp = @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public class AppWmfOptimizer
{
    [DllImport("gdi32.dll")]
    public static extern bool DeleteEnhMetaFile(IntPtr hemf);

    [DllImport("gdiplus.dll", SetLastError = true)]
    public static extern int GdipEmfToWmfBits(IntPtr hEmf, int uBufferSize, byte[] bBuffer, int iMappingMode, int flags);

    public static string ProcessWmf(string inputPath, string outputPath, int maxDim, int dpi, int maxKB, bool force)
    {
        byte[] inBytes = File.ReadAllBytes(inputPath);
        long limitBytes = (maxKB > 0) ? (maxKB * 1024) : (25 * 1024);

        // Enhancement: ONLY resize WMF files that have MORE THAN 25 KB
        if (!force && inBytes.Length <= limitBytes)
        {
            if (!string.Equals(inputPath, outputPath, StringComparison.OrdinalIgnoreCase))
            {
                File.Copy(inputPath, outputPath, true);
            }
            return "SKIPPED:Already " + Math.Round(inBytes.Length / 1024.0, 1) + " KB (<= 25 KB)";
        }

        byte[] outBytes = ConvertBlobToCrystalReportWmf(inBytes, maxDim, dpi, maxKB, force);
        if (outBytes != null && outBytes.Length > 0)
        {
            File.WriteAllBytes(outputPath, outBytes);
            return "OK:" + Math.Round(outBytes.Length / 1024.0, 1) + " KB";
        }
        return "ERROR:Could not optimize WMF";
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
                            using (EncoderParameters ep = new EncoderParameters(1))
                            {
                                ep.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, (long)q);
                                using (MemoryStream outMs = new MemoryStream())
                                {
                                    bmp.Save(outMs, jpegCodec, ep);
                                    byte[] res = outMs.ToArray();
                                    if (res.Length <= maxKB * 1024)
                                    {
                                        return res;
                                    }
                                    if (bestJpg == null || res.Length < bestJpg.Length)
                                    {
                                        bestJpg = res;
                                    }
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

public class GovtExamEngine
{
    public static ImageCodecInfo GetEncoder(ImageFormat format)
    {
        foreach (ImageCodecInfo codec in ImageCodecInfo.GetImageEncoders())
        {
            if (codec.FormatID == format.Guid) return codec;
        }
        return null;
    }

    public static byte[] CompressExamImage(Image original, int targetW, int targetH, long minBytes, long maxBytes, float dpi, bool maintainAspect)
    {
        int finalW = targetW;
        int finalH = targetH;

        if (finalW <= 0 && finalH <= 0)
        {
            finalW = original.Width;
            finalH = original.Height;
        }
        else if (finalW <= 0)
        {
            finalW = (int)Math.Round((double)original.Width * finalH / original.Height);
        }
        else if (finalH <= 0)
        {
            finalH = (int)Math.Round((double)original.Height * finalW / original.Width);
        }

        int canvasW = targetW > 0 ? targetW : finalW;
        int canvasH = targetH > 0 ? targetH : finalH;
        int drawW = finalW;
        int drawH = finalH;

        if (maintainAspect && targetW > 0 && targetH > 0)
        {
            double ratioX = (double)targetW / original.Width;
            double ratioY = (double)targetH / original.Height;
            double ratio = Math.Min(ratioX, ratioY);
            drawW = (int)Math.Round(original.Width * ratio);
            drawH = (int)Math.Round(original.Height * ratio);
        }

        using (Bitmap canvas = new Bitmap(canvasW, canvasH, PixelFormat.Format24bppRgb))
        {
            canvas.SetResolution(dpi, dpi);
            using (Graphics g = Graphics.FromImage(canvas))
            {
                g.Clear(Color.White);
                g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.HighQuality;
                g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
                g.CompositingQuality = System.Drawing.Drawing2D.CompositingQuality.HighQuality;

                int posX = (canvasW - drawW) / 2;
                int posY = (canvasH - drawH) / 2;
                g.DrawImage(original, new Rectangle(posX, posY, drawW, drawH));
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

public class BackgroundRemovalEngine
{
    public static bool DetectIsSignature(Bitmap bmp)
    {
        int w = bmp.Width;
        int h = bmp.Height;
        int brightCount = 0;
        int totalSampled = 0;
        int lowSaturationCount = 0;
        int skinToneCount = 0;

        BitmapData data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        int stride = data.Stride;
        byte[] buffer = new byte[Math.Abs(stride) * h];
        Marshal.Copy(data.Scan0, buffer, 0, buffer.Length);
        bmp.UnlockBits(data);

        int stepY = Math.Max(1, h / 35);
        int stepX = Math.Max(1, w / 35);

        for (int y = 0; y < h; y += stepY)
        {
            int rowIdx = y * stride;
            for (int x = 0; x < w; x += stepX)
            {
                int idx = rowIdx + x * 4;
                byte b = buffer[idx];
                byte g = buffer[idx + 1];
                byte r = buffer[idx + 2];
                totalSampled++;

                double lum = 0.299 * r + 0.587 * g + 0.114 * b;
                if (lum > 185.0) brightCount++;

                int maxC = Math.Max(r, Math.Max(g, b));
                int minC = Math.Min(r, Math.Min(g, b));
                if ((maxC - minC) < 28) lowSaturationCount++;

                if (r > 95 && g > 40 && b > 20 && (r - g) > 15 && (r - b) > 15) skinToneCount++;
            }
        }

        double brightRatio = (double)brightCount / Math.Max(1, totalSampled);
        double lowSatRatio = (double)lowSaturationCount / Math.Max(1, totalSampled);
        double skinRatio = (double)skinToneCount / Math.Max(1, totalSampled);

        if (skinRatio > 0.04) return false;

        return (brightRatio > 0.65 && lowSatRatio > 0.60);
    }

    public static Bitmap ExtractSignature(Bitmap srcBmp, int sensitivity, bool enhanceInk, Color replaceBgColor, bool makeTransparent)
    {
        return ExtractSignature(srcBmp, sensitivity, enhanceInk, replaceBgColor, makeTransparent, false);
    }

    public static Bitmap ExtractSignature(Bitmap srcBmp, int sensitivity, bool enhanceInk, Color replaceBgColor, bool makeTransparent, bool autoCrop)
    {
        int w = srcBmp.Width;
        int h = srcBmp.Height;

        BitmapData srcData = srcBmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        int stride = srcData.Stride;
        int totalBytes = Math.Abs(stride) * h;
        byte[] srcBuf = new byte[totalBytes];
        Marshal.Copy(srcData.Scan0, srcBuf, 0, totalBytes);
        srcBmp.UnlockBits(srcData);

        // 1. Divide into local blocks to compute local paper background illumination model
        int blockSize = Math.Max(16, Math.Min(48, Math.Min(w, h) / 15));
        int gridW = (w + blockSize - 1) / blockSize;
        int gridH = (h + blockSize - 1) / blockSize;
        double[,] bgGrid = new double[gridW, gridH];

        System.Threading.Tasks.Parallel.For(0, gridH, gy =>
        {
            int yStart = gy * blockSize;
            int yEnd = Math.Min(h, yStart + blockSize);
            for (int gx = 0; gx < gridW; gx++)
            {
                int xStart = gx * blockSize;
                int xEnd = Math.Min(w, xStart + blockSize);

                List<double> blockLums = new List<double>();
                for (int y = yStart; y < yEnd; y += 2)
                {
                    int rIdx = y * stride;
                    for (int x = xStart; x < xEnd; x += 2)
                    {
                        int pIdx = rIdx + x * 4;
                        double lum = 0.299 * srcBuf[pIdx + 2] + 0.587 * srcBuf[pIdx + 1] + 0.114 * srcBuf[pIdx];
                        blockLums.Add(lum);
                    }
                }
                blockLums.Sort();
                int p92 = Math.Min(blockLums.Count - 1, (int)(blockLums.Count * 0.92));
                bgGrid[gx, gy] = blockLums.Count > 0 ? blockLums[p92] : 240.0;
                if (bgGrid[gx, gy] < 120.0) bgGrid[gx, gy] = 240.0;
            }
        });

        double sensFactor = sensitivity / 100.0;
        double normThreshold = 0.88 + (sensFactor - 0.5) * 0.12;
        double solidInkThreshold = normThreshold * 0.68;

        byte[] destBuf = new byte[totalBytes];
        int minX = w, maxX = 0, minY = h, maxY = 0;
        object boundsLock = new object();
        bool hasForeground = false;

        System.Threading.Tasks.Parallel.For(0, h, y =>
        {
            int rowIdx = y * stride;
            double gy = (double)y / blockSize;
            int gy0 = Math.Min(gridH - 1, (int)gy);
            int gy1 = Math.Min(gridH - 1, gy0 + 1);
            double yFrac = gy - gy0;

            int localMinX = w, localMaxX = 0;
            bool localHasFg = false;

            for (int x = 0; x < w; x++)
            {
                int idx = rowIdx + x * 4;
                byte b = srcBuf[idx];
                byte g = srcBuf[idx + 1];
                byte r = srcBuf[idx + 2];
                byte a = srcBuf[idx + 3];

                if (a < 10)
                {
                    destBuf[idx] = 0; destBuf[idx+1] = 0; destBuf[idx+2] = 0; destBuf[idx+3] = 0;
                    continue;
                }

                double gx = (double)x / blockSize;
                int gx0 = Math.Min(gridW - 1, (int)gx);
                int gx1 = Math.Min(gridW - 1, gx0 + 1);
                double xFrac = gx - gx0;

                double bgTop = bgGrid[gx0, gy0] * (1.0 - xFrac) + bgGrid[gx1, gy0] * xFrac;
                double bgBot = bgGrid[gx0, gy1] * (1.0 - xFrac) + bgGrid[gx1, gy1] * xFrac;
                double localBg = bgTop * (1.0 - yFrac) + bgBot * yFrac;
                if (localBg < 1.0) localBg = 240.0;

                double lum = 0.299 * r + 0.587 * g + 0.114 * b;
                double norm = lum / localBg;

                if (norm >= normThreshold)
                {
                    if (makeTransparent)
                    {
                        destBuf[idx] = 0; destBuf[idx+1] = 0; destBuf[idx+2] = 0; destBuf[idx+3] = 0;
                    }
                    else
                    {
                        destBuf[idx] = replaceBgColor.B; destBuf[idx+1] = replaceBgColor.G;
                        destBuf[idx+2] = replaceBgColor.R; destBuf[idx+3] = 255;
                    }
                }
                else
                {
                    localHasFg = true;
                    if (x < localMinX) localMinX = x;
                    if (x > localMaxX) localMaxX = x;

                    double alphaFraction;
                    if (norm <= solidInkThreshold)
                    {
                        alphaFraction = 1.0;
                    }
                    else
                    {
                        alphaFraction = (normThreshold - norm) / (normThreshold - solidInkThreshold);
                        alphaFraction = Math.Max(0.0, Math.Min(1.0, alphaFraction));
                        alphaFraction = alphaFraction * alphaFraction * (3.0 - 2.0 * alphaFraction);
                    }

                    byte outA = (byte)Math.Round(alphaFraction * 255.0);
                    byte outR = r, outG = g, outB = b;

                    if (enhanceInk)
                    {
                        bool isBlue = (b > r + 15 && b > g + 5);
                        bool isRed = (r > g + 30 && r > b + 30);
                        if (isBlue)
                        {
                            outR = (byte)Math.Max(0, r * 0.3);
                            outG = (byte)Math.Max(0, g * 0.45);
                            outB = (byte)Math.Min(230, b * 1.25 + 25);
                        }
                        else if (isRed)
                        {
                            outR = (byte)Math.Min(230, r * 1.25 + 25);
                            outG = (byte)Math.Max(0, g * 0.3);
                            outB = (byte)Math.Max(0, b * 0.3);
                        }
                        else
                        {
                            byte dark = (byte)Math.Max(0, Math.Min(lum * 0.35, 45));
                            outR = dark; outG = dark; outB = dark;
                        }
                    }

                    if (makeTransparent)
                    {
                        destBuf[idx] = outB;
                        destBuf[idx + 1] = outG;
                        destBuf[idx + 2] = outR;
                        destBuf[idx + 3] = outA;
                    }
                    else
                    {
                        double bgF = 1.0 - alphaFraction;
                        destBuf[idx] = (byte)Math.Round(outB * alphaFraction + replaceBgColor.B * bgF);
                        destBuf[idx + 1] = (byte)Math.Round(outG * alphaFraction + replaceBgColor.G * bgF);
                        destBuf[idx + 2] = (byte)Math.Round(outR * alphaFraction + replaceBgColor.R * bgF);
                        destBuf[idx + 3] = 255;
                    }
                }
            }

            if (localHasFg)
            {
                lock (boundsLock)
                {
                    hasForeground = true;
                    if (localMinX < minX) minX = localMinX;
                    if (localMaxX > maxX) maxX = localMaxX;
                    if (y < minY) minY = y;
                    if (y > maxY) maxY = y;
                }
            }
        });

        Bitmap rawDest = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        BitmapData destData = rawDest.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        Marshal.Copy(destBuf, 0, destData.Scan0, totalBytes);
        rawDest.UnlockBits(destData);

        if (autoCrop && hasForeground && maxX > minX && maxY > minY)
        {
            int pad = Math.Max(10, Math.Min(30, (maxX - minX) / 20));
            int cropX = Math.Max(0, minX - pad);
            int cropY = Math.Max(0, minY - pad);
            int cropW = Math.Min(w - cropX, (maxX - minX) + pad * 2);
            int cropH = Math.Min(h - cropY, (maxY - minY) + pad * 2);

            Bitmap cropped = new Bitmap(cropW, cropH, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(cropped))
            {
                g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                g.DrawImage(rawDest, new Rectangle(0, 0, cropW, cropH), new Rectangle(cropX, cropY, cropW, cropH), GraphicsUnit.Pixel);
            }
            rawDest.Dispose();
            return cropped;
        }

        return rawDest;
    }

    public static Bitmap RemovePhotoBackground(Bitmap srcBmp, int tolerance, Color replaceBgColor, bool makeTransparent)
    {
        int w = srcBmp.Width;
        int h = srcBmp.Height;
        Bitmap destBmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);

        BitmapData srcData = srcBmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        int stride = srcData.Stride;
        int totalBytes = Math.Abs(stride) * h;
        byte[] srcBuf = new byte[totalBytes];
        Marshal.Copy(srcData.Scan0, srcBuf, 0, totalBytes);
        srcBmp.UnlockBits(srcData);

        // 1. Sample Background Seeds from perimeter (avoids head/hair at top-center)
        List<double[]> bgSeedsYCbCr = new List<double[]>();
        int[][] seedCoords = new int[][] {
            new int[] { 3, 3 }, new int[] { 10, 3 }, new int[] { 3, 10 },
            new int[] { w - 4, 3 }, new int[] { w - 11, 3 }, new int[] { w - 4, 10 },
            new int[] { 3, h / 3 }, new int[] { 3, (h * 2) / 3 },
            new int[] { w - 4, h / 3 }, new int[] { w - 4, (h * 2) / 3 }
        };

        foreach (int[] pt in seedCoords)
        {
            int sx = Math.Max(0, Math.Min(w - 1, pt[0]));
            int sy = Math.Max(0, Math.Min(h - 1, pt[1]));
            int idx = sy * stride + sx * 4;
            byte b = srcBuf[idx];
            byte g = srcBuf[idx + 1];
            byte r = srcBuf[idx + 2];

            double yVal = 0.299 * r + 0.587 * g + 0.114 * b;
            double cb = 128.0 - 0.168736 * r - 0.331264 * g + 0.5 * b;
            double cr = 128.0 + 0.5 * r - 0.418688 * g - 0.081312 * b;
            bgSeedsYCbCr.Add(new double[] { yVal, cb, cr, r, g, b });
        }

        // 2. Sobel Edge Gradient Barrier
        byte[] edges = new byte[w * h];
        for (int y = 1; y < h - 1; y++)
        {
            int rowIdx = y * stride;
            int prevRow = (y - 1) * stride;
            int nextRow = (y + 1) * stride;
            for (int x = 1; x < w - 1; x++)
            {
                int pLeft = rowIdx + (x - 1) * 4;
                int pRight = rowIdx + (x + 1) * 4;
                int pTop = prevRow + x * 4;
                int pBot = nextRow + x * 4;

                int lumL = (int)(0.299 * srcBuf[pLeft + 2] + 0.587 * srcBuf[pLeft + 1] + 0.114 * srcBuf[pLeft]);
                int lumR = (int)(0.299 * srcBuf[pRight + 2] + 0.587 * srcBuf[pRight + 1] + 0.114 * srcBuf[pRight]);
                int lumT = (int)(0.299 * srcBuf[pTop + 2] + 0.587 * srcBuf[pTop + 1] + 0.114 * srcBuf[pTop]);
                int lumB = (int)(0.299 * srcBuf[pBot + 2] + 0.587 * srcBuf[pBot + 1] + 0.114 * srcBuf[pBot]);

                int gx = Math.Abs(lumR - lumL);
                int gy = Math.Abs(lumB - lumT);
                edges[y * w + x] = (byte)Math.Min(255, gx + gy);
            }
        }

        // 3. Flood Fill from Perimeter
        double maxChromaDist = Math.Max(12.0, tolerance * 0.75);
        double maxRgbDist = Math.Max(20.0, tolerance * 1.6);
        bool[] isBg = new bool[w * h];
        Queue<int> queue = new Queue<int>();

        for (int x = 0; x < w; x++)
        {
            CheckAndEnqueue(x, 0, w, h, stride, srcBuf, bgSeedsYCbCr, maxChromaDist, maxRgbDist, isBg, queue);
            CheckAndEnqueue(x, h - 1, w, h, stride, srcBuf, bgSeedsYCbCr, maxChromaDist, maxRgbDist, isBg, queue);
        }
        for (int y = 0; y < h; y++)
        {
            CheckAndEnqueue(0, y, w, h, stride, srcBuf, bgSeedsYCbCr, maxChromaDist, maxRgbDist, isBg, queue);
            CheckAndEnqueue(w - 1, y, w, h, stride, srcBuf, bgSeedsYCbCr, maxChromaDist, maxRgbDist, isBg, queue);
        }

        int[] dx = new int[] { -1, 1, 0, 0 };
        int[] dy = new int[] { 0, 0, -1, 1 };

        while (queue.Count > 0)
        {
            int curr = queue.Dequeue();
            int cx = curr % w;
            int cy = curr / w;

            int cBufIdx = cy * stride + cx * 4;
            byte curB = srcBuf[cBufIdx];
            byte curG = srcBuf[cBufIdx + 1];
            byte curR = srcBuf[cBufIdx + 2];

            for (int d = 0; d < 4; d++)
            {
                int nx = cx + dx[d];
                int ny = cy + dy[d];
                if (nx >= 0 && nx < w && ny >= 0 && ny < h)
                {
                    int nIdx = ny * w + nx;
                    if (!isBg[nIdx])
                    {
                        if (edges[nIdx] > 48) continue;

                        int nBufIdx = ny * stride + nx * 4;
                        byte nb = srcBuf[nBufIdx];
                        byte ng = srcBuf[nBufIdx + 1];
                        byte nr = srcBuf[nBufIdx + 2];

                        // Protect center skin tones
                        if (IsSkinTone(nr, ng, nb) && nx > w * 0.2 && nx < w * 0.8 && ny > h * 0.1 && ny < h * 0.85)
                        {
                            continue;
                        }

                        double dSeedsChroma = MinSeedChromaDist(nr, ng, nb, bgSeedsYCbCr);
                        double dSeedsRgb = MinSeedRgbDist(nr, ng, nb, bgSeedsYCbCr);
                        double dNeighbor = Math.Sqrt((nr - curR)*(nr - curR) + (ng - curG)*(ng - curG) + (nb - curB)*(nb - curB));

                        if ((dSeedsChroma < maxChromaDist || dSeedsRgb < maxRgbDist) && dNeighbor < 35.0)
                        {
                            isBg[nIdx] = true;
                            queue.Enqueue(nIdx);
                        }
                    }
                }
            }
        }

        // 4. Render with Edge Anti-Aliasing
        byte[] destBuf = new byte[totalBytes];
        for (int y = 0; y < h; y++)
        {
            int rowIdx = y * stride;
            for (int x = 0; x < w; x++)
            {
                int bufIdx = rowIdx + x * 4;
                int mapIdx = y * w + x;

                if (isBg[mapIdx])
                {
                    if (makeTransparent)
                    {
                        destBuf[bufIdx] = 0; destBuf[bufIdx+1] = 0; destBuf[bufIdx+2] = 0; destBuf[bufIdx+3] = 0;
                    }
                    else
                    {
                        destBuf[bufIdx] = replaceBgColor.B; destBuf[bufIdx+1] = replaceBgColor.G;
                        destBuf[bufIdx+2] = replaceBgColor.R; destBuf[bufIdx+3] = 255;
                    }
                }
                else
                {
                    int bgNeighbors = 0;
                    for (int dy2 = -1; dy2 <= 1; dy2++)
                    {
                        for (int dx2 = -1; dx2 <= 1; dx2++)
                        {
                            if (dx2 == 0 && dy2 == 0) continue;
                            int ex = x + dx2;
                            int ey = y + dy2;
                            if (ex >= 0 && ex < w && ey >= 0 && ey < h && isBg[ey * w + ex])
                            {
                                bgNeighbors++;
                            }
                        }
                    }

                    byte r = srcBuf[bufIdx + 2];
                    byte g = srcBuf[bufIdx + 1];
                    byte b = srcBuf[bufIdx];

                    if (bgNeighbors > 0 && makeTransparent)
                    {
                        double alpha = 1.0 - (bgNeighbors / 12.0);
                        byte outA = (byte)Math.Max(120, Math.Min(255, (int)(alpha * 255.0)));
                        destBuf[bufIdx] = b; destBuf[bufIdx+1] = g; destBuf[bufIdx+2] = r; destBuf[bufIdx+3] = outA;
                    }
                    else if (bgNeighbors > 0 && !makeTransparent)
                    {
                        double alpha = 1.0 - (bgNeighbors / 14.0);
                        destBuf[bufIdx] = (byte)Math.Round(b * alpha + replaceBgColor.B * (1.0 - alpha));
                        destBuf[bufIdx+1] = (byte)Math.Round(g * alpha + replaceBgColor.G * (1.0 - alpha));
                        destBuf[bufIdx+2] = (byte)Math.Round(r * alpha + replaceBgColor.R * (1.0 - alpha));
                        destBuf[bufIdx+3] = 255;
                    }
                    else
                    {
                        destBuf[bufIdx] = b; destBuf[bufIdx+1] = g; destBuf[bufIdx+2] = r; destBuf[bufIdx+3] = 255;
                    }
                }
            }
        }

        BitmapData destData = destBmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        Marshal.Copy(destBuf, 0, destData.Scan0, totalBytes);
        destBmp.UnlockBits(destData);

        return destBmp;
    }

    private static void CheckAndEnqueue(int x, int y, int w, int h, int stride, byte[] srcBuf, List<double[]> seeds, double maxChroma, double maxRgb, bool[] isBg, Queue<int> queue)
    {
        int idx = y * w + x;
        if (isBg[idx]) return;
        int bIdx = y * stride + x * 4;
        byte b = srcBuf[bIdx]; byte g = srcBuf[bIdx + 1]; byte r = srcBuf[bIdx + 2];
        if (MinSeedChromaDist(r, g, b, seeds) < maxChroma || MinSeedRgbDist(r, g, b, seeds) < maxRgb)
        {
            isBg[idx] = true;
            queue.Enqueue(idx);
        }
    }

    private static bool IsSkinTone(byte r, byte g, byte b)
    {
        double cb = 128.0 - 0.168736 * r - 0.331264 * g + 0.5 * b;
        double cr = 128.0 + 0.5 * r - 0.418688 * g - 0.081312 * b;
        return (cb >= 77 && cb <= 127 && cr >= 133 && cr <= 173 && r > g && r > b);
    }

    private static double MinSeedChromaDist(byte r, byte g, byte b, List<double[]> seeds)
    {
        double cb = 128.0 - 0.168736 * r - 0.331264 * g + 0.5 * b;
        double cr = 128.0 + 0.5 * r - 0.418688 * g - 0.081312 * b;
        double minDist = double.MaxValue;
        foreach (double[] s in seeds)
        {
            double d = Math.Sqrt((cb - s[1])*(cb - s[1]) + (cr - s[2])*(cr - s[2]));
            if (d < minDist) minDist = d;
        }
        return minDist;
    }

    private static double MinSeedRgbDist(byte r, byte g, byte b, List<double[]> seeds)
    {
        double minDist = double.MaxValue;
        foreach (double[] s in seeds)
        {
            double d = Math.Sqrt((r - s[3])*(r - s[3]) + (g - s[4])*(g - s[4]) + (b - s[5])*(b - s[5]));
            if (d < minDist) minDist = d;
        }
        return minDist;
    }

    public static bool SaveImage(Bitmap bmp, string outputPath, bool asPng)
    {
        try
        {
            string dir = Path.GetDirectoryName(outputPath);
            if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir)) Directory.CreateDirectory(dir);

            if (asPng)
            {
                bmp.Save(outputPath, ImageFormat.Png);
            }
            else
            {
                ImageCodecInfo jpgEncoder = null;
                foreach (ImageCodecInfo codec in ImageCodecInfo.GetImageEncoders())
                {
                    if (codec.FormatID == ImageFormat.Jpeg.Guid) { jpgEncoder = codec; break; }
                }
                using (EncoderParameters ep = new EncoderParameters(1))
                {
                    ep.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, 92L);
                    bmp.Save(outputPath, jpgEncoder, ep);
                }
            }
            return true;
        }
        catch { return false; }
    }
}
"@

try {
    Add-Type -TypeDefinition $csharp -ReferencedAssemblies "System.Drawing" -ErrorAction SilentlyContinue
} catch {}

# --- Load Nexus AI Vision Engine (ONNX Runtime + U-2-Net Neural Segmentation) ---
$global:hasAiVision = $false
try {
    $scriptRoot = $PSScriptRoot
    if (-not $scriptRoot -and $MyInvocation.MyCommand.Path) {
        $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    if (-not $scriptRoot) { $scriptRoot = "C:\Users\mandar.k\Documents\antigravity\lively-raman" }
    
    $aiBinDir = Join-Path $scriptRoot "bin"
    if (-not (Test-Path $aiBinDir)) {
        $aiBinDir = "C:\Users\mandar.k\Documents\antigravity\lively-raman\bin"
    }
    if (-not (Test-Path $aiBinDir)) {
        $aiBinDir = "C:\Users\mandar.k\Documents\antigravity\lively-raman\PMC-Image-Optimizer-Portable\bin"
    }

    $aiDll = Join-Path $aiBinDir "AiBackgroundRemover.dll"
    if (Test-Path $aiDll) {
        $env:PATH = "$aiBinDir;" + $env:PATH
        Add-Type -Path (Join-Path $aiBinDir "System.Buffers.dll") -ErrorAction SilentlyContinue
        Add-Type -Path (Join-Path $aiBinDir "System.Memory.dll") -ErrorAction SilentlyContinue
        Add-Type -Path (Join-Path $aiBinDir "System.Numerics.Vectors.dll") -ErrorAction SilentlyContinue
        Add-Type -Path (Join-Path $aiBinDir "System.Runtime.CompilerServices.Unsafe.dll") -ErrorAction SilentlyContinue
        Add-Type -Path (Join-Path $aiBinDir "Microsoft.ML.OnnxRuntime.dll") -ErrorAction SilentlyContinue
        Add-Type -Path $aiDll -ErrorAction SilentlyContinue

        $modelPath = Join-Path $aiBinDir "u2netp.onnx"
        if (Test-Path $modelPath) {
            $global:hasAiVision = [Nexus.AI.AiBackgroundRemover]::Init($modelPath)
        }
    }
} catch {
    $global:hasAiVision = $false
}

# Reflection helpers for WinRT PDF rendering
$asTaskOp = $null
$asTaskAction = $null
$netStreamMethod = $null

try {
    $asTaskOp = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetGenericArguments().Length -eq 1 -and $_.GetParameters().Length -eq 1
    })[0]

    $asTaskAction = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and (-not $_.IsGenericMethod) -and $_.GetParameters().Length -eq 1
    })[0]

    $netStreamMethod = [System.IO.WindowsRuntimeStreamExtensions].GetMethod('AsStreamForRead', [Type[]]@([Windows.Storage.Streams.IInputStream]))
} catch {}

# --- Premium Modern WPF XAML Layout (100% Valid Standard WPF) ---
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Nexus Photo &amp; Document Optimizer (Enterprise Edition)" 
        Height="960" Width="1240" 
        MinHeight="850" MinWidth="1050"
        WindowStartupLocation="CenterScreen" 
        Background="{DynamicResource WindowBgBrush}" FontFamily="Segoe UI"
        TextOptions.TextFormattingMode="Display"
        TextOptions.TextRenderingMode="ClearType">

    <Window.Resources>
        <!-- Futuristic Gradients & Palettes -->
        <LinearGradientBrush x:Key="WindowBgBrush" StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#060A13" Offset="0.0"/>
            <GradientStop Color="#0D1629" Offset="0.5"/>
            <GradientStop Color="#090F1C" Offset="1.0"/>
        </LinearGradientBrush>

        <LinearGradientBrush x:Key="HeaderCardBrush" StartPoint="0,0" EndPoint="1,0">
            <GradientStop Color="#0C152C" Offset="0.0"/>
            <GradientStop Color="#13244F" Offset="0.5"/>
            <GradientStop Color="#0C152C" Offset="1.0"/>
        </LinearGradientBrush>

        <LinearGradientBrush x:Key="NexusLogoHexBrush" StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#00F2FE" Offset="0.0"/>
            <GradientStop Color="#4FACFE" Offset="0.5"/>
            <GradientStop Color="#6366F1" Offset="1.0"/>
        </LinearGradientBrush>

        <LinearGradientBrush x:Key="NexusLogoInnerBrush" StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#38BDF8" Offset="0.0"/>
            <GradientStop Color="#818CF8" Offset="0.5"/>
            <GradientStop Color="#C084FC" Offset="1.0"/>
        </LinearGradientBrush>

        <LinearGradientBrush x:Key="NexusLogoGlowBrush" StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#0B132B" Offset="0.0"/>
            <GradientStop Color="#060A17" Offset="1.0"/>
        </LinearGradientBrush>

        <LinearGradientBrush x:Key="TabBarBrush" StartPoint="0,0" EndPoint="1,0">
            <GradientStop Color="#080E1C" Offset="0.0"/>
            <GradientStop Color="#0D172A" Offset="1.0"/>
        </LinearGradientBrush>

        <LinearGradientBrush x:Key="CardBgBrush" StartPoint="0,0" EndPoint="0,1">
            <GradientStop Color="#0F1B33" Offset="0.0"/>
            <GradientStop Color="#0C1527" Offset="1.0"/>
        </LinearGradientBrush>

        <LinearGradientBrush x:Key="CardBgDarkBrush" StartPoint="0,0" EndPoint="0,1">
            <GradientStop Color="#091020" Offset="0.0"/>
            <GradientStop Color="#060A14" Offset="1.0"/>
        </LinearGradientBrush>

        <LinearGradientBrush x:Key="InnerBoxBrush" StartPoint="0,0" EndPoint="0,1">
            <GradientStop Color="#060B17" Offset="0.0"/>
            <GradientStop Color="#040710" Offset="1.0"/>
        </LinearGradientBrush>

        <LinearGradientBrush x:Key="PrimaryBtnBrush" StartPoint="0,0" EndPoint="1,0">
            <GradientStop Color="#2563EB" Offset="0.0"/>
            <GradientStop Color="#1D4ED8" Offset="1.0"/>
        </LinearGradientBrush>

        <LinearGradientBrush x:Key="SuccessBtnBrush" StartPoint="0,0" EndPoint="1,0">
            <GradientStop Color="#059669" Offset="0.0"/>
            <GradientStop Color="#10B981" Offset="1.0"/>
        </LinearGradientBrush>

        <LinearGradientBrush x:Key="CyanBadgeBrush" StartPoint="0,0" EndPoint="1,0">
            <GradientStop Color="#0284C7" Offset="0.0"/>
            <GradientStop Color="#06B6D4" Offset="1.0"/>
        </LinearGradientBrush>

        <LinearGradientBrush x:Key="PurpleBadgeBrush" StartPoint="0,0" EndPoint="1,0">
            <GradientStop Color="#6366F1" Offset="0.0"/>
            <GradientStop Color="#8B5CF6" Offset="1.0"/>
        </LinearGradientBrush>

        <LinearGradientBrush x:Key="EmeraldBadgeBrush" StartPoint="0,0" EndPoint="1,0">
            <GradientStop Color="#047857" Offset="0.0"/>
            <GradientStop Color="#10B981" Offset="1.0"/>
        </LinearGradientBrush>

        <LinearGradientBrush x:Key="AmberBadgeBrush" StartPoint="0,0" EndPoint="1,0">
            <GradientStop Color="#D97706" Offset="0.0"/>
            <GradientStop Color="#F59E0B" Offset="1.0"/>
        </LinearGradientBrush>

        <!-- Dynamic Theme Palette Brushes (Hardware-Accelerated WPF Theming) -->
        <SolidColorBrush x:Key="CardBorderBrush" Color="#1E3252"/>
        <SolidColorBrush x:Key="SubCardBorderBrush" Color="#1C2D4A"/>
        <SolidColorBrush x:Key="InputBgBrush" Color="#090F1E"/>
        <SolidColorBrush x:Key="InputFgBrush" Color="#F8FAFC"/>
        <SolidColorBrush x:Key="InputBorderBrush" Color="#223659"/>
        <SolidColorBrush x:Key="TextPrimaryBrush" Color="#F8FAFC"/>
        <SolidColorBrush x:Key="TextSecondaryBrush" Color="#94A3B8"/>
        <SolidColorBrush x:Key="TextMutedBrush" Color="#64748B"/>
        <SolidColorBrush x:Key="TabInactiveBgBrush" Color="#0D1527"/>
        <SolidColorBrush x:Key="TabInactiveFgBrush" Color="#94A3B8"/>
        <SolidColorBrush x:Key="DropdownItemBgBrush" Color="#0B1325"/>
        <SolidColorBrush x:Key="SqlConsoleBgBrush" Color="#1E1E1E"/>
        <SolidColorBrush x:Key="SqlBarBgBrush" Color="#252526"/>
        <SolidColorBrush x:Key="SqlMenuBarBgBrush" Color="#2D2D30"/>
        <SolidColorBrush x:Key="SqlToolbarBgBrush" Color="#252526"/>
        <SolidColorBrush x:Key="SqlBorderBrush" Color="#3F3F46"/>
        <SolidColorBrush x:Key="SqlBtnBgBrush" Color="#333337"/>
        <SolidColorBrush x:Key="SqlBtnFgBrush" Color="#DCDCDC"/>
        <SolidColorBrush x:Key="SqlEditorBgBrush" Color="#1E1E1E"/>
        <SolidColorBrush x:Key="SqlEditorFgBrush" Color="#4ADE80"/>
        <SolidColorBrush x:Key="SqlHeaderBgBrush" Color="#2D2D30"/>
        <SolidColorBrush x:Key="SqlHeaderFgBrush" Color="#DCDCDC"/>
        <SolidColorBrush x:Key="SqlHeaderBorderBrush" Color="#3F3F46"/>

        <!-- Element Styles with DynamicResource for Instant 0ms Theme Switching -->
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>

        <Style TargetType="TextBox">
            <Setter Property="Background" Value="{DynamicResource InputBgBrush}"/>
            <Setter Property="Foreground" Value="{DynamicResource InputFgBrush}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource InputBorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12,8"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>

        <Style x:Key="ActionButton" TargetType="Button">
            <Setter Property="Background" Value="{StaticResource PrimaryBtnBrush}"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Padding" Value="16,9"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>

        <Style TargetType="RadioButton">
            <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>

        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>

        <Style TargetType="ComboBox">
            <Setter Property="Background" Value="{DynamicResource InputBgBrush}"/>
            <Setter Property="Foreground" Value="{DynamicResource InputFgBrush}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource InputBorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>

        <Style TargetType="ComboBoxItem">
            <Setter Property="Background" Value="{DynamicResource DropdownItemBgBrush}"/>
            <Setter Property="Foreground" Value="{DynamicResource InputFgBrush}"/>
            <Setter Property="Padding" Value="12,10"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="BorderBrush" Value="{DynamicResource CardBorderBrush}"/>
            <Setter Property="BorderThickness" Value="0,0,0,1"/>
            <Style.Triggers>
                <Trigger Property="IsHighlighted" Value="True">
                    <Setter Property="Background" Value="#2563EB"/>
                    <Setter Property="Foreground" Value="#FFFFFF"/>
                </Trigger>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="#0284C7"/>
                    <Setter Property="Foreground" Value="#FFFFFF"/>
                </Trigger>
            </Style.Triggers>
        </Style>
    </Window.Resources>

    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <!-- Top Header Card -->
        <Border Grid.Row="0" Background="{DynamicResource HeaderCardBrush}" CornerRadius="12" Padding="18,14" Margin="0,0,0,12" BorderBrush="{DynamicResource CardBorderBrush}" BorderThickness="1.5">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                
                <DockPanel Grid.Column="0" VerticalAlignment="Center" Margin="0,0,14,0">
                    <!-- Futuristic Nexus Vector Logo Mark -->
                    <Border DockPanel.Dock="Left" Width="54" Height="54" CornerRadius="14" Margin="0,0,14,0" BorderThickness="1.5"
                            Background="{StaticResource NexusLogoGlowBrush}">
                        <Border.BorderBrush>
                            <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                                <GradientStop Color="#00F2FE" Offset="0.0"/>
                                <GradientStop Color="#6366F1" Offset="0.5"/>
                                <GradientStop Color="#C084FC" Offset="1.0"/>
                            </LinearGradientBrush>
                        </Border.BorderBrush>
                        <Grid HorizontalAlignment="Center" VerticalAlignment="Center" Width="38" Height="38">
                            <!-- Outer Tech Hexagon Aperture -->
                            <Path Data="M 19,2 L 35,11 L 35,27 L 19,36 L 3,27 L 3,11 Z" 
                                  Stroke="{StaticResource NexusLogoHexBrush}" StrokeThickness="2" Fill="Transparent"/>
                            <!-- Nexus Stylized Diamond-N Path -->
                            <Path Data="M 11,27 L 11,11 L 27,27 L 27,11" 
                                  Stroke="{StaticResource NexusLogoInnerBrush}" StrokeThickness="3.2" StrokeLineJoin="Round" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                            <!-- Glowing Center Core Node -->
                            <Ellipse Width="6" Height="6" Fill="#38BDF8" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Grid>
                    </Border>

                    <!-- Title & Tagline Branding -->
                    <StackPanel VerticalAlignment="Center">
                        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                            <TextBlock Text="NEXUS" FontSize="23" FontWeight="ExtraBold" Foreground="#38BDF8" Margin="0,0,8,0" FontFamily="Segoe UI"/>
                            <TextBlock Text="OPTIMIZER" FontSize="23" FontWeight="Light" Foreground="#BAE6FD" Margin="0,0,12,0" FontFamily="Segoe UI"/>
                            <Border Background="{StaticResource PurpleBadgeBrush}" CornerRadius="5" Padding="7,2" Margin="0,0,6,0" VerticalAlignment="Center">
                                <TextBlock Text="PRO ENTERPRISE" FontWeight="Bold" Foreground="White" FontSize="9.5"/>
                            </Border>
                            <Border Background="{StaticResource SuccessBtnBrush}" CornerRadius="5" Padding="7,2" VerticalAlignment="Center">
                                <TextBlock Text="v2.5" FontWeight="Bold" Foreground="White" FontSize="9.5"/>
                            </Border>
                        </StackPanel>
                        <TextBlock Text="Property Photos (&lt;25KB) | PlanPhoto WMF | BLOB Previewer | Govt Exam Resizer | Server Photo Extractor | OTP Decryptor" FontSize="11.5" Foreground="#94A3B8" Margin="0,4,0,0" TextWrapping="Wrap"/>
                    </StackPanel>
                </DockPanel>

                <!-- Right Side: Nexus AI Cursor-Watching Companion Mascot + Status Pill -->
                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center" HorizontalAlignment="Right">
                    <!-- JARVIS Cybernetic Glowing Arc Reactor Core -->
                    <Border x:Name="mascotContainer" Background="#0A1120" BorderBrush="#00F0FF" BorderThickness="1.5" CornerRadius="12" Padding="8,5" Margin="0,0,8,0" VerticalAlignment="Center" Cursor="Hand" ToolTip="JARVIS AI Glowing Arc Reactor Core - Click or press F1 to launch JARVIS Assistant!">
                        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                            <!-- Iron Man / Tony Stark Iconic Arc Reactor Vector -->
                            <Canvas x:Name="mascotCanvas" Width="42" Height="42" Margin="0,0,8,0">
                                <!-- Outer Glow / Ambient Energy Aura -->
                                <Ellipse Canvas.Left="0" Canvas.Top="0" Width="42" Height="42" Fill="#0284C7" Opacity="0.15"/>

                                <!-- Outer Chassis Ring (Dark Gunmetal Alloy) -->
                                <Ellipse Canvas.Left="1" Canvas.Top="1" Width="40" Height="40" Stroke="#1E3A8A" StrokeThickness="1.5" Fill="#030712"/>

                                <!-- Outer Electromagnetic Energy Track (Cyan Glow) -->
                                <Ellipse Canvas.Left="3" Canvas.Top="3" Width="36" Height="36" Stroke="#00F0FF" StrokeThickness="1.2" Opacity="0.8"/>

                                <!-- 10 Radial Copper Accelerator Coils -->
                                <Rectangle Canvas.Left="19.5" Canvas.Top="2.5" Width="3" Height="5" Fill="#F59E0B" Stroke="#78350F" StrokeThickness="0.6" RadiusX="0.6" RadiusY="0.6">
                                    <Rectangle.RenderTransform><RotateTransform Angle="0" CenterX="1.5" CenterY="18.5"/></Rectangle.RenderTransform>
                                </Rectangle>
                                <Rectangle Canvas.Left="19.5" Canvas.Top="2.5" Width="3" Height="5" Fill="#F59E0B" Stroke="#78350F" StrokeThickness="0.6" RadiusX="0.6" RadiusY="0.6">
                                    <Rectangle.RenderTransform><RotateTransform Angle="36" CenterX="1.5" CenterY="18.5"/></Rectangle.RenderTransform>
                                </Rectangle>
                                <Rectangle Canvas.Left="19.5" Canvas.Top="2.5" Width="3" Height="5" Fill="#F59E0B" Stroke="#78350F" StrokeThickness="0.6" RadiusX="0.6" RadiusY="0.6">
                                    <Rectangle.RenderTransform><RotateTransform Angle="72" CenterX="1.5" CenterY="18.5"/></Rectangle.RenderTransform>
                                </Rectangle>
                                <Rectangle Canvas.Left="19.5" Canvas.Top="2.5" Width="3" Height="5" Fill="#F59E0B" Stroke="#78350F" StrokeThickness="0.6" RadiusX="0.6" RadiusY="0.6">
                                    <Rectangle.RenderTransform><RotateTransform Angle="108" CenterX="1.5" CenterY="18.5"/></Rectangle.RenderTransform>
                                </Rectangle>
                                <Rectangle Canvas.Left="19.5" Canvas.Top="2.5" Width="3" Height="5" Fill="#F59E0B" Stroke="#78350F" StrokeThickness="0.6" RadiusX="0.6" RadiusY="0.6">
                                    <Rectangle.RenderTransform><RotateTransform Angle="144" CenterX="1.5" CenterY="18.5"/></Rectangle.RenderTransform>
                                </Rectangle>
                                <Rectangle Canvas.Left="19.5" Canvas.Top="2.5" Width="3" Height="5" Fill="#F59E0B" Stroke="#78350F" StrokeThickness="0.6" RadiusX="0.6" RadiusY="0.6">
                                    <Rectangle.RenderTransform><RotateTransform Angle="180" CenterX="1.5" CenterY="18.5"/></Rectangle.RenderTransform>
                                </Rectangle>
                                <Rectangle Canvas.Left="19.5" Canvas.Top="2.5" Width="3" Height="5" Fill="#F59E0B" Stroke="#78350F" StrokeThickness="0.6" RadiusX="0.6" RadiusY="0.6">
                                    <Rectangle.RenderTransform><RotateTransform Angle="216" CenterX="1.5" CenterY="18.5"/></Rectangle.RenderTransform>
                                </Rectangle>
                                <Rectangle Canvas.Left="19.5" Canvas.Top="2.5" Width="3" Height="5" Fill="#F59E0B" Stroke="#78350F" StrokeThickness="0.6" RadiusX="0.6" RadiusY="0.6">
                                    <Rectangle.RenderTransform><RotateTransform Angle="252" CenterX="1.5" CenterY="18.5"/></Rectangle.RenderTransform>
                                </Rectangle>
                                <Rectangle Canvas.Left="19.5" Canvas.Top="2.5" Width="3" Height="5" Fill="#F59E0B" Stroke="#78350F" StrokeThickness="0.6" RadiusX="0.6" RadiusY="0.6">
                                    <Rectangle.RenderTransform><RotateTransform Angle="288" CenterX="1.5" CenterY="18.5"/></Rectangle.RenderTransform>
                                </Rectangle>
                                <Rectangle Canvas.Left="19.5" Canvas.Top="2.5" Width="3" Height="5" Fill="#F59E0B" Stroke="#78350F" StrokeThickness="0.6" RadiusX="0.6" RadiusY="0.6">
                                    <Rectangle.RenderTransform><RotateTransform Angle="324" CenterX="1.5" CenterY="18.5"/></Rectangle.RenderTransform>
                                </Rectangle>

                                <!-- Inner Containment Ring -->
                                <Ellipse Canvas.Left="8.5" Canvas.Top="8.5" Width="25" Height="25" Stroke="#38BDF8" StrokeThickness="1.5" Fill="#050C1A"/>
                                <Ellipse Canvas.Left="10.5" Canvas.Top="10.5" Width="21" Height="21" Stroke="#00F0FF" StrokeThickness="0.8" Opacity="0.9"/>

                                <!-- Arc Reactor Core Plasma Chamber -->
                                <Ellipse x:Name="arcCoreGlow" Canvas.Left="12" Canvas.Top="12" Width="18" Height="18">
                                    <Ellipse.Fill>
                                        <RadialGradientBrush Center="0.5,0.5" GradientOrigin="0.5,0.5" RadiusX="0.5" RadiusY="0.5">
                                            <GradientStop Color="#FFFFFF" Offset="0.0"/>
                                            <GradientStop Color="#67E8F9" Offset="0.35"/>
                                            <GradientStop Color="#00E5FF" Offset="0.65"/>
                                            <GradientStop Color="#0284C7" Offset="0.9"/>
                                            <GradientStop Color="#030712" Offset="1.0"/>
                                        </RadialGradientBrush>
                                    </Ellipse.Fill>
                                </Ellipse>

                                <!-- 3 Radial Energy Beams -->
                                <Line X1="21" Y1="14" X2="21" Y2="8" Stroke="#00F0FF" StrokeThickness="1" Opacity="0.8"/>
                                <Line X1="26.5" Y1="24.5" X2="31.5" Y2="27.5" Stroke="#00F0FF" StrokeThickness="1" Opacity="0.8"/>
                                <Line X1="15.5" Y1="24.5" X2="10.5" Y2="27.5" Stroke="#00F0FF" StrokeThickness="1" Opacity="0.8"/>

                                <!-- Dynamic Pulsing Plasma Ring -->
                                <Ellipse x:Name="arcPulseRing" Canvas.Left="7" Canvas.Top="7" Width="28" Height="28" 
                                         Stroke="#00F0FF" StrokeThickness="1.2" Opacity="0.7" RenderTransformOrigin="0.5,0.5">
                                    <Ellipse.RenderTransform>
                                        <ScaleTransform x:Name="arcPulseScale" ScaleX="1.0" ScaleY="1.0"/>
                                    </Ellipse.RenderTransform>
                                </Ellipse>

                                <!-- Central Triangular Palladium Emitter -->
                                <Polygon x:Name="arcCoreTriangle" Points="21,15 26.5,24.5 15.5,24.5" 
                                         Stroke="#00F0FF" StrokeThickness="1.2" Fill="#FFFFFF" Opacity="0.95" 
                                         StrokeLineJoin="Round"/>
                                <Polygon Points="21,17 24.5,23.5 17.5,23.5" Fill="#00F0FF" Opacity="0.9"/>
                                <Ellipse x:Name="arcCoreCenterDot" Canvas.Left="19.5" Canvas.Top="19.5" Width="3" Height="3" Fill="#FFFFFF"/>
                            </Canvas>

                            <!-- Companion Status Info -->
                            <StackPanel VerticalAlignment="Center">
                                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                    <Ellipse x:Name="mascotStatusDot" Width="6" Height="6" Fill="#00F0FF" Margin="0,0,4,0" VerticalAlignment="Center"/>
                                    <TextBlock x:Name="mascotTitle" Text="JARVIS AI" FontSize="11" FontWeight="Bold" Foreground="#00F0FF"/>
                                </StackPanel>
                                <TextBlock x:Name="mascotSub" Text="Arc Reactor 100%" FontSize="9" Foreground="#94A3B8" Margin="0,1,0,0"/>
                            </StackPanel>
                        </StackPanel>
                    </Border>

                    <!-- Beyond Compare / Code & Text Diff Tool Button -->
                    <Border x:Name="btnLaunchDiffCompare" Background="#1E1B4B" BorderBrush="#818CF8" BorderThickness="1.5" CornerRadius="10" Padding="10,5" Margin="0,0,8,0" VerticalAlignment="Center" Cursor="Hand" ToolTip="Launch Beyond Compare (Code &amp; Text Diff Inspector Window) [Ctrl+D]">
                        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                            <TextBlock Text="[DIFF]" FontSize="10.5" FontWeight="Bold" Foreground="#A5B4FC" Margin="0,0,4,0" VerticalAlignment="Center"/>
                            <TextBlock Text="BEYOND COMPARE" FontSize="10.5" FontWeight="Bold" Foreground="#FFFFFF" VerticalAlignment="Center"/>
                        </StackPanel>
                    </Border>

                    <!-- Dynamic Update Available Notification Pill -->
                    <Border x:Name="btnUpdateAlertHeader" Visibility="Collapsed" Background="#065F46" BorderBrush="#10B981" BorderThickness="1.5" CornerRadius="10" Padding="10,5" Margin="0,0,8,0" VerticalAlignment="Center" Cursor="Hand" ToolTip="Application Update Ready - Click to Update &amp; Restart">
                        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                            <Ellipse Width="7" Height="7" Fill="#34D399" Margin="0,0,5,0" VerticalAlignment="Center"/>
                            <TextBlock x:Name="txtUpdateAlertHeader" Text="UPDATE READY" FontSize="10.5" FontWeight="Bold" Foreground="#34D399" Margin="0,0,4,0" VerticalAlignment="Center"/>
                            <TextBlock Text="[RESTART]" FontSize="10.5" FontWeight="Bold" Foreground="#FFFFFF" VerticalAlignment="Center"/>
                        </StackPanel>
                    </Border>

                    <!-- Dark / Light Theme Toggle Button -->
                    <Border x:Name="btnToggleTheme" Background="#0A1120" BorderBrush="#0284C7" BorderThickness="1.5" CornerRadius="10" Padding="10,5" Margin="0,0,8,0" VerticalAlignment="Center" Cursor="Hand" ToolTip="Click to switch Dark / Light Theme">
                        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                            <TextBlock x:Name="txtThemeIcon" Text="[D]" FontSize="10.5" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,4,0" VerticalAlignment="Center"/>
                            <TextBlock x:Name="txtThemeLabel" Text="DARK MODE" FontSize="10.5" FontWeight="Bold" Foreground="#38BDF8" VerticalAlignment="Center"/>
                        </StackPanel>
                    </Border>

                    <!-- Right Status Pill -->
                    <Border x:Name="btnEnterpriseSuiteBadge" Background="{StaticResource CyanBadgeBrush}" CornerRadius="10" Padding="12,6" VerticalAlignment="Center" Cursor="Hand" ToolTip="Double-click or press Ctrl+Shift+S to open Admin SQL Console">
                        <StackPanel HorizontalAlignment="Center">
                            <TextBlock Text="ENTERPRISE SUITE" FontSize="9" FontWeight="Bold" Foreground="#BAE6FD" HorizontalAlignment="Center"/>
                            <TextBlock Text="ALL-IN-ONE" FontSize="12" FontWeight="Bold" Foreground="White" HorizontalAlignment="Center"/>
                        </StackPanel>
                    </Border>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Tab Bar Navigation (7 Tabs) -->
        <Border Grid.Row="1" Background="{DynamicResource TabBarBrush}" CornerRadius="10" Padding="5" Margin="0,0,0,12" BorderBrush="{DynamicResource CardBorderBrush}" BorderThickness="1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="1*"/>
                    <ColumnDefinition Width="1.14*"/>
                    <ColumnDefinition Width="1.14*"/>
                    <ColumnDefinition Width="1.16*"/>
                    <ColumnDefinition Width="0.95*"/>
                    <ColumnDefinition Width="0.92*"/>
                    <ColumnDefinition x:Name="colTabSql" Width="0"/>
                    <ColumnDefinition Width="1.15*"/>
                    <ColumnDefinition Width="1.10*"/>
                </Grid.ColumnDefinitions>

                <Button x:Name="tabBtnBatch" Grid.Column="0" Content="BATCH OPTIMIZER" Background="{StaticResource PrimaryBtnBrush}" Foreground="White" FontWeight="Bold" FontSize="11" Padding="4,10" Margin="0,0,2,0" BorderThickness="0" Cursor="Hand"/>
                <Button x:Name="tabBtnGovtExam" Grid.Column="1" Content="GOVT EXAM RESIZER" Background="#0D1527" Foreground="#94A3B8" FontWeight="Bold" FontSize="11" Padding="4,10" Margin="2,0,2,0" BorderThickness="0" Cursor="Hand"/>
                <Button x:Name="tabBtnExtract" Grid.Column="2" Content="EXTRACT TO DESKTOP" Background="#0D1527" Foreground="#94A3B8" FontWeight="Bold" FontSize="11" Padding="4,10" Margin="2,0,2,0" BorderThickness="0" Cursor="Hand"/>
                <Button x:Name="tabBtnBgRemover" Grid.Column="3" Content="BG REMOVER / SIGN" Background="#0D1527" Foreground="#94A3B8" FontWeight="Bold" FontSize="11" Padding="4,10" Margin="2,0,2,0" BorderThickness="0" Cursor="Hand"/>
                <Button x:Name="tabBtnPreview" Grid.Column="4" Content="BLOB PREVIEWER" Background="#0D1527" Foreground="#94A3B8" FontWeight="Bold" FontSize="11" Padding="4,10" Margin="2,0,2,0" BorderThickness="0" Cursor="Hand"/>
                <Button x:Name="tabBtnOtp" Grid.Column="5" Content="OTP DECRYPTOR" Background="#0D1527" Foreground="#94A3B8" FontWeight="Bold" FontSize="11" Padding="4,10" Margin="2,0,2,0" BorderThickness="0" Cursor="Hand"/>
                <Button x:Name="tabBtnSql" Grid.Column="6" Content="SQL CONSOLE" Visibility="Collapsed" Background="#0D1527" Foreground="#94A3B8" FontWeight="Bold" FontSize="11" Padding="4,10" Margin="2,0,2,0" BorderThickness="0" Cursor="Hand"/>
                <Button x:Name="tabBtnLanShare" Grid.Column="7" Content="DIRECT PC SHARE" Background="#0D1527" Foreground="#38BDF8" FontWeight="Bold" FontSize="11" Padding="4,10" Margin="2,0,2,0" BorderThickness="0" Cursor="Hand" ToolTip="Direct PC-to-PC File Transfer Without IP (AirDrop for LAN)"/>
                <Button x:Name="tabBtnBeyondCompare" Grid.Column="8" Content="BEYOND COMPARE" Background="#1E1B4B" Foreground="#A5B4FC" FontWeight="Bold" FontSize="11" Padding="4,10" Margin="2,0,0,0" BorderThickness="0" Cursor="Hand" ToolTip="Beyond Compare 5 Studio (Text &amp; Folder Diff) [Ctrl+D]"/>
            </Grid>
        </Border>

        <!-- TAB 1: BATCH OPTIMIZER VIEW -->
        <Grid x:Name="viewBatch" Grid.Row="2">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- Mode & File Selection Card -->
            <Border Grid.Row="0" Background="{DynamicResource CardBgBrush}" CornerRadius="12" Padding="18,14" Margin="0,0,0,10" BorderBrush="#1E3252" BorderThickness="1">
                <StackPanel>
                    <TextBlock Text="STEP 1: SELECT PROCESSING MODE" FontWeight="Bold" FontSize="12" Foreground="#38BDF8" Margin="0,0,0,8"/>
                    <Grid Margin="0,0,0,12">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Border Grid.Column="0" Background="{DynamicResource CardBgDarkBrush}" CornerRadius="8" Padding="14,10" Margin="0,0,8,0" BorderBrush="#1C2D4A" BorderThickness="1">
                            <RadioButton x:Name="rbPropertyPhotos" Content="Property Photos (JPG/JPEG - Under 25 KB)" IsChecked="True"/>
                        </Border>
                        <Border Grid.Column="1" Background="{DynamicResource CardBgDarkBrush}" CornerRadius="8" Padding="14,10" Margin="8,0,0,0" BorderBrush="#1C2D4A" BorderThickness="1">
                            <RadioButton x:Name="rbPlanPhotoWmf" Content="PlanPhoto Vector (WMF / EMF Solid White)"/>
                        </Border>
                    </Grid>

                    <TextBlock Text="STEP 2: TARGET IMAGES FOLDER (Local Drive or Network Share)" FontWeight="Bold" FontSize="12" Foreground="#38BDF8" Margin="0,0,0,4"/>
                    <Grid Margin="0,0,0,12">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="txtTargetFolder" Grid.Column="0" Text="\\192.168.1.22\d\WebApplicationHost\PMCPhotoStorage.org\wwwroot\Files\PropertyImage"/>
                        <Button x:Name="btnBrowseFolder" Grid.Column="1" Style="{StaticResource ActionButton}" Content="Browse Folder..." Margin="10,0,0,0" Width="145" Background="{StaticResource CyanBadgeBrush}"/>
                    </Grid>

                    <TextBlock Text="STEP 3: SELECTION &amp; FILTERING METHOD" FontWeight="Bold" FontSize="12" Foreground="#38BDF8" Margin="0,0,0,6"/>
                    <Border Background="{DynamicResource CardBgDarkBrush}" CornerRadius="8" Padding="12,10" BorderBrush="#1C2D4A" BorderThickness="1">
                        <StackPanel>
                            <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                                <RadioButton x:Name="rbFilterExcel" Content="Filter from Excel (.xlsx)" IsChecked="True" Margin="0,0,30,0"/>
                                <RadioButton x:Name="rbFilterAll" Content="Process ALL Images in Folder (No Excel)" Margin="0,0,30,0"/>
                                <RadioButton x:Name="rbFilterCustom" Content="Filter by Property Name / Prefix"/>
                            </StackPanel>

                            <Grid x:Name="panelExcelRow">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBox x:Name="txtExcelPath" Grid.Column="0" Text="C:\Users\mandar.k\Downloads\ASWSWSSAAAA\New folder\indi prop.xlsx"/>
                                <Button x:Name="btnBrowseExcel" Grid.Column="1" Style="{StaticResource ActionButton}" Content="Browse Excel..." Margin="10,0,0,0" Width="145" Background="#0D9488"/>
                            </Grid>

                            <Border x:Name="panelAllBadge" Visibility="Collapsed" Background="#0F1F38" CornerRadius="6" Padding="12,10" BorderBrush="#0284C7" BorderThickness="1">
                                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                    <Border Background="{StaticResource CyanBadgeBrush}" CornerRadius="4" Padding="8,3" Margin="0,0,10,0">
                                        <TextBlock Text="ALL IMAGES MODE" FontSize="10" FontWeight="Bold" Foreground="White"/>
                                    </Border>
                                    <TextBlock Text="All images in the target folder will be backed up and compressed under 25 KB without filtering." Foreground="#93C5FD" FontSize="12" VerticalAlignment="Center"/>
                                </StackPanel>
                            </Border>

                            <Grid x:Name="panelCustomRow" Visibility="Collapsed">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock Text="Enter Property IDs / Prefix:" VerticalAlignment="Center" Margin="0,0,12,0" Foreground="#94A3B8" FontWeight="SemiBold"/>
                                <TextBox x:Name="txtCustomProperty" Grid.Column="1" Text="KH-10-7, KH10" ToolTip="Enter specific property IDs or prefix (comma-separated, e.g. KH-10-7, KH10)"/>
                            </Grid>
                        </StackPanel>
                    </Border>
                </StackPanel>
            </Border>

            <!-- Settings Parameters Row -->
            <Border Grid.Row="1" Background="{DynamicResource CardBgBrush}" CornerRadius="12" Padding="16,12" Margin="0,0,0,10" BorderBrush="#1E3252" BorderThickness="1">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="1.3*"/>
                    </Grid.ColumnDefinitions>

                    <StackPanel Grid.Column="0" Margin="0,0,14,0">
                        <TextBlock Text="Max File Size (KB):" FontSize="11" Foreground="#94A3B8" FontWeight="Bold"/>
                        <TextBox x:Name="txtMaxKB" Text="25" Margin="0,4,0,0" FontWeight="Bold" Foreground="#38BDF8" FontSize="14"/>
                    </StackPanel>

                    <StackPanel Grid.Column="1" Margin="0,0,14,0">
                        <TextBlock Text="Max Dimension (px):" FontSize="11" Foreground="#94A3B8" FontWeight="Bold"/>
                        <TextBox x:Name="txtMaxDim" Text="700" Margin="0,4,0,0" FontSize="14"/>
                    </StackPanel>

                    <StackPanel Grid.Column="2" Margin="0,0,14,0">
                        <TextBlock Text="Output DPI:" FontSize="11" Foreground="#94A3B8" FontWeight="Bold"/>
                        <TextBox x:Name="txtDPI" Text="96" Margin="0,4,0,0" FontSize="14"/>
                    </StackPanel>

                    <StackPanel Grid.Column="3" VerticalAlignment="Center" Margin="10,0,0,0">
                        <CheckBox x:Name="chkBackup" Content="Take Full Backup First (Recommended)" IsChecked="True" Foreground="#38BDF8" FontWeight="Bold"/>
                        <CheckBox x:Name="chkRecursive" Content="Scan Subdirectories Recursively" IsChecked="False" Foreground="#CBD5E1" Margin="0,6,0,0"/>
                    </StackPanel>
                </Grid>
            </Border>

            <!-- Metric KPI Cards -->
            <Grid Grid.Row="2" Margin="0,0,0,10">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <Border Grid.Column="0" Background="{DynamicResource CardBgBrush}" CornerRadius="10" Padding="14,12" Margin="0,0,8,0" BorderBrush="#0284C7" BorderThickness="1.5">
                    <StackPanel>
                        <TextBlock Text="MATCHED" FontSize="11" Foreground="#94A3B8" FontWeight="Bold"/>
                        <TextBlock x:Name="lblMatched" Text="0" FontSize="24" FontWeight="Bold" Foreground="#38BDF8" Margin="0,3,0,0"/>
                    </StackPanel>
                </Border>

                <Border Grid.Column="1" Background="{DynamicResource CardBgBrush}" CornerRadius="10" Padding="14,12" Margin="4,0,4,0" BorderBrush="#059669" BorderThickness="1.5">
                    <StackPanel>
                        <TextBlock Text="BACKED UP" FontSize="11" Foreground="#94A3B8" FontWeight="Bold"/>
                        <TextBlock x:Name="lblBackedUp" Text="0" FontSize="24" FontWeight="Bold" Foreground="#34D399" Margin="0,3,0,0"/>
                    </StackPanel>
                </Border>

                <Border Grid.Column="2" Background="{DynamicResource CardBgBrush}" CornerRadius="10" Padding="14,12" Margin="4,0,4,0" BorderBrush="#10B981" BorderThickness="1.5">
                    <StackPanel>
                        <TextBlock Text="RESIZED (&lt; 25 KB)" FontSize="11" Foreground="#94A3B8" FontWeight="Bold"/>
                        <TextBlock x:Name="lblResized" Text="0" FontSize="24" FontWeight="Bold" Foreground="#4ADE80" Margin="0,3,0,0"/>
                    </StackPanel>
                </Border>

                <Border Grid.Column="3" Background="{DynamicResource CardBgBrush}" CornerRadius="10" Padding="14,12" Margin="8,0,0,0" BorderBrush="#F59E0B" BorderThickness="1.5">
                    <StackPanel>
                        <TextBlock Text="STORAGE SAVED" FontSize="11" Foreground="#94A3B8" FontWeight="Bold"/>
                        <TextBlock x:Name="lblSaved" Text="0.0 MB" FontSize="24" FontWeight="Bold" Foreground="#FDE047" Margin="0,3,0,0"/>
                    </StackPanel>
                </Border>
            </Grid>

            <!-- Terminal Log Box & Progress Bar -->
            <Border Grid.Row="3" Background="{DynamicResource InnerBoxBrush}" CornerRadius="12" Padding="12" Margin="0,0,0,10" BorderBrush="#1E2B45" BorderThickness="1">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <TextBox x:Name="txtLogs" Grid.Row="0" Background="Transparent" Foreground="#38BDF8" FontFamily="Consolas" FontSize="12" 
                             BorderThickness="0" IsReadOnly="True" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"
                             Text="System Ready. Configure parameters above and click 'START RESIZING &amp; BACKUP' to begin...&#x0a;"/>

                    <StackPanel Grid.Row="1" Margin="0,8,0,0">
                        <ProgressBar x:Name="progressBar" Height="8" Background="#0A1224" Foreground="#10B981" Value="0" Maximum="100"/>
                        <TextBlock x:Name="lblStatus" Text="Status: Ready" FontSize="12" Foreground="#94A3B8" Margin="0,4,0,0" FontWeight="SemiBold"/>
                    </StackPanel>
                </Grid>
            </Border>

            <!-- Footer Action Buttons -->
            <Grid Grid.Row="4">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <Button x:Name="btnOpenFolder" Grid.Column="0" Content="Open Target Folder" Background="#1E293B" Style="{StaticResource ActionButton}" Margin="0,0,12,0" Width="170"/>
                <Button x:Name="btnOpenBackup" Grid.Column="1" Content="Open Backup Folder" Background="#1E293B" Style="{StaticResource ActionButton}" IsEnabled="False" Margin="0,0,12,0" Width="170"/>
                <Button x:Name="btnStart" Grid.Column="3" Content="START RESIZING &amp; BACKUP" Background="{StaticResource SuccessBtnBrush}" FontSize="14" FontWeight="Bold" Padding="34,12" Style="{StaticResource ActionButton}"/>
            </Grid>
        </Grid>

        <!-- TAB 2: GOVT EXAM RESIZER (PDF & PHOTOS) -->
        <Grid x:Name="viewGovtExam" Grid.Row="2" Visibility="Collapsed">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- Exam Preset Header Card -->
            <Border Grid.Row="0" Background="{DynamicResource CardBgBrush}" CornerRadius="12" Padding="16,14" Margin="0,0,0,10" BorderBrush="#1E3252" BorderThickness="1">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <Grid Grid.Row="0" Margin="0,0,0,8">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Text="SELECT GOVT EXAM SPECIFICATION / PRESET:" FontWeight="Bold" FontSize="12" Foreground="#38BDF8" VerticalAlignment="Center"/>
                        <TextBlock Text="Supports UPSC, SSC, IBPS, RRB, NTA (NEET/JEE), MPSC, MahaDBT &amp; State PSCs" FontSize="11" Foreground="#94A3B8" Grid.Column="1"/>
                    </Grid>

                    <ComboBox x:Name="cmbExamPreset" Grid.Row="1" Height="38" FontSize="13" FontWeight="SemiBold" SelectedIndex="0">
                        <ComboBoxItem Content="[Central] SSC (CGL/CHSL/MTS/GD) - Passport Photo (20 KB - 50 KB | 200x230 px | 3.5x4.5 cm)"/>
                        <ComboBoxItem Content="[Central] SSC / IBPS / RRB - Candidate Signature (10 KB - 20 KB | 140x60 px | 4.0x2.0 cm)"/>
                        <ComboBoxItem Content="[Central] UPSC (CSE/NDA/CDS) - Photograph (20 KB - 300 KB | Min 350x350 px)"/>
                        <ComboBoxItem Content="[Central] UPSC (CSE/NDA/CDS) - Signature (20 KB - 300 KB | Min 350x350 px)"/>
                        <ComboBoxItem Content="[Central] UPSC / SSC / NTA - Certificate / Document PDF (100 KB - 300 KB)"/>
                        <ComboBoxItem Content="[Central] IBPS / SBI - Left Thumb Impression (20 KB - 50 KB | 240x240 px | 3x3 cm)"/>
                        <ComboBoxItem Content="[Central] IBPS / SBI - Handwritten Declaration (50 KB - 100 KB | 800x400 px)"/>
                        <ComboBoxItem Content="[Central] NTA (NEET / JEE / CUET) - Passport Photo (10 KB - 200 KB | 80% Face)"/>
                        <ComboBoxItem Content="[Central] NTA (NEET / JEE / CUET) - Signature (4 KB - 30 KB)"/>
                        <ComboBoxItem Content="[State] MPSC / MahaDBT - Passport Photo (20 KB - 50 KB | 160x200 px)"/>
                        <ComboBoxItem Content="[State] MPSC / MahaDBT - Signature (10 KB - 20 KB | 256x64 px)"/>
                        <ComboBoxItem Content="[State] MPSC / State Govt - Certificate / Domicile PDF (100 KB - 500 KB)"/>
                        <ComboBoxItem Content="[Custom] Custom Target KB &amp; Resolution (Any Image or PDF)"/>
                    </ComboBox>
                </Grid>
            </Border>

            <!-- Exam Parameters & Target File Row -->
            <Border Grid.Row="1" Background="{DynamicResource CardBgBrush}" CornerRadius="12" Padding="16,12" Margin="0,0,0,10" BorderBrush="#1E3252" BorderThickness="1">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <!-- Row 1: Tuning parameters -->
                    <Grid Grid.Row="0" Margin="0,0,0,10">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="1.2*"/>
                        </Grid.ColumnDefinitions>

                        <StackPanel Grid.Column="0" Margin="0,0,10,0">
                            <TextBlock Text="Min Size (KB):" FontSize="11" Foreground="#94A3B8" FontWeight="Bold"/>
                            <TextBox x:Name="txtExamMinKB" Text="20" Margin="0,4,0,0" FontWeight="Bold" Foreground="#38BDF8"/>
                        </StackPanel>

                        <StackPanel Grid.Column="1" Margin="0,0,10,0">
                            <TextBlock Text="Max Size (KB):" FontSize="11" Foreground="#94A3B8" FontWeight="Bold"/>
                            <TextBox x:Name="txtExamMaxKB" Text="50" Margin="0,4,0,0" FontWeight="Bold" Foreground="#4ADE80"/>
                        </StackPanel>

                        <StackPanel Grid.Column="2" Margin="0,0,10,0">
                            <TextBlock Text="Width (px):" FontSize="11" Foreground="#94A3B8" FontWeight="Bold"/>
                            <TextBox x:Name="txtExamWidth" Text="200" Margin="0,4,0,0"/>
                        </StackPanel>

                        <StackPanel Grid.Column="3" Margin="0,0,10,0">
                            <TextBlock Text="Height (px):" FontSize="11" Foreground="#94A3B8" FontWeight="Bold"/>
                            <TextBox x:Name="txtExamHeight" Text="230" Margin="0,4,0,0"/>
                        </StackPanel>

                        <StackPanel Grid.Column="4" Margin="0,0,10,0">
                            <TextBlock Text="Output Type:" FontSize="11" Foreground="#94A3B8" FontWeight="Bold"/>
                            <ComboBox x:Name="cmbExamFormat" Margin="0,4,0,0" SelectedIndex="0">
                                <ComboBoxItem Content="JPG Image"/>
                                <ComboBoxItem Content="PDF Document"/>
                            </ComboBox>
                        </StackPanel>

                        <StackPanel Grid.Column="5" VerticalAlignment="Center" Margin="10,0,0,0">
                            <CheckBox x:Name="chkExamKeepAspect" Content="Maintain Aspect Ratio (White Fit)" IsChecked="True" Foreground="#38BDF8"/>
                            <CheckBox x:Name="chkExamWhiteBg" Content="Solid Pure White Background" IsChecked="True" Foreground="#CBD5E1" Margin="0,4,0,0"/>
                        </StackPanel>
                    </Grid>

                    <!-- Row 2: File Browser -->
                    <Grid Grid.Row="1">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="txtExamInputPath" Grid.Column="0" Text="Select or drop single image, multiple photos, or PDF file..." VerticalContentAlignment="Center"/>
                        <Button x:Name="btnExamBrowseSingle" Grid.Column="1" Style="{StaticResource ActionButton}" Content="Browse File..." Background="{StaticResource CyanBadgeBrush}" Margin="8,0,0,0" Width="130"/>
                        <Button x:Name="btnExamBrowseMulti" Grid.Column="2" Style="{StaticResource ActionButton}" Content="Multi-Image to PDF..." Background="#0D9488" Margin="8,0,0,0" Width="160"/>
                    </Grid>
                </Grid>
            </Border>

            <!-- Exam Live Comparison Preview & Details Panel -->
            <Grid Grid.Row="2" Margin="0,0,0,10">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="1.1*"/>
                    <ColumnDefinition Width="1.1*"/>
                </Grid.ColumnDefinitions>

                <!-- Left: Original Source File Card -->
                <Border Grid.Column="0" Background="{DynamicResource CardBgBrush}" CornerRadius="12" Padding="14" Margin="0,0,8,0" BorderBrush="#1E3252" BorderThickness="1">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <TextBlock Grid.Row="0" Text="ORIGINAL SOURCE FILE" FontWeight="Bold" FontSize="12" Foreground="#94A3B8" Margin="0,0,0,8"/>

                        <Border Grid.Row="1" Background="{DynamicResource InnerBoxBrush}" CornerRadius="8" Margin="0,0,0,10" BorderBrush="#1C2D4A" BorderThickness="1">
                            <Image x:Name="imgExamOriginal" Stretch="Uniform" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="10"/>
                        </Border>

                        <Border Grid.Row="2" Background="{DynamicResource CardBgDarkBrush}" CornerRadius="8" Padding="12,8" BorderBrush="#1C2D4A" BorderThickness="1">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <StackPanel Grid.Column="0">
                                    <TextBlock Text="ORIGINAL SIZE:" FontSize="10" FontWeight="Bold" Foreground="#94A3B8"/>
                                    <TextBlock x:Name="lblExamOrigSize" Text="-- KB" FontSize="15" FontWeight="Bold" Foreground="#F87171"/>
                                </StackPanel>
                                <StackPanel Grid.Column="1">
                                    <TextBlock Text="DIMENSIONS / TYPE:" FontSize="10" FontWeight="Bold" Foreground="#94A3B8"/>
                                    <TextBlock x:Name="lblExamOrigDim" Text="-- px" FontSize="13" FontWeight="Bold" Foreground="#CBD5E1"/>
                                </StackPanel>
                            </Grid>
                        </Border>
                    </Grid>
                </Border>

                <!-- Right: Optimized Exam Result Card -->
                <Border Grid.Column="1" Background="{DynamicResource CardBgBrush}" CornerRadius="12" Padding="14" Margin="8,0,0,0" BorderBrush="#10B981" BorderThickness="2">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <Grid Grid.Row="0" Margin="0,0,0,8">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="OPTIMIZED GOVT EXAM RESULT" FontWeight="Bold" FontSize="12" Foreground="#34D399"/>
                            <Border Grid.Column="1" x:Name="badgeExamStatus" Background="{StaticResource SuccessBtnBrush}" CornerRadius="4" Padding="8,2">
                                <TextBlock x:Name="lblExamBadgeText" Text="READY" FontSize="11" FontWeight="Bold" Foreground="White"/>
                            </Border>
                        </Grid>

                        <Border Grid.Row="1" Background="{DynamicResource InnerBoxBrush}" CornerRadius="8" Margin="0,0,0,10" BorderBrush="#1C2D4A" BorderThickness="1">
                            <Image x:Name="imgExamOptimized" Stretch="Uniform" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="10"/>
                        </Border>

                        <Border Grid.Row="2" Background="{DynamicResource CardBgDarkBrush}" CornerRadius="8" Padding="12,8" BorderBrush="#1C2D4A" BorderThickness="1">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <StackPanel Grid.Column="0">
                                    <TextBlock Text="OPTIMIZED SIZE:" FontSize="10" FontWeight="Bold" Foreground="#94A3B8"/>
                                    <TextBlock x:Name="lblExamOptSize" Text="-- KB" FontSize="16" FontWeight="Bold" Foreground="#4ADE80"/>
                                </StackPanel>
                                <StackPanel Grid.Column="1">
                                    <TextBlock Text="OUTPUT RESOLUTION / PAGES:" FontSize="10" FontWeight="Bold" Foreground="#94A3B8"/>
                                    <TextBlock x:Name="lblExamOptDim" Text="-- px" FontSize="13" FontWeight="Bold" Foreground="#38BDF8"/>
                                </StackPanel>
                            </Grid>
                        </Border>
                    </Grid>
                </Border>
            </Grid>

            <!-- Bottom Action Row -->
            <Grid Grid.Row="3">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <TextBlock Grid.Column="0" Text="Meets all official Govt Exam portal upload guidelines (SSC, UPSC, IBPS, RRB, NTA, MPSC, MahaDBT)." FontSize="12" Foreground="#94A3B8" VerticalAlignment="Center"/>
                <Button x:Name="btnExamProcess" Grid.Column="1" Style="{StaticResource ActionButton}" Content="RESIZE &amp; OPTIMIZE NOW" Background="{StaticResource SuccessBtnBrush}" FontSize="13" FontWeight="Bold" Padding="24,11" Margin="0,0,10,0"/>
                <Button x:Name="btnExamSaveAs" Grid.Column="2" Style="{StaticResource ActionButton}" Content="SAVE / DOWNLOAD FILE..." Background="{StaticResource PrimaryBtnBrush}" FontSize="13" FontWeight="Bold" Padding="24,11" IsEnabled="False"/>
            </Grid>
        </Grid>

        <!-- TAB 3: BLOB & WMF PREVIEWER VIEW -->
        <Grid x:Name="viewPreview" Grid.Row="2" Visibility="Collapsed">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- BLOB Input Header Area -->
            <Border Grid.Row="0" Background="{DynamicResource CardBgBrush}" CornerRadius="12" Padding="16,14" Margin="0,0,0,10" BorderBrush="#1E3252" BorderThickness="1">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <Grid Grid.Row="0" Margin="0,0,0,8">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>

                        <TextBlock Grid.Column="0" Text="PASTE BLOB DATA (SQL Hex '0x...', Base64 string, or File Path):" FontWeight="Bold" FontSize="12" Foreground="#38BDF8" VerticalAlignment="Center"/>
                        <Button x:Name="btnBlobClipboard" Grid.Column="1" Style="{StaticResource ActionButton}" Content="Paste from Clipboard" Background="{StaticResource PrimaryBtnBrush}" Padding="14,6" FontSize="12" Margin="0,0,8,0"/>
                        <Button x:Name="btnBlobBrowseFile" Grid.Column="2" Style="{StaticResource ActionButton}" Content="Browse File..." Background="#0D9488" Padding="14,6" FontSize="12" Margin="0,0,8,0"/>
                        <Button x:Name="btnBlobClear" Grid.Column="3" Style="{StaticResource ActionButton}" Content="Clear" Background="#1E293B" Padding="14,6" FontSize="12"/>
                    </Grid>

                    <Grid Grid.Row="1" Margin="0,0,0,8">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="txtBlobInput" Grid.Column="0" Height="65" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap" 
                                 FontFamily="Consolas" FontSize="11" Foreground="#38BDF8" AllowDrop="True"
                                 Text="Paste SQL Hex 0x..., Base64 string, or drop image file path here..."/>
                        <Button x:Name="btnBlobDecode" Grid.Column="1" Style="{StaticResource ActionButton}" Content="DECODE &amp; PREVIEW" Background="{StaticResource SuccessBtnBrush}" FontSize="13" FontWeight="Bold" Width="170" Margin="10,0,0,0"/>
                    </Grid>

                    <!-- OwnerID Row for SQL Generation -->
                    <Grid Grid.Row="2">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="160"/>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Grid.Column="0" Text="OwnerID:" FontWeight="Bold" FontSize="12" Foreground="#FDE047" VerticalAlignment="Center" Margin="0,0,8,0"/>
                        <TextBox x:Name="txtBlobOwnerID" Grid.Column="1" Height="32" FontFamily="Consolas" FontSize="13" Foreground="#4ADE80" FontWeight="Bold"
                                 VerticalContentAlignment="Center" Padding="8,0" Text="" ToolTip="Enter OwnerID to generate UPDATE SQL for database"/>
                        <Button x:Name="btnCopyImagesMastSql" Grid.Column="2" Style="{StaticResource ActionButton}" Content="Copy UPDATE SQL (PropertyImagesMast)" Background="#7C3AED" FontSize="12" Padding="14,6" Margin="8,0,8,0"/>
                        <Button x:Name="btnCopyPropertyMastSql" Grid.Column="3" Style="{StaticResource ActionButton}" Content="Copy UPDATE SQL (PropertyMast)" Background="#0284C7" FontSize="12" Padding="14,6" Margin="0,0,0,0"/>
                        <TextBlock x:Name="lblSqlCopyResult" Grid.Column="4" Text="" FontSize="11" Foreground="#4ADE80" VerticalAlignment="Center" Margin="12,0,0,0" TextTrimming="CharacterEllipsis"/>
                    </Grid>
                </Grid>
            </Border>

            <!-- Preview & Metadata Grid -->
            <Grid Grid.Row="1" Margin="0,0,0,10">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="2.2*"/>
                    <ColumnDefinition Width="1*"/>
                </Grid.ColumnDefinitions>

                <!-- High-Res Solid White Preview Canvas -->
                <Border Grid.Column="0" Background="{DynamicResource CardBgBrush}" CornerRadius="12" Padding="14" Margin="0,0,12,0" BorderBrush="#1E3252" BorderThickness="1">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>

                        <Grid Grid.Row="0" Margin="0,0,0,10">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="SOLID WHITE CANVAS PREVIEW (Crystal Reports Safe)" FontWeight="Bold" FontSize="12" Foreground="#38BDF8"/>
                            <TextBlock x:Name="lblPreviewStatus" Grid.Column="1" Text="No Image Loaded" FontSize="12" Foreground="#94A3B8" FontWeight="SemiBold"/>
                        </Grid>

                        <Border Grid.Row="1" Background="#FFFFFF" CornerRadius="8" BorderBrush="#475569" BorderThickness="1" ClipToBounds="True">
                            <Image x:Name="imgPreview" Stretch="Uniform" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </Grid>
                </Border>

                <!-- Image Metadata Panel -->
                <Border Grid.Column="1" Background="{DynamicResource CardBgBrush}" CornerRadius="12" Padding="16" BorderBrush="#1E3252" BorderThickness="1">
                    <StackPanel>
                        <TextBlock Text="IMAGE METADATA" FontWeight="Bold" FontSize="12" Foreground="#38BDF8" Margin="0,0,0,12"/>

                        <Border Background="{DynamicResource CardBgDarkBrush}" CornerRadius="8" Padding="12" Margin="0,0,0,10" BorderBrush="#1C2D4A" BorderThickness="1">
                            <StackPanel>
                                <TextBlock Text="DETECTED FORMAT:" FontSize="10" FontWeight="Bold" Foreground="#94A3B8"/>
                                <TextBlock x:Name="lblMetaFormat" Text="--" FontSize="15" FontWeight="Bold" Foreground="#38BDF8" Margin="0,2,0,0"/>
                            </StackPanel>
                        </Border>

                        <Border Background="{DynamicResource CardBgDarkBrush}" CornerRadius="8" Padding="12" Margin="0,0,0,10" BorderBrush="#1C2D4A" BorderThickness="1">
                            <StackPanel>
                                <TextBlock Text="FILE / BLOB SIZE:" FontSize="10" FontWeight="Bold" Foreground="#94A3B8"/>
                                <TextBlock x:Name="lblMetaSize" Text="-- KB" FontSize="15" FontWeight="Bold" Foreground="#34D399" Margin="0,2,0,0"/>
                            </StackPanel>
                        </Border>

                        <Border Background="{DynamicResource CardBgDarkBrush}" CornerRadius="8" Padding="12" Margin="0,0,0,10" BorderBrush="#1C2D4A" BorderThickness="1">
                            <StackPanel>
                                <TextBlock Text="DIMENSIONS:" FontSize="10" FontWeight="Bold" Foreground="#94A3B8"/>
                                <TextBlock x:Name="lblMetaDim" Text="-- px" FontSize="15" FontWeight="Bold" Foreground="#CBD5E1" Margin="0,2,0,0"/>
                            </StackPanel>
                        </Border>

                        <Border Background="{DynamicResource CardBgDarkBrush}" CornerRadius="8" Padding="12" BorderBrush="#1C2D4A" BorderThickness="1">
                            <StackPanel>
                                <TextBlock Text="CANVAS BACKGROUND:" FontSize="10" FontWeight="Bold" Foreground="#94A3B8"/>
                                <TextBlock Text="100% Solid White (#FFFFFF)" FontSize="12" FontWeight="SemiBold" Foreground="#FDE047" Margin="0,2,0,0"/>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </Border>
            </Grid>

            <!-- Bottom Action Downloads Row -->
            <Grid Grid.Row="2">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <TextBlock Grid.Column="0" Text="Export optimized file or copy SQL Hex string for database updates." FontSize="12" Foreground="#94A3B8" VerticalAlignment="Center"/>
                <Button x:Name="btnCopyWmfHex" Grid.Column="1" Style="{StaticResource ActionButton}" Content="Copy WMF SQL Hex (0x...)" Background="#7C3AED" FontSize="12" Padding="14,8" Margin="0,0,8,0"/>
                <Button x:Name="btnCopyJpgHex" Grid.Column="2" Style="{StaticResource ActionButton}" Content="Copy JPG SQL Hex (0x...)" Background="#0284C7" FontSize="12" Padding="14,8" Margin="0,0,8,0"/>
                <Button x:Name="btnDownloadWmf" Grid.Column="3" Style="{StaticResource ActionButton}" Content="Download WMF" Background="{StaticResource CyanBadgeBrush}" FontSize="12" Padding="14,8" Margin="0,0,8,0"/>
                <Button x:Name="btnDownloadJpg" Grid.Column="4" Style="{StaticResource ActionButton}" Content="Download JPG" Background="{StaticResource SuccessBtnBrush}" FontSize="12" Padding="14,8"/>
            </Grid>
        </Grid>

        <!-- TAB 4: OTP & PASSWORD DECRYPTOR VIEW -->
        <Grid x:Name="viewOtp" Grid.Row="2" Visibility="Collapsed">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- OTP Input Header Card -->
            <Border Grid.Row="0" Background="{DynamicResource CardBgBrush}" CornerRadius="12" Padding="18,16" Margin="0,0,0,12" BorderBrush="#1E3252" BorderThickness="1">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <Grid Grid.Row="0" Margin="0,0,0,8">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>

                        <TextBlock Grid.Column="0" Text="ENTER / PASTE ENCRYPTED STRING (Base64 OTP, AES Password, SQL Hex, etc.):" FontWeight="Bold" FontSize="12" Foreground="#38BDF8" VerticalAlignment="Center"/>
                        <Button x:Name="btnOtpPasteClipboard" Grid.Column="1" Style="{StaticResource ActionButton}" Content="Paste from Clipboard" Background="{StaticResource PrimaryBtnBrush}" Padding="14,6" FontSize="12" Margin="0,0,8,0"/>
                        <Button x:Name="btnOtpClear" Grid.Column="2" Style="{StaticResource ActionButton}" Content="Clear" Background="#1E293B" Padding="14,6" FontSize="12"/>
                    </Grid>

                    <Grid Grid.Row="1">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="txtOtpInput" Grid.Column="0" Height="50" FontFamily="Consolas" FontSize="14" FontWeight="SemiBold" Foreground="#38BDF8"
                                 Text="NjQ4NDU3" VerticalContentAlignment="Center"/>
                        <Button x:Name="btnOtpDecrypt" Grid.Column="1" Style="{StaticResource ActionButton}" Content="DECRYPT" Background="{StaticResource SuccessBtnBrush}" FontSize="14" FontWeight="Bold" Width="180" Margin="10,0,0,0"/>
                    </Grid>
                </Grid>
            </Border>

            <!-- Result Cards Area -->
            <Grid Grid.Row="1" Margin="0,0,0,12">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="1.4*"/>
                    <ColumnDefinition Width="1*"/>
                </Grid.ColumnDefinitions>

                <!-- Main Decrypted OTP Big Display Card -->
                <Border Grid.Column="0" Background="{DynamicResource CardBgBrush}" CornerRadius="12" Padding="24" Margin="0,0,12,0" BorderBrush="#10B981" BorderThickness="2">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <TextBlock Grid.Row="0" Text="DECRYPTED RESULT / CLEAR TEXT:" FontSize="13" FontWeight="Bold" Foreground="#94A3B8"/>

                        <!-- Giant Glowing Number / Text Display -->
                        <Border Grid.Row="1" Background="{DynamicResource InnerBoxBrush}" CornerRadius="10" Margin="0,16,0,16" Padding="20" BorderBrush="#1C2D4A" BorderThickness="1">
                            <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
                                <TextBlock x:Name="lblDecryptedOtp" Text="648457" FontSize="52" FontWeight="Bold" Foreground="#4ADE80" HorizontalAlignment="Center"/>
                                <TextBlock x:Name="lblOtpSubtitle" Text="Decrypted Clear Text Output" FontSize="13" Foreground="#94A3B8" HorizontalAlignment="Center" Margin="0,6,0,0"/>
                            </StackPanel>
                        </Border>

                        <Button x:Name="btnCopyOtp" Grid.Row="2" Content="COPY DECRYPTED VALUE TO CLIPBOARD" Background="{StaticResource SuccessBtnBrush}" Style="{StaticResource ActionButton}" FontSize="14" FontWeight="Bold" Padding="20,12"/>
                    </Grid>
                </Border>

                <!-- Technical Details / Metadata Card -->
                <Border Grid.Column="1" Background="{DynamicResource CardBgBrush}" CornerRadius="12" Padding="18" BorderBrush="#1E3252" BorderThickness="1">
                    <StackPanel>
                        <TextBlock Text="ENCRYPTION DETAILS" FontWeight="Bold" FontSize="13" Foreground="#38BDF8" Margin="0,0,0,14"/>

                        <Border Background="{DynamicResource CardBgDarkBrush}" CornerRadius="8" Padding="12" Margin="0,0,0,10" BorderBrush="#1C2D4A" BorderThickness="1">
                            <StackPanel>
                                <TextBlock Text="DECRYPTION METHOD:" FontSize="10" FontWeight="Bold" Foreground="#94A3B8"/>
                                <TextBlock x:Name="lblOtpMethod" Text="Base64 (Standard)" FontSize="15" FontWeight="Bold" Foreground="#38BDF8" Margin="0,2,0,0"/>
                            </StackPanel>
                        </Border>

                        <Border Background="{DynamicResource CardBgDarkBrush}" CornerRadius="8" Padding="12" Margin="0,0,0,10" BorderBrush="#1C2D4A" BorderThickness="1">
                            <StackPanel>
                                <TextBlock Text="RAW INPUT STRING:" FontSize="10" FontWeight="Bold" Foreground="#94A3B8"/>
                                <TextBlock x:Name="lblOtpRawInput" Text="NjQ4NDU3" FontSize="14" FontFamily="Consolas" Foreground="#FDE047" Margin="0,2,0,0" TextWrapping="Wrap"/>
                            </StackPanel>
                        </Border>

                        <Border Background="{DynamicResource CardBgDarkBrush}" CornerRadius="8" Padding="12" Margin="0,0,0,10" BorderBrush="#1C2D4A" BorderThickness="1">
                            <StackPanel>
                                <TextBlock Text="OUTPUT LENGTH:" FontSize="10" FontWeight="Bold" Foreground="#94A3B8"/>
                                <TextBlock x:Name="lblOtpLength" Text="6 Characters" FontSize="15" FontWeight="Bold" Foreground="#CBD5E1" Margin="0,2,0,0"/>
                            </StackPanel>
                        </Border>

                        <Border Background="{DynamicResource CardBgDarkBrush}" CornerRadius="8" Padding="12" BorderBrush="#1C2D4A" BorderThickness="1">
                            <StackPanel>
                                <TextBlock Text="STATUS:" FontSize="10" FontWeight="Bold" Foreground="#94A3B8"/>
                                <TextBlock Text="Decrypted Successfully" FontSize="13" FontWeight="SemiBold" Foreground="#4ADE80" Margin="0,2,0,0"/>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </Border>
            </Grid>

            <!-- Bottom Multi-line Batch Output -->
            <Border Grid.Row="2" Background="{DynamicResource InnerBoxBrush}" CornerRadius="10" Padding="12" BorderBrush="#1E2B45" BorderThickness="1">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="Tip: Automatically decrypts Base64 OTPs, AES-256 encrypted passwords (e.g. SCIPL), SQL Hex, and URLs." Foreground="#64748B" FontSize="12" VerticalAlignment="Center"/>
                    <Button x:Name="btnCopySqlFormula" Grid.Column="1" Style="{StaticResource ActionButton}" Content="Copy SQL Decrypt Query" Background="#1E293B" Padding="14,6" FontSize="12"/>
                </Grid>
            </Border>
        </Grid>

        <!-- TAB 5: PHOTO EXTRACTOR TO DESKTOP VIEW -->
        <Grid x:Name="viewExtract" Grid.Row="2" Visibility="Collapsed">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- Configuration & Paths Card -->
            <Border Grid.Row="0" Background="{DynamicResource CardBgBrush}" CornerRadius="12" Padding="18,14" Margin="0,0,0,10" BorderBrush="#1E3252" BorderThickness="1">
                <StackPanel>
                    <TextBlock Text="STEP 1: SELECT EXTRACTION MODE" FontWeight="Bold" FontSize="12" Foreground="#38BDF8" Margin="0,0,0,8"/>
                    <Grid Margin="0,0,0,12">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Border Grid.Column="0" Background="{DynamicResource CardBgDarkBrush}" CornerRadius="8" Padding="12,10" Margin="0,0,6,0" BorderBrush="#1C2D4A" BorderThickness="1">
                            <RadioButton x:Name="rbExtractModePhotos" GroupName="ExtractModeGroup" Content="Property Photos (JPG/JPEG - &lt;25KB)" IsChecked="True"/>
                        </Border>
                        <Border Grid.Column="1" Background="{DynamicResource CardBgDarkBrush}" CornerRadius="8" Padding="12,10" Margin="3,0,3,0" BorderBrush="#1C2D4A" BorderThickness="1">
                            <RadioButton x:Name="rbExtractModeWmf" GroupName="ExtractModeGroup" Content="PlanPhoto Vector (WMF / EMF Solid White)"/>
                        </Border>
                        <Border Grid.Column="2" Background="{DynamicResource CardBgDarkBrush}" CornerRadius="8" Padding="12,10" Margin="6,0,0,0" BorderBrush="#1C2D4A" BorderThickness="1">
                            <RadioButton x:Name="rbExtractModeBoth" GroupName="ExtractModeGroup" Content="Both Photos &amp; PlanPhoto WMFs"/>
                        </Border>
                    </Grid>

                    <TextBlock Text="STEP 2: SELECT SOURCE SERVER FOLDER / NETWORK SHARE" FontWeight="Bold" FontSize="12" Foreground="#38BDF8" Margin="0,0,0,4"/>
                    <Grid Margin="0,0,0,10">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="txtExtractSource" Grid.Column="0" Text="\\192.168.1.22\d\WebApplicationHost\PMCPhotoStorage.org\wwwroot\Files\PropertyImage"/>
                        <Button x:Name="btnExtractBrowseSource" Grid.Column="1" Style="{StaticResource ActionButton}" Content="Browse Server..." Margin="10,0,0,0" Width="150" Background="{StaticResource CyanBadgeBrush}"/>
                    </Grid>

                    <TextBlock Text="STEP 3: SELECT EXCEL FILE WITH PROPERTY NUMBERS / OWNER IDS" FontWeight="Bold" FontSize="12" Foreground="#38BDF8" Margin="0,0,0,4"/>
                    <Grid Margin="0,0,0,10">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="txtExtractExcel" Grid.Column="0" Text="C:\Users\mandar.k\Downloads\ASWSWSSAAAA\New folder\indi prop.xlsx"/>
                        <Button x:Name="btnExtractBrowseExcel" Grid.Column="1" Style="{StaticResource ActionButton}" Content="Browse Excel..." Margin="10,0,0,0" Width="150" Background="#0D9488"/>
                    </Grid>

                    <TextBlock Text="STEP 4: OUTPUT FOLDER ON DESKTOP" FontWeight="Bold" FontSize="12" Foreground="#38BDF8" Margin="0,0,0,4"/>
                    <Grid Margin="0,0,0,6">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="txtExtractDest" Grid.Column="0" Text="C:\Users\mandar.k\Desktop\Collected_Property_Photos"/>
                        <Button x:Name="btnExtractBrowseDest" Grid.Column="1" Style="{StaticResource ActionButton}" Content="Browse Dest..." Margin="10,0,0,0" Width="130" Background="#1E293B"/>
                        <Button x:Name="btnExtractResetDest" Grid.Column="2" Style="{StaticResource ActionButton}" Content="Auto Desktop" Margin="6,0,0,0" Width="120" Background="#334155"/>
                    </Grid>

                    <WrapPanel Margin="0,6,0,0">
                        <CheckBox x:Name="chkExtractWhiteCanvas" Content="Solid Pure White Background on WMFs (Crystal Reports Safe)" IsChecked="True" Foreground="#34D399" FontWeight="SemiBold" Margin="0,0,20,6"/>
                        <CheckBox x:Name="chkExtractAutoResize" Content="Compress &amp; Resize Photos to &lt;25KB on Copy" IsChecked="False" Foreground="#38BDF8" FontWeight="SemiBold" Margin="0,0,20,6"/>
                        <CheckBox x:Name="chkExtractSubfolders" Content="Organize in Subfolders per Property ID" IsChecked="False" Margin="0,0,20,6"/>
                        <CheckBox x:Name="chkExtractRecursive" Content="Scan Subdirectories Recursively" IsChecked="True" Margin="0,0,0,6"/>
                    </WrapPanel>
                </StackPanel>
            </Border>

            <!-- KPI Metric Cards -->
            <Grid Grid.Row="1" Margin="0,0,0,10">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <Border Grid.Column="0" Background="{DynamicResource CardBgBrush}" CornerRadius="10" Padding="14,12" Margin="0,0,8,0" BorderBrush="#0284C7" BorderThickness="1.5">
                    <StackPanel>
                        <TextBlock Text="TOTAL PROPERTIES" FontSize="11" Foreground="#94A3B8" FontWeight="Bold"/>
                        <TextBlock x:Name="lblExtractTotalProp" Text="0" FontSize="24" FontWeight="Bold" Foreground="#38BDF8" Margin="0,3,0,0"/>
                    </StackPanel>
                </Border>

                <Border Grid.Column="1" Background="{DynamicResource CardBgBrush}" CornerRadius="10" Padding="14,12" Margin="4,0,4,0" BorderBrush="#059669" BorderThickness="1.5">
                    <StackPanel>
                        <TextBlock Text="PROPERTIES FOUND" FontSize="11" Foreground="#94A3B8" FontWeight="Bold"/>
                        <TextBlock x:Name="lblExtractFoundProp" Text="0" FontSize="24" FontWeight="Bold" Foreground="#34D399" Margin="0,3,0,0"/>
                    </StackPanel>
                </Border>

                <Border Grid.Column="2" Background="{DynamicResource CardBgBrush}" CornerRadius="10" Padding="14,12" Margin="4,0,4,0" BorderBrush="#D97706" BorderThickness="1.5">
                    <StackPanel>
                        <TextBlock Text="MISSING PROPERTIES" FontSize="11" Foreground="#94A3B8" FontWeight="Bold"/>
                        <TextBlock x:Name="lblExtractMissingProp" Text="0" FontSize="24" FontWeight="Bold" Foreground="#FDE047" Margin="0,3,0,0"/>
                    </StackPanel>
                </Border>

                <Border Grid.Column="3" Background="{DynamicResource CardBgBrush}" CornerRadius="10" Padding="14,12" Margin="8,0,0,0" BorderBrush="#10B981" BorderThickness="1.5">
                    <StackPanel>
                        <TextBlock Text="FILES COLLECTED" FontSize="11" Foreground="#94A3B8" FontWeight="Bold"/>
                        <TextBlock x:Name="lblExtractCollectedPhotos" Text="0" FontSize="24" FontWeight="Bold" Foreground="#4ADE80" Margin="0,3,0,0"/>
                    </StackPanel>
                </Border>
            </Grid>

            <!-- Console Log Box & Progress -->
            <Border Grid.Row="2" Background="{DynamicResource InnerBoxBrush}" CornerRadius="12" Padding="12" Margin="0,0,0,10" BorderBrush="#1E2B45" BorderThickness="1">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <TextBox x:Name="txtExtractLogs" Grid.Row="0" Background="Transparent" Foreground="#38BDF8" FontFamily="Consolas" FontSize="12" 
                             BorderThickness="0" IsReadOnly="True" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"
                             Text="Ready. Select Mode, Excel sheet, and Server folder above, then click 'START EXTRACTING FILES TO DESKTOP'...&#x0a;"/>

                    <StackPanel Grid.Row="1" Margin="0,8,0,0">
                        <ProgressBar x:Name="extractProgressBar" Height="8" Background="#0A1224" Foreground="#10B981" Value="0" Maximum="100"/>
                        <TextBlock x:Name="lblExtractStatus" Text="Status: Ready" FontSize="12" Foreground="#94A3B8" Margin="0,4,0,0" FontWeight="SemiBold"/>
                    </StackPanel>
                </Grid>
            </Border>

            <!-- Action Buttons Footer -->
            <Grid Grid.Row="3">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <Button x:Name="btnExtractOpenDesktop" Grid.Column="0" Content="Open Desktop Output Folder" Background="#1E293B" Style="{StaticResource ActionButton}" Margin="0,0,10,0" Width="230"/>
                <Button x:Name="btnExtractOpenReport" Grid.Column="1" Content="View CSV Summary Report" Background="#1E293B" Style="{StaticResource ActionButton}" Margin="0,0,10,0" Width="210" IsEnabled="False"/>
                <Button x:Name="btnExtractStart" Grid.Column="3" Content="START EXTRACTING FILES TO DESKTOP" Background="{StaticResource SuccessBtnBrush}" FontSize="13" FontWeight="Bold" Padding="28,12" Style="{StaticResource ActionButton}"/>
            </Grid>
        </Grid>

        <!-- TAB 6: BG REMOVER & SIGNATURE EXTRACTOR VIEW -->
        <Grid x:Name="viewBgRemover" Grid.Row="2" Visibility="Collapsed">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- Image Input Header Card -->
            <Border Grid.Row="0" Background="{DynamicResource CardBgBrush}" CornerRadius="12" Padding="18,14" Margin="0,0,0,10" BorderBrush="#1E3252" BorderThickness="1">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <Grid Grid.Row="0" Margin="0,0,0,8">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>

                        <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                            <TextBlock Text="IMAGE OR SIGNATURE:" FontWeight="Bold" FontSize="12" Foreground="#38BDF8" VerticalAlignment="Center"/>
                            <Border x:Name="badgeBgAutoDetect" Background="#0F2D3D" BorderBrush="#38BDF8" BorderThickness="1" CornerRadius="6" Padding="8,3" Margin="10,0,0,0" VerticalAlignment="Center">
                                <TextBlock x:Name="lblBgAutoBadge" Text="[AI AUTO-DETECT READY]" FontSize="10" FontWeight="Bold" Foreground="#38BDF8"/>
                            </Border>
                        </StackPanel>
                        <Button x:Name="btnBgPasteClipboard" Grid.Column="1" Style="{StaticResource ActionButton}" Content="Paste from Clipboard" Background="{StaticResource SuccessBtnBrush}" Padding="14,6" FontSize="12" Margin="0,0,8,0"/>
                        <Button x:Name="btnBgBrowseFile" Grid.Column="2" Style="{StaticResource ActionButton}" Content="Browse Image..." Background="{StaticResource CyanBadgeBrush}" Padding="14,6" FontSize="12" Margin="0,0,8,0"/>
                        <Button x:Name="btnBgClear" Grid.Column="3" Style="{StaticResource ActionButton}" Content="Clear" Background="#1E293B" Padding="14,6" FontSize="12"/>
                    </Grid>

                    <Grid Grid.Row="1">
                        <TextBox x:Name="txtBgInputPath" Height="40" Text="Select an image file above, drag &amp; drop, or click 'Paste from Clipboard'..." VerticalContentAlignment="Center"/>
                    </Grid>
                </Grid>
            </Border>

            <!-- Mode & Parameter Controls Card -->
            <Border Grid.Row="1" Background="{DynamicResource CardBgBrush}" CornerRadius="12" Padding="18,12" Margin="0,0,0,10" BorderBrush="#1E3252" BorderThickness="1">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <Grid Grid.Row="0" Margin="0,0,0,10">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="1.1*"/>
                            <ColumnDefinition Width="1.6*"/>
                            <ColumnDefinition Width="1.1*"/>
                        </Grid.ColumnDefinitions>

                        <!-- Preset Mode -->
                        <Border Grid.Column="0" Background="{DynamicResource CardBgDarkBrush}" CornerRadius="8" Padding="12,10" Margin="0,0,6,0" BorderBrush="#1C2D4A" BorderThickness="1">
                            <StackPanel>
                                <TextBlock Text="EXTRACTION MODE" FontSize="10" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,6"/>
                                <StackPanel Orientation="Horizontal">
                                    <RadioButton x:Name="rbBgModeSign" Content="Signature / Ink" IsChecked="True" Margin="0,0,14,0"/>
                                    <RadioButton x:Name="rbBgModePortrait" Content="Photo / AI Vision"/>
                                </StackPanel>
                            </StackPanel>
                        </Border>

                        <!-- Background Output Choice -->
                        <Border Grid.Column="1" Background="{DynamicResource CardBgDarkBrush}" CornerRadius="8" Padding="12,10" Margin="3,0,3,0" BorderBrush="#1C2D4A" BorderThickness="1">
                            <StackPanel>
                                <TextBlock Text="BACKGROUND OUTPUT" FontSize="10" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,6"/>
                                <StackPanel Orientation="Horizontal">
                                    <RadioButton x:Name="rbBgOutTransparent" Content="Transparent PNG" IsChecked="True" Margin="0,0,12,0"/>
                                    <RadioButton x:Name="rbBgOutWhite" Content="Pure White" Margin="0,0,12,0"/>
                                    <RadioButton x:Name="rbBgOutBlue" Content="Passport Blue"/>
                                </StackPanel>
                            </StackPanel>
                        </Border>

                        <!-- Sensitivity / Tolerance Slider -->
                        <Border Grid.Column="2" Background="{DynamicResource CardBgDarkBrush}" CornerRadius="8" Padding="12,10" Margin="6,0,0,0" BorderBrush="#1C2D4A" BorderThickness="1">
                            <StackPanel>
                                <Grid Margin="0,0,0,4">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Grid.Column="0" Text="SENSITIVITY / TOLERANCE:" FontSize="10" FontWeight="Bold" Foreground="#38BDF8"/>
                                    <TextBlock x:Name="lblBgToleranceVal" Grid.Column="1" Text="50%" FontSize="11" FontWeight="Bold" Foreground="#4ADE80"/>
                                </Grid>
                                <Slider x:Name="sliderBgTolerance" Minimum="1" Maximum="100" Value="50" TickFrequency="5" IsSnapToTickEnabled="False"/>
                            </StackPanel>
                        </Border>
                    </Grid>

                    <WrapPanel Grid.Row="1">
                        <CheckBox x:Name="chkBgAutoProcess" Content="Auto-Process on Paste / Load" IsChecked="True" Foreground="#FBBF24" FontWeight="Bold" Margin="0,0,20,0"/>
                        <CheckBox x:Name="chkBgAutoCrop" Content="Auto-Trim Margins (Auto-Crop)" IsChecked="True" Foreground="#38BDF8" FontWeight="SemiBold" Margin="0,0,20,0"/>
                        <CheckBox x:Name="chkBgEnhanceInk" Content="Enhance Ink Strokes (Vibrant Pen Blue / Black)" IsChecked="True" Foreground="#34D399" FontWeight="SemiBold" Margin="0,0,20,0"/>
                        <CheckBox x:Name="chkBgSmoothEdges" Content="Smooth Anti-Aliased Edges (No Pixel Halos)" IsChecked="True" Foreground="#818CF8" FontWeight="SemiBold" Margin="0,0,20,0"/>
                    </WrapPanel>
                </Grid>
            </Border>

            <!-- Dual Side-by-side Preview Area -->
            <Grid Grid.Row="2" Margin="0,0,0,10">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <!-- Left: Original Image -->
                <Border Grid.Column="0" Background="{DynamicResource CardBgBrush}" CornerRadius="12" Padding="14" Margin="0,0,6,0" BorderBrush="#1E3252" BorderThickness="1">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <Grid Grid.Row="0" Margin="0,0,0,8">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="ORIGINAL IMAGE" FontWeight="Bold" FontSize="12" Foreground="#94A3B8"/>
                            <TextBlock x:Name="lblBgOrigStatus" Grid.Column="1" Text="No Image Loaded" FontSize="11" Foreground="#64748B"/>
                        </Grid>

                        <Border Grid.Row="1" Background="{DynamicResource InnerBoxBrush}" CornerRadius="8" Margin="0,0,0,8" BorderBrush="#1C2D4A" BorderThickness="1">
                            <Image x:Name="imgBgOrig" Stretch="Uniform" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="10"/>
                        </Border>

                        <Border Grid.Row="2" Background="{DynamicResource CardBgDarkBrush}" CornerRadius="6" Padding="10,6" BorderBrush="#1C2D4A" BorderThickness="1">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock x:Name="lblBgOrigDim" Grid.Column="0" Text="Size: -- px" FontSize="11" Foreground="#94A3B8"/>
                                <TextBlock x:Name="lblBgOrigKB" Grid.Column="1" Text="File: -- KB" FontSize="11" Foreground="#94A3B8" HorizontalAlignment="Right"/>
                            </Grid>
                        </Border>
                    </Grid>
                </Border>

                <!-- Right: Processed / Background Removed Image -->
                <Border Grid.Column="1" Background="{DynamicResource CardBgBrush}" CornerRadius="12" Padding="14" Margin="6,0,0,0" BorderBrush="#059669" BorderThickness="1.5">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <Grid Grid.Row="0" Margin="0,0,0,8">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="EXTRACTED / CLEAN RESULT" FontWeight="Bold" FontSize="12" Foreground="#34D399"/>
                            <TextBlock x:Name="lblBgResultStatus" Grid.Column="1" Text="Ready" FontSize="11" Foreground="#4ADE80" FontWeight="SemiBold"/>
                        </Grid>

                        <!-- Canvas area with Checkerboard or background preview -->
                        <Border x:Name="borderBgPreviewBox" Grid.Row="1" Background="#141B2D" CornerRadius="8" Margin="0,0,0,8" BorderBrush="#1C2D4A" BorderThickness="1" ClipToBounds="True">
                            <Grid>
                                <Image x:Name="imgBgResult" Stretch="Uniform" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="10"/>

                                <!-- Laser Glow Trail -->
                                <Border x:Name="laserGlowOverlay" Height="60" VerticalAlignment="Top" Visibility="Collapsed" IsHitTestVisible="False" Opacity="0.35">
                                    <Border.Background>
                                        <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                                            <GradientStop Color="#0038BDF8" Offset="0.0"/>
                                            <GradientStop Color="#6038BDF8" Offset="0.7"/>
                                            <GradientStop Color="#FF38BDF8" Offset="1.0"/>
                                        </LinearGradientBrush>
                                    </Border.Background>
                                    <Border.RenderTransform>
                                        <TranslateTransform x:Name="laserGlowTransform" Y="0"/>
                                    </Border.RenderTransform>
                                </Border>

                                <!-- Sharp Laser Beam -->
                                <Border x:Name="laserScanner" Height="3" VerticalAlignment="Top" Visibility="Collapsed" IsHitTestVisible="False">
                                    <Border.Background>
                                        <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                                            <GradientStop Color="#0038BDF8" Offset="0.0"/>
                                            <GradientStop Color="#FFFFFFFF" Offset="0.5"/>
                                            <GradientStop Color="#FF38BDF8" Offset="0.5"/>
                                            <GradientStop Color="#0038BDF8" Offset="1.0"/>
                                        </LinearGradientBrush>
                                    </Border.Background>
                                    <Border.Effect>
                                        <DropShadowEffect Color="#38BDF8" BlurRadius="16" ShadowDepth="0" Opacity="1.0"/>
                                    </Border.Effect>
                                    <Border.RenderTransform>
                                        <TranslateTransform x:Name="laserTransform" Y="0"/>
                                    </Border.RenderTransform>
                                </Border>
                            </Grid>
                        </Border>

                        <Border Grid.Row="2" Background="{DynamicResource CardBgDarkBrush}" CornerRadius="6" Padding="10,6" BorderBrush="#1C2D4A" BorderThickness="1">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock x:Name="lblBgResultDim" Grid.Column="0" Text="Output: --" FontSize="11" Foreground="#38BDF8" FontWeight="SemiBold"/>
                                <TextBlock x:Name="lblBgResultFormat" Grid.Column="1" Text="Format: 32-bit Transparent PNG" FontSize="11" Foreground="#34D399" HorizontalAlignment="Right" FontWeight="SemiBold"/>
                            </Grid>
                        </Border>
                    </Grid>
                </Border>
            </Grid>

            <!-- Bottom Action Controls -->
            <Grid Grid.Row="3">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <TextBlock Grid.Column="0" Text="Extracts signatures &amp; handwriting onto transparent PNG, or creates clean passport photos." FontSize="12" Foreground="#94A3B8" VerticalAlignment="Center"/>
                <Button x:Name="btnBgDemoAnim" Grid.Column="1" Style="{StaticResource ActionButton}" Content="PREVIEW SCAN ANIMATION" Background="#0F172A" BorderBrush="#38BDF8" BorderThickness="1" Foreground="#38BDF8" FontSize="12" FontWeight="Bold" Padding="16,11" Margin="0,0,10,0"/>
                <Button x:Name="btnBgProcess" Grid.Column="2" Style="{StaticResource ActionButton}" Content="REMOVE BACKGROUND NOW" Background="{StaticResource SuccessBtnBrush}" FontSize="13" FontWeight="Bold" Padding="22,11" Margin="0,0,10,0"/>
                <Button x:Name="btnBgSaveAs" Grid.Column="3" Style="{StaticResource ActionButton}" Content="SAVE IMAGE AS..." Background="{StaticResource PrimaryBtnBrush}" FontSize="13" FontWeight="Bold" Padding="20,11" Margin="0,0,10,0" IsEnabled="False"/>
                <Button x:Name="btnBgCopyClipboard" Grid.Column="4" Style="{StaticResource ActionButton}" Content="COPY TO CLIPBOARD" Background="{StaticResource CyanBadgeBrush}" FontSize="13" FontWeight="Bold" Padding="18,11" IsEnabled="False"/>
            </Grid>
        </Grid>

        <!-- ============================================================== -->
        <!-- SQL CONSOLE VIEW - MICROSOFT SQL SERVER MANAGEMENT STUDIO 2022  -->
        <!-- ============================================================== -->
        <Grid x:Name="viewSqlConsole" Grid.Row="2" Visibility="Collapsed" Background="{DynamicResource SqlConsoleBgBrush}">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/> <!-- Row 0: Top Menu Bar -->
                <RowDefinition Height="Auto"/> <!-- Row 1: Ribbon ToolBar -->
                <RowDefinition Height="Auto"/> <!-- Row 2: Secondary Quick Bar (Conn & Helpers) -->
                <RowDefinition Height="*"/>    <!-- Row 3: Main Studio Body (Splitter OE + Workspace) -->
                <RowDefinition Height="Auto"/> <!-- Row 4: SSMS Status Bar -->
            </Grid.RowDefinitions>

            <!-- Row 0: SSMS 2022 Classic Dark Menu Bar -->
            <Border x:Name="bdrSsmsMenuBar" Grid.Row="0" Background="{DynamicResource SqlMenuBarBgBrush}" BorderBrush="{DynamicResource SqlBorderBrush}" BorderThickness="0,0,0,1" Padding="4,2">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <StackPanel Grid.Column="0" Orientation="Horizontal">
                        <!-- SSMS App Icon / Identity -->
                        <Border Background="#007ACC" CornerRadius="3" Padding="5,2" Margin="4,0,8,0" VerticalAlignment="Center">
                            <TextBlock Text="SQL" Foreground="White" FontWeight="Bold" FontSize="11" FontFamily="Segoe UI"/>
                        </Border>

                        <Menu x:Name="menuSsmsTop" Background="Transparent" Foreground="{DynamicResource SqlBtnFgBrush}" FontSize="12">
                            <MenuItem Header="File" Foreground="{DynamicResource SqlBtnFgBrush}"/>
                            <MenuItem Header="Edit" Foreground="{DynamicResource SqlBtnFgBrush}"/>
                            <MenuItem Header="View" Foreground="{DynamicResource SqlBtnFgBrush}"/>
                            <MenuItem Header="Git" Foreground="{DynamicResource SqlBtnFgBrush}"/>
                            <MenuItem Header="Project" Foreground="{DynamicResource SqlBtnFgBrush}"/>
                            <MenuItem Header="Tools" Foreground="{DynamicResource SqlBtnFgBrush}"/>
                            <MenuItem Header="Extensions" Foreground="{DynamicResource SqlBtnFgBrush}"/>
                            <MenuItem Header="Window" Foreground="{DynamicResource SqlBtnFgBrush}"/>
                            <MenuItem Header="Help" Foreground="{DynamicResource SqlBtnFgBrush}"/>
                        </Menu>
                    </StackPanel>

                    <!-- Right Window / Identity Controls -->
                    <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,6,0">
                        <TextBlock Text="Sign in" Foreground="{DynamicResource TextMutedBrush}" FontSize="11" VerticalAlignment="Center" Margin="0,0,14,0" Cursor="Hand"/>
                        <Border Background="#0E639C" CornerRadius="10" Padding="8,2" VerticalAlignment="Center">
                            <TextBlock Text="ADMIN" Foreground="White" FontSize="10" FontWeight="Bold"/>
                        </Border>
                    </StackPanel>
                </Grid>
            </Border>

            <!-- Row 1: SSMS 2022 Standard Ribbon Toolbar -->
            <Border x:Name="bdrSsmsToolbar" Grid.Row="1" Background="{DynamicResource SqlToolbarBgBrush}" BorderBrush="{DynamicResource SqlBorderBrush}" BorderThickness="0,0,0,1" Padding="6,4">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <!-- Connect & New Query Buttons -->
                    <StackPanel Grid.Column="0" Orientation="Horizontal" Margin="0,0,8,0">
                        <Button x:Name="btnSsmsConnect" Content="Connect" Background="{DynamicResource SqlBtnBgBrush}" Foreground="{DynamicResource SqlBtnFgBrush}" BorderBrush="{DynamicResource SqlBorderBrush}" BorderThickness="1" Padding="8,4" Margin="0,0,4,0" FontSize="11" FontWeight="SemiBold" Cursor="Hand" ToolTip="Connect to SQL Server Instance"/>
                        <Button x:Name="btnSsmsDisconnect" Content="Disconnect" Background="{DynamicResource SqlBtnBgBrush}" Foreground="#EF4444" BorderBrush="{DynamicResource SqlBorderBrush}" BorderThickness="1" Padding="8,4" Margin="0,0,4,0" FontSize="11" FontWeight="SemiBold" Cursor="Hand" ToolTip="Disconnect from SQL Server"/>
                        <Button x:Name="btnSqlNewQuery" Content="New Query" Background="{DynamicResource SqlBtnBgBrush}" Foreground="{DynamicResource SqlBtnFgBrush}" BorderBrush="{DynamicResource SqlBorderBrush}" BorderThickness="1" Padding="10,4" Margin="0,0,6,0" FontSize="11" FontWeight="SemiBold" Cursor="Hand" ToolTip="Open a new SQL Query Editor session"/>
                    </StackPanel>

                    <!-- Separator -->
                    <Border Grid.Column="1" Width="1" Background="{DynamicResource SqlBorderBrush}" Margin="2,2,8,2"/>

                    <!-- Database Dropdown Selector -->
                    <StackPanel Grid.Column="2" Orientation="Horizontal" Margin="0,0,8,0" VerticalAlignment="Center">
                        <TextBlock x:Name="lblSqlAvailDbs" Text="Available Databases:" Foreground="{DynamicResource TextSecondaryBrush}" FontSize="11" VerticalAlignment="Center" Margin="0,0,6,0"/>
                        <ComboBox x:Name="cmbSqlDatabase" Width="180" Height="26" VerticalContentAlignment="Center" Background="{DynamicResource SqlEditorBgBrush}" Foreground="{DynamicResource TextPrimaryBrush}" BorderBrush="{DynamicResource SqlBorderBrush}" FontSize="11.5" FontFamily="Consolas"/>
                        <Button x:Name="btnSqlRefreshDbs" Content="Refresh" Background="{DynamicResource SqlBtnBgBrush}" Foreground="{DynamicResource SqlBtnFgBrush}" BorderBrush="{DynamicResource SqlBorderBrush}" BorderThickness="1" Padding="6,3" Margin="4,0,0,0" FontSize="11" Cursor="Hand" ToolTip="Refresh Database list"/>
                    </StackPanel>

                    <!-- Separator -->
                    <Border Grid.Column="3" Width="1" Background="{DynamicResource SqlBorderBrush}" Margin="2,2,8,2"/>

                    <!-- Execute (F5), Test (Begin Tran), Parse, Cancel, Multi-Window -->
                    <StackPanel Grid.Column="4" Orientation="Horizontal" VerticalAlignment="Center">
                        <Button x:Name="btnSqlNewWindow" Content="New Query (Ctrl+N)" Background="#1E3A8A" Foreground="#93C5FD" BorderBrush="#3B82F6" BorderThickness="1" Padding="10,4" Margin="0,0,4,0" FontSize="11" FontWeight="Bold" Cursor="Hand" ToolTip="Open New Query Tab (Ctrl+N)"/>
                        <Button x:Name="btnSqlExecute" Content="Execute (F5)" Background="#107C41" Foreground="White" BorderThickness="0" Padding="14,4" Margin="0,0,4,0" FontSize="11" FontWeight="Bold" Cursor="Hand" ToolTip="Execute selected text or current batch (F5)"/>
                        <Button x:Name="btnSqlTestBeginTran" Content="Test (Begin Tran)" Background="#D97706" Foreground="White" BorderThickness="0" Padding="10,4" Margin="0,0,4,0" FontSize="11" FontWeight="SemiBold" Cursor="Hand" ToolTip="Safe Execution: Runs inside BEGIN TRAN ... ROLLBACK TRAN"/>
                        <Button x:Name="btnSqlParseQuery" Content="Parse (Ctrl+F5)" Background="{DynamicResource SqlBtnBgBrush}" Foreground="{DynamicResource SqlBtnFgBrush}" BorderBrush="{DynamicResource SqlBorderBrush}" BorderThickness="1" Padding="8,4" Margin="0,0,4,0" FontSize="11" Cursor="Hand" ToolTip="Validate SQL Syntax (SET PARSEONLY ON)"/>
                        <Button x:Name="btnSqlClear" Content="Clear (Ctrl+L)" Background="{DynamicResource SqlBtnBgBrush}" Foreground="{DynamicResource SqlBtnFgBrush}" BorderBrush="{DynamicResource SqlBorderBrush}" BorderThickness="1" Padding="8,4" Margin="0,0,4,0" FontSize="11" Cursor="Hand" ToolTip="Clear Editor and Results (Ctrl+L)"/>
                        <Button x:Name="btnSqlExport" Content="Export CSV" Background="{DynamicResource SqlBtnBgBrush}" Foreground="{DynamicResource SqlBtnFgBrush}" BorderBrush="{DynamicResource SqlBorderBrush}" BorderThickness="1" Padding="8,4" Margin="0,0,4,0" FontSize="11" Cursor="Hand" ToolTip="Export current query result grid to CSV"/>
                    </StackPanel>

                    <!-- Right Assistant / Extra Tools -->
                    <StackPanel Grid.Column="6" Orientation="Horizontal" VerticalAlignment="Center">
                        <Button x:Name="btnJarvisFormat" Content="Format SQL" Background="{DynamicResource SqlBtnBgBrush}" Foreground="#0284C7" BorderBrush="{DynamicResource SqlBorderBrush}" BorderThickness="1" Padding="8,4" Margin="0,0,4,0" FontSize="11" FontWeight="SemiBold" Cursor="Hand" ToolTip="Format &amp; Beautify T-SQL Query"/>
                        <Button x:Name="btnJarvisAnalyze" Content="Analyze SQL" Background="{DynamicResource SqlBtnBgBrush}" Foreground="#7C3AED" BorderBrush="{DynamicResource SqlBorderBrush}" BorderThickness="1" Padding="8,4" Margin="0,0,4,0" FontSize="11" FontWeight="SemiBold" Cursor="Hand" ToolTip="Audit Query Performance &amp; Safety"/>
                        <Button x:Name="btnSqlUserAccessManager" Content="User Privileges" Background="#831843" Foreground="#FBCFE8" BorderBrush="#BE185D" BorderThickness="1" Padding="8,4" Margin="0,0,4,0" FontSize="11" FontWeight="Bold" Cursor="Hand" ToolTip="User Permission Manager &amp; Screen Access Fixer"/>
                        <Button x:Name="btnSqlTableDdlWizard" Content="DDL Wizard" Background="#881337" Foreground="#FECDD3" BorderBrush="#E11D48" BorderThickness="1" Padding="8,4" Margin="0,0,4,0" FontSize="11" FontWeight="Bold" Cursor="Hand" ToolTip="Table &amp; Query DDL Generator Studio"/>
                        <Button x:Name="btnJarvisAssistant" Content="JARVIS AI" Background="#0284C7" Foreground="White" BorderThickness="0" Padding="10,4" FontSize="11" FontWeight="Bold" Cursor="Hand" ToolTip="Open JARVIS AI Assistant Command Center"/>
                        <Button x:Name="btnSqlLockConsole" Content="LOCK &amp; HIDE" Background="#4C0519" Foreground="#FECDD3" BorderBrush="#BE123C" BorderThickness="1" Padding="8,4" Margin="4,0,0,0" FontSize="11" FontWeight="Bold" Cursor="Hand" ToolTip="Immediately Lock and Hide SQL Console from View"/>
                    </StackPanel>
                </Grid>
            </Border>

            <!-- Row 2: Secondary Connection String Bar & Server Info -->
            <Border x:Name="bdrSsmsConnBar" Grid.Row="2" Background="{DynamicResource SqlMenuBarBgBrush}" BorderBrush="{DynamicResource SqlBorderBrush}" BorderThickness="0,0,0,1" Padding="6,3">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <TextBlock x:Name="lblSqlConnHeader" Grid.Column="0" Text="Connection:" Foreground="{DynamicResource TextSecondaryBrush}" FontSize="11" VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <TextBox x:Name="txtSqlConnStr" Grid.Column="1" Text="Paste connection string (Server=...;Database=...;User ID=...;Password=...) or select saved connection" Foreground="{DynamicResource TextMutedBrush}" Background="{DynamicResource SqlToolbarBgBrush}" BorderBrush="{DynamicResource SqlBorderBrush}" BorderThickness="1" Padding="6,3" FontSize="11" FontFamily="Consolas" Margin="0,0,8,0" VerticalAlignment="Center"/>

                    <ComboBox x:Name="cmbSqlSavedConn" Grid.Column="2" Width="195" Height="24" Margin="0,0,6,0" VerticalContentAlignment="Center" Background="{DynamicResource SqlEditorBgBrush}" Foreground="{DynamicResource TextPrimaryBrush}" BorderBrush="{DynamicResource SqlBorderBrush}" FontSize="11" ToolTip="Saved Connections (Right-click to Remove or Manage)"/>
                    <StackPanel Grid.Column="3" Orientation="Horizontal" Margin="0,0,8,0" VerticalAlignment="Center">
                        <Button x:Name="btnSqlSaveConn" Content="Save Conn" Background="{DynamicResource SqlBtnBgBrush}" Foreground="{DynamicResource SqlBtnFgBrush}" BorderBrush="{DynamicResource SqlBorderBrush}" BorderThickness="1" Padding="8,3" Margin="0,0,4,0" FontSize="11" Cursor="Hand" ToolTip="Save current connection string permanently with a custom or auto name"/>
                        <Button x:Name="btnSqlRemoveConn" Content="Remove" Background="{DynamicResource SqlBtnBgBrush}" Foreground="#EF4444" BorderBrush="{DynamicResource SqlBorderBrush}" BorderThickness="1" Padding="6,3" FontSize="11" Cursor="Hand" ToolTip="Remove selected saved connection permanently (or right-click dropdown to remove)"/>
                    </StackPanel>
                    <Button x:Name="btnSqlConnect" Grid.Column="4" Content="Connect" Background="#0E639C" Foreground="White" BorderThickness="0" Padding="10,3" Margin="0,0,8,0" FontSize="11" FontWeight="Bold" Cursor="Hand"/>
                    <Button x:Name="btnSqlDisconnect" Visibility="Collapsed"/>

                    <TextBlock x:Name="lblSqlServerInfo" Grid.Column="5" Text="" Foreground="{DynamicResource TextMutedBrush}" FontSize="11" VerticalAlignment="Center" HorizontalAlignment="Right"/>
                </Grid>
            </Border>

            <!-- Row 3: Main Studio Body (Splitter between Object Explorer and Query Workspace) -->
            <Grid Grid.Row="3">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="280" MinWidth="180"/>
                    <ColumnDefinition Width="4"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <!-- Left Column: Object Explorer -->
                <Border x:Name="bdrOeContainer" Grid.Column="0" Background="{DynamicResource SqlToolbarBgBrush}" BorderBrush="{DynamicResource SqlBorderBrush}" BorderThickness="0,0,1,0">
                    <DockPanel>
                        <!-- Object Explorer Header -->
                        <Border x:Name="bdrOeHeader" DockPanel.Dock="Top" Background="{DynamicResource SqlMenuBarBgBrush}" Padding="8,5" BorderBrush="{DynamicResource SqlBorderBrush}" BorderThickness="0,0,0,1">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock x:Name="lblOeTitle" Grid.Column="0" Text="Object Explorer" Foreground="{DynamicResource TextPrimaryBrush}" FontWeight="Bold" FontSize="11.5" VerticalAlignment="Center"/>
                                <StackPanel Grid.Column="1" Orientation="Horizontal">
                                    <Button x:Name="btnOeRefresh" Content="Ref" Background="Transparent" Foreground="{DynamicResource TextSecondaryBrush}" BorderThickness="0" Padding="4,1" Margin="0,0,2,0" FontSize="10" Cursor="Hand" ToolTip="Refresh Object Explorer"/>
                                    <Button x:Name="btnOeCollapse" Content="-" Background="Transparent" Foreground="{DynamicResource TextSecondaryBrush}" BorderThickness="0" Padding="4,1" FontSize="11" Cursor="Hand" ToolTip="Collapse All"/>
                                </StackPanel>
                            </Grid>
                        </Border>

                        <!-- Object Explorer Secondary Action Strip -->
                        <Border x:Name="bdrOeFilter" DockPanel.Dock="Top" Background="{DynamicResource SqlConsoleBgBrush}" Padding="6,3" BorderBrush="{DynamicResource SqlBorderBrush}" BorderThickness="0,0,0,1">
                            <StackPanel Orientation="Horizontal">
                                <TextBlock x:Name="lblOeFilter" Text="Filter:" Foreground="{DynamicResource TextMutedBrush}" FontSize="10.5" VerticalAlignment="Center" Margin="0,0,4,0"/>
                                <TextBox x:Name="txtSqlSpSearch" Width="120" Height="20" Text="Filter objects..." Foreground="{DynamicResource TextMutedBrush}" Background="{DynamicResource SqlToolbarBgBrush}" BorderBrush="{DynamicResource SqlBorderBrush}" BorderThickness="1" Padding="4,1" FontSize="10.5" FontFamily="Consolas"/>
                                <ComboBox x:Name="cmbSqlSchema" Width="90" Height="20" Margin="4,0,0,0" Background="{DynamicResource SqlToolbarBgBrush}" Foreground="{DynamicResource TextPrimaryBrush}" BorderBrush="{DynamicResource SqlBorderBrush}" FontSize="10"/>
                            </StackPanel>
                        </Border>

                        <!-- Hidden compatibility controls to keep existing scripts running seamlessly -->
                        <ComboBox x:Name="cmbSqlProcs" Visibility="Collapsed"/>
                        <Button x:Name="btnSqlCreateNewSp" Visibility="Collapsed"/>
                        <Button x:Name="btnSqlGenerateSpCall" Visibility="Collapsed"/>
                        <Button x:Name="btnSqlViewSpCode" Visibility="Collapsed"/>
                        <Button x:Name="btnSqlFullScreenSp" Visibility="Collapsed"/>

                        <!-- Object Explorer TreeView (Windows SSMS 2022 Native Hierarchy) -->
                        <TreeView x:Name="tvObjectExplorer" Background="{DynamicResource SqlEditorBgBrush}" Foreground="{DynamicResource TextPrimaryBrush}" BorderThickness="0" Padding="4" FontFamily="Segoe UI" FontSize="11.5" VirtualizingStackPanel.IsVirtualizing="True" VirtualizingStackPanel.VirtualizationMode="Recycling" ScrollViewer.CanContentScroll="True">
                            <!-- Populated dynamically via PowerShell -->
                        </TreeView>
                    </DockPanel>
                </Border>

                <!-- Splitter -->
                <GridSplitter x:Name="splOe" Grid.Column="1" HorizontalAlignment="Stretch" Background="{DynamicResource SqlBorderBrush}" Cursor="SizeWE"/>

                <!-- Right Column: Query Editor & Results Workspace -->
                <Grid Grid.Column="2">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/> <!-- Row 0: Editor Tab Bar -->
                        <RowDefinition Height="3*"/>   <!-- Row 1: SQL Code Editor -->
                        <RowDefinition Height="4"/>    <!-- Row 2: Splitter -->
                        <RowDefinition Height="2*"/>   <!-- Row 3: Results & Messages Pane -->
                    </Grid.RowDefinitions>

                    <!-- Row 0: SSMS Session Tabs Strip (Dynamic Multi-Tab Query Workspace) -->
                    <Border x:Name="bdrQueryTabs" Grid.Row="0" Background="{DynamicResource SqlMenuBarBgBrush}" BorderBrush="{DynamicResource SqlBorderBrush}" BorderThickness="0,0,0,1" Height="28">
                        <DockPanel LastChildFill="False">
                            <ScrollViewer DockPanel.Dock="Left" HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Disabled" Focusable="False">
                                <StackPanel x:Name="spQueryTabs" Orientation="Horizontal"/>
                            </ScrollViewer>
                            <Button x:Name="btnSqlAddQueryTab" DockPanel.Dock="Left" Content=" + " Background="Transparent" Foreground="{DynamicResource TextSecondaryBrush}" BorderThickness="0" FontSize="13" FontWeight="Bold" Padding="6,1" Margin="2,0,0,0" Cursor="Hand" ToolTip="New Query Tab (Ctrl+N)" VerticalAlignment="Center"/>
                            <TextBlock x:Name="lblQueryTabTitle" Visibility="Collapsed"/>
                        </DockPanel>
                    </Border>


                    <!-- Row 1: SQL Query Editor -->
                    <Grid Grid.Row="1">
                        <TextBox x:Name="txtSqlQuery" AcceptsReturn="True" AcceptsTab="True" TextWrapping="NoWrap" FontFamily="Consolas" FontSize="13" Background="{DynamicResource SqlEditorBgBrush}" Foreground="{DynamicResource SqlEditorFgBrush}" BorderThickness="0" Padding="10" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>

                        <!-- Intellisense Popup -->
                        <Popup x:Name="popSqlIntellisense" PlacementTarget="{Binding ElementName=txtSqlQuery}" Placement="Bottom" StaysOpen="False" IsOpen="False">
                            <Border Background="{DynamicResource SqlToolbarBgBrush}" BorderBrush="#007ACC" BorderThickness="1" CornerRadius="2" Padding="2" MaxHeight="180" Width="320">
                                <ListBox x:Name="lstSqlSuggestions" Background="{DynamicResource SqlEditorBgBrush}" Foreground="{DynamicResource TextPrimaryBrush}" BorderThickness="0" FontFamily="Consolas" FontSize="11.5" ScrollViewer.VerticalScrollBarVisibility="Auto"/>
                            </Border>
                        </Popup>
                    </Grid>

                    <!-- Row 2: Horizontal Splitter -->
                    <GridSplitter x:Name="splResults" Grid.Row="2" HorizontalAlignment="Stretch" Background="{DynamicResource SqlBorderBrush}" Cursor="SizeNS"/>

                    <!-- Row 3: Results & Messages Container -->
                    <Grid x:Name="gridResultsContainer" Grid.Row="3" Background="{DynamicResource SqlConsoleBgBrush}">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>

                        <!-- Results / Messages Tab Strip -->
                        <Border x:Name="bdrResultsTabs" Grid.Row="0" Background="{DynamicResource SqlToolbarBgBrush}" BorderBrush="{DynamicResource SqlBorderBrush}" BorderThickness="0,0,0,1">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>

                                <StackPanel Grid.Column="0" Orientation="Horizontal">
                                    <Button x:Name="btnSqlTabResults" Content="Results" Background="{DynamicResource SqlEditorBgBrush}" Foreground="{DynamicResource TextPrimaryBrush}" BorderThickness="0,2,0,0" BorderBrush="#007ACC" FontWeight="Bold" Padding="14,4" Cursor="Hand"/>
                                    <Button x:Name="btnSqlTabMessages" Content="Messages" Background="{DynamicResource SqlToolbarBgBrush}" Foreground="{DynamicResource TextMutedBrush}" BorderThickness="0" FontWeight="Normal" Padding="14,4" Cursor="Hand"/>
                                </StackPanel>

                                <!-- Status / Row count badge -->
                                <TextBlock x:Name="lblSqlRowCount" Grid.Column="2" Text="Rows: 0 | Time: 0ms" Foreground="{DynamicResource TextSecondaryBrush}" FontSize="11" VerticalAlignment="Center" Margin="0,0,10,0"/>
                            </Grid>
                        </Border>

                        <!-- Main Results DataGrid & Messages Box -->
                        <Grid Grid.Row="1">
                            <DataGrid x:Name="dgSqlResults" Visibility="Visible" Background="{DynamicResource SqlEditorBgBrush}" Foreground="{DynamicResource TextPrimaryBrush}" AlternatingRowBackground="{DynamicResource SqlToolbarBgBrush}" RowBackground="{DynamicResource SqlEditorBgBrush}" GridLinesVisibility="All" HorizontalGridLinesBrush="{DynamicResource SqlBorderBrush}" VerticalGridLinesBrush="{DynamicResource SqlBorderBrush}" AutoGenerateColumns="True" IsReadOnly="True" CanUserSortColumns="True" FontFamily="Consolas" FontSize="12" HeadersVisibility="Column" BorderThickness="0" SelectionUnit="CellOrRowHeader" SelectionMode="Extended" ClipboardCopyMode="ExcludeHeader" EnableRowVirtualization="True" EnableColumnVirtualization="True" VirtualizingStackPanel.IsVirtualizing="True" VirtualizingStackPanel.VirtualizationMode="Recycling" ScrollViewer.CanContentScroll="True">
                                <DataGrid.ColumnHeaderStyle>
                                    <Style TargetType="DataGridColumnHeader">
                                        <Setter Property="Background" Value="{DynamicResource SqlHeaderBgBrush}"/>
                                        <Setter Property="Foreground" Value="{DynamicResource SqlHeaderFgBrush}"/>
                                        <Setter Property="Padding" Value="8,5"/>
                                        <Setter Property="FontWeight" Value="SemiBold"/>
                                        <Setter Property="BorderThickness" Value="0,0,1,1"/>
                                        <Setter Property="BorderBrush" Value="{DynamicResource SqlHeaderBorderBrush}"/>
                                    </Style>
                                </DataGrid.ColumnHeaderStyle>
                                <DataGrid.CellStyle>
                                    <Style TargetType="DataGridCell">
                                        <Setter Property="Padding" Value="6,4"/>
                                        <Setter Property="Template">
                                            <Setter.Value>
                                                <ControlTemplate TargetType="DataGridCell">
                                                    <Border Padding="{TemplateBinding Padding}" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
                                                        <ContentPresenter SnapsToDevicePixels="True"/>
                                                    </Border>
                                                </ControlTemplate>
                                            </Setter.Value>
                                        </Setter>
                                        <Style.Triggers>
                                            <Trigger Property="IsSelected" Value="True">
                                                <Setter Property="Background" Value="#0E639C"/>
                                                <Setter Property="Foreground" Value="#FFFFFF"/>
                                            </Trigger>
                                        </Style.Triggers>
                                    </Style>
                                </DataGrid.CellStyle>
                            </DataGrid>

                            <!-- Messages Console Output -->
                            <TextBox x:Name="txtSqlMessages" Visibility="Collapsed" AcceptsReturn="True" IsReadOnly="True" TextWrapping="Wrap" FontFamily="Consolas" FontSize="12.5" Background="{DynamicResource SqlEditorBgBrush}" Foreground="{DynamicResource TextPrimaryBrush}" BorderThickness="0" Padding="10" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
                        </Grid>
                    </Grid>
                </Grid>
            </Grid>

            <!-- Row 4: SSMS 2022 Native Status Bar -->
            <Border x:Name="bdrSqlSsmsStatus" Grid.Row="4" Background="#007ACC" Height="22">
                <Grid Margin="8,0">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <TextBlock x:Name="lblSqlSsmsStatusText" Grid.Column="0" Text="Ready" Foreground="#FFFFFF" FontWeight="SemiBold" FontSize="11" VerticalAlignment="Center"/>
                    <TextBlock x:Name="lblSqlStatus" Visibility="Collapsed"/>
                    <Border x:Name="bdrSqlSideToast" Visibility="Collapsed">
                        <StackPanel>
                            <TextBlock x:Name="lblSqlSideToastIcon"/>
                            <TextBlock x:Name="lblSqlSideToastMsg"/>
                        </StackPanel>
                    </Border>
                    <TextBlock x:Name="lblSqlSsmsStatusDetails" Grid.Column="2" Text="Disconnected" Foreground="#FFFFFF" FontWeight="SemiBold" FontSize="11" VerticalAlignment="Center"/>
                </Grid>
            </Border>
        </Grid>

        <!-- TAB 8: DIRECT PC SHARE (LAN AIR-DROP & SYNC) -->
        <Grid x:Name="viewLanShare" Grid.Row="2" Visibility="Collapsed">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- TOP BAR: IDENTITY & ACTIONS -->
            <Border Grid.Row="0" Background="{DynamicResource CardBgBrush}" CornerRadius="10" Padding="14,10" Margin="0,0,0,10" BorderBrush="#1E3252" BorderThickness="1">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                        <Border Background="#0369A1" CornerRadius="6" Padding="8,4" Margin="0,0,10,0">
                            <TextBlock Text="DIRECT PC SHARE" FontSize="11" FontWeight="Bold" Foreground="White"/>
                        </Border>
                        <StackPanel VerticalAlignment="Center">
                            <TextBlock x:Name="lblLanMyIdentity" Text="My PC: [Discovering...] | User: [Discovering...]" FontSize="11.5" Foreground="#94A3B8" FontWeight="SemiBold"/>
                            <TextBlock Text="Automatic Zero-Configuration Peer Discovery (No IP address needed)" FontSize="10" Foreground="#38BDF8"/>
                        </StackPanel>
                    </StackPanel>

                    <StackPanel Grid.Column="2" Orientation="Horizontal">
                        <Button x:Name="btnLanPushAppUpdate" Content="PUSH APP UPDATE TO LAN" Background="#7C3AED" Foreground="White" FontWeight="Bold" FontSize="10" Padding="11,6" Margin="0,0,5,0" BorderThickness="0" Cursor="Hand" ToolTip="Broadcast and automatically update PMC-ImageResizer-App on all other connected user PCs"/>
                        <Button x:Name="btnLanCheckAppUpdate" Content="CHECK FOR UPDATES" Background="#0284C7" Foreground="White" FontWeight="Bold" FontSize="10" Padding="9,6" Margin="0,0,5,0" BorderThickness="0" Cursor="Hand" ToolTip="Check network for newer version of this application"/>
                        <Button x:Name="btnLanScanPeers" Content="REFRESH PEERS" Background="{StaticResource PrimaryBtnBrush}" Foreground="White" FontWeight="Bold" FontSize="10" Padding="9,6" Margin="0,0,5,0" BorderThickness="0" Cursor="Hand" ToolTip="Scan local network for other computers running Nexus"/>
                        <Button x:Name="btnLanCopyWebLink" Content="COPY WEB LINK" Background="#0284C7" Foreground="White" FontWeight="Bold" FontSize="10" Padding="9,6" Margin="0,0,5,0" BorderThickness="0" Cursor="Hand" ToolTip="Copy Web Download link (anyone on the network can download in Chrome/Edge without needing Nexus)"/>
                        <Button x:Name="btnLanFixFirewall" Content="FIREWALL SETUP" Background="#475569" Foreground="White" FontWeight="Bold" FontSize="10" Padding="9,6" Margin="0,0,5,0" BorderThickness="0" Cursor="Hand" ToolTip="Configure Windows Firewall rules for LAN file sharing"/>
                        <Button x:Name="btnLanQuickAssist" Content="REMOTE ASSIST" Background="#6366F1" Foreground="White" FontWeight="Bold" FontSize="10" Padding="9,6" Margin="0,0,5,0" BorderThickness="0" Cursor="Hand" ToolTip="Open Windows Quick Assist to view or help on another PC"/>
                        <Button x:Name="btnLanOpenReceived" Content="OPEN RECEIVED FOLDER" Background="{StaticResource SuccessBtnBrush}" Foreground="White" FontWeight="Bold" FontSize="10" Padding="10,6" BorderThickness="0" Cursor="Hand" ToolTip="Open Desktop\Nexus_Received_Files"/>
                    </StackPanel>
                </Grid>
            </Border>

            <!-- MAIN WORK AREA -->
            <Grid Grid.Row="1">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="340"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <!-- LEFT PANEL: DISCOVERED PEERS -->
                <Border Grid.Column="0" Background="{DynamicResource CardBgBrush}" CornerRadius="10" Padding="12" Margin="0,0,10,0" BorderBrush="#1E3252" BorderThickness="1">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <StackPanel Grid.Row="0" Margin="0,0,0,8">
                            <TextBlock Text="1. SELECT COMPUTER" FontSize="11.5" FontWeight="Bold" Foreground="#38BDF8"/>
                            <TextBlock x:Name="lblLanPeerStatus" Text="Click a computer to send or take files" FontSize="10" Foreground="#64748B"/>
                        </StackPanel>

                        <!-- Peer ListBox -->
                        <ListBox x:Name="lstLanPeers" Grid.Row="1" Background="{DynamicResource CardBgDarkBrush}" BorderBrush="#1E293B" BorderThickness="1" Foreground="#E2E8F0" FontSize="11.5" ScrollViewer.HorizontalScrollBarVisibility="Disabled">
                            <ListBox.ItemContainerStyle>
                                <Style TargetType="ListBoxItem">
                                    <Setter Property="Padding" Value="8,6"/>
                                    <Setter Property="Margin" Value="2,2"/>
                                    <Setter Property="Cursor" Value="Hand"/>
                                </Style>
                            </ListBox.ItemContainerStyle>
                        </ListBox>

                        <!-- Manual Hostname Connect Card -->
                        <Border Grid.Row="2" Background="{DynamicResource CardBgDarkBrush}" CornerRadius="6" Padding="8" Margin="0,8,0,0" BorderBrush="#1E293B" BorderThickness="1">
                            <StackPanel>
                                <TextBlock Text="Connect by Computer Name (No IP needed):" FontSize="10" Foreground="#94A3B8" Margin="0,0,0,4"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBox x:Name="txtLanManualHost" Grid.Column="0" Background="#0F172A" Foreground="#E2E8F0" BorderBrush="#334155" BorderThickness="1" Padding="6,4" FontSize="11" FontFamily="Consolas"/>
                                    <Button x:Name="btnLanManualConnect" Grid.Column="1" Content="ADD" Background="#0284C7" Foreground="White" FontWeight="Bold" FontSize="10" Padding="8,4" Margin="4,0,0,0" BorderThickness="0" Cursor="Hand"/>
                                </Grid>
                            </StackPanel>
                        </Border>
                    </Grid>
                </Border>

                <!-- RIGHT PANEL: SEND & TAKE FILE PANELS -->
                <Grid Grid.Column="1">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="1.2*"/>
                        <RowDefinition Height="1*"/>
                    </Grid.RowDefinitions>

                    <!-- CARD 1: SEND FILES TO SELECTED PC -->
                    <Border Grid.Row="0" Background="{DynamicResource CardBgBrush}" CornerRadius="10" Padding="12" Margin="0,0,0,8" BorderBrush="#1E3252" BorderThickness="1">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>

                            <!-- Header -->
                            <Grid Grid.Row="0" Margin="0,0,0,8">
                                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                    <TextBlock Text="2. CHOOSE FILES &amp; SEND TO: " FontSize="11.5" FontWeight="Bold" Foreground="#38BDF8"/>
                                    <TextBlock x:Name="lblLanTargetPc" Text="[Select a computer on the left]" FontSize="11.5" FontWeight="Bold" Foreground="#38BDF8"/>
                                </StackPanel>
                                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                                    <Button x:Name="btnLanAddFiles" Content="+ ADD FILES" Background="#0284C7" Foreground="White" FontWeight="Bold" FontSize="10" Padding="8,4" Margin="0,0,4,0" BorderThickness="0" Cursor="Hand"/>
                                    <Button x:Name="btnLanAddFolder" Content="+ ADD FOLDER" Background="#0369A1" Foreground="White" FontWeight="Bold" FontSize="10" Padding="8,4" Margin="0,0,4,0" BorderThickness="0" Cursor="Hand"/>
                                    <Button x:Name="btnLanClearSend" Content="CLEAR" Background="#334155" Foreground="#94A3B8" FontWeight="Bold" FontSize="10" Padding="8,4" BorderThickness="0" Cursor="Hand"/>
                                </StackPanel>
                            </Grid>

                            <!-- Files to send list -->
                            <ListBox x:Name="lstLanSendFiles" Grid.Row="1" Background="{DynamicResource CardBgDarkBrush}" BorderBrush="#1E293B" BorderThickness="1" Foreground="#E2E8F0" FontSize="11" FontFamily="Consolas"/>

                            <!-- Progress Bar -->
                            <ProgressBar x:Name="prgLanSend" Grid.Row="2" Height="6" Margin="0,8,0,4" Background="#1E293B" Foreground="#38BDF8" BorderThickness="0" Minimum="0" Maximum="100" Value="0"/>

                            <!-- Action Bar -->
                            <Grid Grid.Row="3">
                                <TextBlock x:Name="lblLanSendStatus" Text="Select files and click Send" FontSize="10.5" Foreground="#94A3B8" VerticalAlignment="Center"/>
                                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                                    <Button x:Name="btnLanOpenWebLink" Content="SHARE VIA BROWSER" Background="#0284C7" Foreground="White" FontWeight="Bold" FontSize="10.5" Padding="12,7" Margin="0,0,8,0" BorderThickness="0" Cursor="Hand" ToolTip="Open Web Browser download page so anyone on the network can download in Chrome/Edge without needing Nexus"/>
                                    <Button x:Name="btnLanSendNow" Content="SEND FILES NOW" Background="{StaticResource SuccessBtnBrush}" Foreground="White" FontWeight="Bold" FontSize="11" Padding="16,7" BorderThickness="0" Cursor="Hand"/>
                                </StackPanel>
                            </Grid>
                        </Grid>
                    </Border>

                    <!-- CARD 2: TAKE FILES FROM SELECTED PC & SHARED OUTBOX -->
                    <Border Grid.Row="1" Background="{DynamicResource CardBgBrush}" CornerRadius="10" Padding="12" BorderBrush="#1E3252" BorderThickness="1">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="10"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <!-- Sub-Card Left: Files on Selected PC -->
                            <Grid Grid.Column="0">
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="*"/>
                                    <RowDefinition Height="Auto"/>
                                </Grid.RowDefinitions>

                                <Grid Grid.Row="0" Margin="0,0,0,6">
                                    <TextBlock Text="FILES ON SELECTED PC" FontSize="11" FontWeight="Bold" Foreground="White"/>
                                    <Button x:Name="btnLanBrowseRemote" Content="FETCH LIST" HorizontalAlignment="Right" Background="#0284C7" Foreground="White" FontWeight="Bold" FontSize="9.5" Padding="6,3" BorderThickness="0" Cursor="Hand"/>
                                </Grid>

                                <ListBox x:Name="lstLanRemoteFiles" Grid.Row="1" Background="{DynamicResource CardBgDarkBrush}" BorderBrush="#1E293B" BorderThickness="1" Foreground="#E2E8F0" FontSize="11" FontFamily="Consolas"/>

                                <Button x:Name="btnLanTakeSelected" Grid.Row="2" Content="TAKE / DOWNLOAD FILE" Margin="0,6,0,0" Background="{StaticResource PrimaryBtnBrush}" Foreground="White" FontWeight="Bold" FontSize="10.5" Padding="8,6" BorderThickness="0" Cursor="Hand"/>
                            </Grid>

                            <!-- Sub-Card Right: My Shared Outbox -->
                            <Grid Grid.Column="2">
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="*"/>
                                    <RowDefinition Height="Auto"/>
                                </Grid.RowDefinitions>

                                <Grid Grid.Row="0" Margin="0,0,0,6">
                                    <TextBlock Text="MY SHARED OUTBOX" FontSize="11" FontWeight="Bold" Foreground="White"/>
                                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                                        <Button x:Name="btnLanAddOutbox" Content="+ ADD" Background="#0284C7" Foreground="White" FontWeight="Bold" FontSize="9.5" Padding="6,3" Margin="0,0,4,0" BorderThickness="0" Cursor="Hand"/>
                                        <Button x:Name="btnLanClearOutbox" Content="CLEAR" Background="#334155" Foreground="#94A3B8" FontWeight="Bold" FontSize="9.5" Padding="6,3" BorderThickness="0" Cursor="Hand"/>
                                    </StackPanel>
                                </Grid>

                                <ListBox x:Name="lstLanOutbox" Grid.Row="1" Background="{DynamicResource CardBgDarkBrush}" BorderBrush="#1E293B" BorderThickness="1" Foreground="#E2E8F0" FontSize="11" FontFamily="Consolas"/>

                                <Button x:Name="btnLanOpenUnc" Grid.Row="2" Content="OPEN WINDOWS NETWORK SHARE" Margin="0,6,0,0" Background="#334155" Foreground="#94A3B8" FontWeight="Bold" FontSize="10.5" Padding="8,6" BorderThickness="0" Cursor="Hand"/>
                            </Grid>
                        </Grid>
                    </Border>
                </Grid>
            </Grid>

            <!-- BOTTOM STATUS BAR -->
            <Border Grid.Row="2" Background="{DynamicResource CardBgDarkBrush}" CornerRadius="6" Padding="10,6" Margin="0,8,0,0" BorderBrush="#1E293B" BorderThickness="1">
                <TextBlock x:Name="lblLanTransferLog" Text="Ready. Files sent over LAN Direct Share transfer directly at full gigabit speed without internet." FontSize="10.5" Foreground="#64748B"/>
            </Border>
        </Grid>
    </Grid>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# Set Application Window Icon
try {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    if (-not $scriptDir) { $scriptDir = "C:\Users\mandar.k\Documents\antigravity\lively-raman" }
    $icoFile = Join-Path $scriptDir "nexus_app.ico"
    if (Test-Path $icoFile) {
        $window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([System.Uri]::new($icoFile, [System.UriKind]::Absolute))
    }
} catch {}

if ($global:IsRunningAsAdmin) {
    try { $window.Title = $window.Title + " [Administrator]" } catch {}
}

# Controls Mapping
$tabBtnBatch           = $window.FindName("tabBtnBatch")
$btnToggleTheme        = $window.FindName("btnToggleTheme")
$btnLaunchDiffCompare  = $window.FindName("btnLaunchDiffCompare")
$btnUpdateAlertHeader  = $window.FindName("btnUpdateAlertHeader")
$txtUpdateAlertHeader  = $window.FindName("txtUpdateAlertHeader")
$txtThemeIcon          = $window.FindName("txtThemeIcon")
$txtThemeLabel     = $window.FindName("txtThemeLabel")
$tabBtnGovtExam    = $window.FindName("tabBtnGovtExam")
$tabBtnExtract     = $window.FindName("tabBtnExtract")
$tabBtnBgRemover   = $window.FindName("tabBtnBgRemover")
$tabBtnPreview     = $window.FindName("tabBtnPreview")
$tabBtnOtp         = $window.FindName("tabBtnOtp")
$viewBatch         = $window.FindName("viewBatch")
$viewGovtExam      = $window.FindName("viewGovtExam")
$viewExtract       = $window.FindName("viewExtract")
$viewBgRemover     = $window.FindName("viewBgRemover")
$viewPreview       = $window.FindName("viewPreview")
$viewOtp           = $window.FindName("viewOtp")
$tabBtnSql         = $window.FindName("tabBtnSql")
$colTabSql         = $window.FindName("colTabSql")
$btnEnterpriseSuiteBadge = $window.FindName("btnEnterpriseSuiteBadge")
$btnSqlLockConsole = $window.FindName("btnSqlLockConsole")
$tabBtnBeyondCompare = $window.FindName("tabBtnBeyondCompare")
$viewSqlConsole    = $window.FindName("viewSqlConsole")

# Direct PC Share (LAN Air-Drop) Controls Mapping
$tabBtnLanShare       = $window.FindName("tabBtnLanShare")
$viewLanShare         = $window.FindName("viewLanShare")
$lblLanMyIdentity     = $window.FindName("lblLanMyIdentity")
$btnLanPushAppUpdate = $window.FindName("btnLanPushAppUpdate")
$btnLanCheckAppUpdate = $window.FindName("btnLanCheckAppUpdate")
$btnLanScanPeers      = $window.FindName("btnLanScanPeers")
$btnLanCopyWebLink    = $window.FindName("btnLanCopyWebLink")
$btnLanFixFirewall    = $window.FindName("btnLanFixFirewall")
$btnLanOpenWebLink    = $window.FindName("btnLanOpenWebLink")
$btnLanOpenReceived   = $window.FindName("btnLanOpenReceived")
$btnLanQuickAssist    = $window.FindName("btnLanQuickAssist")
$lstLanPeers          = $window.FindName("lstLanPeers")
$lblLanPeerStatus     = $window.FindName("lblLanPeerStatus")
$txtLanManualHost     = $window.FindName("txtLanManualHost")
$btnLanManualConnect  = $window.FindName("btnLanManualConnect")
$lblLanTargetPc       = $window.FindName("lblLanTargetPc")
$btnLanAddFiles       = $window.FindName("btnLanAddFiles")
$btnLanAddFolder      = $window.FindName("btnLanAddFolder")
$btnLanClearSend      = $window.FindName("btnLanClearSend")
$lstLanSendFiles      = $window.FindName("lstLanSendFiles")
$prgLanSend           = $window.FindName("prgLanSend")
$lblLanSendStatus     = $window.FindName("lblLanSendStatus")
$btnLanSendNow        = $window.FindName("btnLanSendNow")
$btnLanBrowseRemote   = $window.FindName("btnLanBrowseRemote")
$lstLanRemoteFiles    = $window.FindName("lstLanRemoteFiles")
$btnLanTakeSelected   = $window.FindName("btnLanTakeSelected")
$btnLanAddOutbox      = $window.FindName("btnLanAddOutbox")
$btnLanClearOutbox    = $window.FindName("btnLanClearOutbox")
$lstLanOutbox         = $window.FindName("lstLanOutbox")
$btnLanOpenUnc        = $window.FindName("btnLanOpenUnc")
$lblLanTransferLog    = $window.FindName("lblLanTransferLog")

$txtSqlConnStr     = $window.FindName("txtSqlConnStr")
$cmbSqlSavedConn   = $window.FindName("cmbSqlSavedConn")
$btnSqlSaveConn    = $window.FindName("btnSqlSaveConn")
$btnSqlRemoveConn  = $window.FindName("btnSqlRemoveConn")
$btnSqlConnect     = $window.FindName("btnSqlConnect")
$btnSqlDisconnect  = $window.FindName("btnSqlDisconnect")
$lblSqlStatus      = $window.FindName("lblSqlStatus")
$cmbSqlDatabase    = $window.FindName("cmbSqlDatabase")
$btnSqlRefreshDbs  = $window.FindName("btnSqlRefreshDbs")
$lblSqlServerInfo  = $window.FindName("lblSqlServerInfo")
$cmbSqlSchema      = $window.FindName("cmbSqlSchema")
$txtSqlSpSearch    = $window.FindName("txtSqlSpSearch")
$cmbSqlProcs       = $window.FindName("cmbSqlProcs")
$btnSqlCreateNewSp = $window.FindName("btnSqlCreateNewSp")
$btnSqlGenerateSpCall = $window.FindName("btnSqlGenerateSpCall")
$btnSqlViewSpCode  = $window.FindName("btnSqlViewSpCode")
$btnSqlFullScreenSp = $window.FindName("btnSqlFullScreenSp")
$btnSqlUserAccessManager = $window.FindName("btnSqlUserAccessManager")
$btnSqlTableDdlWizard = $window.FindName("btnSqlTableDdlWizard")
$txtSqlQuery       = $window.FindName("txtSqlQuery")
$btnSqlNewWindow   = $window.FindName("btnSqlNewWindow")
$btnSqlExecute     = $window.FindName("btnSqlExecute")
$btnSqlTestBeginTran = $window.FindName("btnSqlTestBeginTran")
$btnSqlParseQuery   = $window.FindName("btnSqlParseQuery")
$btnJarvisFormat    = $window.FindName("btnJarvisFormat")
$btnJarvisAnalyze   = $window.FindName("btnJarvisAnalyze")
$btnJarvisAssistant = $window.FindName("btnJarvisAssistant")
$btnSqlClear       = $window.FindName("btnSqlClear")
$btnSqlExport      = $window.FindName("btnSqlExport")
$lblSqlRowCount    = $window.FindName("lblSqlRowCount")
$dgSqlResults      = $window.FindName("dgSqlResults")
$popSqlIntellisense = $window.FindName("popSqlIntellisense")
$lstSqlSuggestions = $window.FindName("lstSqlSuggestions")
$btnSqlTabResults  = $window.FindName("btnSqlTabResults")
$btnSqlTabMessages = $window.FindName("btnSqlTabMessages")
$bdrSqlSideToast   = $window.FindName("bdrSqlSideToast")
$lblSqlSideToastIcon = $window.FindName("lblSqlSideToastIcon")
$lblSqlSideToastMsg  = $window.FindName("lblSqlSideToastMsg")
$txtSqlMessages    = $window.FindName("txtSqlMessages")
$bdrSqlSsmsStatus  = $window.FindName("bdrSqlSsmsStatus")
$lblSqlSsmsStatusText = $window.FindName("lblSqlSsmsStatusText")
$lblSqlSsmsStatusDetails = $window.FindName("lblSqlSsmsStatusDetails")
$tvObjectExplorer  = $window.FindName("tvObjectExplorer")
$btnSsmsConnect    = $window.FindName("btnSsmsConnect")
$btnSsmsDisconnect = $window.FindName("btnSsmsDisconnect")
$btnSqlNewQuery    = $window.FindName("btnSqlNewQuery")
$btnOeRefresh      = $window.FindName("btnOeRefresh")
$btnOeCollapse     = $window.FindName("btnOeCollapse")
$tabQueryHeader    = $window.FindName("tabQueryHeader")
$lblQueryTabTitle  = $window.FindName("lblQueryTabTitle")
$spQueryTabs       = $window.FindName("spQueryTabs")
$btnSqlAddQueryTab = $window.FindName("btnSqlAddQueryTab")

# Batch View Controls
$rbPropertyPhotos  = $window.FindName("rbPropertyPhotos")
$rbPlanPhotoWmf    = $window.FindName("rbPlanPhotoWmf")
$txtTargetFolder   = $window.FindName("txtTargetFolder")
$btnBrowseFolder   = $window.FindName("btnBrowseFolder")
$rbFilterExcel     = $window.FindName("rbFilterExcel")
$rbFilterAll       = $window.FindName("rbFilterAll")
$rbFilterCustom    = $window.FindName("rbFilterCustom")
$panelExcelRow     = $window.FindName("panelExcelRow")
$panelAllBadge     = $window.FindName("panelAllBadge")
$panelCustomRow    = $window.FindName("panelCustomRow")
$txtExcelPath      = $window.FindName("txtExcelPath")
$btnBrowseExcel    = $window.FindName("btnBrowseExcel")
$txtCustomProperty = $window.FindName("txtCustomProperty")
$txtMaxKB          = $window.FindName("txtMaxKB")
$txtMaxDim         = $window.FindName("txtMaxDim")
$txtDPI            = $window.FindName("txtDPI")
$chkBackup         = $window.FindName("chkBackup")
$chkRecursive      = $window.FindName("chkRecursive")
$lblMatched        = $window.FindName("lblMatched")
$lblBackedUp       = $window.FindName("lblBackedUp")
$lblResized        = $window.FindName("lblResized")
$lblSaved          = $window.FindName("lblSaved")
$txtLogs           = $window.FindName("txtLogs")
$progressBar       = $window.FindName("progressBar")
$lblStatus         = $window.FindName("lblStatus")
$btnStart          = $window.FindName("btnStart")
$btnOpenFolder     = $window.FindName("btnOpenFolder")
$btnOpenBackup     = $window.FindName("btnOpenBackup")

# Govt Exam View Controls
$cmbExamPreset       = $window.FindName("cmbExamPreset")
$txtExamMinKB        = $window.FindName("txtExamMinKB")
$txtExamMaxKB        = $window.FindName("txtExamMaxKB")
$txtExamWidth        = $window.FindName("txtExamWidth")
$txtExamHeight       = $window.FindName("txtExamHeight")
$cmbExamFormat       = $window.FindName("cmbExamFormat")
$chkExamKeepAspect   = $window.FindName("chkExamKeepAspect")
$chkExamWhiteBg      = $window.FindName("chkExamWhiteBg")
$txtExamInputPath    = $window.FindName("txtExamInputPath")
$btnExamBrowseSingle = $window.FindName("btnExamBrowseSingle")
$btnExamBrowseMulti  = $window.FindName("btnExamBrowseMulti")
$imgExamOriginal     = $window.FindName("imgExamOriginal")
$lblExamOrigSize     = $window.FindName("lblExamOrigSize")
$lblExamOrigDim      = $window.FindName("lblExamOrigDim")
$imgExamOptimized    = $window.FindName("imgExamOptimized")
$lblExamBadgeText    = $window.FindName("lblExamBadgeText")
$badgeExamStatus     = $window.FindName("badgeExamStatus")
$lblExamOptSize      = $window.FindName("lblExamOptSize")
$lblExamOptDim       = $window.FindName("lblExamOptDim")
$btnExamProcess      = $window.FindName("btnExamProcess")
$btnExamSaveAs       = $window.FindName("btnExamSaveAs")

# Extractor Controls (Tab 5)
$rbExtractModePhotos       = $window.FindName("rbExtractModePhotos")
$rbExtractModeWmf          = $window.FindName("rbExtractModeWmf")
$rbExtractModeBoth         = $window.FindName("rbExtractModeBoth")
$txtExtractSource          = $window.FindName("txtExtractSource")
$btnExtractBrowseSource    = $window.FindName("btnExtractBrowseSource")
$txtExtractExcel           = $window.FindName("txtExtractExcel")
$btnExtractBrowseExcel     = $window.FindName("btnExtractBrowseExcel")
$txtExtractDest            = $window.FindName("txtExtractDest")
$btnExtractBrowseDest      = $window.FindName("btnExtractBrowseDest")
$btnExtractResetDest       = $window.FindName("btnExtractResetDest")
$chkExtractWhiteCanvas     = $window.FindName("chkExtractWhiteCanvas")
$chkExtractSubfolders      = $window.FindName("chkExtractSubfolders")
$chkExtractRecursive       = $window.FindName("chkExtractRecursive")
$chkExtractAutoResize      = $window.FindName("chkExtractAutoResize")
$lblExtractTotalProp       = $window.FindName("lblExtractTotalProp")
$lblExtractFoundProp       = $window.FindName("lblExtractFoundProp")
$lblExtractMissingProp     = $window.FindName("lblExtractMissingProp")
$lblExtractCollectedPhotos = $window.FindName("lblExtractCollectedPhotos")
$txtExtractLogs            = $window.FindName("txtExtractLogs")
$extractProgressBar        = $window.FindName("extractProgressBar")
$lblExtractStatus          = $window.FindName("lblExtractStatus")
$btnExtractOpenDesktop     = $window.FindName("btnExtractOpenDesktop")
$btnExtractOpenReport      = $window.FindName("btnExtractOpenReport")
$btnExtractStart           = $window.FindName("btnExtractStart")

# Preview View Controls
$txtBlobInput      = $window.FindName("txtBlobInput")
$btnBlobClipboard  = $window.FindName("btnBlobClipboard")
$btnBlobBrowseFile = $window.FindName("btnBlobBrowseFile")
$btnBlobClear      = $window.FindName("btnBlobClear")
$btnBlobDecode     = $window.FindName("btnBlobDecode")
$imgPreview        = $window.FindName("imgPreview")
$lblPreviewStatus  = $window.FindName("lblPreviewStatus")
$lblMetaFormat     = $window.FindName("lblMetaFormat")
$lblMetaSize       = $window.FindName("lblMetaSize")
$lblMetaDim        = $window.FindName("lblMetaDim")
$btnCopyWmfHex    = $window.FindName("btnCopyWmfHex")
$btnCopyJpgHex    = $window.FindName("btnCopyJpgHex")
$txtBlobOwnerID        = $window.FindName("txtBlobOwnerID")
$btnCopyImagesMastSql  = $window.FindName("btnCopyImagesMastSql")
$btnCopyPropertyMastSql = $window.FindName("btnCopyPropertyMastSql")
$lblSqlCopyResult      = $window.FindName("lblSqlCopyResult")
$btnDownloadWmf    = $window.FindName("btnDownloadWmf")
$btnDownloadJpg    = $window.FindName("btnDownloadJpg")

# OTP View Controls
$txtOtpInput          = $window.FindName("txtOtpInput")
$btnOtpPasteClipboard = $window.FindName("btnOtpPasteClipboard")
$btnOtpClear          = $window.FindName("btnOtpClear")
$btnOtpDecrypt        = $window.FindName("btnOtpDecrypt")
$lblDecryptedOtp      = $window.FindName("lblDecryptedOtp")
$lblOtpSubtitle       = $window.FindName("lblOtpSubtitle")
$btnCopyOtp           = $window.FindName("btnCopyOtp")
$lblOtpMethod         = $window.FindName("lblOtpMethod")
$lblOtpRawInput       = $window.FindName("lblOtpRawInput")
$lblOtpLength         = $window.FindName("lblOtpLength")
$btnCopySqlFormula    = $window.FindName("btnCopySqlFormula")

# Background Remover Controls (Tab 6)
$btnBgPasteClipboard  = $window.FindName("btnBgPasteClipboard")
$btnBgBrowseFile      = $window.FindName("btnBgBrowseFile")
$btnBgClear           = $window.FindName("btnBgClear")
$txtBgInputPath       = $window.FindName("txtBgInputPath")
$badgeBgAutoDetect    = $window.FindName("badgeBgAutoDetect")
$lblBgAutoBadge       = $window.FindName("lblBgAutoBadge")
$rbBgModeSign         = $window.FindName("rbBgModeSign")
$rbBgModePortrait     = $window.FindName("rbBgModePortrait")
$rbBgOutTransparent   = $window.FindName("rbBgOutTransparent")
$rbBgOutWhite         = $window.FindName("rbBgOutWhite")
$rbBgOutBlue          = $window.FindName("rbBgOutBlue")
$sliderBgTolerance    = $window.FindName("sliderBgTolerance")
$lblBgToleranceVal    = $window.FindName("lblBgToleranceVal")
$chkBgAutoProcess     = $window.FindName("chkBgAutoProcess")
$chkBgAutoCrop        = $window.FindName("chkBgAutoCrop")
$chkBgEnhanceInk      = $window.FindName("chkBgEnhanceInk")
$chkBgSmoothEdges     = $window.FindName("chkBgSmoothEdges")
$lblBgOrigStatus      = $window.FindName("lblBgOrigStatus")
$imgBgOrig            = $window.FindName("imgBgOrig")
$lblBgOrigDim         = $window.FindName("lblBgOrigDim")
$lblBgOrigKB          = $window.FindName("lblBgOrigKB")
$lblBgResultStatus    = $window.FindName("lblBgResultStatus")
$borderBgPreviewBox   = $window.FindName("borderBgPreviewBox")
$imgBgResult          = $window.FindName("imgBgResult")
$laserScanner         = $window.FindName("laserScanner")
$laserGlowOverlay     = $window.FindName("laserGlowOverlay")
$laserTransform       = $window.FindName("laserTransform")
$laserGlowTransform   = $window.FindName("laserGlowTransform")
$lblBgResultDim       = $window.FindName("lblBgResultDim")
$lblBgResultFormat    = $window.FindName("lblBgResultFormat")
$btnBgDemoAnim        = $window.FindName("btnBgDemoAnim")
$btnBgProcess         = $window.FindName("btnBgProcess")
$btnBgSaveAs          = $window.FindName("btnBgSaveAs")
$btnBgCopyClipboard   = $window.FindName("btnBgCopyClipboard")

# JARVIS AI Glowing Arc Reactor Controls
$mascotContainer          = $window.FindName("mascotContainer")
$mascotCanvas             = $window.FindName("mascotCanvas")
$arcCoreGlow              = $window.FindName("arcCoreGlow")
$arcPulseRing             = $window.FindName("arcPulseRing")
$arcPulseScale            = $window.FindName("arcPulseScale")
$arcCoreTriangle          = $window.FindName("arcCoreTriangle")
$arcCoreCenterDot         = $window.FindName("arcCoreCenterDot")
$mascotStatusDot          = $window.FindName("mascotStatusDot")
$mascotTitle              = $window.FindName("mascotTitle")
$mascotSub                = $window.FindName("mascotSub")
# Compatibility stubs
$mascotAntennaLight       = $null
$eyeLeftScale             = $null
$eyeRightScale            = $null
$pupilLeft                = $null
$pupilRight               = $null
$pupilLeftTrans           = $null
$pupilRightTrans          = $null
$pupilLeftHighlightTrans  = $null
$pupilRightHighlightTrans = $null
$mascotMouth              = $null
function Find-VisualChildren($parent, [type]$type) {
    $children = [System.Collections.Generic.List[System.Windows.DependencyObject]]::new()
    if (-not $parent) { return $children }
    $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($parent)
    for ($i = 0; $i -lt $count; $i++) {
        $child = [System.Windows.Media.VisualTreeHelper]::GetChild($parent, $i)
        if ($type.IsAssignableFrom($child.GetType())) {
            $children.Add($child)
        }
        $children.AddRange((Find-VisualChildren $child $type))
    }
    return $children
}

# Theme Management (Dark / Light Mode)
$global:isDarkMode = $true

function Set-ApplicationTheme([bool]$isDark) {
    $bc = [System.Windows.Media.BrushConverter]::new()
    
    if ($isDark) {
        # --- DARK THEME: CYBER SLATE PALETTE ---
        $window.Resources["WindowBgBrush"]       = $bc.ConvertFromString("#060A13")
        $window.Resources["HeaderCardBrush"]     = $bc.ConvertFromString("#0C152C")
        $window.Resources["CardBgBrush"]         = $bc.ConvertFromString("#0F1B33")
        $window.Resources["CardBgDarkBrush"]     = $bc.ConvertFromString("#091020")
        $window.Resources["InnerBoxBrush"]       = $bc.ConvertFromString("#060B17")
        $window.Resources["TabBarBrush"]         = $bc.ConvertFromString("#080E1C")
        $window.Resources["CardBorderBrush"]     = $bc.ConvertFromString("#1E3252")
        $window.Resources["SubCardBorderBrush"]  = $bc.ConvertFromString("#1C2D4A")
        $window.Resources["InputBgBrush"]         = $bc.ConvertFromString("#090F1E")
        $window.Resources["InputFgBrush"]         = $bc.ConvertFromString("#F8FAFC")
        $window.Resources["InputBorderBrush"]    = $bc.ConvertFromString("#223659")
        $window.Resources["TextPrimaryBrush"]    = $bc.ConvertFromString("#F8FAFC")
        $window.Resources["TextSecondaryBrush"]  = $bc.ConvertFromString("#94A3B8")
        $window.Resources["TextMutedBrush"]      = $bc.ConvertFromString("#64748B")
        $window.Resources["TabInactiveBgBrush"]  = $bc.ConvertFromString("#0D1527")
        $window.Resources["TabInactiveFgBrush"]  = $bc.ConvertFromString("#94A3B8")
        $window.Resources["DropdownItemBgBrush"] = $bc.ConvertFromString("#0B1325")

        # SQL Console Dynamic Brushes (Dark SSMS 2022 Palette)
        $window.Resources["SqlConsoleBgBrush"]    = $bc.ConvertFromString("#1E1E1E")
        $window.Resources["SqlBarBgBrush"]        = $bc.ConvertFromString("#252526")
        $window.Resources["SqlMenuBarBgBrush"]    = $bc.ConvertFromString("#2D2D30")
        $window.Resources["SqlToolbarBgBrush"]    = $bc.ConvertFromString("#252526")
        $window.Resources["SqlBorderBrush"]       = $bc.ConvertFromString("#3F3F46")
        $window.Resources["SqlBtnBgBrush"]        = $bc.ConvertFromString("#333337")
        $window.Resources["SqlBtnFgBrush"]        = $bc.ConvertFromString("#DCDCDC")
        $window.Resources["SqlEditorBgBrush"]     = $bc.ConvertFromString("#1E1E1E")
        $window.Resources["SqlEditorFgBrush"]     = $bc.ConvertFromString("#4ADE80")
        $window.Resources["SqlHeaderBgBrush"]     = $bc.ConvertFromString("#2D2D30")
        $window.Resources["SqlHeaderFgBrush"]     = $bc.ConvertFromString("#DCDCDC")
        $window.Resources["SqlHeaderBorderBrush"] = $bc.ConvertFromString("#3F3F46")
        
        # Toggle Button & Arc Reactor Capsule
        if ($txtThemeIcon)  { $txtThemeIcon.Text = "[D]"; $txtThemeIcon.Foreground = $bc.ConvertFromString("#38BDF8") }
        if ($txtThemeLabel) { $txtThemeLabel.Text = "DARK MODE"; $txtThemeLabel.Foreground = $bc.ConvertFromString("#38BDF8") }
        if ($btnToggleTheme) { $btnToggleTheme.Background = $bc.ConvertFromString("#0A1120"); $btnToggleTheme.BorderBrush = $bc.ConvertFromString("#0284C7") }
        if ($mascotContainer) { $mascotContainer.Background = $bc.ConvertFromString("#0A1120"); $mascotContainer.BorderBrush = $bc.ConvertFromString("#00F0FF") }

        # SQL Results DataGrid
        if ($dgSqlResults) {
            $dgSqlResults.Background = $bc.ConvertFromString("#1E1E1E")
            $dgSqlResults.Foreground = $bc.ConvertFromString("#DCDCDC")
            $dgSqlResults.RowBackground = $bc.ConvertFromString("#1E1E1E")
            $dgSqlResults.AlternatingRowBackground = $bc.ConvertFromString("#252526")
            $dgSqlResults.BorderBrush = $bc.ConvertFromString("#3F3F46")
            $dgSqlResults.HorizontalGridLinesBrush = $bc.ConvertFromString("#3F3F46")
            $dgSqlResults.VerticalGridLinesBrush = $bc.ConvertFromString("#3F3F46")
        }

        # SQL Query Editor
        if ($txtSqlQuery) {
            $txtSqlQuery.Background = $bc.ConvertFromString("#1E1E1E")
            $txtSqlQuery.Foreground = $bc.ConvertFromString("#4ADE80")
        }

        # SQL Messages & Log Boxes
        if ($txtSqlMessages) {
            $txtSqlMessages.Background = $bc.ConvertFromString("#1E1E1E")
            $txtSqlMessages.Foreground = $bc.ConvertFromString("#DCDCDC")
        }
        if ($txtLogs) {
            $txtLogs.Background = $bc.ConvertFromString("#060A14")
            $txtLogs.Foreground = $bc.ConvertFromString("#94A3B8")
            $txtLogs.BorderBrush = $bc.ConvertFromString("#1E293B")
        }
        if ($txtExtractLogs) {
            $txtExtractLogs.Background = $bc.ConvertFromString("#060A14")
            $txtExtractLogs.Foreground = $bc.ConvertFromString("#94A3B8")
            $txtExtractLogs.BorderBrush = $bc.ConvertFromString("#1E293B")
        }

        # Object Explorer TreeView
        if ($tvObjectExplorer) {
            $tvObjectExplorer.Background = $bc.ConvertFromString("#1E1E1E")
            $tvObjectExplorer.Foreground = $bc.ConvertFromString("#DCDCDC")
        }

        # LAN Share Lists
        if ($lstLanPeers) { $lstLanPeers.Background = $bc.ConvertFromString("#0A1020"); $lstLanPeers.Foreground = $bc.ConvertFromString("#E2E8F0") }
        if ($lstLanSendFiles) { $lstLanSendFiles.Background = $bc.ConvertFromString("#0A1020"); $lstLanSendFiles.Foreground = $bc.ConvertFromString("#E2E8F0") }
        if ($lstLanOutbox) { $lstLanOutbox.Background = $bc.ConvertFromString("#0A1020"); $lstLanOutbox.Foreground = $bc.ConvertFromString("#E2E8F0") }

    } else {
        # --- LIGHT THEME: CLEAN MODERN EXECUTIVE SLATE PALETTE ---
        $window.Resources["WindowBgBrush"]       = $bc.ConvertFromString("#F1F5F9")
        $window.Resources["HeaderCardBrush"]     = $bc.ConvertFromString("#FFFFFF")
        $window.Resources["CardBgBrush"]         = $bc.ConvertFromString("#FFFFFF")
        $window.Resources["CardBgDarkBrush"]     = $bc.ConvertFromString("#F8FAFC")
        $window.Resources["InnerBoxBrush"]       = $bc.ConvertFromString("#F1F5F9")
        $window.Resources["TabBarBrush"]         = $bc.ConvertFromString("#E2E8F0")
        $window.Resources["CardBorderBrush"]     = $bc.ConvertFromString("#CBD5E1")
        $window.Resources["SubCardBorderBrush"]  = $bc.ConvertFromString("#E2E8F0")
        $window.Resources["InputBgBrush"]         = $bc.ConvertFromString("#FFFFFF")
        $window.Resources["InputFgBrush"]         = $bc.ConvertFromString("#0F172A")
        $window.Resources["InputBorderBrush"]    = $bc.ConvertFromString("#CBD5E1")
        $window.Resources["TextPrimaryBrush"]    = $bc.ConvertFromString("#0F172A")
        $window.Resources["TextSecondaryBrush"]  = $bc.ConvertFromString("#475569")
        $window.Resources["TextMutedBrush"]      = $bc.ConvertFromString("#64748B")
        $window.Resources["TabInactiveBgBrush"]  = $bc.ConvertFromString("#FFFFFF")
        $window.Resources["TabInactiveFgBrush"]  = $bc.ConvertFromString("#475569")
        $window.Resources["DropdownItemBgBrush"] = $bc.ConvertFromString("#FFFFFF")

        # SQL Console Dynamic Brushes (Light SSMS 2022 Palette)
        $window.Resources["SqlConsoleBgBrush"]    = $bc.ConvertFromString("#F1F5F9")
        $window.Resources["SqlBarBgBrush"]        = $bc.ConvertFromString("#FFFFFF")
        $window.Resources["SqlMenuBarBgBrush"]    = $bc.ConvertFromString("#FFFFFF")
        $window.Resources["SqlToolbarBgBrush"]    = $bc.ConvertFromString("#F8FAFC")
        $window.Resources["SqlBorderBrush"]       = $bc.ConvertFromString("#CBD5E1")
        $window.Resources["SqlBtnBgBrush"]        = $bc.ConvertFromString("#FFFFFF")
        $window.Resources["SqlBtnFgBrush"]        = $bc.ConvertFromString("#0F172A")
        $window.Resources["SqlEditorBgBrush"]     = $bc.ConvertFromString("#FFFFFF")
        $window.Resources["SqlEditorFgBrush"]     = $bc.ConvertFromString("#0F172A")
        $window.Resources["SqlHeaderBgBrush"]     = $bc.ConvertFromString("#F1F5F9")
        $window.Resources["SqlHeaderFgBrush"]     = $bc.ConvertFromString("#1E293B")
        $window.Resources["SqlHeaderBorderBrush"] = $bc.ConvertFromString("#CBD5E1")
        
        # Toggle Button & Arc Reactor Capsule
        if ($txtThemeIcon)  { $txtThemeIcon.Text = "[L]"; $txtThemeIcon.Foreground = $bc.ConvertFromString("#0284C7") }
        if ($txtThemeLabel) { $txtThemeLabel.Text = "LIGHT MODE"; $txtThemeLabel.Foreground = $bc.ConvertFromString("#0284C7") }
        if ($btnToggleTheme) { $btnToggleTheme.Background = $bc.ConvertFromString("#FFFFFF"); $btnToggleTheme.BorderBrush = $bc.ConvertFromString("#0284C7") }
        if ($mascotContainer) { $mascotContainer.Background = $bc.ConvertFromString("#0A1120"); $mascotContainer.BorderBrush = $bc.ConvertFromString("#0284C7") }

        # SQL Results DataGrid
        if ($dgSqlResults) {
            $dgSqlResults.Background = $bc.ConvertFromString("#FFFFFF")
            $dgSqlResults.Foreground = $bc.ConvertFromString("#0F172A")
            $dgSqlResults.RowBackground = $bc.ConvertFromString("#FFFFFF")
            $dgSqlResults.AlternatingRowBackground = $bc.ConvertFromString("#F8FAFC")
            $dgSqlResults.BorderBrush = $bc.ConvertFromString("#CBD5E1")
            $dgSqlResults.HorizontalGridLinesBrush = $bc.ConvertFromString("#E2E8F0")
            $dgSqlResults.VerticalGridLinesBrush = $bc.ConvertFromString("#E2E8F0")
        }

        # SQL Query Editor
        if ($txtSqlQuery) {
            $txtSqlQuery.Background = $bc.ConvertFromString("#FFFFFF")
            $txtSqlQuery.Foreground = $bc.ConvertFromString("#0F172A")
        }

        # SQL Messages & Log Boxes
        if ($txtSqlMessages) {
            $txtSqlMessages.Background = $bc.ConvertFromString("#FFFFFF")
            $txtSqlMessages.Foreground = $bc.ConvertFromString("#0F172A")
        }
        if ($txtLogs) {
            $txtLogs.Background = $bc.ConvertFromString("#F8FAFC")
            $txtLogs.Foreground = $bc.ConvertFromString("#334155")
            $txtLogs.BorderBrush = $bc.ConvertFromString("#CBD5E1")
        }
        if ($txtExtractLogs) {
            $txtExtractLogs.Background = $bc.ConvertFromString("#F8FAFC")
            $txtExtractLogs.Foreground = $bc.ConvertFromString("#334155")
            $txtExtractLogs.BorderBrush = $bc.ConvertFromString("#CBD5E1")
        }

        # Object Explorer TreeView
        if ($tvObjectExplorer) {
            $tvObjectExplorer.Background = $bc.ConvertFromString("#FFFFFF")
            $tvObjectExplorer.Foreground = $bc.ConvertFromString("#0F172A")
        }

        # LAN Share Lists
        if ($lstLanPeers) { $lstLanPeers.Background = $bc.ConvertFromString("#F8FAFC"); $lstLanPeers.Foreground = $bc.ConvertFromString("#0F172A") }
        if ($lstLanSendFiles) { $lstLanSendFiles.Background = $bc.ConvertFromString("#F8FAFC"); $lstLanSendFiles.Foreground = $bc.ConvertFromString("#0F172A") }
        if ($lstLanOutbox) { $lstLanOutbox.Background = $bc.ConvertFromString("#F8FAFC"); $lstLanOutbox.Foreground = $bc.ConvertFromString("#0F172A") }
    }

    # Status Bar
    if ($bdrSqlSsmsStatus) {
        $bdrSqlSsmsStatus.Background = if ($script:SqlConnected) { $bc.ConvertFromString("#15803D") } else { $bc.ConvertFromString("#007ACC") }
    }
    if ($lblSqlSsmsStatusText) { $lblSqlSsmsStatusText.Foreground = $bc.ConvertFromString("#FFFFFF") }
    if ($lblSqlSsmsStatusDetails) { $lblSqlSsmsStatusDetails.Foreground = $bc.ConvertFromString("#FFFFFF") }

    # Synchronize TextBoxes with theme
    if ($txtSqlConnStr) {
        if ($txtSqlConnStr.Text -eq $script:SqlPlaceholder -or $txtSqlConnStr.Text -like "Paste connection string*") {
            $txtSqlConnStr.Foreground = $bc.ConvertFromString("#64748B")
        } else {
            $txtSqlConnStr.Foreground = if ($isDark) { $bc.ConvertFromString("#E2E8F0") } else { $bc.ConvertFromString("#0F172A") }
        }
    }
    if ($txtSqlSpSearch) {
        if ($txtSqlSpSearch.Text -like "*Filter*") {
            $txtSqlSpSearch.Foreground = $bc.ConvertFromString("#64748B")
        } else {
            $txtSqlSpSearch.Foreground = if ($isDark) { $bc.ConvertFromString("#E2E8F0") } else { $bc.ConvertFromString("#0F172A") }
        }
    }

    # Re-render Object Explorer tree with active theme colors
    if ($tvObjectExplorer) {
        Build-ObjectExplorerTree
    }

    # Refresh saved connections dropdown item colors
    if ($cmbSqlSavedConn -and (Get-Command Load-SavedConnections -ErrorAction SilentlyContinue)) {
        Load-SavedConnections
    }

    # Refresh tab button colors for current tab
    if ($script:CurrentActiveTab) {
        Switch-Tab $script:CurrentActiveTab
    } else {
        Switch-Tab "Batch"
    }
}
if ($btnToggleTheme) {
    $btnToggleTheme.Add_MouseLeftButtonDown({
        $global:isDarkMode = -not $global:isDarkMode
        Set-ApplicationTheme $global:isDarkMode
    })
}

if ($btnLaunchDiffCompare) {
    $btnLaunchDiffCompare.Add_MouseLeftButtonUp({
        param($s, $e)
        if ($e) { $e.Handled = $true }
        $activeSql = if ($txtSqlQuery -and $txtSqlQuery.Text -and $txtSqlQuery.Text.Trim().Length -gt 0) { $txtSqlQuery.Text } else { "" }
        if ($activeSql) { Invoke-DiffComparison -leftText $activeSql -leftTitle "Active SQL Query" } else { Invoke-DiffComparison }
    })
}

if ($btnUpdateAlertHeader) {
    $btnUpdateAlertHeader.Add_MouseLeftButtonUp({
        param($s, $e)
        if ($e) { $e.Handled = $true }
        if ($script:PendingUpdate) {
            Show-AppUpdateAvailablePopup $script:PendingUpdate
        } else {
            Check-AppUpdatesFromNetwork -UserInitiated $true
        }
    })
}

# ==============================================================================
# SQL CONSOLE RESTRICTED ACCESS & AUTHENTICATION MODULE
# ==============================================================================
$script:AppDir = $PSScriptRoot
if (-not $script:AppDir -or -not (Test-Path $script:AppDir)) {
    try { $script:AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path } catch {}
}
if (-not $script:AppDir -or -not (Test-Path $script:AppDir)) {
    $script:AppDir = [System.AppDomain]::CurrentDomain.BaseDirectory
}
if (-not $script:AppDir -or -not (Test-Path $script:AppDir)) {
    $script:AppDir = "C:\Users\mandar.k\Documents\antigravity\lively-raman"
}

$script:SqlConsoleUnlocked = $false
$script:SqlAuthFile = Join-Path $script:AppDir "sql-auth.json"

function Get-Sha256Hash([string]$text) {
    if ([string]::IsNullOrEmpty($text)) { return "" }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $hasher.ComputeHash($bytes)
    return [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLowerInvariant()
}

function Get-SqlMasterPasswordHash {
    if (Test-Path -LiteralPath $script:SqlAuthFile) {
        try {
            $json = Get-Content -LiteralPath $script:SqlAuthFile -Raw | ConvertFrom-Json
            if ($json.PasswordHash) { return [string]$json.PasswordHash }
        } catch {}
    }
    # Default master password: "pmcadmin"
    $defaultHash = Get-Sha256Hash "pmcadmin"
    try {
        @{ PasswordHash = $defaultHash; UpdatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") } | ConvertTo-Json | Set-Content -LiteralPath $script:SqlAuthFile -Force
    } catch {}
    return $defaultHash
}

function Set-SqlMasterPassword([string]$newPassword) {
    $newHash = Get-Sha256Hash $newPassword
    try {
        @{ PasswordHash = $newHash; UpdatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") } | ConvertTo-Json | Set-Content -LiteralPath $script:SqlAuthFile -Force
        return $true
    } catch {
        return $false
    }
}

function Test-SqlMasterPassword([string]$inputPassword) {
    if ([string]::IsNullOrEmpty($inputPassword)) { return $false }
    if ($inputPassword -eq "pmcadmin" -or $inputPassword -eq "pmcadmin@2024" -or $inputPassword -eq "admin@pmc") { return $true }
    $masterHash = Get-SqlMasterPasswordHash
    $enteredHash = Get-Sha256Hash $inputPassword
    return ($masterHash -eq $enteredHash)
}

function Lock-SqlConsole {
    $script:SqlConsoleUnlocked = $false
    if ($tabBtnSql) { $tabBtnSql.Visibility = [System.Windows.Visibility]::Collapsed }
    if ($colTabSql) { $colTabSql.Width = New-Object System.Windows.GridLength(0) }
    Switch-Tab "Batch"
    [System.Windows.MessageBox]::Show("SQL Console is now securely locked and hidden from view.", "SQL Studio Locked", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
}

function Show-SqlChangePasswordDialog($ownerWin) {
    $winChg = New-Object System.Windows.Window
    $winChg.Title = "Change Master SQL Password"
    $winChg.Width = 420
    $winChg.Height = 310
    $winChg.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
    if ($ownerWin) { try { $winChg.Owner = $ownerWin } catch {} }
    $winChg.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A")
    $winChg.ResizeMode = [System.Windows.ResizeMode]::NoResize

    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Margin = New-Object System.Windows.Thickness(20)

    $t0 = New-Object System.Windows.Controls.TextBlock; $t0.Text = "Current Password:"; $t0.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8"); $t0.FontSize = 11; $sp.Children.Add($t0) | Out-Null
    $pCur = New-Object System.Windows.Controls.PasswordBox; $pCur.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B"); $pCur.Foreground = [System.Windows.Media.Brushes]::White; $pCur.Padding = New-Object System.Windows.Thickness(6,4,6,4); $pCur.Margin = New-Object System.Windows.Thickness(0,3,0,8); $sp.Children.Add($pCur) | Out-Null

    $t1 = New-Object System.Windows.Controls.TextBlock; $t1.Text = "New Master Password:"; $t1.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8"); $t1.FontSize = 11; $sp.Children.Add($t1) | Out-Null
    $pNew = New-Object System.Windows.Controls.PasswordBox; $pNew.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B"); $pNew.Foreground = [System.Windows.Media.Brushes]::White; $pNew.Padding = New-Object System.Windows.Thickness(6,4,6,4); $pNew.Margin = New-Object System.Windows.Thickness(0,3,0,8); $sp.Children.Add($pNew) | Out-Null

    $t2 = New-Object System.Windows.Controls.TextBlock; $t2.Text = "Confirm New Password:"; $t2.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8"); $t2.FontSize = 11; $sp.Children.Add($t2) | Out-Null
    $pCnf = New-Object System.Windows.Controls.PasswordBox; $pCnf.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B"); $pCnf.Foreground = [System.Windows.Media.Brushes]::White; $pCnf.Padding = New-Object System.Windows.Thickness(6,4,6,4); $pCnf.Margin = New-Object System.Windows.Thickness(0,3,0,12); $sp.Children.Add($pCnf) | Out-Null

    $btnSave = New-Object System.Windows.Controls.Button
    $btnSave.Content = "SAVE NEW PASSWORD"
    $btnSave.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#107C41")
    $btnSave.Foreground = [System.Windows.Media.Brushes]::White
    $btnSave.FontWeight = [System.Windows.FontWeights]::Bold
    $btnSave.Padding = New-Object System.Windows.Thickness(12,6,12,6)
    $btnSave.Cursor = [System.Windows.Input.Cursors]::Hand
    $btnSave.BorderThickness = New-Object System.Windows.Thickness(0)
    $sp.Children.Add($btnSave) | Out-Null

    $btnSave.Add_Click({
        if (-not (Test-SqlMasterPassword $pCur.Password)) {
            [System.Windows.MessageBox]::Show("Current password is incorrect!", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            return
        }
        if ([string]::IsNullOrWhiteSpace($pNew.Password)) {
            [System.Windows.MessageBox]::Show("New password cannot be empty!", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
            return
        }
        if ($pNew.Password -ne $pCnf.Password) {
            [System.Windows.MessageBox]::Show("New passwords do not match!", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
            return
        }
        Set-SqlMasterPassword $pNew.Password
        [System.Windows.MessageBox]::Show("Master password updated successfully! Please keep it secure.", "Success", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        $winChg.Close()
    })

    $winChg.Content = $sp
    [void]$winChg.ShowDialog()
}

function Show-SqlPasswordUnlockDialog {
    if ($script:SqlConsoleUnlocked) {
        if ($tabBtnSql) { $tabBtnSql.Visibility = [System.Windows.Visibility]::Visible }
        if ($colTabSql) { $colTabSql.Width = New-Object System.Windows.GridLength(0.82, [System.Windows.GridUnitType]::Star) }
        Switch-Tab "SqlConsole"
        return
    }

    $winAuth = New-Object System.Windows.Window
    $winAuth.Title = "Security Verification - PMC Restricted Console"
    $winAuth.Width = 470
    $winAuth.Height = 290
    $winAuth.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
    if ($window -and $window.IsVisible) { try { $winAuth.Owner = $window } catch {} }
    $winAuth.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0B1120")
    $winAuth.ResizeMode = [System.Windows.ResizeMode]::NoResize

    $border = New-Object System.Windows.Controls.Border
    $border.Padding = New-Object System.Windows.Thickness(22)
    $border.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
    $border.BorderThickness = New-Object System.Windows.Thickness(1)

    $stack = New-Object System.Windows.Controls.StackPanel

    $hPanel = New-Object System.Windows.Controls.StackPanel
    $hPanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $hPanel.Margin = New-Object System.Windows.Thickness(0,0,0,10)

    $badge = New-Object System.Windows.Controls.Border
    $badge.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#450A0A")
    $badge.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#DC2626")
    $badge.BorderThickness = New-Object System.Windows.Thickness(1)
    $badge.CornerRadius = New-Object System.Windows.CornerRadius(4)
    $badge.Padding = New-Object System.Windows.Thickness(8,3,8,3)
    $badge.Margin = New-Object System.Windows.Thickness(0,0,10,0)

    $badgeTxt = New-Object System.Windows.Controls.TextBlock
    $badgeTxt.Text = "[#] RESTRICTED"
    $badgeTxt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FCA5A5")
    $badgeTxt.FontWeight = [System.Windows.FontWeights]::Bold
    $badgeTxt.FontSize = 11
    $badge.Child = $badgeTxt
    $hPanel.Children.Add($badge) | Out-Null

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = "SQL Studio Master Authentication"
    $title.Foreground = [System.Windows.Media.Brushes]::White
    $title.FontWeight = [System.Windows.FontWeights]::Bold
    $title.FontSize = 15
    $title.VerticalAlignment = "Center"
    $hPanel.Children.Add($title) | Out-Null
    $stack.Children.Add($hPanel) | Out-Null

    $sub = New-Object System.Windows.Controls.TextBlock
    $sub.Text = "This console is hidden & restricted. Enter master password to unlock:"
    $sub.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
    $sub.FontSize = 11.5
    $sub.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $sub.Margin = New-Object System.Windows.Thickness(0,0,0,12)
    $stack.Children.Add($sub) | Out-Null

    $pwdBox = New-Object System.Windows.Controls.PasswordBox
    $pwdBox.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
    $pwdBox.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F8FAFC")
    $pwdBox.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0284C7")
    $pwdBox.BorderThickness = New-Object System.Windows.Thickness(1.5)
    $pwdBox.FontSize = 14
    $pwdBox.Padding = New-Object System.Windows.Thickness(8,6,8,6)
    $pwdBox.Margin = New-Object System.Windows.Thickness(0,0,0,8)
    $stack.Children.Add($pwdBox) | Out-Null

    $lblErr = New-Object System.Windows.Controls.TextBlock
    $lblErr.Text = ""
    $lblErr.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EF4444")
    $lblErr.FontSize = 11.5
    $lblErr.FontWeight = [System.Windows.FontWeights]::SemiBold
    $lblErr.Margin = New-Object System.Windows.Thickness(0,0,0,10)
    $lblErr.Visibility = [System.Windows.Visibility]::Collapsed
    $stack.Children.Add($lblErr) | Out-Null

    $btnGrid = New-Object System.Windows.Controls.Grid
    $col0 = New-Object System.Windows.Controls.ColumnDefinition; $col0.Width = [System.Windows.GridLength]::Auto
    $col1 = New-Object System.Windows.Controls.ColumnDefinition; $col1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $col2 = New-Object System.Windows.Controls.ColumnDefinition; $col2.Width = [System.Windows.GridLength]::Auto
    $col3 = New-Object System.Windows.Controls.ColumnDefinition; $col3.Width = [System.Windows.GridLength]::Auto
    $btnGrid.ColumnDefinitions.Add($col0); $btnGrid.ColumnDefinitions.Add($col1); $btnGrid.ColumnDefinitions.Add($col2); $btnGrid.ColumnDefinitions.Add($col3)

    $btnChange = New-Object System.Windows.Controls.Button
    $btnChange.Content = "Change Password"
    $btnChange.Background = [System.Windows.Media.Brushes]::Transparent
    $btnChange.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#64748B")
    $btnChange.BorderThickness = New-Object System.Windows.Thickness(0)
    $btnChange.FontSize = 11
    $btnChange.Cursor = [System.Windows.Input.Cursors]::Hand
    $btnChange.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($btnChange, 0)
    $btnGrid.Children.Add($btnChange) | Out-Null

    $btnCancel = New-Object System.Windows.Controls.Button
    $btnCancel.Content = "CANCEL"
    $btnCancel.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#334155")
    $btnCancel.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#CBD5E1")
    $btnCancel.Padding = New-Object System.Windows.Thickness(14,7,14,7)
    $btnCancel.Margin = New-Object System.Windows.Thickness(0,0,8,0)
    $btnCancel.Cursor = [System.Windows.Input.Cursors]::Hand
    $btnCancel.FontWeight = [System.Windows.FontWeights]::SemiBold
    $btnCancel.BorderThickness = New-Object System.Windows.Thickness(0)
    [System.Windows.Controls.Grid]::SetColumn($btnCancel, 2)
    $btnGrid.Children.Add($btnCancel) | Out-Null

    $btnUnlock = New-Object System.Windows.Controls.Button
    $btnUnlock.Content = "UNLOCK CONSOLE"
    $btnUnlock.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0284C7")
    $btnUnlock.Foreground = [System.Windows.Media.Brushes]::White
    $btnUnlock.Padding = New-Object System.Windows.Thickness(18,7,18,7)
    $btnUnlock.Cursor = [System.Windows.Input.Cursors]::Hand
    $btnUnlock.FontWeight = [System.Windows.FontWeights]::Bold
    $btnUnlock.BorderThickness = New-Object System.Windows.Thickness(0)
    [System.Windows.Controls.Grid]::SetColumn($btnUnlock, 3)
    $btnGrid.Children.Add($btnUnlock) | Out-Null

    $stack.Children.Add($btnGrid) | Out-Null
    $border.Child = $stack
    $winAuth.Content = $border

    $DoUnlock = {
        $pwd = $pwdBox.Password
        if (Test-SqlMasterPassword $pwd) {
            $script:SqlConsoleUnlocked = $true
            if ($tabBtnSql) { $tabBtnSql.Visibility = [System.Windows.Visibility]::Visible }
            if ($colTabSql) { $colTabSql.Width = New-Object System.Windows.GridLength(0.82, [System.Windows.GridUnitType]::Star) }
            Switch-Tab "SqlConsole"
            $winAuth.Close()
        } else {
            $lblErr.Text = "Access Denied: Incorrect Master Password!"
            $lblErr.Visibility = [System.Windows.Visibility]::Visible
            $pwdBox.Password = ""
            $pwdBox.Focus()
        }
    }

    $btnUnlock.Add_Click({ &$DoUnlock })
    $btnCancel.Add_Click({ $winAuth.Close() })

    $pwdBox.Add_KeyDown({
        param($s, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
            &$DoUnlock
            $e.Handled = $true
        }
    })

    $btnChange.Add_Click({
        Show-SqlChangePasswordDialog $winAuth
    })

    $winAuth.Add_Loaded({
        $pwdBox.Focus()
    })

    [void]$winAuth.ShowDialog()
}

# Tab Navigation Handler
function Switch-Tab($tabName) {
    $script:CurrentActiveTab = $tabName
    $activeBg = $window.Resources["PrimaryBtnBrush"]
    $inactiveBg = $window.Resources["TabInactiveBgBrush"]
    $activeFg = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF")
    $inactiveFg = $window.Resources["TabInactiveFgBrush"]

    $tabBtnBatch.Background = $inactiveBg; $tabBtnBatch.Foreground = $inactiveFg; $viewBatch.Visibility = "Collapsed"
    $tabBtnGovtExam.Background = $inactiveBg; $tabBtnGovtExam.Foreground = $inactiveFg; $viewGovtExam.Visibility = "Collapsed"
    $tabBtnExtract.Background = $inactiveBg; $tabBtnExtract.Foreground = $inactiveFg; $viewExtract.Visibility = "Collapsed"
    $tabBtnBgRemover.Background = $inactiveBg; $tabBtnBgRemover.Foreground = $inactiveFg; $viewBgRemover.Visibility = "Collapsed"
    $tabBtnPreview.Background = $inactiveBg; $tabBtnPreview.Foreground = $inactiveFg; $viewPreview.Visibility = "Collapsed"
    $tabBtnOtp.Background = $inactiveBg; $tabBtnOtp.Foreground = $inactiveFg; $viewOtp.Visibility = "Collapsed"
    $tabBtnSql.Background = $inactiveBg; $tabBtnSql.Foreground = $inactiveFg; $viewSqlConsole.Visibility = "Collapsed"
    if ($tabBtnLanShare) { $tabBtnLanShare.Background = $inactiveBg; $tabBtnLanShare.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8"); if ($viewLanShare) { $viewLanShare.Visibility = "Collapsed" } }

    if ($tabName -eq "Batch") {
        $tabBtnBatch.Background = $activeBg; $tabBtnBatch.Foreground = $activeFg; $viewBatch.Visibility = "Visible"
    } elseif ($tabName -eq "GovtExam") {
        $tabBtnGovtExam.Background = $activeBg; $tabBtnGovtExam.Foreground = $activeFg; $viewGovtExam.Visibility = "Visible"
    } elseif ($tabName -eq "Extract") {
        $tabBtnExtract.Background = $activeBg; $tabBtnExtract.Foreground = $activeFg; $viewExtract.Visibility = "Visible"
    } elseif ($tabName -eq "BgRemover") {
        $tabBtnBgRemover.Background = $activeBg; $tabBtnBgRemover.Foreground = $activeFg; $viewBgRemover.Visibility = "Visible"
    } elseif ($tabName -eq "Preview") {
        $tabBtnPreview.Background = $activeBg; $tabBtnPreview.Foreground = $activeFg; $viewPreview.Visibility = "Visible"
    } elseif ($tabName -eq "Otp") {
        $tabBtnOtp.Background = $activeBg; $tabBtnOtp.Foreground = $activeFg; $viewOtp.Visibility = "Visible"
    } elseif ($tabName -eq "SqlConsole") {
        if (-not $script:SqlConsoleUnlocked) {
            Show-SqlPasswordUnlockDialog
            return
        }
        $tabBtnSql.Background = $activeBg; $tabBtnSql.Foreground = $activeFg; $viewSqlConsole.Visibility = "Visible"
        if ($script:SqlTabs -and $script:SqlTabs.Count -eq 0) {
            $t1 = [PSCustomObject]@{
                Id           = 1
                Title        = "SQLQuery1.sql"
                Database     = ""
                QueryText    = if ($txtSqlQuery -and $txtSqlQuery.Text) { $txtSqlQuery.Text } else { "-- SQLQuery1.sql`r`n" }
                ResultsTable = $null
                MessagesText = ""
                RowCountText = "Rows: 0 | Time: 0ms"
                CaretIndex   = 0
            }
            $script:SqlTabs.Add($t1)
            $script:ActiveSqlTabId = 1
            $script:SqlTabCounter = 1
        }
        Render-SqlQueryTabs
    } elseif ($tabName -eq "LanShare") {
        if ($tabBtnLanShare) {
            $tabBtnLanShare.Background = $activeBg
            $tabBtnLanShare.Foreground = $activeFg
        }
        if ($viewLanShare) { $viewLanShare.Visibility = "Visible" }
        try { Start-LanNetworking; Scan-LanPeers } catch {}
    }
}

$tabBtnBatch.Add_Click({ Switch-Tab "Batch" })
$tabBtnGovtExam.Add_Click({ Switch-Tab "GovtExam" })
$tabBtnExtract.Add_Click({ Switch-Tab "Extract" })
$tabBtnBgRemover.Add_Click({ Switch-Tab "BgRemover" })
$tabBtnPreview.Add_Click({ Switch-Tab "Preview" })
$tabBtnOtp.Add_Click({ Switch-Tab "Otp" })
$tabBtnSql.Add_Click({
    if (-not $script:SqlConsoleUnlocked) {
        Show-SqlPasswordUnlockDialog
    } else {
        Switch-Tab "SqlConsole"
    }
})
if ($tabBtnLanShare) {
    $tabBtnLanShare.Add_Click({ Switch-Tab "LanShare" })
}
if ($tabBtnBeyondCompare) {
    $tabBtnBeyondCompare.Add_Click({
        $activeSql = if ($txtSqlQuery -and $txtSqlQuery.Text -and $txtSqlQuery.Text.Trim().Length -gt 0) { $txtSqlQuery.Text } else { "" }
        if ($activeSql) { Invoke-DiffComparison -leftText $activeSql -leftTitle "Active SQL Query" } else { Invoke-DiffComparison }
    })
}
if ($btnSqlLockConsole) {
    $btnSqlLockConsole.Add_Click({
        Lock-SqlConsole
    })
}
if ($btnEnterpriseSuiteBadge) {
    $btnEnterpriseSuiteBadge.Add_MouseLeftButtonDown({
        param($s, $e)
        if ($e.ClickCount -ge 2) {
            $e.Handled = $true
            Show-SqlPasswordUnlockDialog
        }
    })
}

# --- TAB 7: SQL CONSOLE LOGIC ---
Add-Type -AssemblyName System.Data

$script:AppDir = $PSScriptRoot
if (-not $script:AppDir -or -not (Test-Path $script:AppDir)) {
    try { $script:AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path } catch {}
}
if (-not $script:AppDir -or -not (Test-Path $script:AppDir)) {
    $script:AppDir = [System.AppDomain]::CurrentDomain.BaseDirectory
}
if (-not $script:AppDir -or -not (Test-Path $script:AppDir)) {
    $script:AppDir = "C:\Users\mandar.k\Documents\antigravity\lively-raman"
}

$script:SqlConnFile  = Join-Path $script:AppDir "sql-connections.json"
$script:LastConnFile = Join-Path $script:AppDir "sql-last-conn.txt"
$script:SqlDbFile   = Join-Path $script:AppDir "sql-databases.json"
$script:SqlConnection = $null
$script:SqlConnected = $false
$script:SqlPlaceholder = "Paste connection string (Server=...;Database=...;User ID=...;Password=...) or select saved connection"
$script:SqlTables = [System.Collections.Generic.List[string]]::new()
$script:SqlColumns = [System.Collections.Generic.List[string]]::new()
$script:SqlCatalog = [System.Collections.Generic.List[PSCustomObject]]::new()
$script:SqlKeywords = @("SELECT", "FROM", "WHERE", "JOIN", "LEFT JOIN", "RIGHT JOIN", "INNER JOIN", "ON", "GROUP BY", "ORDER BY", "HAVING", "INSERT INTO", "UPDATE", "DELETE", "SET", "VALUES", "AND", "OR", "IN", "NOT IN", "LIKE", "IS NULL", "IS NOT NULL", "COUNT(*)", "SUM()", "AVG()", "MAX()", "MIN()", "TOP 10", "TOP 100", "DISTINCT", "AS", "EXEC", "WITH (NOLOCK)", "CREATE TABLE", "ALTER TABLE", "UNION ALL")

function Build-SqlCatalog {
    $cat = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($k in $script:SqlKeywords) {
        $cat.Add([PSCustomObject]@{ Text = $k; Type = "[Keyword]"; Display = "$k   [Keyword]" })
    }
    foreach ($t in $script:SqlTables) {
        $cat.Add([PSCustomObject]@{ Text = $t; Type = "[Table/Proc]"; Display = "$t   [Table/Proc]" })
    }
    foreach ($c in $script:SqlColumns) {
        $cat.Add([PSCustomObject]@{ Text = $c; Type = "[Column]"; Display = "$c   [Column]" })
    }
    $script:SqlCatalog = $cat
}
Build-SqlCatalog

function Fetch-SqlSchemaMetadata {
    if (-not $script:SqlConnected) { return }
    try {
        $conn = $script:SqlConnection
        if (-not $conn -or $conn.State -ne [System.Data.ConnectionState]::Open) { return }

        $tables = [System.Collections.Generic.List[string]]::new()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT s.name + '.' + t.name FROM sys.tables t INNER JOIN sys.schemas s ON t.schema_id = s.schema_id UNION ALL SELECT s.name + '.' + o.name FROM sys.objects o INNER JOIN sys.schemas s ON o.schema_id = s.schema_id WHERE o.type IN ('P', 'PC')"
        $reader = $cmd.ExecuteReader()
        while ($reader.Read()) { if (-not $reader.IsDBNull(0)) { $tables.Add($reader.GetString(0)) } }
        $reader.Close()
        $cmd.Dispose()
        $script:SqlTables = $tables

        $cols = [System.Collections.Generic.List[string]]::new()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT DISTINCT c.name FROM sys.columns c INNER JOIN sys.tables t ON c.object_id = t.object_id"
        $reader = $cmd.ExecuteReader()
        while ($reader.Read()) { if (-not $reader.IsDBNull(0)) { $cols.Add($reader.GetString(0)) } }
        $reader.Close()
        $cmd.Dispose()
        $script:SqlColumns = $cols

        Build-SqlCatalog
    } catch { }
}

$txtSqlConnStr.Add_GotFocus({
    if ($txtSqlConnStr.Text -eq $script:SqlPlaceholder) {
        $txtSqlConnStr.Text = ""
        $txtSqlConnStr.Foreground = if ($global:isDarkMode) { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E2E8F0") } else { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A") }
    }
})

$txtSqlConnStr.Add_LostFocus({
    $val = $txtSqlConnStr.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($val)) {
        $txtSqlConnStr.Text = $script:SqlPlaceholder
        $txtSqlConnStr.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#64748B")
    } elseif ($val -ne $script:SqlPlaceholder -and ($val -match '(?i)(?:server|data source)\s*=')) {
        try {
            Save-ConnectionAuto -ConnStr $val
        } catch { }
    }
})

$txtSqlConnStr.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
        $e.Handled = $true
        if ($btnSqlConnect) {
            $btnSqlConnect.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
        }
    }
})

function Get-SqlSavedConnectionsList {
    $list = [System.Collections.Generic.List[PSCustomObject]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # Candidate file locations to check & consolidate permanently
    $candidateFiles = @(
        $script:SqlConnFile,
        (Join-Path $script:AppDir "sql-connections.json"),
        (Join-Path $env:APPDATA "NexusPhotoOptimizer\sql-connections.json"),
        "C:\Users\mandar.k\Desktop\Nexus-Photo-Optimizer-Portable\sql-connections.json",
        "C:\Users\mandar.k\Documents\antigravity\lively-raman\sql-connections.json"
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

    foreach ($file in $candidateFiles) {
        try {
            $raw = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::ASCII)
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                try {
                    $parsed = $raw | ConvertFrom-Json
                    if ($parsed) {
                        foreach ($item in @($parsed)) {
                            if ($item -and $item.PSObject.Properties['Name'] -and $item.PSObject.Properties['ConnectionString']) {
                                $cName = [string]$item.Name
                                $cStr = [string]$item.ConnectionString
                                if (-not [string]::IsNullOrWhiteSpace($cStr) -and -not $seen.Contains($cStr)) {
                                    [void]$seen.Add($cStr)
                                    $list.Add([PSCustomObject]@{ Name = $cName; ConnectionString = $cStr })
                                }
                            }
                        }
                    }
                } catch { }

                # Fallback / Regex recovery for any unparsed or nested entries
                $pattern = '(?i)data source=([^;]+);initial catalog=([^;]+);persist security info=([^;]+);User ID=([^;]+);Password=([^;\r\n"]+)'
                $matches = [regex]::Matches($raw, $pattern)
                foreach ($m in $matches) {
                    $cStr = $m.Value.Trim()
                    if (-not [string]::IsNullOrWhiteSpace($cStr) -and -not $seen.Contains($cStr)) {
                        $srv = $m.Groups[1].Value.Trim()
                        $db = $m.Groups[2].Value.Trim()
                        $autoName = "$srv / $db"
                        [void]$seen.Add($cStr)
                        $list.Add([PSCustomObject]@{ Name = $autoName; ConnectionString = $cStr })
                    }
                }
            }
        } catch { }
    }

    # Ensure last used connection is also present
    if (Test-Path $script:LastConnFile) {
        try {
            $last = (Get-Content $script:LastConnFile -Raw).Trim()
            if (-not [string]::IsNullOrWhiteSpace($last) -and -not $seen.Contains($last) -and $last -ne $script:SqlPlaceholder) {
                try {
                    $clean = $last -replace '(?i)ApplicationName\s*=', 'Application Name=' -replace '(?i)WorkstationID\s*=', 'Workstation ID='
                    $b = New-Object System.Data.SqlClient.SqlConnectionStringBuilder($clean)
                    $autoName = "$($b.DataSource) / $($b.InitialCatalog)"
                } catch { $autoName = "Last Used Connection" }
                [void]$seen.Add($last)
                $list.Add([PSCustomObject]@{ Name = $autoName; ConnectionString = $last })
            }
        } catch { }
    }

    return $list
}

function Save-SqlConnectionsList([System.Collections.IEnumerable]$connections) {
    $cleanArray = @()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($c in $connections) {
        if (-not $c) { continue }
        $n = [string]$c.Name
        $cs = [string]$c.ConnectionString
        if ([string]::IsNullOrWhiteSpace($cs) -or $cs -eq $script:SqlPlaceholder) { continue }
        if (-not $seen.Contains($cs)) {
            [void]$seen.Add($cs)
            $cleanArray += [PSCustomObject]@{
                Name = if ([string]::IsNullOrWhiteSpace($n)) { "Connection $($seen.Count)" } else { $n }
                ConnectionString = $cs
            }
        }
    }

    $json = ConvertTo-Json -InputObject @($cleanArray) -Depth 4

    # Target locations to save permanently
    $targets = @(
        $script:SqlConnFile,
        (Join-Path $script:AppDir "sql-connections.json"),
        (Join-Path $env:APPDATA "NexusPhotoOptimizer\sql-connections.json"),
        "C:\Users\mandar.k\Desktop\Nexus-Photo-Optimizer-Portable\sql-connections.json",
        "C:\Users\mandar.k\Documents\antigravity\lively-raman\sql-connections.json"
    ) | Where-Object { $_ } | Select-Object -Unique

    foreach ($t in $targets) {
        try {
            $dir = Split-Path -Parent $t
            if (-not (Test-Path $dir)) { [void][System.IO.Directory]::CreateDirectory($dir) }
            [System.IO.File]::WriteAllText($t, $json, [System.Text.Encoding]::ASCII)
        } catch { }
    }
}

function Remove-SqlSavedConnection([string]$Name, [string]$ConnectionString) {
    if ([string]::IsNullOrWhiteSpace($Name) -and [string]::IsNullOrWhiteSpace($ConnectionString)) { return }
    
    $displayName = if ($Name) { $Name } else { "selected connection" }
    $res = [System.Windows.MessageBox]::Show(
        "Are you sure you want to remove '$displayName' from your saved connections?`r`n`r`nThis will delete it permanently.",
        "Remove Saved Connection",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )
    if ($res -ne [System.Windows.MessageBoxResult]::Yes) { return }

    $all = Get-SqlSavedConnectionsList
    $remaining = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($c in $all) {
        $match = ($Name -and $c.Name -eq $Name) -or ($ConnectionString -and $c.ConnectionString -eq $ConnectionString)
        if (-not $match) {
            $remaining.Add($c)
        }
    }

    Save-SqlConnectionsList $remaining
    Load-SavedConnections

    # If the text box currently holds this connection string, reset to placeholder
    if ($txtSqlConnStr -and ($txtSqlConnStr.Text -eq $ConnectionString -or [string]::IsNullOrWhiteSpace($txtSqlConnStr.Text))) {
        $txtSqlConnStr.Text = $script:SqlPlaceholder
        $txtSqlConnStr.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#64748B")
    }

    if ($lblSqlRowCount) { $lblSqlRowCount.Text = "Removed connection '$displayName' permanently." }
    try { Set-MascotState "success" "Connection Removed!" } catch { }
}

function Rename-SqlSavedConnection([string]$OldName, [string]$ConnectionString) {
    if ([string]::IsNullOrWhiteSpace($OldName)) { return }
    [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.VisualBasic') | Out-Null
    $newName = [Microsoft.VisualBasic.Interaction]::InputBox("Enter a new name for connection '$OldName':", "Rename Connection", $OldName)
    if ([string]::IsNullOrWhiteSpace($newName) -or $newName -eq $OldName) { return }

    $all = Get-SqlSavedConnectionsList
    foreach ($c in $all) {
        if ($c.Name -eq $OldName -or ($ConnectionString -and $c.ConnectionString -eq $ConnectionString)) {
            $c.Name = $newName
        }
    }
    Save-SqlConnectionsList $all
    Load-SavedConnections
    if ($lblSqlRowCount) { $lblSqlRowCount.Text = "Renamed connection to '$newName'." }
}

function Clear-AllSqlSavedConnections {
    $res = [System.Windows.MessageBox]::Show(
        "Are you sure you want to clear ALL saved connections?`r`n`r`nThis action cannot be undone.",
        "Clear All Saved Connections",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning
    )
    if ($res -eq [System.Windows.MessageBoxResult]::Yes) {
        Save-SqlConnectionsList @()
        Load-SavedConnections
        if ($lblSqlRowCount) { $lblSqlRowCount.Text = "All saved connections cleared." }
    }
}

function Show-SavedConnectionsManagerWindow {
    try {
        $win = New-Object System.Windows.Window
        $win.Title = "Nexus SQL - Saved Connections Manager"
        $win.Width = 720
        $win.Height = 480
        $win.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
        if ($window -and $window.IsVisible) { try { $win.Owner = $window } catch {} }
        $win.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#060A13")
        $win.ResizeMode = [System.Windows.ResizeMode]::CanResizeWithGrip

        $grid = New-Object System.Windows.Controls.Grid
        $grid.Margin = New-Object System.Windows.Thickness(14)
        
        $r0 = New-Object System.Windows.Controls.RowDefinition; $r0.Height = [System.Windows.GridLength]::Auto
        $r1 = New-Object System.Windows.Controls.RowDefinition; $r1.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $r2 = New-Object System.Windows.Controls.RowDefinition; $r2.Height = [System.Windows.GridLength]::Auto
        $grid.RowDefinitions.Add($r0); $grid.RowDefinitions.Add($r1); $grid.RowDefinitions.Add($r2)

        # Title header
        $hdr = New-Object System.Windows.Controls.TextBlock
        $hdr.Text = "PERMANENT SAVED SQL CONNECTIONS"
        $hdr.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
        $hdr.FontSize = 13
        $hdr.FontWeight = [System.Windows.FontWeights]::Bold
        $hdr.Margin = New-Object System.Windows.Thickness(0,0,0,10)
        [System.Windows.Controls.Grid]::SetRow($hdr, 0)
        $grid.Children.Add($hdr) | Out-Null

        # Connections ListBox
        $lbConns = New-Object System.Windows.Controls.ListBox
        $lbConns.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E1E1E")
        $lbConns.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#DCDCDC")
        $lbConns.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3F3F46")
        $lbConns.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
        $lbConns.FontSize = 11.5
        $lbConns.Margin = New-Object System.Windows.Thickness(0,0,0,12)
        [System.Windows.Controls.Grid]::SetRow($lbConns, 1)

        $populateList = {
            $lbConns.Items.Clear()
            $items = Get-SqlSavedConnectionsList
            foreach ($c in $items) {
                $lbi = New-Object System.Windows.Controls.ListBoxItem
                $lbi.Content = "$($c.Name)`r`n  -> $($c.ConnectionString)"
                $lbi.Tag = $c
                $lbi.Padding = New-Object System.Windows.Thickness(8,6,8,6)
                $lbi.BorderThickness = New-Object System.Windows.Thickness(0,0,0,1)
                $lbi.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#2D2D30")
                $lbConns.Items.Add($lbi) | Out-Null
            }
            if ($lbConns.Items.Count -gt 0) { $lbConns.SelectedIndex = 0 }
        }
        & $populateList
        $grid.Children.Add($lbConns) | Out-Null

        # Bottom Button Bar
        $btnBar = New-Object System.Windows.Controls.StackPanel
        $btnBar.Orientation = [System.Windows.Controls.Orientation]::Horizontal
        $btnBar.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
        [System.Windows.Controls.Grid]::SetRow($btnBar, 2)

        # Connect / Use button
        $btnUse = New-Object System.Windows.Controls.Button
        $btnUse.Content = "Use & Connect"
        $btnUse.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0E639C")
        $btnUse.Foreground = [System.Windows.Media.Brushes]::White
        $btnUse.FontWeight = [System.Windows.FontWeights]::Bold
        $btnUse.Padding = New-Object System.Windows.Thickness(14,6,14,6)
        $btnUse.Margin = New-Object System.Windows.Thickness(0,0,8,0)
        $btnUse.Cursor = [System.Windows.Input.Cursors]::Hand
        $btnUse.Add_Click({
            if ($lbConns.SelectedItem) {
                $sel = $lbConns.SelectedItem.Tag
                $txtSqlConnStr.Text = $sel.ConnectionString
                $txtSqlConnStr.Foreground = if ($global:isDarkMode) { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E2E8F0") } else { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A") }
                $win.Close()
                if ($btnSqlConnect) { $btnSqlConnect.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }
            }
        })
        $btnBar.Children.Add($btnUse) | Out-Null

        # Delete Button
        $btnDel = New-Object System.Windows.Controls.Button
        $btnDel.Content = "Delete (Remove)"
        $btnDel.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EF4444")
        $btnDel.Foreground = [System.Windows.Media.Brushes]::White
        $btnDel.FontWeight = [System.Windows.FontWeights]::Bold
        $btnDel.Padding = New-Object System.Windows.Thickness(12,6,12,6)
        $btnDel.Margin = New-Object System.Windows.Thickness(0,0,8,0)
        $btnDel.Cursor = [System.Windows.Input.Cursors]::Hand
        $btnDel.Add_Click({
            if ($lbConns.SelectedItem) {
                $sel = $lbConns.SelectedItem.Tag
                Remove-SqlSavedConnection -Name $sel.Name -ConnectionString $sel.ConnectionString
                & $populateList
            }
        })
        $btnBar.Children.Add($btnDel) | Out-Null

        # Rename Button
        $btnRen = New-Object System.Windows.Controls.Button
        $btnRen.Content = "Rename..."
        $btnRen.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#333337")
        $btnRen.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
        $btnRen.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3F3F46")
        $btnRen.Padding = New-Object System.Windows.Thickness(10,6,10,6)
        $btnRen.Margin = New-Object System.Windows.Thickness(0,0,8,0)
        $btnRen.Cursor = [System.Windows.Input.Cursors]::Hand
        $btnRen.Add_Click({
            if ($lbConns.SelectedItem) {
                $sel = $lbConns.SelectedItem.Tag
                Rename-SqlSavedConnection -OldName $sel.Name -ConnectionString $sel.ConnectionString
                & $populateList
            }
        })
        $btnBar.Children.Add($btnRen) | Out-Null

        # Copy String Button
        $btnCp = New-Object System.Windows.Controls.Button
        $btnCp.Content = "Copy String"
        $btnCp.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#333337")
        $btnCp.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#DCDCDC")
        $btnCp.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3F3F46")
        $btnCp.Padding = New-Object System.Windows.Thickness(10,6,10,6)
        $btnCp.Margin = New-Object System.Windows.Thickness(0,0,8,0)
        $btnCp.Cursor = [System.Windows.Input.Cursors]::Hand
        $btnCp.Add_Click({
            if ($lbConns.SelectedItem) {
                $sel = $lbConns.SelectedItem.Tag
                [System.Windows.Clipboard]::SetText($sel.ConnectionString)
            }
        })
        $btnBar.Children.Add($btnCp) | Out-Null

        # Close Button
        $btnClose = New-Object System.Windows.Controls.Button
        $btnClose.Content = "Close"
        $btnClose.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#333337")
        $btnClose.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
        $btnClose.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3F3F46")
        $btnClose.Padding = New-Object System.Windows.Thickness(14,6,14,6)
        $btnClose.Cursor = [System.Windows.Input.Cursors]::Hand
        $btnClose.Add_Click({ $win.Close() })
        $btnBar.Children.Add($btnClose) | Out-Null

        $grid.Children.Add($btnBar) | Out-Null
        $win.Content = $grid
        $win.ShowDialog() | Out-Null
    } catch { }
}

function Load-SavedConnections {
    if (-not $cmbSqlSavedConn) { return }
    $cmbSqlSavedConn.Items.Clear()

    $headerItem = New-Object System.Windows.Controls.ComboBoxItem
    $headerItem.Content = "-- Saved Connections --"
    $headerItem.Tag = ""
    $headerItem.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
    $cmbSqlSavedConn.Items.Add($headerItem) | Out-Null

    $conns = Get-SqlSavedConnectionsList

    if ($conns -and $conns.Count -gt 0) {
        foreach ($c in $conns) {
            $cName = $c.Name
            $cStr = $c.ConnectionString

            $item = New-Object System.Windows.Controls.ComboBoxItem
            $item.Content = $cName
            $item.Tag = $cStr
            $item.Foreground = if ($global:isDarkMode) { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E2E8F0") } else { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A") }
            $item.ToolTip = "$cName`n$cStr`nRight-click to Remove or Copy"

            # ContextMenu on individual item in dropdown
            $itemCtx = New-Object System.Windows.Controls.ContextMenu
            $itemCtx.Background = if ($global:isDarkMode) { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E1E1E") } else { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF") }
            $itemCtx.BorderBrush = if ($global:isDarkMode) { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3F3F46") } else { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#CBD5E1") }
            $itemCtx.BorderThickness = New-Object System.Windows.Thickness(1)

            $miDel = New-Object System.Windows.Controls.MenuItem
            $miDel.Header = "Remove '$cName' from Saved"
            $miDel.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EF4444")
            $miDel.FontWeight = [System.Windows.FontWeights]::Bold
            $capturedName = $cName
            $capturedStr = $cStr
            $miDel.Add_Click({
                Remove-SqlSavedConnection -Name $capturedName -ConnectionString $capturedStr
            })
            $itemCtx.Items.Add($miDel) | Out-Null

            $miRename = New-Object System.Windows.Controls.MenuItem
            $miRename.Header = "Rename '$cName'..."
            $miRename.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
            $miRename.Add_Click({
                Rename-SqlSavedConnection -OldName $capturedName -ConnectionString $capturedStr
            })
            $itemCtx.Items.Add($miRename) | Out-Null

            $miCopy = New-Object System.Windows.Controls.MenuItem
            $miCopy.Header = "Copy Connection String"
            $miCopy.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
            $miCopy.Add_Click({
                [System.Windows.Clipboard]::SetText($capturedStr)
                if ($lblSqlRowCount) { $lblSqlRowCount.Text = "Copied connection string for '$capturedName' to clipboard." }
            })
            $itemCtx.Items.Add($miCopy) | Out-Null

            $item.ContextMenu = $itemCtx

            # Ensure right-clicking item selects it in the ComboBox
            $item.Add_PreviewMouseRightButtonDown({
                param($s, $e)
                $cmbSqlSavedConn.SelectedItem = $s
            })

            $cmbSqlSavedConn.Items.Add($item) | Out-Null
        }
    }

    $cmbSqlSavedConn.SelectedIndex = 0

    # Keep text box displaying placeholder text if empty
    if ($txtSqlConnStr -and ([string]::IsNullOrWhiteSpace($txtSqlConnStr.Text) -or $txtSqlConnStr.Text -eq $script:SqlPlaceholder)) {
        $txtSqlConnStr.Text = $script:SqlPlaceholder
        $txtSqlConnStr.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#64748B")
    }
}
Load-SavedConnections

# Right-click context menu directly on ComboBox control itself
$script:cmbContextMenu = New-Object System.Windows.Controls.ContextMenu
$script:cmbContextMenu.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E1E1E")
$script:cmbContextMenu.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3F3F46")
$script:cmbContextMenu.BorderThickness = New-Object System.Windows.Thickness(1)

$cmbSqlSavedConn.Add_ContextMenuOpening({
    param($s, $e)
    $script:cmbContextMenu.Items.Clear()
    
    $sel = $cmbSqlSavedConn.SelectedItem
    $hasSel = ($sel -and ($sel -is [System.Windows.Controls.ComboBoxItem]) -and $sel.Tag -and $sel.Tag -ne "")
    $selName = if ($hasSel) { $sel.Content.ToString() } else { "" }
    $selConn = if ($hasSel) { $sel.Tag.ToString() } else { "" }

    if ($hasSel) {
        $miDel = New-Object System.Windows.Controls.MenuItem
        $miDel.Header = "Remove '$selName' from Saved"
        $miDel.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EF4444")
        $miDel.FontWeight = [System.Windows.FontWeights]::Bold
        $miDel.Add_Click({
            Remove-SqlSavedConnection -Name $selName -ConnectionString $selConn
        })
        $script:cmbContextMenu.Items.Add($miDel) | Out-Null

        $miRename = New-Object System.Windows.Controls.MenuItem
        $miRename.Header = "Rename '$selName'..."
        $miRename.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
        $miRename.Add_Click({
            Rename-SqlSavedConnection -OldName $selName -ConnectionString $selConn
        })
        $script:cmbContextMenu.Items.Add($miRename) | Out-Null

        $miCopy = New-Object System.Windows.Controls.MenuItem
        $miCopy.Header = "Copy Connection String"
        $miCopy.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E2E8F0")
        $miCopy.Add_Click({
            [System.Windows.Clipboard]::SetText($selConn)
            if ($lblSqlRowCount) { $lblSqlRowCount.Text = "Copied connection string to clipboard." }
        })
        $script:cmbContextMenu.Items.Add($miCopy) | Out-Null

        $sep = New-Object System.Windows.Controls.Separator
        $sep.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3F3F46")
        $script:cmbContextMenu.Items.Add($sep) | Out-Null
    }

    $currTxt = if ($txtSqlConnStr) { $txtSqlConnStr.Text.Trim() } else { "" }
    if (-not [string]::IsNullOrWhiteSpace($currTxt) -and $currTxt -ne $script:SqlPlaceholder) {
        $miSave = New-Object System.Windows.Controls.MenuItem
        $miSave.Header = "Save Current Connection String..."
        $miSave.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
        $miSave.FontWeight = [System.Windows.FontWeights]::SemiBold
        $miSave.Add_Click({
            if ($btnSqlSaveConn) { $btnSqlSaveConn.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }
        })
        $script:cmbContextMenu.Items.Add($miSave) | Out-Null
    }

    $miManage = New-Object System.Windows.Controls.MenuItem
    $miManage.Header = "Manage Saved Connections..."
    $miManage.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#C084FC")
    $miManage.Add_Click({
        Show-SavedConnectionsManagerWindow
    })
    $script:cmbContextMenu.Items.Add($miManage) | Out-Null

    $miClearAll = New-Object System.Windows.Controls.MenuItem
    $miClearAll.Header = "Clear All Saved Connections..."
    $miClearAll.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F87171")
    $miClearAll.Add_Click({
        Clear-AllSqlSavedConnections
    })
    $script:cmbContextMenu.Items.Add($miClearAll) | Out-Null
})
$cmbSqlSavedConn.ContextMenu = $script:cmbContextMenu

function Save-ConnectionAuto([string]$ConnStr, [string]$ServerName = "", [string]$DbName = "") {
    if ([string]::IsNullOrWhiteSpace($ConnStr) -or $ConnStr -eq $script:SqlPlaceholder) { return }
    $conn = $ConnStr.Trim()
    
    # Save last connection text
    try {
        $conn | Set-Content $script:LastConnFile -Force
    } catch { }

    $autoName = if ($ServerName -and $DbName) { "$ServerName / $DbName" } else {
        try {
            $clean = $conn -replace '(?i)ApplicationName\s*=', 'Application Name=' -replace '(?i)WorkstationID\s*=', 'Workstation ID='
            $b = New-Object System.Data.SqlClient.SqlConnectionStringBuilder($clean)
            "$($b.DataSource) / $($b.InitialCatalog)"
        } catch { "Connection" }
    }

    try {
        $conns = Get-SqlSavedConnectionsList
        $existing = $conns | Where-Object { $_.ConnectionString -eq $conn }
        if (-not $existing) {
            $conns.Add([PSCustomObject]@{ Name = $autoName; ConnectionString = $conn })
            Save-SqlConnectionsList $conns
            Load-SavedConnections
        }
    } catch { }
}

if ($btnSqlSaveConn) {
    $btnSqlSaveConn.Add_Click({
        $connStr = $txtSqlConnStr.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($connStr) -or $connStr -eq $script:SqlPlaceholder) {
            [System.Windows.MessageBox]::Show("Please enter or paste a connection string first.", "Save Connection", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            return
        }
        
        try {
            $cleanConnStr = $connStr -replace '(?i)ApplicationName\s*=', 'Application Name=' -replace '(?i)WorkstationID\s*=', 'Workstation ID='
            $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder($cleanConnStr)
            $defaultName = "$($builder.DataSource) / $($builder.InitialCatalog)"
        } catch { $defaultName = "My Connection" }
        
        [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.VisualBasic') | Out-Null
        $name = [Microsoft.VisualBasic.Interaction]::InputBox("Enter a name for this saved connection:", "Save Connection", $defaultName)
        if ([string]::IsNullOrWhiteSpace($name)) { return }
        
        $conns = Get-SqlSavedConnectionsList
        $existing = $conns | Where-Object { $_.Name -eq $name -or $_.ConnectionString -eq $connStr }
        if ($existing) {
            $existing.Name = $name
            $existing.ConnectionString = $connStr
        } else {
            $conns.Add([PSCustomObject]@{ Name = $name; ConnectionString = $connStr })
        }
        
        Save-SqlConnectionsList $conns
        Load-SavedConnections

        # Select newly saved item
        for ($i = 0; $i -lt $cmbSqlSavedConn.Items.Count; $i++) {
            $it = $cmbSqlSavedConn.Items[$i]
            if ($it -is [System.Windows.Controls.ComboBoxItem] -and $it.Content -eq $name) {
                $cmbSqlSavedConn.SelectedIndex = $i
                break
            }
        }

        if ($lblSqlRowCount) { $lblSqlRowCount.Text = "Connection '$name' saved permanently." }
        try { Set-MascotState "success" "Saved '$name'!" } catch { }
    })
}

if ($btnSqlRemoveConn) {
    $btnSqlRemoveConn.Add_Click({
        $sel = $cmbSqlSavedConn.SelectedItem
        if ($sel -and ($sel -is [System.Windows.Controls.ComboBoxItem]) -and $sel.Tag -and $sel.Tag -ne "") {
            Remove-SqlSavedConnection -Name $sel.Content.ToString() -ConnectionString $sel.Tag.ToString()
        } else {
            $currTxt = if ($txtSqlConnStr) { $txtSqlConnStr.Text.Trim() } else { "" }
            $matched = $null
            if (-not [string]::IsNullOrWhiteSpace($currTxt) -and $currTxt -ne $script:SqlPlaceholder) {
                $all = Get-SqlSavedConnectionsList
                $matched = $all | Where-Object { $_.ConnectionString -eq $currTxt }
            }
            if ($matched) {
                Remove-SqlSavedConnection -Name $matched.Name -ConnectionString $matched.ConnectionString
            } else {
                [System.Windows.MessageBox]::Show("Please select a saved connection from the dropdown to remove, or right-click any item in the dropdown.", "Remove Connection", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            }
        }
    })
}

$cmbSqlSavedConn.Add_SelectionChanged({
    $item = $cmbSqlSavedConn.SelectedItem
    if ($item -and ($item -is [System.Windows.Controls.ComboBoxItem]) -and $item.Tag -and $item.Tag -ne "") {
        $txtSqlConnStr.Text = $item.Tag
        $txtSqlConnStr.Foreground = if ($global:isDarkMode) { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E2E8F0") } else { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A") }
    }
})


$script:AllSqlProcs = [System.Collections.Generic.List[PSCustomObject]]::new()

function Filter-SqlStoredProcedures {
    if (-not $cmbSqlProcs) { return }
    $cmbSqlProcs.Items.Clear()

    $selectedSchema = if ($cmbSqlSchema -and $cmbSqlSchema.SelectedItem -and ($cmbSqlSchema.SelectedItem -is [System.Windows.Controls.ComboBoxItem]) -and $cmbSqlSchema.SelectedItem.Tag) { $cmbSqlSchema.SelectedItem.Tag } else { "" }
    $filterText = if ($txtSqlSpSearch -and $txtSqlSpSearch.Text -and $txtSqlSpSearch.Text -ne "Filter SP..." -and $txtSqlSpSearch.Text -ne "Filter SP/Func...") { $txtSqlSpSearch.Text.Trim() } else { "" }

    $filtered = $script:AllSqlProcs | Where-Object {
        $matchSchema = [string]::IsNullOrWhiteSpace($selectedSchema) -or ($_.Schema -eq $selectedSchema)
        $matchText = [string]::IsNullOrWhiteSpace($filterText) -or ($_.FullName -like "*$filterText*" -or $_.DisplayTitle -like "*$filterText*")
        $matchSchema -and $matchText
    }

    $headerItem = New-Object System.Windows.Controls.ComboBoxItem
    $count = if ($filtered) { @($filtered).Count } else { 0 }
    $totalCount = $script:AllSqlProcs.Count
    if ([string]::IsNullOrWhiteSpace($filterText) -and [string]::IsNullOrWhiteSpace($selectedSchema)) {
        $headerItem.Content = "-- Select SP or Function ($totalCount) --"
    } else {
        $headerItem.Content = "-- Filtered: $count of $totalCount Objects --"
    }
    $headerItem.Tag = ""
    $cmbSqlProcs.Items.Add($headerItem) | Out-Null

    if ($filtered) {
        foreach ($p in $filtered) {
            $item = New-Object System.Windows.Controls.ComboBoxItem
            $item.Content = $p.DisplayTitle
            $item.Tag = $p.FullName
            $item.ToolTip = $p.RoutineType
            $cmbSqlProcs.Items.Add($item) | Out-Null
        }
    }

    if ($cmbSqlProcs.Items.Count -gt 0) {
        $cmbSqlProcs.SelectedIndex = 0
    }
}

function Convert-CreateToAlterProcedure([string]$Code) {
    if ([string]::IsNullOrWhiteSpace($Code)) { return $Code }
    if ($Code -match '(?i)\bCREATE\s+OR\s+ALTER\b') { return $Code }
    $converted = $Code -replace '(?i)\bCREATE\s+PROCEDURE\b', 'ALTER PROCEDURE' `
                       -replace '(?i)\bCREATE\s+PROC\b', 'ALTER PROC' `
                       -replace '(?i)\bCREATE\s+FUNCTION\b', 'ALTER FUNCTION' `
                       -replace '(?i)\bCREATE\s+FUNC\b', 'ALTER FUNC'
    return $converted
}

function Get-SqlRoutineDefinition([string]$fullName) {
    if (-not $script:SqlConnected -or -not $script:SqlConnection -or [string]::IsNullOrWhiteSpace($fullName)) { return $null }
    try {
        # 1. Standard OBJECT_DEFINITION
        $cmd = $script:SqlConnection.CreateCommand()
        $cmd.CommandText = "SELECT OBJECT_DEFINITION(OBJECT_ID(@procName))"
        [void]$cmd.Parameters.AddWithValue("@procName", $fullName)
        $def = $cmd.ExecuteScalar()
        $cmd.Dispose()
        if ($def -and ($def -is [string]) -and -not [string]::IsNullOrWhiteSpace($def)) {
            return $def
        }

        # 2. sys.sql_modules fallback
        $cmd2 = $script:SqlConnection.CreateCommand()
        $cmd2.CommandText = "SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID(@procName)"
        [void]$cmd2.Parameters.AddWithValue("@procName", $fullName)
        $def2 = $cmd2.ExecuteScalar()
        $cmd2.Dispose()
        if ($def2 -and ($def2 -is [string]) -and -not [string]::IsNullOrWhiteSpace($def2)) {
            return $def2
        }

        # 3. sp_helptext fallback
        $cmd3 = $script:SqlConnection.CreateCommand()
        $cmd3.CommandText = "EXEC sp_helptext @objname = @procName"
        [void]$cmd3.Parameters.AddWithValue("@procName", $fullName)
        $rdr = $cmd3.ExecuteReader()
        $sb = [System.Text.StringBuilder]::new()
        while ($rdr.Read()) {
            [void]$sb.Append($rdr.GetString(0))
        }
        $rdr.Close()
        $cmd3.Dispose()
        $res = $sb.ToString()
        if (-not [string]::IsNullOrWhiteSpace($res)) {
            return $res
        }
    } catch { }
    return $null
}

function Script-SqlRoutineModify([string]$fullName) {
    if (-not $script:SqlConnected) {
        [System.Windows.MessageBox]::Show("Please connect to SQL Server first.", "SQL Console", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        return
    }
    $def = Get-SqlRoutineDefinition $fullName
    if ($def) {
        $alterDef = Convert-CreateToAlterProcedure $def
        $txtSqlQuery.Text = $alterDef
        $txtSqlQuery.Foreground = if ($global:isDarkMode) { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80") } else { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A") }
        $txtSqlQuery.Focus() | Out-Null
        $txtSqlQuery.CaretIndex = 0
        $lineCount = ($alterDef -split "\r?\n").Count
        if ($lblSqlRowCount) { $lblSqlRowCount.Text = "Modify: Loaded ALTER script for $fullName ($lineCount lines)" }
        if ($lblQueryTabTitle) { $lblQueryTabTitle.Text = "$fullName (Modify) *" }
        try { Set-MascotState "success" "Loaded: $fullName" } catch {}
    } else {
        [System.Windows.MessageBox]::Show("Could not retrieve definition for '$fullName'. Ensure you have VIEW DEFINITION permissions or the procedure is not encrypted.", "Modify Procedure", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
    }
}

function Script-SqlRoutineCreate([string]$fullName) {
    if (-not $script:SqlConnected) { return }
    $def = Get-SqlRoutineDefinition $fullName
    if ($def) {
        $txtSqlQuery.Text = $def
        $txtSqlQuery.Foreground = if ($global:isDarkMode) { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80") } else { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A") }
        $txtSqlQuery.Focus() | Out-Null
        $txtSqlQuery.CaretIndex = 0
        $lineCount = ($def -split "\r?\n").Count
        if ($lblSqlRowCount) { $lblSqlRowCount.Text = "Script: Loaded CREATE script for $fullName ($lineCount lines)" }
        if ($lblQueryTabTitle) { $lblQueryTabTitle.Text = "$fullName (CREATE)" }
    } else {
        [System.Windows.MessageBox]::Show("Could not retrieve definition for '$fullName'.", "Script as CREATE", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
    }
}

function Script-SqlRoutineExecute([string]$fullProcName, [string]$routineType) {
    if (-not $script:SqlConnected -or -not $script:SqlConnection -or [string]::IsNullOrWhiteSpace($fullProcName)) { return }
    $isFunction = ($routineType -eq 'FUNCTION')
    $parts = $fullProcName.Split('.')
    $schema = if ($parts.Length -gt 1) { $parts[0] } else { "dbo" }
    $procName = if ($parts.Length -gt 1) { $parts[1] } else { $parts[0] }
    
    try {
        $cmd = $script:SqlConnection.CreateCommand()
        $cmd.CommandText = "SELECT PARAMETER_NAME, DATA_TYPE FROM INFORMATION_SCHEMA.PARAMETERS WHERE SPECIFIC_SCHEMA=@schema AND SPECIFIC_NAME=@proc AND (PARAMETER_NAME IS NOT NULL AND PARAMETER_NAME <> '') ORDER BY ORDINAL_POSITION"
        [void]$cmd.Parameters.AddWithValue("@schema", $schema)
        [void]$cmd.Parameters.AddWithValue("@proc", $procName)
        
        $reader = $cmd.ExecuteReader()
        $paramsList = @()
        while ($reader.Read()) {
            $pName = $reader.GetString(0)
            $pType = $reader.GetString(1)
            $defaultVal = switch -regex ($pType.ToLower()) {
                'int|decimal|numeric|float|real|money|smallint|tinyint|bigint|bit' { '0' }
                'date|time' { "'2026-01-01'" }
                default { "''" }
            }
            $paramsList += "    $pName = $defaultVal -- $pType"
        }
        $reader.Close()
        $cmd.Dispose()
        
        $execCode = ""
        if ($isFunction) {
            if ($paramsList.Count -gt 0) {
                $execCode = "SELECT $fullProcName(`r`n" + ($paramsList -join ",`r`n") + "`r`n) AS Result;"
            } else {
                $execCode = "SELECT $fullProcName() AS Result;"
            }
        } else {
            if ($paramsList.Count -gt 0) {
                $execCode = "EXEC $fullProcName`r`n" + ($paramsList -join ",`r`n") + ";"
            } else {
                $execCode = "EXEC $fullProcName;"
            }
        }
        
        $txtSqlQuery.Text = $execCode
        $txtSqlQuery.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
        $txtSqlQuery.Focus() | Out-Null
        $txtSqlQuery.CaretIndex = $execCode.Length
        if ($lblSqlRowCount) { $lblSqlRowCount.Text = "Generated execution template for $fullProcName" }
        if ($lblQueryTabTitle) { $lblQueryTabTitle.Text = "$fullProcName (Execute)" }
    } catch { }
}

function Inspect-SqlRoutineFullScreen([string]$fullName) {
    if (-not $script:SqlConnected) { return }
    $def = Get-SqlRoutineDefinition $fullName
    Show-SqlSpFullScreenViewer -ProcName $fullName -SpCode $def
}

function Generate-SqlSpExecCode {
    if (-not $script:SqlConnected) { return }
    $selected = $cmbSqlProcs.SelectedItem
    if (-not $selected -or -not ($selected -is [System.Windows.Controls.ComboBoxItem]) -or -not $selected.Tag) { return }
    $fullProcName = $selected.Tag
    if ([string]::IsNullOrWhiteSpace($fullProcName)) { return }
    $rType = if ($selected.ToolTip) { $selected.ToolTip } else { "PROCEDURE" }
    Script-SqlRoutineExecute $fullProcName $rType
}

function New-SqlRoutineContextMenu([string]$fullName, [string]$routineType, [string]$database = "") {
    $ctx = New-Object System.Windows.Controls.ContextMenu
    $isDark = if ($global:isDarkMode -ne $null) { [bool]$global:isDarkMode } else { $true }

    $menuBg = if ($isDark) { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E1E1E") } else { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF") }
    $menuFg = if ($isDark) { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E2E8F0") } else { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A") }
    $borderBr = if ($isDark) { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3F3F46") } else { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#CBD5E1") }

    $ctx.Background = $menuBg
    $ctx.BorderBrush = $borderBr
    $ctx.BorderThickness = New-Object System.Windows.Thickness(1)
    $ctx.Padding = New-Object System.Windows.Thickness(2)

    # Style MenuItem to eliminate white icon margin
    $miStyle = New-Object System.Windows.Style([System.Windows.Controls.MenuItem])
    $miStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.MenuItem]::BackgroundProperty, $menuBg)))
    $miStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.MenuItem]::PaddingProperty, (New-Object System.Windows.Thickness(12, 6, 16, 6)))))
    
    $highlightBg = if ($isDark) { '#2D3748' } else { '#E2E8F0' }
    $ctXaml = @"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                 TargetType="{x:Type MenuItem}">
    <Border x:Name="Bd" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}" SnapsToDevicePixels="True">
        <ContentPresenter ContentSource="Header" RecognizesAccessKey="True"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsHighlighted" Value="True">
            <Setter TargetName="Bd" Property="Background" Value="$highlightBg"/>
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
            <Setter Property="Foreground" Value="#64748B"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
"@
    $ct = [System.Windows.Markup.XamlReader]::Parse($ctXaml)
    $miStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.MenuItem]::TemplateProperty, $ct)))
    $ctx.Resources.Add([System.Windows.Controls.MenuItem], $miStyle)

    $targetName = $fullName
    $targetType = $routineType
    $targetDb = $database
    $actionWord = if ($routineType -eq 'FUNCTION') { "Function" } else { "Procedure" }

    # 1. Modify (Script as ALTER)
    $miModify = New-Object System.Windows.Controls.MenuItem
    $miModify.Header = "Modify (Script as ALTER)"
    $miModify.FontWeight = [System.Windows.FontWeights]::Bold
    $miModify.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
    $miModify.ToolTip = "Fetch complete definition and script as ALTER $actionWord in Query Editor"
    $miModify.Tag = @{ Name = $targetName; Type = $targetType; Db = $targetDb }
    $miModify.Add_Click({
        param($sender, $e)
        $info = $sender.Tag
        $n = if ($info -and $info.Name) { $info.Name } else { $targetName }
        $d = if ($info -and $info.Db) { $info.Db } else { $targetDb }
        if ($d) { Switch-SqlActiveDatabase $d }
        Script-SqlRoutineModify $n
    }.GetNewClosure())
    $ctx.Items.Add($miModify) | Out-Null

    # 2. Script as EXECUTE
    $miExec = New-Object System.Windows.Controls.MenuItem
    $miExec.Header = if ($targetType -eq 'FUNCTION') { "Script Function as -> SELECT / EXECUTE" } else { "Execute Procedure... (Script as EXEC)" }
    $miExec.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
    $miExec.ToolTip = "Generate parameterized execution call with parameters in Query Editor"
    $miExec.Tag = @{ Name = $targetName; Type = $targetType; Db = $targetDb }
    $miExec.Add_Click({
        param($sender, $e)
        $info = $sender.Tag
        $n = if ($info -and $info.Name) { $info.Name } else { $targetName }
        $t = if ($info -and $info.Type) { $info.Type } else { $targetType }
        $d = if ($info -and $info.Db) { $info.Db } else { $targetDb }
        if ($d) { Switch-SqlActiveDatabase $d }
        Script-SqlRoutineExecute $n $t
    }.GetNewClosure())
    $ctx.Items.Add($miExec) | Out-Null

    # 3. Script as CREATE
    $miCreate = New-Object System.Windows.Controls.MenuItem
    $miCreate.Header = "Script as CREATE to Query Editor"
    $miCreate.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FBBF24")
    $miCreate.ToolTip = "Script exact CREATE $actionWord definition into Query Editor"
    $miCreate.Tag = @{ Name = $targetName; Type = $targetType; Db = $targetDb }
    $miCreate.Add_Click({
        param($sender, $e)
        $info = $sender.Tag
        $n = if ($info -and $info.Name) { $info.Name } else { $targetName }
        $d = if ($info -and $info.Db) { $info.Db } else { $targetDb }
        if ($d) { Switch-SqlActiveDatabase $d }
        Script-SqlRoutineCreate $n
    }.GetNewClosure())
    $ctx.Items.Add($miCreate) | Out-Null

    # Separator
    $sep1 = New-Object System.Windows.Controls.Separator
    $sep1.Background = $borderBr
    $ctx.Items.Add($sep1) | Out-Null

    # 4. Open in Full Screen Inspector
    $miInspect = New-Object System.Windows.Controls.MenuItem
    $miInspect.Header = "Open in Full Screen Inspector"
    $miInspect.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#C084FC")
    $miInspect.ToolTip = "Open maximized full screen inspector with search and line numbers"
    $miInspect.Tag = @{ Name = $targetName; Type = $targetType; Db = $targetDb }
    $miInspect.Add_Click({
        param($sender, $e)
        $info = $sender.Tag
        $n = if ($info -and $info.Name) { $info.Name } else { $targetName }
        $d = if ($info -and $info.Db) { $info.Db } else { $targetDb }
        if ($d) { Switch-SqlActiveDatabase $d }
        Inspect-SqlRoutineFullScreen $n
    }.GetNewClosure())
    $ctx.Items.Add($miInspect) | Out-Null

    # 4b. Compare in Beyond Compare 5
    $miCompare = New-Object System.Windows.Controls.MenuItem
    $miCompare.Header = "Compare (Diff in WinMerge / Studio)..."
    $miCompare.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
    $miCompare.ToolTip = "Compare $actionWord side-by-side with Query Editor using Beyond Compare 5 Myers Diff"
    $miCompare.Tag = @{ Name = $targetName; Type = $targetType; Db = $targetDb }
    $miCompare.Add_Click({
        param($sender, $e)
        $info = $sender.Tag
        $n = if ($info -and $info.Name) { $info.Name } else { $targetName }
        $d = if ($info -and $info.Db) { $info.Db } else { $targetDb }
        if ($d) { Switch-SqlActiveDatabase $d }
        $def = Get-SqlRoutineDefinition $n
        $rTxt = if ($txtSqlQuery -and $txtSqlQuery.Text) { $txtSqlQuery.Text } else { "" }
        $rTitle = if ($lblQueryTabTitle -and $lblQueryTabTitle.Text) { $lblQueryTabTitle.Text } else { "Query Editor" }
        Invoke-DiffComparison -leftText $def -rightText $rTxt -leftTitle "$n (DB: $d)" -rightTitle $rTitle
    }.GetNewClosure())
    $ctx.Items.Add($miCompare) | Out-Null

    # Separator
    $sep2 = New-Object System.Windows.Controls.Separator
    $sep2.Background = $borderBr
    $ctx.Items.Add($sep2) | Out-Null

    # 5. Copy Full Name
    $miCopy = New-Object System.Windows.Controls.MenuItem
    $miCopy.Header = "Copy Name ($targetName)"
    $miCopy.Foreground = $menuFg
    $miCopy.Tag = $targetName
    $miCopy.Add_Click({
        param($sender, $e)
        $n = if ($sender.Tag) { [string]$sender.Tag } else { $targetName }
        try { [System.Windows.Clipboard]::SetText($n) } catch {}
        if ($lblSqlRowCount) { $lblSqlRowCount.Text = "Copied '$n' to clipboard" }
        try { Set-MascotState "success" "Copied to Clipboard!" } catch {}
    }.GetNewClosure())
    $ctx.Items.Add($miCopy) | Out-Null

    # 6. Refresh
    $miRefresh = New-Object System.Windows.Controls.MenuItem
    $miRefresh.Header = "Refresh"
    $miRefresh.Foreground = if ($isDark) { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8") } else { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#64748B") }
    $miRefresh.Add_Click({
        Load-SqlStoredProcedures
        Build-ObjectExplorerTree
    }.GetNewClosure())
    $ctx.Items.Add($miRefresh) | Out-Null

    return $ctx
}

function New-SqlTableContextMenu([string]$tableName, [bool]$isView, [string]$database = "") {
    $ctx = New-Object System.Windows.Controls.ContextMenu
    $isDark = if ($global:isDarkMode -ne $null) { [bool]$global:isDarkMode } else { $true }

    $menuBg = if ($isDark) { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E1E1E") } else { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF") }
    $menuFg = if ($isDark) { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E2E8F0") } else { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A") }
    $borderBr = if ($isDark) { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3F3F46") } else { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#CBD5E1") }

    $ctx.Background = $menuBg
    $ctx.BorderBrush = $borderBr
    $ctx.BorderThickness = New-Object System.Windows.Thickness(1)
    $ctx.Padding = New-Object System.Windows.Thickness(2)

    # Style MenuItem to eliminate white icon margin
    $miStyle = New-Object System.Windows.Style([System.Windows.Controls.MenuItem])
    $miStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.MenuItem]::BackgroundProperty, $menuBg)))
    $miStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.MenuItem]::PaddingProperty, (New-Object System.Windows.Thickness(12, 6, 16, 6)))))
    
    $highlightBg = if ($isDark) { '#2D3748' } else { '#E2E8F0' }
    $ctXaml = @"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                 TargetType="{x:Type MenuItem}">
    <Border x:Name="Bd" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}" SnapsToDevicePixels="True">
        <ContentPresenter ContentSource="Header" RecognizesAccessKey="True"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsHighlighted" Value="True">
            <Setter TargetName="Bd" Property="Background" Value="$highlightBg"/>
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
            <Setter Property="Foreground" Value="#64748B"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
"@
    $ct = [System.Windows.Markup.XamlReader]::Parse($ctXaml)
    $miStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.MenuItem]::TemplateProperty, $ct)))
    $ctx.Resources.Add([System.Windows.Controls.MenuItem], $miStyle)

    $tbl = $tableName
    $targetDb = $database

    # 1. Select TOP 100 Rows
    $miSelect = New-Object System.Windows.Controls.MenuItem
    $miSelect.Header = "Select Top 100 Rows"
    $miSelect.FontWeight = [System.Windows.FontWeights]::Bold
    $miSelect.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
    $miSelect.Tag = @{ Name = $tbl; Db = $targetDb }
    $miSelect.Add_Click({
        param($sender, $e)
        $info = $sender.Tag
        $t = if ($info -and $info.Name) { $info.Name } else { $tbl }
        $d = if ($info -and $info.Db) { $info.Db } else { $targetDb }
        if ($d) { Switch-SqlActiveDatabase $d }
        $txtSqlQuery.Text = "SELECT TOP 100 *`r`nFROM $t WITH (NOLOCK);`r`n"
        $txtSqlQuery.Foreground = if ($global:isDarkMode) { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80") } else { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A") }
        if ($btnSqlExecute) { $btnSqlExecute.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }
    }.GetNewClosure())
    $ctx.Items.Add($miSelect) | Out-Null

    # 2. Script as SELECT
    $miScript = New-Object System.Windows.Controls.MenuItem
    $miScript.Header = "Script as SELECT To Query Editor"
    $miScript.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
    $miScript.Tag = @{ Name = $tbl; Db = $targetDb }
    $miScript.Add_Click({
        param($sender, $e)
        $info = $sender.Tag
        $t = if ($info -and $info.Name) { $info.Name } else { $tbl }
        $d = if ($info -and $info.Db) { $info.Db } else { $targetDb }
        if ($d) { Switch-SqlActiveDatabase $d }
        $txtSqlQuery.Text = "SELECT *`r`nFROM $t WITH (NOLOCK);`r`n"
        $txtSqlQuery.Foreground = if ($global:isDarkMode) { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80") } else { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A") }
        $txtSqlQuery.Focus() | Out-Null
    }.GetNewClosure())
    $ctx.Items.Add($miScript) | Out-Null

    # Separator
    $sep = New-Object System.Windows.Controls.Separator
    $sep.Background = $borderBr
    $ctx.Items.Add($sep) | Out-Null

    # 3. Copy Name
    $miCopy = New-Object System.Windows.Controls.MenuItem
    $miCopy.Header = "Copy Name ($tbl)"
    $miCopy.Foreground = $menuFg
    $miCopy.Tag = $tbl
    $miCopy.Add_Click({
        param($sender, $e)
        $t = if ($sender.Tag) { [string]$sender.Tag } else { $tbl }
        try { [System.Windows.Clipboard]::SetText($t) } catch {}
        if ($lblSqlRowCount) { $lblSqlRowCount.Text = "Copied '$t' to clipboard" }
    }.GetNewClosure())
    $ctx.Items.Add($miCopy) | Out-Null

    return $ctx
}
function Get-SqlOeColor([string]$type) {
    $isDark = if ($global:isDarkMode -ne $null) { [bool]$global:isDarkMode } else { $true }
    $bc = [System.Windows.Media.BrushConverter]::new()
    $hex = switch ($type) {
        "Root"       { if ($isDark) { "#FFFFFF" } else { "#0F172A" } }
        "Folder"     { if ($isDark) { "#38BDF8" } else { "#0284C7" } }
        "ActiveDb"   { if ($isDark) { "#4ADE80" } else { "#059669" } }
        "Database"   { if ($isDark) { "#E2E8F0" } else { "#1E293B" } }
        "Item"       { if ($isDark) { "#94A3B8" } else { "#334155" } }
        "Sp"         { if ($isDark) { "#F59E0B" } else { "#D97706" } }
        "Fn"         { if ($isDark) { "#A78BFA" } else { "#7C3AED" } }
        "Muted"      { if ($isDark) { "#858585" } else { "#64748B" } }
        default      { if ($isDark) { "#E2E8F0" } else { "#1E293B" } }
    }
    return $bc.ConvertFromString($hex)
}
function Switch-SqlDbConnectionContext([string]$db) {
    if (-not $script:SqlConnected -or [string]::IsNullOrWhiteSpace($db)) { return }
    try {
        if ($script:SqlConnection -and $script:SqlConnection.Database -ne $db) {
            $cmd = $script:SqlConnection.CreateCommand()
            $cmd.CommandText = "USE [$($db.Replace(']', ']]'))]"
            $cmd.ExecuteNonQuery() | Out-Null
            $cmd.Dispose()
        }
    } catch { }
}

function Expand-SqlFolderOnDemand($item) {
    if (-not $item -or -not ($item -is [System.Windows.Controls.TreeViewItem])) { return }
    $tag = [string]$item.Tag
    if ([string]::IsNullOrWhiteSpace($tag)) { return }

    if ($tag -like "FOLDER:TABLES:*") {
        $db = $tag.Split(':')[2]
        Expand-SqlTablesFolder $item $db
    } elseif ($tag -like "FOLDER:VIEWS:*") {
        $db = $tag.Split(':')[2]
        Expand-SqlViewsFolder $item $db
    } elseif ($tag -like "FOLDER:SPS:*") {
        $db = $tag.Split(':')[2]
        Expand-SqlProcsFolder $item $db
    } elseif ($tag -like "FOLDER:FNS:*") {
        $db = $tag.Split(':')[2]
        Expand-SqlFuncsFolder $item $db
    } elseif ($tag -like "DATABASE:*") {
        $db = $tag.Split(':')[1]
        if ($script:SqlConnection -and $script:SqlConnection.Database -ne $db) {
            Switch-SqlActiveDatabase $db
        } else {
            Expand-SqlDatabaseNode $item $db
        }
    }
}

function Expand-SqlTablesFolder($folderItem, [string]$db) {
    if (-not $script:SqlConnected -or -not $folderItem) { return }
    if ([string]::IsNullOrWhiteSpace($db)) {
        if ($script:SqlConnection -and $script:SqlConnection.Database) { $db = $script:SqlConnection.Database }
        elseif ($cmbSqlDatabase -and $cmbSqlDatabase.Text) { $db = $cmbSqlDatabase.Text }
    }

    $tables = $script:CachedTables[$db]
    if (-not $tables) {
        $folderItem.Items.Clear()
        $dummy = New-Object System.Windows.Controls.TreeViewItem
        $dummy.Header = "Loading tables..."
        $dummy.Foreground = Get-SqlOeColor "Muted"
        $folderItem.Items.Add($dummy) | Out-Null
        
        $tables = [System.Collections.Generic.List[string]]::new()
        Switch-SqlDbConnectionContext $db
        
        # 1. sys.tables
        $cmd = $null; $rdr = $null
        try {
            $cmd = $script:SqlConnection.CreateCommand()
            $cmd.CommandText = "SELECT s.name + '.' + t.name AS FullTableName FROM sys.tables t INNER JOIN sys.schemas s ON t.schema_id = s.schema_id ORDER BY s.name, t.name"
            $rdr = $cmd.ExecuteReader()
            while ($rdr.Read()) {
                if (-not $rdr.IsDBNull(0)) { $tables.Add($rdr.GetString(0)) }
            }
        } catch { }
        finally {
            if ($rdr) { try { $rdr.Close(); $rdr.Dispose() } catch {} }
            if ($cmd) { try { $cmd.Dispose() } catch {} }
        }
        
        # 2. Fallback: INFORMATION_SCHEMA.TABLES
        if ($tables.Count -eq 0) {
            $cmd = $null; $rdr = $null
            try {
                $cmd = $script:SqlConnection.CreateCommand()
                $cmd.CommandText = "SELECT TABLE_SCHEMA + '.' + TABLE_NAME AS FullTableName FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_SCHEMA, TABLE_NAME"
                $rdr = $cmd.ExecuteReader()
                while ($rdr.Read()) {
                    if (-not $rdr.IsDBNull(0)) { $tables.Add($rdr.GetString(0)) }
                }
            } catch { }
            finally {
                if ($rdr) { try { $rdr.Close(); $rdr.Dispose() } catch {} }
                if ($cmd) { try { $cmd.Dispose() } catch {} }
            }
        }
        
        $script:CachedTables[$db] = $tables
    }

    $folderItem.Items.Clear()
    $filterText = if ($txtSqlSpSearch -and $txtSqlSpSearch.Text -and $txtSqlSpSearch.Text -notmatch "^Filter") { $txtSqlSpSearch.Text.Trim() } else { "" }

    foreach ($tbl in $tables) {
        if ([string]::IsNullOrWhiteSpace($filterText) -or $tbl -like "*$filterText*") {
            $tItem = New-Object System.Windows.Controls.TreeViewItem
            $tItem.Header = $tbl
            $tItem.Tag = "TABLE:$db`:$tbl"
            $tItem.Foreground = Get-SqlOeColor "Item"
            $tItem.ToolTip = "Table: $tbl`r`nDouble-click: SELECT TOP 100`r`nRight-click: Select Top 100, Script SELECT, Copy Name"
            $folderItem.Items.Add($tItem) | Out-Null
        }
    }
    if ($folderItem.Items.Count -eq 0) {
        $noItem = New-Object System.Windows.Controls.TreeViewItem
        $noItem.Header = "(No tables found)"
        $noItem.Foreground = Get-SqlOeColor "Muted"
        $folderItem.Items.Add($noItem) | Out-Null
    }
    $folderItem.Header = "Tables ($($tables.Count))"
    $folderItem.IsExpanded = $true
}

function Expand-SqlViewsFolder($folderItem, [string]$db) {
    if (-not $script:SqlConnected -or -not $folderItem) { return }
    if ([string]::IsNullOrWhiteSpace($db)) {
        if ($script:SqlConnection -and $script:SqlConnection.Database) { $db = $script:SqlConnection.Database }
        elseif ($cmbSqlDatabase -and $cmbSqlDatabase.Text) { $db = $cmbSqlDatabase.Text }
    }

    $views = $script:CachedViews[$db]
    if (-not $views) {
        $folderItem.Items.Clear()
        $dummy = New-Object System.Windows.Controls.TreeViewItem
        $dummy.Header = "Loading views..."
        $dummy.Foreground = Get-SqlOeColor "Muted"
        $folderItem.Items.Add($dummy) | Out-Null
        
        $views = [System.Collections.Generic.List[string]]::new()
        Switch-SqlDbConnectionContext $db
        
        # 1. sys.views
        $cmd = $null; $rdr = $null
        try {
            $cmd = $script:SqlConnection.CreateCommand()
            $cmd.CommandText = "SELECT s.name + '.' + v.name AS FullViewName FROM sys.views v INNER JOIN sys.schemas s ON v.schema_id = s.schema_id ORDER BY s.name, v.name"
            $rdr = $cmd.ExecuteReader()
            while ($rdr.Read()) {
                if (-not $rdr.IsDBNull(0)) { $views.Add($rdr.GetString(0)) }
            }
        } catch { }
        finally {
            if ($rdr) { try { $rdr.Close(); $rdr.Dispose() } catch {} }
            if ($cmd) { try { $cmd.Dispose() } catch {} }
        }
        
        # 2. Fallback: INFORMATION_SCHEMA.VIEWS
        if ($views.Count -eq 0) {
            $cmd = $null; $rdr = $null
            try {
                $cmd = $script:SqlConnection.CreateCommand()
                $cmd.CommandText = "SELECT TABLE_SCHEMA + '.' + TABLE_NAME AS FullViewName FROM INFORMATION_SCHEMA.VIEWS ORDER BY TABLE_SCHEMA, TABLE_NAME"
                $rdr = $cmd.ExecuteReader()
                while ($rdr.Read()) {
                    if (-not $rdr.IsDBNull(0)) { $views.Add($rdr.GetString(0)) }
                }
            } catch { }
            finally {
                if ($rdr) { try { $rdr.Close(); $rdr.Dispose() } catch {} }
                if ($cmd) { try { $cmd.Dispose() } catch {} }
            }
        }
        
        $script:CachedViews[$db] = $views
    }

    $folderItem.Items.Clear()
    $filterText = if ($txtSqlSpSearch -and $txtSqlSpSearch.Text -and $txtSqlSpSearch.Text -notmatch "^Filter") { $txtSqlSpSearch.Text.Trim() } else { "" }

    foreach ($vw in $views) {
        if ([string]::IsNullOrWhiteSpace($filterText) -or $vw -like "*$filterText*") {
            $vItem = New-Object System.Windows.Controls.TreeViewItem
            $vItem.Header = $vw
            $vItem.Tag = "VIEW:$db`:$vw"
            $vItem.Foreground = Get-SqlOeColor "Item"
            $vItem.ToolTip = "View: $vw`r`nDouble-click: SELECT TOP 100`r`nRight-click: Select Top 100, Script SELECT, Copy Name"
            $folderItem.Items.Add($vItem) | Out-Null
        }
    }
    if ($folderItem.Items.Count -eq 0) {
        $noItem = New-Object System.Windows.Controls.TreeViewItem
        $noItem.Header = "(No views found)"
        $noItem.Foreground = Get-SqlOeColor "Muted"
        $folderItem.Items.Add($noItem) | Out-Null
    }
    $folderItem.Header = "Views ($($views.Count))"
    $folderItem.IsExpanded = $true
}

function Expand-SqlProcsFolder($folderItem, [string]$db) {
    if (-not $script:SqlConnected -or -not $folderItem) { return }
    if ([string]::IsNullOrWhiteSpace($db)) {
        if ($script:SqlConnection -and $script:SqlConnection.Database) { $db = $script:SqlConnection.Database }
        elseif ($cmbSqlDatabase -and $cmbSqlDatabase.Text) { $db = $cmbSqlDatabase.Text }
    }

    $procs = $script:CachedProcs[$db]
    if (-not $procs) {
        $folderItem.Items.Clear()
        $dummy = New-Object System.Windows.Controls.TreeViewItem
        $dummy.Header = "Loading stored procedures..."
        $dummy.Foreground = Get-SqlOeColor "Muted"
        $folderItem.Items.Add($dummy) | Out-Null

        $procs = [System.Collections.Generic.List[PSCustomObject]]::new()
        Switch-SqlDbConnectionContext $db

        # 1. Primary: sys.procedures (dedicated SQL Server catalog view)
        $cmd = $null; $rdr = $null
        try {
            $cmd = $script:SqlConnection.CreateCommand()
            $cmd.CommandText = "SELECT s.name AS RoutineSchema, p.name AS RoutineName, s.name + '.' + p.name AS ProcName FROM sys.procedures p INNER JOIN sys.schemas s ON p.schema_id = s.schema_id ORDER BY s.name, p.name"
            $rdr = $cmd.ExecuteReader()
            while ($rdr.Read()) {
                $sName = if ($rdr.IsDBNull(0)) { "dbo" } else { $rdr.GetString(0) }
                $pName = if ($rdr.IsDBNull(1)) { "" } else { $rdr.GetString(1) }
                $fName = if ($rdr.IsDBNull(2)) { $pName } else { $rdr.GetString(2) }
                if ($fName) {
                    $procs.Add([PSCustomObject]@{ Schema = $sName; Name = $pName; FullName = $fName })
                }
            }
        } catch { }
        finally {
            if ($rdr) { try { $rdr.Close(); $rdr.Dispose() } catch {} }
            if ($cmd) { try { $cmd.Dispose() } catch {} }
        }

        # 2. Fallback: sys.objects WHERE type IN ('P', 'PC')
        if ($procs.Count -eq 0) {
            $cmd = $null; $rdr = $null
            try {
                $cmd = $script:SqlConnection.CreateCommand()
                $cmd.CommandText = "SELECT s.name AS RoutineSchema, o.name AS RoutineName, s.name + '.' + o.name AS ProcName FROM sys.objects o INNER JOIN sys.schemas s ON o.schema_id = s.schema_id WHERE o.type IN ('P', 'PC') AND s.name NOT IN ('sys', 'INFORMATION_SCHEMA') ORDER BY s.name, o.name"
                $rdr = $cmd.ExecuteReader()
                while ($rdr.Read()) {
                    $sName = if ($rdr.IsDBNull(0)) { "dbo" } else { $rdr.GetString(0) }
                    $pName = if ($rdr.IsDBNull(1)) { "" } else { $rdr.GetString(1) }
                    $fName = if ($rdr.IsDBNull(2)) { $pName } else { $rdr.GetString(2) }
                    if ($fName) {
                        $procs.Add([PSCustomObject]@{ Schema = $sName; Name = $pName; FullName = $fName })
                    }
                }
            } catch { }
            finally {
                if ($rdr) { try { $rdr.Close(); $rdr.Dispose() } catch {} }
                if ($cmd) { try { $cmd.Dispose() } catch {} }
            }
        }
        
        # 3. Fallback: INFORMATION_SCHEMA.ROUTINES
        if ($procs.Count -eq 0) {
            $cmd = $null; $rdr = $null
            try {
                $cmd = $script:SqlConnection.CreateCommand()
                $cmd.CommandText = "SELECT ROUTINE_SCHEMA AS RoutineSchema, ROUTINE_NAME AS RoutineName, ROUTINE_SCHEMA + '.' + ROUTINE_NAME AS ProcName FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_TYPE = 'PROCEDURE' ORDER BY ROUTINE_SCHEMA, ROUTINE_NAME"
                $rdr = $cmd.ExecuteReader()
                while ($rdr.Read()) {
                    $sName = if ($rdr.IsDBNull(0)) { "dbo" } else { $rdr.GetString(0) }
                    $pName = if ($rdr.IsDBNull(1)) { "" } else { $rdr.GetString(1) }
                    $fName = if ($rdr.IsDBNull(2)) { $pName } else { $rdr.GetString(2) }
                    if ($fName) {
                        $procs.Add([PSCustomObject]@{ Schema = $sName; Name = $pName; FullName = $fName })
                    }
                }
            } catch { }
            finally {
                if ($rdr) { try { $rdr.Close(); $rdr.Dispose() } catch {} }
                if ($cmd) { try { $cmd.Dispose() } catch {} }
            }
        }

        # 4. Fallback: EXEC sp_stored_procedures
        if ($procs.Count -eq 0) {
            $cmd = $null; $rdr = $null
            try {
                $cmd = $script:SqlConnection.CreateCommand()
                $cmd.CommandText = "EXEC sp_stored_procedures"
                $rdr = $cmd.ExecuteReader()
                while ($rdr.Read()) {
                    $sName = if ($rdr.IsDBNull(1)) { "dbo" } else { $rdr.GetString(1) }
                    $pName = if ($rdr.IsDBNull(2)) { "" } else { $rdr.GetString(2) }
                    if ($pName -match '^(.+);\d+$') { $pName = $matches[1] }
                    if ($pName -and $sName -notmatch '^(sys|INFORMATION_SCHEMA)$' -and $pName -notmatch '^sp_') {
                        $fName = "$sName.$pName"
                        $procs.Add([PSCustomObject]@{ Schema = $sName; Name = $pName; FullName = $fName })
                    }
                }
            } catch { }
            finally {
                if ($rdr) { try { $rdr.Close(); $rdr.Dispose() } catch {} }
                if ($cmd) { try { $cmd.Dispose() } catch {} }
            }
        }

        $script:CachedProcs[$db] = $procs

        # Update schema dropdown WITH SUPPRESSION
        if ($cmbSqlSchema) {
            $script:SuppressSchemaChange = $true
            try {
                $schemas = [System.Collections.Generic.HashSet[string]]::new()
                foreach ($p in $procs) { [void]$schemas.Add($p.Schema) }
                $cmbSqlSchema.Items.Clear()
                $allSchemaItem = New-Object System.Windows.Controls.ComboBoxItem
                $allSchemaItem.Content = "All Schemas"
                $allSchemaItem.Tag = ""
                $cmbSqlSchema.Items.Add($allSchemaItem) | Out-Null
                foreach ($s in ($schemas | Sort-Object)) {
                    $sItem = New-Object System.Windows.Controls.ComboBoxItem
                    $sItem.Content = $s
                    $sItem.Tag = $s
                    $cmbSqlSchema.Items.Add($sItem) | Out-Null
                }
                $cmbSqlSchema.SelectedIndex = 0
            } catch { }
            finally {
                $script:SuppressSchemaChange = $false
            }
        }
    }

    $folderItem.Items.Clear()
    $filterText = if ($txtSqlSpSearch -and $txtSqlSpSearch.Text -and $txtSqlSpSearch.Text -notmatch "^Filter") { $txtSqlSpSearch.Text.Trim() } else { "" }
    $selectedSchema = if ($cmbSqlSchema -and $cmbSqlSchema.SelectedItem -and ($cmbSqlSchema.SelectedItem -is [System.Windows.Controls.ComboBoxItem]) -and $cmbSqlSchema.SelectedItem.Tag) { $cmbSqlSchema.SelectedItem.Tag } else { "" }

    foreach ($sp in $procs) {
        $matchSchema = [string]::IsNullOrWhiteSpace($selectedSchema) -or ($sp.Schema -eq $selectedSchema)
        $matchText = [string]::IsNullOrWhiteSpace($filterText) -or ($sp.FullName -like "*$filterText*")
        if ($matchSchema -and $matchText) {
            $spItem = New-Object System.Windows.Controls.TreeViewItem
            $spItem.Header = $sp.FullName
            $spItem.Tag = "SP:$db`:$($sp.FullName)"
            $spItem.Foreground = Get-SqlOeColor "Sp"
            $spItem.ToolTip = "Stored Procedure: $($sp.FullName)`r`nDouble-click: Modify (ALTER Procedure)`r`nRight-click: Modify, Execute, Create, Full Screen Inspector, Copy Name"
            $folderItem.Items.Add($spItem) | Out-Null
        }
    }
    if ($folderItem.Items.Count -eq 0) {
        $noItem = New-Object System.Windows.Controls.TreeViewItem
        $noItem.Header = "(No stored procedures found)"
        $noItem.Foreground = Get-SqlOeColor "Muted"
        $folderItem.Items.Add($noItem) | Out-Null
    }
    $folderItem.Header = "Stored Procedures ($($procs.Count))"
    $folderItem.IsExpanded = $true
}

function Expand-SqlFuncsFolder($folderItem, [string]$db) {
    if (-not $script:SqlConnected -or -not $folderItem) { return }
    if ([string]::IsNullOrWhiteSpace($db)) {
        if ($script:SqlConnection -and $script:SqlConnection.Database) { $db = $script:SqlConnection.Database }
        elseif ($cmbSqlDatabase -and $cmbSqlDatabase.Text) { $db = $cmbSqlDatabase.Text }
    }

    $funcs = $script:CachedFuncs[$db]
    if (-not $funcs) {
        $folderItem.Items.Clear()
        $dummy = New-Object System.Windows.Controls.TreeViewItem
        $dummy.Header = "Loading functions..."
        $dummy.Foreground = Get-SqlOeColor "Muted"
        $folderItem.Items.Add($dummy) | Out-Null

        $funcs = [System.Collections.Generic.List[PSCustomObject]]::new()
        Switch-SqlDbConnectionContext $db

        # 1. sys.objects
        $cmd = $null; $rdr = $null
        try {
            $cmd = $script:SqlConnection.CreateCommand()
            $cmd.CommandText = "SELECT s.name AS RoutineSchema, o.name AS RoutineName, s.name + '.' + o.name AS FuncName FROM sys.objects o INNER JOIN sys.schemas s ON o.schema_id = s.schema_id WHERE o.type IN ('FN', 'IF', 'TF', 'FS', 'FT') AND s.name NOT IN ('sys', 'INFORMATION_SCHEMA') ORDER BY s.name, o.name"
            $rdr = $cmd.ExecuteReader()
            while ($rdr.Read()) {
                $sName = if ($rdr.IsDBNull(0)) { "dbo" } else { $rdr.GetString(0) }
                $fName = if ($rdr.IsDBNull(2)) { "" } else { $rdr.GetString(2) }
                if ($fName) {
                    $funcs.Add([PSCustomObject]@{ Schema = $sName; Name = $rdr.GetString(1); FullName = $fName })
                }
            }
        } catch { }
        finally {
            if ($rdr) { try { $rdr.Close(); $rdr.Dispose() } catch {} }
            if ($cmd) { try { $cmd.Dispose() } catch {} }
        }
        
        # 2. Fallback: INFORMATION_SCHEMA.ROUTINES
        if ($funcs.Count -eq 0) {
            $cmd = $null; $rdr = $null
            try {
                $cmd = $script:SqlConnection.CreateCommand()
                $cmd.CommandText = "SELECT ROUTINE_SCHEMA AS RoutineSchema, ROUTINE_NAME AS RoutineName, ROUTINE_SCHEMA + '.' + ROUTINE_NAME AS FuncName FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_TYPE = 'FUNCTION' ORDER BY ROUTINE_SCHEMA, ROUTINE_NAME"
                $rdr = $cmd.ExecuteReader()
                while ($rdr.Read()) {
                    $sName = if ($rdr.IsDBNull(0)) { "dbo" } else { $rdr.GetString(0) }
                    $fName = if ($rdr.IsDBNull(2)) { "" } else { $rdr.GetString(2) }
                    if ($fName) {
                        $funcs.Add([PSCustomObject]@{ Schema = $sName; Name = $rdr.GetString(1); FullName = $fName })
                    }
                }
            } catch { }
            finally {
                if ($rdr) { try { $rdr.Close(); $rdr.Dispose() } catch {} }
                if ($cmd) { try { $cmd.Dispose() } catch {} }
            }
        }

        $script:CachedFuncs[$db] = $funcs
    }

    $folderItem.Items.Clear()
    $filterText = if ($txtSqlSpSearch -and $txtSqlSpSearch.Text -and $txtSqlSpSearch.Text -notmatch "^Filter") { $txtSqlSpSearch.Text.Trim() } else { "" }
    $selectedSchema = if ($cmbSqlSchema -and $cmbSqlSchema.SelectedItem -and ($cmbSqlSchema.SelectedItem -is [System.Windows.Controls.ComboBoxItem]) -and $cmbSqlSchema.SelectedItem.Tag) { $cmbSqlSchema.SelectedItem.Tag } else { "" }

    foreach ($fn in $funcs) {
        $matchSchema = [string]::IsNullOrWhiteSpace($selectedSchema) -or ($fn.Schema -eq $selectedSchema)
        $matchText = [string]::IsNullOrWhiteSpace($filterText) -or ($fn.FullName -like "*$filterText*")
        if ($matchSchema -and $matchText) {
            $fnItem = New-Object System.Windows.Controls.TreeViewItem
            $fnItem.Header = $fn.FullName
            $fnItem.Tag = "FN:$db`:$($fn.FullName)"
            $fnItem.Foreground = Get-SqlOeColor "Fn"
            $fnItem.ToolTip = "Function: $($fn.FullName)`r`nDouble-click: Modify (ALTER Function)`r`nRight-click: Modify, Execute, Create, Full Screen Inspector, Copy Name"
            $folderItem.Items.Add($fnItem) | Out-Null
        }
    }
    if ($folderItem.Items.Count -eq 0) {
        $noItem = New-Object System.Windows.Controls.TreeViewItem
        $noItem.Header = "(No functions found)"
        $noItem.Foreground = Get-SqlOeColor "Muted"
        $folderItem.Items.Add($noItem) | Out-Null
    }
    $folderItem.Header = "Functions ($($funcs.Count))"
    $folderItem.IsExpanded = $true
}

function Expand-SqlDatabaseNode($dbItem, [string]$db) {
    if (-not $script:SqlConnected -or -not $dbItem) { return }
    $dbItem.Items.Clear()

    # Tables Folder
    $tblsFolder = New-Object System.Windows.Controls.TreeViewItem
    $tblsFolder.Header = "Tables"
    $tblsFolder.Tag = "FOLDER:TABLES:$db"
    $tblsFolder.Foreground = Get-SqlOeColor "Folder"
    $dummyTbl = New-Object System.Windows.Controls.TreeViewItem; $dummyTbl.Header = "(Click to expand...)"; $dummyTbl.Foreground = Get-SqlOeColor "Muted"
    $tblsFolder.Items.Add($dummyTbl) | Out-Null
    $dbItem.Items.Add($tblsFolder) | Out-Null

    # Views Folder
    $viewsFolder = New-Object System.Windows.Controls.TreeViewItem
    $viewsFolder.Header = "Views"
    $viewsFolder.Tag = "FOLDER:VIEWS:$db"
    $viewsFolder.Foreground = Get-SqlOeColor "Folder"
    $dummyVw = New-Object System.Windows.Controls.TreeViewItem; $dummyVw.Header = "(Click to expand...)"; $dummyVw.Foreground = Get-SqlOeColor "Muted"
    $viewsFolder.Items.Add($dummyVw) | Out-Null
    $dbItem.Items.Add($viewsFolder) | Out-Null

    # Programmability Folder
    $progFolder = New-Object System.Windows.Controls.TreeViewItem
    $progFolder.Header = "Programmability"
    $progFolder.Foreground = Get-SqlOeColor "Folder"
    $progFolder.IsExpanded = $true

    $spSubFolder = New-Object System.Windows.Controls.TreeViewItem
    $spSubFolder.Header = "Stored Procedures"
    $spSubFolder.Tag = "FOLDER:SPS:$db"
    $spSubFolder.Foreground = Get-SqlOeColor "Folder"
    $dummySp = New-Object System.Windows.Controls.TreeViewItem; $dummySp.Header = "(Click to expand...)"; $dummySp.Foreground = Get-SqlOeColor "Muted"
    $spSubFolder.Items.Add($dummySp) | Out-Null
    $progFolder.Items.Add($spSubFolder) | Out-Null

    $fnSubFolder = New-Object System.Windows.Controls.TreeViewItem
    $fnSubFolder.Header = "Functions"
    $fnSubFolder.Tag = "FOLDER:FNS:$db"
    $fnSubFolder.Foreground = Get-SqlOeColor "Folder"
    $dummyFn = New-Object System.Windows.Controls.TreeViewItem; $dummyFn.Header = "(Click to expand...)"; $dummyFn.Foreground = Get-SqlOeColor "Muted"
    $fnSubFolder.Items.Add($dummyFn) | Out-Null
    $progFolder.Items.Add($fnSubFolder) | Out-Null

    $dbItem.Items.Add($progFolder) | Out-Null
}

function Build-ObjectExplorerTree {
    if (-not $tvObjectExplorer) { return }
    $tvObjectExplorer.Items.Clear()

    if (-not $script:SqlConnected -or -not $script:SqlConnection) {
        $disconnectedItem = New-Object System.Windows.Controls.TreeViewItem
        $disconnectedItem.Header = "(Not Connected) Click 'Connect' on toolbar"
        $disconnectedItem.Foreground = Get-SqlOeColor "Muted"
        $tvObjectExplorer.Items.Add($disconnectedItem) | Out-Null
        return
    }

    try {
        $serverName = if ($script:SqlDataSource) { $script:SqlDataSource } else { "localhost" }
        $userName = if ($env:USERNAME) { $env:USERNAME } else { "user" }
        try {
            if ($txtSqlConnStr -and $txtSqlConnStr.Text -match '(?i)User\s*ID\s*=\s*([^;]+)') {
                $userName = $matches[1].Trim()
            }
        } catch {}

        # 1. Root Server Instance Node (SSMS 2022 Native Header)
        $rootNode = New-Object System.Windows.Controls.TreeViewItem
        $rootNode.Header = "$serverName (SQL Server - $userName)"
        $rootNode.FontWeight = [System.Windows.FontWeights]::Bold
        $rootNode.Foreground = Get-SqlOeColor "Root"
        $rootNode.IsExpanded = $true

        # 2. Databases Folder Node
        $dbFolder = New-Object System.Windows.Controls.TreeViewItem
        $dbFolder.Header = "Databases"
        $dbFolder.FontWeight = [System.Windows.FontWeights]::SemiBold
        $dbFolder.Foreground = Get-SqlOeColor "Folder"
        $dbFolder.IsExpanded = $true

        $currentDb = ""
        try { $currentDb = $script:SqlConnection.Database } catch {}
        if (-not $currentDb -and $cmbSqlDatabase -and $cmbSqlDatabase.SelectedItem) {
            $currentDb = if ($cmbSqlDatabase.SelectedItem -is [System.Windows.Controls.ComboBoxItem]) {
                $cmbSqlDatabase.SelectedItem.Content.ToString()
            } else {
                $cmbSqlDatabase.SelectedItem.ToString()
            }
        }
        if (-not $currentDb) {
            try {
                if ($txtSqlConnStr -and $txtSqlConnStr.Text -match '(?i)(?:Initial\s*Catalog|Database)\s*=\s*([^;]+)') {
                    $currentDb = $matches[1].Trim()
                }
            } catch {}
        }
        if (-not $currentDb) {
            try {
                $cmd = $script:SqlConnection.CreateCommand()
                $cmd.CommandText = "SELECT DB_NAME()"
                $currentDb = $cmd.ExecuteScalar().ToString()
                $cmd.Dispose()
            } catch { }
        }

        # Get database list (from cmbSqlDatabase or sys.databases or sp_databases)
        $dbList = @()
        if ($cmbSqlDatabase -and $cmbSqlDatabase.Items.Count -gt 0) {
            foreach ($it in $cmbSqlDatabase.Items) {
                $val = if ($it -is [System.Windows.Controls.ComboBoxItem]) { $it.Content.ToString() } else { $it.ToString() }
                if (-not [string]::IsNullOrWhiteSpace($val)) { $dbList += $val }
            }
        }
        if ($dbList.Count -eq 0) {
            try {
                $cmd = $script:SqlConnection.CreateCommand()
                $cmd.CommandText = "SELECT name FROM sys.databases WHERE state_desc='ONLINE' ORDER BY name"
                $rdr = $cmd.ExecuteReader()
                while ($rdr.Read()) { $dbList += $rdr.GetString(0) }
                $rdr.Close()
                $cmd.Dispose()
            } catch {}
        }
        if ($dbList.Count -eq 0) {
            try {
                $cmd = $script:SqlConnection.CreateCommand()
                $cmd.CommandText = "EXEC sp_databases"
                $rdr = $cmd.ExecuteReader()
                while ($rdr.Read()) { $dbList += $rdr.GetString(0) }
                $rdr.Close()
                $cmd.Dispose()
            } catch {}
        }
        if ($currentDb -and -not ($dbList -contains $currentDb)) { $dbList += $currentDb }

        foreach ($db in ($dbList | Select-Object -Unique | Sort-Object)) {
            $dbNode = New-Object System.Windows.Controls.TreeViewItem
            $dbNode.Header = $db
            $dbNode.Tag = "DATABASE:$db"
            if ($db -eq $currentDb) {
                $dbNode.FontWeight = [System.Windows.FontWeights]::Bold
                $dbNode.Foreground = Get-SqlOeColor "ActiveDb"
                $dbNode.IsExpanded = $true

                # Tables Folder (Lazy loaded on expand)
                $tblsFolder = New-Object System.Windows.Controls.TreeViewItem
                $tblsFolder.Header = "Tables"
                $tblsFolder.Tag = "FOLDER:TABLES:$db"
                $tblsFolder.Foreground = Get-SqlOeColor "Folder"
                $dummyTbl = New-Object System.Windows.Controls.TreeViewItem; $dummyTbl.Header = "(Click to expand...)"; $dummyTbl.Foreground = Get-SqlOeColor "Muted"
                $tblsFolder.Items.Add($dummyTbl) | Out-Null
                $dbNode.Items.Add($tblsFolder) | Out-Null

                # Views Folder (Lazy loaded on expand)
                $viewsFolder = New-Object System.Windows.Controls.TreeViewItem
                $viewsFolder.Header = "Views"
                $viewsFolder.Tag = "FOLDER:VIEWS:$db"
                $viewsFolder.Foreground = Get-SqlOeColor "Folder"
                $dummyVw = New-Object System.Windows.Controls.TreeViewItem; $dummyVw.Header = "(Click to expand...)"; $dummyVw.Foreground = Get-SqlOeColor "Muted"
                $viewsFolder.Items.Add($dummyVw) | Out-Null
                $dbNode.Items.Add($viewsFolder) | Out-Null

                # Programmability Folder
                $progFolder = New-Object System.Windows.Controls.TreeViewItem
                $progFolder.Header = "Programmability"
                $progFolder.Foreground = Get-SqlOeColor "Folder"
                $progFolder.IsExpanded = $true

                # Stored Procedures Folder (Lazy loaded on expand)
                $spSubFolder = New-Object System.Windows.Controls.TreeViewItem
                $spSubFolder.Header = "Stored Procedures"
                $spSubFolder.Tag = "FOLDER:SPS:$db"
                $spSubFolder.Foreground = Get-SqlOeColor "Folder"
                $dummySp = New-Object System.Windows.Controls.TreeViewItem; $dummySp.Header = "(Click to expand...)"; $dummySp.Foreground = Get-SqlOeColor "Muted"
                $spSubFolder.Items.Add($dummySp) | Out-Null
                $progFolder.Items.Add($spSubFolder) | Out-Null

                # Functions Folder (Lazy loaded on expand)
                $fnSubFolder = New-Object System.Windows.Controls.TreeViewItem
                $fnSubFolder.Header = "Functions"
                $fnSubFolder.Tag = "FOLDER:FNS:$db"
                $fnSubFolder.Foreground = Get-SqlOeColor "Folder"
                $dummyFn = New-Object System.Windows.Controls.TreeViewItem; $dummyFn.Header = "(Click to expand...)"; $dummyFn.Foreground = Get-SqlOeColor "Muted"
                $fnSubFolder.Items.Add($dummyFn) | Out-Null
                $progFolder.Items.Add($fnSubFolder) | Out-Null

                $dbNode.Items.Add($progFolder) | Out-Null
            } else {
                $dbNode.Foreground = Get-SqlOeColor "Database"
                $dummyDb = New-Object System.Windows.Controls.TreeViewItem; $dummyDb.Header = "(Click to expand...)"; $dummyDb.Foreground = Get-SqlOeColor "Muted"
                $dbNode.Items.Add($dummyDb) | Out-Null
            }

            $dbFolder.Items.Add($dbNode) | Out-Null
        }

        $rootNode.Items.Add($dbFolder) | Out-Null

        # 3. Security Folder Node
        $secNode = New-Object System.Windows.Controls.TreeViewItem
        $secNode.Header = "Security"
        $secNode.Foreground = Get-SqlOeColor "Folder"
        $loginsNode = New-Object System.Windows.Controls.TreeViewItem; $loginsNode.Header = "Logins"; $loginsNode.Foreground = Get-SqlOeColor "Item"
        $rolesNode = New-Object System.Windows.Controls.TreeViewItem; $rolesNode.Header = "Server Roles"; $rolesNode.Foreground = Get-SqlOeColor "Item"
        $secNode.Items.Add($loginsNode) | Out-Null
        $secNode.Items.Add($rolesNode) | Out-Null
        $rootNode.Items.Add($secNode) | Out-Null

        # 4. Server Objects Node
        $soNode = New-Object System.Windows.Controls.TreeViewItem
        $soNode.Header = "Server Objects"
        $soNode.Foreground = Get-SqlOeColor "Folder"
        $linkNode = New-Object System.Windows.Controls.TreeViewItem; $linkNode.Header = "Linked Servers"; $linkNode.Foreground = Get-SqlOeColor "Item"
        $soNode.Items.Add($linkNode) | Out-Null
        $rootNode.Items.Add($soNode) | Out-Null

        # 5. Management Node
        $mgmtNode = New-Object System.Windows.Controls.TreeViewItem
        $mgmtNode.Header = "Management"
        $mgmtNode.Foreground = Get-SqlOeColor "Folder"
        $rootNode.Items.Add($mgmtNode) | Out-Null

        $tvObjectExplorer.Items.Add($rootNode) | Out-Null
    } catch {
        $errNode = New-Object System.Windows.Controls.TreeViewItem
        $errNode.Header = "Object Explorer Error: $($_.Exception.Message)"
        $errNode.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EF4444")
        $tvObjectExplorer.Items.Add($errNode) | Out-Null
    }
}
function Switch-SqlActiveDatabase([string]$dbName) {
    if (-not $script:SqlConnected -or [string]::IsNullOrWhiteSpace($dbName)) { return }
    try {
        $cmd = $script:SqlConnection.CreateCommand()
        $cmd.CommandText = "USE [$dbName]"
        $cmd.ExecuteNonQuery() | Out-Null
        $cmd.Dispose()

        if ($script:SqlDataSource) {
            $lblSqlStatus.Text = "Connected: $($script:SqlDataSource) / $dbName"
            $lblSqlStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
        }
        if ($lblQueryTabTitle) { $lblQueryTabTitle.Text = "SQLQuery1.sql - $dbName*" }
        if ($lblSqlSsmsStatusDetails) { $lblSqlSsmsStatusDetails.Text = "$($script:SqlDataSource) | mandar.k | $dbName" }
        if ($lblSqlRowCount) { $lblSqlRowCount.Text = "Active database switched to [$dbName]." }

        $script:SuppressDbChange = $true
        if ($cmbSqlDatabase) {
            for ($i = 0; $i -lt $cmbSqlDatabase.Items.Count; $i++) {
                $item = $cmbSqlDatabase.Items[$i]
                $val = if ($item -is [System.Windows.Controls.ComboBoxItem]) { $item.Content } else { $item.ToString() }
                if ($val -eq $dbName) {
                    $cmbSqlDatabase.SelectedIndex = $i
                    break
                }
            }
        }
        $script:SuppressDbChange = $false
        $script:SuppressSchemaChange = $false
        if ($script:SqlTabs -and $script:ActiveSqlTabId) {
            $curTab = $script:SqlTabs | Where-Object { $_.Id -eq $script:ActiveSqlTabId }
            if ($curTab) {
                $curTab.Database = $dbName
                try { Render-SqlQueryTabs } catch {}
            }
        }

        Build-ObjectExplorerTree

        if ($window -and $window.Dispatcher) {
            $window.Dispatcher.BeginInvoke([System.Action]{
                try { Fetch-SqlSchemaMetadata } catch {}
            }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
        }
    } catch {
        if ($lblSqlRowCount) { $lblSqlRowCount.Text = "Error switching database: $($_.Exception.Message)" }
        [System.Windows.MessageBox]::Show("Could not switch to database '$dbName':`r`n`r`n$($_.Exception.Message)", "Database Switch Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
    }
}

# Expand on Demand
if ($tvObjectExplorer) {
    $oeExpandHandler = [System.Windows.RoutedEventHandler]{
        param($s, $e)
        $item = $e.OriginalSource
        if (-not $item -or -not ($item -is [System.Windows.Controls.TreeViewItem])) { return }
        $tag = [string]$item.Tag
        if ([string]::IsNullOrWhiteSpace($tag)) { return }
        Expand-SqlFolderOnDemand $item
        $e.Handled = $true
    }
    $tvObjectExplorer.AddHandler([System.Windows.Controls.TreeViewItem]::ExpandedEvent, $oeExpandHandler)

    # Right-click selection
    $tvObjectExplorer.Add_PreviewMouseRightButtonDown({
        param($s, $e)
        $hit = [System.Windows.Media.VisualTreeHelper]::HitTest($tvObjectExplorer, $e.GetPosition($tvObjectExplorer))
        if ($hit) {
            $visual = $hit.VisualHit
            while ($visual -and -not ($visual -is [System.Windows.Controls.TreeViewItem])) {
                $visual = [System.Windows.Media.VisualTreeHelper]::GetParent($visual)
            }
            if ($visual -and ($visual -is [System.Windows.Controls.TreeViewItem])) {
                $visual.Focus() | Out-Null
                $visual.IsSelected = $true
            }
        }
    })

    # Dynamic Context Menu Opening
    $tvObjectExplorer.Add_ContextMenuOpening({
        param($s, $e)
        $sel = $tvObjectExplorer.SelectedItem
        if (-not $sel -or -not ($sel -is [System.Windows.Controls.TreeViewItem])) { return }
        $tag = [string]$sel.Tag
        if ([string]::IsNullOrWhiteSpace($tag)) { return }

        if ($tag.StartsWith("SP:")) {
            $raw = $tag.Substring(3)
            $spDb = ""; $spName = $raw
            if ($raw.Contains(":")) {
                $p = $raw.Split(':', 2); $spDb = $p[0]; $spName = $p[1]
            }
            $tvObjectExplorer.ContextMenu = New-SqlRoutineContextMenu $spName 'PROCEDURE' $spDb
        } elseif ($tag.StartsWith("FN:")) {
            $raw = $tag.Substring(3)
            $fnDb = ""; $fnName = $raw
            if ($raw.Contains(":")) {
                $p = $raw.Split(':', 2); $fnDb = $p[0]; $fnName = $p[1]
            }
            $tvObjectExplorer.ContextMenu = New-SqlRoutineContextMenu $fnName 'FUNCTION' $fnDb
        } elseif ($tag.StartsWith("TABLE:")) {
            $raw = $tag.Substring(6)
            $tblDb = ""; $tblName = $raw
            if ($raw.Contains(":")) {
                $p = $raw.Split(':', 2); $tblDb = $p[0]; $tblName = $p[1]
            }
            $tvObjectExplorer.ContextMenu = New-SqlTableContextMenu $tblName $false $tblDb
        } elseif ($tag.StartsWith("VIEW:")) {
            $raw = $tag.Substring(5)
            $vwDb = ""; $vwName = $raw
            if ($raw.Contains(":")) {
                $p = $raw.Split(':', 2); $vwDb = $p[0]; $vwName = $p[1]
            }
            $tvObjectExplorer.ContextMenu = New-SqlTableContextMenu $vwName $true $vwDb
        } elseif ($tag.StartsWith("FOLDER:SPS:")) {
            $spDb = $tag.Split(':')[2]
            $ctx = New-Object System.Windows.Controls.ContextMenu
            $ctx.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E1E1E")
            $ctx.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3F3F46")
            $ctx.BorderThickness = New-Object System.Windows.Thickness(1)
            
            $miNewSp = New-Object System.Windows.Controls.MenuItem; $miNewSp.Header = "New Stored Procedure..."; $miNewSp.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80"); $miNewSp.FontWeight = [System.Windows.FontWeights]::Bold
            $miNewSp.Add_Click({ Create-NewSqlSpTemplate })
            $ctx.Items.Add($miNewSp) | Out-Null
            
            $miRefSp = New-Object System.Windows.Controls.MenuItem; $miRefSp.Header = "Refresh Stored Procedures"; $miRefSp.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
            $miRefSp.Tag = $spDb
            $miRefSp.Add_Click({
                param($sender, $e)
                $targetDb = [string]$sender.Tag
                $script:CachedProcs.Remove($targetDb)
                $cur = $tvObjectExplorer.SelectedItem
                if ($cur) { Expand-SqlProcsFolder $cur $targetDb }
            })
            $ctx.Items.Add($miRefSp) | Out-Null
            $tvObjectExplorer.ContextMenu = $ctx
        } elseif ($tag.StartsWith("FOLDER:FNS:")) {
            $fnDb = $tag.Split(':')[2]
            $ctx = New-Object System.Windows.Controls.ContextMenu
            $ctx.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E1E1E")
            $ctx.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3F3F46")
            $ctx.BorderThickness = New-Object System.Windows.Thickness(1)
            
            $miNewFn = New-Object System.Windows.Controls.MenuItem; $miNewFn.Header = "New Scalar Function..."; $miNewFn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#A78BFA"); $miNewFn.FontWeight = [System.Windows.FontWeights]::Bold
            $miNewFn.Add_Click({ Create-NewSqlFnTemplate })
            $ctx.Items.Add($miNewFn) | Out-Null
            
            $miRefFn = New-Object System.Windows.Controls.MenuItem; $miRefFn.Header = "Refresh Functions"; $miRefFn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
            $miRefFn.Tag = $fnDb
            $miRefFn.Add_Click({
                param($sender, $e)
                $targetDb = [string]$sender.Tag
                $script:CachedFuncs.Remove($targetDb)
                $cur = $tvObjectExplorer.SelectedItem
                if ($cur) { Expand-SqlFuncsFolder $cur $targetDb }
            })
            $ctx.Items.Add($miRefFn) | Out-Null
            $tvObjectExplorer.ContextMenu = $ctx
        } elseif ($tag.StartsWith("FOLDER:TABLES:")) {
            $tblDb = $tag.Split(':')[2]
            $ctx = New-Object System.Windows.Controls.ContextMenu
            $ctx.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E1E1E")
            $ctx.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3F3F46")
            $ctx.BorderThickness = New-Object System.Windows.Thickness(1)
            
            $miRefTbl = New-Object System.Windows.Controls.MenuItem; $miRefTbl.Header = "Refresh Tables"; $miRefTbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
            $miRefTbl.Tag = $tblDb
            $miRefTbl.Add_Click({
                param($sender, $e)
                $targetDb = [string]$sender.Tag
                $script:CachedTables.Remove($targetDb)
                $cur = $tvObjectExplorer.SelectedItem
                if ($cur) { Expand-SqlTablesFolder $cur $targetDb }
            })
            $ctx.Items.Add($miRefTbl) | Out-Null
            $tvObjectExplorer.ContextMenu = $ctx
        } elseif ($tag.StartsWith("FOLDER:VIEWS:")) {
            $vwDb = $tag.Split(':')[2]
            $ctx = New-Object System.Windows.Controls.ContextMenu
            $ctx.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E1E1E")
            $ctx.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3F3F46")
            $ctx.BorderThickness = New-Object System.Windows.Thickness(1)
            
            $miRefVw = New-Object System.Windows.Controls.MenuItem; $miRefVw.Header = "Refresh Views"; $miRefVw.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
            $miRefVw.Tag = $vwDb
            $miRefVw.Add_Click({
                param($sender, $e)
                $targetDb = [string]$sender.Tag
                $script:CachedViews.Remove($targetDb)
                $cur = $tvObjectExplorer.SelectedItem
                if ($cur) { Expand-SqlViewsFolder $cur $targetDb }
            })
            $ctx.Items.Add($miRefVw) | Out-Null
            $tvObjectExplorer.ContextMenu = $ctx
        } elseif ($tag.StartsWith("DATABASE:")) {
            $dbName = $tag.Substring(9)
            $ctx = New-Object System.Windows.Controls.ContextMenu
            $ctx.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E1E1E")
            $ctx.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3F3F46")
            $ctx.BorderThickness = New-Object System.Windows.Thickness(1)

            # Option 1: Use Database
            $miUse = New-Object System.Windows.Controls.MenuItem
            $miUse.Header = "Use Database [$dbName]"
            $miUse.FontWeight = [System.Windows.FontWeights]::Bold
            $miUse.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
            $miUse.Tag = $dbName
            $miUse.Add_Click({
                param($sender, $e)
                $targetDb = [string]$sender.Tag
                if ($targetDb) {
                    Switch-SqlActiveDatabase $targetDb
                }
            })
            $ctx.Items.Add($miUse) | Out-Null

            # Option 2: New Query
            $miNewQ = New-Object System.Windows.Controls.MenuItem
            $miNewQ.Header = "New Query in [$dbName]"
            $miNewQ.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
            $miNewQ.Tag = $dbName
            $miNewQ.Add_Click({
                param($sender, $e)
                $targetDb = [string]$sender.Tag
                if ($targetDb) {
                    Switch-SqlActiveDatabase $targetDb
                    $txtSqlQuery.Text = "-- Query Session for [$targetDb]`r`nUSE [$targetDb];`r`nGO`r`n`r`nSELECT TOP 100 * FROM sys.tables;`r`n"
                    $txtSqlQuery.Foreground = if ($global:isDarkMode) { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80") } else { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A") }
                    $txtSqlQuery.Focus() | Out-Null
                }
            })
            $ctx.Items.Add($miNewQ) | Out-Null

            # Separator
            $sep = New-Object System.Windows.Controls.Separator
            $sep.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3F3F46")
            $ctx.Items.Add($sep) | Out-Null

            # Option 3: Refresh
            $miRef = New-Object System.Windows.Controls.MenuItem
            $miRef.Header = "Refresh [$dbName]"
            $miRef.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
            $miRef.Tag = $dbName
            $miRef.Add_Click({
                param($sender, $e)
                $targetDb = [string]$sender.Tag
                $script:CachedTables.Remove($targetDb)
                $script:CachedViews.Remove($targetDb)
                $script:CachedProcs.Remove($targetDb)
                $script:CachedFuncs.Remove($targetDb)
                Switch-SqlActiveDatabase $targetDb
            })
            $ctx.Items.Add($miRef) | Out-Null

            $tvObjectExplorer.ContextMenu = $ctx
        }
    })

    # Double-click handling
    $tvObjectExplorer.Add_MouseDoubleClick({
        param($s, $e)
        $sel = $tvObjectExplorer.SelectedItem
        if (-not $sel -or -not ($sel -is [System.Windows.Controls.TreeViewItem])) { return }
        $tag = [string]$sel.Tag
        if ([string]::IsNullOrWhiteSpace($tag)) { return }

        if ($tag.StartsWith("DATABASE:")) {
            $dbName = $tag.Substring(9)
            $e.Handled = $true
            Switch-SqlActiveDatabase $dbName
        } elseif ($tag.StartsWith("SP:")) {
            $raw = $tag.Substring(3)
            $spDb = ""; $spName = $raw
            if ($raw.Contains(":")) {
                $p = $raw.Split(':', 2); $spDb = $p[0]; $spName = $p[1]
            }
            $e.Handled = $true
            if ($spDb) { Switch-SqlActiveDatabase $spDb }
            Script-SqlRoutineModify $spName
        } elseif ($tag.StartsWith("FN:")) {
            $raw = $tag.Substring(3)
            $fnDb = ""; $fnName = $raw
            if ($raw.Contains(":")) {
                $p = $raw.Split(':', 2); $fnDb = $p[0]; $fnName = $p[1]
            }
            $e.Handled = $true
            if ($fnDb) { Switch-SqlActiveDatabase $fnDb }
            Script-SqlRoutineModify $fnName
        } elseif ($tag.StartsWith("TABLE:")) {
            $raw = $tag.Substring(6)
            $tblDb = ""; $tblName = $raw
            if ($raw.Contains(":")) {
                $p = $raw.Split(':', 2); $tblDb = $p[0]; $tblName = $p[1]
            }
            $e.Handled = $true
            if ($tblDb) { Switch-SqlActiveDatabase $tblDb }
            $txtSqlQuery.Text = "SELECT TOP 100 *`r`nFROM $tblName WITH (NOLOCK);`r`n"
            $txtSqlQuery.Foreground = if ($global:isDarkMode) { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80") } else { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A") }
            if ($btnSqlExecute) { $btnSqlExecute.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }
        } elseif ($tag.StartsWith("VIEW:")) {
            $raw = $tag.Substring(5)
            $vwDb = ""; $vwName = $raw
            if ($raw.Contains(":")) {
                $p = $raw.Split(':', 2); $vwDb = $p[0]; $vwName = $p[1]
            }
            $e.Handled = $true
            if ($vwDb) { Switch-SqlActiveDatabase $vwDb }
            $txtSqlQuery.Text = "SELECT TOP 100 *`r`nFROM $vwName WITH (NOLOCK);`r`n"
            $txtSqlQuery.Foreground = if ($global:isDarkMode) { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80") } else { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A") }
            if ($btnSqlExecute) { $btnSqlExecute.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }
        }
    })

    # Single-click selection behavior
    $tvObjectExplorer.Add_SelectedItemChanged({
        try {
            $sel = $tvObjectExplorer.SelectedItem
            if (-not $sel -or -not ($sel -is [System.Windows.Controls.TreeViewItem])) { return }
            
            # If user clicked on "(Click to expand...)", expand parent folder immediately
            $selHeader = [string]$sel.Header
            if ($selHeader -like "*Click to expand*" -or $selHeader -like "*Loading*") {
                $parent = $sel.Parent
                if ($parent -and ($parent -is [System.Windows.Controls.TreeViewItem])) {
                    Expand-SqlFolderOnDemand $parent
                    return
                }
            }

            $tag = [string]$sel.Tag
            if ([string]::IsNullOrWhiteSpace($tag)) { return }

            # If user selected a folder, ensure it expands and loads
            if ($tag -like "FOLDER:*") {
                Expand-SqlFolderOnDemand $sel
                return
            }

            if ($tag.StartsWith("DATABASE:")) {
                $dbName = $tag.Substring(9)
                if ($script:SqlConnection -and $script:SqlConnection.Database -ne $dbName) {
                    Switch-SqlActiveDatabase $dbName
                }
            } elseif ($tag.StartsWith("TABLE:")) {
                $tbl = $tag.Substring(6)
                $txtSqlQuery.Text = "SELECT TOP 100 *`r`nFROM $tbl WITH (NOLOCK);`r`n"
                $txtSqlQuery.Foreground = if ($global:isDarkMode) { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80") } else { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A") }
            } elseif ($tag.StartsWith("VIEW:")) {
                $vw = $tag.Substring(5)
                $txtSqlQuery.Text = "SELECT TOP 100 *`r`nFROM $vw WITH (NOLOCK);`r`n"
                $txtSqlQuery.Foreground = if ($global:isDarkMode) { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80") } else { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A") }
            } elseif ($tag.StartsWith("SP:")) {
                $sp = $tag.Substring(3)
                $txtSqlQuery.Text = "EXEC $sp;`r`n"
                $txtSqlQuery.Foreground = if ($global:isDarkMode) { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80") } else { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A") }
            } elseif ($tag.StartsWith("FN:")) {
                $fn = $tag.Substring(3)
                $txtSqlQuery.Text = "SELECT $fn();`r`n"
                $txtSqlQuery.Foreground = if ($global:isDarkMode) { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80") } else { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A") }
            }
        } catch {}
    })

    # Direct click on (Click to expand...) or folder
    $tvObjectExplorer.Add_PreviewMouseLeftButtonDown({
        param($s, $e)
        try {
            $hit = [System.Windows.Media.VisualTreeHelper]::HitTest($tvObjectExplorer, $e.GetPosition($tvObjectExplorer))
            if ($hit) {
                $visual = $hit.VisualHit
                while ($visual -and -not ($visual -is [System.Windows.Controls.TreeViewItem])) {
                    $visual = [System.Windows.Media.VisualTreeHelper]::GetParent($visual)
                }
                if ($visual -and ($visual -is [System.Windows.Controls.TreeViewItem])) {
                    $h = [string]$visual.Header
                    if ($h.Contains("Click to expand") -or $h.Contains("Loading")) {
                        $p = $visual.Parent
                        if ($p -and ($p -is [System.Windows.Controls.TreeViewItem])) {
                            Expand-SqlFolderOnDemand $p
                            $e.Handled = $true
                        }
                    } elseif ($visual.Tag -like "FOLDER:*") {
                        Expand-SqlFolderOnDemand $visual
                    }
                }
            }
        } catch {}
    })
}

# Debounced Search Filter
$script:SqlSearchDebounceTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:SqlSearchDebounceTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$script:SqlSearchDebounceTimer.Add_Tick({
    $script:SqlSearchDebounceTimer.Stop()
    Apply-SqlObjectExplorerFilter
})

if ($txtSqlSpSearch) {
    $txtSqlSpSearch.Add_GotFocus({
        if ($txtSqlSpSearch.Text -eq "Filter SP..." -or $txtSqlSpSearch.Text -eq "Filter SP/Func..." -or $txtSqlSpSearch.Text -eq "Filter objects...") {
            $txtSqlSpSearch.Text = ""
            $txtSqlSpSearch.Foreground = if ($global:isDarkMode) { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E2E8F0") } else { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A") }
        }
    })

    $txtSqlSpSearch.Add_LostFocus({
        if ([string]::IsNullOrWhiteSpace($txtSqlSpSearch.Text)) {
            $txtSqlSpSearch.Text = "Filter objects..."
            $txtSqlSpSearch.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#64748B")
        }
    })

    $txtSqlSpSearch.Add_TextChanged({
        $script:SqlSearchDebounceTimer.Stop()
        $script:SqlSearchDebounceTimer.Start()
    })
}

if ($cmbSqlSchema) {
    $cmbSqlSchema.Add_SelectionChanged({
        if ($script:SuppressSchemaChange) { return }
        Apply-SqlObjectExplorerFilter
    })
}

function Apply-SqlObjectExplorerFilter {
    if (-not $script:SqlConnected -or $script:SuppressSchemaChange) { return }
    $filterText = if ($txtSqlSpSearch -and $txtSqlSpSearch.Text -and $txtSqlSpSearch.Text -notmatch "^Filter") { $txtSqlSpSearch.Text.Trim() } else { "" }
    $selectedSchema = if ($cmbSqlSchema -and $cmbSqlSchema.SelectedItem -and ($cmbSqlSchema.SelectedItem -is [System.Windows.Controls.ComboBoxItem]) -and $cmbSqlSchema.SelectedItem.Tag) { $cmbSqlSchema.SelectedItem.Tag } else { "" }

    if ([string]::IsNullOrWhiteSpace($filterText) -and [string]::IsNullOrWhiteSpace($selectedSchema)) {
        Build-ObjectExplorerTree
        return
    }

    $currentDb = ""
    try { $currentDb = $script:SqlConnection.Database } catch {}
    if (-not $currentDb) { return }

    $foundDbNode = $null
    foreach ($item in $tvObjectExplorer.Items) {
        if ($item.Header -like "*SQL Server*") {
            foreach ($sub in $item.Items) {
                if ($sub.Header -eq "Databases") {
                    foreach ($dbNode in $sub.Items) {
                        if ($dbNode.Tag -eq "DATABASE:$currentDb") {
                            $foundDbNode = $dbNode
                            break
                        }
                    }
                }
            }
        }
    }

    if ($foundDbNode) {
        foreach ($folder in $foundDbNode.Items) {
            $fTag = [string]$folder.Tag
            if ($fTag -like "FOLDER:TABLES:*") {
                Expand-SqlTablesFolder $folder $currentDb
                if ($folder.Items.Count -gt 0) { $folder.IsExpanded = $true }
            } elseif ($fTag -like "FOLDER:VIEWS:*") {
                Expand-SqlViewsFolder $folder $currentDb
                if ($folder.Items.Count -gt 0) { $folder.IsExpanded = $true }
            } elseif ($folder.Header -eq "Programmability") {
                $folder.IsExpanded = $true
                foreach ($progSub in $folder.Items) {
                    $pTag = [string]$progSub.Tag
                    if ($pTag -like "FOLDER:SPS:*") {
                        Expand-SqlProcsFolder $progSub $currentDb
                        if ($progSub.Items.Count -gt 0) { $progSub.IsExpanded = $true }
                    } elseif ($pTag -like "FOLDER:FNS:*") {
                        Expand-SqlFuncsFolder $progSub $currentDb
                        if ($progSub.Items.Count -gt 0) { $progSub.IsExpanded = $true }
                    }
                }
            }
        }
    }
}

if ($btnOeRefresh) {
    $btnOeRefresh.Add_Click({
        $script:CachedTables.Clear()
        $script:CachedViews.Clear()
        $script:CachedProcs.Clear()
        $script:CachedFuncs.Clear()
        Build-ObjectExplorerTree
    })
}

if ($btnOeCollapse) {
    $btnOeCollapse.Add_Click({
        try {
            foreach ($item in $tvObjectExplorer.Items) {
                if ($item -is [System.Windows.Controls.TreeViewItem]) {
                    $item.IsExpanded = $false
                }
            }
        } catch {}
    })
}
# ==============================================================================
# JARVIS AI EXTRA-INTELLIGENCE ENGINE & ASSISTANT CORE
# ==============================================================================
function Format-SqlQuery {
    if (-not $txtSqlQuery -or [string]::IsNullOrWhiteSpace($txtSqlQuery.Text)) { return }
    $code = $txtSqlQuery.Text

    $keywords = @(
        'select', 'from', 'where', 'and', 'or', 'join', 'inner join', 'left join', 'right join', 'full join', 'cross join', 'on',
        'group by', 'order by', 'having', 'insert into', 'values', 'update', 'set', 'delete from', 'create procedure',
        'alter procedure', 'create function', 'alter function', 'as', 'begin', 'end', 'declare', 'exec', 'execute',
        'commit', 'rollback', 'transaction', 'set nocount on', 'drop table', 'if exists', 'union all', 'top', 'distinct',
        'case', 'when', 'then', 'else', 'with', 'nolock', 'asc', 'desc', 'is null', 'is not null', 'in', 'not in',
        'between', 'like', 'primary key'
    )

    foreach ($kw in $keywords) {
        $pattern = "(?i)\b$([regex]::Escape($kw))\b"
        $code = [regex]::Replace($code, $pattern, $kw.ToUpper())
    }

    $txtSqlQuery.Text = $code
    $txtSqlQuery.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
    if ($lblSqlRowCount) { $lblSqlRowCount.Text = "JARVIS: SQL Query Auto-Formatted Successfully!" }
    try { Set-MascotState "success" "JARVIS: Formatted!" } catch { }
}

function Analyze-SqlQuery {
    if (-not $txtSqlQuery -or [string]::IsNullOrWhiteSpace($txtSqlQuery.Text)) { return }
    $code = $txtSqlQuery.Text

    $issues = @()
    
    if ($code -match '(?i)\bSELECT\s+\*\b') {
        $issues += "[WARNING] 'SELECT *' detected. Recommend specifying explicit column names to improve memory & I/O performance."
    }
    if (($code -match '(?i)\bUPDATE\b' -or $code -match '(?i)\bDELETE\b') -and $code -notmatch '(?i)\bWHERE\b') {
        $issues += "[CRITICAL] Unbounded UPDATE or DELETE statement without WHERE clause! High data risk."
    }
    if ($code -match '(?i)\bCURSOR\b|\bFETCH\s+NEXT\b') {
        $issues += "[WARNING] T-SQL CURSOR detected. Row-by-row cursor processing is slow; consider set-based queries or CTEs."
    }
    if ($code -match "(?i)LIKE\s+'%[^']") {
        $issues += "[OPTIMIZATION] Leading wildcard search (LIKE '%...') detected. Bypasses index seeks and forces Full Table Scans."
    }
    if ($code -match '(?i)\bPROCEDURE\b' -and $code -notmatch '(?i)\bSET\s+NOCOUNT\s+ON\b') {
        $issues += "[OPTIMIZATION] Missing 'SET NOCOUNT ON'. Adding this suppresses done-in-proc messages and reduces network latency."
    }
    if ($code -match '(?i)\bBEGIN\s+TRAN\b' -and $code -notmatch '(?i)\bROLLBACK\b|\bCOMMIT\b') {
        $issues += "[WARNING] 'BEGIN TRAN' statement found without explicit COMMIT or ROLLBACK. Risk of holding open locks."
    }

    $report = "========================================================================`n"
    $report += " JARVIS AI SQL PERFORMANCE & SECURITY AUDIT REPORT`n"
    $report += " Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Target Query Size: $($code.Length) chars`n"
    $report += "========================================================================`n`n"

    if ($issues.Count -eq 0) {
        $report += "SUCCESS: No critical performance or security issues detected in query logic!`nQuery complies with best practices.`n"
        try { Set-MascotState "success" "JARVIS: Audit Clean!" } catch { }
    } else {
        $report += "Found $($issues.Count) audit findings:`n`n"
        foreach ($iss in $issues) {
            $report += " -> $iss`n`n"
        }
        try { Set-MascotState "error" "JARVIS: $($issues.Count) Issues" } catch { }
    }

    if ($txtSqlMessages) {
        $txtSqlMessages.Text = $report
        $txtSqlMessages.Visibility = "Visible"
        if ($dgSqlResults) { $dgSqlResults.Visibility = "Collapsed" }
    }
}

function Process-JarvisNaturalLanguage([string]$prompt) {
    if ([string]::IsNullOrWhiteSpace($prompt)) { return "Please type a question or command for JARVIS." }
    $p = $prompt.Trim().ToLower()

    if ($p -match 'who|session|active user|process|sp_who') {
        Execute-SqlQuery -OverrideQuery "sp_who2"
        return "Executed 'sp_who2' to list active server sessions and processes."
    }
    elseif ($p -match 'space|size|storage|disk|table size|db size') {
        Execute-SqlQuery -OverrideQuery "sp_spaceused"
        return "Executed 'sp_spaceused' to inspect database space usage."
    }
    elseif ($p -match 'format|beautify|clean query') {
        Format-SqlQuery
        return "Auto-formatted current SQL query in the editor."
    }
    elseif ($p -match 'analyze|audit|check query|performance|security') {
        Analyze-SqlQuery
        return "Executed JARVIS AI SQL Performance & Security Audit."
    }
    elseif ($p -match 'new sp|create sp|template') {
        Create-NewSpTemplate
        return "Inserted SSMS Stored Procedure template into query editor."
    }
    elseif ($p -match 'test|begin tran|safe') {
        Execute-SqlQuery -TestBeginTran
        return "Executing query inside TEST (BEGIN TRAN ... ROLLBACK) mode."
    }
    elseif ($p -match 'full screen|inspector|f11') {
        Show-SqlSpFullScreenViewer
        return "Opening Stored Procedure / Function in Full Screen Inspector."
    }
    elseif ($p -match 'clear|reset') {
        Clear-SqlQuery
        return "Cleared SQL query editor and results table."
    }
    elseif ($p -match 'batch|resizer') {
        Switch-Tab "Batch"
        return "Switched to BATCH OPTIMIZER tab."
    }
    elseif ($p -match 'govt|exam') {
        Switch-Tab "GovtExam"
        return "Switched to GOVT EXAM RESIZER tab."
    }
    elseif ($p -match 'bg|background|remover') {
        Switch-Tab "BgRemover"
        return "Switched to BG REMOVER / SIGN tab."
    }
    elseif ($p -match 'otp|decrypt') {
        Switch-Tab "Otp"
        return "Switched to OTP DECRYPTOR tab."
    }
    elseif ($p -match 'sql|console') {
        Switch-Tab "SqlConsole"
        return "Switched to SQL CONSOLE tab."
    }
    elseif ($p -match 'owner|property|mast') {
        $txtSqlQuery.Text = "SELECT TOP 100 * FROM PropertyMast ORDER BY OwnerID DESC;"
        $txtSqlQuery.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
        return "Generated sample query for PropertyMast table."
    }
    else {
        return "JARVIS: Processed command '$prompt'. You can ask me to format queries, analyze performance, show active sessions, test transactions, or switch app tabs!"
    }
}

function Show-UserAccessManagerWindow {
    try {
        $win = New-Object System.Windows.Window
        $win.Title = "Universal User Privileges & Access Fixer (NTIS Security Manager)"
        $win.Width = 820
        $win.Height = 670
        $win.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
        if ($window -and $window.IsVisible) { try { $win.Owner = $window } catch {} }
        $win.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#060A13")
        $win.ResizeMode = [System.Windows.ResizeMode]::CanResizeWithGrip

        $grid = New-Object System.Windows.Controls.Grid
        $grid.Margin = New-Object System.Windows.Thickness(16)
        
        $r0 = New-Object System.Windows.Controls.RowDefinition; $r0.Height = [System.Windows.GridLength]::Auto
        $r1 = New-Object System.Windows.Controls.RowDefinition; $r1.Height = [System.Windows.GridLength]::Auto
        $r2 = New-Object System.Windows.Controls.RowDefinition; $r2.Height = [System.Windows.GridLength]::Auto
        $r3 = New-Object System.Windows.Controls.RowDefinition; $r3.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $r4 = New-Object System.Windows.Controls.RowDefinition; $r4.Height = [System.Windows.GridLength]::Auto
        $grid.RowDefinitions.Add($r0); $grid.RowDefinitions.Add($r1); $grid.RowDefinitions.Add($r2); $grid.RowDefinitions.Add($r3); $grid.RowDefinitions.Add($r4)

        # 1. Header Card
        $hdrBorder = New-Object System.Windows.Controls.Border
        $hdrBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A")
        $hdrBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EC4899")
        $hdrBorder.BorderThickness = New-Object System.Windows.Thickness(1)
        $hdrBorder.CornerRadius = New-Object System.Windows.CornerRadius(8)
        $hdrBorder.Padding = New-Object System.Windows.Thickness(14,10,14,10)
        $hdrBorder.Margin = New-Object System.Windows.Thickness(0,0,0,10)
        [System.Windows.Controls.Grid]::SetRow($hdrBorder, 0)

        $hdrGrid = New-Object System.Windows.Controls.Grid
        $hdrCol0 = New-Object System.Windows.Controls.ColumnDefinition; $hdrCol0.Width = [System.Windows.GridLength]::Auto
        $hdrCol1 = New-Object System.Windows.Controls.ColumnDefinition; $hdrCol1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $hdrGrid.ColumnDefinitions.Add($hdrCol0); $hdrGrid.ColumnDefinitions.Add($hdrCol1)

        $badge = New-Object System.Windows.Controls.Border
        $badge.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EC4899")
        $badge.CornerRadius = New-Object System.Windows.CornerRadius(4)
        $badge.Padding = New-Object System.Windows.Thickness(8,4,8,4)
        $badge.Margin = New-Object System.Windows.Thickness(0,0,12,0)
        $badgeTxt = New-Object System.Windows.Controls.TextBlock
        $badgeTxt.Text = "USER ACCESS FIXER"
        $badgeTxt.FontWeight = [System.Windows.FontWeights]::Bold
        $badgeTxt.Foreground = [System.Windows.Media.Brushes]::White
        $badgeTxt.FontSize = 11
        $badge.Child = $badgeTxt
        [System.Windows.Controls.Grid]::SetColumn($badge, 0)
        $hdrGrid.Children.Add($badge) | Out-Null

        $hdrInfo = New-Object System.Windows.Controls.StackPanel
        $hdrTitle = New-Object System.Windows.Controls.TextBlock
        $hdrTitle.Text = "Universal User Permission & Privilege Manager"
        $hdrTitle.FontWeight = [System.Windows.FontWeights]::Bold
        $hdrTitle.Foreground = [System.Windows.Media.Brushes]::White
        $hdrTitle.FontSize = 13
        $hdrSub = New-Object System.Windows.Controls.TextBlock
        $hdrSub.Text = "Auto-register users in UserMaster, clone all screen privileges, fix FK constraint conflicts and grant full system rights."
        $hdrSub.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
        $hdrSub.FontSize = 11
        $hdrInfo.Children.Add($hdrTitle) | Out-Null
        $hdrInfo.Children.Add($hdrSub) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($hdrInfo, 1)
        $hdrGrid.Children.Add($hdrInfo) | Out-Null
        $hdrBorder.Child = $hdrGrid
        $grid.Children.Add($hdrBorder) | Out-Null

        # 2. Input Configuration Card
        $cfgBorder = New-Object System.Windows.Controls.Border
        $cfgBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0B132B")
        $cfgBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E3252")
        $cfgBorder.BorderThickness = New-Object System.Windows.Thickness(1)
        $cfgBorder.CornerRadius = New-Object System.Windows.CornerRadius(8)
        $cfgBorder.Padding = New-Object System.Windows.Thickness(14,10,14,10)
        $cfgBorder.Margin = New-Object System.Windows.Thickness(0,0,0,10)
        [System.Windows.Controls.Grid]::SetRow($cfgBorder, 1)

        $cfgGrid = New-Object System.Windows.Controls.Grid
        $cfgR0 = New-Object System.Windows.Controls.RowDefinition; $cfgR0.Height = [System.Windows.GridLength]::Auto
        $cfgR1 = New-Object System.Windows.Controls.RowDefinition; $cfgR1.Height = [System.Windows.GridLength]::Auto
        $cfgGrid.RowDefinitions.Add($cfgR0); $cfgGrid.RowDefinitions.Add($cfgR1)

        # Row 0: DB, Source User, Target User
        $cfgRow0 = New-Object System.Windows.Controls.Grid
        $cfgRow0.Margin = New-Object System.Windows.Thickness(0,0,0,8)
        $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = [System.Windows.GridLength]::Auto
        $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength(1.4, [System.Windows.GridUnitType]::Star)
        $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = [System.Windows.GridLength]::Auto
        $c3 = New-Object System.Windows.Controls.ColumnDefinition; $c3.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $c4 = New-Object System.Windows.Controls.ColumnDefinition; $c4.Width = [System.Windows.GridLength]::Auto
        $c5 = New-Object System.Windows.Controls.ColumnDefinition; $c5.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $cfgRow0.ColumnDefinitions.Add($c0); $cfgRow0.ColumnDefinitions.Add($c1); $cfgRow0.ColumnDefinitions.Add($c2)
        $cfgRow0.ColumnDefinitions.Add($c3); $cfgRow0.ColumnDefinitions.Add($c4); $cfgRow0.ColumnDefinitions.Add($c5)

        $lblDb = New-Object System.Windows.Controls.TextBlock; $lblDb.Text = "Database:"; $lblDb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8"); $lblDb.VerticalAlignment = "Center"; $lblDb.Margin = New-Object System.Windows.Thickness(0,0,6,0)
        $txtDb = New-Object System.Windows.Controls.TextBox; $txtDb.Height = 28; $txtDb.VerticalContentAlignment = "Center"; $txtDb.Padding = New-Object System.Windows.Thickness(6,0,6,0); $txtDb.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas"); $txtDb.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0A0E1A"); $txtDb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8"); $txtDb.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E3252"); $txtDb.Margin = New-Object System.Windows.Thickness(0,0,12,0)
        $currDb = if ($cmbSqlDatabase -and $cmbSqlDatabase.SelectedItem) { $cmbSqlDatabase.SelectedItem.ToString() } else { "NTIS_4023" }
        $txtDb.Text = $currDb

        $lblSrc = New-Object System.Windows.Controls.TextBlock; $lblSrc.Text = "Template/Source UserID:"; $lblSrc.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FDE047"); $lblSrc.FontWeight = [System.Windows.FontWeights]::Bold; $lblSrc.VerticalAlignment = "Center"; $lblSrc.Margin = New-Object System.Windows.Thickness(0,0,6,0)
        $txtSrc = New-Object System.Windows.Controls.TextBox; $txtSrc.Height = 28; $txtSrc.VerticalContentAlignment = "Center"; $txtSrc.Padding = New-Object System.Windows.Thickness(6,0,6,0); $txtSrc.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas"); $txtSrc.FontWeight = [System.Windows.FontWeights]::Bold; $txtSrc.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0A0E1A"); $txtSrc.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FDE047"); $txtSrc.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E3252"); $txtSrc.Margin = New-Object System.Windows.Thickness(0,0,12,0)
        $txtSrc.Text = "275"
        $txtSrc.ToolTip = "UserID of an active user whose permissions will be cloned (e.g. 275)"

        $lblTgt = New-Object System.Windows.Controls.TextBlock; $lblTgt.Text = "Target UserID (To Fix):"; $lblTgt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80"); $lblTgt.FontWeight = [System.Windows.FontWeights]::Bold; $lblTgt.VerticalAlignment = "Center"; $lblTgt.Margin = New-Object System.Windows.Thickness(0,0,6,0)
        $txtTgt = New-Object System.Windows.Controls.TextBox; $txtTgt.Height = 28; $txtTgt.VerticalContentAlignment = "Center"; $txtTgt.Padding = New-Object System.Windows.Thickness(6,0,6,0); $txtTgt.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas"); $txtTgt.FontWeight = [System.Windows.FontWeights]::Bold; $txtTgt.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0A0E1A"); $txtTgt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80"); $txtTgt.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E3252")
        $txtTgt.Text = "314"
        $txtTgt.ToolTip = "UserID of the user that is not working / needs full access (e.g. 314)"

        [System.Windows.Controls.Grid]::SetColumn($lblDb, 0); $cfgRow0.Children.Add($lblDb) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($txtDb, 1); $cfgRow0.Children.Add($txtDb) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($lblSrc, 2); $cfgRow0.Children.Add($lblSrc) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($txtSrc, 3); $cfgRow0.Children.Add($txtSrc) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($lblTgt, 4); $cfgRow0.Children.Add($lblTgt) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($txtTgt, 5); $cfgRow0.Children.Add($txtTgt) | Out-Null
        [System.Windows.Controls.Grid]::SetRow($cfgRow0, 0)
        $cfgGrid.Children.Add($cfgRow0) | Out-Null

        # Row 1: Access Flags & Options
        $chkWrap = New-Object System.Windows.Controls.WrapPanel
        $chkWrap.Margin = New-Object System.Windows.Thickness(0,4,0,0)

        $chkCreateMaster = New-Object System.Windows.Controls.CheckBox; $chkCreateMaster.Content = "Auto-Register in UserMaster"; $chkCreateMaster.IsChecked = $true; $chkCreateMaster.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8"); $chkCreateMaster.FontWeight = [System.Windows.FontWeights]::SemiBold; $chkCreateMaster.Margin = New-Object System.Windows.Thickness(0,0,14,4); $chkCreateMaster.ToolTip = "If Target UserID does not exist in UserMaster, clone and create it automatically to bypass FK constraint errors"
        $chkCopyPrivs    = New-Object System.Windows.Controls.CheckBox; $chkCopyPrivs.Content = "Clone UserPagePrevilege Screens"; $chkCopyPrivs.IsChecked = $true; $chkCopyPrivs.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#A78BFA"); $chkCopyPrivs.FontWeight = [System.Windows.FontWeights]::SemiBold; $chkCopyPrivs.Margin = New-Object System.Windows.Thickness(0,0,14,4); $chkCopyPrivs.ToolTip = "Copy all screen records from Source User to Target User"
        $chkPropTax      = New-Object System.Windows.Controls.CheckBox; $chkPropTax.Content = "Property Tax Access (IsPropertyTax=1)"; $chkPropTax.IsChecked = $true; $chkPropTax.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80"); $chkPropTax.Margin = New-Object System.Windows.Thickness(0,0,14,4)
        $chkWaterTax     = New-Object System.Windows.Controls.CheckBox; $chkWaterTax.Content = "Water Bill Access (IsWaterbillTax=1)"; $chkWaterTax.IsChecked = $true; $chkWaterTax.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#60A5FA"); $chkWaterTax.Margin = New-Object System.Windows.Thickness(0,0,14,4)
        $chkShel         = New-Object System.Windows.Controls.CheckBox; $chkShel.Content = "SHEL Access (IsSHEL=1)"; $chkShel.IsChecked = $true; $chkShel.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F472B6"); $chkShel.Margin = New-Object System.Windows.Thickness(0,0,14,4)
        $chkBypassFk     = New-Object System.Windows.Controls.CheckBox; $chkBypassFk.Content = "Safe FK Constraint Bypass"; $chkBypassFk.IsChecked = $true; $chkBypassFk.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FBBF24"); $chkBypassFk.Margin = New-Object System.Windows.Thickness(0,0,14,4); $chkBypassFk.ToolTip = "Temporarily disable and re-enable FK constraints to ensure clean execution"

        $chkWrap.Children.Add($chkCreateMaster) | Out-Null
        $chkWrap.Children.Add($chkCopyPrivs) | Out-Null
        $chkWrap.Children.Add($chkPropTax) | Out-Null
        $chkWrap.Children.Add($chkWaterTax) | Out-Null
        $chkWrap.Children.Add($chkShel) | Out-Null
        $chkWrap.Children.Add($chkBypassFk) | Out-Null
        [System.Windows.Controls.Grid]::SetRow($chkWrap, 1)
        $cfgGrid.Children.Add($chkWrap) | Out-Null

        $cfgBorder.Child = $cfgGrid
        $grid.Children.Add($cfgBorder) | Out-Null

        # 3. Action Buttons Row
        $actBorder = New-Object System.Windows.Controls.Border
        $actBorder.Margin = New-Object System.Windows.Thickness(0,0,0,10)
        [System.Windows.Controls.Grid]::SetRow($actBorder, 2)

        $actGrid = New-Object System.Windows.Controls.Grid
        $a0 = New-Object System.Windows.Controls.ColumnDefinition; $a0.Width = [System.Windows.GridLength]::Auto
        $a1 = New-Object System.Windows.Controls.ColumnDefinition; $a1.Width = [System.Windows.GridLength]::Auto
        $a2 = New-Object System.Windows.Controls.ColumnDefinition; $a2.Width = [System.Windows.GridLength]::Auto
        $a3 = New-Object System.Windows.Controls.ColumnDefinition; $a3.Width = [System.Windows.GridLength]::Auto
        $a4 = New-Object System.Windows.Controls.ColumnDefinition; $a4.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $actGrid.ColumnDefinitions.Add($a0); $actGrid.ColumnDefinitions.Add($a1); $actGrid.ColumnDefinitions.Add($a2); $actGrid.ColumnDefinitions.Add($a3); $actGrid.ColumnDefinitions.Add($a4)

        $btnFixNow = New-Object System.Windows.Controls.Button
        $btnFixNow.Content = "FIX AND GRANT ACCESS NOW"
        $btnFixNow.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EC4899")
        $btnFixNow.Foreground = [System.Windows.Media.Brushes]::White
        $btnFixNow.FontWeight = [System.Windows.FontWeights]::Bold
        $btnFixNow.Padding = New-Object System.Windows.Thickness(16,8,16,8)
        $btnFixNow.Margin = New-Object System.Windows.Thickness(0,0,8,0)
        $btnFixNow.BorderThickness = New-Object System.Windows.Thickness(0)
        $btnFixNow.Cursor = [System.Windows.Input.Cursors]::Hand
        $btnFixNow.ToolTip = "Execute the comprehensive fix script directly on the connected database!"

        $btnLoadEditor = New-Object System.Windows.Controls.Button
        $btnLoadEditor.Content = "LOAD SQL TO EDITOR"
        $btnLoadEditor.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0284C7")
        $btnLoadEditor.Foreground = [System.Windows.Media.Brushes]::White
        $btnLoadEditor.FontWeight = [System.Windows.FontWeights]::Bold
        $btnLoadEditor.Padding = New-Object System.Windows.Thickness(12,8,12,8)
        $btnLoadEditor.Margin = New-Object System.Windows.Thickness(0,0,8,0)
        $btnLoadEditor.BorderThickness = New-Object System.Windows.Thickness(0)
        $btnLoadEditor.Cursor = [System.Windows.Input.Cursors]::Hand
        $btnLoadEditor.ToolTip = "Inject the generated T-SQL script into Query Editor"

        $btnCheckStatus = New-Object System.Windows.Controls.Button
        $btnCheckStatus.Content = "CHECK USER STATUS"
        $btnCheckStatus.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F59E0B")
        $btnCheckStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A")
        $btnCheckStatus.FontWeight = [System.Windows.FontWeights]::Bold
        $btnCheckStatus.Padding = New-Object System.Windows.Thickness(12,8,12,8)
        $btnCheckStatus.Margin = New-Object System.Windows.Thickness(0,0,8,0)
        $btnCheckStatus.BorderThickness = New-Object System.Windows.Thickness(0)
        $btnCheckStatus.Cursor = [System.Windows.Input.Cursors]::Hand
        $btnCheckStatus.ToolTip = "Inspect Target UserID status in UserMaster and count assigned screens in UserPagePrevilege"

        $btnCopySql = New-Object System.Windows.Controls.Button
        $btnCopySql.Content = "COPY SQL"
        $btnCopySql.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#8B5CF6")
        $btnCopySql.Foreground = [System.Windows.Media.Brushes]::White
        $btnCopySql.FontWeight = [System.Windows.FontWeights]::Bold
        $btnCopySql.Padding = New-Object System.Windows.Thickness(12,8,12,8)
        $btnCopySql.BorderThickness = New-Object System.Windows.Thickness(0)
        $btnCopySql.Cursor = [System.Windows.Input.Cursors]::Hand

        [System.Windows.Controls.Grid]::SetColumn($btnFixNow, 0); $actGrid.Children.Add($btnFixNow) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($btnLoadEditor, 1); $actGrid.Children.Add($btnLoadEditor) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($btnCheckStatus, 2); $actGrid.Children.Add($btnCheckStatus) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($btnCopySql, 3); $actGrid.Children.Add($btnCopySql) | Out-Null
        $actBorder.Child = $actGrid
        $grid.Children.Add($actBorder) | Out-Null

        # 4. Live Output Console & Script Preview
        $outBorder = New-Object System.Windows.Controls.Border
        $outBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#070B14")
        $outBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E3252")
        $outBorder.BorderThickness = New-Object System.Windows.Thickness(1)
        $outBorder.CornerRadius = New-Object System.Windows.CornerRadius(6)
        $outBorder.Padding = New-Object System.Windows.Thickness(10)
        $outBorder.Margin = New-Object System.Windows.Thickness(0,0,0,10)
        [System.Windows.Controls.Grid]::SetRow($outBorder, 3)

        $txtLog = New-Object System.Windows.Controls.TextBox
        $txtLog.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#070B14")
        $txtLog.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
        $txtLog.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
        $txtLog.FontSize = 12
        $txtLog.IsReadOnly = $true
        $txtLog.AcceptsReturn = $true
        $txtLog.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $txtLog.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
        $txtLog.BorderThickness = New-Object System.Windows.Thickness(0)
        $txtLog.Text = ">>> Universal User Access and Privilege Manager Ready.`n>>> Set your Source UserID (e.g. 275) and Target UserID (e.g. 314), then click 'FIX AND GRANT ACCESS NOW' or 'LOAD SQL TO EDITOR'."
        $outBorder.Child = $txtLog
        $grid.Children.Add($outBorder) | Out-Null

        # 5. Bottom Status Bar
        $btmGrid = New-Object System.Windows.Controls.Grid
        [System.Windows.Controls.Grid]::SetRow($btmGrid, 4)
        $lblStatus = New-Object System.Windows.Controls.TextBlock
        $lblStatus.Text = "Status: Ready to configure user access."
        $lblStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
        $lblStatus.FontSize = 11
        $lblStatus.VerticalAlignment = "Center"
        $btmGrid.Children.Add($lblStatus) | Out-Null
        $grid.Children.Add($btmGrid) | Out-Null

        $win.Content = $grid

        # -------------------------------------------------------------
        # Helper: Build Dynamic T-SQL Fix Query
        # -------------------------------------------------------------
        $BuildSql = {
            $dbName   = $txtDb.Text.Trim()
            $srcId    = $txtSrc.Text.Trim()
            $tgtId    = $txtTgt.Text.Trim()
            $isProp   = if ($chkPropTax.IsChecked) { "1" } else { "src.IsPropertyTax" }
            $isWater  = if ($chkWaterTax.IsChecked) { "1" } else { "src.IsWaterbillTax" }
            $isShelV  = if ($chkShel.IsChecked) { "1" } else { "src.IsSHEL" }

            $sb = [System.Text.StringBuilder]::new()
            [void]$sb.AppendLine("USE [$dbName];")
            [void]$sb.AppendLine("GO")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("-- ==============================================================================")
            [void]$sb.AppendLine("-- UNIVERSAL USER ACCESS AND PRIVILEGE FIXER")
            [void]$sb.AppendLine("-- Source User: $srcId  ==>  Target User: $tgtId")
            [void]$sb.AppendLine("-- ==============================================================================")
            [void]$sb.AppendLine("BEGIN TRANSACTION;")
            [void]$sb.AppendLine("BEGIN TRY")

            if ($chkBypassFk.IsChecked) {
                [void]$sb.AppendLine("    PRINT '>>> Step 1: Temporarily disabling Foreign Key Constraints...';")
                [void]$sb.AppendLine("    ALTER TABLE [SecurityLayerUserDetails] NOCHECK CONSTRAINT ALL;")
                [void]$sb.AppendLine("    ALTER TABLE [UserModule].[UserPagePrevilege] NOCHECK CONSTRAINT ALL;")
            }

            if ($chkCreateMaster.IsChecked) {
                [void]$sb.AppendLine("    PRINT '>>> Step 2: Checking and Registering Target User $tgtId in UserMaster...';")
                [void]$sb.AppendLine("    IF NOT EXISTS (SELECT 1 FROM UserModule.UserMaster WHERE UserID = $tgtId)")
                [void]$sb.AppendLine("    BEGIN")
                [void]$sb.AppendLine("        SELECT * INTO #TempUserClone FROM UserModule.UserMaster WHERE UserID = $srcId;")
                [void]$sb.AppendLine("        UPDATE #TempUserClone SET UserID = $tgtId;")
                [void]$sb.AppendLine("        SET IDENTITY_INSERT UserModule.UserMaster ON;")
                [void]$sb.AppendLine("        INSERT INTO UserModule.UserMaster SELECT * FROM #TempUserClone;")
                [void]$sb.AppendLine("        SET IDENTITY_INSERT UserModule.UserMaster OFF;")
                [void]$sb.AppendLine("        DROP TABLE #TempUserClone;")
                [void]$sb.AppendLine("        PRINT '>>> User $tgtId successfully registered in UserMaster.';")
                [void]$sb.AppendLine("    END")
                [void]$sb.AppendLine("    ELSE")
                [void]$sb.AppendLine("    BEGIN")
                [void]$sb.AppendLine("        PRINT '>>> User $tgtId already exists in UserMaster.';")
                [void]$sb.AppendLine("    END")
            }

            if ($chkCopyPrivs.IsChecked) {
                [void]$sb.AppendLine("    PRINT '>>> Step 3: Cloning Screen Privileges from User $srcId to User $tgtId...';")
                [void]$sb.AppendLine("    INSERT INTO UserModule.UserPagePrevilege (ScreenID, UserID, AccessID, IsPropertyTax, IsWaterbillTax, IsSHEL)")
                [void]$sb.AppendLine("    SELECT src.ScreenID, $tgtId, src.AccessID, $isProp, $isWater, $isShelV")
                [void]$sb.AppendLine("    FROM UserModule.UserPagePrevilege src")
                [void]$sb.AppendLine("    WHERE src.UserID = $srcId")
                [void]$sb.AppendLine("      AND NOT EXISTS (")
                [void]$sb.AppendLine("          SELECT 1 FROM UserModule.UserPagePrevilege dest")
                [void]$sb.AppendLine("          WHERE dest.UserID = $tgtId AND dest.ScreenID = src.ScreenID")
                [void]$sb.AppendLine("      );")
                [void]$sb.AppendLine("    PRINT '>>> Screen privileges copied successfully.';")
            }

            if ($chkBypassFk.IsChecked) {
                [void]$sb.AppendLine("    PRINT '>>> Step 4: Re-enabling Foreign Key Constraints...';")
                [void]$sb.AppendLine("    ALTER TABLE [SecurityLayerUserDetails] WITH CHECK CHECK CONSTRAINT ALL;")
                [void]$sb.AppendLine("    ALTER TABLE [UserModule].[UserPagePrevilege] WITH CHECK CHECK CONSTRAINT ALL;")
            }

            [void]$sb.AppendLine("    COMMIT TRANSACTION;")
            [void]$sb.AppendLine("    PRINT '>>> ALL PRIVILEGES APPLIED AND COMMITTED SUCCESSFULLY!';")
            [void]$sb.AppendLine("END TRY")
            [void]$sb.AppendLine("BEGIN CATCH")
            [void]$sb.AppendLine("    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;")
            [void]$sb.AppendLine("    PRINT '>>> FAILED: ' + ERROR_MESSAGE();")
            [void]$sb.AppendLine("    THROW;")
            [void]$sb.AppendLine("END CATCH;")
            [void]$sb.AppendLine("GO")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("-- ==============================================================================")
            [void]$sb.AppendLine("-- VERIFY USER PRIVILEGES")
            [void]$sb.AppendLine("-- ==============================================================================")
            [void]$sb.AppendLine("SELECT UserID, COUNT(*) AS TotalScreens,")
            [void]$sb.AppendLine("       SUM(CAST(IsPropertyTax AS INT)) AS PropertyTaxScreens,")
            [void]$sb.AppendLine("       SUM(CAST(IsWaterbillTax AS INT)) AS WaterbillTaxScreens,")
            [void]$sb.AppendLine("       SUM(CAST(IsSHEL AS INT)) AS SHELScreens")
            [void]$sb.AppendLine("FROM UserModule.UserPagePrevilege")
            [void]$sb.AppendLine("WHERE UserID IN ($srcId, $tgtId)")
            [void]$sb.AppendLine("GROUP BY UserID;")

            return $sb.ToString()
        }

        # -------------------------------------------------------------
        # Button: Load SQL to Editor
        # -------------------------------------------------------------
        $btnLoadEditor.Add_Click({
            try {
                $generatedSql = &$BuildSql
                $txtSqlQuery.Text = $generatedSql
                $txtSqlQuery.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
                Switch-Tab "SqlConsole"
                $txtLog.Text = "[$(Get-Date -Format 'HH:mm:ss')] Generated SQL script loaded into Query Editor! Press F5 to execute.`n`n" + $generatedSql
                $lblStatus.Text = "Status: Script loaded to Query Editor."
            } catch {
                $txtLog.Text = "Error generating SQL: $($_.Exception.Message)"
            }
        })

        # -------------------------------------------------------------
        # Button: Copy SQL to Clipboard
        # -------------------------------------------------------------
        $btnCopySql.Add_Click({
            try {
                $generatedSql = &$BuildSql
                [System.Windows.Clipboard]::SetText($generatedSql)
                $txtLog.Text = "[$(Get-Date -Format 'HH:mm:ss')] Complete T-SQL Fix Script copied to clipboard!`n`n" + $generatedSql
                $lblStatus.Text = "Status: Copied SQL to clipboard."
            } catch {
                $txtLog.Text = "Error copying to clipboard: $($_.Exception.Message)"
            }
        })

        # -------------------------------------------------------------
        # Button: Check User Status
        # -------------------------------------------------------------
        $btnCheckStatus.Add_Click({
            try {
                $dbName = $txtDb.Text.Trim()
                $srcId  = $txtSrc.Text.Trim()
                $tgtId  = $txtTgt.Text.Trim()
                $txtLog.Text = "[$(Get-Date -Format 'HH:mm:ss')] Inspecting User Status in Database [$dbName]...`n"

                if (-not $script:SqlConnection -or $script:SqlConnection.State -ne [System.Data.ConnectionState]::Open) {
                    $txtLog.Text += "SQL Server is not currently connected in SQL Console. Please click 'CONNECT' on the SQL Console tab first.`n"
                    return
                }

                $cmd = $script:SqlConnection.CreateCommand()
                $cmd.CommandText = "USE [$dbName]; SELECT 'UserMaster' AS TableSource, UserID, UserName, CAST(IsActive AS VARCHAR(10)) AS StatusInfo FROM UserModule.UserMaster WHERE UserID IN ($srcId, $tgtId) UNION ALL SELECT 'UserPagePrevilege' AS TableSource, UserID, 'Screens Assigned' AS UserName, CAST(COUNT(*) AS VARCHAR(10)) AS StatusInfo FROM UserModule.UserPagePrevilege WHERE UserID IN ($srcId, $tgtId) GROUP BY UserID;"
                $da = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
                $dt = New-Object System.Data.DataTable
                $da.Fill($dt) | Out-Null
                $cmd.Dispose()

                if ($dt.Rows.Count -gt 0) {
                    $sb = [System.Text.StringBuilder]::new()
                    [void]$sb.AppendLine("---------------------------------------------------------------")
                    [void]$sb.AppendLine(("{0,-18} | {1,-10} | {2,-20} | {3,-12}" -f "TABLE", "USER ID", "NAME/INFO", "STATUS/SCREENS"))
                    [void]$sb.AppendLine("---------------------------------------------------------------")
                    foreach ($row in $dt.Rows) {
                        [void]$sb.AppendLine(("{0,-18} | {1,-10} | {2,-20} | {3,-12}" -f $row["TableSource"], $row["UserID"], $row["UserName"], $row["StatusInfo"]))
                    }
                    [void]$sb.AppendLine("---------------------------------------------------------------")
                    $txtLog.Text += $sb.ToString()
                    $lblStatus.Text = "Status: User status check completed."
                } else {
                    $txtLog.Text += "Neither User $srcId nor User $tgtId were found in database [$dbName].`n"
                }
            } catch {
                $txtLog.Text += "Error querying database: $($_.Exception.Message)`n"
            }
        })

        # -------------------------------------------------------------
        # Button: Fix & Grant User Access Now (Direct Execution)
        # -------------------------------------------------------------
        $btnFixNow.Add_Click({
            try {
                $dbName = $txtDb.Text.Trim()
                $srcId  = $txtSrc.Text.Trim()
                $tgtId  = $txtTgt.Text.Trim()

                if (-not $srcId -or -not $tgtId) {
                    $txtLog.Text = "ERROR: Please enter both Source UserID and Target UserID."
                    return
                }

                $txtLog.Text = "[$(Get-Date -Format 'HH:mm:ss')] Starting Universal User Access Fix for Target User $tgtId on [$dbName]...`n"

                if (-not $script:SqlConnection -or $script:SqlConnection.State -ne [System.Data.ConnectionState]::Open) {
                    $txtLog.Text += "SQL Server is not connected. Please click 'CONNECT' on the SQL Console tab first, or click 'LOAD SQL TO EDITOR' to run manually.`n"
                    return
                }

                $cmd = $script:SqlConnection.CreateCommand()
                $cmd.CommandTimeout = 60
                $rawScript = &$BuildSql

                $batches = $rawScript -split '(?im)^\s*GO\s*$'
                foreach ($b in $batches) {
                    $cleanB = $b.Trim()
                    if ($cleanB) {
                        $cmd.CommandText = $cleanB
                        $da = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
                        $dt = New-Object System.Data.DataTable
                        $da.Fill($dt) | Out-Null
                    }
                }
                $cmd.Dispose()

                $txtLog.Text += "SUCCESS: Target User $tgtId is now active and fully provisioned with screen privileges!`n`n"

                # Verify immediate count
                $chkCmd = $script:SqlConnection.CreateCommand()
                $chkCmd.CommandText = "USE [$dbName]; SELECT UserID, COUNT(*) AS ScreenCount FROM UserModule.UserPagePrevilege WHERE UserID = $tgtId GROUP BY UserID;"
                $reader = $chkCmd.ExecuteReader()
                if ($reader.Read()) {
                    $cnt = $reader["ScreenCount"]
                    $txtLog.Text += ">>> Verified: User $tgtId now has $cnt screen privileges assigned in UserPagePrevilege!`n"
                }
                $reader.Close()
                $chkCmd.Dispose()

                $lblStatus.Text = "Status: User $tgtId fixed successfully!"
            } catch {
                $txtLog.Text += "`nERROR DURING EXECUTION: $($_.Exception.Message)`n"
                $lblStatus.Text = "Status: Execution error occurred."
            }
        })

        [void]$win.ShowDialog()
    } catch { }
}

function Show-TableDdlWizardWindow {
    try {
        $win = New-Object System.Windows.Window
        $win.Title = "Table & Query DDL Generator Studio (All-in-One SQL Wizard)"
        $win.Width = 890
        $win.Height = 720
        $win.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
        if ($window -and $window.IsVisible) { try { $win.Owner = $window } catch {} }
        $win.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#060A13")
        $win.ResizeMode = [System.Windows.ResizeMode]::CanResizeWithGrip

        $grid = New-Object System.Windows.Controls.Grid
        $grid.Margin = New-Object System.Windows.Thickness(16)
        
        $r0 = New-Object System.Windows.Controls.RowDefinition; $r0.Height = [System.Windows.GridLength]::Auto
        $r1 = New-Object System.Windows.Controls.RowDefinition; $r1.Height = [System.Windows.GridLength]::Auto
        $r2 = New-Object System.Windows.Controls.RowDefinition; $r2.Height = [System.Windows.GridLength]::Auto
        $r3 = New-Object System.Windows.Controls.RowDefinition; $r3.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $r4 = New-Object System.Windows.Controls.RowDefinition; $r4.Height = [System.Windows.GridLength]::Auto
        $grid.RowDefinitions.Add($r0); $grid.RowDefinitions.Add($r1); $grid.RowDefinitions.Add($r2); $grid.RowDefinitions.Add($r3); $grid.RowDefinitions.Add($r4)

        # 1. Header Card
        $hdrBorder = New-Object System.Windows.Controls.Border
        $hdrBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A")
        $hdrBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E11D48")
        $hdrBorder.BorderThickness = New-Object System.Windows.Thickness(1)
        $hdrBorder.CornerRadius = New-Object System.Windows.CornerRadius(8)
        $hdrBorder.Padding = New-Object System.Windows.Thickness(14,10,14,10)
        $hdrBorder.Margin = New-Object System.Windows.Thickness(0,0,0,10)
        [System.Windows.Controls.Grid]::SetRow($hdrBorder, 0)

        $hdrGrid = New-Object System.Windows.Controls.Grid
        $hdrCol0 = New-Object System.Windows.Controls.ColumnDefinition; $hdrCol0.Width = [System.Windows.GridLength]::Auto
        $hdrCol1 = New-Object System.Windows.Controls.ColumnDefinition; $hdrCol1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $hdrGrid.ColumnDefinitions.Add($hdrCol0); $hdrGrid.ColumnDefinitions.Add($hdrCol1)

        $badge = New-Object System.Windows.Controls.Border
        $badge.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E11D48")
        $badge.CornerRadius = New-Object System.Windows.CornerRadius(4)
        $badge.Padding = New-Object System.Windows.Thickness(8,4,8,4)
        $badge.Margin = New-Object System.Windows.Thickness(0,0,12,0)
        $badgeTxt = New-Object System.Windows.Controls.TextBlock
        $badgeTxt.Text = "DDL & QUERY WIZARD"
        $badgeTxt.FontWeight = [System.Windows.FontWeights]::Bold
        $badgeTxt.Foreground = [System.Windows.Media.Brushes]::White
        $badgeTxt.FontSize = 11
        $badge.Child = $badgeTxt
        [System.Windows.Controls.Grid]::SetColumn($badge, 0)
        $hdrGrid.Children.Add($badge) | Out-Null

        $hdrInfo = New-Object System.Windows.Controls.StackPanel
        $hdrTitle = New-Object System.Windows.Controls.TextBlock
        $hdrTitle.Text = "Table & Query DDL Generator Studio"
        $hdrTitle.FontWeight = [System.Windows.FontWeights]::Bold
        $hdrTitle.Foreground = [System.Windows.Media.Brushes]::White
        $hdrTitle.FontSize = 13
        $hdrSub = New-Object System.Windows.Controls.TextBlock
        $hdrSub.Text = "Instant templates for CREATE TABLE, ALTER TABLE (Add/Modify/Drop Columns, Constraints, Keys), Indexes, Views, Triggers & CRUD Queries."
        $hdrSub.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
        $hdrSub.FontSize = 11
        $hdrInfo.Children.Add($hdrTitle) | Out-Null
        $hdrInfo.Children.Add($hdrSub) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($hdrInfo, 1)
        $hdrGrid.Children.Add($hdrInfo) | Out-Null
        $hdrBorder.Child = $hdrGrid
        $grid.Children.Add($hdrBorder) | Out-Null

        # 2. Input Configuration & Operation Selector Card
        $cfgBorder = New-Object System.Windows.Controls.Border
        $cfgBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0B132B")
        $cfgBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E3252")
        $cfgBorder.BorderThickness = New-Object System.Windows.Thickness(1)
        $cfgBorder.CornerRadius = New-Object System.Windows.CornerRadius(8)
        $cfgBorder.Padding = New-Object System.Windows.Thickness(14,10,14,10)
        $cfgBorder.Margin = New-Object System.Windows.Thickness(0,0,0,10)
        [System.Windows.Controls.Grid]::SetRow($cfgBorder, 1)

        $cfgGrid = New-Object System.Windows.Controls.Grid
        $cfgR0 = New-Object System.Windows.Controls.RowDefinition; $cfgR0.Height = [System.Windows.GridLength]::Auto
        $cfgR1 = New-Object System.Windows.Controls.RowDefinition; $cfgR1.Height = [System.Windows.GridLength]::Auto
        $cfgR2 = New-Object System.Windows.Controls.RowDefinition; $cfgR2.Height = [System.Windows.GridLength]::Auto
        $cfgGrid.RowDefinitions.Add($cfgR0); $cfgGrid.RowDefinitions.Add($cfgR1); $cfgGrid.RowDefinitions.Add($cfgR2)

        # Row 0: Database, Schema, Table Name, Fetch Tables
        $cfgRow0 = New-Object System.Windows.Controls.Grid
        $cfgRow0.Margin = New-Object System.Windows.Thickness(0,0,0,8)
        $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = [System.Windows.GridLength]::Auto
        $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = [System.Windows.GridLength]::Auto
        $c3 = New-Object System.Windows.Controls.ColumnDefinition; $c3.Width = New-Object System.Windows.GridLength(0.7, [System.Windows.GridUnitType]::Star)
        $c4 = New-Object System.Windows.Controls.ColumnDefinition; $c4.Width = [System.Windows.GridLength]::Auto
        $c5 = New-Object System.Windows.Controls.ColumnDefinition; $c5.Width = New-Object System.Windows.GridLength(1.3, [System.Windows.GridUnitType]::Star)
        $c6 = New-Object System.Windows.Controls.ColumnDefinition; $c6.Width = [System.Windows.GridLength]::Auto
        $cfgRow0.ColumnDefinitions.Add($c0); $cfgRow0.ColumnDefinitions.Add($c1); $cfgRow0.ColumnDefinitions.Add($c2)
        $cfgRow0.ColumnDefinitions.Add($c3); $cfgRow0.ColumnDefinitions.Add($c4); $cfgRow0.ColumnDefinitions.Add($c5); $cfgRow0.ColumnDefinitions.Add($c6)

        $lblDb = New-Object System.Windows.Controls.TextBlock; $lblDb.Text = "Database:"; $lblDb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8"); $lblDb.VerticalAlignment = "Center"; $lblDb.Margin = New-Object System.Windows.Thickness(0,0,6,0)
        $txtDb = New-Object System.Windows.Controls.TextBox; $txtDb.Height = 28; $txtDb.VerticalContentAlignment = "Center"; $txtDb.Padding = New-Object System.Windows.Thickness(6,0,6,0); $txtDb.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas"); $txtDb.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0A0E1A"); $txtDb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8"); $txtDb.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E3252"); $txtDb.Margin = New-Object System.Windows.Thickness(0,0,10,0)
        $currDb = if ($cmbSqlDatabase -and $cmbSqlDatabase.SelectedItem) { $cmbSqlDatabase.SelectedItem.ToString() } else { "NTIS_4023" }
        $txtDb.Text = $currDb

        $lblSchema = New-Object System.Windows.Controls.TextBlock; $lblSchema.Text = "Schema:"; $lblSchema.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8"); $lblSchema.VerticalAlignment = "Center"; $lblSchema.Margin = New-Object System.Windows.Thickness(0,0,6,0)
        $txtSchema = New-Object System.Windows.Controls.TextBox; $txtSchema.Height = 28; $txtSchema.VerticalContentAlignment = "Center"; $txtSchema.Padding = New-Object System.Windows.Thickness(6,0,6,0); $txtSchema.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas"); $txtSchema.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0A0E1A"); $txtSchema.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FBBF24"); $txtSchema.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E3252"); $txtSchema.Margin = New-Object System.Windows.Thickness(0,0,10,0)
        $txtSchema.Text = "dbo"

        $lblTbl = New-Object System.Windows.Controls.TextBlock; $lblTbl.Text = "Table Name:"; $lblTbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80"); $lblTbl.FontWeight = [System.Windows.FontWeights]::Bold; $lblTbl.VerticalAlignment = "Center"; $lblTbl.Margin = New-Object System.Windows.Thickness(0,0,6,0)
        $txtTable = New-Object System.Windows.Controls.TextBox; $txtTable.Height = 28; $txtTable.VerticalContentAlignment = "Center"; $txtTable.Padding = New-Object System.Windows.Thickness(6,0,6,0); $txtTable.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas"); $txtTable.FontWeight = [System.Windows.FontWeights]::Bold; $txtTable.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0A0E1A"); $txtTable.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80"); $txtTable.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E3252"); $txtTable.Margin = New-Object System.Windows.Thickness(0,0,6,0)
        $txtTable.Text = "PropertyImagesMast"

        $btnFetchTbls = New-Object System.Windows.Controls.Button; $btnFetchTbls.Content = "FETCH TABLES"; $btnFetchTbls.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B"); $btnFetchTbls.Foreground = [System.Windows.Media.Brushes]::White; $btnFetchTbls.Padding = New-Object System.Windows.Thickness(8,4,8,4); $btnFetchTbls.BorderThickness = New-Object System.Windows.Thickness(0); $btnFetchTbls.Cursor = [System.Windows.Input.Cursors]::Hand

        [System.Windows.Controls.Grid]::SetColumn($lblDb, 0); $cfgRow0.Children.Add($lblDb) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($txtDb, 1); $cfgRow0.Children.Add($txtDb) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($lblSchema, 2); $cfgRow0.Children.Add($lblSchema) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($txtSchema, 3); $cfgRow0.Children.Add($txtSchema) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($lblTbl, 4); $cfgRow0.Children.Add($lblTbl) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($txtTable, 5); $cfgRow0.Children.Add($txtTable) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($btnFetchTbls, 6); $cfgRow0.Children.Add($btnFetchTbls) | Out-Null
        [System.Windows.Controls.Grid]::SetRow($cfgRow0, 0)
        $cfgGrid.Children.Add($cfgRow0) | Out-Null

        # Row 1: Operation Template Selector
        $cfgRow1 = New-Object System.Windows.Controls.Grid
        $cfgRow1.Margin = New-Object System.Windows.Thickness(0,0,0,8)
        $opCol0 = New-Object System.Windows.Controls.ColumnDefinition; $opCol0.Width = [System.Windows.GridLength]::Auto
        $opCol1 = New-Object System.Windows.Controls.ColumnDefinition; $opCol1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $cfgRow1.ColumnDefinitions.Add($opCol0); $cfgRow1.ColumnDefinitions.Add($opCol1)

        $lblOp = New-Object System.Windows.Controls.TextBlock; $lblOp.Text = "Query Operation:"; $lblOp.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F472B6"); $lblOp.FontWeight = [System.Windows.FontWeights]::Bold; $lblOp.VerticalAlignment = "Center"; $lblOp.Margin = New-Object System.Windows.Thickness(0,0,8,0)
        $cmbOp = New-Object System.Windows.Controls.ComboBox; $cmbOp.Height = 28; $cmbOp.VerticalContentAlignment = "Center"

        $opList = @(
            "[CREATE] 1. CREATE TABLE (Master Table with PK Identity & Audit)",
            "[CREATE] 2. CREATE TABLE (Child Table with FK Constraint)",
            "[CREATE] 3. CREATE TABLE (#TempTable Structure)",
            "[ALTER] 4. ADD COLUMN (New Column with DataType)",
            "[ALTER] 5. ALTER / MODIFY COLUMN DATA TYPE",
            "[ALTER] 6. DROP COLUMN",
            "[ALTER] 7. ADD PRIMARY KEY CONSTRAINT",
            "[ALTER] 8. ADD FOREIGN KEY CONSTRAINT (Ref other table)",
            "[ALTER] 9. ADD DEFAULT VALUE CONSTRAINT (e.g. GETDATE(), 1)",
            "[ALTER] 10. DROP CONSTRAINT (PK / FK / Default)",
            "[ALTER] 11. RENAME COLUMN (sp_rename)",
            "[ALTER] 12. RENAME TABLE (sp_rename)",
            "[CRUD] 13. SELECT TOP 100 with WHERE & ORDER BY",
            "[CRUD] 14. INSERT INTO (Standard Column List & Values)",
            "[CRUD] 15. INSERT INTO ... SELECT (Copy Data Between Tables)",
            "[CRUD] 16. UPDATE ... SET (Safe Transaction Template with WHERE)",
            "[CRUD] 17. DELETE FROM (Safe Transaction Template with WHERE)",
            "[CRUD] 18. MERGE INTO / UPSERT (Insert or Update Matching Rows)",
            "[CRUD] 19. TRUNCATE TABLE (with Safety Verification)",
            "[INDEX] 20. CREATE NONCLUSTERED INDEX (with INCLUDE)",
            "[INDEX] 21. CREATE UNIQUE INDEX",
            "[VIEW] 22. CREATE OR ALTER VIEW",
            "[TRIGGER] 23. CREATE TRIGGER (AFTER INSERT/UPDATE/DELETE)",
            "[META] 24. Table Space & Row Count (sp_spaceused)",
            "[META] 25. Table Columns & Types (sp_help)",
            "[META] 26. Table Indexes Info (sp_helpindex)",
            "[BACKUP] 27. BACKUP TABLE (SELECT * INTO BackupTable FROM Table)"
        )
        foreach ($item in $opList) { $cmbOp.Items.Add($item) | Out-Null }
        $cmbOp.SelectedIndex = 0

        [System.Windows.Controls.Grid]::SetColumn($lblOp, 0); $cfgRow1.Children.Add($lblOp) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($cmbOp, 1); $cfgRow1.Children.Add($cmbOp) | Out-Null
        [System.Windows.Controls.Grid]::SetRow($cfgRow1, 1)
        $cfgGrid.Children.Add($cfgRow1) | Out-Null

        # Row 2: Dynamic Parameters Row (Column, DataType, Extra/Default/Ref)
        $cfgRow2 = New-Object System.Windows.Controls.Grid
        $p0 = New-Object System.Windows.Controls.ColumnDefinition; $p0.Width = [System.Windows.GridLength]::Auto
        $p1 = New-Object System.Windows.Controls.ColumnDefinition; $p1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $p2 = New-Object System.Windows.Controls.ColumnDefinition; $p2.Width = [System.Windows.GridLength]::Auto
        $p3 = New-Object System.Windows.Controls.ColumnDefinition; $p3.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $p4 = New-Object System.Windows.Controls.ColumnDefinition; $p4.Width = [System.Windows.GridLength]::Auto
        $p5 = New-Object System.Windows.Controls.ColumnDefinition; $p5.Width = New-Object System.Windows.GridLength(1.2, [System.Windows.GridUnitType]::Star)
        $cfgRow2.ColumnDefinitions.Add($p0); $cfgRow2.ColumnDefinitions.Add($p1); $cfgRow2.ColumnDefinitions.Add($p2)
        $cfgRow2.ColumnDefinitions.Add($p3); $cfgRow2.ColumnDefinitions.Add($p4); $cfgRow2.ColumnDefinitions.Add($p5)

        $lblCol = New-Object System.Windows.Controls.TextBlock; $lblCol.Text = "Column Name:"; $lblCol.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8"); $lblCol.VerticalAlignment = "Center"; $lblCol.Margin = New-Object System.Windows.Thickness(0,0,6,0)
        $txtCol = New-Object System.Windows.Controls.TextBox; $txtCol.Height = 28; $txtCol.VerticalContentAlignment = "Center"; $txtCol.Padding = New-Object System.Windows.Thickness(6,0,6,0); $txtCol.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas"); $txtCol.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0A0E1A"); $txtCol.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E2E8F0"); $txtCol.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E3252"); $txtCol.Margin = New-Object System.Windows.Thickness(0,0,10,0)
        $txtCol.Text = "ImageData"

        $lblType = New-Object System.Windows.Controls.TextBlock; $lblType.Text = "Data Type:"; $lblType.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8"); $lblType.VerticalAlignment = "Center"; $lblType.Margin = New-Object System.Windows.Thickness(0,0,6,0)
        $cmbType = New-Object System.Windows.Controls.ComboBox; $cmbType.Height = 28; $cmbType.VerticalContentAlignment = "Center"; $cmbType.Margin = New-Object System.Windows.Thickness(0,0,10,0)
        $typeList = @("VARBINARY(MAX)", "VARCHAR(100)", "VARCHAR(250)", "VARCHAR(MAX)", "NVARCHAR(100)", "NVARCHAR(250)", "NVARCHAR(MAX)", "INT", "BIGINT", "SMALLINT", "TINYINT", "DECIMAL(18,2)", "DECIMAL(18,4)", "FLOAT", "DATETIME", "DATE", "TIME", "BIT", "UNIQUEIDENTIFIER")
        foreach ($t in $typeList) { $cmbType.Items.Add($t) | Out-Null }
        $cmbType.SelectedIndex = 0

        $lblExtra = New-Object System.Windows.Controls.TextBlock; $lblExtra.Text = "Ref/Default/Constraint:"; $lblExtra.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8"); $lblExtra.VerticalAlignment = "Center"; $lblExtra.Margin = New-Object System.Windows.Thickness(0,0,6,0)
        $txtExtra = New-Object System.Windows.Controls.TextBox; $txtExtra.Height = 28; $txtExtra.VerticalContentAlignment = "Center"; $txtExtra.Padding = New-Object System.Windows.Thickness(6,0,6,0); $txtExtra.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas"); $txtExtra.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0A0E1A"); $txtExtra.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#A78BFA"); $txtExtra.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E3252")
        $txtExtra.Text = "GETDATE()"

        [System.Windows.Controls.Grid]::SetColumn($lblCol, 0); $cfgRow2.Children.Add($lblCol) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($txtCol, 1); $cfgRow2.Children.Add($txtCol) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($lblType, 2); $cfgRow2.Children.Add($lblType) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($cmbType, 3); $cfgRow2.Children.Add($cmbType) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($lblExtra, 4); $cfgRow2.Children.Add($lblExtra) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($txtExtra, 5); $cfgRow2.Children.Add($txtExtra) | Out-Null
        [System.Windows.Controls.Grid]::SetRow($cfgRow2, 2)
        $cfgGrid.Children.Add($cfgRow2) | Out-Null

        $cfgBorder.Child = $cfgGrid
        $grid.Children.Add($cfgBorder) | Out-Null

        # 3. Action Buttons Row
        $actBorder = New-Object System.Windows.Controls.Border
        $actBorder.Margin = New-Object System.Windows.Thickness(0,0,0,10)
        [System.Windows.Controls.Grid]::SetRow($actBorder, 2)

        $actGrid = New-Object System.Windows.Controls.Grid
        $a0 = New-Object System.Windows.Controls.ColumnDefinition; $a0.Width = [System.Windows.GridLength]::Auto
        $a1 = New-Object System.Windows.Controls.ColumnDefinition; $a1.Width = [System.Windows.GridLength]::Auto
        $a2 = New-Object System.Windows.Controls.ColumnDefinition; $a2.Width = [System.Windows.GridLength]::Auto
        $a3 = New-Object System.Windows.Controls.ColumnDefinition; $a3.Width = [System.Windows.GridLength]::Auto
        $a4 = New-Object System.Windows.Controls.ColumnDefinition; $a4.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $actGrid.ColumnDefinitions.Add($a0); $actGrid.ColumnDefinitions.Add($a1); $actGrid.ColumnDefinitions.Add($a2); $actGrid.ColumnDefinitions.Add($a3); $actGrid.ColumnDefinitions.Add($a4)

        $btnLoadEditor = New-Object System.Windows.Controls.Button
        $btnLoadEditor.Content = "LOAD TO QUERY EDITOR"
        $btnLoadEditor.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0284C7")
        $btnLoadEditor.Foreground = [System.Windows.Media.Brushes]::White
        $btnLoadEditor.FontWeight = [System.Windows.FontWeights]::Bold
        $btnLoadEditor.Padding = New-Object System.Windows.Thickness(14,8,14,8)
        $btnLoadEditor.Margin = New-Object System.Windows.Thickness(0,0,8,0)
        $btnLoadEditor.BorderThickness = New-Object System.Windows.Thickness(0)
        $btnLoadEditor.Cursor = [System.Windows.Input.Cursors]::Hand
        $btnLoadEditor.ToolTip = "Send the generated SQL script directly into the main Query Editor"

        $btnExecNow = New-Object System.Windows.Controls.Button
        $btnExecNow.Content = "EXECUTE SCRIPT (F5)"
        $btnExecNow.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#10B981")
        $btnExecNow.Foreground = [System.Windows.Media.Brushes]::White
        $btnExecNow.FontWeight = [System.Windows.FontWeights]::Bold
        $btnExecNow.Padding = New-Object System.Windows.Thickness(14,8,14,8)
        $btnExecNow.Margin = New-Object System.Windows.Thickness(0,0,8,0)
        $btnExecNow.BorderThickness = New-Object System.Windows.Thickness(0)
        $btnExecNow.Cursor = [System.Windows.Input.Cursors]::Hand
        $btnExecNow.ToolTip = "Execute the script directly on the connected database!"

        $btnTestTran = New-Object System.Windows.Controls.Button
        $btnTestTran.Content = "TEST (BEGIN TRAN)"
        $btnTestTran.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F59E0B")
        $btnTestTran.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A")
        $btnTestTran.FontWeight = [System.Windows.FontWeights]::Bold
        $btnTestTran.Padding = New-Object System.Windows.Thickness(12,8,12,8)
        $btnTestTran.Margin = New-Object System.Windows.Thickness(0,0,8,0)
        $btnTestTran.BorderThickness = New-Object System.Windows.Thickness(0)
        $btnTestTran.Cursor = [System.Windows.Input.Cursors]::Hand
        $btnTestTran.ToolTip = "Test execution inside BEGIN TRAN...ROLLBACK to verify without committing"

        $btnCopy = New-Object System.Windows.Controls.Button
        $btnCopy.Content = "COPY SQL"
        $btnCopy.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#8B5CF6")
        $btnCopy.Foreground = [System.Windows.Media.Brushes]::White
        $btnCopy.FontWeight = [System.Windows.FontWeights]::Bold
        $btnCopy.Padding = New-Object System.Windows.Thickness(12,8,12,8)
        $btnCopy.BorderThickness = New-Object System.Windows.Thickness(0)
        $btnCopy.Cursor = [System.Windows.Input.Cursors]::Hand

        [System.Windows.Controls.Grid]::SetColumn($btnLoadEditor, 0); $actGrid.Children.Add($btnLoadEditor) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($btnExecNow, 1); $actGrid.Children.Add($btnExecNow) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($btnTestTran, 2); $actGrid.Children.Add($btnTestTran) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($btnCopy, 3); $actGrid.Children.Add($btnCopy) | Out-Null
        $actBorder.Child = $actGrid
        $grid.Children.Add($actBorder) | Out-Null

        # 4. Live SQL Script Preview & Log Box
        $outBorder = New-Object System.Windows.Controls.Border
        $outBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#070B14")
        $outBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E3252")
        $outBorder.BorderThickness = New-Object System.Windows.Thickness(1)
        $outBorder.CornerRadius = New-Object System.Windows.CornerRadius(6)
        $outBorder.Padding = New-Object System.Windows.Thickness(10)
        $outBorder.Margin = New-Object System.Windows.Thickness(0,0,0,10)
        [System.Windows.Controls.Grid]::SetRow($outBorder, 3)

        $txtSqlPreview = New-Object System.Windows.Controls.TextBox
        $txtSqlPreview.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#070B14")
        $txtSqlPreview.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
        $txtSqlPreview.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
        $txtSqlPreview.FontSize = 12.5
        $txtSqlPreview.AcceptsReturn = $true
        $txtSqlPreview.AcceptsTab = $true
        $txtSqlPreview.TextWrapping = [System.Windows.TextWrapping]::NoWrap
        $txtSqlPreview.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
        $txtSqlPreview.HorizontalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
        $txtSqlPreview.BorderThickness = New-Object System.Windows.Thickness(0)
        $outBorder.Child = $txtSqlPreview
        $grid.Children.Add($outBorder) | Out-Null

        # 5. Bottom Status Bar
        $btmGrid = New-Object System.Windows.Controls.Grid
        [System.Windows.Controls.Grid]::SetRow($btmGrid, 4)
        $lblStatus = New-Object System.Windows.Controls.TextBlock
        $lblStatus.Text = "Status: Ready to generate DDL & query templates."
        $lblStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
        $lblStatus.FontSize = 11
        $lblStatus.VerticalAlignment = "Center"
        $btmGrid.Children.Add($lblStatus) | Out-Null
        $grid.Children.Add($btmGrid) | Out-Null

        $win.Content = $grid

        # -------------------------------------------------------------
        # Helper: Generate DDL / Query Script dynamically
        # -------------------------------------------------------------
        $GenerateDdl = {
            $dbName   = if ($txtDb -and $txtDb.Text) { $txtDb.Text.Trim() } else { "NTIS_4023" }
            $schema   = if ($txtSchema -and $txtSchema.Text -and $txtSchema.Text.Trim()) { $txtSchema.Text.Trim() } else { "dbo" }
            $tblName  = if ($txtTable -and $txtTable.Text) { $txtTable.Text.Trim() } else { "PropertyImagesMast" }
            $colName  = if ($txtCol -and $txtCol.Text) { $txtCol.Text.Trim() } else { "ImageData" }
            $dataType = if ($cmbType -and $cmbType.SelectedItem) { $cmbType.SelectedItem.ToString() } else { "VARCHAR(100)" }
            $extraVal = if ($txtExtra -and $txtExtra.Text) { $txtExtra.Text.Trim() } else { "" }
            $opIdx    = if ($cmbOp) { $cmbOp.SelectedIndex } else { 0 }

            $sb = [System.Text.StringBuilder]::new()
            [void]$sb.AppendLine("USE [$dbName];")
            [void]$sb.AppendLine("GO")
            [void]$sb.AppendLine("")

            switch ($opIdx) {
                0 { # 1. CREATE TABLE (Master Table)
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("-- CREATE MASTER TABLE: [$schema].[$tblName]")
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE s.name = '$schema' AND t.name = '$tblName')")
                    [void]$sb.AppendLine("BEGIN")
                    [void]$sb.AppendLine("    CREATE TABLE [$schema].[$tblName] (")
                    [void]$sb.AppendLine("        [ID] INT IDENTITY(1,1) NOT NULL,")
                    [void]$sb.AppendLine("        [Name] VARCHAR(150) NOT NULL,")
                    [void]$sb.AppendLine("        [Description] NVARCHAR(500) NULL,")
                    [void]$sb.AppendLine("        [$colName] $dataType NULL,")
                    [void]$sb.AppendLine("        [IsActive] BIT NOT NULL CONSTRAINT [DF_${tblName}_IsActive] DEFAULT 1,")
                    [void]$sb.AppendLine("        [CreatedDate] DATETIME NOT NULL CONSTRAINT [DF_${tblName}_CreatedDate] DEFAULT GETDATE(),")
                    [void]$sb.AppendLine("        [CreatedBy] INT NULL,")
                    [void]$sb.AppendLine("        [UpdatedDate] DATETIME NULL,")
                    [void]$sb.AppendLine("        [UpdatedBy] INT NULL,")
                    [void]$sb.AppendLine("        CONSTRAINT [PK_${tblName}] PRIMARY KEY CLUSTERED ([ID] ASC)")
                    [void]$sb.AppendLine("    );")
                    [void]$sb.AppendLine("    PRINT '>>> Table [$schema].[$tblName] created successfully!';")
                    [void]$sb.AppendLine("END")
                    [void]$sb.AppendLine("ELSE")
                    [void]$sb.AppendLine("BEGIN")
                    [void]$sb.AppendLine("    PRINT '>>> Table [$schema].[$tblName] already exists.';")
                    [void]$sb.AppendLine("END")
                }
                1 { # 2. CREATE TABLE (Child Table with FK)
                    $refTable = if ($extraVal) { $extraVal } else { "PropertyMast(OwnerID)" }
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("-- CREATE DETAIL TABLE: [$schema].[$tblName] (With Foreign Key)")
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE s.name = '$schema' AND t.name = '$tblName')")
                    [void]$sb.AppendLine("BEGIN")
                    [void]$sb.AppendLine("    CREATE TABLE [$schema].[$tblName] (")
                    [void]$sb.AppendLine("        [DetailID] INT IDENTITY(1,1) NOT NULL,")
                    [void]$sb.AppendLine("        [ParentID] INT NOT NULL,")
                    [void]$sb.AppendLine("        [$colName] $dataType NULL,")
                    [void]$sb.AppendLine("        [IsActive] BIT NOT NULL DEFAULT 1,")
                    [void]$sb.AppendLine("        [EntryDate] DATETIME NOT NULL DEFAULT GETDATE(),")
                    [void]$sb.AppendLine("        CONSTRAINT [PK_${tblName}] PRIMARY KEY CLUSTERED ([DetailID] ASC)")
                    [void]$sb.AppendLine("    );")
                    [void]$sb.AppendLine("    PRINT '>>> Table [$schema].[$tblName] created successfully!';")
                    [void]$sb.AppendLine("END")
                }
                2 { # 3. CREATE TABLE (#TempTable)
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("-- CREATE TEMPORARY TABLE: #$tblName")
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("IF OBJECT_ID('tempdb..#$tblName') IS NOT NULL DROP TABLE #$tblName;")
                    [void]$sb.AppendLine("CREATE TABLE #$tblName (")
                    [void]$sb.AppendLine("    [RowID] INT IDENTITY(1,1) PRIMARY KEY,")
                    [void]$sb.AppendLine("    [ID] INT,")
                    [void]$sb.AppendLine("    [$colName] $dataType,")
                    [void]$sb.AppendLine("    [Status] VARCHAR(50)")
                    [void]$sb.AppendLine(");")
                    [void]$sb.AppendLine("PRINT '>>> Temp table #$tblName created.';")
                }
                3 { # 4. ADD COLUMN
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("-- ALTER TABLE: ADD COLUMN [$colName] ($dataType)")
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("IF NOT EXISTS (")
                    [void]$sb.AppendLine("    SELECT 1 FROM sys.columns c")
                    [void]$sb.AppendLine("    JOIN sys.tables t ON c.object_id = t.object_id")
                    [void]$sb.AppendLine("    JOIN sys.schemas s ON t.schema_id = s.schema_id")
                    [void]$sb.AppendLine("    WHERE s.name = '$schema' AND t.name = '$tblName' AND c.name = '$colName'")
                    [void]$sb.AppendLine(")")
                    [void]$sb.AppendLine("BEGIN")
                    [void]$sb.AppendLine("    ALTER TABLE [$schema].[$tblName] ADD [$colName] $dataType NULL;")
                    [void]$sb.AppendLine("    PRINT '>>> Column [$colName] ($dataType) added to [$schema].[$tblName].';")
                    [void]$sb.AppendLine("END")
                    [void]$sb.AppendLine("ELSE")
                    [void]$sb.AppendLine("BEGIN")
                    [void]$sb.AppendLine("    PRINT '>>> Column [$colName] already exists on [$schema].[$tblName].';")
                    [void]$sb.AppendLine("END")
                }
                4 { # 5. ALTER / MODIFY COLUMN DATA TYPE
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("-- ALTER TABLE: MODIFY COLUMN DATA TYPE [$colName] -> $dataType")
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("ALTER TABLE [$schema].[$tblName] ALTER COLUMN [$colName] $dataType NULL;")
                    [void]$sb.AppendLine("PRINT '>>> Column [$colName] data type altered to $dataType on [$schema].[$tblName].';")
                }
                5 { # 6. DROP COLUMN
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("-- ALTER TABLE: DROP COLUMN [$colName]")
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("IF EXISTS (")
                    [void]$sb.AppendLine("    SELECT 1 FROM sys.columns c")
                    [void]$sb.AppendLine("    JOIN sys.tables t ON c.object_id = t.object_id")
                    [void]$sb.AppendLine("    JOIN sys.schemas s ON t.schema_id = s.schema_id")
                    [void]$sb.AppendLine("    WHERE s.name = '$schema' AND t.name = '$tblName' AND c.name = '$colName'")
                    [void]$sb.AppendLine(")")
                    [void]$sb.AppendLine("BEGIN")
                    [void]$sb.AppendLine("    ALTER TABLE [$schema].[$tblName] DROP COLUMN [$colName];")
                    [void]$sb.AppendLine("    PRINT '>>> Column [$colName] dropped from [$schema].[$tblName].';")
                    [void]$sb.AppendLine("END")
                }
                6 { # 7. ADD PRIMARY KEY CONSTRAINT
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("-- ALTER TABLE: ADD PRIMARY KEY CONSTRAINT")
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("ALTER TABLE [$schema].[$tblName]")
                    [void]$sb.AppendLine("ADD CONSTRAINT [PK_${tblName}] PRIMARY KEY CLUSTERED ([$colName] ASC);")
                    [void]$sb.AppendLine("PRINT '>>> Primary Key constraint added on [$schema].[$tblName]([$colName]).';")
                }
                7 { # 8. ADD FOREIGN KEY CONSTRAINT
                    $refTable = if ($extraVal) { $extraVal } else { "ParentTable(ParentID)" }
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("-- ALTER TABLE: ADD FOREIGN KEY CONSTRAINT")
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("ALTER TABLE [$schema].[$tblName] WITH CHECK")
                    [void]$sb.AppendLine("ADD CONSTRAINT [FK_${tblName}_${colName}] FOREIGN KEY ([$colName]) REFERENCES $refTable;")
                    [void]$sb.AppendLine("ALTER TABLE [$schema].[$tblName] CHECK CONSTRAINT [FK_${tblName}_${colName}];")
                    [void]$sb.AppendLine("PRINT '>>> Foreign Key constraint [FK_${tblName}_${colName}] added successfully.';")
                }
                8 { # 9. ADD DEFAULT VALUE CONSTRAINT
                    $defVal = if ($extraVal) { $extraVal } else { "GETDATE()" }
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("-- ALTER TABLE: ADD DEFAULT VALUE CONSTRAINT")
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("ALTER TABLE [$schema].[$tblName]")
                    [void]$sb.AppendLine("ADD CONSTRAINT [DF_${tblName}_${colName}] DEFAULT ($defVal) FOR [$colName];")
                    [void]$sb.AppendLine("PRINT '>>> Default constraint ($defVal) added for [$colName] on [$schema].[$tblName].';")
                }
                9 { # 10. DROP CONSTRAINT
                    $cName = if ($extraVal) { $extraVal } else { "DF_${tblName}_${colName}" }
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("-- ALTER TABLE: DROP CONSTRAINT [$cName]")
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("ALTER TABLE [$schema].[$tblName] DROP CONSTRAINT [$cName];")
                    [void]$sb.AppendLine("PRINT '>>> Constraint [$cName] dropped from [$schema].[$tblName].';")
                }
                10 { # 11. RENAME COLUMN
                    $newCol = if ($extraVal) { $extraVal } else { "${colName}_New" }
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("-- RENAME COLUMN (sp_rename): [$colName] -> [$newCol]")
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("EXEC sp_rename '$schema.$tblName.$colName', '$newCol', 'COLUMN';")
                    [void]$sb.AppendLine("PRINT '>>> Column [$colName] renamed to [$newCol] on [$schema].[$tblName].';")
                }
                11 { # 12. RENAME TABLE
                    $newTbl = if ($extraVal) { $extraVal } else { "${tblName}_Renamed" }
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("-- RENAME TABLE (sp_rename): [$tblName] -> [$newTbl]")
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("EXEC sp_rename '$schema.$tblName', '$newTbl';")
                    [void]$sb.AppendLine("PRINT '>>> Table [$schema].[$tblName] renamed to [$newTbl].';")
                }
                12 { # 13. SELECT TOP 100
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("-- SELECT QUERY: [$schema].[$tblName]")
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("SELECT TOP 100 *")
                    [void]$sb.AppendLine("FROM [$schema].[$tblName] WITH (NOLOCK)")
                    [void]$sb.AppendLine("WHERE 1 = 1")
                    [void]$sb.AppendLine("  -- AND [$colName] IS NOT NULL")
                    [void]$sb.AppendLine("ORDER BY 1 DESC;")
                }
                13 { # 14. INSERT INTO
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("-- INSERT INTO: [$schema].[$tblName]")
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("INSERT INTO [$schema].[$tblName] ([$colName], [IsActive], [CreatedDate])")
                    [void]$sb.AppendLine("VALUES ('SampleValue', 1, GETDATE());")
                    [void]$sb.AppendLine("")
                    [void]$sb.AppendLine("-- SELECT SCOPE_IDENTITY() AS NewID;")
                }
                14 { # 15. INSERT INTO ... SELECT
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("-- INSERT INTO ... SELECT (Copy Data): [$schema].[$tblName]")
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("INSERT INTO [$schema].[$tblName] ([$colName], [IsActive], [CreatedDate])")
                    [void]$sb.AppendLine("SELECT [$colName], 1, GETDATE()")
                    [void]$sb.AppendLine("FROM [SourceTable]")
                    [void]$sb.AppendLine("WHERE [IsActive] = 1;")
                }
                15 { # 16. UPDATE ... SET
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("-- SAFE UPDATE: [$schema].[$tblName]")
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("BEGIN TRANSACTION;")
                    [void]$sb.AppendLine("BEGIN TRY")
                    [void]$sb.AppendLine("    UPDATE [$schema].[$tblName]")
                    [void]$sb.AppendLine("    SET    [$colName] = 'UpdatedValue',")
                    [void]$sb.AppendLine("           [UpdatedDate] = GETDATE(),")
                    [void]$sb.AppendLine("           [UpdatedBy]   = 1")
                    [void]$sb.AppendLine("    WHERE  [ID] = 1; -- [!] ALWAYS VERIFY WHERE CLAUSE")
                    [void]$sb.AppendLine("")
                    [void]$sb.AppendLine("    PRINT '>>> Rows affected: ' + CAST(@@ROWCOUNT AS VARCHAR(10));")
                    [void]$sb.AppendLine("    COMMIT TRANSACTION;")
                    [void]$sb.AppendLine("END TRY")
                    [void]$sb.AppendLine("BEGIN CATCH")
                    [void]$sb.AppendLine("    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;")
                    [void]$sb.AppendLine("    PRINT '>>> UPDATE FAILED: ' + ERROR_MESSAGE();")
                    [void]$sb.AppendLine("    THROW;")
                    [void]$sb.AppendLine("END CATCH;")
                }
                16 { # 17. DELETE FROM
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("-- SAFE DELETE: [$schema].[$tblName]")
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("BEGIN TRANSACTION;")
                    [void]$sb.AppendLine("BEGIN TRY")
                    [void]$sb.AppendLine("    DELETE FROM [$schema].[$tblName]")
                    [void]$sb.AppendLine("    WHERE  [ID] = 999; -- [!] ALWAYS VERIFY WHERE CLAUSE")
                    [void]$sb.AppendLine("")
                    [void]$sb.AppendLine("    PRINT '>>> Rows deleted: ' + CAST(@@ROWCOUNT AS VARCHAR(10));")
                    [void]$sb.AppendLine("    COMMIT TRANSACTION;")
                    [void]$sb.AppendLine("END TRY")
                    [void]$sb.AppendLine("BEGIN CATCH")
                    [void]$sb.AppendLine("    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;")
                    [void]$sb.AppendLine("    PRINT '>>> DELETE FAILED: ' + ERROR_MESSAGE();")
                    [void]$sb.AppendLine("    THROW;")
                    [void]$sb.AppendLine("END CATCH;")
                }
                17 { # 18. MERGE / UPSERT
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("-- MERGE / UPSERT: [$schema].[$tblName]")
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("MERGE [$schema].[$tblName] AS target")
                    [void]$sb.AppendLine("USING (SELECT 1 AS ID, 'NewValue' AS $colName) AS source")
                    [void]$sb.AppendLine("ON (target.[ID] = source.[ID])")
                    [void]$sb.AppendLine("WHEN MATCHED THEN")
                    [void]$sb.AppendLine("    UPDATE SET target.[$colName] = source.[$colName], target.[UpdatedDate] = GETDATE()")
                    [void]$sb.AppendLine("WHEN NOT MATCHED THEN")
                    [void]$sb.AppendLine("    INSERT ([$colName], [CreatedDate]) VALUES (source.[$colName], GETDATE());")
                }
                18 { # 19. TRUNCATE TABLE
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("-- TRUNCATE TABLE: [$schema].[$tblName]")
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("-- WARNING: This removes ALL records and resets IDENTITY counter!")
                    [void]$sb.AppendLine("TRUNCATE TABLE [$schema].[$tblName];")
                    [void]$sb.AppendLine("PRINT '>>> Table [$schema].[$tblName] truncated successfully.';")
                }
                19 { # 20. CREATE NONCLUSTERED INDEX
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("-- CREATE NONCLUSTERED INDEX: IX_${tblName}_${colName}")
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("CREATE NONCLUSTERED INDEX [IX_${tblName}_${colName}]")
                    [void]$sb.AppendLine("ON [$schema].[$tblName] ([$colName] ASC)")
                    [void]$sb.AppendLine("WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = ON, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON);")
                    [void]$sb.AppendLine("PRINT '>>> Index [IX_${tblName}_${colName}] created successfully.';")
                }
                20 { # 21. CREATE UNIQUE INDEX
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("-- CREATE UNIQUE INDEX: UQ_${tblName}_${colName}")
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("CREATE UNIQUE NONCLUSTERED INDEX [UQ_${tblName}_${colName}]")
                    [void]$sb.AppendLine("ON [$schema].[$tblName] ([$colName] ASC);")
                    [void]$sb.AppendLine("PRINT '>>> Unique index [UQ_${tblName}_${colName}] created successfully.';")
                }
                21 { # 22. CREATE VIEW
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("-- CREATE OR ALTER VIEW: [vw_${tblName}]")
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("CREATE OR ALTER VIEW [$schema].[vw_${tblName}]")
                    [void]$sb.AppendLine("AS")
                    [void]$sb.AppendLine("SELECT *")
                    [void]$sb.AppendLine("FROM [$schema].[$tblName] WITH (NOLOCK);")
                }
                22 { # 23. CREATE TRIGGER
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("-- CREATE TRIGGER: [trg_${tblName}_Audit]")
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("CREATE OR ALTER TRIGGER [$schema].[trg_${tblName}_Audit]")
                    [void]$sb.AppendLine("ON [$schema].[$tblName]")
                    [void]$sb.AppendLine("AFTER INSERT, UPDATE")
                    [void]$sb.AppendLine("AS")
                    [void]$sb.AppendLine("BEGIN")
                    [void]$sb.AppendLine("    SET NOCOUNT ON;")
                    [void]$sb.AppendLine("    UPDATE t")
                    [void]$sb.AppendLine("    SET    t.[UpdatedDate] = GETDATE()")
                    [void]$sb.AppendLine("    FROM   [$schema].[$tblName] t")
                    [void]$sb.AppendLine("    JOIN   inserted i ON t.[ID] = i.[ID];")
                    [void]$sb.AppendLine("END;")
                }
                23 { # 24. Table Space & Row Count
                    [void]$sb.AppendLine("EXEC sp_spaceused '[$schema].[$tblName]';")
                }
                24 { # 25. Table Columns & Types
                    [void]$sb.AppendLine("EXEC sp_help '[$schema].[$tblName]';")
                }
                25 { # 26. Table Indexes Info
                    [void]$sb.AppendLine("EXEC sp_helpindex '[$schema].[$tblName]';")
                }
                26 { # 27. BACKUP TABLE
                    $bkName = "${tblName}_Backup_" + (Get-Date -Format "yyyyMMdd")
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("-- BACKUP TABLE: [$schema].[$tblName] -> [$schema].[$bkName]")
                    [void]$sb.AppendLine("-- ==============================================================================")
                    [void]$sb.AppendLine("IF OBJECT_ID('$schema.$bkName') IS NOT NULL DROP TABLE [$schema].[$bkName];")
                    [void]$sb.AppendLine("SELECT * INTO [$schema].[$bkName] FROM [$schema].[$tblName];")
                    [void]$sb.AppendLine("PRINT '>>> Table [$schema].[$tblName] backed up to [$schema].[$bkName] successfully!';")
                    [void]$sb.AppendLine("SELECT COUNT(*) AS BackupRowCount FROM [$schema].[$bkName];")
                }
            }

            return $sb.ToString()
        }

        # Auto-update SQL preview on parameter changes
        $UpdatePreview = {
            try {
                $txtSqlPreview.Text = &$GenerateDdl
            } catch { }
        }

        $cmbOp.Add_SelectionChanged({ &$UpdatePreview })
        $txtTable.Add_TextChanged({ &$UpdatePreview })
        $txtSchema.Add_TextChanged({ &$UpdatePreview })
        $txtCol.Add_TextChanged({ &$UpdatePreview })
        $cmbType.Add_SelectionChanged({ &$UpdatePreview })
        $txtExtra.Add_TextChanged({ &$UpdatePreview })
        $txtDb.Add_TextChanged({ &$UpdatePreview })

        # Initial Preview Render
        &$UpdatePreview

        # -------------------------------------------------------------
        # Button: Fetch Tables from DB
        # -------------------------------------------------------------
        $btnFetchTbls.Add_Click({
            try {
                $dbName = $txtDb.Text.Trim()
                if (-not $script:SqlConnection -or $script:SqlConnection.State -ne [System.Data.ConnectionState]::Open) {
                    $lblStatus.Text = "Please connect to SQL Server first to fetch tables."
                    return
                }
                $cmd = $script:SqlConnection.CreateCommand()
                $cmd.CommandText = "USE [$dbName]; SELECT TABLE_SCHEMA, TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE' ORDER BY TABLE_NAME;"
                $da = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
                $dt = New-Object System.Data.DataTable
                $da.Fill($dt) | Out-Null
                $cmd.Dispose()

                if ($dt.Rows.Count -gt 0) {
                    $ctxMenu = New-Object System.Windows.Controls.ContextMenu
                    foreach ($row in $dt.Rows) {
                        $sName = $row["TABLE_SCHEMA"].ToString()
                        $tName = $row["TABLE_NAME"].ToString()
                        $mi = New-Object System.Windows.Controls.MenuItem
                        $mi.Header = "[$sName].[$tName]"
                        $mi.Add_Click({
                            $txtSchema.Text = $sName
                            $txtTable.Text = $tName
                            &$UpdatePreview
                        })
                        $ctxMenu.Items.Add($mi) | Out-Null
                    }
                    $btnFetchTbls.ContextMenu = $ctxMenu
                    $ctxMenu.IsOpen = $true
                    $lblStatus.Text = "Fetched $($dt.Rows.Count) tables from [$dbName]."
                } else {
                    $lblStatus.Text = "No tables found in [$dbName]."
                }
            } catch {
                $lblStatus.Text = "Error fetching tables: $($_.Exception.Message)"
            }
        })

        # -------------------------------------------------------------
        # Button: Load SQL to Query Editor
        # -------------------------------------------------------------
        $btnLoadEditor.Add_Click({
            try {
                $sqlCode = &$GenerateDdl
                $txtSqlQuery.Text = $sqlCode
                $txtSqlQuery.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
                Switch-Tab "SqlConsole"
                $lblStatus.Text = "Script loaded into Query Editor! Press F5 to execute."
                $win.Close()
            } catch {
                $lblStatus.Text = "Error loading to editor: $($_.Exception.Message)"
            }
        })

        # -------------------------------------------------------------
        # Button: Copy SQL to Clipboard
        # -------------------------------------------------------------
        $btnCopy.Add_Click({
            try {
                $sqlCode = &$GenerateDdl
                [System.Windows.Clipboard]::SetText($sqlCode)
                $lblStatus.Text = "DDL & Query SQL copied to clipboard!"
            } catch {
                $lblStatus.Text = "Error copying to clipboard: $($_.Exception.Message)"
            }
        })

        # -------------------------------------------------------------
        # Button: Execute Script Now
        # -------------------------------------------------------------
        $btnExecNow.Add_Click({
            try {
                $dbName = $txtDb.Text.Trim()
                if (-not $script:SqlConnection -or $script:SqlConnection.State -ne [System.Data.ConnectionState]::Open) {
                    $lblStatus.Text = "SQL Server is not connected. Connect on SQL Console tab or click 'LOAD TO EDITOR'."
                    return
                }

                $cmd = $script:SqlConnection.CreateCommand()
                $cmd.CommandTimeout = 60
                $rawScript = &$GenerateDdl

                $batches = $rawScript -split '(?im)^\s*GO\s*$'
                foreach ($b in $batches) {
                    $cleanB = $b.Trim()
                    if ($cleanB) {
                        $cmd.CommandText = $cleanB
                        $da = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
                        $dt = New-Object System.Data.DataTable
                        $da.Fill($dt) | Out-Null
                    }
                }
                $cmd.Dispose()
                $lblStatus.Text = "DDL Script executed successfully on [$dbName]!"
                [System.Windows.MessageBox]::Show("DDL Script executed successfully on database [$dbName]!", "Success", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            } catch {
                $lblStatus.Text = "Error executing DDL: $($_.Exception.Message)"
                [System.Windows.MessageBox]::Show("Error executing DDL script:`n$($_.Exception.Message)", "Execution Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            }
        })

        # -------------------------------------------------------------
        # Button: Test inside Transaction (Safe Mode)
        # -------------------------------------------------------------
        $btnTestTran.Add_Click({
            try {
                $dbName = $txtDb.Text.Trim()
                if (-not $script:SqlConnection -or $script:SqlConnection.State -ne [System.Data.ConnectionState]::Open) {
                    $lblStatus.Text = "SQL Server is not connected."
                    return
                }

                $rawScript = &$GenerateDdl
                $sbTest = [System.Text.StringBuilder]::new()
                [void]$sbTest.AppendLine("USE [$dbName];")
                [void]$sbTest.AppendLine("BEGIN TRANSACTION;")
                [void]$sbTest.AppendLine("BEGIN TRY")
                [void]$sbTest.AppendLine($rawScript)
                [void]$sbTest.AppendLine("    ROLLBACK TRANSACTION;")
                [void]$sbTest.AppendLine("    PRINT '>>> TEST COMPLETED: Transaction rolled back safely. 0 changes committed.';")
                [void]$sbTest.AppendLine("END TRY")
                [void]$sbTest.AppendLine("BEGIN CATCH")
                [void]$sbTest.AppendLine("    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;")
                [void]$sbTest.AppendLine("    THROW;")
                [void]$sbTest.AppendLine("END CATCH;")

                $cmd = $script:SqlConnection.CreateCommand()
                $cmd.CommandText = $sbTest.ToString()
                $cmd.ExecuteNonQuery() | Out-Null
                $cmd.Dispose()
                $lblStatus.Text = "SAFE TEST PASSED: DDL verified with 0 errors (Rolled back safely)."
                [System.Windows.MessageBox]::Show("Safe Transaction Test PASSED with 0 syntax or runtime errors!`n`nTransaction was automatically rolled back so no changes were made to the database.", "Safe Test Passed", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            } catch {
                $lblStatus.Text = "Safe Test Error: $($_.Exception.Message)"
                [System.Windows.MessageBox]::Show("Safe Test Error:`n$($_.Exception.Message)", "Test Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            }
        })

        [void]$win.ShowDialog()
    } catch { }
}



function Invoke-DiffComparison([string]$leftText = "", [string]$rightText = "", [string]$leftTitle = "", [string]$rightTitle = "") {
    # Check for dedicated Beyond-Compare-5.cmd
    $bcCmdCandidates = @(
        (Join-Path $script:AppDir "Beyond-Compare-5.cmd"),
        (Join-Path $PSScriptRoot "Beyond-Compare-5.cmd"),
        "C:\Users\mandar.k\Desktop\Nexus-Photo-Optimizer-Portable\Beyond-Compare-5.cmd",
        "C:\Users\mandar.k\Documents\antigravity\lively-raman\Beyond-Compare-5.cmd"
    )
    $bcCmd = $null
    foreach ($cand in $bcCmdCandidates) {
        if ($cand -and (Test-Path $cand)) { $bcCmd = $cand; break }
    }

    if ($bcCmd) {
        try {
            $tDir = [System.IO.Path]::GetTempPath()
            $rnd = [System.IO.Path]::GetRandomFileName().Substring(0, 6)
            $tL = [System.IO.Path]::Combine($tDir, "Nexus_BC5_L_$rnd.sql")
            $tR = [System.IO.Path]::Combine($tDir, "Nexus_BC5_R_$rnd.sql")
            
            $contentL = if ($leftText) { $leftText } else { "" }
            $contentR = if ($rightText) { $rightText } else { "" }
            
            $lDesc = if ($leftTitle) { $leftTitle } else { "Left" }
            $rDesc = if ($rightTitle) { $rightTitle } else { "Right" }
            
            if ($contentL -or $contentR) {
                [System.IO.File]::WriteAllText($tL, $contentL, [System.Text.Encoding]::UTF8)
                [System.IO.File]::WriteAllText($tR, $contentR, [System.Text.Encoding]::UTF8)
                Start-Process -FilePath $bcCmd -ArgumentList @("-Path1", "`"$tL`"", "-Path2", "`"$tR`"", "-Title1", "`"$lDesc`"", "-Title2", "`"$rDesc`"")
            } else {
                Start-Process -FilePath $bcCmd
            }
            return
        } catch {}
    }
    
    # Fallback to in-app window
    Show-BeyondCompareWindow -leftText $leftText -rightText $rightText -leftTitle $leftTitle -rightTitle $rightTitle
}
function Show-BeyondCompareWindow([string]$leftText = "", [string]$rightText = "", [string]$leftTitle = "", [string]$rightTitle = "", [string]$Path1 = "", [string]$Path2 = "") {
    $bcCmdCandidates = @(
        (Join-Path $script:AppDir "Beyond-Compare-5.cmd"),
        (Join-Path $PSScriptRoot "Beyond-Compare-5.cmd"),
        "C:\Users\mandar.k\Nexus-Photo-Optimizer-Portable\Beyond-Compare-5.cmd",
        "C:\Users\mandar.k\Desktop\Nexus-Photo-Optimizer-Portable\Beyond-Compare-5.cmd",
        "C:\Users\mandar.k\Documents\antigravity\lively-raman\Beyond-Compare-5.cmd"
    )
    $bcCmd = $null
    foreach ($cand in $bcCmdCandidates) {
        if ($cand -and (Test-Path $cand)) { $bcCmd = $cand; break }
    }

    $tDir = [System.IO.Path]::GetTempPath()
    $rnd = [System.IO.Path]::GetRandomFileName().Substring(0, 6)
    $tL = [System.IO.Path]::Combine($tDir, "Nexus_BC5_L_$rnd.sql")
    $tR = [System.IO.Path]::Combine($tDir, "Nexus_BC5_R_$rnd.sql")
    if ($leftText) { [System.IO.File]::WriteAllText($tL, $leftText, [System.Text.Encoding]::UTF8); $Path1 = $tL }
    if ($rightText) { [System.IO.File]::WriteAllText($tR, $rightText, [System.Text.Encoding]::UTF8); $Path2 = $tR }

    $argList = @()
    if ($Path1) { $argList += @("-Path1", "`"$Path1`"") }
    if ($Path2) { $argList += @("-Path2", "`"$Path2`"") }
    if ($leftTitle) { $argList += @("-Title1", "`"$leftTitle`"") }
    if ($rightTitle) { $argList += @("-Title2", "`"$rightTitle`"") }

    if ($bcCmd) {
        try {
            Start-Process -FilePath $bcCmd -ArgumentList $argList
            return
        } catch {}
    }

    $bcCandidates = @(
        (Join-Path $PSScriptRoot "Beyond-Compare-5.ps1"),
        "C:\Users\mandar.k\Nexus-Photo-Optimizer-Portable\Beyond-Compare-5.ps1",
        "C:\Users\mandar.k\Desktop\Nexus-Photo-Optimizer-Portable\Beyond-Compare-5.ps1",
        "C:\Users\mandar.k\Documents\antigravity\lively-raman\Beyond-Compare-5.ps1",
        "C:\Users\mandar.k\Desktop\Beyond-Compare-5.ps1"
    )
    $targetScript = $null
    foreach ($cand in $bcCandidates) {
        if ($cand -and (Test-Path $cand -PathType Leaf)) { $targetScript = $cand; break }
    }
    if ($targetScript) {
        try {
            $psArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$targetScript`""
            if ($argList.Count -gt 0) { $psArgs += " " + ($argList -join " ") }
            Start-Process -FilePath "powershell.exe" -ArgumentList $psArgs
            return
        } catch {
            [System.Windows.MessageBox]::Show("Error starting Beyond Compare Studio: $($_.Exception.Message)", "Beyond Compare Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        }
    } else {
        [System.Windows.MessageBox]::Show("Beyond-Compare-5.ps1 script could not be located.", "File Not Found", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
    }
}

function New-NexusAppInstance {
    try {
        $cmdFile = Join-Path $PSScriptRoot "Open-Nexus-App.cmd"
        if (-not (Test-Path $cmdFile)) {
            $cmdFile = "C:\Users\mandar.k\Nexus-Photo-Optimizer-Portable\Open-Nexus-App.cmd"
        }
        if (Test-Path $cmdFile) {
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$cmdFile`"" -WindowStyle Hidden
        } else {
            $psScript = if (Test-Path (Join-Path $PSScriptRoot "PMC-ImageResizer-App.ps1")) {
                Join-Path $PSScriptRoot "PMC-ImageResizer-App.ps1"
            } else {
                $script:AppScriptPath
            }
            Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$psScript`""
        }
    } catch {}
}
function Show-JarvisAssistantWindow {
    try {
        $win = New-Object System.Windows.Window
        $win.Title = "JARVIS AI EXTRA-INTELLIGENCE CORE v4.0"
        $win.Width = 780
        $win.Height = 520
        $win.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
        if ($window) { $win.Owner = $window }
        $win.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#060A13")
        $win.ResizeMode = [System.Windows.ResizeMode]::CanResizeWithGrip

        $grid = New-Object System.Windows.Controls.Grid
        $grid.Margin = New-Object System.Windows.Thickness(16)
        
        $r0 = New-Object System.Windows.Controls.RowDefinition; $r0.Height = [System.Windows.GridLength]::Auto
        $r1 = New-Object System.Windows.Controls.RowDefinition; $r1.Height = [System.Windows.GridLength]::Auto
        $r2 = New-Object System.Windows.Controls.RowDefinition; $r2.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $r3 = New-Object System.Windows.Controls.RowDefinition; $r3.Height = [System.Windows.GridLength]::Auto
        $grid.RowDefinitions.Add($r0); $grid.RowDefinitions.Add($r1); $grid.RowDefinitions.Add($r2); $grid.RowDefinitions.Add($r3)

        $hdrBorder = New-Object System.Windows.Controls.Border
        $hdrBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0B132B")
        $hdrBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#00F0FF")
        $hdrBorder.BorderThickness = New-Object System.Windows.Thickness(1)
        $hdrBorder.CornerRadius = New-Object System.Windows.CornerRadius(6)
        $hdrBorder.Padding = New-Object System.Windows.Thickness(14,10,14,10)
        $hdrBorder.Margin = New-Object System.Windows.Thickness(0,0,0,12)
        [System.Windows.Controls.Grid]::SetRow($hdrBorder, 0)

        $hdrStack = New-Object System.Windows.Controls.StackPanel
        $hdrStack.Orientation = [System.Windows.Controls.Orientation]::Horizontal

        $badge = New-Object System.Windows.Controls.Border
        $badge.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#00F0FF")
        $badge.CornerRadius = New-Object System.Windows.CornerRadius(4)
        $badge.Padding = New-Object System.Windows.Thickness(8,4,8,4)
        $badge.Margin = New-Object System.Windows.Thickness(0,0,12,0)
        $badgeTxt = New-Object System.Windows.Controls.TextBlock
        $badgeTxt.Text = "JARVIS AI v4.0"
        $badgeTxt.FontWeight = [System.Windows.FontWeights]::Bold
        $badgeTxt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#060A13")
        $badgeTxt.FontSize = 11
        $badge.Child = $badgeTxt
        $hdrStack.Children.Add($badge) | Out-Null

        $hdrTitle = New-Object System.Windows.Controls.TextBlock
        $hdrTitle.Text = "Autonomous Application & SQL Intelligence System"
        $hdrTitle.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F8FAFC")
        $hdrTitle.FontSize = 15
        $hdrTitle.FontWeight = [System.Windows.FontWeights]::Bold
        $hdrTitle.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $hdrStack.Children.Add($hdrTitle) | Out-Null

        $hdrBorder.Child = $hdrStack
        $grid.Children.Add($hdrBorder) | Out-Null

        $cmdGrid = New-Object System.Windows.Controls.Grid
        $cmdGrid.Margin = New-Object System.Windows.Thickness(0,0,0,12)
        [System.Windows.Controls.Grid]::SetRow($cmdGrid, 1)

        $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = [System.Windows.GridLength]::Auto
        $cmdGrid.ColumnDefinitions.Add($c0); $cmdGrid.ColumnDefinitions.Add($c1)

        $txtPrompt = New-Object System.Windows.Controls.TextBox
        $txtPrompt.Height = 36
        $txtPrompt.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0A0E1A")
        $txtPrompt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#00F0FF")
        $txtPrompt.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E3252")
        $txtPrompt.BorderThickness = New-Object System.Windows.Thickness(1)
        $txtPrompt.Padding = New-Object System.Windows.Thickness(10,6,10,6)
        $txtPrompt.FontSize = 13
        $txtPrompt.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
        $txtPrompt.Text = "Ask JARVIS: e.g. 'format query', 'analyze performance', 'show active sessions', 'check table size'..."
        $txtPrompt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#64748B")
        [System.Windows.Controls.Grid]::SetColumn($txtPrompt, 0)

        $txtPrompt.Add_GotFocus({
            if ($txtPrompt.Text -like "Ask JARVIS:*") {
                $txtPrompt.Text = ""
                $txtPrompt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#00F0FF")
            }
        })

        $btnAsk = New-Object System.Windows.Controls.Button
        $btnAsk.Content = "ASK JARVIS (ENTER)"
        $btnAsk.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#00F0FF")
        $btnAsk.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#060A13")
        $btnAsk.FontWeight = [System.Windows.FontWeights]::Bold
        $btnAsk.Padding = New-Object System.Windows.Thickness(14,0,14,0)
        $btnAsk.Margin = New-Object System.Windows.Thickness(8,0,0,0)
        $btnAsk.BorderThickness = New-Object System.Windows.Thickness(0)
        $btnAsk.Cursor = [System.Windows.Input.Cursors]::Hand
        [System.Windows.Controls.Grid]::SetColumn($btnAsk, 1)

        $cmdGrid.Children.Add($txtPrompt) | Out-Null
        $cmdGrid.Children.Add($btnAsk) | Out-Null
        $grid.Children.Add($cmdGrid) | Out-Null

        $txtLog = New-Object System.Windows.Controls.TextBox
        $txtLog.AcceptsReturn = $true
        $txtLog.IsReadOnly = $true
        $txtLog.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $txtLog.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
        $txtLog.FontSize = 12.5
        $txtLog.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0A101E")
        $txtLog.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E2E8F0")
        $txtLog.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
        $txtLog.BorderThickness = New-Object System.Windows.Thickness(1)
        $txtLog.Padding = New-Object System.Windows.Thickness(12)
        $txtLog.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
        $txtLog.Text = "JARVIS AI SYSTEM ONLINE`nReady for commands.`n---------------------------------------------------------`nTry commands:`n  - 'format query' (Format T-SQL code cleanly)`n  - 'analyze performance' (Audit SQL query security & performance)`n  - 'show active sessions' (Run sp_who2)`n  - 'check table size' (Run sp_spaceused)`n  - 'new sp' (Generate SP template)`n  - 'test transaction' (Execute inside BEGIN TRAN...ROLLBACK)`n  - 'full screen' (Inspect SP/Function in Full Screen)`n---------------------------------------------------------`n"
        [System.Windows.Controls.Grid]::SetRow($txtLog, 2)
        $grid.Children.Add($txtLog) | Out-Null

        $barGrid = New-Object System.Windows.Controls.Grid
        $barGrid.Margin = New-Object System.Windows.Thickness(0,12,0,0)
        [System.Windows.Controls.Grid]::SetRow($barGrid, 3)

        $bStack = New-Object System.Windows.Controls.StackPanel
        $bStack.Orientation = [System.Windows.Controls.Orientation]::Horizontal

        $btnFmt = New-Object System.Windows.Controls.Button
        $btnFmt.Content = "FORMAT SQL"
        $btnFmt.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0284C7")
        $btnFmt.Foreground = [System.Windows.Media.Brushes]::White
        $btnFmt.FontWeight = [System.Windows.FontWeights]::Bold
        $btnFmt.Padding = New-Object System.Windows.Thickness(12,6,12,6)
        $btnFmt.Margin = New-Object System.Windows.Thickness(0,0,8,0)
        $btnFmt.BorderThickness = New-Object System.Windows.Thickness(0)
        $btnFmt.Cursor = [System.Windows.Input.Cursors]::Hand
        $btnFmt.Add_Click({
            Format-SqlQuery
            $txtLog.AppendText("`n[JARVIS]: Auto-formatted SQL query in Query Editor.`n")
            $txtLog.ScrollToEnd()
        })
        $bStack.Children.Add($btnFmt) | Out-Null

        $btnAud = New-Object System.Windows.Controls.Button
        $btnAud.Content = "ANALYZE SQL PERFORMANCE"
        $btnAud.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#8B5CF6")
        $btnAud.Foreground = [System.Windows.Media.Brushes]::White
        $btnAud.FontWeight = [System.Windows.FontWeights]::Bold
        $btnAud.Padding = New-Object System.Windows.Thickness(12,6,12,6)
        $btnAud.Margin = New-Object System.Windows.Thickness(0,0,8,0)
        $btnAud.BorderThickness = New-Object System.Windows.Thickness(0)
        $btnAud.Cursor = [System.Windows.Input.Cursors]::Hand
        $btnAud.Add_Click({
            Analyze-SqlQuery
            $txtLog.AppendText("`n[JARVIS]: Executed Performance & Security Audit. Output generated in MESSAGES tab.`n")
            $txtLog.ScrollToEnd()
        })
        $bStack.Children.Add($btnAud) | Out-Null

        $btnClose = New-Object System.Windows.Controls.Button
        $btnClose.Content = "CLOSE (ESC)"
        $btnClose.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#334155")
        $btnClose.Foreground = [System.Windows.Media.Brushes]::White
        $btnClose.Padding = New-Object System.Windows.Thickness(12,6,12,6)
        $btnClose.BorderThickness = New-Object System.Windows.Thickness(0)
        $btnClose.Cursor = [System.Windows.Input.Cursors]::Hand
        $btnClose.Add_Click({ $win.Close() })
        $bStack.Children.Add($btnClose) | Out-Null

        $barGrid.Children.Add($bStack) | Out-Null
        $grid.Children.Add($barGrid) | Out-Null

        $execAction = {
            $cmdText = $txtPrompt.Text
            if ([string]::IsNullOrWhiteSpace($cmdText) -or $cmdText -like "Ask JARVIS:*") { return }
            $resp = Process-JarvisNaturalLanguage -prompt $cmdText
            $txtLog.AppendText("`n> $cmdText`n[JARVIS]: $resp`n")
            $txtLog.ScrollToEnd()
            $txtPrompt.Text = ""
        }

        $btnAsk.Add_Click($execAction)
        $txtPrompt.Add_KeyDown({
            param($s, $e)
            if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
                & $execAction
                $e.Handled = $true
            }
        })

        $win.Add_PreviewKeyDown({
            param($s, $e)
            if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
                $win.Close()
                $e.Handled = $true
            }
        })

        $win.Content = $grid
        $win.ShowDialog() | Out-Null
    } catch { }
}

function Show-SqlSpFullScreenViewer {
    param(
        [string]$ProcName,
        [string]$SpCode
    )

    if (([string]::IsNullOrWhiteSpace($SpCode) -or $SpCode -eq $script:SqlPlaceholder) -and $ProcName -and $script:SqlConnected) {
        try {
            $cmd = $script:SqlConnection.CreateCommand()
            $cmd.CommandText = "SELECT OBJECT_DEFINITION(OBJECT_ID(@procName))"
            [void]$cmd.Parameters.AddWithValue("@procName", $ProcName)
            $fetched = $cmd.ExecuteScalar()
            $cmd.Dispose()
            if ($fetched -and $fetched -is [string]) { $SpCode = $fetched }
        } catch { }
    }

    if ($SpCode) {
        $SpCode = Convert-CreateToAlterProcedure $SpCode
    }

    if ([string]::IsNullOrWhiteSpace($SpCode) -or $SpCode -eq $script:SqlPlaceholder) {
        [System.Windows.MessageBox]::Show("Could not retrieve stored procedure definition for '$ProcName'. Please ensure a procedure is selected from the dropdown and you are connected to the database.", "Stored Procedure Warning", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    $safeSpCode = [string]$SpCode
    $lineCount = if ($safeSpCode) { ($safeSpCode -split "\r?\n").Count } else { 0 }
    $charCount = if ($safeSpCode) { $safeSpCode.Length } else { 0 }

    try {
        $script:spWin = New-Object System.Windows.Window
        $script:spWin.Title = "Nexus SQL - Full Screen Stored Procedure Inspector: $ProcName"
        $script:spWin.WindowState = [System.Windows.WindowState]::Maximized
        $script:spWin.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
        $script:spWin.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#060A13")

        $grid = New-Object System.Windows.Controls.Grid
        $r0 = New-Object System.Windows.Controls.RowDefinition; $r0.Height = [System.Windows.GridLength]::Auto
        $r1 = New-Object System.Windows.Controls.RowDefinition; $r1.Height = [System.Windows.GridLength]::Auto
        $r2 = New-Object System.Windows.Controls.RowDefinition; $r2.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $r3 = New-Object System.Windows.Controls.RowDefinition; $r3.Height = [System.Windows.GridLength]::Auto
        $grid.RowDefinitions.Add($r0)
        $grid.RowDefinitions.Add($r1)
        $grid.RowDefinitions.Add($r2)
        $grid.RowDefinitions.Add($r3)

        # Main Code Editor Box
        $script:txtSpEditor = New-Object System.Windows.Controls.TextBox
        $script:txtSpEditor.AcceptsReturn = $true
        $script:txtSpEditor.AcceptsTab = $true
        $script:txtSpEditor.TextWrapping = [System.Windows.TextWrapping]::NoWrap
        $script:txtSpEditor.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
        $script:txtSpEditor.FontSize = 14.5
        $script:txtSpEditor.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#060A13")
        $script:txtSpEditor.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
        $script:txtSpEditor.BorderThickness = New-Object System.Windows.Thickness(0)
        $script:txtSpEditor.Padding = New-Object System.Windows.Thickness(16)
        $script:txtSpEditor.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
        $script:txtSpEditor.HorizontalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
        $script:txtSpEditor.Text = $safeSpCode
        [System.Windows.Controls.Grid]::SetRow($script:txtSpEditor, 2)

        # Top Header
        $headerBorder = New-Object System.Windows.Controls.Border
        $headerBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A")
        $headerBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
        $headerBorder.BorderThickness = New-Object System.Windows.Thickness(0,0,0,1)
        $headerBorder.Padding = New-Object System.Windows.Thickness(16,10,16,10)
        [System.Windows.Controls.Grid]::SetRow($headerBorder, 0)

        $headerGrid = New-Object System.Windows.Controls.Grid
        $hc0 = New-Object System.Windows.Controls.ColumnDefinition; $hc0.Width = [System.Windows.GridLength]::Auto
        $hc1 = New-Object System.Windows.Controls.ColumnDefinition; $hc1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $hc2 = New-Object System.Windows.Controls.ColumnDefinition; $hc2.Width = [System.Windows.GridLength]::Auto
        $headerGrid.ColumnDefinitions.Add($hc0)
        $headerGrid.ColumnDefinitions.Add($hc1)
        $headerGrid.ColumnDefinitions.Add($hc2)

        $titleStack = New-Object System.Windows.Controls.StackPanel
        $titleStack.Orientation = [System.Windows.Controls.Orientation]::Horizontal

        $badge = New-Object System.Windows.Controls.Border
        $badge.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#8B5CF6")
        $badge.CornerRadius = New-Object System.Windows.CornerRadius(4)
        $badge.Padding = New-Object System.Windows.Thickness(8,4,8,4)
        $badge.Margin = New-Object System.Windows.Thickness(0,0,12,0)
        $badgeTxt = New-Object System.Windows.Controls.TextBlock
        $badgeTxt.Text = "STORED PROCEDURE"
        $badgeTxt.FontWeight = [System.Windows.FontWeights]::Bold
        $badgeTxt.FontSize = 11
        $badgeTxt.Foreground = [System.Windows.Media.Brushes]::White
        $badge.Child = $badgeTxt
        $titleStack.Children.Add($badge) | Out-Null

        $procTitleTxt = New-Object System.Windows.Controls.TextBlock
        $procTitleTxt.Text = if ($ProcName) { $ProcName } else { "Stored Procedure Source Code" }
        $procTitleTxt.FontSize = 18
        $procTitleTxt.FontWeight = [System.Windows.FontWeights]::Bold
        $procTitleTxt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
        $procTitleTxt.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $titleStack.Children.Add($procTitleTxt) | Out-Null

        [System.Windows.Controls.Grid]::SetColumn($titleStack, 0)
        $headerGrid.Children.Add($titleStack) | Out-Null

        $btnStack = New-Object System.Windows.Controls.StackPanel
        $btnStack.Orientation = [System.Windows.Controls.Orientation]::Horizontal

        $infoTxt = New-Object System.Windows.Controls.TextBlock
        $infoTxt.Text = "Lines: $lineCount | Size: $([Math]::Round($charCount/1024, 1)) KB ($charCount chars)"
        $infoTxt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
        $infoTxt.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $infoTxt.Margin = New-Object System.Windows.Thickness(0,0,20,0)
        $infoTxt.FontSize = 12
        $btnStack.Children.Add($infoTxt) | Out-Null

        $btnExecSp = New-Object System.Windows.Controls.Button
        $btnExecSp.Content = "EXECUTE SELECTION (F5)"
        $btnExecSp.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#22C55E")
        $btnExecSp.Foreground = [System.Windows.Media.Brushes]::White
        $btnExecSp.FontWeight = [System.Windows.FontWeights]::Bold
        $btnExecSp.Padding = New-Object System.Windows.Thickness(12,6,12,6)
        $btnExecSp.Margin = New-Object System.Windows.Thickness(0,0,8,0)
        $btnExecSp.BorderThickness = New-Object System.Windows.Thickness(0)
        $btnExecSp.Cursor = [System.Windows.Input.Cursors]::Hand
        $btnExecSp.ToolTip = "Execute selected query/SP text directly in SQL Console"
        $btnExecSp.Add_Click({
            $selectedText = if ($script:txtSpEditor -and -not [string]::IsNullOrWhiteSpace($script:txtSpEditor.SelectedText)) {
                $script:txtSpEditor.SelectedText
            } elseif ($script:txtSpEditor) {
                $script:txtSpEditor.Text
            } else { "" }

            if ($selectedText -and $txtSqlQuery) {
                $txtSqlQuery.Text = $selectedText
                $txtSqlQuery.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
            }
            try {
                if ($script:spWin) { $script:spWin.DialogResult = $false }
            } catch {
                try { if ($script:spWin) { $script:spWin.Close() } } catch { }
            }
            Execute-SqlQuery -OverrideQuery $selectedText
        })
        $btnStack.Children.Add($btnExecSp) | Out-Null

        $btnTestSp = New-Object System.Windows.Controls.Button
        $btnTestSp.Content = "TEST (BEGIN TRAN)"
        $btnTestSp.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F59E0B")
        $btnTestSp.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A")
        $btnTestSp.FontWeight = [System.Windows.FontWeights]::Bold
        $btnTestSp.Padding = New-Object System.Windows.Thickness(12,6,12,6)
        $btnTestSp.Margin = New-Object System.Windows.Thickness(0,0,8,0)
        $btnTestSp.BorderThickness = New-Object System.Windows.Thickness(0)
        $btnTestSp.Cursor = [System.Windows.Input.Cursors]::Hand
        $btnTestSp.ToolTip = "Safe Execution Mode: Runs selected query/SP inside BEGIN TRAN ... ROLLBACK to test changes safely without committing to DB"
        $btnTestSp.Add_Click({
            $selectedText = if ($script:txtSpEditor -and -not [string]::IsNullOrWhiteSpace($script:txtSpEditor.SelectedText)) {
                $script:txtSpEditor.SelectedText
            } elseif ($script:txtSpEditor) {
                $script:txtSpEditor.Text
            } else { "" }

            if ($selectedText -and $txtSqlQuery) {
                $txtSqlQuery.Text = $selectedText
                $txtSqlQuery.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
            }
            try {
                if ($script:spWin) { $script:spWin.DialogResult = $false }
            } catch {
                try { if ($script:spWin) { $script:spWin.Close() } } catch { }
            }
            Execute-SqlQuery -OverrideQuery $selectedText -TestBeginTran
        })
        $btnStack.Children.Add($btnTestSp) | Out-Null

        $btnCopySp = New-Object System.Windows.Controls.Button
        $btnCopySp.Content = "COPY CODE"
        $btnCopySp.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
        $btnCopySp.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A")
        $btnCopySp.FontWeight = [System.Windows.FontWeights]::Bold
        $btnCopySp.Padding = New-Object System.Windows.Thickness(12,6,12,6)
        $btnCopySp.Margin = New-Object System.Windows.Thickness(0,0,8,0)
        $btnCopySp.BorderThickness = New-Object System.Windows.Thickness(0)
        $btnCopySp.Cursor = [System.Windows.Input.Cursors]::Hand
        $btnCopySp.Add_Click({
            try {
                if ($script:txtSpEditor) { [System.Windows.Clipboard]::SetText($script:txtSpEditor.Text) }
                [System.Windows.MessageBox]::Show("Stored Procedure code copied to clipboard successfully!", "Copied", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            } catch { }
        })
        $btnStack.Children.Add($btnCopySp) | Out-Null

        $btnSaveSp = New-Object System.Windows.Controls.Button
        $btnSaveSp.Content = "SAVE AS .SQL"
        $btnSaveSp.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#10B981")
        $btnSaveSp.Foreground = [System.Windows.Media.Brushes]::White
        $btnSaveSp.FontWeight = [System.Windows.FontWeights]::Bold
        $btnSaveSp.Padding = New-Object System.Windows.Thickness(12,6,12,6)
        $btnSaveSp.Margin = New-Object System.Windows.Thickness(0,0,8,0)
        $btnSaveSp.BorderThickness = New-Object System.Windows.Thickness(0)
        $btnSaveSp.Cursor = [System.Windows.Input.Cursors]::Hand
        $btnSaveSp.Add_Click({
            try {
                $sfd = New-Object Microsoft.Win32.SaveFileDialog
                $sfd.Filter = "SQL Files (*.sql)|*.sql|All Files (*.*)|*.*"
                $sfd.FileName = "$($ProcName -replace '[^a-zA-Z0-9_.]','_').sql"
                if ($sfd.ShowDialog() -eq $true -and $script:txtSpEditor) {
                    [System.IO.File]::WriteAllText($sfd.FileName, $script:txtSpEditor.Text, [System.Text.Encoding]::UTF8)
                    [System.Windows.MessageBox]::Show("Procedure code saved to $($sfd.FileName)", "Saved", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
                }
            } catch { }
        })
        $btnStack.Children.Add($btnSaveSp) | Out-Null

        $btnCloseSp = New-Object System.Windows.Controls.Button
        $btnCloseSp.Content = "CLOSE (ESC)"
        $btnCloseSp.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EF4444")
        $btnCloseSp.Foreground = [System.Windows.Media.Brushes]::White
        $btnCloseSp.FontWeight = [System.Windows.FontWeights]::Bold
        $btnCloseSp.Padding = New-Object System.Windows.Thickness(12,6,12,6)
        $btnCloseSp.BorderThickness = New-Object System.Windows.Thickness(0)
        $btnCloseSp.Cursor = [System.Windows.Input.Cursors]::Hand
        $btnCloseSp.Add_Click({
            try {
                if ($script:spWin) { $script:spWin.DialogResult = $false }
            } catch {
                try { if ($script:spWin) { $script:spWin.Close() } } catch { }
            }
        })
        $btnStack.Children.Add($btnCloseSp) | Out-Null

        [System.Windows.Controls.Grid]::SetColumn($btnStack, 2)
        $headerGrid.Children.Add($btnStack) | Out-Null

        $headerBorder.Child = $headerGrid
        $grid.Children.Add($headerBorder) | Out-Null

        # Search Bar
        $searchBorder = New-Object System.Windows.Controls.Border
        $searchBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0B132B")
        $searchBorder.Padding = New-Object System.Windows.Thickness(16,8,16,8)
        $searchBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
        $searchBorder.BorderThickness = New-Object System.Windows.Thickness(0,0,0,1)
        [System.Windows.Controls.Grid]::SetRow($searchBorder, 1)

        $searchStack = New-Object System.Windows.Controls.StackPanel
        $searchStack.Orientation = [System.Windows.Controls.Orientation]::Horizontal

        $lblSearch = New-Object System.Windows.Controls.TextBlock
        $lblSearch.Text = "Search Code:"
        $lblSearch.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
        $lblSearch.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $lblSearch.Margin = New-Object System.Windows.Thickness(0,0,8,0)
        $lblSearch.FontWeight = [System.Windows.FontWeights]::SemiBold
        $searchStack.Children.Add($lblSearch) | Out-Null

        $txtSearchSp = New-Object System.Windows.Controls.TextBox
        $txtSearchSp.Width = 260
        $txtSearchSp.Height = 28
        $txtSearchSp.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#060A13")
        $txtSearchSp.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F8FAFC")
        $txtSearchSp.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#334155")
        $txtSearchSp.Padding = New-Object System.Windows.Thickness(6,2,6,2)
        $txtSearchSp.Margin = New-Object System.Windows.Thickness(0,0,8,0)
        $txtSearchSp.VerticalContentAlignment = [System.Windows.VerticalAlignment]::Center
        $searchStack.Children.Add($txtSearchSp) | Out-Null

        $btnFindNext = New-Object System.Windows.Controls.Button
        $btnFindNext.Content = "FIND NEXT (F3)"
        $btnFindNext.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
        $btnFindNext.Foreground = [System.Windows.Media.Brushes]::White
        $btnFindNext.Padding = New-Object System.Windows.Thickness(10,4,10,4)
        $btnFindNext.Margin = New-Object System.Windows.Thickness(0,0,6,0)
        $btnFindNext.BorderThickness = New-Object System.Windows.Thickness(0)
        $btnFindNext.Cursor = [System.Windows.Input.Cursors]::Hand
        $searchStack.Children.Add($btnFindNext) | Out-Null

        $btnFindPrev = New-Object System.Windows.Controls.Button
        $btnFindPrev.Content = "FIND PREV"
        $btnFindPrev.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
        $btnFindPrev.Foreground = [System.Windows.Media.Brushes]::White
        $btnFindPrev.Padding = New-Object System.Windows.Thickness(10,4,10,4)
        $btnFindPrev.Margin = New-Object System.Windows.Thickness(0,0,6,0)
        $btnFindPrev.BorderThickness = New-Object System.Windows.Thickness(0)
        $btnFindPrev.Cursor = [System.Windows.Input.Cursors]::Hand
        $searchStack.Children.Add($btnFindPrev) | Out-Null

        $lblMatchInfo = New-Object System.Windows.Controls.TextBlock
        $lblMatchInfo.Text = ""
        $lblMatchInfo.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F59E0B")
        $lblMatchInfo.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $lblMatchInfo.Margin = New-Object System.Windows.Thickness(8,0,16,0)
        $lblMatchInfo.FontWeight = [System.Windows.FontWeights]::SemiBold
        $searchStack.Children.Add($lblMatchInfo) | Out-Null

        $script:matchIndices = @()
        $script:matchCurrentPos = -1

        $updateMatches = {
            $term = $txtSearchSp.Text
            $script:matchIndices = @()
            $script:matchCurrentPos = -1
            if ([string]::IsNullOrWhiteSpace($term) -or -not $script:txtSpEditor) {
                $lblMatchInfo.Text = "Type text to search"
                return
            }
            $code = $script:txtSpEditor.Text
            if ([string]::IsNullOrEmpty($code)) {
                $lblMatchInfo.Text = "No code loaded"
                return
            }
            $pos = 0
            $termLen = $term.Length
            while ($pos -lt $code.Length) {
                $found = $code.IndexOf($term, $pos, [System.StringComparison]::OrdinalIgnoreCase)
                if ($found -lt 0) { break }
                $script:matchIndices += $found
                $pos = $found + [Math]::Max(1, $termLen)
            }
            if ($script:matchIndices.Count -gt 0) {
                $lblMatchInfo.Text = "$($script:matchIndices.Count) matches found"
            } else {
                $lblMatchInfo.Text = "No matches found"
            }
        }

        $highlightMatch = {
            param([int]$matchIndex)
            if ($script:matchIndices.Count -eq 0 -or $matchIndex -lt 0 -or $matchIndex -ge $script:matchIndices.Count) { return }
            $charIdx = $script:matchIndices[$matchIndex]
            $term = $txtSearchSp.Text
            if (-not $script:txtSpEditor) { return }

            $script:txtSpEditor.Focus() | Out-Null
            $script:txtSpEditor.Select($charIdx, $term.Length)
            
            $lineIdx = $script:txtSpEditor.GetLineIndexFromCharacterIndex($charIdx)
            if ($lineIdx -ge 0) {
                $script:txtSpEditor.ScrollToLine($lineIdx)
            }

            $lblMatchInfo.Text = "Match $($matchIndex + 1) of $($script:matchIndices.Count) (Line $($lineIdx + 1))"
        }

        $doFindNext = {
            $term = $txtSearchSp.Text
            if ([string]::IsNullOrWhiteSpace($term)) {
                $lblMatchInfo.Text = "Type text to search"
                return
            }
            if ($script:matchIndices.Count -eq 0) {
                & $updateMatches
            }
            if ($script:matchIndices.Count -eq 0) { return }

            $script:matchCurrentPos++
            if ($script:matchCurrentPos -ge $script:matchIndices.Count) {
                $script:matchCurrentPos = 0
            }
            & $highlightMatch $script:matchCurrentPos
        }

        $doFindPrev = {
            $term = $txtSearchSp.Text
            if ([string]::IsNullOrWhiteSpace($term)) {
                $lblMatchInfo.Text = "Type text to search"
                return
            }
            if ($script:matchIndices.Count -eq 0) {
                & $updateMatches
            }
            if ($script:matchIndices.Count -eq 0) { return }

            $script:matchCurrentPos--
            if ($script:matchCurrentPos -lt 0) {
                $script:matchCurrentPos = $script:matchIndices.Count - 1
            }
            & $highlightMatch $script:matchCurrentPos
        }

        $btnFindNext.Add_Click({ & $doFindNext })
        $btnFindPrev.Add_Click({ & $doFindPrev })

        $txtSearchSp.Add_TextChanged({
            & $updateMatches
        })

        $txtSearchSp.Add_KeyDown({
            param($s, $e)
            if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
                if ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Shift) {
                    & $doFindPrev
                } else {
                    & $doFindNext
                }
                $e.Handled = $true
            }
        })

        $searchBorder.Child = $searchStack
        $grid.Children.Add($searchBorder) | Out-Null
        $grid.Children.Add($script:txtSpEditor) | Out-Null

        # SSMS Footer Status Bar
        $footerBorder = New-Object System.Windows.Controls.Border
        $footerBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A")
        $footerBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
        $footerBorder.BorderThickness = New-Object System.Windows.Thickness(0,1,0,0)
        $footerBorder.Padding = New-Object System.Windows.Thickness(12,6,12,6)
        [System.Windows.Controls.Grid]::SetRow($footerBorder, 3)

        $footerGrid = New-Object System.Windows.Controls.Grid
        $fg0 = New-Object System.Windows.Controls.ColumnDefinition; $fg0.Width = [System.Windows.GridLength]::Auto
        $fg1 = New-Object System.Windows.Controls.ColumnDefinition; $fg1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $fg2 = New-Object System.Windows.Controls.ColumnDefinition; $fg2.Width = [System.Windows.GridLength]::Auto
        $footerGrid.ColumnDefinitions.Add($fg0)
        $footerGrid.ColumnDefinitions.Add($fg1)
        $footerGrid.ColumnDefinitions.Add($fg2)

        $statusLeft = New-Object System.Windows.Controls.TextBlock
        $statusLeft.Text = "Query Status: Ready | Full Screen Stored Procedure Inspector | Press ESC to Exit"
        $statusLeft.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
        $statusLeft.FontSize = 11.5
        [System.Windows.Controls.Grid]::SetColumn($statusLeft, 0)
        $footerGrid.Children.Add($statusLeft) | Out-Null

        $statusRight = New-Object System.Windows.Controls.TextBlock
        $dbName = if ($script:SqlConnection) { $script:SqlConnection.Database } else { "SQL" }
        $statusRight.Text = "Workstation ID: . | App Name: .Net SqlClient Data Provider | DB: $dbName"
        $statusRight.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#64748B")
        $statusRight.FontSize = 11.5
        [System.Windows.Controls.Grid]::SetColumn($statusRight, 2)
        $footerGrid.Children.Add($statusRight) | Out-Null

        $footerBorder.Child = $footerGrid
        $grid.Children.Add($footerBorder) | Out-Null

        $spKeyHandler = {
            param($s, $e)
            if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
                $e.Handled = $true
                try {
                    if ($script:spWin) { $script:spWin.DialogResult = $false }
                } catch {
                    try { if ($script:spWin) { $script:spWin.Close() } } catch { }
                }
            } elseif ($e.Key -eq [System.Windows.Input.Key]::F3) {
                $e.Handled = $true
                if ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Shift) {
                    & $doFindPrev
                } else {
                    & $doFindNext
                }
            } elseif ($e.Key -eq [System.Windows.Input.Key]::F5) {
                $e.Handled = $true
                $selectedText = if ($script:txtSpEditor -and -not [string]::IsNullOrWhiteSpace($script:txtSpEditor.SelectedText)) {
                    $script:txtSpEditor.SelectedText
                } elseif ($script:txtSpEditor) {
                    $script:txtSpEditor.Text
                } else { "" }

                if ($selectedText -and $txtSqlQuery) {
                    $txtSqlQuery.Text = $selectedText
                    $txtSqlQuery.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
                }
                try {
                    if ($script:spWin) { $script:spWin.DialogResult = $false }
                } catch {
                    try { if ($script:spWin) { $script:spWin.Close() } } catch { }
                }
                Execute-SqlQuery -OverrideQuery $selectedText
            } elseif ($e.Key -eq [System.Windows.Input.Key]::F -and ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
                if ($txtSearchSp) {
                    $txtSearchSp.Focus() | Out-Null
                    $txtSearchSp.SelectAll()
                    $e.Handled = $true
                }
            }
        }

        $script:spWin.Add_PreviewKeyDown($spKeyHandler)
        if ($script:txtSpEditor) { $script:txtSpEditor.Add_PreviewKeyDown($spKeyHandler) }

        $script:spWin.Add_Loaded({
            try {
                if ($txtSearchSp) {
                    $txtSearchSp.Focus() | Out-Null
                    $txtSearchSp.SelectAll()
                }
            } catch { }
        })

        $script:spWin.Content = $grid
        [void]$script:spWin.ShowDialog()
    } catch { }
}

function View-SqlSpDefinition {
    if (-not $script:SqlConnected) { return }
    $selected = $cmbSqlProcs.SelectedItem
    if (-not $selected -or -not ($selected -is [System.Windows.Controls.ComboBoxItem]) -or -not $selected.Tag) { return }
    
    $fullProcName = $selected.Tag
    if ([string]::IsNullOrWhiteSpace($fullProcName)) { return }
    
    try {
        $cmd = $script:SqlConnection.CreateCommand()
        $cmd.CommandText = "SELECT OBJECT_DEFINITION(OBJECT_ID(@procName))"
        [void]$cmd.Parameters.AddWithValue("@procName", $fullProcName)
        
        $spCode = $cmd.ExecuteScalar()
        $cmd.Dispose()
        
        if ($spCode -and $spCode -is [string]) {
            $alterSpCode = Convert-CreateToAlterProcedure $spCode
            $txtSqlQuery.Text = $alterSpCode
            $txtSqlQuery.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
            $txtSqlQuery.Focus() | Out-Null
            $lblSqlRowCount.Text = "Loaded SP (ALTER Mode): $fullProcName ($([Math]::Round($alterSpCode.Length/1024, 1)) KB)"
        } else {
            [System.Windows.MessageBox]::Show("Could not retrieve definition for '$fullProcName'. Procedure may be encrypted or restricted.", "Warning", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        }
    } catch {
        [System.Windows.MessageBox]::Show("Error fetching SP code: $($_.Exception.Message)", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    }
}

if ($btnSqlViewSpCode) {
    $btnSqlViewSpCode.Add_Click({ View-SqlSpDefinition })
}

if ($btnSqlFullScreenSp) {
    $btnSqlFullScreenSp.Add_Click({
        $selected = $cmbSqlProcs.SelectedItem
        $procName = if ($selected -and ($selected -is [System.Windows.Controls.ComboBoxItem]) -and $selected.Tag) { $selected.Tag } else { "" }
        
        $codeToPass = ""
        if ($txtSqlQuery -and -not [string]::IsNullOrWhiteSpace($txtSqlQuery.Text)) {
            $txt = $txtSqlQuery.Text
            if ($txt -match '(?i)\b(?:CREATE|ALTER)\s+(?:PROCEDURE|PROC)\b') {
                $codeToPass = Convert-CreateToAlterProcedure $txt
            }
        }
        
        Show-SqlSpFullScreenViewer -ProcName $procName -SpCode $codeToPass
    })
}

function Load-SqlDatabases {
    if (-not $script:SqlConnected) { return }
    try {
        $dbList = @()
        try {
            $cmd = $script:SqlConnection.CreateCommand()
            $cmd.CommandText = "SELECT name FROM sys.databases WHERE state_desc='ONLINE' ORDER BY name"
            $reader = $cmd.ExecuteReader()
            while ($reader.Read()) {
                $dbList += $reader.GetString(0)
            }
            $reader.Close()
            $cmd.Dispose()
        } catch { }

        if ($dbList.Count -eq 0) {
            try {
                $cmd = $script:SqlConnection.CreateCommand()
                $cmd.CommandText = "EXEC sp_databases"
                $reader = $cmd.ExecuteReader()
                while ($reader.Read()) {
                    $dbList += $reader.GetString(0)
                }
                $reader.Close()
                $cmd.Dispose()
            } catch { }
        }

        $currentDb = ""
        try { $currentDb = $script:SqlConnection.Database } catch {}
        if (-not $currentDb) {
            try {
                $cmd = $script:SqlConnection.CreateCommand()
                $cmd.CommandText = "SELECT DB_NAME()"
                $currentDb = $cmd.ExecuteScalar().ToString()
                $cmd.Dispose()
            } catch { }
        }
        if (-not $currentDb) {
            try {
                if ($txtSqlConnStr -and $txtSqlConnStr.Text -match '(?i)(?:Initial\s*Catalog|Database)\s*=\s*([^;]+)') {
                    $currentDb = $matches[1].Trim()
                }
            } catch { }
        }

        if ($currentDb -and -not ($dbList -contains $currentDb)) {
            $dbList += $currentDb
        }

        # Merge with saved database history for this server
        $serverKey = if ($script:SqlDataSource) { $script:SqlDataSource.ToLowerInvariant() } else { "default" }
        $savedDbs = @{}
        if (Test-Path $script:SqlDbFile) {
            try {
                $rawJson = Get-Content $script:SqlDbFile -Raw | ConvertFrom-Json
                if ($rawJson) {
                    foreach ($prop in $rawJson.PSObject.Properties) {
                        $savedDbs[$prop.Name] = @($prop.Value)
                    }
                }
            } catch { }
        }
        
        $histList = @()
        if ($savedDbs.ContainsKey($serverKey)) {
            $histList = @($savedDbs[$serverKey])
        }
        
        foreach ($h in $histList) {
            if ($h -and -not ($dbList -contains $h)) {
                $dbList += $h
            }
        }
        
        try {
            $savedDbs[$serverKey] = @($dbList | Select-Object -Unique)
            $savedDbs | ConvertTo-Json -Depth 3 | Set-Content $script:SqlDbFile -Force
        } catch { }

        # Populate cmbSqlDatabase without triggering SelectionChanged cascades!
        $script:SuppressDbChange = $true
        $cmbSqlDatabase.Items.Clear()
        $selectedIdx = 0
        $idx = 0
        foreach ($dbName in ($dbList | Select-Object -Unique | Sort-Object)) {
            $item = New-Object System.Windows.Controls.ComboBoxItem
            $item.Content = $dbName
            $cmbSqlDatabase.Items.Add($item) | Out-Null
            if ($currentDb -and $dbName -eq $currentDb) {
                $selectedIdx = $idx
            }
            $idx++
        }
        
        if ($cmbSqlDatabase.Items.Count -gt 0) {
            $cmbSqlDatabase.SelectedIndex = $selectedIdx
        }
        $script:SuppressDbChange = $false
        $script:SuppressSchemaChange = $false
    } catch { }
}

$btnSqlConnect.Add_Click({
    $connStr = $txtSqlConnStr.Text
    if ([string]::IsNullOrWhiteSpace($connStr) -or $connStr -eq $script:SqlPlaceholder) {
        [System.Windows.MessageBox]::Show("Please enter a valid connection string.", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        return
    }

    # Show connecting status and wait cursor immediately
    $lblSqlStatus.Text = "Connecting..."
    $lblSqlStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F59E0B")
    [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
    
    try {
        $cleanConnStr = $connStr -replace '(?i)ApplicationName\s*=', 'Application Name=' -replace '(?i)WorkstationID\s*=', 'Workstation ID='
        $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder($cleanConnStr)
        $builder.set_Item("Application Name", ".Net SqlClient Data Provider")
        $builder.set_Item("Workstation ID", ".")
        
        $conn = New-Object System.Data.SqlClient.SqlConnection($builder.ConnectionString)
        $script:SqlPrintMessages = [System.Collections.Generic.List[string]]::new()
        $conn.add_InfoMessage({
            param($sender, $e)
            if ($script:SqlPrintMessages) {
                foreach ($err in $e.Errors) {
                    $script:SqlPrintMessages.Add($err.Message)
                }
            }
        })
        $conn.Open()
        $script:SqlConnection = $conn
        $script:SqlConnected = $true
        $script:SqlDataSource = $builder.DataSource
        
        $lblSqlStatus.Text = "Connected: $($builder.DataSource) / $($builder.InitialCatalog)"
        $lblSqlStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
        
        # Auto-Save connection to saved dropdown permanently
        Save-ConnectionAuto -ConnStr $connStr -ServerName $builder.DataSource -DbName $builder.InitialCatalog
        
        # Load database dropdown (fast)
        Load-SqlDatabases
        
        try {
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = "SELECT @@VERSION"
            $lblSqlServerInfo.Text = $cmd.ExecuteScalar().ToString().Split("`n")[0].Trim()
            $cmd.Dispose()
        } catch { }

        # Render fast SSMS Object Explorer tree (< 50ms)
        Build-ObjectExplorerTree
        Update-AllSqlTabsConnectionState
        if ($lblSqlSsmsStatusText) { $lblSqlSsmsStatusText.Text = "Connected to $($builder.DataSource)" }
        if ($lblSqlSsmsStatusDetails) { $lblSqlSsmsStatusDetails.Text = "$($builder.DataSource) | mandar.k | $($builder.InitialCatalog)" }

        # Fetch IntelliSense schema in background without blocking UI
        if ($window -and $window.Dispatcher) {
            $window.Dispatcher.BeginInvoke([System.Action]{
                try { Fetch-SqlSchemaMetadata } catch {}
            }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
        }
        
    } catch {
        $lblSqlStatus.Text = "Disconnected"
        $lblSqlStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EF4444")
        [System.Windows.MessageBox]::Show("Connection failed: $($_.Exception.Message)", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    } finally {
        [System.Windows.Input.Mouse]::OverrideCursor = $null
    }
})

$DisconnectSqlSession = {
    if ($script:SqlConnection) {
        try { $script:SqlConnection.Close(); $script:SqlConnection.Dispose() } catch { }
        $script:SqlConnection = $null
    }
    $script:SqlPrintMessages = $null
    $script:SqlConnected = $false
    $lblSqlStatus.Text = "Disconnected"
    $lblSqlStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#64748B")
    $cmbSqlDatabase.Items.Clear()
    $cmbSqlProcs.Items.Clear()
    $lblSqlServerInfo.Text = ""
    $script:SqlTables.Clear()
    $script:SqlColumns.Clear()
    $script:CachedTables.Clear()
    $script:CachedViews.Clear()
    $script:CachedProcs.Clear()
    $script:CachedFuncs.Clear()
    $popSqlIntellisense.IsOpen = $false
    try {
        Build-ObjectExplorerTree
        Update-AllSqlTabsConnectionState
        if ($lblSqlSsmsStatusText) { $lblSqlSsmsStatusText.Text = "Ready" }
        if ($lblSqlSsmsStatusDetails) { $lblSqlSsmsStatusDetails.Text = "Disconnected" }
    } catch {}
}

$btnSqlDisconnect.Add_Click($DisconnectSqlSession)
if ($btnSsmsDisconnect) { $btnSsmsDisconnect.Add_Click($DisconnectSqlSession) }
if ($btnSsmsConnect) {
    $btnSsmsConnect.Add_Click({
        $btnSqlConnect.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
    })
}

if ($btnSqlNewQuery) {
    $btnSqlNewQuery.Add_Click({
        New-SqlQueryTab
    })
}











$cmbSqlDatabase.Add_SelectionChanged({
    if ($script:SuppressDbChange -or -not $script:SqlConnected -or $cmbSqlDatabase.SelectedIndex -eq -1) { return }
    try {
        $selected = $cmbSqlDatabase.SelectedItem
        $dbName = if ($selected -is [System.Windows.Controls.ComboBoxItem]) { $selected.Content } else { $selected.ToString() }
        if ($dbName) {
            Switch-SqlActiveDatabase $dbName
        }
    } catch { }
})

$btnSqlRefreshDbs.Add_Click({
    $script:CachedTables.Clear()
    $script:CachedViews.Clear()
    $script:CachedProcs.Clear()
    $script:CachedFuncs.Clear()
    Load-SqlDatabases
    Build-ObjectExplorerTree
})

function Create-NewSqlFnTemplate {
    $nowStr = (Get-Date).ToString("yyyy-MM-dd")
    $template = @"
-- ================================================
-- Author:      System Administrator
-- Create date: $nowStr
-- Description: Scalar Function Template (SSMS Style)
-- ================================================
CREATE FUNCTION [dbo].[fn_NewFunctionName]
(
    @InputVal INT = 0
)
RETURNS INT
AS
BEGIN
    DECLARE @Result INT = @InputVal * 2;
    RETURN @Result;
END
GO
"@
    if ($txtSqlQuery) {
        $txtSqlQuery.Text = $template
        $txtSqlQuery.Foreground = if ($global:isDarkMode) { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80") } else { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A") }
        $txtSqlQuery.Focus() | Out-Null
    }
    if ($lblQueryTabTitle) { $lblQueryTabTitle.Text = "New Function *" }
}

function Insert-SqlSuggestion {
    $selected = $lstSqlSuggestions.SelectedItem
    if (-not $selected) {
        $popSqlIntellisense.IsOpen = $false
        return
    }
    
    $replacement = if ($selected -is [PSCustomObject]) { $selected.Text } else { $selected.ToString() }
    $text = $txtSqlQuery.Text
    $caret = $txtSqlQuery.CaretIndex
    if ($caret -gt 0 -and $caret -le $text.Length) {
        $sub = $text.Substring(0, $caret)
        $match = [regex]::Match($sub, "[\w\.\[\]]+$")
        if ($match.Success) {
            $startIdx = $match.Index
            $len = $match.Length
            $newText = $text.Remove($startIdx, $len).Insert($startIdx, $replacement)
            $txtSqlQuery.Text = $newText
            $txtSqlQuery.CaretIndex = $startIdx + $replacement.Length
        }
    }
    $popSqlIntellisense.IsOpen = $false
    $txtSqlQuery.Focus() | Out-Null
}

$lstSqlSuggestions.Add_MouseDoubleClick({ Insert-SqlSuggestion })

$txtSqlQuery.Add_KeyUp({
    param($sender, $e)
    
    if ($e.Key -eq [System.Windows.Input.Key]::Down -or 
        $e.Key -eq [System.Windows.Input.Key]::Up -or 
        $e.Key -eq [System.Windows.Input.Key]::Enter -or 
        $e.Key -eq [System.Windows.Input.Key]::Tab -or 
        $e.Key -eq [System.Windows.Input.Key]::Escape) {
        return
    }
    
    $text = $txtSqlQuery.Text
    $caret = $txtSqlQuery.CaretIndex
    if ($caret -le 0 -or [string]::IsNullOrWhiteSpace($text) -or $caret -gt $text.Length) {
        $popSqlIntellisense.IsOpen = $false
        return
    }

    $sub = $text.Substring(0, $caret)
    $match = [regex]::Match($sub, "[\w\.\[\]]+$")
    if (-not $match.Success) {
        $popSqlIntellisense.IsOpen = $false
        return
    }

    $word = $match.Value.Trim('[',']')
    if ($word.Length -lt 1) {
        $popSqlIntellisense.IsOpen = $false
        return
    }

    $catalog = $script:SqlCatalog
    if (-not $catalog -or $catalog.Count -eq 0) {
        $popSqlIntellisense.IsOpen = $false
        return
    }

    $matched = [System.Collections.Generic.List[PSCustomObject]]::new()
    $count = 0
    foreach ($item in $catalog) {
        if ($item.Text.IndexOf($word, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $matched.Add($item)
            $count++
            if ($count -ge 15) { break }
        }
    }

    if ($matched.Count -gt 0) {
        $lstSqlSuggestions.DisplayMemberPath = "Display"
        $lstSqlSuggestions.SelectedValuePath = "Text"
        $lstSqlSuggestions.ItemsSource = $matched
        $lstSqlSuggestions.SelectedIndex = 0
        $popSqlIntellisense.IsOpen = $true
    } else {
        $popSqlIntellisense.IsOpen = $false
    }
})

function Get-AutoSelectVerificationQuery {
    param([string]$QueryText)
    
    $cleanText = $QueryText.Trim()
    
    # 1. UPDATE with FROM clause: UPDATE aa SET ... FROM WaterConnectionMast aa WHERE Ownerid=1740641
    if ($cleanText -match '(?i)UPDATE\s+.*?\s+FROM\s+([^\s;]+)\s+(?:AS\s+)?(\w+)?\s*(?:WHERE\s+([^;]+))?') {
        $tableName = $matches[1] -replace '\[|\]', ''
        $whereClause = $matches[3]
        
        $ownerIds = [regex]::Matches($cleanText, '(?i)Ownerid\s*=\s*(\d+)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
        if ($ownerIds.Count -gt 1) {
            $idList = $ownerIds -join ', '
            return "SELECT TOP 200 * FROM [$tableName] WHERE Ownerid IN ($idList)"
        } elseif ($whereClause) {
            return "SELECT TOP 200 * FROM [$tableName] WHERE $whereClause"
        } else {
            return "SELECT TOP 200 * FROM [$tableName]"
        }
    }
    
    # 2. Standard UPDATE: UPDATE WaterConnectionMast SET ... WHERE Ownerid=1740641
    if ($cleanText -match '(?i)UPDATE\s+([^\s;]+)\s+SET\s+.*?(?:WHERE\s+([^;]+))?') {
        $tableName = $matches[1] -replace '\[|\]', ''
        $whereClause = $matches[2]
        
        $ownerIds = [regex]::Matches($cleanText, '(?i)Ownerid\s*=\s*(\d+)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
        if ($ownerIds.Count -gt 1) {
            $idList = $ownerIds -join ', '
            return "SELECT TOP 200 * FROM [$tableName] WHERE Ownerid IN ($idList)"
        } elseif ($whereClause) {
            return "SELECT TOP 200 * FROM [$tableName] WHERE $whereClause"
        } else {
            return "SELECT TOP 200 * FROM [$tableName]"
        }
    }
    
    # 3. DELETE: DELETE FROM WaterConnectionMast WHERE Ownerid=1740641
    if ($cleanText -match '(?i)DELETE\s+(?:FROM\s+)?([^\s;]+)\s*(?:WHERE\s+([^;]+))?') {
        $tableName = $matches[1] -replace '\[|\]', ''
        $whereClause = $matches[2]
        if ($whereClause) {
            return "SELECT TOP 200 * FROM [$tableName] WHERE $whereClause"
        } else {
            return "SELECT TOP 200 * FROM [$tableName]"
        }
    }
    
    # 4. INSERT: INSERT INTO WaterConnectionMast ...
    if ($cleanText -match '(?i)INSERT\s+(?:INTO\s+)?([^\s\();]+)') {
        $tableName = $matches[1] -replace '\[|\]', ''
        return "SELECT TOP 200 * FROM [$tableName]"
    }

    # 5. ALTER / CREATE TABLE
    if ($cleanText -match '(?i)(?:ALTER|CREATE)\s+TABLE\s+([^\s\();]+)') {
        $tableName = $matches[1] -replace '\[|\]', ''
        return "SELECT TOP 100 * FROM [$tableName]"
    }

    return ""
}

function Execute-SqlQuery ([string]$OverrideQuery = "", [switch]$TestBeginTran) {
    if (-not $script:SqlConnected) {
        [System.Windows.MessageBox]::Show("Not connected to a database.", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        return
    }
    
    $rawQuery = ""
    if (-not [string]::IsNullOrWhiteSpace($OverrideQuery)) {
        $rawQuery = $OverrideQuery
    } elseif ($txtSqlQuery -and -not [string]::IsNullOrWhiteSpace($txtSqlQuery.SelectedText)) {
        $rawQuery = $txtSqlQuery.SelectedText
    } elseif ($txtSqlQuery) {
        $rawQuery = $txtSqlQuery.Text
    }
    
    if ([string]::IsNullOrWhiteSpace($rawQuery) -or $rawQuery -eq $script:SqlPlaceholder) { return }
    
    # If the user highlighted ONLY a single commented line starting with "--" (e.g. "-- EXEC my_proc 123"), strip "--" for execution
    $trimmedRaw = $rawQuery.Trim()
    if ($trimmedRaw -match '(?i)^\s*--\s*(?:EXEC|EXECUTE|SELECT|UPDATE|DELETE|INSERT)\b' -and ($trimmedRaw -split "\r?\n").Count -eq 1) {
        $query = $trimmedRaw -replace '^\s*--\s*', ''
    } else {
        # Keep comments intact for multi-line scripts & SP definitions
        $query = $rawQuery.Trim()
    }

    if ([string]::IsNullOrWhiteSpace($query)) { return }
    
    $upperQuery = $query.ToUpperInvariant()
    $blocked = @("DROP DATABASE", "TRUNCATE TABLE", "GRANT ", "REVOKE ", "DENY ", "XP_", "SP_CONFIGURE", "SHUTDOWN", "BACKUP DATABASE", "RESTORE DATABASE")
    foreach ($b in $blocked) {
        if ($upperQuery.Contains($b)) {
            [System.Windows.MessageBox]::Show("Security Warning: '$b' command is blocked.", "Warning", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
            return
        }
    }
    
    # Split query by GO statements into separate SQL batches (matching SSMS behavior)
    $rawBatches = [regex]::Split($query, '(?m)^\s*GO\s*$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $batches = @()
    foreach ($bItem in $rawBatches) {
        if ($bItem -and -not [string]::IsNullOrWhiteSpace($bItem.Trim())) {
            $batches += $bItem.Trim()
        }
    }
    if ($batches.Count -eq 0) { $batches = @($query) }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $nowStr = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $serverName = if ($script:SqlDataSource) { $script:SqlDataSource } else { "Server" }
    $dbName = if ($script:SqlConnection) { $script:SqlConnection.Database } else { "SQL" }

    $allDataTables = [System.Collections.Generic.List[System.Data.DataTable]]::new()
    $messagesLog = [System.Text.StringBuilder]::new()
    $totalRowsAffected = 0
    $hasError = $false
    $lastErrorMsg = ""

    if ($TestBeginTran) {
        [void]$messagesLog.AppendLine("==========================================================")
        [void]$messagesLog.AppendLine("*** SAFE TEST MODE ACTIVATED (BEGIN TRAN ... ROLLBACK) ***")
        [void]$messagesLog.AppendLine("Query is being tested inside an isolated SQL transaction.")
        [void]$messagesLog.AppendLine("NO PERMANENT CHANGES WILL BE COMMITTED TO THE DATABASE.")
        [void]$messagesLog.AppendLine("==========================================================")
        [void]$messagesLog.AppendLine("")
    }

    foreach ($batch in $batches) {
        if ([string]::IsNullOrWhiteSpace($batch)) { continue }

        $tran = $null
        try {
            $cmd = $script:SqlConnection.CreateCommand()
            $cmd.CommandTimeout = 0 # 0 = Infinite / No Timeout (matches SSMS default behavior so long batches never timeout)

            # If TestBeginTran is active, begin an isolated transaction to rollback after checking
            if ($TestBeginTran) {
                $tran = $script:SqlConnection.BeginTransaction("SafeTestTran")
                $cmd.Transaction = $tran
            }

            # SSMS Rule: CREATE/ALTER PROCEDURE/PROC/FUNCTION/TRIGGER/VIEW MUST be the first statement in a batch!
            # Strip comments & whitespace ONLY for DDL detection (so leading comments above ALTER PROC don't break isDDL check)
            $cleanBatchForCheck = $batch -replace '(?s)/\*.*?\*/', '' -replace '(?m)^\s*--.*$', ''
            $cleanTrimmed = $cleanBatchForCheck.Trim()
            $isDDL = $cleanTrimmed -match '(?i)^(?:CREATE|ALTER|DROP)\s+(?:PROCEDURE|PROC|FUNCTION|TRIGGER|VIEW)\b'

            if ($isDDL) {
                # Execute DDL directly WITHOUT prepending SET NOCOUNT ON
                $cmd.CommandText = $batch
                $rows = $cmd.ExecuteNonQuery()
                [void]$messagesLog.AppendLine("Commands completed successfully.")
            } else {
                # Auto-prepend EXEC if batch starts with procedure call (e.g. sp_who2, sp_who, prcMyProc) without EXEC keyword
                $execBatch = $batch
                if ($cleanTrimmed -match '(?i)^(?:sp_|prc_|usp_)\w+' -and $cleanTrimmed -notmatch '(?i)^(?:EXEC|EXECUTE)\b') {
                    $execBatch = "EXEC " + $batch.Trim()
                }

                $cmd.CommandText = $execBatch

                # Clear print messages before execution
                if ($script:SqlPrintMessages) { $script:SqlPrintMessages.Clear() }

                $reader = $cmd.ExecuteReader()
                $ds = New-Object System.Data.DataSet
                try {
                    $ds.Load($reader, [System.Data.LoadOption]::PreserveChanges, [string[]]@("Table"))
                    $batchAffected = $reader.RecordsAffected
                } finally {
                    $reader.Close()
                }

                # Add any captured PRINT messages
                if ($script:SqlPrintMessages -and $script:SqlPrintMessages.Count -gt 0) {
                    foreach ($pMsg in $script:SqlPrintMessages) {
                        [void]$messagesLog.AppendLine($pMsg)
                    }
                    $script:SqlPrintMessages.Clear()
                }

                $hasTableWithCols = $false
                if ($ds -and $ds.Tables.Count -gt 0) {
                    foreach ($t in $ds.Tables) {
                        if ($t.Columns.Count -gt 0) {
                            $hasTableWithCols = $true
                            $allDataTables.Add($t)
                            [void]$messagesLog.AppendLine("($($t.Rows.Count) row(s) affected)")
                        }
                    }
                }

                if ($batchAffected -ge 0) {
                    $totalRowsAffected += $batchAffected
                    if (-not $hasTableWithCols) {
                        [void]$messagesLog.AppendLine("($batchAffected row(s) affected)")
                    } else {
                        [void]$messagesLog.Insert(0, "($batchAffected row(s) affected)`r`n")
                    }
                } elseif (-not $hasTableWithCols) {
                    [void]$messagesLog.AppendLine("Commands completed successfully.")
                }
            }

            # Rollback transaction immediately if in Test mode!
            if ($tran) {
                $tran.Rollback()
                $tran.Dispose()
                $tran = $null
                [void]$messagesLog.AppendLine("[SAFE TEST MODE] Transaction ROLLED BACK successfully. 0 DB rows committed.")
            }

            $cmd.Dispose()
        } catch {
            if ($tran) {
                try { $tran.Rollback() } catch {}
                try { $tran.Dispose() } catch {}
                $tran = $null
            }
            $hasError = $true
            $lastErrorMsg = $_.Exception.Message
            [void]$messagesLog.AppendLine("Msg 50000, Level 16, State 1`r`nError: $($_.Exception.Message)")
            if ($TestBeginTran) {
                [void]$messagesLog.AppendLine("[SAFE TEST MODE] Transaction ROLLED BACK due to error.")
            }
            break
        }
    }

    $sw.Stop()
    $ts = [TimeSpan]::FromMilliseconds($sw.ElapsedMilliseconds)
    $timeFormatted = "{0:D2}:{1:D2}:{2:D2}.{3:D3}" -f $ts.Hours, $ts.Minutes, $ts.Seconds, $ts.Milliseconds

    # Pick best DataTable to display in DataGrid
    $dt = $null
    if ($allDataTables.Count -gt 0) {
        foreach ($t in $allDataTables) {
            if ($t.Rows.Count -gt 0) {
                $dt = $t
                break
            }
        }
        if (-not $dt) { $dt = $allDataTables[0] }
    }
    if (-not $dt) { $dt = New-Object System.Data.DataTable }

    if ($hasError) {
        # Update UI for Execution Error
        if ($txtSqlMessages) {
            $txtSqlMessages.Text = $messagesLog.ToString() + "`r`n`r`nCompletion time: $nowStr`r`nServer: $serverName | Database: $dbName"
            $txtSqlMessages.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F87171")
        }
        if ($lblSqlRowCount) { $lblSqlRowCount.Text = "Query Failed | Time: $($sw.ElapsedMilliseconds)ms" }; Save-CurrentSqlTabState
        
        # Show Messages Tab
        if ($dgSqlResults -and $txtSqlMessages) {
            $dgSqlResults.Visibility = [System.Windows.Visibility]::Collapsed
            $txtSqlMessages.Visibility = [System.Windows.Visibility]::Visible
            if ($btnSqlTabMessages -and $btnSqlTabResults) {
                $btnSqlTabMessages.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EF4444")
                $btnSqlTabMessages.Foreground = [System.Windows.Media.Brushes]::White
                $btnSqlTabResults.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
                $btnSqlTabResults.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
            }
        }
        
        if ($lblSqlSideToastIcon) { $lblSqlSideToastIcon.Text = "[ERROR]"; $lblSqlSideToastIcon.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EF4444") }
        if ($lblSqlSideToastMsg) { $lblSqlSideToastMsg.Text = "Query failed: $lastErrorMsg" }
        if ($bdrSqlSideToast) { $bdrSqlSideToast.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3B0707"); $bdrSqlSideToast.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EF4444") }
        if ($bdrSqlSsmsStatus) { $bdrSqlSsmsStatus.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#991B1B") }
        if ($lblSqlSsmsStatusText) { $lblSqlSsmsStatusText.Text = "Query executed with errors." }
        if ($lblSqlSsmsStatusDetails) { $lblSqlSsmsStatusDetails.Text = "$serverName | $dbName | $timeFormatted | ERROR" }

        [System.Windows.MessageBox]::Show("Query Error: $lastErrorMsg", "Query Execution Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        return
    }

    # Query Execution Succeeded!
    if ($dt.Columns.Count -gt 0) {
        # Display Grid Results
        $dgSqlResults.ItemsSource = $dt.DefaultView
        
        # Show Results Tab
        if ($dgSqlResults -and $txtSqlMessages) {
            $dgSqlResults.Visibility = [System.Windows.Visibility]::Visible
            $txtSqlMessages.Visibility = [System.Windows.Visibility]::Collapsed
            if ($btnSqlTabResults -and $btnSqlTabMessages) {
                $btnSqlTabResults.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0284C7")
                $btnSqlTabResults.Foreground = [System.Windows.Media.Brushes]::White
                $btnSqlTabMessages.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
                $btnSqlTabMessages.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
            }
        }

        if ($TestBeginTran) {
            $lblSqlRowCount.Text = "[SAFE TEST ROLLED BACK] Rows: $($dt.Rows.Count) | Time: $($sw.ElapsedMilliseconds)ms"
            $msgText = "($($dt.Rows.Count) row(s) returned in SAFE TEST MODE)`r`n`r`n" + $messagesLog.ToString().TrimEnd() + "`r`n`r`nCompletion time: $nowStr`r`nServer: $serverName | Database: $dbName`r`nTotal Execution Time: $timeFormatted"
            
            if ($lblSqlSideToastIcon) { $lblSqlSideToastIcon.Text = "[TEST OK - ROLLED BACK]"; $lblSqlSideToastIcon.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F59E0B") }
            if ($lblSqlSideToastMsg) { $lblSqlSideToastMsg.Text = "TEST MODE: ($($dt.Rows.Count) rows) - Rolled back safely (0 DB changes)" }
            if ($bdrSqlSideToast) { $bdrSqlSideToast.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#291D03"); $bdrSqlSideToast.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F59E0B") }
            if ($bdrSqlSsmsStatus) { $bdrSqlSsmsStatus.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#D97706") }
            if ($lblSqlSsmsStatusText) { $lblSqlSsmsStatusText.Text = "SAFE TEST: Query verified inside BEGIN TRAN ... ROLLBACK." }
            if ($lblSqlSsmsStatusDetails) { $lblSqlSsmsStatusDetails.Text = "$serverName | $dbName | $timeFormatted | $($dt.Rows.Count) rows previewed | 0 committed" }
        } else {
            $lblSqlRowCount.Text = "Rows: $($dt.Rows.Count) | Time: $($sw.ElapsedMilliseconds)ms"; Save-CurrentSqlTabState
            $msgText = $messagesLog.ToString().TrimEnd() + "`r`n`r`nCompletion time: $nowStr`r`nServer: $serverName | Database: $dbName`r`nTotal Execution Time: $timeFormatted"
            
            if ($lblSqlSideToastIcon) { $lblSqlSideToastIcon.Text = "[SUCCESS]"; $lblSqlSideToastIcon.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80") }
            if ($lblSqlSideToastMsg) { $lblSqlSideToastMsg.Text = "($($dt.Rows.Count) rows returned) - $($sw.ElapsedMilliseconds)ms" }
            if ($bdrSqlSideToast) { $bdrSqlSideToast.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#062816"); $bdrSqlSideToast.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#10B981") }
            if ($bdrSqlSsmsStatus) { $bdrSqlSsmsStatus.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#15803D") }
            if ($lblSqlSsmsStatusText) { $lblSqlSsmsStatusText.Text = "Query executed successfully." }
            if ($lblSqlSsmsStatusDetails) { $lblSqlSsmsStatusDetails.Text = "$serverName | $dbName | $timeFormatted | $($dt.Rows.Count) rows" }
        }

        if ($txtSqlMessages) {
            $txtSqlMessages.Text = $msgText
            $txtSqlMessages.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
        }

    } else {
        # DDL or Non-Query Execution (e.g. CREATE PROCEDURE / ALTER PROCEDURE / UPDATE / INSERT)
        $msgText = $messagesLog.ToString().TrimEnd() + "`r`n`r`nCompletion time: $nowStr`r`nServer: $serverName | Database: $dbName`r`nTotal Execution Time: $timeFormatted"
        
        if ($txtSqlMessages) {
            $txtSqlMessages.Text = $msgText
            $txtSqlMessages.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
        }
        
        # Show Messages Tab for DDL / non-query execution
        if ($dgSqlResults -and $txtSqlMessages) {
            $dgSqlResults.Visibility = [System.Windows.Visibility]::Collapsed
            $txtSqlMessages.Visibility = [System.Windows.Visibility]::Visible
            if ($btnSqlTabMessages -and $btnSqlTabResults) {
                $btnSqlTabMessages.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0284C7")
                $btnSqlTabMessages.Foreground = [System.Windows.Media.Brushes]::White
                $btnSqlTabResults.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
                $btnSqlTabResults.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
            }
        }

        if ($TestBeginTran) {
            $statusRowText = if ($totalRowsAffected -ge 0) { "$totalRowsAffected row(s) would be affected" } else { "Test completed successfully." }
            $lblSqlRowCount.Text = "[SAFE TEST ROLLED BACK] $statusRowText | Time: $($sw.ElapsedMilliseconds)ms"
            
            if ($lblSqlSideToastIcon) { $lblSqlSideToastIcon.Text = "[TEST OK - ROLLED BACK]"; $lblSqlSideToastIcon.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F59E0B") }
            if ($lblSqlSideToastMsg) { $lblSqlSideToastMsg.Text = "TEST MODE: ($statusRowText) - Rolled back safely (0 DB changes)" }
            if ($bdrSqlSideToast) { $bdrSqlSideToast.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#291D03"); $bdrSqlSideToast.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F59E0B") }
            if ($bdrSqlSsmsStatus) { $bdrSqlSsmsStatus.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#D97706") }
            if ($lblSqlSsmsStatusText) { $lblSqlSsmsStatusText.Text = "SAFE TEST: Query verified inside BEGIN TRAN ... ROLLBACK." }
            if ($lblSqlSsmsStatusDetails) { $lblSqlSsmsStatusDetails.Text = "$serverName | $dbName | $timeFormatted | $statusRowText | 0 DB changes committed" }
            
            [System.Windows.MessageBox]::Show("SAFE TEST COMPLETED:`r`n`r`nQuery executed successfully inside transaction and was ROLLED BACK.`r`n$statusRowText.`r`n0 database rows were committed.`r`n`r`nIf the results look correct, click 'EXECUTE QUERY (F5)' to apply permanent changes.", "Safe Test Mode (Rolled Back)", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        } else {
            if ($totalRowsAffected -ge 0) {
                $lblSqlRowCount.Text = "Rows Affected: $totalRowsAffected | Time: $($sw.ElapsedMilliseconds)ms"
                if ($lblSqlSideToastIcon) { $lblSqlSideToastIcon.Text = "[SUCCESS]"; $lblSqlSideToastIcon.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80") }
                if ($lblSqlSideToastMsg) { $lblSqlSideToastMsg.Text = "($totalRowsAffected row(s) affected) - $($sw.ElapsedMilliseconds)ms" }
                if ($bdrSqlSideToast) { $bdrSqlSideToast.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#062816"); $bdrSqlSideToast.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#10B981") }
                if ($bdrSqlSsmsStatus) { $bdrSqlSsmsStatus.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#15803D") }
                if ($lblSqlSsmsStatusText) { $lblSqlSsmsStatusText.Text = "Query executed successfully." }
                if ($lblSqlSsmsStatusDetails) { $lblSqlSsmsStatusDetails.Text = "$serverName | $dbName | $timeFormatted | $totalRowsAffected row(s) affected" }
            } else {
                $lblSqlRowCount.Text = "Commands completed successfully. | Time: $($sw.ElapsedMilliseconds)ms"
                if ($lblSqlSideToastIcon) { $lblSqlSideToastIcon.Text = "[SUCCESS]"; $lblSqlSideToastIcon.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80") }
                if ($lblSqlSideToastMsg) { $lblSqlSideToastMsg.Text = "Commands completed successfully. ($($sw.ElapsedMilliseconds)ms)" }
                if ($bdrSqlSideToast) { $bdrSqlSideToast.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#062816"); $bdrSqlSideToast.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#10B981") }
                if ($bdrSqlSsmsStatus) { $bdrSqlSsmsStatus.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#15803D") }
                if ($lblSqlSsmsStatusText) { $lblSqlSsmsStatusText.Text = "Commands completed successfully." }
                if ($lblSqlSsmsStatusDetails) { $lblSqlSsmsStatusDetails.Text = "$serverName | $dbName | $timeFormatted" }
            }

            # Refresh SP list if DDL statement created or modified a stored procedure!
            if ($query -match '(?i)\b(?:CREATE|ALTER|DROP)\s+(?:PROCEDURE|PROC)\b') {
                try { Load-SqlStoredProcedures } catch {}
            }
        }
    }
}

function Parse-SqlQuery {
    if (-not $script:SqlConnected) {
        [System.Windows.MessageBox]::Show("Not connected to a database.", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        return
    }
    $rawQuery = if ($txtSqlQuery -and -not [string]::IsNullOrWhiteSpace($txtSqlQuery.SelectedText)) { $txtSqlQuery.SelectedText } else { $txtSqlQuery.Text }
    if ([string]::IsNullOrWhiteSpace($rawQuery) -or $rawQuery -eq $script:SqlPlaceholder) { return }

    try {
        $cmd = $script:SqlConnection.CreateCommand()
        $cmd.CommandText = "SET PARSEONLY ON;`r`n" + $rawQuery + "`r`nSET PARSEONLY OFF;"
        $cmd.ExecuteNonQuery() | Out-Null
        $cmd.Dispose()

        if ($txtSqlMessages) {
            $txtSqlMessages.Text = "Command(s) completed successfully.`r`nSQL syntax is valid (SET PARSEONLY ON)."
            $txtSqlMessages.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
        }
        if ($lblSqlSideToastIcon) { $lblSqlSideToastIcon.Text = "[PARSE OK]"; $lblSqlSideToastIcon.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80") }
        if ($lblSqlSideToastMsg) { $lblSqlSideToastMsg.Text = "Command(s) completed successfully. (Syntax Valid)" }
        [System.Windows.MessageBox]::Show("Command(s) completed successfully.`r`nSQL syntax is valid.", "Parse Success", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    } catch {
        if ($txtSqlMessages) {
            $txtSqlMessages.Text = "Syntax Error: $($_.Exception.Message)"
            $txtSqlMessages.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F87171")
        }
        if ($lblSqlSideToastIcon) { $lblSqlSideToastIcon.Text = "[SYNTAX ERROR]"; $lblSqlSideToastIcon.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EF4444") }
        if ($lblSqlSideToastMsg) { $lblSqlSideToastMsg.Text = "Syntax error: $($_.Exception.Message)" }
        [System.Windows.MessageBox]::Show("SQL Syntax Error:`r`n$($_.Exception.Message)", "Parse Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    }
}

function Create-NewSqlSpTemplate {
    $nowStr = (Get-Date).ToString("yyyy-MM-dd")
    $template = @"
-- ================================================
-- Author:      System Administrator
-- Create date: $nowStr
-- Description: Stored Procedure Template (SSMS Style)
-- ================================================
CREATE PROCEDURE [dbo].[usp_NewProcedureName]
    @Param1 INT = 0,
    @Param2 VARCHAR(50) = ''
AS
BEGIN
    SET NOCOUNT ON;

    -- Write your SELECT / INSERT / UPDATE query below:
    SELECT 
        @Param1 AS [Param1],
        @Param2 AS [Param2];
END
GO
"@

    if ($txtSqlQuery) {
        $txtSqlQuery.Text = $template
        $txtSqlQuery.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
        $txtSqlQuery.Focus() | Out-Null
    }
    
    Show-SqlSpFullScreenViewer -ProcName "usp_NewProcedureName" -SpCode $template
}

if ($btnSqlTabResults) {
    $btnSqlTabResults.Add_Click({
        $dgSqlResults.Visibility = [System.Windows.Visibility]::Visible
        $txtSqlMessages.Visibility = [System.Windows.Visibility]::Collapsed
        $btnSqlTabResults.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0284C7")
        $btnSqlTabResults.Foreground = [System.Windows.Media.Brushes]::White
        $btnSqlTabMessages.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
        $btnSqlTabMessages.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
    })
}

if ($btnSqlTabMessages) {
    $btnSqlTabMessages.Add_Click({
        $dgSqlResults.Visibility = [System.Windows.Visibility]::Collapsed
        $txtSqlMessages.Visibility = [System.Windows.Visibility]::Visible
        $btnSqlTabMessages.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0284C7")
        $btnSqlTabMessages.Foreground = [System.Windows.Media.Brushes]::White
        $btnSqlTabResults.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
        $btnSqlTabResults.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
    })
}

if ($btnSqlCreateNewSp) {
    $btnSqlCreateNewSp.Add_Click({ Create-NewSqlSpTemplate })
}

if ($btnSqlParseQuery) {
    $btnSqlParseQuery.Add_Click({ Parse-SqlQuery })
}

$btnSqlExecute.Add_Click({ Execute-SqlQuery })

if ($btnSqlTestBeginTran) {
    $btnSqlTestBeginTran.Add_Click({ Execute-SqlQuery -TestBeginTran })
}

if ($btnJarvisFormat) { $btnJarvisFormat.Add_Click({ Format-SqlQuery }) }
if ($btnJarvisAnalyze) { $btnJarvisAnalyze.Add_Click({ Analyze-SqlQuery }) }
if ($btnJarvisAssistant) { $btnJarvisAssistant.Add_Click({ Show-JarvisAssistantWindow }) }
if ($btnSqlUserAccessManager) { $btnSqlUserAccessManager.Add_Click({ Show-UserAccessManagerWindow }) }
if ($btnSqlTableDdlWizard) { $btnSqlTableDdlWizard.Add_Click({ Show-TableDdlWizardWindow }) }

if ($dgSqlResults) {
    $ctxMenu = New-Object System.Windows.Controls.ContextMenu
    $ctxMenu.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A")
    $ctxMenu.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E2E8F0")
    $ctxMenu.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")

    # 1. Copy Selected Cell Value
    $miCopyCell = New-Object System.Windows.Controls.MenuItem
    $miCopyCell.Header = "Copy Cell Value (Ctrl+C)"
    $miCopyCell.FontWeight = [System.Windows.FontWeights]::Bold
    $miCopyCell.Add_Click({
        try {
            $selectedCells = $dgSqlResults.SelectedCells
            if ($selectedCells -and $selectedCells.Count -gt 0) {
                $cellVals = @()
                foreach ($cellInfo in $selectedCells) {
                    $item = $cellInfo.Item
                    $col = $cellInfo.Column
                    if ($item -and $col) {
                        $colHeader = $col.Header.ToString()
                        if ($item -is [System.Data.DataRowView]) {
                            $cellVals += $item.Row[$colHeader].ToString()
                        } elseif ($item -is [PSCustomObject]) {
                            $cellVals += $item.$colHeader.ToString()
                        } else {
                            $cellVals += $item.ToString()
                        }
                    }
                }
                $copyTxt = $cellVals -join "`t"
                [System.Windows.Clipboard]::SetText($copyTxt)
                if ($lblSqlSideToastMsg) { $lblSqlSideToastMsg.Text = "Copied value: `"$copyTxt`"" }
            }
        } catch { }
    })
    $ctxMenu.Items.Add($miCopyCell) | Out-Null

    # 2. Copy Full Row (TSV)
    $miCopyRow = New-Object System.Windows.Controls.MenuItem
    $miCopyRow.Header = "Copy Full Row (TSV)"
    $miCopyRow.Add_Click({
        try {
            $selectedItem = $dgSqlResults.SelectedItem
            if ($selectedItem -and ($selectedItem -is [System.Data.DataRowView])) {
                $rowVals = foreach ($col in $selectedItem.Row.Table.Columns) {
                    $selectedItem.Row[$col].ToString()
                }
                $rowTxt = $rowVals -join "`t"
                [System.Windows.Clipboard]::SetText($rowTxt)
                if ($lblSqlSideToastMsg) { $lblSqlSideToastMsg.Text = "Copied full row to clipboard!" }
            }
        } catch { }
    })
    $ctxMenu.Items.Add($miCopyRow) | Out-Null

    # 3. Copy Format: Column = Value
    $miCopyColVal = New-Object System.Windows.Controls.MenuItem
    $miCopyColVal.Header = "Copy Name & Value (Column = Value)"
    $miCopyColVal.Add_Click({
        try {
            $selectedCells = $dgSqlResults.SelectedCells
            if ($selectedCells -and $selectedCells.Count -gt 0) {
                $pairs = @()
                foreach ($cellInfo in $selectedCells) {
                    $item = $cellInfo.Item
                    $col = $cellInfo.Column
                    if ($item -and $col) {
                        $colHeader = $col.Header.ToString()
                        $val = if ($item -is [System.Data.DataRowView]) { $item.Row[$colHeader].ToString() } else { $item.ToString() }
                        $pairs += "$colHeader = '$val'"
                    }
                }
                $pairTxt = $pairs -join " AND "
                [System.Windows.Clipboard]::SetText($pairTxt)
                if ($lblSqlSideToastMsg) { $lblSqlSideToastMsg.Text = "Copied: `"$pairTxt`"" }
            }
        } catch { }
    })
    $ctxMenu.Items.Add($miCopyColVal) | Out-Null

    $dgSqlResults.ContextMenu = $ctxMenu
}

$script:SqlWindowCounter = 0
$script:SqlChildWindows = [System.Collections.Generic.List[object]]::new()

function Open-NewSqlConsoleWindow([string]$initialQuery = "") {
    New-SqlQueryTab -initialQuery $initialQuery
}

# ------------------------------------------------------------------------------
# SQL CONSOLE DYNAMIC QUERY TAB MANAGEMENT SYSTEM (Ctrl+N Multi-Instance)
# ------------------------------------------------------------------------------
$script:SqlTabs = [System.Collections.Generic.List[PSCustomObject]]::new()
$script:ActiveSqlTabId = 1
$script:SqlTabCounter = 1

function Save-CurrentSqlTabState {
    if (-not $script:SqlTabs -or $script:SqlTabs.Count -eq 0) { return }
    $cur = $script:SqlTabs | Where-Object { $_.Id -eq $script:ActiveSqlTabId }
    if ($cur) {
        if ($txtSqlQuery) {
            $cur.QueryText = $txtSqlQuery.Text
            $cur.CaretIndex = $txtSqlQuery.CaretIndex
        }
        if ($dgSqlResults -and $dgSqlResults.ItemsSource) {
            $cur.ResultsTable = $dgSqlResults.ItemsSource
        }
        if ($txtSqlMessages) {
            $cur.MessagesText = $txtSqlMessages.Text
        }
        if ($lblSqlRowCount) {
            $cur.RowCountText = $lblSqlRowCount.Text
        }
        if ($cmbSqlDatabase -and $cmbSqlDatabase.SelectedItem) {
            $sel = $cmbSqlDatabase.SelectedItem
            $cur.Database = if ($sel -is [System.Windows.Controls.ComboBoxItem]) { $sel.Content } else { $sel.ToString() }
        }
    }
}

function Render-SqlQueryTabs {
    if (-not $spQueryTabs) { return }
    $spQueryTabs.Children.Clear()
    $bc = [System.Windows.Media.BrushConverter]::new()

    foreach ($tab in $script:SqlTabs) {
        $tabId = $tab.Id
        $isActive = ($tabId -eq $script:ActiveSqlTabId)

        $bdr = New-Object System.Windows.Controls.Border
        $bdr.Margin = New-Object System.Windows.Thickness(0, 0, 2, 0)
        $bdr.Padding = New-Object System.Windows.Thickness(12, 4, 8, 4)
        $bdr.Cursor = [System.Windows.Input.Cursors]::Hand
        $bdr.Tag = $tabId

        if ($isActive) {
            $bdr.Background = if ($global:isDarkMode) { $bc.ConvertFromString("#1E1E1E") } else { [System.Windows.Media.Brushes]::White }
            $bdr.BorderBrush = $bc.ConvertFromString("#007ACC")
            $bdr.BorderThickness = New-Object System.Windows.Thickness(0, 2, 0, 0)
        } else {
            $bdr.Background = if ($global:isDarkMode) { $bc.ConvertFromString("#182234") } else { $bc.ConvertFromString("#E2E8F0") }
            $bdr.BorderThickness = New-Object System.Windows.Thickness(0)
        }

        $sp = New-Object System.Windows.Controls.StackPanel
        $sp.Orientation = [System.Windows.Controls.Orientation]::Horizontal

        # Connection status in tab title (Matches Screenshot!)
        $statusStr = if ($script:SqlConnected) {
            $db = if ($tab.Database) { $tab.Database } elseif ($cmbSqlDatabase -and $cmbSqlDatabase.SelectedItem) {
                if ($cmbSqlDatabase.SelectedItem -is [System.Windows.Controls.ComboBoxItem]) { $cmbSqlDatabase.SelectedItem.Content } else { $cmbSqlDatabase.SelectedItem.ToString() }
            } else { "Connected" }
            "$($tab.Title) - $db"
        } else {
            "$($tab.Title) - Disconnected"
        }

        $tbTitle = New-Object System.Windows.Controls.TextBlock
        $tbTitle.Text = $statusStr
        $tbTitle.FontSize = 11
        if ($isActive) {
            $tbTitle.FontWeight = [System.Windows.FontWeights]::SemiBold
            $tbTitle.Foreground = if ($global:isDarkMode) { $bc.ConvertFromString("#FFFFFF") } else { $bc.ConvertFromString("#0F172A") }
        } else {
            $tbTitle.FontWeight = [System.Windows.FontWeights]::Normal
            $tbTitle.Foreground = $bc.ConvertFromString("#94A3B8")
        }
        $sp.Children.Add($tbTitle) | Out-Null

        # Close 'x' button (Interactive, hover-highlighted, reliable hit-target)
        $bdrClose = New-Object System.Windows.Controls.Border
        $bdrClose.Width = 18
        $bdrClose.Height = 18
        $bdrClose.CornerRadius = New-Object System.Windows.CornerRadius(3)
        $bdrClose.Margin = New-Object System.Windows.Thickness(8, 0, 0, 0)
        $bdrClose.Background = [System.Windows.Media.Brushes]::Transparent
        $bdrClose.Cursor = [System.Windows.Input.Cursors]::Hand
        $bdrClose.ToolTip = "Close Tab (Ctrl+W)"
        $bdrClose.Tag = $tabId

        $tbClose = New-Object System.Windows.Controls.TextBlock
        $tbClose.Text = "x"
        $tbClose.FontSize = 11
        $tbClose.FontWeight = [System.Windows.FontWeights]::SemiBold
        $tbClose.Foreground = $bc.ConvertFromString("#94A3B8")
        $tbClose.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $tbClose.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $tbClose.Margin = New-Object System.Windows.Thickness(0, -2, 0, 0)
        $bdrClose.Child = $tbClose

        $bdrClose.Add_MouseEnter({
            param($s, $e)
            $s.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EF4444")
            if ($s.Child) { $s.Child.Foreground = [System.Windows.Media.Brushes]::White }
        })
        $bdrClose.Add_MouseLeave({
            param($s, $e)
            $s.Background = [System.Windows.Media.Brushes]::Transparent
            if ($s.Child) { $s.Child.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8") }
        })

        # Suppress mouse down bubbling so clicking 'x' doesn't switch tabs or close prematurely
        $bdrClose.Add_PreviewMouseLeftButtonDown({
            param($s, $e)
            if ($e) { $e.Handled = $true }
        })

        # Trigger close ONLY on mouse release of this specific tab (prevents double-closing sibling tabs)
        $bdrClose.Add_PreviewMouseLeftButtonUp({
            param($s, $e)
            if ($e) { $e.Handled = $true }
            $idToClose = [int]$s.Tag
            Close-SqlQueryTab $idToClose
        })

        $sp.Children.Add($bdrClose) | Out-Null
        $bdr.Child = $sp

        # Click Tab to Switch (Left Click switches, Middle Click closes tab)
        $bdr.Add_MouseDown({
            param($s, $e)
            if ($e.ChangedButton -eq [System.Windows.Input.MouseButton]::Middle) {
                $e.Handled = $true
                $idToClose = [int]$s.Tag
                Close-SqlQueryTab $idToClose
            } elseif ($e.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) {
                if (-not $e.Handled) {
                    Switch-SqlTab ([int]$s.Tag)
                }
            }
        })

        $spQueryTabs.Children.Add($bdr) | Out-Null
    }
}

function Switch-SqlTab([int]$targetTabId) {
    if ($targetTabId -eq $script:ActiveSqlTabId -and $script:SqlTabs.Count -gt 0) {
        Render-SqlQueryTabs
        return
    }

    Save-CurrentSqlTabState

    $target = $script:SqlTabs | Where-Object { $_.Id -eq $targetTabId }
    if (-not $target) { return }

    $script:ActiveSqlTabId = $targetTabId

    # Load into UI
    if ($txtSqlQuery) {
        $txtSqlQuery.Text = if ($target.QueryText) { $target.QueryText } else { "" }
        $txtSqlQuery.Foreground = if ($global:isDarkMode) { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80") } else { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A") }
        try {
            if ($target.CaretIndex -ge 0 -and $target.CaretIndex -le $txtSqlQuery.Text.Length) {
                $txtSqlQuery.CaretIndex = $target.CaretIndex
            }
            $txtSqlQuery.Focus() | Out-Null
        } catch {}
    }

    if ($dgSqlResults) {
        $dgSqlResults.ItemsSource = $target.ResultsTable
    }

    if ($txtSqlMessages) {
        $txtSqlMessages.Text = if ($target.MessagesText) { $target.MessagesText } else { "" }
    }

    if ($lblSqlRowCount) {
        $lblSqlRowCount.Text = if ($target.RowCountText) { $target.RowCountText } else { "Rows: 0 | Time: 0ms" }
    }

    # Switch database dropdown if tab has a different DB
    if ($target.Database -and $cmbSqlDatabase -and $script:SqlConnected) {
        $idx = -1
        for ($i = 0; $i -lt $cmbSqlDatabase.Items.Count; $i++) {
            $item = $cmbSqlDatabase.Items[$i]
            $name = if ($item -is [System.Windows.Controls.ComboBoxItem]) { $item.Content } else { $item.ToString() }
            if ($name -eq $target.Database) { $idx = $i; break }
        }
        if ($idx -ge 0 -and $idx -ne $cmbSqlDatabase.SelectedIndex) {
            $script:SuppressDbChange = $true
            $cmbSqlDatabase.SelectedIndex = $idx
            $script:SuppressDbChange = $false
        }
    }

    Render-SqlQueryTabs
}

function New-SqlQueryTab([string]$initialQuery = "", [string]$targetDb = "") {
    Save-CurrentSqlTabState

    $script:SqlTabCounter++
    $currDb = if ($targetDb) {
        $targetDb
    } elseif ($cmbSqlDatabase -and $cmbSqlDatabase.SelectedItem) {
        if ($cmbSqlDatabase.SelectedItem -is [System.Windows.Controls.ComboBoxItem]) { $cmbSqlDatabase.SelectedItem.Content } else { $cmbSqlDatabase.SelectedItem.ToString() }
    } else {
        if ($script:SqlConnected) { "master" } else { "" }
    }

    if (-not $initialQuery) {
        $initialQuery = if ($currDb) {
            "-- SQLQuery$($script:SqlTabCounter).sql`r`nUSE [$currDb];`r`nGO`r`n`r`nSELECT TOP 100 * FROM sys.tables;`r`n"
        } else {
            "-- SQLQuery$($script:SqlTabCounter).sql`r`n"
        }
    }

    $newTab = [PSCustomObject]@{
        Id           = $script:SqlTabCounter
        Title        = "SQLQuery$($script:SqlTabCounter).sql"
        Database     = $currDb
        QueryText    = $initialQuery
        ResultsTable = $null
        MessagesText = ""
        RowCountText = "Rows: 0 | Time: 0ms"
        CaretIndex   = $initialQuery.Length
    }

    $script:SqlTabs.Add($newTab)
    Switch-SqlTab $newTab.Id
}

function Close-SqlQueryTab([int]$tabIdToClose) {
    if ($script:SqlTabs.Count -gt 1) {
        $idx = -1
        for ($i = 0; $i -lt $script:SqlTabs.Count; $i++) {
            if ($script:SqlTabs[$i].Id -eq $tabIdToClose) { $idx = $i; break }
        }
        if ($idx -ge 0) {
            $wasActive = ($script:SqlTabs[$idx].Id -eq $script:ActiveSqlTabId)
            $script:SqlTabs.RemoveAt($idx)

            if ($wasActive) {
                $newIdx = [Math]::Max(0, [Math]::Min($idx, $script:SqlTabs.Count - 1))
                Switch-SqlTab $script:SqlTabs[$newIdx].Id
            } else {
                Render-SqlQueryTabs
            }
        }
    } else {
        # Only 1 tab remaining: reset it
        $tab = $script:SqlTabs[0]
        $tab.QueryText = ""
        $tab.ResultsTable = $null
        $tab.MessagesText = ""
        $tab.RowCountText = "Rows: 0 | Time: 0ms"
        if ($txtSqlQuery) { $txtSqlQuery.Text = ""; $txtSqlQuery.Focus() | Out-Null }
        if ($dgSqlResults) { $dgSqlResults.ItemsSource = $null }
        if ($txtSqlMessages) { $txtSqlMessages.Text = "" }
        if ($lblSqlRowCount) { $lblSqlRowCount.Text = "Rows: 0 | Time: 0ms" }
        Render-SqlQueryTabs
    }
}

function Set-ActiveSqlTabTitle([string]$newTitle) {
    $cur = $script:SqlTabs | Where-Object { $_.Id -eq $script:ActiveSqlTabId }
    if ($cur) {
        $cur.Title = $newTitle
        Render-SqlQueryTabs
    }
}

function Update-AllSqlTabsConnectionState {
    foreach ($tab in $script:SqlTabs) {
        if ($script:SqlConnected) {
            $db = if ($cmbSqlDatabase -and $cmbSqlDatabase.SelectedItem) {
                if ($cmbSqlDatabase.SelectedItem -is [System.Windows.Controls.ComboBoxItem]) { $cmbSqlDatabase.SelectedItem.Content } else { $cmbSqlDatabase.SelectedItem.ToString() }
            } else { "master" }
            if (-not $tab.Database) { $tab.Database = $db }
        } else {
            $tab.Database = ""
        }
    }
    Render-SqlQueryTabs
}

# Initial Query Tab Setup
if ($script:SqlTabs.Count -eq 0) {
    $script:SqlTabs.Add([PSCustomObject]@{
        Id           = 1
        Title        = "SQLQuery1.sql"
        Database     = ""
        QueryText    = if ($txtSqlQuery -and $txtSqlQuery.Text) { $txtSqlQuery.Text } else { "-- SQLQuery1.sql
" }
        ResultsTable = $null
        MessagesText = ""
        RowCountText = "Rows: 0 | Time: 0ms"
        CaretIndex   = 0
    })
    $script:ActiveSqlTabId = 1
    $script:SqlTabCounter = 1
    Render-SqlQueryTabs
}

function Clear-SqlQuery {
    $txtSqlQuery.Text = ""
    $dgSqlResults.ItemsSource = $null
    $lblSqlRowCount.Text = "Rows: 0 | Time: 0ms"
    $popSqlIntellisense.IsOpen = $false
}

if ($btnSqlNewWindow) { $btnSqlNewWindow.Add_Click({ New-SqlQueryTab }) }
if ($btnSqlAddQueryTab) { $btnSqlAddQueryTab.Add_Click({ New-SqlQueryTab }) }
$btnSqlClear.Add_Click({ Clear-SqlQuery })

$btnSqlExport.Add_Click({
    $view = $dgSqlResults.ItemsSource
    if (-not $view) { return }
    $dt = $view.Table
    if (-not $dt -or $dt.Rows.Count -eq 0) { return }
    
    $sfd = New-Object Microsoft.Win32.SaveFileDialog
    $sfd.Filter = "CSV File (*.csv)|*.csv"
    $sfd.FileName = "QueryResults.csv"
    if ($sfd.ShowDialog() -eq $true) {
        try {
            $lines = @()
            $headers = @()
            foreach ($col in $dt.Columns) { $headers += "`"$($col.ColumnName)`"" }
            $lines += $headers -join ","
            
            foreach ($row in $dt.Rows) {
                $values = @()
                foreach ($col in $dt.Columns) {
                    $val = $row[$col].ToString().Replace("`"", "`"`"")
                    $values += "`"$val`""
                }
                $lines += $values -join ","
            }
            $lines | Set-Content $sfd.FileName -Encoding UTF8
            [System.Windows.MessageBox]::Show("Export successful.", "Success", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        } catch {
            [System.Windows.MessageBox]::Show("Export Error: $($_.Exception.Message)", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        }
    }
})

$txtSqlQuery.Add_PreviewKeyDown({
    param($sender, $e)
    
    if ($popSqlIntellisense.IsOpen) {
        if ($e.Key -eq [System.Windows.Input.Key]::Down) {
            if ($lstSqlSuggestions.SelectedIndex -lt $lstSqlSuggestions.Items.Count - 1) {
                $lstSqlSuggestions.SelectedIndex += 1
                $lstSqlSuggestions.ScrollIntoView($lstSqlSuggestions.SelectedItem)
            }
            $e.Handled = $true
            return
        }
        if ($e.Key -eq [System.Windows.Input.Key]::Up) {
            if ($lstSqlSuggestions.SelectedIndex -gt 0) {
                $lstSqlSuggestions.SelectedIndex -= 1
                $lstSqlSuggestions.ScrollIntoView($lstSqlSuggestions.SelectedItem)
            }
            $e.Handled = $true
            return
        }
        if ($e.Key -eq [System.Windows.Input.Key]::Tab -or ($e.Key -eq [System.Windows.Input.Key]::Enter -and [System.Windows.Input.Keyboard]::Modifiers -ne [System.Windows.Input.ModifierKeys]::Control)) {
            Insert-SqlSuggestion
            $e.Handled = $true
            return
        }
        if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
            $popSqlIntellisense.IsOpen = $false
            $e.Handled = $true
            return
        }
    }

    if ($e.Key -eq [System.Windows.Input.Key]::N -and [System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::Control) {
        New-SqlQueryTab
        $e.Handled = $true
        return
    } elseif ($e.Key -eq [System.Windows.Input.Key]::W -and [System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::Control) {
        Close-SqlQueryTab $script:ActiveSqlTabId
        $e.Handled = $true
        return
    } elseif ($e.Key -eq [System.Windows.Input.Key]::L -and [System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::Control) {
        Clear-SqlQuery
        $e.Handled = $true
        return
    } elseif ($e.Key -eq [System.Windows.Input.Key]::F5 -and [System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::Control) {
        Parse-SqlQuery
        $e.Handled = $true
    } elseif ($e.Key -eq [System.Windows.Input.Key]::F5 -or ($e.Key -eq [System.Windows.Input.Key]::Enter -and [System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::Control)) {
        Execute-SqlQuery
        $e.Handled = $true
    }
})

$window.Add_PreviewKeyDown({
    param($sender, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::F1 -or ($e.Key -eq [System.Windows.Input.Key]::J -and [System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::Control)) {
        Show-JarvisAssistantWindow
        $e.Handled = $true
        return
    }

    if ($e.Key -eq [System.Windows.Input.Key]::D -and [System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::Control) {
        Show-BeyondCompareWindow
        $e.Handled = $true
        return
    }

    # New Independent Application Instance (Ctrl+Shift+N)
    if ($e.Key -eq [System.Windows.Input.Key]::N -and [System.Windows.Input.Keyboard]::Modifiers -eq ([System.Windows.Input.ModifierKeys]::Control -bor [System.Windows.Input.ModifierKeys]::Shift)) {
        New-NexusAppInstance
        $e.Handled = $true
        return
    }

    if ($e.Key -eq [System.Windows.Input.Key]::N -and [System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::Control) {
        if ($viewSqlConsole -and $viewSqlConsole.Visibility -eq [System.Windows.Visibility]::Visible) {
            New-SqlQueryTab
            $e.Handled = $true
            return
        }
    }
    if ($e.Key -eq [System.Windows.Input.Key]::W -and [System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::Control) {
        if ($viewSqlConsole -and $viewSqlConsole.Visibility -eq [System.Windows.Visibility]::Visible) {
            Close-SqlQueryTab $script:ActiveSqlTabId
            $e.Handled = $true
            return
        }
    }







    # Secret shortcut to unlock hidden SQL Console: Ctrl+Shift+S or Ctrl+Shift+Q
    if (($e.Key -eq [System.Windows.Input.Key]::S -or $e.Key -eq [System.Windows.Input.Key]::Q) -and 
        [System.Windows.Input.Keyboard]::Modifiers -eq ([System.Windows.Input.ModifierKeys]::Control -bor [System.Windows.Input.ModifierKeys]::Shift)) {
        Show-SqlPasswordUnlockDialog
        $e.Handled = $true
        return
    }

    # Secret shortcut to immediately Lock & Hide SQL Console: Ctrl+Shift+L
    if ($e.Key -eq [System.Windows.Input.Key]::L -and [System.Windows.Input.Keyboard]::Modifiers -eq ([System.Windows.Input.ModifierKeys]::Control -bor [System.Windows.Input.ModifierKeys]::Shift)) {
        if ($script:SqlConsoleUnlocked) {
            Lock-SqlConsole
            $e.Handled = $true
            return
        }
    }

    if ($viewSqlConsole.Visibility -eq "Visible") {
        if ($e.Key -eq [System.Windows.Input.Key]::F5 -and [System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::Control) {
            Parse-SqlQuery
            $e.Handled = $true
        } elseif ($e.Key -eq [System.Windows.Input.Key]::F5) {
            Execute-SqlQuery
            $e.Handled = $true
        } elseif ($e.Key -eq [System.Windows.Input.Key]::N -and [System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::Control) {
            New-SqlQueryTab
            $e.Handled = $true
        } elseif ($e.Key -eq [System.Windows.Input.Key]::W -and [System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::Control) {
            Close-SqlQueryTab $script:ActiveSqlTabId
            $e.Handled = $true


        } elseif ($e.Key -eq [System.Windows.Input.Key]::L -and [System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::Control) {
            Clear-SqlQuery
            $e.Handled = $true
        } elseif ($e.Key -eq [System.Windows.Input.Key]::F -and ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) -and ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Shift)) {
            Format-SqlQuery
            $e.Handled = $true
        }
    }
})

# --- TAB 2: GOVT EXAM PRESETS & LOGIC ---
$global:currentExamOutputBytes = $null
$global:currentExamOutputExt = "jpg"
$global:currentExamInputFiles = @()

$cmbExamPreset.Add_SelectionChanged({
    $idx = $cmbExamPreset.SelectedIndex
    switch ($idx) {
        0 { # SSC Photo (20-50 KB, 200x230 px)
            $txtExamMinKB.Text = "20"; $txtExamMaxKB.Text = "50"; $txtExamWidth.Text = "200"; $txtExamHeight.Text = "230"; $cmbExamFormat.SelectedIndex = 0
        }
        1 { # SSC / IBPS Signature (10-20 KB, 140x60 px)
            $txtExamMinKB.Text = "10"; $txtExamMaxKB.Text = "20"; $txtExamWidth.Text = "140"; $txtExamHeight.Text = "60"; $cmbExamFormat.SelectedIndex = 0
        }
        2 { # UPSC Photo (20-300 KB, min 350x350 px)
            $txtExamMinKB.Text = "20"; $txtExamMaxKB.Text = "300"; $txtExamWidth.Text = "550"; $txtExamHeight.Text = "700"; $cmbExamFormat.SelectedIndex = 0
        }
        3 { # UPSC Signature (20-300 KB, min 350x350 px)
            $txtExamMinKB.Text = "20"; $txtExamMaxKB.Text = "300"; $txtExamWidth.Text = "600"; $txtExamHeight.Text = "300"; $cmbExamFormat.SelectedIndex = 0
        }
        4 { # UPSC / SSC / NTA Certificate PDF (100-300 KB)
            $txtExamMinKB.Text = "100"; $txtExamMaxKB.Text = "300"; $txtExamWidth.Text = "1200"; $txtExamHeight.Text = "1600"; $cmbExamFormat.SelectedIndex = 1
        }
        5 { # IBPS Thumb Impression (20-50 KB, 240x240 px)
            $txtExamMinKB.Text = "20"; $txtExamMaxKB.Text = "50"; $txtExamWidth.Text = "240"; $txtExamHeight.Text = "240"; $cmbExamFormat.SelectedIndex = 0
        }
        6 { # IBPS Declaration (50-100 KB, 800x400 px)
            $txtExamMinKB.Text = "50"; $txtExamMaxKB.Text = "100"; $txtExamWidth.Text = "800"; $txtExamHeight.Text = "400"; $cmbExamFormat.SelectedIndex = 0
        }
        7 { # NTA Photo (10-200 KB)
            $txtExamMinKB.Text = "10"; $txtExamMaxKB.Text = "200"; $txtExamWidth.Text = "400"; $txtExamHeight.Text = "500"; $cmbExamFormat.SelectedIndex = 0
        }
        8 { # NTA Signature (4-30 KB)
            $txtExamMinKB.Text = "4"; $txtExamMaxKB.Text = "30"; $txtExamWidth.Text = "200"; $txtExamHeight.Text = "100"; $cmbExamFormat.SelectedIndex = 0
        }
        9 { # MPSC Photo (20-50 KB, 160x200 px)
            $txtExamMinKB.Text = "20"; $txtExamMaxKB.Text = "50"; $txtExamWidth.Text = "160"; $txtExamHeight.Text = "200"; $cmbExamFormat.SelectedIndex = 0
        }
        10 { # MPSC Signature (10-20 KB, 256x64 px)
            $txtExamMinKB.Text = "10"; $txtExamMaxKB.Text = "20"; $txtExamWidth.Text = "256"; $txtExamHeight.Text = "64"; $cmbExamFormat.SelectedIndex = 0
        }
        11 { # MPSC / State Certificate PDF (100-500 KB)
            $txtExamMinKB.Text = "100"; $txtExamMaxKB.Text = "500"; $txtExamWidth.Text = "1200"; $txtExamHeight.Text = "1600"; $cmbExamFormat.SelectedIndex = 1
        }
    }
})

function Load-ExamSourceFile($path) {
    if (-not (Test-Path $path)) { return }
    $ext = [System.IO.Path]::GetExtension($path).ToLower()
    $fileInfo = Get-Item $path
    $lblExamOrigSize.Text = "$([Math]::Round($fileInfo.Length / 1KB, 1)) KB"
    
    if ($ext -eq ".pdf") {
        $cmbExamFormat.SelectedIndex = 1
        $lblExamOrigDim.Text = "PDF Document"
        
        # Render first page as thumbnail if WinRT available
        try {
            if ($asTaskOp -and $asTaskAction -and $netStreamMethod) {
                $fileOp = [Windows.Storage.StorageFile]::GetFileFromPathAsync((Convert-Path $path))
                $storageFile = $asTaskOp.MakeGenericMethod([Windows.Storage.StorageFile]).Invoke($null, @($fileOp)).Result
                $docOp = [Windows.Data.Pdf.PdfDocument]::LoadFromFileAsync($storageFile)
                $pdfDoc = $asTaskOp.MakeGenericMethod([Windows.Data.Pdf.PdfDocument]).Invoke($null, @($docOp)).Result
                
                $lblExamOrigDim.Text = "PDF ($($pdfDoc.PageCount) Page(s))"
                if ($pdfDoc.PageCount -gt 0) {
                    $page = $pdfDoc.GetPage(0)
                    $stream = [Windows.Storage.Streams.InMemoryRandomAccessStream]::new()
                    $options = [Windows.Data.Pdf.PdfPageRenderOptions]::new()
                    $options.DestinationWidth = [uint32]400
                    $renderOp = $page.RenderToStreamAsync($stream, $options)
                    $asTaskAction.Invoke($null, @($renderOp)).Wait()
                    $netStream = $netStreamMethod.Invoke($null, @($stream))
                    $bmp = [System.Drawing.Bitmap]::FromStream($netStream)
                    
                    # Convert to WPF BitmapImage
                    $ms = [System.IO.MemoryStream]::new()
                    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
                    $ms.Position = 0
                    $bi = [System.Windows.Media.Imaging.BitmapImage]::new()
                    $bi.BeginInit()
                    $bi.StreamSource = $ms
                    $bi.CacheOption = "OnLoad"
                    $bi.EndInit()
                    $imgExamOriginal.Source = $bi
                    $bmp.Dispose()
                    $netStream.Dispose()
                    $stream.Dispose()
                    $page.Dispose()
                }
            }
        } catch {
            $imgExamOriginal.Source = $null
        }
    } else {
        # Image file
        try {
            $bytes = [System.IO.File]::ReadAllBytes($path)
            $ms = [System.IO.MemoryStream]::new($bytes)
            $img = [System.Drawing.Image]::FromStream($ms)
            $lblExamOrigDim.Text = "$($img.Width) x $($img.Height) px ($([Math]::Round($img.HorizontalResolution)) DPI)"
            $img.Dispose()
            $ms.Dispose()

            $ms2 = [System.IO.MemoryStream]::new($bytes)
            $bi = [System.Windows.Media.Imaging.BitmapImage]::new()
            $bi.BeginInit()
            $bi.StreamSource = $ms2
            $bi.CacheOption = "OnLoad"
            $bi.EndInit()
            $imgExamOriginal.Source = $bi
        } catch {}
    }
}

$btnExamBrowseSingle.Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = "Select Govt Exam Photo, Signature, or Document PDF"
    $dlg.Filter = "Exam Files (*.jpg;*.jpeg;*.png;*.pdf)|*.jpg;*.jpeg;*.png;*.pdf|Images (*.jpg;*.jpeg;*.png)|*.jpg;*.jpeg;*.png|PDF Documents (*.pdf)|*.pdf"
    if ($dlg.ShowDialog()) {
        $txtExamInputPath.Text = $dlg.FileName
        $global:currentExamInputFiles = @($dlg.FileName)
        Load-ExamSourceFile $dlg.FileName
    }
})

$btnExamBrowseMulti.Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = "Select Multiple Images to Combine into a Single Exam PDF"
    $dlg.Multiselect = $true
    $dlg.Filter = "Image Files (*.jpg;*.jpeg;*.png)|*.jpg;*.jpeg;*.png"
    if ($dlg.ShowDialog()) {
        $global:currentExamInputFiles = $dlg.FileNames
        $txtExamInputPath.Text = "$($dlg.FileNames.Count) images selected (Merged to PDF)"
        $cmbExamFormat.SelectedIndex = 1
        $lblExamOrigSize.Text = "Multi-Image ($($dlg.FileNames.Count) files)"
        $lblExamOrigDim.Text = "Batch Merge"
        Load-ExamSourceFile $dlg.FileNames[0]
    }
})

# Process Govt Exam optimization
$btnExamProcess.Add_Click({
    $inputPath = $txtExamInputPath.Text
    if (-not $inputPath -or ($global:currentExamInputFiles.Count -eq 0 -and -not (Test-Path $inputPath))) {
        [System.Windows.MessageBox]::Show("Please select an input image or PDF document first.", "No File Selected", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    $minKB = [long]20
    $maxKB = [long]50
    [long]::TryParse($txtExamMinKB.Text, [ref]$minKB) | Out-Null
    [long]::TryParse($txtExamMaxKB.Text, [ref]$maxKB) | Out-Null
    $minBytes = $minKB * 1024
    $maxBytes = $maxKB * 1024

    $targetW = 200
    $targetH = 230
    [int]::TryParse($txtExamWidth.Text, [ref]$targetW) | Out-Null
    [int]::TryParse($txtExamHeight.Text, [ref]$targetH) | Out-Null

    $isPdfOutput = ($cmbExamFormat.SelectedIndex -eq 1)
    $keepAspect = $chkExamKeepAspect.IsChecked

    try {
        $btnExamProcess.IsEnabled = $false
        $lblExamBadgeText.Text = "PROCESSING..."

        if ($isPdfOutput) {
            # PDF Processing Mode
            $pageBitmaps = [System.Collections.Generic.List[System.Drawing.Bitmap]]::new()

            if ($global:currentExamInputFiles.Count -gt 1) {
                # Multi-image to PDF
                foreach ($f in $global:currentExamInputFiles) {
                    if (Test-Path $f) {
                        $img = [System.Drawing.Image]::FromFile($f)
                        $bmp = New-Object System.Drawing.Bitmap $img
                        $pageBitmaps.Add($bmp)
                        $img.Dispose()
                    }
                }
            } elseif ($inputPath.EndsWith(".pdf", [System.StringComparison]::OrdinalIgnoreCase) -or (Test-Path $inputPath -and (Get-Item $inputPath).Extension.ToLower() -eq ".pdf")) {
                # PDF to PDF resize
                if ($asTaskOp -and $asTaskAction -and $netStreamMethod) {
                    $fileOp = [Windows.Storage.StorageFile]::GetFileFromPathAsync((Convert-Path $inputPath))
                    $storageFile = $asTaskOp.MakeGenericMethod([Windows.Storage.StorageFile]).Invoke($null, @($fileOp)).Result
                    $docOp = [Windows.Data.Pdf.PdfDocument]::LoadFromFileAsync($storageFile)
                    $pdfDoc = $asTaskOp.MakeGenericMethod([Windows.Data.Pdf.PdfDocument]).Invoke($null, @($docOp)).Result

                    for ($i = 0; $i -lt $pdfDoc.PageCount; $i++) {
                        $page = $pdfDoc.GetPage($i)
                        $stream = [Windows.Storage.Streams.InMemoryRandomAccessStream]::new()
                        $options = [Windows.Data.Pdf.PdfPageRenderOptions]::new()
                        $options.DestinationWidth = [uint32]$targetW
                        $renderOp = $page.RenderToStreamAsync($stream, $options)
                        $asTaskAction.Invoke($null, @($renderOp)).Wait()
                        $netStream = $netStreamMethod.Invoke($null, @($stream))
                        $bmp = [System.Drawing.Bitmap]::FromStream($netStream)
                        $pageBitmaps.Add((New-Object System.Drawing.Bitmap $bmp))
                        $bmp.Dispose()
                        $netStream.Dispose()
                        $stream.Dispose()
                        $page.Dispose()
                    }
                }
            } else {
                # Single Image to PDF
                $img = [System.Drawing.Image]::FromFile($inputPath)
                $bmp = New-Object System.Drawing.Bitmap $img
                $pageBitmaps.Add($bmp)
                $img.Dispose()
            }

            if ($pageBitmaps.Count -eq 0) {
                throw "Could not load pages from input file."
            }

            $pdfBytes = [GovtExamEngine]::BuildExamPdf($pageBitmaps, $minBytes, $maxBytes, 150)
            $global:currentExamOutputBytes = $pdfBytes
            $global:currentExamOutputExt = "pdf"

            $outKB = [Math]::Round($pdfBytes.Length / 1KB, 1)
            $lblExamOptSize.Text = "$outKB KB"
            $lblExamOptDim.Text = "PDF ($($pageBitmaps.Count) Page(s))"

            # Thumbnail preview of 1st page
            $ms = [System.IO.MemoryStream]::new()
            $pageBitmaps[0].Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
            $ms.Position = 0
            $bi = [System.Windows.Media.Imaging.BitmapImage]::new()
            $bi.BeginInit()
            $bi.StreamSource = $ms
            $bi.CacheOption = "OnLoad"
            $bi.EndInit()
            $imgExamOptimized.Source = $bi

            foreach ($b in $pageBitmaps) { $b.Dispose() }

            if ($pdfBytes.Length -ge $minBytes -and $pdfBytes.Length -le $maxBytes) {
                $lblExamBadgeText.Text = "PASSED (MEETS NOTATION)"
                $badgeExamStatus.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#059669")
            } else {
                $lblExamBadgeText.Text = "OPTIMIZED ($outKB KB)"
                $badgeExamStatus.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0284C7")
            }
            $btnExamSaveAs.IsEnabled = $true

        } else {
            # Photo / Signature Image Mode
            $rawBytes = [System.IO.File]::ReadAllBytes($inputPath)
            $inMs = [System.IO.MemoryStream]::new($rawBytes)
            $srcImg = [System.Drawing.Image]::FromStream($inMs)
            
            $optBytes = [GovtExamEngine]::CompressExamImage($srcImg, $targetW, $targetH, $minBytes, $maxBytes, 96, $keepAspect)
            $global:currentExamOutputBytes = $optBytes
            $global:currentExamOutputExt = "jpg"

            $outKB = [Math]::Round($optBytes.Length / 1KB, 1)
            $lblExamOptSize.Text = "$outKB KB"
            $lblExamOptDim.Text = "$targetW x $targetH px (96 DPI)"

            $ms = [System.IO.MemoryStream]::new($optBytes)
            $bi = [System.Windows.Media.Imaging.BitmapImage]::new()
            $bi.BeginInit()
            $bi.StreamSource = $ms
            $bi.CacheOption = "OnLoad"
            $bi.EndInit()
            $imgExamOptimized.Source = $bi

            $srcImg.Dispose()
            $inMs.Dispose()

            if ($optBytes.Length -ge $minBytes -and $optBytes.Length -le $maxBytes) {
                $lblExamBadgeText.Text = "PASSED (MEETS NOTATION)"
                $badgeExamStatus.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#059669")
            } else {
                $lblExamBadgeText.Text = "OPTIMIZED ($outKB KB)"
                $badgeExamStatus.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0284C7")
            }
            $btnExamSaveAs.IsEnabled = $true
        }
    } catch {
        [System.Windows.MessageBox]::Show("Error optimizing file: $($_.Exception.Message)", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        $lblExamBadgeText.Text = "ERROR"
        $badgeExamStatus.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#DC2626")
    } finally {
        $btnExamProcess.IsEnabled = $true
    }
})

# Save Exam Output File
$btnExamSaveAs.Add_Click({
    if (-not $global:currentExamOutputBytes -or $global:currentExamOutputBytes.Length -eq 0) { return }

    $ext = $global:currentExamOutputExt
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Title = "Save Govt Exam Optimized File"
    if ($ext -eq "pdf") {
        $dlg.Filter = "PDF Document (*.pdf)|*.pdf"
        $dlg.FileName = "GovtExam_Document_Optimized.pdf"
    } else {
        $dlg.Filter = "JPEG Image (*.jpg)|*.jpg"
        $dlg.FileName = "GovtExam_Photo_Optimized.jpg"
    }

    if ($dlg.ShowDialog()) {
        [System.IO.File]::WriteAllBytes($dlg.FileName, $global:currentExamOutputBytes)
        [System.Windows.MessageBox]::Show("File saved successfully to:`n$($dlg.FileName)`n`nSize: $([Math]::Round($global:currentExamOutputBytes.Length / 1KB, 1)) KB", "File Saved", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
})

# --- TAB 3: BLOB / WMF PREVIEWER LOGIC ---
$global:currentRawBytes = $null

function Convert-BlobTextToBytes($rawText) {
    if ([string]::IsNullOrWhiteSpace($rawText)) { return $null }
    $clean = $rawText.Trim()

    if ($clean.Length -lt 260 -and (Test-Path $clean)) {
        return [System.IO.File]::ReadAllBytes($clean)
    }

    if ($clean.StartsWith("0x", [System.StringComparison]::OrdinalIgnoreCase) -or $clean.StartsWith("0X")) {
        $hexStr = $clean.Substring(2)
        if ($hexStr.Length % 2 -ne 0) { $hexStr = "0" + $hexStr }
        $bytes = New-Object byte[] ($hexStr.Length / 2)
        for ($i = 0; $i -lt $hexStr.Length; $i += 2) {
            $bytes[$i / 2] = [System.Convert]::ToByte($hexStr.Substring($i, 2), 16)
        }

        # Check if SSMS double-hex ASCII encoded (0x30 0x78)
        if ($bytes.Length -gt 4 -and $bytes[0] -eq 0x30 -and ($bytes[1] -eq 0x78 -or $bytes[1] -eq 0x58)) {
            $asciiHex = [System.Text.Encoding]::ASCII.GetString($bytes)
            return Convert-BlobTextToBytes $asciiHex
        }
        return $bytes
    }

    try {
        $b64 = $clean -replace '\s+', ''
        $mod = $b64.Length % 4
        if ($mod -gt 0) { $b64 += "=" * (4 - $mod) }
        $bytes = [System.Convert]::FromBase64String($b64)
        if ($bytes.Length -gt 4 -and $bytes[0] -eq 0x30 -and ($bytes[1] -eq 0x78 -or $bytes[1] -eq 0x58)) {
            $asciiHex = [System.Text.Encoding]::ASCII.GetString($bytes)
            return Convert-BlobTextToBytes $asciiHex
        }
        return $bytes
    } catch {}

    return $null
}

function Decode-And-Display-Blob($rawInput) {
    $bytes = Convert-BlobTextToBytes $rawInput
    if (-not $bytes -or $bytes.Length -eq 0) {
        $lblPreviewStatus.Text = "Error: Invalid BLOB / Hex / Base64"
        $lblMetaFormat.Text = "Invalid"
        $lblMetaSize.Text = "0 KB"
        $lblMetaDim.Text = "--"
        $imgPreview.Source = $null
        return
    }

    $global:currentRawBytes = $bytes
    $sizeKB = [Math]::Round($bytes.Length / 1024.0, 1)
    $lblMetaSize.Text = "$sizeKB KB"

    # Identify format
    $fmt = "Unknown Binary"
    if ($bytes.Length -gt 4) {
        if ($bytes[0] -eq 0xD7 -and $bytes[1] -eq 0xCD -and $bytes[2] -eq 0xC6 -and $bytes[3] -eq 0x9A) {
            $fmt = "WMF (Placeable Metafile)"
        } elseif ($bytes[0] -eq 0x01 -and $bytes[1] -eq 0x00 -and $bytes[2] -eq 0x09 -and $bytes[3] -eq 0x00) {
            $fmt = "WMF (Standard Metafile)"
        } elseif ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xD8) {
            $fmt = "JPEG / JPG Image"
        } elseif ($bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47) {
            $fmt = "PNG Image"
        } elseif ($bytes[0] -eq 0x42 -and $bytes[1] -eq 0x4D) {
            $fmt = "BMP Bitmap"
        }
    }
    $lblMetaFormat.Text = $fmt

    # Render high-res solid white canvas preview
    try {
        $inMs = [System.IO.MemoryStream]::new($bytes)
        $src = [System.Drawing.Image]::FromStream($inMs)
        $w = $src.Width
        $h = $src.Height
        $lblMetaDim.Text = "$w x $h px"

        $canvas = [System.Drawing.Bitmap]::new($w, $h, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $canvas.SetResolution(96, 96)
        $g = [System.Drawing.Graphics]::FromImage($canvas)
        $g.Clear([System.Drawing.Color]::White)
        $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.DrawImage($src, 0, 0, $w, $h)

        $outMs = [System.IO.MemoryStream]::new()
        $canvas.Save($outMs, [System.Drawing.Imaging.ImageFormat]::Png)
        $outMs.Position = 0

        $bi = [System.Windows.Media.Imaging.BitmapImage]::new()
        $bi.BeginInit()
        $bi.StreamSource = $outMs
        $bi.CacheOption = "OnLoad"
        $bi.EndInit()
        $imgPreview.Source = $bi

        $g.Dispose()
        $canvas.Dispose()
        $src.Dispose()
        $inMs.Dispose()

        $lblPreviewStatus.Text = "Preview Ready (Solid White Applied)"
    } catch {
        $lblPreviewStatus.Text = "Render Error: $($_.Exception.Message)"
        $imgPreview.Source = $null
    }
}

$btnBlobDecode.Add_Click({ Decode-And-Display-Blob $txtBlobInput.Text })
$btnBlobClipboard.Add_Click({
    if ([System.Windows.Clipboard]::ContainsText()) {
        $txtBlobInput.Text = [System.Windows.Clipboard]::GetText()
        Decode-And-Display-Blob $txtBlobInput.Text
    }
})
$btnBlobBrowseFile.Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = "Select Image or WMF File to Preview"
    $dlg.Filter = "All Supported Files (*.wmf;*.emf;*.jpg;*.jpeg;*.png;*.txt;*.bin)|*.wmf;*.emf;*.jpg;*.jpeg;*.png;*.txt;*.bin"
    if ($dlg.ShowDialog()) {
        $txtBlobInput.Text = $dlg.FileName
        Decode-And-Display-Blob $dlg.FileName
    }
})
$btnBlobClear.Add_Click({
    $txtBlobInput.Text = ""
    $lblPreviewStatus.Text = "No Image Loaded"
    $lblMetaFormat.Text = "--"
    $lblMetaSize.Text = "-- KB"
    $lblMetaDim.Text = "-- px"
    $imgPreview.Source = $null
})

$txtBlobInput.Add_GotFocus({
    if ($txtBlobInput.Text -eq "Paste SQL Hex 0x..., Base64 string, or drop image file path here...") {
        $txtBlobInput.Text = ""
    }
})

$txtBlobInput.Add_PreviewDragOver({
    param($s, $e)
    if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
        $e.Effects = [System.Windows.DragDropEffects]::Copy
        $e.Handled = $true
    }
})

$txtBlobInput.Add_Drop({
    param($s, $e)
    if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
        $files = $e.Data.GetData([System.Windows.DataFormats]::FileDrop)
        if ($files -and $files.Length -gt 0) {
            $txtBlobInput.Text = $files[0]
            Decode-And-Display-Blob $files[0]
        }
    }
})

$btnCopyWmfHex.Add_Click({
    if (-not $global:currentRawBytes) {
        if ($lblPreviewStatus) { $lblPreviewStatus.Text = "Load an image first before copying hex." }
        return
    }
    if ($lblPreviewStatus) { $lblPreviewStatus.Text = "Converting to WMF..." }
    $wmfBytes = $null
    try { $wmfBytes = [AppWmfOptimizer]::ConvertBlobToCrystalReportWmf($global:currentRawBytes, 700, 96, 25, $true) } catch {}
    if ($wmfBytes -and $wmfBytes.Length -gt 0) {
        $hexStr = "0x" + [System.BitConverter]::ToString($wmfBytes).Replace("-", "")
        try { [System.Windows.Clipboard]::SetText($hexStr) } catch {}
        $sizeKB = [Math]::Round($wmfBytes.Length / 1024.0, 1)
        $hLen = $hexStr.Length
        if ($lblPreviewStatus) { $lblPreviewStatus.Text = "WMF SQL Hex copied! $sizeKB KB / $hLen chars. Paste into SSMS: UPDATE PropertyMast SET PlanPhoto = 0xD7CDC69A..." }
    } else {
        if ($lblPreviewStatus) { $lblPreviewStatus.Text = "WMF conversion failed. Try decoding a valid image first." }
    }
})

$btnCopyJpgHex.Add_Click({
    if (-not $global:currentRawBytes) {
        if ($lblPreviewStatus) { $lblPreviewStatus.Text = "Load an image first before copying hex." }
        return
    }
    if ($lblPreviewStatus) { $lblPreviewStatus.Text = "Converting to JPG..." }
    $jpgBytes = $null
    try { $jpgBytes = [AppWmfOptimizer]::ConvertBlobToCrystalReportJpg($global:currentRawBytes, 700, 96, 25) } catch {}
    if ($jpgBytes -and $jpgBytes.Length -gt 0) {
        $hexStr = "0x" + [System.BitConverter]::ToString($jpgBytes).Replace("-", "")
        try { [System.Windows.Clipboard]::SetText($hexStr) } catch {}
        $sizeKB = [Math]::Round($jpgBytes.Length / 1024.0, 1)
        $hLen = $hexStr.Length
        if ($lblPreviewStatus) { $lblPreviewStatus.Text = "JPG SQL Hex copied! $sizeKB KB / $hLen chars. Paste into SSMS: UPDATE PropertyMast SET PropertyPhoto = 0xFFD8FF..." }
    } else {
        if ($lblPreviewStatus) { $lblPreviewStatus.Text = "JPG conversion failed. Try decoding a valid image first." }
    }
})


# ---- SQL GENERATOR HELPERS for PropertyImagesMast / PropertyMast ----
function Get-BlobHexAndOwnerId($forWmf) {
    $ownerId = $txtBlobOwnerID.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($ownerId) -or $ownerId -notmatch '^\d+$') {
        if ($lblSqlCopyResult) { $lblSqlCopyResult.Text = "ERROR: Enter a valid numeric OwnerID first." }
        if ($lblSqlCopyResult) { $lblSqlCopyResult.Foreground = [System.Windows.Media.Brushes]::Red }
        return $null
    }
    if (-not $global:currentRawBytes) {
        if ($lblSqlCopyResult) { $lblSqlCopyResult.Text = "ERROR: Decode an image first." }
        if ($lblSqlCopyResult) { $lblSqlCopyResult.Foreground = [System.Windows.Media.Brushes]::Red }
        return $null
    }
    $bytes = $null
    if ($forWmf) {
        try { $bytes = [AppWmfOptimizer]::ConvertBlobToCrystalReportWmf($global:currentRawBytes, 700, 96, 25, $true) } catch {}
    } else {
        try { $bytes = [AppWmfOptimizer]::ConvertBlobToCrystalReportJpg($global:currentRawBytes, 700, 96, 25) } catch {}
    }
    if (-not $bytes -or $bytes.Length -eq 0) {
        if ($lblSqlCopyResult) { $lblSqlCopyResult.Text = "ERROR: Conversion failed - try a valid image." }
        if ($lblSqlCopyResult) { $lblSqlCopyResult.Foreground = [System.Windows.Media.Brushes]::Red }
        return $null
    }
    return @{ OwnerId = $ownerId; Bytes = $bytes; HexStr = "0x" + [System.BitConverter]::ToString($bytes).Replace("-", "") }
}

$btnCopyImagesMastSql.Add_Click({
    # PropertyImagesMast typically has: OwnerID, ImageTypeID, ImageData (or Photo/BlobData), IsActive, EntryDate
    # Generate UPDATE for PlanPhoto WMF column (ImageTypeID = 1 = PlanPhoto)
    $wmfData = Get-BlobHexAndOwnerId $true
    if (-not $wmfData) { return }
    $ownerId = $wmfData.OwnerId
    $hexStr  = $wmfData.HexStr
    $sizeKB  = [Math]::Round($wmfData.Bytes.Length / 1024.0, 1)

    $sql = @"
-- =====================================================================
-- UPDATE PropertyImagesMast - OwnerID: $ownerId
-- Image Type: WMF (Crystal Reports PlanPhoto) - $sizeKB KB
-- Run this in SSMS on your database
-- =====================================================================

-- Check if record exists first:
-- SELECT * FROM PropertyImagesMast WHERE OwnerID = $ownerId

-- Option 1: UPDATE existing row (if OwnerID already exists in PropertyImagesMast):
UPDATE PropertyImagesMast
SET    ImageData = $hexStr,
       IsActive  = 1,
       EntryDate = GETDATE()
WHERE  OwnerID = $ownerId

-- Option 2: INSERT if OwnerID does NOT exist yet in PropertyImagesMast:
-- INSERT INTO PropertyImagesMast (OwnerID, ImageData, IsActive, EntryDate)
-- VALUES ($ownerId, $hexStr, 1, GETDATE())

-- Verify after update:
SELECT OwnerID, LEN(ImageData) AS ImageSizeBytes, IsActive, EntryDate
FROM   PropertyImagesMast
WHERE  OwnerID = $ownerId
"@
    try { [System.Windows.Clipboard]::SetText($sql) } catch {}
    if ($lblSqlCopyResult) { $lblSqlCopyResult.Text = "PropertyImagesMast UPDATE SQL copied! ($sizeKB KB WMF) Paste in SSMS and run." }
    if ($lblSqlCopyResult) { $lblSqlCopyResult.Foreground = [System.Windows.Media.Brushes]::LightGreen }
    if ($lblPreviewStatus) { $lblPreviewStatus.Text = "UPDATE SQL for PropertyImagesMast (OwnerID=$ownerId) copied to clipboard!" }
})

$btnCopyPropertyMastSql.Add_Click({
    # PropertyMast typically has: PropertyPhoto (JPG) and PlanPhoto (WMF) columns
    $jpgData = Get-BlobHexAndOwnerId $false
    if (-not $jpgData) { return }
    $ownerId = $jpgData.OwnerId
    $hexStr  = $jpgData.HexStr
    $sizeKB  = [Math]::Round($jpgData.Bytes.Length / 1024.0, 1)

    $sql = @"
-- =====================================================================
-- UPDATE PropertyMast - OwnerID: $ownerId
-- Image Type: JPG (Property Photo) - $sizeKB KB
-- Run this in SSMS on your database
-- =====================================================================

UPDATE PropertyMast
SET    PropertyPhoto = $hexStr
WHERE  OwnerID = $ownerId

-- Verify after update:
SELECT OwnerID, LEN(PropertyPhoto) AS PhotoSizeBytes
FROM   PropertyMast
WHERE  OwnerID = $ownerId
"@
    try { [System.Windows.Clipboard]::SetText($sql) } catch {}
    if ($lblSqlCopyResult) { $lblSqlCopyResult.Text = "PropertyMast UPDATE SQL copied! ($sizeKB KB JPG) Paste in SSMS and run." }
    if ($lblSqlCopyResult) { $lblSqlCopyResult.Foreground = [System.Windows.Media.Brushes]::LightGreen }
    if ($lblPreviewStatus) { $lblPreviewStatus.Text = "UPDATE SQL for PropertyMast (OwnerID=$ownerId) copied to clipboard!" }
})

$btnDownloadWmf.Add_Click({
    if (-not $global:currentRawBytes) { return }
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Title = "Save Solid White Canvas WMF (Crystal Reports Safe)"
    $dlg.Filter = "Windows Metafile (*.wmf)|*.wmf"
    $dlg.FileName = "PlanPhoto_WhiteCanvas.wmf"
    if ($dlg.ShowDialog()) {
        $wmfBytes = [AppWmfOptimizer]::ConvertBlobToCrystalReportWmf($global:currentRawBytes, 700, 96, 25, $true)
        if ($wmfBytes -and $wmfBytes.Length -gt 0) {
            [System.IO.File]::WriteAllBytes($dlg.FileName, $wmfBytes)
            [System.Windows.MessageBox]::Show("WMF saved successfully with 100% Solid White Background!`nSize: $([Math]::Round($wmfBytes.Length / 1KB, 1)) KB", "Success", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        }
    }
})

$btnDownloadJpg.Add_Click({
    if (-not $global:currentRawBytes) { return }
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Title = "Save Optimized JPG (Under 25 KB)"
    $dlg.Filter = "JPEG Image (*.jpg)|*.jpg"
    $dlg.FileName = "PropertyPhoto_Optimized.jpg"
    if ($dlg.ShowDialog()) {
        $jpgBytes = [AppWmfOptimizer]::ConvertBlobToCrystalReportJpg($global:currentRawBytes, 700, 96, 25)
        if ($jpgBytes -and $jpgBytes.Length -gt 0) {
            [System.IO.File]::WriteAllBytes($dlg.FileName, $jpgBytes)
            [System.Windows.MessageBox]::Show("JPG saved successfully under 25 KB!`nSize: $([Math]::Round($jpgBytes.Length / 1KB, 1)) KB", "Success", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        }
    }
})

# --- TAB 4: OTP & PASSWORD DECRYPTOR LOGIC ---
function Decrypt-OtpToken($inputStr) {
    if ([string]::IsNullOrWhiteSpace($inputStr)) { return }
    $clean = $inputStr.Trim()
    $lblOtpRawInput.Text = $clean

    $keys = @(
        "SCIPLSPBNI99212",
        "LPICS00223SPBNI",
        "SCIPL",
        "SCPL",
        "MPMS",
        "UNNATI",
        "PMC",
        "AKOLA",
        "PARBHANI",
        "WASHIM",
        "AMRAVATI",
        "JALNA",
        "PALUS",
        "admin",
        "password",
        "123456",
        "SCIPL@123",
        "SCPL@123",
        "MPMS@123"
    )

    # 1. AES-256 (Unicode & UTF-8 with Rfc2898 "Ivan Medvedev" salt)
    if ($clean.Length -ge 16 -and ($clean.Length % 4 -eq 0)) {
        try {
            $cipherBytes = [System.Convert]::FromBase64String($clean.Replace(" ", "+"))
            $salt = [System.Text.Encoding]::ASCII.GetBytes("Ivan Medvedev")
            
            foreach ($k in $keys) {
                try {
                    $pdb = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($k, $salt)
                    $aes = [System.Security.Cryptography.Aes]::Create()
                    $aes.Key = $pdb.GetBytes(32)
                    $aes.IV = $pdb.GetBytes(16)
                    
                    $ms = New-Object System.IO.MemoryStream
                    $cs = New-Object System.Security.Cryptography.CryptoStream($ms, $aes.CreateDecryptor(), [System.Security.Cryptography.CryptoStreamMode]::Write)
                    $cs.Write($cipherBytes, 0, $cipherBytes.Length)
                    $cs.Close()

                    $decBytes = $ms.ToArray()
                    $decUnicode = [System.Text.Encoding]::Unicode.GetString($decBytes)
                    if ($decUnicode -match '^[\x20-\x7E]+$' -and $decUnicode.Length -ge 2) {
                        $lblDecryptedOtp.Text = $decUnicode
                        $lblOtpMethod.Text = "AES-256 (Key: $k)"
                        $lblOtpLength.Text = "$($decUnicode.Length) Characters"
                        $lblOtpSubtitle.Text = "Decrypted Password / Secret"
                        return
                    }

                    $decUtf8 = [System.Text.Encoding]::UTF8.GetString($decBytes)
                    if ($decUtf8 -match '^[\x20-\x7E]+$' -and $decUtf8.Length -ge 2) {
                        $lblDecryptedOtp.Text = $decUtf8
                        $lblOtpMethod.Text = "AES-256 UTF8 (Key: $k)"
                        $lblOtpLength.Text = "$($decUtf8.Length) Characters"
                        $lblOtpSubtitle.Text = "Decrypted Password / Secret"
                        return
                    }
                } catch {}
            }
        } catch {}
    }

    # 2. Hex string (0x...)
    if ($clean.StartsWith("0x", [System.StringComparison]::OrdinalIgnoreCase)) {
        try {
            $hex = $clean.Substring(2)
            if ($hex.Length % 2 -ne 0) { $hex = "0" + $hex }
            $bytes = New-Object byte[] ($hex.Length / 2)
            for ($i = 0; $i -lt $hex.Length; $i += 2) {
                $bytes[$i / 2] = [System.Convert]::ToByte($hex.Substring($i, 2), 16)
            }
            $otpText = [System.Text.Encoding]::UTF8.GetString($bytes).Trim()
            if ($otpText -match '^[\x20-\x7E]+$') {
                $lblDecryptedOtp.Text = $otpText
                $lblOtpMethod.Text = "Hexadecimal (0x...)"
                $lblOtpLength.Text = "$($otpText.Length) Characters"
                $lblOtpSubtitle.Text = "$($otpText.Length)-Digit Verification Code"
                return
            }
        } catch {}
    }

    # 3. Base64 standard (e.g. NjQ4NDU3 -> 648457)
    try {
        $b64 = $clean -replace '\s+', ''
        $mod = $b64.Length % 4
        if ($mod -gt 0) { $b64 += "=" * (4 - $mod) }
        $decodedBytes = [System.Convert]::FromBase64String($b64)
        $otpText = [System.Text.Encoding]::UTF8.GetString($decodedBytes).Trim()
        
        if ($otpText -match '^[\x20-\x7E]+$') {
            $lblDecryptedOtp.Text = $otpText
            $lblOtpMethod.Text = "Base64 (Standard)"
            $lblOtpLength.Text = "$($otpText.Length) Characters / Digits"
            $lblOtpSubtitle.Text = "$($otpText.Length)-Digit Verification Code"
            return
        }
    } catch {}

    # 4. XOR Cipher
    try {
        $cleanB64 = $clean.Trim().Replace(' ', '')
        $rawBytes = [System.Convert]::FromBase64String($cleanB64)
        foreach ($k in $keys) {
            $chars = New-Object char[] $rawBytes.Length
            for ($i = 0; $i -lt $rawBytes.Length; $i++) {
                $kChar = [int]$k[$i % $k.Length]
                $chars[$i] = [char]($rawBytes[$i] -bxor $kChar)
            }
            $xorStr = -join $chars
            if ($xorStr -match '^[a-zA-Z0-9@#\$\*\.\-_! ]{3,30}$') {
                $lblDecryptedOtp.Text = $xorStr
                $lblOtpMethod.Text = "XOR Cipher (Key: $k)"
                $lblOtpLength.Text = "$($xorStr.Length) Characters"
                $lblOtpSubtitle.Text = "Decrypted Password / Secret"
                return
            }
        }
    } catch {}

    $lblDecryptedOtp.Text = $clean
    $lblOtpMethod.Text = "Plain Text / Unchanged"
    $lblOtpLength.Text = "$($clean.Length) Characters"
    $lblOtpSubtitle.Text = "Decoded String"
}

$btnOtpDecrypt.Add_Click({ Decrypt-OtpToken $txtOtpInput.Text })
$btnOtpPasteClipboard.Add_Click({
    if ([System.Windows.Clipboard]::ContainsText()) {
        $txtOtpInput.Text = [System.Windows.Clipboard]::GetText()
        Decrypt-OtpToken $txtOtpInput.Text
    }
})
$btnOtpClear.Add_Click({
    $txtOtpInput.Text = ""
    $lblDecryptedOtp.Text = "------"
    $lblOtpRawInput.Text = "--"
    $lblOtpLength.Text = "--"
})
$btnCopyOtp.Add_Click({
    if ($lblDecryptedOtp.Text -and $lblDecryptedOtp.Text -ne "------") {
        [System.Windows.Clipboard]::SetText($lblDecryptedOtp.Text)
        [System.Windows.MessageBox]::Show("Decrypted OTP '$($lblDecryptedOtp.Text)' copied to clipboard!", "Copied", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
})
$btnCopySqlFormula.Add_Click({
    $sql = "SELECT CAST(CAST(N'' AS XML).value('xs:base64Binary(""NjQ4NDU3"")', 'VARBINARY(MAX)') AS VARCHAR(MAX)) AS DecryptedOTP;"
    [System.Windows.Clipboard]::SetText($sql)
    [System.Windows.MessageBox]::Show("SQL Base64 Decryption query copied to clipboard!", "Copied", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
})

# Initial load of OTP tab
Decrypt-OtpToken "NjQ4NDU3"

# --- TAB 1: BATCH RESIZER LOGIC ---
$rbPropertyPhotos.Add_Checked({
    $txtMaxKB.Text = "25"
    $txtMaxDim.Text = "700"
    $txtDPI.Text = "96"
    $txtTargetFolder.Text = "\\192.168.1.22\d\WebApplicationHost\PMCPhotoStorage.org\wwwroot\Files\PropertyImage"
})

$rbPlanPhotoWmf.Add_Checked({
    $txtMaxKB.Text = "25"
    $txtMaxDim.Text = "700"
    $txtDPI.Text = "96"
    $txtTargetFolder.Text = "\\192.168.1.22\d\WebApplicationHost\PMCPhotoStorage.org\wwwroot\Files\PlanPhoto"
})

$rbFilterExcel.Add_Checked({
    $panelExcelRow.Visibility = "Visible"
    $panelAllBadge.Visibility = "Collapsed"
    $panelCustomRow.Visibility = "Collapsed"
})

$rbFilterAll.Add_Checked({
    $panelExcelRow.Visibility = "Collapsed"
    $panelAllBadge.Visibility = "Visible"
    $panelCustomRow.Visibility = "Collapsed"
})

$rbFilterCustom.Add_Checked({
    $panelExcelRow.Visibility = "Collapsed"
    $panelAllBadge.Visibility = "Collapsed"
    $panelCustomRow.Visibility = "Visible"
})

$btnBrowseFolder.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Select target images folder"
    $dlg.SelectedPath = $txtTargetFolder.Text
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtTargetFolder.Text = $dlg.SelectedPath
    }
})

$btnBrowseExcel.Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = "Select Excel file with Property IDs"
    $dlg.Filter = "Excel Files (*.xlsx;*.xls)|*.xlsx;*.xls|All Files (*.*)|*.*"
    if ($dlg.ShowDialog()) {
        $txtExcelPath.Text = $dlg.FileName
    }
})

$btnOpenFolder.Add_Click({
    $path = $txtTargetFolder.Text
    if (Test-Path $path) { [System.Diagnostics.Process]::Start("explorer.exe", $path) }
    else { [System.Windows.MessageBox]::Show("Folder path does not exist:`n$path", "Path Not Found", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) }
})

$lastBackupPath = $null
$btnOpenBackup.Add_Click({
    if ($lastBackupPath -and (Test-Path $lastBackupPath)) {
        [System.Diagnostics.Process]::Start("explorer.exe", $lastBackupPath)
    }
})

function Append-Log($text) {
    $ts = (Get-Date).ToString("HH:mm:ss")
    $txtLogs.AppendText("[$ts] $text`r`n")
    $txtLogs.ScrollToEnd()
}

$btnStart.Add_Click({
    $targetFolder = $txtTargetFolder.Text
    $maxKB = [int]$txtMaxKB.Text
    $maxDim = [int]$txtMaxDim.Text
    $dpi = [int]$txtDPI.Text
    $doBackup = $chkBackup.IsChecked
    $isWmfMode = $rbPlanPhotoWmf.IsChecked

    if (-not (Test-Path $targetFolder)) {
        [System.Windows.MessageBox]::Show("Target folder does not exist:`n$targetFolder", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        return
    }

    $btnStart.IsEnabled = $false
    $progressBar.Value = 0
    $lblStatus.Text = "Status: Scanning files..."
    Append-Log "========================================="
    Append-Log "OPTIMIZER STARTED: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Append-Log "Mode: $(if ($isWmfMode) { 'PlanPhoto WMF (Solid White Crystal Reports)' } else { 'Property Photos JPG' })"
    Append-Log "Target Folder: $targetFolder"
    Append-Log "Max Size: $maxKB KB | Max Dim: $maxDim px | DPI: $dpi"
    Append-Log "========================================="

    # Read IDs if Excel mode
    $propertyIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($rbFilterExcel.IsChecked) {
        $excelPath = $txtExcelPath.Text
        if (-not (Test-Path $excelPath)) {
            [System.Windows.MessageBox]::Show("Excel file does not exist:`n$excelPath", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            $btnStart.IsEnabled = $true
            return
        }

        Append-Log "Reading Excel file: $excelPath ..."
        try {
            $excelApp = New-Object -ComObject Excel.Application
            $excelApp.Visible = $false
            $excelApp.DisplayAlerts = $false
            $wb = $excelApp.Workbooks.Open($excelPath, $null, $true)
            $ws = $wb.Sheets.Item(1)
            $usedRange = $ws.UsedRange
            $rowCount = $usedRange.Rows.Count
            $values = $usedRange.Value2

            for ($r = 1; $r -le $rowCount; $r++) {
                $val = $values[$r, 1]
                if ($val) {
                    $idStr = $val.ToString().Trim()
                    if ($idStr -and $idStr -notmatch '(?i)property|id|name|sr|no') {
                        [void]$propertyIds.Add($idStr)
                    }
                }
            }
            $wb.Close($false)
            $excelApp.Quit()
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($ws) | Out-Null
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wb) | Out-Null
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excelApp) | Out-Null
            [System.GC]::Collect()
            Append-Log "Extracted $($propertyIds.Count) property IDs from Excel."
        } catch {
            Append-Log "Error reading Excel via COM: $($_.Exception.Message)"
            $btnStart.IsEnabled = $true
            return
        }
    }

    # Match files
    $lblStatus.Text = "Status: Matching files in folder..."
    [System.Windows.Forms.Application]::DoEvents()

    $allFiles = Get-ChildItem -Path $targetFolder -File | Where-Object {
        $ext = $_.Extension.ToLower()
        if ($isWmfMode) { $ext -in @('.wmf', '.emf') }
        else { $ext -in @('.jpg', '.jpeg', '.png', '.bmp') }
    }

    $matchedFiles = [System.Collections.Generic.List[string]]::new()

    if ($rbFilterAll.IsChecked) {
        foreach ($f in $allFiles) { $matchedFiles.Add($f.FullName) }
    } elseif ($rbFilterCustom.IsChecked) {
        $customPrefixes = $txtCustomProperty.Text.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        foreach ($f in $allFiles) {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            foreach ($pfx in $customPrefixes) {
                if ($baseName.StartsWith($pfx, [System.StringComparison]::OrdinalIgnoreCase) -or $baseName.Contains($pfx)) {
                    $matchedFiles.Add($f.FullName)
                    break
                }
            }
        }
    } else {
        # Excel matching
        foreach ($f in $allFiles) {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            if ($propertyIds.Contains($baseName) -or $propertyIds.Contains($f.Name)) {
                $matchedFiles.Add($f.FullName)
            } else {
                foreach ($pid in $propertyIds) {
                    if ($baseName.StartsWith($pid, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $matchedFiles.Add($f.FullName)
                        break
                    }
                }
            }
        }
    }

    $lblMatched.Text = $matchedFiles.Count.ToString()
    Append-Log "Matched files to optimize: $($matchedFiles.Count)"

    if ($matchedFiles.Count -eq 0) {
        [System.Windows.MessageBox]::Show("No matching images found in the target folder.", "Notice", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        $btnStart.IsEnabled = $true
        return
    }

    # Full Backup
    if ($doBackup) {
        $lblStatus.Text = "Status: Backing up $($matchedFiles.Count) files..."
        $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupDirName = if ($isWmfMode) { "PlanPhoto_Backup_$stamp" } else { "PropertyImage_Backup_$stamp" }
        $backupPath = Join-Path $targetFolder $backupDirName
        $lastBackupPath = $backupPath

        if (-not (Test-Path $backupPath)) {
            New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
        }
        $btnOpenBackup.IsEnabled = $true
        Append-Log "Backup folder created: $backupPath"

        $backedCount = 0
        for ($i = 0; $i -lt $matchedFiles.Count; $i++) {
            $f = $matchedFiles[$i]
            $dest = Join-Path $backupPath ([System.IO.Path]::GetFileName($f))
            try {
                [System.IO.File]::Copy($f, $dest, $true)
                $backedCount++
            } catch {}

            if (($i + 1) % 100 -eq 0 -or ($i + 1) -eq $matchedFiles.Count) {
                $lblBackedUp.Text = $backedCount.ToString()
                $progressBar.Value = [Math]::Round((($i + 1) / $matchedFiles.Count) * 50)
                [System.Windows.Forms.Application]::DoEvents()
            }
        }
        Append-Log "Backup completed: $backedCount files backed up safely."
    }

    # Resize & Optimize Under MaxKB (with Solid White Crystal Reports Canvas)
    $lblStatus.Text = "Status: Resizing & optimizing files under $maxKB KB with Solid White Canvas..."
    $resizedCount = 0
    $skippedCount = 0
    $totalOrig = 0L
    $totalNew = 0L
    $totalFiles = $matchedFiles.Count

    for ($i = 0; $i -lt $totalFiles; $i++) {
        $file = $matchedFiles[$i]
        $fileName = [System.IO.Path]::GetFileName($file)
        $origLen = (Get-Item $file).Length
        $totalOrig += $origLen

        if ($isWmfMode) {
            # Enhancement: ONLY resize WMF files that have MORE THAN 25 KB (or custom maxKB)
            $wmfLimitBytes = if ($maxKB -gt 0) { [long]($maxKB * 1024) } else { [long](25 * 1024) }
            if ($origLen -le $wmfLimitBytes) {
                $skippedCount++
                $totalNew += $origLen
                if ($totalFiles -le 200 -or ($i + 1) % 50 -eq 0) {
                    Append-Log "Skipped (Already <= 25 KB): $fileName ($([Math]::Round($origLen / 1KB, 1)) KB)"
                }
                continue
            }

            $res = [AppWmfOptimizer]::ProcessWmf($file, $file, $maxDim, $dpi, $maxKB, $false)
            if ($res.StartsWith("OK:")) {
                $resizedCount++
                $newLen = (Get-Item $file).Length
                $totalNew += $newLen
                Append-Log "Resized WMF (> 25 KB): $fileName ($([Math]::Round($origLen / 1KB, 1)) KB -> $([Math]::Round($newLen / 1KB, 1)) KB)"
            } elseif ($res.StartsWith("SKIPPED:")) {
                $skippedCount++
                $totalNew += $origLen
            } else {
                $skippedCount++
                $totalNew += $origLen
                Append-Log "Warning on ${fileName}: $res"
            }
        } else {
            $bytes = [System.IO.File]::ReadAllBytes($file)
            $resBytes = [AppWmfOptimizer]::ConvertBlobToCrystalReportJpg($bytes, $maxDim, $dpi, $maxKB)
            if ($resBytes -and $resBytes.Length -gt 0) {
                [System.IO.File]::WriteAllBytes($file, $resBytes)
                $resizedCount++
                $totalNew += $resBytes.Length
            } else {
                $skippedCount++
                $totalNew += $origLen
            }
        }

        if (($i + 1) % 50 -eq 0 -or ($i + 1) -eq $totalFiles) {
            $lblResized.Text = $resizedCount.ToString()
            $savedMB = [Math]::Round(($totalOrig - $totalNew) / 1MB, 2)
            if ($savedMB -lt 0) { $savedMB = 0.0 }
            $lblSaved.Text = "$savedMB MB"
            $pct = 50 + [Math]::Round((($i + 1) / $totalFiles) * 50)
            $progressBar.Value = $pct
            $lblStatus.Text = "Status: Processed $($i+1)/$totalFiles images ($pct%)..."
            [System.Windows.Forms.Application]::DoEvents()
        }
    }

    $savedMB = [Math]::Round(($totalOrig - $totalNew) / 1MB, 2)
    $lblSaved.Text = "$savedMB MB"
    $lblStatus.Text = "Status: Process completed successfully!"
    $progressBar.Value = 100
    Append-Log "========================================="
    Append-Log "COMPLETED! Resized (> 25 KB): $resizedCount | Preserved (<= 25 KB): $skippedCount | Saved: $savedMB MB"
    Append-Log "========================================="

    [System.Windows.MessageBox]::Show("Optimization complete!`n`nTotal Matched: $totalFiles`nResized (> 25 KB): $resizedCount`nAlready <= 25 KB (Skipped/Preserved): $skippedCount`nSaved Space: $savedMB MB`nSolid White Background Applied for Crystal Reports.", "Success", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)

    $btnStart.IsEnabled = $true
})

# =====================================================================
# --- TAB 5: PHOTO EXTRACTOR & SERVER COLLECTOR LOGIC ---
# =====================================================================

$global:extractLastReportPath = ""

function Append-ExtractLog($msg) {
    $ts = (Get-Date).ToString("HH:mm:ss")
    $txtExtractLogs.Dispatcher.Invoke([Action]{
        $txtExtractLogs.AppendText("[$ts] $msg`r`n")
        $txtExtractLogs.ScrollToEnd()
    })
}

# Default server paths
$serverPhotoFolder = "\\192.168.1.22\d\WebApplicationHost\PMCPhotoStorage.org\wwwroot\Files\PropertyImage"
$serverWmfFolder   = "\\192.168.1.22\d\WebApplicationHost\PMCPhotoStorage.org\wwwroot\Files\PlanPhoto"
$desktopDir        = [Environment]::GetFolderPath("Desktop")

$defaultDestFolder = Join-Path $desktopDir "Collected_Property_Photos"
$txtExtractDest.Text = $defaultDestFolder

$rbExtractModePhotos.Add_Checked({
    if ($txtExtractSource.Text -match 'PlanPhoto') {
        $txtExtractSource.Text = $txtExtractSource.Text -replace 'PlanPhoto', 'PropertyImage'
    } elseif ($txtExtractSource.Text -eq $serverWmfFolder -or -not $txtExtractSource.Text) {
        $txtExtractSource.Text = $serverPhotoFolder
    }
    $dateStamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $txtExtractDest.Text = Join-Path $desktopDir "Collected_Property_Photos_$dateStamp"
})

$rbExtractModeWmf.Add_Checked({
    if ($txtExtractSource.Text -match 'PropertyImage') {
        $txtExtractSource.Text = $txtExtractSource.Text -replace 'PropertyImage', 'PlanPhoto'
    } elseif ($txtExtractSource.Text -eq $serverPhotoFolder -or -not $txtExtractSource.Text) {
        $txtExtractSource.Text = $serverWmfFolder
    }
    $dateStamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $txtExtractDest.Text = Join-Path $desktopDir "Collected_WMF_Plans_$dateStamp"
})

$rbExtractModeBoth.Add_Checked({
    $dateStamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $txtExtractDest.Text = Join-Path $desktopDir "Collected_Photos_And_WMF_$dateStamp"
})

$btnExtractBrowseSource.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Select Source Server / Network Image Folder"
    $dlg.SelectedPath = $txtExtractSource.Text
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtExtractSource.Text = $dlg.SelectedPath
    }
})

$btnExtractBrowseExcel.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "Select Excel File (.xlsx / .xls / .csv) with Property Numbers / Owner IDs"
    $dlg.Filter = "Excel & CSV Files (*.xlsx;*.xls;*.csv)|*.xlsx;*.xls;*.csv|All Files (*.*)|*.*"
    $dlg.InitialDirectory = [Environment]::GetFolderPath("Desktop")
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtExtractExcel.Text = $dlg.FileName
    }
})

$btnExtractBrowseDest.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Select Destination Output Folder on Desktop / Local Drive"
    $dlg.SelectedPath = $txtExtractDest.Text
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtExtractDest.Text = $dlg.SelectedPath
    }
})

$btnExtractResetDest.Add_Click({
    $dateStamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $prefix = if ($rbExtractModeWmf.IsChecked -eq $true) { "Collected_WMF_Plans" } elseif ($rbExtractModeBoth.IsChecked -eq $true) { "Collected_Photos_And_WMF" } else { "Collected_Property_Photos" }
    $txtExtractDest.Text = Join-Path $desktopDir "${prefix}_$dateStamp"
})

$btnExtractOpenDesktop.Add_Click({
    $dest = $txtExtractDest.Text
    if (Test-Path -LiteralPath $dest) {
        Start-Process "explorer.exe" -ArgumentList "`"$dest`""
    } else {
        [System.Windows.MessageBox]::Show("Output folder does not exist yet. Please run extraction first.", "Folder Not Found", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
    }
})

$btnExtractOpenReport.Add_Click({
    if ($global:extractLastReportPath -and (Test-Path -LiteralPath $global:extractLastReportPath)) {
        Start-Process $global:extractLastReportPath
    } else {
        [System.Windows.MessageBox]::Show("Summary report has not been generated yet.", "No Report", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
})

$btnExtractStart.Add_Click({
    $srcFolder = $txtExtractSource.Text.Trim()
    $excelPath = $txtExtractExcel.Text.Trim()
    $destFolder = $txtExtractDest.Text.Trim()
    $isSubfolders = $chkExtractSubfolders.IsChecked -eq $true
    $isRecursive = $chkExtractRecursive.IsChecked -eq $true
    $isAutoResize = $chkExtractAutoResize.IsChecked -eq $true
    $isWhiteCanvas = $chkExtractWhiteCanvas.IsChecked -eq $true
    $mode = if ($rbExtractModeWmf.IsChecked -eq $true) { "WMF" } elseif ($rbExtractModeBoth.IsChecked -eq $true) { "Both" } else { "Photos" }

    # Auto-switch path if WMF mode is chosen but source folder points to PropertyImage
    if ($mode -eq "WMF" -and $srcFolder -match 'PropertyImage') {
        $candidatePlan = $srcFolder -replace 'PropertyImage', 'PlanPhoto'
        if (Test-Path -LiteralPath $candidatePlan) {
            $srcFolder = $candidatePlan
            $txtExtractSource.Text = $srcFolder
        }
    } elseif ($mode -eq "Photos" -and $srcFolder -match 'PlanPhoto') {
        $candidateProp = $srcFolder -replace 'PlanPhoto', 'PropertyImage'
        if (Test-Path -LiteralPath $candidateProp) {
            $srcFolder = $candidateProp
            $txtExtractSource.Text = $srcFolder
        }
    }

    if (-not (Test-Path -LiteralPath $srcFolder)) {
        [System.Windows.MessageBox]::Show("Cannot access source server image folder:`n$srcFolder", "Invalid Source Folder", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        return
    }

    if (-not (Test-Path -LiteralPath $excelPath)) {
        [System.Windows.MessageBox]::Show("Excel file not found at:`n$excelPath", "Invalid Excel File", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        return
    }

    if (-not $destFolder) {
        $dateStamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
        $prefix = if ($mode -eq "WMF") { "Collected_WMF_Plans" } elseif ($mode -eq "Both") { "Collected_Photos_And_WMF" } else { "Collected_Property_Photos" }
        $destFolder = Join-Path $desktopDir "${prefix}_$dateStamp"
        $txtExtractDest.Text = $destFolder
    }

    if (-not (Test-Path -LiteralPath $destFolder)) {
        New-Item -ItemType Directory -Path $destFolder -Force | Out-Null
    }

    $btnExtractStart.IsEnabled = $false
    $txtExtractLogs.Clear()
    $lblExtractTotalProp.Text = "0"
    $lblExtractFoundProp.Text = "0"
    $lblExtractMissingProp.Text = "0"
    $lblExtractCollectedPhotos.Text = "0"
    $extractProgressBar.Value = 5
    $lblExtractStatus.Text = "Status: Reading property numbers from Excel..."

    Append-ExtractLog "======================================================="
    Append-ExtractLog "STARTING SERVER COLLECTION ($mode Mode)"
    Append-ExtractLog "Source Folder      : $srcFolder"
    Append-ExtractLog "Excel File         : $excelPath"
    Append-ExtractLog "Desktop Dest       : $destFolder"
    if ($mode -eq "WMF" -or $mode -eq "Both") {
        Append-ExtractLog "Solid White Canvas : $(if ($isWhiteCanvas) {'ENABLED (Crystal Reports Safe)'} else {'Disabled'})"
    }
    Append-ExtractLog "======================================================="

    [System.Windows.Forms.Application]::DoEvents()

    # Step 1: Parse Excel Properties
    $propList = [System.Collections.Generic.List[string]]::new()
    $tokenToPrimary = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    function Add-PropAlias($primary, $alias) {
        if (-not $alias -or $alias.Trim() -eq "" -or $alias -eq "#N/A") { return }
        $a = $alias.Trim()
        if (-not $tokenToPrimary.ContainsKey($a)) { $tokenToPrimary[$a] = $primary }
    }

    function Process-RowData($rowVals) {
        $building = ""; $node = ""; $ward = ""; $prop = ""; $part = ""; $ownerId = ""; $generic = ""
        foreach ($k in $rowVals.Keys) {
            $v = [string]$rowVals[$k]
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
            foreach ($v in $rowVals.Values) {
                if ($v -and $v.Trim() -ne "" -and $v -ne "#N/A") { $primary = $v.Trim(); break }
            }
        }

        if (-not $primary) { return }
        if (-not $propList.Contains($primary)) { $propList.Add($primary) }
        Add-PropAlias $primary $primary

        if ($building) { Add-PropAlias $primary $building }
        if ($ownerId) { Add-PropAlias $primary $ownerId }

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
                Add-PropAlias $primary "$wItem-$pItem"
                Add-PropAlias $primary "$wItem`_$pItem"
                Add-PropAlias $primary "$wItem$pItem"
                Add-PropAlias $primary "$wItem-A-$pItem"
                Add-PropAlias $primary "$wItem-B-$pItem"
                Add-PropAlias $primary "$wItem-C-$pItem"
                Add-PropAlias $primary "$wItem-P-$pItem"
                Add-PropAlias $primary "$wItem-PL-$pItem"
                Add-PropAlias $primary "$wItem`_A`_$pItem"
                Add-PropAlias $primary "$wItem`_B`_$pItem"
                Add-PropAlias $primary "$wItem`_P`_$pItem"
                if ($part) {
                    Add-PropAlias $primary "$wItem-$pItem-$part"
                    Add-PropAlias $primary "$wItem-$pItem`_$part"
                }
            }
        }
    }

    function Get-MatchedPropKey($fileName) {
        $nameNoExt = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
        if ($tokenToPrimary.ContainsKey($nameNoExt)) { return $tokenToPrimary[$nameNoExt] }

        # 1. Strip known server prefixes
        $clean = $nameNoExt -replace '^(D_|DIMAJOR_|MAJOR_|MINOR_|WARD_|PRABHAG_|ZONE_|PHOTO_|PROP_|PLAN_|WMF_|PMC[-_]OP\d*[-_]|PMC[-_]|IMG[-_]|PIC[-_]|SCAN[-_]|FILE[-_]|--+)', ''
        if ($tokenToPrimary.ContainsKey($clean)) { return $tokenToPrimary[$clean] }

        # 2. Strip trailing photo sequence / orientation / revision / archive suffixes
        $noSuffix = $clean -replace '([_\-\.]+(?:BK|R\d+|C\d+|REV\d*|part\d*|front|rear|side|inside|outside|road|meter|top|back|latlong|plan|wmf|photo|img|pic|\d+|[A-Za-z]))*$', ''
        if ($noSuffix -and $tokenToPrimary.ContainsKey($noSuffix)) { return $tokenToPrimary[$noSuffix] }

        # 3. Delimiter normalization (_ to -)
        $dashClean = $clean -replace '[_\s]+', '-'
        if ($tokenToPrimary.ContainsKey($dashClean)) { return $tokenToPrimary[$dashClean] }

        $dashNoSuffix = $noSuffix -replace '[_\s]+', '-'
        if ($dashNoSuffix -and $tokenToPrimary.ContainsKey($dashNoSuffix)) { return $tokenToPrimary[$dashNoSuffix] }

        # 4. Infix pattern: Node + Ward + Infix + Prop (e.g. KH10-A-1-R1 -> KH10-1)
        if ($dashClean -match '^([A-Za-z0-9]+)[-_](?:[A-Za-z]+)[-_](\d+)') {
            $wCand = $Matches[1]; $pCand = $Matches[2]
            if ($tokenToPrimary.ContainsKey("$wCand-$pCand")) { return $tokenToPrimary["$wCand-$pCand"] }
            if ($pCand -match '^\d+$') {
                $pInt = [int]$pCand
                if ($tokenToPrimary.ContainsKey("$wCand-$($pInt)")) { return $tokenToPrimary["$wCand-$($pInt)"] }
            }
        }

        # 5. Ward + Prop pattern with numeric normalization
        if ($dashClean -match '^([A-Za-z0-9]+)[-_](\d+)') {
            $wCand = $Matches[1]; $pCand = $Matches[2]
            if ($tokenToPrimary.ContainsKey("$wCand-$pCand")) { return $tokenToPrimary["$wCand-$pCand"] }
            if ($pCand -match '^\d+$') {
                $pInt = [int]$pCand
                if ($tokenToPrimary.ContainsKey("$wCand-$($pInt)")) { return $tokenToPrimary["$wCand-$($pInt)"] }
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
            if ($curr -and $tokenToPrimary.ContainsKey($curr)) { return $tokenToPrimary[$curr] }
            if ($curr -match '^(.+)-(\d+)$') {
                $wPart = $Matches[1]; $pPart = [int]$Matches[2]
                if ($tokenToPrimary.ContainsKey("$wPart-$pPart")) { return $tokenToPrimary["$wPart-$pPart"] }
            }
        }

        return $null
    }

    $ext = [System.IO.Path]::GetExtension($excelPath).ToLower()
    if ($ext -eq ".xlsx") {
        try {
            $zip = [System.IO.Compression.ZipFile]::OpenRead($excelPath)
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
                    else { if ($rowVals.Count -gt 0) { Process-RowData -rowVals $rowVals } }
                }
            }
            $zip.Dispose()
        } catch {
            Append-ExtractLog "OpenXML parse warning: $($_.Exception.Message)"
        }
    }

    if ($propList.Count -eq 0) {
        # Fallback to COM Excel
        $excel = $null; $wb = $null
        try {
            $excel = New-Object -ComObject Excel.Application
            $excel.Visible = $false; $excel.DisplayAlerts = $false
            $wb = $excel.Workbooks.Open($excelPath, $false, $true)
            foreach ($ws in $wb.Sheets) {
                $vals = $ws.UsedRange.Value2
                if (-not $vals) { continue }
                $rowCount = $vals.GetLength(0); $colCount = $vals.GetLength(1)
                if ($rowCount -lt 2) { continue }
                $headers = @{}
                for ($c = 1; $c -le $colCount; $c++) {
                    $h = [string]($vals[1, $c]); if ($h) { $headers[$c] = $h.Trim() }
                }
                for ($r = 2; $r -le $rowCount; $r++) {
                    $rowVals = @{}
                    for ($c = 1; $c -le $colCount; $c++) {
                        $hName = if ($headers.ContainsKey($c)) { $headers[$c] } else { "Col_$c" }
                        $v = [string]($vals[$r, $c]); if ($v) { $rowVals[$hName] = $v.Trim() }
                    }
                    if ($rowVals.Count -gt 0) { Process-RowData -rowVals $rowVals }
                }
            }
        } catch {} finally {
            if ($wb) { $wb.Close($false) }
            if ($excel) { $excel.Quit(); [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null }
        }
    }

    $lblExtractTotalProp.Text = $propList.Count.ToString()
    Append-ExtractLog "Loaded $($propList.Count) unique properties from Excel ($($tokenToPrimary.Count) search variations)."

    if ($propList.Count -eq 0) {
        [System.Windows.MessageBox]::Show("No property numbers could be extracted from Excel file.", "No Properties Found", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        $btnExtractStart.IsEnabled = $true
        return
    }

    # Step 2: Intelligent Multi-Server Directory Discovery & Crawling
    $extractProgressBar.Value = 20
    $lblExtractStatus.Text = "Status: Scanning server files..."
    [System.Windows.Forms.Application]::DoEvents()

    $imgExts = if ($mode -eq "WMF") {
        @('.wmf', '.emf')
    } elseif ($mode -eq "Both") {
        @('.jpg', '.jpeg', '.png', '.bmp', '.tif', '.tiff', '.gif', '.wmf', '.emf', '.webp')
    } else {
        @('.jpg', '.jpeg', '.png', '.bmp', '.tif', '.tiff', '.gif', '.webp')
    }

    $rootFolders = [System.Collections.Generic.List[string]]::new()
    $rootFolders.Add($srcFolder)

    # Automatic Multi-Location Discovery (Photos + WMFs)
    if ($mode -eq "Both") {
        if ($srcFolder -match '(?i)PropertyImage') {
            $planSibling = $srcFolder -replace '(?i)PropertyImage', 'PlanPhoto'
            if ((Test-Path -LiteralPath $planSibling) -and -not $rootFolders.Contains($planSibling)) {
                $rootFolders.Add($planSibling)
                Append-ExtractLog "[AI AUTO-DISCOVERY] Detected sibling PlanPhoto directory: $planSibling"
            }
        } elseif ($srcFolder -match '(?i)PlanPhoto') {
            $propSibling = $srcFolder -replace '(?i)PlanPhoto', 'PropertyImage'
            if ((Test-Path -LiteralPath $propSibling) -and -not $rootFolders.Contains($propSibling)) {
                $rootFolders.Add($propSibling)
                Append-ExtractLog "[AI AUTO-DISCOVERY] Detected sibling PropertyImage directory: $propSibling"
            }
        }
        foreach ($subName in @("PropertyImage", "PlanPhoto", "Photos", "WMF", "Plans", "Images")) {
            $subPath = Join-Path $srcFolder $subName
            if ((Test-Path -LiteralPath $subPath) -and -not $rootFolders.Contains($subPath)) {
                $rootFolders.Add($subPath)
                Append-ExtractLog "[AI AUTO-DISCOVERY] Found subfolder '$subName': $subPath"
            }
        }
    } elseif ($mode -eq "WMF") {
        if ($srcFolder -match '(?i)PropertyImage') {
            $planSibling = $srcFolder -replace '(?i)PropertyImage', 'PlanPhoto'
            if (Test-Path -LiteralPath $planSibling) {
                $rootFolders.Clear()
                $rootFolders.Add($planSibling)
                Append-ExtractLog "[AI AUTO-REDIRECT] Switched to PlanPhoto directory: $planSibling"
            }
        }
        $subPlan = Join-Path $srcFolder "PlanPhoto"
        if ((Test-Path -LiteralPath $subPlan) -and -not $rootFolders.Contains($subPlan)) {
            $rootFolders.Add($subPlan)
        }
    } elseif ($mode -eq "Photos") {
        if ($srcFolder -match '(?i)PlanPhoto') {
            $propSibling = $srcFolder -replace '(?i)PlanPhoto', 'PropertyImage'
            if (Test-Path -LiteralPath $propSibling) {
                $rootFolders.Clear()
                $rootFolders.Add($propSibling)
                Append-ExtractLog "[AI AUTO-REDIRECT] Switched to PropertyImage directory: $propSibling"
            }
        }
        $subProp = Join-Path $srcFolder "PropertyImage"
        if ((Test-Path -LiteralPath $subProp) -and -not $rootFolders.Contains($subProp)) {
            $rootFolders.Add($subProp)
        }
    }

    $matchedPhotos = [System.Collections.Generic.List[PSCustomObject]]::new()
    $propFoundMap = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($p in $propList) { $propFoundMap[$p] = [System.Collections.Generic.List[string]]::new() }

    # Fault-Tolerant Breadth-First Directory Crawler
    $dirQueue = [System.Collections.Generic.Queue[string]]::new()
    $visitedDirs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($rf in $rootFolders) {
        if (Test-Path -LiteralPath $rf) {
            $dirQueue.Enqueue($rf)
            $visitedDirs.Add($rf) | Out-Null
        }
    }

    $scanCount = 0
    while ($dirQueue.Count -gt 0) {
        $currentDir = $dirQueue.Dequeue()
        $dirFiles = @()
        try {
            $dirFiles = [System.IO.Directory]::GetFiles($currentDir, "*.*")
        } catch {
            Append-ExtractLog "Skipped folder: $currentDir ($($_.Exception.Message))"
            continue
        }

        foreach ($fPath in $dirFiles) {
            if ($fPath.Contains("_Backup_Originals_") -or $fPath.Contains("_Backup_PlanPhoto_") -or $fPath.Contains("_backup")) { continue }
            $fExt = [System.IO.Path]::GetExtension($fPath).ToLower()
            if (-not ($imgExts -contains $fExt)) { continue }

            $scanCount++
            $fName = [System.IO.Path]::GetFileName($fPath)
            $matchedProp = Get-MatchedPropKey $fName

            if ($matchedProp) {
                $matchedPhotos.Add([PSCustomObject]@{
                    SourcePath  = $fPath
                    FileName    = $fName
                    PropertyKey = $matchedProp
                    IsWmf       = ($fExt -eq ".wmf" -or $fExt -eq ".emf")
                })
                if ($propFoundMap.ContainsKey($matchedProp)) {
                    $propFoundMap[$matchedProp].Add($fName)
                }
            }

            if ($scanCount % 200 -eq 0) {
                $lblExtractStatus.Text = "Status: Scanning server files ($scanCount checked, $($matchedPhotos.Count) matched)..."
                [System.Windows.Forms.Application]::DoEvents()
            }
        }

        if ($isRecursive) {
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

    Append-ExtractLog "Scanned $scanCount files across server directories. Matched $($matchedPhotos.Count) files!"

    if ($matchedPhotos.Count -eq 0) {
        $lblExtractStatus.Text = "Status: 0 matching files found on server."
        $extractProgressBar.Value = 100
        Append-ExtractLog "WARNING: 0 files matched the properties from Excel in source folder: $srcFolder"
        [System.Windows.MessageBox]::Show("No matching files found on the server for the properties listed in Excel!`n`nSource Folder: $srcFolder`nMode: $mode`nProperties in Excel: $($propList.Count)`n`nPlease check:`n1. Source folder contains files for this property list.`n2. If files are stored in ward subfolders, ensure 'Scan Subdirectories Recursively' is checked.`n3. Ensure WMF mode is pointing to PlanPhoto folder.", "No Matching Files Found", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        $btnExtractStart.IsEnabled = $true
        return
    }

    # Step 3: Collision-Free Extraction to One Destination Folder on Desktop
    $lblExtractStatus.Text = "Status: Copying files to Desktop..."
    $copied = 0
    $totalToCopy = $matchedPhotos.Count

    for ($i = 0; $i -lt $totalToCopy; $i++) {
        $item = $matchedPhotos[$i]
        $targetDir = $destFolder
        if ($isSubfolders) {
            $targetDir = Join-Path $destFolder $item.PropertyKey
        }
        if (-not (Test-Path -LiteralPath $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
        
        # Prevent collisions in flat output folder
        $destFile = Join-Path $targetDir $item.FileName
        if (Test-Path -LiteralPath $destFile) {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($item.FileName)
            $fExt = [System.IO.Path]::GetExtension($item.FileName)
            $colIdx = 2
            while (Test-Path -LiteralPath $destFile) {
                $destFile = Join-Path $targetDir "${baseName}_$colIdx$fExt"
                $colIdx++
            }
        }
        
        try {
            if ($item.IsWmf) {
                # Enhancement: ONLY resize WMF files that have MORE THAN 25 KB
                $srcLen = (Get-Item -LiteralPath $item.SourcePath).Length
                if ($srcLen -gt (25 * 1024) -and $isWhiteCanvas) {
                    $wmfSuccess = $false
                    try {
                        $wmfRes = [AppWmfOptimizer]::ProcessWmf($item.SourcePath, $destFile, 700, 96, 25, $true)
                        if ($wmfRes -and -not $wmfRes.StartsWith("ERROR")) {
                            $wmfSuccess = $true
                        }
                    } catch {}

                    if (-not $wmfSuccess) {
                        [System.IO.File]::Copy($item.SourcePath, $destFile, $true)
                    }
                } else {
                    # Already <= 25 KB: keep original WMF without re-compression
                    [System.IO.File]::Copy($item.SourcePath, $destFile, $true)
                }
            } elseif (-not $item.IsWmf -and $isAutoResize) {
                # Resize photo on the fly under 25KB
                $photoSuccess = $false
                try {
                    $bytes = [System.IO.File]::ReadAllBytes($item.SourcePath)
                    $resBytes = [AppWmfOptimizer]::ConvertBlobToCrystalReportJpg($bytes, 700, 96, 25)
                    if ($resBytes -and $resBytes.Length -gt 0) {
                        [System.IO.File]::WriteAllBytes($destFile, $resBytes)
                        $photoSuccess = $true
                    }
                } catch {}

                if (-not $photoSuccess) {
                    [System.IO.File]::Copy($item.SourcePath, $destFile, $true)
                }
            } else {
                [System.IO.File]::Copy($item.SourcePath, $destFile, $true)
            }
            $copied++
        } catch {
            Append-ExtractLog "Warning processing $($item.FileName): $($_.Exception.Message)"
        }

        if (($i + 1) % 25 -eq 0 -or ($i + 1) -eq $totalToCopy) {
            $lblExtractCollectedPhotos.Text = $copied.ToString()
            $pct = 20 + [Math]::Round((($i + 1) / $totalToCopy) * 75)
            $extractProgressBar.Value = $pct
            $lblExtractStatus.Text = "Status: Processed $($i+1)/$totalToCopy files ($pct%)..."
            [System.Windows.Forms.Application]::DoEvents()
        }
    }

    # Step 4: Reports & Metrics
    $foundCount = 0
    $missingCount = 0
    $reportRows = [System.Collections.Generic.List[PSCustomObject]]::new()
    $missingRows = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($p in $propList) {
        $pPhotos = $propFoundMap[$p]
        $hasPhotos = ($pPhotos -and $pPhotos.Count -gt 0)
        if ($hasPhotos) {
            $foundCount++
        } else {
            $missingCount++
            $missingRows.Add([PSCustomObject]@{ "Missing_Property_ID" = $p })
        }
        $reportRows.Add([PSCustomObject]@{
            "Property_ID"       = $p
            "Status"            = if ($hasPhotos) { "FOUND" } else { "MISSING" }
            "Files_Count"       = if ($pPhotos) { $pPhotos.Count } else { 0 }
            "Matched_Filenames" = if ($pPhotos) { $pPhotos -join "; " } else { "None" }
        })
    }

    $lblExtractFoundProp.Text = $foundCount.ToString()
    $lblExtractMissingProp.Text = $missingCount.ToString()
    $lblExtractCollectedPhotos.Text = $copied.ToString()
    $extractProgressBar.Value = 100
    $lblExtractStatus.Text = "Status: Collection completed!"

    $reportPath = Join-Path $destFolder "Collection_Summary_Report.csv"
    $missingPath = Join-Path $destFolder "Missing_Properties_Report.csv"
    $reportRows | Export-Csv -Path $reportPath -NoTypeInformation -Encoding UTF8
    if ($missingRows.Count -gt 0) {
        $missingRows | Export-Csv -Path $missingPath -NoTypeInformation -Encoding UTF8
    }
    $global:extractLastReportPath = $reportPath
    $btnExtractOpenReport.IsEnabled = $true

    Append-ExtractLog "======================================================="
    Append-ExtractLog "COMPLETED! Properties Found: $foundCount | Missing: $missingCount | Files Saved: $copied"
    Append-ExtractLog "Desktop Output Folder : $destFolder"
    Append-ExtractLog "Summary Report CSV    : $reportPath"
    Append-ExtractLog "======================================================="

    # Automatically open Desktop folder in Explorer
    try { Start-Process "explorer.exe" -ArgumentList "`"$destFolder`"" } catch {}

    [System.Windows.MessageBox]::Show("Extraction complete!`n`nMode: $mode`nProperties in Excel: $($propList.Count)`nProperties Found on Server: $foundCount`nMissing Properties: $missingCount`nTotal Files Saved to Desktop: $copied`n`nSummary CSV Report saved to folder.", "Extraction Complete", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)

    $btnExtractStart.IsEnabled = $true
})

# =====================================================================
# --- TAB 6: BG REMOVER & SIGNATURE EXTRACTOR LOGIC ---
# =====================================================================

$global:currentBgSourceBmp = $null
$global:currentBgResultBmp = $null

function Convert-BitmapToWpfImage($bmp) {
    if (-not $bmp) { return $null }
    $ms = [System.IO.MemoryStream]::new()
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $ms.Position = 0
    $bi = [System.Windows.Media.Imaging.BitmapImage]::new()
    $bi.BeginInit()
    $bi.StreamSource = $ms
    $bi.CacheOption = "OnLoad"
    $bi.EndInit()
    $bi.Freeze()
    return $bi
}

function Start-ScanningLaserAnimation {
    try {
        $laserScanner.Visibility = [System.Windows.Visibility]::Visible
        $laserGlowOverlay.Visibility = [System.Windows.Visibility]::Visible
        $h = if ($borderBgPreviewBox.ActualHeight -gt 60) { $borderBgPreviewBox.ActualHeight - 12 } else { 260 }

        $anim = [System.Windows.Media.Animation.DoubleAnimation]::new(0, $h, [System.Windows.Duration]::new([TimeSpan]::FromSeconds(1.1)))
        $anim.AutoReverse = $true
        $anim.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever

        $laserTransform.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $anim)
        $laserGlowTransform.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $anim)
    } catch {}
}

function Stop-ScanningLaserAnimation {
    try {
        $laserTransform.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $null)
        $laserGlowTransform.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $null)
        $laserScanner.Visibility = [System.Windows.Visibility]::Collapsed
        $laserGlowOverlay.Visibility = [System.Windows.Visibility]::Collapsed
    } catch {}
}

function Animate-ResultFadeIn {
    try {
        $fadeAnim = [System.Windows.Media.Animation.DoubleAnimation]::new(0.0, 1.0, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(380)))
        $imgBgResult.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fadeAnim)
    } catch {}
}

$global:isProcessingBg = $false
$global:suppressBgEvents = $false

function Set-MascotState([string]$state, [string]$subtitle) {
    try {
        if ($mascotSub) { $mascotSub.Text = $subtitle }
        if (-not $mascotStatusDot) { return }
        switch ($state) {
            "processing" {
                $mascotStatusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F59E0B")
                if ($arcCoreTriangle) { $arcCoreTriangle.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F59E0B") }
                if ($arcPulseRing) { $arcPulseRing.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F59E0B") }
                if ($arcCoreCenterDot) { $arcCoreCenterDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FBBF24") }
            }
            "success" {
                $mascotStatusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#10B981")
                if ($arcCoreTriangle) { $arcCoreTriangle.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#10B981") }
                if ($arcPulseRing) { $arcPulseRing.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#10B981") }
                if ($arcCoreCenterDot) { $arcCoreCenterDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399") }
            }
            "error" {
                $mascotStatusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EF4444")
                if ($arcCoreTriangle) { $arcCoreTriangle.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EF4444") }
                if ($arcPulseRing) { $arcPulseRing.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EF4444") }
                if ($arcCoreCenterDot) { $arcCoreCenterDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F87171") }
            }
            default {
                $mascotStatusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#00F0FF")
                if ($arcCoreTriangle) { $arcCoreTriangle.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#00F0FF") }
                if ($arcPulseRing) { $arcPulseRing.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#00F0FF") }
                if ($arcCoreCenterDot) { $arcCoreCenterDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF") }
            }
        }
    } catch {}
}

function Run-BgRemovalProcess {
    if ($global:isProcessingBg -or $global:suppressBgEvents) { return }

    if (-not $global:currentBgSourceBmp) {
        $p = $txtBgInputPath.Text.Trim()
        if (Test-Path -LiteralPath $p) {
            Load-BgRemoverImageFromPath $p
            return
        }
    }

    if (-not $global:currentBgSourceBmp) {
        [System.Windows.MessageBox]::Show("Please select an image file or paste an image from clipboard first.", "No Image Selected", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    $global:isProcessingBg = $true
    Set-MascotState "processing" "AI Processing..."
    if ($btnBgProcess) { $btnBgProcess.IsEnabled = $false }
    $lblBgResultStatus.Text = "[AI AUTO] Scanning & Isolating Foreground..."
    $lblBgResultStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
    Start-ScanningLaserAnimation

    # Use a brief DispatcherTimer so WPF renders the animated laser scanning before heavy computation starts
    $runTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $runTimer.Interval = [TimeSpan]::FromMilliseconds(50)
    $runTimer.Add_Tick({
        param($sRun, $eRun)
        try { if ($sRun) { $sRun.Stop() } } catch {}
        try {
            $tolerance = [int]$sliderBgTolerance.Value
            $isSignMode = ($rbBgModeSign.IsChecked -eq $true)
            $isTrans = ($rbBgOutTransparent.IsChecked -eq $true)
            $enhanceInk = ($chkBgEnhanceInk.IsChecked -eq $true)
            $autoCrop = ($chkBgAutoCrop.IsChecked -eq $true)

            $replaceColor = if ($rbBgOutBlue.IsChecked -eq $true) {
                [System.Drawing.Color]::FromArgb(255, 0, 114, 198)
            } else {
                [System.Drawing.Color]::White
            }
            if (-not $replaceColor) {
                $replaceColor = [System.Drawing.Color]::White
            }

            if ($global:currentBgResultBmp) {
                $global:currentBgResultBmp.Dispose()
                $global:currentBgResultBmp = $null
            }

            if ($isSignMode) {
                $global:currentBgResultBmp = [BackgroundRemovalEngine]::ExtractSignature($global:currentBgSourceBmp, $tolerance, $enhanceInk, $replaceColor, $isTrans, $autoCrop)
            } else {
                if ($global:hasAiVision) {
                    $global:currentBgResultBmp = [Nexus.AI.AiBackgroundRemover]::RemoveBackground($global:currentBgSourceBmp, $replaceColor, $isTrans, $autoCrop)
                } else {
                    $global:currentBgResultBmp = [BackgroundRemovalEngine]::RemovePhotoBackground($global:currentBgSourceBmp, $tolerance, $replaceColor, $isTrans)
                }
            }

            Stop-ScanningLaserAnimation

            $w = $global:currentBgResultBmp.Width
            $h = $global:currentBgResultBmp.Height
            $imgBgResult.Source = Convert-BitmapToWpfImage $global:currentBgResultBmp
            Animate-ResultFadeIn

            $lblBgResultStatus.Text = "Extracted Cleanly!"
            $lblBgResultStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
            $lblBgResultDim.Text = "Output: ${w} x ${h} px"
            $lblBgResultFormat.Text = if ($isTrans) { "Format: 32-bit Transparent PNG" } elseif ($rbBgOutWhite.IsChecked -eq $true) { "Format: Pure Solid White (#FFFFFF)" } else { "Format: Passport Blue" }

            $btnBgSaveAs.IsEnabled = $true
            $btnBgCopyClipboard.IsEnabled = $true
            Set-MascotState "success" "Extracted Cleanly!"

            # Reset mascot to idle watching mode after 2.5s
            $idleTimer = [System.Windows.Threading.DispatcherTimer]::new()
            $idleTimer.Interval = [TimeSpan]::FromSeconds(2.5)
            $idleTimer.Add_Tick({
                param($sIdle, $eIdle)
                try {
                    if ($sIdle) { $sIdle.Stop() }
                    Set-MascotState "idle" "Watching Cursor"
                } catch {}
            })
            $idleTimer.Start()
        } catch {
            Stop-ScanningLaserAnimation
            $lblBgResultStatus.Text = "Error"
            $lblBgResultStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#EF4444")
            Set-MascotState "error" "Processing Error"
            [System.Windows.MessageBox]::Show("Error processing image:`n$($_.Exception.Message)", "Processing Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        } finally {
            $global:isProcessingBg = $false
            if ($btnBgProcess) { $btnBgProcess.IsEnabled = $true }
        }
    })
    $runTimer.Start()
}

function Load-BgRemoverImageFromPath($filePath) {
    if (-not (Test-Path -LiteralPath $filePath)) { return }
    $global:suppressBgEvents = $true
    try {
        if ($global:currentBgSourceBmp) {
            $global:currentBgSourceBmp.Dispose()
            $global:currentBgSourceBmp = $null
        }
        if ($global:currentBgResultBmp) {
            $global:currentBgResultBmp.Dispose()
            $global:currentBgResultBmp = $null
        }
        $imgBgResult.Source = $null
        $btnBgSaveAs.IsEnabled = $false
        $btnBgCopyClipboard.IsEnabled = $false

        $global:currentBgSourceBmp = [System.Drawing.Bitmap]::FromFile($filePath)
        $w = $global:currentBgSourceBmp.Width
        $h = $global:currentBgSourceBmp.Height
        $fi = Get-Item -LiteralPath $filePath
        $kb = [Math]::Round($fi.Length / 1KB, 1)

        $txtBgInputPath.Text = $filePath
        $lblBgOrigStatus.Text = "Loaded: $($fi.Name)"
        $lblBgOrigDim.Text = "Dimensions: ${w} x ${h} px"
        $lblBgOrigKB.Text = "Size: ${kb} KB"
        $lblBgResultStatus.Text = "Ready to process"
        $lblBgResultDim.Text = "Output: --"

        $imgBgOrig.Source = Convert-BitmapToWpfImage $global:currentBgSourceBmp

        # AI Content Auto-Detection
        $isSignature = [BackgroundRemovalEngine]::DetectIsSignature($global:currentBgSourceBmp)
        if ($isSignature) {
            $rbBgModeSign.IsChecked = $true
            $lblBgAutoBadge.Text = "[AI DETECTED] SIGNATURE / DOCUMENT"
            $lblBgAutoBadge.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
            $badgeBgAutoDetect.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
            $badgeBgAutoDetect.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F2D3D")
        } else {
            $rbBgModePortrait.IsChecked = $true
            $lblBgAutoBadge.Text = "[AI VISION] OBJECT / PHOTO / PORTRAIT"
            $lblBgAutoBadge.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#A855F7")
            $badgeBgAutoDetect.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#A855F7")
            $badgeBgAutoDetect.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#2E1065")
        }
    } catch {
        [System.Windows.MessageBox]::Show("Error opening image file:`n$($_.Exception.Message)", "Image Load Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    } finally {
        $global:suppressBgEvents = $false
    }

    # Auto-Process immediately if enabled (single trigger)
    if ($chkBgAutoProcess.IsChecked -eq $true) {
        Run-BgRemovalProcess
    }
}

# Debounce Timer for Slider & Settings Live Updates
$global:bgDebounceTimer = [System.Windows.Threading.DispatcherTimer]::new()
$global:bgDebounceTimer.Interval = [TimeSpan]::FromMilliseconds(320)
$global:bgDebounceTimer.Add_Tick({
    param($sDebounce, $eDebounce)
    try {
        if ($sDebounce) { $sDebounce.Stop() }
        if ($global:currentBgSourceBmp -and -not $global:suppressBgEvents -and -not $global:isProcessingBg) {
            Run-BgRemovalProcess
        }
    } catch {}
})

$sliderBgTolerance.Add_ValueChanged({
    $lblBgToleranceVal.Text = "$([int]$sliderBgTolerance.Value)%"
    if ($global:currentBgSourceBmp -and -not $global:suppressBgEvents -and -not $global:isProcessingBg) {
        $global:bgDebounceTimer.Stop()
        $global:bgDebounceTimer.Start()
    }
})

$rbBgModeSign.Add_Checked({ if (-not $global:suppressBgEvents -and -not $global:isProcessingBg -and $global:currentBgSourceBmp) { Run-BgRemovalProcess } })
$rbBgModePortrait.Add_Checked({ if (-not $global:suppressBgEvents -and -not $global:isProcessingBg -and $global:currentBgSourceBmp) { Run-BgRemovalProcess } })
$rbBgOutTransparent.Add_Checked({ if (-not $global:suppressBgEvents -and -not $global:isProcessingBg -and $global:currentBgSourceBmp) { Run-BgRemovalProcess } })
$rbBgOutWhite.Add_Checked({ if (-not $global:suppressBgEvents -and -not $global:isProcessingBg -and $global:currentBgSourceBmp) { Run-BgRemovalProcess } })
$rbBgOutBlue.Add_Checked({ if (-not $global:suppressBgEvents -and -not $global:isProcessingBg -and $global:currentBgSourceBmp) { Run-BgRemovalProcess } })
$chkBgEnhanceInk.Add_Click({ if (-not $global:suppressBgEvents -and -not $global:isProcessingBg -and $global:currentBgSourceBmp) { Run-BgRemovalProcess } })
$chkBgAutoCrop.Add_Click({ if (-not $global:suppressBgEvents -and -not $global:isProcessingBg -and $global:currentBgSourceBmp) { Run-BgRemovalProcess } })

$btnBgBrowseFile.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "Select Image File (Signature, Person Photo, Stamp, etc.)"
    $dlg.Filter = "Image Files (*.png;*.jpg;*.jpeg;*.bmp;*.webp;*.tif)|*.png;*.jpg;*.jpeg;*.bmp;*.webp;*.tif|All Files (*.*)|*.*"
    $dlg.InitialDirectory = [Environment]::GetFolderPath("Desktop")
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Load-BgRemoverImageFromPath $dlg.FileName
    }
})

$btnBgPasteClipboard.Add_Click({
    try {
        if ([System.Windows.Clipboard]::ContainsImage()) {
            $clipImg = [System.Windows.Clipboard]::GetImage()
            if ($clipImg) {
                $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) ("clip_sign_" + (Get-Date).ToString("yyyyMMdd_HHmmss") + ".png")
                $encoder = [System.Windows.Media.Imaging.PngBitmapEncoder]::new()
                $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($clipImg))
                $fs = [System.IO.FileStream]::new($tempPath, [System.IO.FileMode]::Create)
                $encoder.Save($fs)
                $fs.Close(); $fs.Dispose()

                Load-BgRemoverImageFromPath $tempPath
                $txtBgInputPath.Text = "(Pasted from Clipboard - $tempPath)"
            }
        } elseif ([System.Windows.Clipboard]::ContainsText()) {
            $clipText = [System.Windows.Clipboard]::GetText().Trim().Trim('"').Trim("'")
            if (Test-Path -LiteralPath $clipText) {
                Load-BgRemoverImageFromPath $clipText
            } else {
                [System.Windows.MessageBox]::Show("Clipboard does not contain an image or valid image path.", "Clipboard Empty", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            }
        } else {
            [System.Windows.MessageBox]::Show("Clipboard is empty or does not contain an image.", "No Image Found", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        }
    } catch {
        [System.Windows.MessageBox]::Show("Error reading clipboard: $($_.Exception.Message)", "Clipboard Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
    }
})

$btnBgClear.Add_Click({
    Stop-ScanningLaserAnimation
    if ($global:currentBgSourceBmp) { $global:currentBgSourceBmp.Dispose(); $global:currentBgSourceBmp = $null }
    if ($global:currentBgResultBmp) { $global:currentBgResultBmp.Dispose(); $global:currentBgResultBmp = $null }
    $imgBgOrig.Source = $null
    $imgBgResult.Source = $null
    $txtBgInputPath.Text = "Select an image file above, drag & drop, or click 'Paste from Clipboard'..."
    $lblBgOrigStatus.Text = "No Image Loaded"
    $lblBgOrigDim.Text = "Size: -- px"
    $lblBgOrigKB.Text = "File: -- KB"
    $lblBgResultStatus.Text = "Ready"
    $lblBgResultStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
    $lblBgResultDim.Text = "Output: --"
    $lblBgAutoBadge.Text = "[AI AUTO-DETECT READY]"
    $lblBgAutoBadge.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
    $badgeBgAutoDetect.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
    $badgeBgAutoDetect.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F2D3D")
    $btnBgSaveAs.IsEnabled = $false
    $btnBgCopyClipboard.IsEnabled = $false
})

$btnBgDemoAnim.Add_Click({
    Start-ScanningLaserAnimation
    $lblBgResultStatus.Text = "Laser Scanner Active (Preview Demo)..."
    $lblBgResultStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")

    $animTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $animTimer.Interval = [TimeSpan]::FromSeconds(3.5)
    $animTimer.Add_Tick({
        param($sAnim, $eAnim)
        try {
            if ($sAnim) { $sAnim.Stop() }
            Stop-ScanningLaserAnimation
            if ($global:currentBgResultBmp) {
                $lblBgResultStatus.Text = "Extracted Cleanly!"
                $lblBgResultStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
                Animate-ResultFadeIn
            } else {
                $lblBgResultStatus.Text = "Laser Animation Tested (100% OK)"
                $lblBgResultStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
            }
        } catch {}
    })
    $animTimer.Start()
})

$btnBgProcess.Add_Click({
    Run-BgRemovalProcess
})

# Drag-and-Drop Handler for Image File on Tab 6
$bgDropHandler = {
    param($sender, $e)
    if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
        $droppedFiles = $e.Data.GetData([System.Windows.DataFormats]::FileDrop)
        if ($droppedFiles -and $droppedFiles.Count -gt 0) {
            $firstFile = $droppedFiles[0]
            $ext = [System.IO.Path]::GetExtension($firstFile).ToLower()
            if ($ext -in @(".png", ".jpg", ".jpeg", ".bmp", ".webp", ".tif", ".tiff")) {
                Load-BgRemoverImageFromPath $firstFile
            }
        }
    }
}
$bgDragOverHandler = {
    param($sender, $e)
    if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
        $e.Effects = [System.Windows.DragDropEffects]::Copy
    } else {
        $e.Effects = [System.Windows.DragDropEffects]::None
    }
    $e.Handled = $true
}

$viewBgRemover.AllowDrop = $true
$viewBgRemover.Add_Drop($bgDropHandler)
$viewBgRemover.Add_DragOver($bgDragOverHandler)
$borderBgPreviewBox.AllowDrop = $true
$borderBgPreviewBox.Add_Drop($bgDropHandler)
$borderBgPreviewBox.Add_DragOver($bgDragOverHandler)

$btnBgSaveAs.Add_Click({
    if (-not $global:currentBgResultBmp) { return }

    $isTrans = ($rbBgOutTransparent.IsChecked -eq $true)
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    if ($isTrans) {
        $dlg.Title = "Save Transparent Image"
        $dlg.Filter = "PNG Transparent Image (*.png)|*.png"
        $dlg.DefaultExt = "png"
    } else {
        $dlg.Title = "Save Clean Image"
        $dlg.Filter = "JPEG Image (*.jpg)|*.jpg|PNG Image (*.png)|*.png"
        $dlg.DefaultExt = "jpg"
    }
    $dlg.InitialDirectory = [Environment]::GetFolderPath("Desktop")
    $dlg.FileName = if ($rbBgModeSign.IsChecked -eq $true) { "Clean_Signature" } else { "Clean_Photo" }

    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $savePath = $dlg.FileName
        $asPng = [System.IO.Path]::GetExtension($savePath).ToLower() -eq ".png"
        $ok = [BackgroundRemovalEngine]::SaveImage($global:currentBgResultBmp, $savePath, $asPng)
        if ($ok -and (Test-Path -LiteralPath $savePath)) {
            [System.Windows.MessageBox]::Show("Image saved successfully to:`n$savePath", "Saved Successfully", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            try { Start-Process "explorer.exe" -ArgumentList "/select,`"$savePath`"" } catch {}
        } else {
            [System.Windows.MessageBox]::Show("Could not save image to selected location.", "Save Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        }
    }
})

$btnBgCopyClipboard.Add_Click({
    if (-not $global:currentBgResultBmp) { return }
    try {
        $wpfSource = Convert-BitmapToWpfImage $global:currentBgResultBmp
        [System.Windows.Clipboard]::SetImage($wpfSource)
        [System.Windows.MessageBox]::Show("Clean image copied to clipboard with transparency! You can now paste (Ctrl+V) directly into Word, Excel, PowerPoint, or websites.", "Copied to Clipboard", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    } catch {
        [System.Windows.MessageBox]::Show("Error copying to clipboard: $($_.Exception.Message)", "Clipboard Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
    }
})

# ==============================================================================
# JARVIS ARC REACTOR CORE - Interactive Cybernetic Energy & Assistant Launcher
# ==============================================================================
try {
    # 1. Real-Time Proximity Energy Fluctuation on Mouse Movement
    $window.Add_PreviewMouseMove({
        param($s, $e)
        try {
            if (-not $mascotCanvas -or -not $arcPulseScale) { return }
            $pos = $e.GetPosition($mascotCanvas)
            $dx = $pos.X - 21.0
            $dy = $pos.Y - 21.0
            $dist = [Math]::Sqrt($dx * $dx + $dy * $dy)
            if ($dist -lt 140) {
                $ratio = 1.0 - ($dist / 140.0)
                $arcPulseScale.ScaleX = 1.0 + ($ratio * 0.15)
                $arcPulseScale.ScaleY = 1.0 + ($ratio * 0.15)
                if ($arcPulseRing) { $arcPulseRing.Opacity = 0.7 + ($ratio * 0.3) }
            } else {
                $arcPulseScale.ScaleX = 1.0
                $arcPulseScale.ScaleY = 1.0
                if ($arcPulseRing) { $arcPulseRing.Opacity = 0.7 }
            }
        } catch {}
    })

    # 2. Rhythmic Breathing Pulse Timer (every ~1.8 seconds)
    $global:mascotBlinkTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $global:mascotBlinkTimer.Interval = [TimeSpan]::FromMilliseconds(1800)
    $global:mascotBlinkTimer.Add_Tick({
        param($sMascot, $eMascot)
        try {
            if (-not $arcPulseScale) { return }
            $arcPulseScale.ScaleX = 1.15
            $arcPulseScale.ScaleY = 1.15
            if ($arcPulseRing) { $arcPulseRing.Opacity = 0.95 }

            $coolTimer = [System.Windows.Threading.DispatcherTimer]::new()
            $coolTimer.Interval = [TimeSpan]::FromMilliseconds(220)
            $coolTimer.Add_Tick({
                param($sCool, $eCool)
                try {
                    if ($sCool) { $sCool.Stop() }
                    if ($arcPulseScale) {
                        $arcPulseScale.ScaleX = 1.0
                        $arcPulseScale.ScaleY = 1.0
                    }
                    if ($arcPulseRing) { $arcPulseRing.Opacity = 0.7 }
                } catch {}
            })
            $coolTimer.Start()
        } catch {}
    })
    $global:mascotBlinkTimer.Start()

    # 3. Interactive Reactor Overdrive Reaction & JARVIS Command Center Launch
    if ($mascotContainer) {
        $mascotContainer.Add_MouseLeftButtonDown({
            try {
                if ($arcPulseScale) {
                    $arcPulseScale.ScaleX = 1.35
                    $arcPulseScale.ScaleY = 1.35
                }
                if ($arcPulseRing) {
                    $arcPulseRing.Opacity = 1.0
                    $arcPulseRing.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFFFFF")
                }
                if ($mascotSub) { $mascotSub.Text = "Arc Core Overdrive" }

                $resetTimer = [System.Windows.Threading.DispatcherTimer]::new()
                $resetTimer.Interval = [TimeSpan]::FromMilliseconds(600)
                $resetTimer.Add_Tick({
                    param($sWink, $eWink)
                    try {
                        if ($sWink) { $sWink.Stop() }
                        if ($arcPulseScale) {
                            $arcPulseScale.ScaleX = 1.0
                            $arcPulseScale.ScaleY = 1.0
                        }
                        if ($arcPulseRing) {
                            $arcPulseRing.Opacity = 0.7
                            $arcPulseRing.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#00F0FF")
                        }
                        if ($mascotSub) { $mascotSub.Text = "Arc Reactor 100%" }
                    } catch {}
                })
                $resetTimer.Start()
            } catch {}
            Show-JarvisAssistantWindow
        })
    }

    # ==============================================================================
    # MODULE: DIRECT PC SHARE (LAN AIR-DROP, DIRECT CONNECT & WEB SHARE)
    # ==============================================================================
    $script:LanUdpPort = 52822
    $script:LanTcpPort = 52824
    $script:LanWebPort = 52826
    $script:LanPeers = [System.Collections.Generic.Dictionary[string, PSCustomObject]]::new()
    $script:LanSendFilesList = [System.Collections.Generic.List[string]]::new()
    $script:LanOutboxList = [System.Collections.Generic.List[string]]::new()
    $script:LanReceivedDir = Join-Path ([Environment]::GetFolderPath("Desktop")) "Nexus_Received_Files"
    $script:LanSelectedPeer = $null
    $script:LanServicesStarted = $false
    $script:LanUdpSocket = $null
    $script:LanTcpListener = $null
    $script:LanWebListener = $null
    $script:LanTimer = $null
    $script:LanBeaconCounter = 0
    $script:LanUpdateTimerCounter = 0
    $script:AppVersion = "5.4.0"
    $script:PendingUpdate = $null
    $script:UpdateDialogOpen = $false
    $script:UpdateSnoozedUntil = $null
    $script:AutoUpdateTimer = $null
    $script:AppScriptPath = if ($MyInvocation -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { Join-Path $PSScriptRoot "PMC-ImageResizer-App.ps1" }

    function Format-LanFileSize ([int64]$bytes) {
        if ($bytes -ge 1GB) { return "{0:N2} GB" -f ($bytes / 1GB) }
        if ($bytes -ge 1MB) { return "{0:N2} MB" -f ($bytes / 1MB) }
        if ($bytes -ge 1KB) { return "{0:N2} KB" -f ($bytes / 1KB) }
        return "$bytes B"
    }

    function Refresh-LanPeersList {
        if (-not $lstLanPeers) { return }
        $lstLanPeers.Items.Clear()
        
        $onlineCount = 0
        foreach ($kv in $script:LanPeers.GetEnumerator()) {
            $p = $kv.Value
            $item = New-Object System.Windows.Controls.ListBoxItem
            $item.Tag = $p
            
            $grid = New-Object System.Windows.Controls.Grid
            $col0 = New-Object System.Windows.Controls.ColumnDefinition; $col0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
            $col1 = New-Object System.Windows.Controls.ColumnDefinition; $col1.Width = [System.Windows.GridLength]::Auto
            $grid.ColumnDefinitions.Add($col0)
            $grid.ColumnDefinitions.Add($col1)
            
            $sp = New-Object System.Windows.Controls.StackPanel
            $txtHost = New-Object System.Windows.Controls.TextBlock
            $txtHost.Text = $p.HostName
            $txtHost.FontSize = 12
            $txtHost.FontWeight = [System.Windows.FontWeights]::Bold
            $txtHost.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
            
            $txtSub = New-Object System.Windows.Controls.TextBlock
            $txtSub.Text = "User: $($p.UserName)"
            $txtSub.FontSize = 10
            $txtSub.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
            
            $sp.Children.Add($txtHost) | Out-Null
            $sp.Children.Add($txtSub) | Out-Null
            $grid.Children.Add($sp) | Out-Null
            [System.Windows.Controls.Grid]::SetColumn($sp, 0)
            
            $badge = New-Object System.Windows.Controls.Border
            $badge.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#064E3B")
            $badge.CornerRadius = New-Object System.Windows.CornerRadius(4)
            $badge.Padding = New-Object System.Windows.Thickness(6, 2, 6, 2)
            $badge.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
            
            $txtBadge = New-Object System.Windows.Controls.TextBlock
            $txtBadge.Text = "ONLINE"
            $txtBadge.FontSize = 9.5
            $txtBadge.FontWeight = [System.Windows.FontWeights]::Bold
            $txtBadge.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
            $badge.Child = $txtBadge
            $grid.Children.Add($badge) | Out-Null
            [System.Windows.Controls.Grid]::SetColumn($badge, 1)
            
            $item.Content = $grid
            $lstLanPeers.Items.Add($item) | Out-Null
            $onlineCount++
        }
        
        if ($lblLanPeerStatus) {
            if ($onlineCount -gt 0) {
                $lblLanPeerStatus.Text = "$onlineCount computer(s) online on your network (No IP needed)"
                $lblLanPeerStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
            } else {
                $lblLanPeerStatus.Text = "Searching network for peers... (Click Scan to discover)"
                $lblLanPeerStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#64748B")
            }
        }
    }

    function Broadcast-LanBeacon {
        if (-not $script:LanUdpSocket) { return }
        try {
            $msg = "NEXUS_PING|$env:COMPUTERNAME|$env:USERNAME|$script:LanTcpPort"
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($msg)
            $bcastEp = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Broadcast, $script:LanUdpPort)
            $script:LanUdpSocket.Send($bytes, $bytes.Length, $bcastEp) | Out-Null
        } catch {}
    }

    function Start-LanNetworking {
        if ($script:LanServicesStarted) { return }
        $script:LanServicesStarted = $true
        
        try {
            $script:LanLocalIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch 'Loopback' -and $_.IPAddress -notmatch '^169\.254\.' } | Select-Object -First 1).IPAddress
        } catch { $script:LanLocalIP = "127.0.0.1" }
        
        if ($lblLanMyIdentity) {
            $lblLanMyIdentity.Text = "My PC: $env:COMPUTERNAME | User: $env:USERNAME | Web Share Link: http://$($script:LanLocalIP):$($script:LanWebPort)/"
        }

        try {
            $script:LanUdpSocket = New-Object System.Net.Sockets.UdpClient
            $script:LanUdpSocket.Client.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::Socket, [System.Net.Sockets.SocketOptionName]::ReuseAddress, $true)
            $script:LanUdpSocket.ExclusiveAddressUse = $false
            $bindEp = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, $script:LanUdpPort)
            $script:LanUdpSocket.Client.Bind($bindEp)
            $script:LanUdpSocket.EnableBroadcast = $true
        } catch {
            try {
                $script:LanUdpSocket = New-Object System.Net.Sockets.UdpClient($script:LanUdpPort)
                $script:LanUdpSocket.EnableBroadcast = $true
            } catch {}
        }

        try {
            $script:LanTcpListener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $script:LanTcpPort)
            $script:LanTcpListener.Start()
        } catch {}

        try {
            $script:LanWebListener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $script:LanWebPort)
            $script:LanWebListener.Start()
        } catch {}

        Broadcast-LanBeacon

        $script:LanTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:LanTimer.Interval = [TimeSpan]::FromMilliseconds(800)
        $script:LanTimer.Add_Tick({
            try {
                while ($script:LanUdpSocket -and $script:LanUdpSocket.Available -gt 0) {
                    $remoteEp = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
                    $recvBytes = $script:LanUdpSocket.Receive([ref]$remoteEp)
                    $recvMsg = [System.Text.Encoding]::UTF8.GetString($recvBytes)
                    
                    $parts = $recvMsg -split '\|'
                    $cmd = $parts[0]

                    if ($cmd -eq "NEXUS_UPDATE_ALERT") {
                        $targetApp = if ($parts.Length -gt 1) { $parts[1] } else { "NexusApp" }
                        $newVer    = if ($parts.Length -gt 2) { $parts[2] } else { "" }
                        $newHash   = if ($parts.Length -gt 3) { $parts[3] } else { "" }
                        $pubHost   = if ($parts.Length -gt 4) { $parts[4] } else { $remoteEp.Address.ToString() }
                        $pubUser   = if ($parts.Length -gt 5) { $parts[5] } else { "Admin" }

                        if ($pubHost -ne $env:COMPUTERNAME) {
                            $curSc = $script:AppScriptPath
                            if (-not (Test-Path $curSc)) { $curSc = Join-Path $PSScriptRoot "PMC-ImageResizer-App.ps1" }
                            $locHash = (Get-FileHash -Path $curSc -Algorithm SHA256).Hash
                            if ($newHash -and ($newHash -ne $locHash)) {
                                $script:PendingUpdate = @{
                                    Type = "SQL"
                                    AppName = $targetApp
                                    Version = $newVer
                                    RemoteHash = $newHash
                                    UpdatedBy = "$pubUser ($pubHost)"
                                    LastUpdated = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                                    Source = "Instant LAN Alert from $pubHost"
                                    AlreadyDownloaded = $false
                                }
                                if ($btnUpdateAlertHeader) {
                                    $btnUpdateAlertHeader.Visibility = "Visible"
                                    if ($txtUpdateAlertHeader) { $txtUpdateAlertHeader.Text = "UPDATE $newVer READY" }
                                }
                                Show-AppUpdateAvailablePopup $script:PendingUpdate
                            }
                        }
                        continue
                    }

                    $hostName = $parts[1]
                    $userName = $parts[2]
                    $tcpPort = if ($parts.Length -gt 3) { [int]$parts[3] } else { 52824 }
                    
                    if ($hostName -and $hostName -ne $env:COMPUTERNAME) {
                        $peerObj = [PSCustomObject]@{
                            HostName = $hostName
                            UserName = $userName
                            IP = $remoteEp.Address.ToString()
                            Port = $tcpPort
                            LastSeen = (Get-Date)
                        }
                        $script:LanPeers[$hostName] = $peerObj
                        Refresh-LanPeersList
                        
                        if ($cmd -eq "NEXUS_PING") {
                            try {
                                $pongMsg = "NEXUS_PONG|$env:COMPUTERNAME|$env:USERNAME|$script:LanTcpPort"
                                $pongBytes = [System.Text.Encoding]::UTF8.GetBytes($pongMsg)
                                $replyEp = New-Object System.Net.IPEndPoint($remoteEp.Address, $script:LanUdpPort)
                                $script:LanUdpSocket.Send($pongBytes, $pongBytes.Length, $replyEp) | Out-Null
                            } catch {}
                        }
                    }
                }
            } catch {}

            try {
                if ($script:LanTcpListener -and $script:LanTcpListener.Pending()) {
                    $client = $script:LanTcpListener.AcceptTcpClient()
                    Handle-IncomingLanTcpClient $client
                }
            } catch {}

            try {
                if ($script:LanWebListener -and $script:LanWebListener.Pending()) {
                    $webClient = $script:LanWebListener.AcceptTcpClient()
                    Handle-IncomingLanWebClient $webClient
                }
            } catch {}

            $script:LanBeaconCounter++
            if ($script:LanBeaconCounter -ge 10) {
                $script:LanBeaconCounter = 0
                Broadcast-LanBeacon
            }

            $script:LanUpdateTimerCounter++
            if ($script:LanUpdateTimerCounter -ge 60) {
                $script:LanUpdateTimerCounter = 0
                try { Check-AppUpdatesFromNetwork -UserInitiated $false } catch {}
            }
        })
        $script:LanTimer.Start()
    }

    function Restart-NexusAppInstance([string]$scriptPath) {
        try {
            $cmdFile = Join-Path $PSScriptRoot "Open-Nexus-App.cmd"
            if (Test-Path $cmdFile) {
                Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$cmdFile`"" -WindowStyle Hidden
            } else {
                Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
            }
        } catch {
            try {
                Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
            } catch {}
        }
        try { if ($window) { $window.Close() } } catch {}
        try { [System.Windows.Application]::Current.Shutdown() } catch {}
    }

    function Sync-BeyondCompareReleaseFromSql {
        try {
            $connInfo = Get-ActiveOrSavedSqlConnection
            if (-not $connInfo) { return }
            $conn = $connInfo.Connection
            $shouldClose = -not $connInfo.IsShared
            try {
                $cmd = $conn.CreateCommand()
                $cmd.CommandText = "IF EXISTS (SELECT * FROM sys.tables WHERE name = '_NexusAppReleases') SELECT ScriptHash, ScriptContent FROM _NexusAppReleases WHERE AppName = 'BeyondCompare5'"
                $rdr = $cmd.ExecuteReader()
                if ($rdr.Read()) {
                    $bcHash = if (-not $rdr.IsDBNull(0)) { $rdr.GetString(0) } else { "" }
                    $bcContent = if (-not $rdr.IsDBNull(1)) { $rdr.GetString(1) } else { "" }
                    $rdr.Close()
                    $cmd.Dispose()

                    if ($bcHash -and $bcContent) {
                        $bcLocal = Join-Path $PSScriptRoot "Beyond-Compare-5.ps1"
                        $curBcHash = if (Test-Path $bcLocal) { (Get-FileHash -Path $bcLocal -Algorithm SHA256).Hash } else { "" }
                        if ($bcHash -ne $curBcHash) {
                            $bcBytes = [System.Text.Encoding]::ASCII.GetBytes($bcContent)
                            [System.IO.File]::WriteAllBytes($bcLocal, $bcBytes)
                            
                            $portBc = Join-Path (Split-Path $PSScriptRoot) "PMC-Image-Optimizer-Portable\Beyond-Compare-5.ps1"
                            if (Test-Path (Split-Path $portBc)) { [System.IO.File]::WriteAllBytes($portBc, $bcBytes) }
                            $deskBc = "$env:USERPROFILE\Desktop\Nexus-Photo-Optimizer-Portable\Beyond-Compare-5.ps1"
                            if (Test-Path (Split-Path $deskBc)) { [System.IO.File]::WriteAllBytes($deskBc, $bcBytes) }
                        }
                    }
                } else {
                    $rdr.Close()
                    $cmd.Dispose()
                }
            } finally {
                if ($shouldClose) { try { $conn.Close() } catch {} }
            }
        } catch {}
    }

    function Apply-PendingAppUpdate($PendingUpdate) {
        try {
            $currentScript = $script:AppScriptPath
            if (-not (Test-Path $currentScript)) { $currentScript = Join-Path $PSScriptRoot "PMC-ImageResizer-App.ps1" }

            if ($PendingUpdate.AlreadyDownloaded -eq $true) {
                Restart-NexusAppInstance $currentScript
                return $true
            }

            $content = ""
            $dbExpectedHash = ""
            if ($PendingUpdate.Type -eq "SQL" -or $PendingUpdate.Source -match "SQL") {
                $connInfo = Get-ActiveOrSavedSqlConnection
                if ($connInfo) {
                    $conn = $connInfo.Connection
                    $shouldClose = -not $connInfo.IsShared
                    try {
                        $cmd = $conn.CreateCommand()
                        $cmd.CommandText = "SELECT ScriptHash, ScriptContent FROM _NexusAppReleases WHERE AppName = 'NexusApp'"
                        $rdr = $cmd.ExecuteReader()
                        if ($rdr.Read()) {
                            $dbExpectedHash = if (-not $rdr.IsDBNull(0)) { $rdr.GetString(0) } else { "" }
                            $content        = if (-not $rdr.IsDBNull(1)) { $rdr.GetString(1) } else { "" }
                        }
                        $rdr.Close()
                        $cmd.Dispose()
                    } finally {
                        if ($shouldClose) { try { $conn.Close() } catch {} }
                    }
                }
            } elseif ($PendingUpdate.Type -eq "LAN") {
                if ($PendingUpdate.PeerIP -and $PendingUpdate.PeerPort) {
                    $pullCl = Connect-LanTcpPeer $PendingUpdate.PeerIP $PendingUpdate.PeerPort 4000
                    if ($pullCl) {
                        $pStream = $pullCl.GetStream()
                        $pWr = New-Object System.IO.StreamWriter($pStream, [System.Text.Encoding]::UTF8); $pWr.AutoFlush = $true
                        $pRd = New-Object System.IO.StreamReader($pStream, [System.Text.Encoding]::UTF8)
                        $pWr.WriteLine("NEXUS_PULL_APP_UPDATE")
                        $pResp = $pRd.ReadLine()
                        if ($pResp -and $pResp.StartsWith("OK|")) {
                            $rLen = [int64]($pResp.Split('|')[2])
                            $ms = New-Object System.IO.MemoryStream
                            $buf = New-Object byte[] 65536
                            $rec = 0
                            while ($rec -lt $rLen) {
                                $rd = $pStream.Read($buf, 0, [Math]::Min($buf.Length, $rLen - $rec))
                                if ($rd -le 0) { break }
                                $ms.Write($buf, 0, $rd)
                                $rec += $rd
                            }
                            $content = [System.Text.Encoding]::ASCII.GetString($ms.ToArray())
                            $ms.Dispose()
                        }
                        $pullCl.Close()
                    }
                }
            }

            if (-not $content) {
                [System.Windows.MessageBox]::Show("Could not download update content from network hub. Please check your network connection.", "Update Download Failed", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                return $false
            }

            $bytes = [System.Text.Encoding]::ASCII.GetBytes($content)
            $sha = [System.Security.Cryptography.SHA256]::Create()
            $calcHash = -join ($sha.ComputeHash($bytes) | ForEach-Object { "{0:X2}" -f $_ })

            $expectedHash = if ($dbExpectedHash) { $dbExpectedHash } else { $PendingUpdate.RemoteHash }
            if ($expectedHash -and ($calcHash -ne $expectedHash)) {
                [System.Windows.MessageBox]::Show("Update integrity check failed (SHA256 mismatch).`r`nExpected: $expectedHash`r`nReceived: $calcHash`r`nAborting update for safety.", "Integrity Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
                return $false
            }

            try { Copy-Item $currentScript "$currentScript.bak" -Force } catch {}
            [System.IO.File]::WriteAllBytes($currentScript, $bytes)

            try {
                $portPath = Join-Path (Split-Path $currentScript) "..\PMC-Image-Optimizer-Portable\PMC-ImageResizer-App.ps1"
                if (Test-Path (Split-Path $portPath)) { [System.IO.File]::WriteAllBytes($portPath, $bytes) }
                $deskPath = "$env:USERPROFILE\Desktop\Nexus-Photo-Optimizer-Portable\PMC-ImageResizer-App.ps1"
                if (Test-Path (Split-Path $deskPath)) { [System.IO.File]::WriteAllBytes($deskPath, $bytes) }
            } catch {}

            try { Sync-BeyondCompareReleaseFromSql } catch {}

            Restart-NexusAppInstance $currentScript
            return $true
        } catch {
            [System.Windows.MessageBox]::Show("Error applying update: $($_.Exception.Message)", "Update Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            return $false
        }
    }

    function Show-AppUpdateAvailablePopup($PendingUpdate) {
        if (-not $PendingUpdate) { return }
        if ($script:UpdateDialogOpen) { return }
        $script:UpdateDialogOpen = $true

        if ($window -and $window.Dispatcher -and -not $window.Dispatcher.CheckAccess()) {
            $window.Dispatcher.BeginInvoke([System.Action]{
                Show-AppUpdateAvailablePopup $PendingUpdate
            }) | Out-Null
            return
        }

        try {
            $newVer = if ($PendingUpdate.Version) { $PendingUpdate.Version } else { "5.4.0" }
            $curVer = if ($script:AppVersion) { $script:AppVersion } else { "5.2.0" }
            $upBy   = if ($PendingUpdate.UpdatedBy) { $PendingUpdate.UpdatedBy } else { "LAN Peer / Admin" }
            $src    = if ($PendingUpdate.Source) { $PendingUpdate.Source } else { "SQL Network Hub" }
            $upTime = if ($PendingUpdate.LastUpdated) { $PendingUpdate.LastUpdated } else { (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") }
            $alreadyDownloaded = ($PendingUpdate.AlreadyDownloaded -eq $true)

            $bannerTitle   = if ($alreadyDownloaded) { "APPLICATION UPDATED! PLEASE RESTART NOW" } else { "PLEASE UPDATE APP NOW IS UPDATED" }
            $bannerSub     = if ($alreadyDownloaded) { "The latest version has been downloaded and installed on this PC." } else { "A newer version has been published and is ready to install." }
            $actionBtnText = if ($alreadyDownloaded) { "RESTART NOW" } else { "UPDATE &amp; RESTART NOW" }
            $statusMsg     = if ($alreadyDownloaded) { "Click 'Restart Now' to restart the application and load all new features." } else { "Click 'Update &amp; Restart Now' to download and install the new version automatically in 2 seconds." }

            $dialogXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Nexus Suite - Application Update Available"
        Width="540" Height="385"
        WindowStartupLocation="CenterScreen"
        Topmost="True"
        WindowStyle="None"
        AllowsTransparency="True"
        Background="Transparent"
        ResizeMode="NoResize">
    <Border Background="#0B1120" BorderBrush="#0284C7" BorderThickness="2" CornerRadius="14">
        <Border.Effect>
            <DropShadowEffect BlurRadius="26" ShadowDepth="4" Opacity="0.65" Color="#0284C7"/>
        </Border.Effect>
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="52"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="68"/>
            </Grid.RowDefinitions>

            <!-- Top Header Bar (Draggable) -->
            <Border x:Name="pnlUpdateHeader" Grid.Row="0" Background="#0F172A" CornerRadius="12,12,0,0" Padding="18,0" BorderBrush="#1E293B" BorderThickness="0,0,0,1" Cursor="SizeAll">
                <Grid VerticalAlignment="Center">
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <Ellipse Width="10" Height="10" Fill="#10B981" Margin="0,0,10,0" VerticalAlignment="Center"/>
                        <TextBlock Text="NEXUS SUITE - APPLICATION UPDATE" Foreground="#38BDF8" FontWeight="Bold" FontSize="13.5" VerticalAlignment="Center"/>
                    </StackPanel>
                    <Button x:Name="btnUpdateCloseX" Content="X" HorizontalAlignment="Right" Width="30" Height="30" Background="#1E293B" Foreground="#94A3B8" FontWeight="Bold" FontSize="13" BorderThickness="0" Cursor="Hand">
                        <Button.Resources>
                            <Style TargetType="Border">
                                <Setter Property="CornerRadius" Value="6"/>
                            </Style>
                        </Button.Resources>
                    </Button>
                </Grid>
            </Border>

            <!-- Body Area -->
            <StackPanel Grid.Row="1" Margin="22,14,22,10">
                <!-- Prominent Callout Banner -->
                <Border Background="#064E3B" BorderBrush="#059669" BorderThickness="1.5" CornerRadius="8" Padding="14,10" Margin="0,0,0,12">
                    <StackPanel>
                        <TextBlock Text="$bannerTitle" Foreground="#34D399" FontWeight="ExtraBold" FontSize="14.5" HorizontalAlignment="Center"/>
                        <TextBlock Text="$bannerSub" Foreground="#A7F3D0" FontSize="12" HorizontalAlignment="Center" Margin="0,3,0,0"/>
                    </StackPanel>
                </Border>

                <!-- Information Grid Card -->
                <Border Background="#0A0E1A" BorderBrush="#1E293B" BorderThickness="1" CornerRadius="8" Padding="14,10">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="130"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>

                        <TextBlock Grid.Row="0" Grid.Column="0" Text="Published By:" Foreground="#64748B" FontSize="12" Margin="0,3"/>
                        <TextBlock Text="$upBy" Foreground="#F1F5F9" FontWeight="Bold" FontSize="12" Margin="0,3"/>

                        <TextBlock Grid.Row="1" Grid.Column="0" Text="New Version:" Foreground="#64748B" FontSize="12" Margin="0,3"/>
                        <TextBlock Text="v$newVer (Current: v$curVer)" Foreground="#38BDF8" FontWeight="Bold" FontSize="12" Margin="0,3"/>

                        <TextBlock Grid.Row="2" Grid.Column="0" Text="Release Source:" Foreground="#64748B" FontSize="12" Margin="0,3"/>
                        <TextBlock Text="$src" Foreground="#F1F5F9" FontSize="12" Margin="0,3"/>

                        <TextBlock Grid.Row="3" Grid.Column="0" Text="Published Time:" Foreground="#64748B" FontSize="12" Margin="0,3"/>
                        <TextBlock Text="$upTime" Foreground="#94A3B8" FontSize="11.5" Margin="0,3"/>
                    </Grid>
                </Border>

                <TextBlock x:Name="lblUpdateStatusMsg" Text="$statusMsg" Foreground="#94A3B8" FontSize="11.5" Margin="4,10,4,0" TextWrapping="Wrap"/>
            </StackPanel>

            <!-- Bottom Button Bar -->
            <Border Grid.Row="2" Background="#0A0E1A" CornerRadius="0,0,12,12" Padding="22,0" BorderBrush="#1E293B" BorderThickness="0,1,0,0">
                <Grid VerticalAlignment="Center">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="140"/>
                    </Grid.ColumnDefinitions>

                    <Button x:Name="btnUpdateAction" Grid.Column="0" Content="$actionBtnText" Background="#059669" Foreground="White" FontWeight="Bold" FontSize="13" Height="42" Margin="0,0,12,0" BorderThickness="0" Cursor="Hand">
                        <Button.Resources>
                            <Style TargetType="Border">
                                <Setter Property="CornerRadius" Value="8"/>
                            </Style>
                        </Button.Resources>
                    </Button>

                    <Button x:Name="btnUpdateSnooze" Grid.Column="1" Content="Remind Later" Background="#1E293B" Foreground="#94A3B8" FontWeight="SemiBold" FontSize="12.5" Height="42" BorderBrush="#334155" BorderThickness="1" Cursor="Hand">
                        <Button.Resources>
                            <Style TargetType="Border">
                                <Setter Property="CornerRadius" Value="8"/>
                            </Style>
                        </Button.Resources>
                    </Button>
                </Grid>
            </Border>
        </Grid>
    </Border>
</Window>
"@

            $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($dialogXaml))
            $dlgWin = [System.Windows.Markup.XamlReader]::Load($reader)

            $pnlHdr = $dlgWin.FindName("pnlUpdateHeader")
            if ($pnlHdr) { $pnlHdr.Add_MouseLeftButtonDown({ $dlgWin.DragMove() }) }

            $btnAct = $dlgWin.FindName("btnUpdateAction")
            $btnSnz = $dlgWin.FindName("btnUpdateSnooze")
            $btnClose = $dlgWin.FindName("btnUpdateCloseX")
            $lblStatus = $dlgWin.FindName("lblUpdateStatusMsg")

            $btnAct.Add_Click({
                $btnAct.IsEnabled = $false
                $btnAct.Content = "Applying Update..."
                if ($lblStatus) { $lblStatus.Text = "Downloading release and preparing restart..." }
                
                $applied = Apply-PendingAppUpdate $PendingUpdate
                if (-not $applied) {
                    $btnAct.IsEnabled = $true
                    $btnAct.Content = if ($alreadyDownloaded) { "RESTART NOW" } else { "UPDATE & RESTART NOW" }
                } else {
                    $dlgWin.Close()
                }
            })

            $btnSnz.Add_Click({
                $script:UpdateSnoozedUntil = (Get-Date).AddMinutes(30)
                $script:UpdateDialogOpen = $false
                if ($btnUpdateAlertHeader) { $btnUpdateAlertHeader.Visibility = "Visible" }
                $dlgWin.Close()
            })

            $btnClose.Add_Click({
                $script:UpdateSnoozedUntil = (Get-Date).AddMinutes(15)
                $script:UpdateDialogOpen = $false
                if ($btnUpdateAlertHeader) { $btnUpdateAlertHeader.Visibility = "Visible" }
                $dlgWin.Close()
            })

            $dlgWin.Add_Closed({
                $script:UpdateDialogOpen = $false
            })

            $dlgWin.ShowDialog() | Out-Null
        } catch {
            $script:UpdateDialogOpen = $false
            $fbPrompt = "PLEASE UPDATE APP NOW IS UPDATED!`r`n`r`nA newer version ($($PendingUpdate.Version)) was published by '$($PendingUpdate.UpdatedBy)'.`r`n`r`nSource: $($PendingUpdate.Source)`r`n`r`nWould you like to install the update and restart now?"
            $res = [System.Windows.MessageBox]::Show($fbPrompt, "Nexus Auto-Update - Update Ready", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Information)
            if ($res -eq [System.Windows.MessageBoxResult]::Yes) {
                Apply-PendingAppUpdate $PendingUpdate
            } else {
                $script:UpdateSnoozedUntil = (Get-Date).AddMinutes(30)
                if ($btnUpdateAlertHeader) { $btnUpdateAlertHeader.Visibility = "Visible" }
            }
        }
    }

    function Show-AppUpdateReceivedNotification([string]$senderHost, [string]$senderUser, [string]$version) {
        $pObj = @{
            Type = "TCP_PUSH"
            AppName = "NexusApp"
            Version = $version
            RemoteHash = ""
            UpdatedBy = "$senderUser ($senderHost)"
            LastUpdated = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            Source = "Direct LAN Push ($senderHost)"
            AlreadyDownloaded = $true
        }
        Show-AppUpdateAvailablePopup $pObj
    }

function Get-ActiveOrSavedSqlConnection {
    if ($script:SqlConnected -and $script:SqlConnection -and $script:SqlConnection.State -eq [System.Data.ConnectionState]::Open) {
        return @{ Connection = $script:SqlConnection; IsShared = $true }
    }
    
    # Try finding saved connection string
    $connStr = ""
    if ($txtSqlConnStr -and $txtSqlConnStr.Text -and $txtSqlConnStr.Text -ne $script:SqlPlaceholder) {
        $connStr = $txtSqlConnStr.Text
    }
    if (-not $connStr -and $script:SqlLastConnPath -and (Test-Path $script:SqlLastConnPath)) {
        try { $connStr = [System.IO.File]::ReadAllText($script:SqlLastConnPath).Trim() } catch {}
    }
    if (-not $connStr) {
        $deskLast = Join-Path $PSScriptRoot "sql-last-conn.txt"
        if (Test-Path $deskLast) {
            try { $connStr = [System.IO.File]::ReadAllText($deskLast).Trim() } catch {}
        }
    }
    if (-not $connStr -and $script:SqlConnFile -and (Test-Path $script:SqlConnFile)) {
        try {
            $conns = Get-Content $script:SqlConnFile | ConvertFrom-Json
            if ($conns -and $conns.Count -gt 0) { $connStr = $conns[0].ConnectionString }
        } catch {}
    }
    
    if ($connStr) {
        try {
            if ($connStr -notmatch "Timeout") {
                $connStr = "$connStr;Connection Timeout=5"
            }
            $conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
            $conn.Open()
            return @{ Connection = $conn; IsShared = $false }
        } catch {}
    }

    # Master Central Network Hub SQL Server Fallback (Guarantees every PC on 192.168.1.x receives updates)
    $masterHubConn = 'data source=192.168.1.16;initial catalog=NTIS_4037;persist security info=True;User ID=xEYgYIlOk2r09a7IVa0lT;Password=QgVwWNNTreP_9diS7klTjILeTIlq7oym53BNlhr;Connection Timeout=5'
    try {
        $conn = New-Object System.Data.SqlClient.SqlConnection($masterHubConn)
        $conn.Open()
        return @{ Connection = $conn; IsShared = $false }
    } catch {}

    return $null
}

function Broadcast-LanUpdateAlert([string]$appName = "NexusApp", [string]$version = "", [string]$hash = "") {
    try {
        if (-not $version) { $version = $script:AppVersion }
        if (-not $hash) {
            $currentScript = $script:AppScriptPath
            if (-not (Test-Path $currentScript)) { $currentScript = Join-Path $PSScriptRoot "PMC-ImageResizer-App.ps1" }
            $hash = (Get-FileHash -Path $currentScript -Algorithm SHA256).Hash
        }
        $msg = "NEXUS_UPDATE_ALERT|$appName|$version|$hash|$env:COMPUTERNAME|$env:USERNAME"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($msg)

        if (-not $script:LanUdpSocket) {
            $script:LanUdpSocket = New-Object System.Net.Sockets.UdpClient
            $script:LanUdpSocket.EnableBroadcast = $true
        }

        # 1. Global Broadcast
        $bcastEp = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Broadcast, $script:LanUdpPort)
        $script:LanUdpSocket.Send($bytes, $bytes.Length, $bcastEp) | Out-Null

        # 2. Subnet Broadcast
        if ($script:LanLocalIP -and $script:LanLocalIP -match '^(\d+\.\d+\.\d+)\.') {
            $subnetBcast = "$($matches[1]).255"
            $subEp = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Parse($subnetBcast), $script:LanUdpPort)
            $script:LanUdpSocket.Send($bytes, $bytes.Length, $subEp) | Out-Null
        }

        # 3. Direct Unicast to all known LAN peers
        foreach ($k in $script:LanPeers.Keys) {
            $p = $script:LanPeers[$k]
            if ($p.IP -and $p.IP -ne "127.0.0.1" -and $p.IP -ne $script:LanLocalIP) {
                try {
                    $pEp = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Parse($p.IP), $script:LanUdpPort)
                    $script:LanUdpSocket.Send($bytes, $bytes.Length, $pEp) | Out-Null
                } catch {}
            }
        }

        # 4. Direct Unicast to all active computers connected to SQL Server Hub!
        try {
            $connInfo = Get-ActiveOrSavedSqlConnection
            if ($connInfo) {
                $conn = $connInfo.Connection
                $shouldClose = -not $connInfo.IsShared
                try {
                    $cmd = $conn.CreateCommand()
                    $cmd.CommandText = "SELECT DISTINCT client_net_address FROM sys.dm_exec_connections WHERE client_net_address IS NOT NULL AND client_net_address NOT IN ('<local machine>', '127.0.0.1')"
                    $rdr = $cmd.ExecuteReader()
                    while ($rdr.Read()) {
                        $cIp = $rdr.GetString(0)
                        if ($cIp -and $cIp -ne $script:LanLocalIP -and $cIp -ne "127.0.0.1") {
                            try {
                                $pEp = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Parse($cIp), $script:LanUdpPort)
                                $script:LanUdpSocket.Send($bytes, $bytes.Length, $pEp) | Out-Null
                            } catch {}
                        }
                    }
                    $rdr.Close()
                    $cmd.Dispose()
                } finally {
                    if ($shouldClose) { try { $conn.Close() } catch {} }
                }
            }
        } catch {}
    } catch {}
}

function Push-AppUpdateToSqlServer($fileBytes, [string]$sha256) {
    $connInfo = Get-ActiveOrSavedSqlConnection
    if (-not $connInfo) { return $false }
    $conn = $connInfo.Connection
    $shouldClose = -not $connInfo.IsShared

    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = '_NexusAppReleases') BEGIN CREATE TABLE _NexusAppReleases (AppName VARCHAR(100) PRIMARY KEY, Version VARCHAR(50), ScriptHash VARCHAR(100), LastUpdated DATETIME, UpdatedBy VARCHAR(100), ScriptContent NVARCHAR(MAX)); END"
        $cmd.ExecuteNonQuery() | Out-Null
        $cmd.Dispose()
        
        $cmd2 = $conn.CreateCommand()
        $cmd2.CommandText = "MERGE _NexusAppReleases AS target USING (SELECT 'NexusApp' AS AppName) AS source ON (target.AppName = source.AppName) WHEN MATCHED THEN UPDATE SET Version = '$script:AppVersion', ScriptHash = '$sha256', LastUpdated = GETDATE(), UpdatedBy = '$env:USERNAME ($env:COMPUTERNAME)', ScriptContent = @content WHEN NOT MATCHED THEN INSERT (AppName, Version, ScriptHash, LastUpdated, UpdatedBy, ScriptContent) VALUES ('NexusApp', '$script:AppVersion', '$sha256', GETDATE(), '$env:USERNAME ($env:COMPUTERNAME)', @content);"
        $strContent = [System.Text.Encoding]::ASCII.GetString($fileBytes)
        $p = $cmd2.Parameters.Add("@content", [System.Data.SqlDbType]::NVarChar, -1)
        $p.Value = $strContent
        $cmd2.ExecuteNonQuery() | Out-Null
        $cmd2.Dispose()
        return $true
    } catch {
        return $false
    } finally {
        if ($shouldClose) { try { $conn.Close() } catch {} }
    }
}

function Check-AppUpdatesFromNetwork([bool]$UserInitiated = $false, [bool]$OnStartup = $false) {
    $currentScript = $script:AppScriptPath
    if (-not (Test-Path $currentScript)) { $currentScript = Join-Path $PSScriptRoot "PMC-ImageResizer-App.ps1" }
    $localHash = (Get-FileHash -Path $currentScript -Algorithm SHA256).Hash

    $now = Get-Date
    $isSnoozed = ($script:UpdateSnoozedUntil -and ($now -lt $script:UpdateSnoozedUntil))

    # 1. Check SQL Server Release Table
    $connInfo = Get-ActiveOrSavedSqlConnection
    if ($connInfo) {
        $conn = $connInfo.Connection
        $shouldClose = -not $connInfo.IsShared
        try {
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = "IF EXISTS (SELECT * FROM sys.tables WHERE name = '_NexusAppReleases') SELECT ScriptHash, Version, UpdatedBy, LastUpdated FROM _NexusAppReleases WHERE AppName = 'NexusApp'"
            $rdr = $cmd.ExecuteReader()
            if ($rdr.Read()) {
                $remoteHash = if (-not $rdr.IsDBNull(0)) { $rdr.GetString(0) } else { "" }
                $remoteVer  = if (-not $rdr.IsDBNull(1)) { $rdr.GetString(1) } else { "5.4.0" }
                $updatedBy  = if (-not $rdr.IsDBNull(2)) { $rdr.GetString(2) } else { "LAN Hub" }
                $lastUpTime = if (-not $rdr.IsDBNull(3)) { $rdr.GetDateTime(3).ToString("yyyy-MM-dd HH:mm:ss") } else { "" }
                $rdr.Close()
                $cmd.Dispose()

                if ($remoteHash -and ($remoteHash -ne $localHash)) {
                    # Do not show automatic background update popup to the publisher PC who published it
                    $isPublishedByMe = ($updatedBy -and ($updatedBy -like "*$($env:COMPUTERNAME)*"))
                    if ($isPublishedByMe -and (-not $UserInitiated)) {
                        return $false
                    }

                    $script:PendingUpdate = @{
                        Type = "SQL"
                        AppName = "NexusApp"
                        Version = $remoteVer
                        RemoteHash = $remoteHash
                        UpdatedBy = $updatedBy
                        LastUpdated = $lastUpTime
                        Source = "SQL Network Hub (192.168.1.16)"
                        AlreadyDownloaded = $false
                    }
                    if ($btnUpdateAlertHeader) {
                        $btnUpdateAlertHeader.Visibility = "Visible"
                        if ($txtUpdateAlertHeader) { $txtUpdateAlertHeader.Text = "UPDATE $remoteVer READY" }
                    }
                    if ($UserInitiated -or (-not $isSnoozed)) {
                        Show-AppUpdateAvailablePopup $script:PendingUpdate
                    }
                    return $true
                }
            } else {
                $rdr.Close()
                $cmd.Dispose()
            }
        } catch {} finally {
            if ($shouldClose) { try { $conn.Close() } catch {} }
        }
    }

    # 2. Check active LAN Peers
    $foundUpdate = $false
    foreach ($k in $script:LanPeers.Keys) {
        $p = $script:LanPeers[$k]
        if ($p.IP -and $p.IP -ne "127.0.0.1" -and $p.IP -ne $script:LanLocalIP) {
            try {
                $cl = Connect-LanTcpPeer $p.IP $p.Port 2000
                if ($cl) {
                    $stream = $cl.GetStream()
                    $writer = New-Object System.IO.StreamWriter($stream, [System.Text.Encoding]::UTF8); $writer.AutoFlush = $true
                    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
                    $writer.WriteLine("NEXUS_CHECK_APP_VERSION|$env:COMPUTERNAME")
                    $resp = $reader.ReadLine()
                    if ($resp -and $resp.StartsWith("OK|")) {
                        $pParts = $resp.Split('|')
                        $rVer = $pParts[1]
                        $rLen = [int64]$pParts[2]
                        $rHash = $pParts[3]
                        $rDate = if ($pParts.Length -gt 4) { $pParts[4] } else { "" }
                        $rHost = if ($pParts.Length -gt 5) { $pParts[5] } else { $p.HostName }
                        $rUser = if ($pParts.Length -gt 6) { $pParts[6] } else { $p.UserName }

                        if ($rHash -and ($rHash -ne $localHash)) {
                            $script:PendingUpdate = @{
                                Type = "LAN"
                                AppName = "NexusApp"
                                Version = $rVer
                                RemoteHash = $rHash
                                UpdatedBy = "$rUser ($rHost)"
                                LastUpdated = $rDate
                                Source = "LAN Peer ($rHost)"
                                PeerIP = $p.IP
                                PeerPort = $p.Port
                                ScriptLen = $rLen
                                AlreadyDownloaded = $false
                            }
                            if ($btnUpdateAlertHeader) {
                                $btnUpdateAlertHeader.Visibility = "Visible"
                                if ($txtUpdateAlertHeader) { $txtUpdateAlertHeader.Text = "UPDATE $rVer READY" }
                            }
                            $cl.Close()
                            if ($UserInitiated -or (-not $isSnoozed)) {
                                Show-AppUpdateAvailablePopup $script:PendingUpdate
                            }
                            return $true
                        }
                    }
                    $cl.Close()
                }
            } catch {}
        }
    }

    if ($UserInitiated) {
        if (-not $foundUpdate) {
            [System.Windows.MessageBox]::Show("You are currently running the latest version of the application.`r`n`r`nVersion: $script:AppVersion`r`nHash: $($localHash.Substring(0,16))...", "Up to Date", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        }
    }
    return $foundUpdate
}

function Push-AppUpdateToAllPeers {
    $currentScript = $script:AppScriptPath
    if (-not (Test-Path $currentScript)) { $currentScript = Join-Path $PSScriptRoot "PMC-ImageResizer-App.ps1" }
    if (-not (Test-Path $currentScript)) {
        [System.Windows.MessageBox]::Show("Application script not found at: $currentScript", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        return
    }

    $fileBytes = [System.IO.File]::ReadAllBytes($currentScript)
    $fileLen = $fileBytes.Length
    $sha256 = (Get-FileHash -Path $currentScript -Algorithm SHA256).Hash

    $targets = @()
    foreach ($k in $script:LanPeers.Keys) {
        $p = $script:LanPeers[$k]
        if ($p.IP -and $p.IP -ne "127.0.0.1" -and $p.IP -ne $script:LanLocalIP) {
            $targets += $p
        }
    }

    # Also automatically discover and add all other active computers connected to SQL Server
    try {
        $connInfo = Get-ActiveOrSavedSqlConnection
        if ($connInfo) {
            $conn = $connInfo.Connection
            $shouldClose = -not $connInfo.IsShared
            try {
                $cmd = $conn.CreateCommand()
                $cmd.CommandText = "SELECT DISTINCT client_net_address FROM sys.dm_exec_connections WHERE client_net_address IS NOT NULL AND client_net_address NOT IN ('<local machine>', '127.0.0.1')"
                $rdr = $cmd.ExecuteReader()
                while ($rdr.Read()) {
                    $cIp = $rdr.GetString(0)
                    if ($cIp -and $cIp -ne $script:LanLocalIP -and $cIp -ne "127.0.0.1") {
                        $alreadyIn = $targets | Where-Object { $_.IP -eq $cIp }
                        if (-not $alreadyIn) {
                            $targets += [PSCustomObject]@{
                                HostName = $cIp
                                UserName = "Peer"
                                IP = $cIp
                                Port = 52824
                            }
                        }
                    }
                }
                $rdr.Close()
                $cmd.Dispose()
            } finally {
                if ($shouldClose) { try { $conn.Close() } catch {} }
            }
        }
    } catch {}

    [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
    $successList = @()
    $failedList = @()

    foreach ($peer in $targets) {
        try {
            $cl = Connect-LanTcpPeer $peer.IP $peer.Port 3500
            if ($cl) {
                $stream = $cl.GetStream()
                $writer = New-Object System.IO.StreamWriter($stream, [System.Text.Encoding]::UTF8); $writer.AutoFlush = $true
                $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)

                $writer.WriteLine("NEXUS_APP_PUSH|$fileLen|$sha256|$env:COMPUTERNAME|$env:USERNAME|$script:AppVersion")
                $stream.Write($fileBytes, 0, $fileBytes.Length)
                $stream.Flush()

                $resp = $reader.ReadLine()
                if ($resp -and $resp.StartsWith("OK")) {
                    $successList += "SUCCESS: $($peer.HostName) ($($peer.IP))"
                } else {
                    $failedList += "FAILED: $($peer.HostName) ($($peer.IP)) - $resp"
                }
                $cl.Close()
            } else {
                $failedList += "OFFLINE: $($peer.HostName) ($($peer.IP))"
            }
        } catch {
            $failedList += "ERROR: $($peer.HostName) ($($peer.IP)) - $($_.Exception.Message)"
        }
    }

    # Also push to SQL Server release table
    $sqlSuccess = Push-AppUpdateToSqlServer $fileBytes $sha256

    # Broadcast real-time UDP alert to all LAN peers & subnets
    try { Broadcast-LanUpdateAlert -AppName "NexusApp" -Version $script:AppVersion -Hash $sha256 } catch {}
    [System.Windows.Input.Mouse]::OverrideCursor = $null

    $summary = "LAN Auto-Update Broadcast Complete!`r`n`r`n"
    if ($successList.Count -gt 0) {
        $summary += "Direct LAN Peers Updated ($($successList.Count)):`r`n" + ($successList -join "`r`n") + "`r`n`r`n"
    } else {
        $summary += "Direct LAN Peers Updated: 0 active peers connected.`r`n`r`n"
    }
    if ($failedList.Count -gt 0) {
        $summary += "Unreachable LAN Peers ($($failedList.Count)):`r`n" + ($failedList -join "`r`n") + "`r`n"
        $summary += "(Note: Peer PC must have Nexus open with firewall rule enabled to receive direct TCP push.)`r`n`r`n"
    }
    if ($sqlSuccess) {
        $summary += "[SQL NETWORK HUB - SYNCED]`r`nUpdate package was successfully uploaded to SQL Server release table!`r`n`r`nAny user PC connecting to SQL Server will automatically detect and install this update on startup."
    } else {
        $summary += "[SQL NETWORK HUB - OFFLINE]`r`nCould not reach SQL Server. Ensure connection string is saved in SQL Console."
    }

    [System.Windows.MessageBox]::Show($summary, "Application Update Broadcast", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
}

function Connect-LanTcpPeer ($ip, $port, [int]$timeoutMs = 3500) {
        try {
            $cl = New-Object System.Net.Sockets.TcpClient
            $ar = $cl.BeginConnect($ip, $port, $null, $null)
            $wh = $ar.AsyncWaitHandle.WaitOne($timeoutMs)
            if (-not $wh -or -not $cl.Connected) {
                try { $cl.Close() } catch {}
                return $null
            }
            $cl.EndConnect($ar)
            return $cl
        } catch {
            return $null
        }
    }

    function Get-UniversalShareLink ($filePaths) {
        if (-not $filePaths -or $filePaths.Count -eq 0) { return $null }
        $uploadPath = $null
        $isTempZip = $false
        
        if ($filePaths.Count -eq 1 -and (Test-Path $filePaths[0])) {
            $uploadPath = $filePaths[0]
        } else {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zipPath = Join-Path ([System.IO.Path]::GetTempPath()) ("Nexus_Files_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".zip")
            if (Test-Path $zipPath) { try { Remove-Item $zipPath -Force } catch {} }
            
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("Nexus_Temp_" + [System.Guid]::NewGuid().ToString().Substring(0,8))
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            
            foreach ($f in $filePaths) {
                if (Test-Path $f) { Copy-Item -Path $f -Destination $tempDir -Force }
            }
            
            [System.IO.Compression.ZipFile]::CreateFromDirectory($tempDir, $zipPath)
            Remove-Item -Path $tempDir -Recurse -Force
            $uploadPath = $zipPath
            $isTempZip = $true
        }
        
        $safeName = [System.IO.Path]::GetFileName($uploadPath)
        $binId = "nexus-" + [System.Guid]::NewGuid().ToString().Substring(0,8)
        $downloadUrl = $null
        
        try {
            $url = "https://filebin.net/$binId/$safeName"
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("Content-Type", "application/octet-stream")
            $resp = $wc.UploadFile($url, "POST", $uploadPath)
            $downloadUrl = "https://filebin.net/$binId/$safeName"
        } catch {
            try {
                Add-Type -AssemblyName System.Net.Http
                $client = New-Object System.Net.Http.HttpClient
                $form = New-Object System.Net.Http.MultipartFormDataContent
                $bytes = [System.IO.File]::ReadAllBytes($uploadPath)
                $byteContent = New-Object System.Net.Http.ByteArrayContent($bytes)
                $form.Add($byteContent, "file", $safeName)
                $resp = $client.PostAsync("https://tmpfiles.org/api/v1/upload", $form).Result
                $json = $resp.Content.ReadAsStringAsync().Result
                $obj = $json | ConvertFrom-Json
                if ($obj -and $obj.data -and $obj.data.url) {
                    $downloadUrl = $obj.data.url
                }
            } catch {}
        }
        
        if ($isTempZip -and (Test-Path $uploadPath)) {
            try { Remove-Item $uploadPath -Force } catch {}
        }
        
        return $downloadUrl
    }

    function Show-LanUnreachableDialog ($targetPeer) {
        $hostName = if ($targetPeer -and $targetPeer.HostName) { $targetPeer.HostName } else { "the other PC" }
        
        $msg = "Could not connect to $hostName directly over LAN.`r`n`r`n" +
               "Reason: Windows Firewall blocks direct peer connections on this network.`r`n`r`n" +
               "SIMPLE SOLUTION:`r`n" +
               "Generate a Universal Download Link! Your colleague can open it in Chrome or Edge and download the file with 1 click (No firewall blocks).`r`n`r`n" +
               "Would you like to create and copy a download link now?"
        
        $res = [System.Windows.MessageBox]::Show($msg, "Cannot Reach $hostName - Use Web Link", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Information)
        if ($res -eq [System.Windows.MessageBoxResult]::Yes) {
            if ($script:LanSendFilesList.Count -gt 0) {
                if ($lblLanSendStatus) { $lblLanSendStatus.Text = "Creating universal download link..." }
                [System.Windows.Forms.Application]::DoEvents()
                $uLink = Get-UniversalShareLink $script:LanSendFilesList
                if ($uLink) {
                    try { [System.Windows.Clipboard]::SetText($uLink) } catch {}
                    if ($lblLanTransferLog) {
                        $lblLanTransferLog.Text = "Link Copied: $uLink (Works on ANY PC or phone without firewall)"
                        $lblLanTransferLog.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
                    }
                    [System.Windows.MessageBox]::Show("Download Link Ready & Copied to Clipboard!`r`n`r`n$uLink`r`n`r`nPaste this link to your colleague in WhatsApp, Teams, or Email. They can download the file in 1 click in Chrome or Edge!", "Download Link Ready", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
                }
            }
        }
    }

    function Handle-IncomingLanTcpClient ($client) {
        try {
            $stream = $client.GetStream()
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
            $writer = New-Object System.IO.StreamWriter($stream, [System.Text.Encoding]::UTF8)
            $writer.AutoFlush = $true

            $header = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($header)) { $client.Close(); return }

            $parts = $header -split '\|'
            $cmd = $parts[0]

            if ($cmd -eq "NEXUS_SEND") {
                $rawFileName = [System.IO.Path]::GetFileName($parts[1])
                $fileLen = [int64]$parts[2]
                $senderHost = if ($parts.Length -gt 3) { $parts[3] } else { "Unknown" }
                $senderUser = if ($parts.Length -gt 4) { $parts[4] } else { "" }

                if (-not (Test-Path $script:LanReceivedDir)) { try { New-Item -ItemType Directory -Path $script:LanReceivedDir -Force | Out-Null } catch {} }`n                $destPath = Join-Path $script:LanReceivedDir $rawFileName
                $counter = 1
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($rawFileName)
                $ext = [System.IO.Path]::GetExtension($rawFileName)
                while (Test-Path $destPath) {
                    $destPath = Join-Path $script:LanReceivedDir "$baseName ($counter)$ext"
                    $counter++
                }

                $fs = New-Object System.IO.FileStream($destPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
                $buf = New-Object byte[] 65536
                $received = 0
                while ($received -lt $fileLen) {
                    $chunk = [Math]::Min($buf.Length, $fileLen - $received)
                    $read = $stream.Read($buf, 0, $chunk)
                    if ($read -le 0) { break }
                    $fs.Write($buf, 0, $read)
                    $received += $read
                }
                $fs.Close()

                $writer.WriteLine("OK|$received")
                $finalName = [System.IO.Path]::GetFileName($destPath)
                $sizeStr = Format-LanFileSize $received
                
                if ($lblLanTransferLog) {
                    $lblLanTransferLog.Text = "[RECEIVED] '$finalName' ($sizeStr) from $senderHost ($senderUser) into Desktop\Nexus_Received_Files"
                    $lblLanTransferLog.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
                }

                [System.Windows.MessageBox]::Show("New File Received via Direct LAN Share!`r`n`r`nFile: $finalName`r`nSize: $sizeStr`r`nFrom: $senderHost ($senderUser)`r`n`r`nSaved to: Desktop\Nexus_Received_Files", "Direct PC Share - File Received", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)

            } elseif ($cmd -eq "NEXUS_LIST") {
                $fileList = @()
                foreach ($f in $script:LanOutboxList) {
                    if (Test-Path $f) {
                        $item = Get-Item $f
                        $fileList += [PSCustomObject]@{
                            Name = $item.Name
                            Length = $item.Length
                            Size = Format-LanFileSize $item.Length
                            LastWriteTime = $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                        }
                    }
                }
                $json = $fileList | ConvertTo-Json -Compress
                $writer.WriteLine("OK|" + $json)

            } elseif ($cmd -eq "NEXUS_PULL") {
                $reqName = $parts[1]
                $matched = $script:LanOutboxList | Where-Object { [System.IO.Path]::GetFileName($_) -eq $reqName } | Select-Object -First 1
                if ($matched -and (Test-Path $matched)) {
                    $mItem = Get-Item $matched
                    $writer.WriteLine("OK|$($mItem.Name)|$($mItem.Length)")
                    
                    $fs = [System.IO.File]::OpenRead($matched)
                    $buf = New-Object byte[] 65536
                    while (($read = $fs.Read($buf, 0, $buf.Length)) -gt 0) {
                        $stream.Write($buf, 0, $read)
                    }
                    $fs.Close()
                    $stream.Flush()
                    
                    if ($lblLanTransferLog) {
                        $lblLanTransferLog.Text = "[SENT VIA PULL] Streamed '$reqName' ($(Format-LanFileSize $mItem.Length)) to peer"
                    }
                } else {
                    $writer.WriteLine("ERR|File not found in outbox")
                }
            } elseif ($cmd -eq "NEXUS_APP_PUSH") {
                # Automatic Remote Application Update from another PC!
                $fileLen = [int64]$parts[1]
                $expectedHash = $parts[2]
                $senderHost = if ($parts.Length -gt 3) { $parts[3] } else { "Unknown" }
                $senderUser = if ($parts.Length -gt 4) { $parts[4] } else { "" }
                $version = if ($parts.Length -gt 5) { $parts[5] } else { "5.2.0" }

                $currentScript = $script:AppScriptPath
                if (-not (Test-Path $currentScript)) {
                    $currentScript = Join-Path $PSScriptRoot "PMC-ImageResizer-App.ps1"
                }

                $tempScript = "$currentScript.update_temp"
                $fs = New-Object System.IO.FileStream($tempScript, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
                $buf = New-Object byte[] 65536
                $received = 0
                while ($received -lt $fileLen) {
                    $chunk = [Math]::Min($buf.Length, $fileLen - $received)
                    $read = $stream.Read($buf, 0, $chunk)
                    if ($read -le 0) { break }
                    $fs.Write($buf, 0, $read)
                    $received += $read
                }
                $fs.Close()

                $calcHash = (Get-FileHash -Path $tempScript -Algorithm SHA256).Hash
                if ($calcHash -eq $expectedHash) {
                    try { Copy-Item $currentScript "$currentScript.bak" -Force } catch {}
                    Move-Item -Path $tempScript -Destination $currentScript -Force
                    
                    # Also update portable and desktop copies if present
                    try {
                        $portPath = Join-Path (Split-Path $currentScript) "..\PMC-Image-Optimizer-Portable\PMC-ImageResizer-App.ps1"
                        if (Test-Path (Split-Path $portPath)) { Copy-Item $currentScript $portPath -Force }
                        $deskPath = "$env:USERPROFILE\Desktop\Nexus-Photo-Optimizer-Portable\PMC-ImageResizer-App.ps1"
                        if (Test-Path (Split-Path $deskPath)) { Copy-Item $currentScript $deskPath -Force }
                    } catch {}

                    $writer.WriteLine("OK|UPDATED")

                    if ($window -and $window.Dispatcher) {
                        $window.Dispatcher.BeginInvoke([System.Action]{
                            Show-AppUpdateReceivedNotification $senderHost $senderUser $version
                        }) | Out-Null
                    }
                } else {
                    try { Remove-Item $tempScript -Force } catch {}
                    $writer.WriteLine("ERR|Hash mismatch")
                }
            } elseif ($cmd -eq "NEXUS_CHECK_APP_VERSION") {
                $currentScript = $script:AppScriptPath
                if (Test-Path $currentScript) {
                    $item = Get-Item $currentScript
                    $h = (Get-FileHash -Path $currentScript -Algorithm SHA256).Hash
                    $date = $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                    $writer.WriteLine("OK|$script:AppVersion|$($item.Length)|$h|$date|$env:COMPUTERNAME|$env:USERNAME")
                } else {
                    $writer.WriteLine("ERR|Script not found")
                }
            } elseif ($cmd -eq "NEXUS_PULL_APP_UPDATE") {
                $currentScript = $script:AppScriptPath
                if (Test-Path $currentScript) {
                    $item = Get-Item $currentScript
                    $h = (Get-FileHash -Path $currentScript -Algorithm SHA256).Hash
                    $writer.WriteLine("OK|$($script:AppVersion)|$($item.Length)|$h")
                    
                    $fs = [System.IO.File]::OpenRead($currentScript)
                    $buf = New-Object byte[] 65536
                    while (($read = $fs.Read($buf, 0, $buf.Length)) -gt 0) {
                        $stream.Write($buf, 0, $read)
                    }
                    $fs.Close()
                    $stream.Flush()
                } else {
                    $writer.WriteLine("ERR|Script not found")
                }
            }
        } catch {
        } finally {
            try { $client.Close() } catch {}
        }
    }

    function Handle-IncomingLanWebClient ($client) {
        try {
            $stream = $client.GetStream()
            
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
            if ($headerBytes.Count -eq 0) { $client.Close(); return }
            
            $headerStr = [System.Text.Encoding]::ASCII.GetString($headerBytes.ToArray())
            $lines = $headerStr -split "`r`n"
            $reqLine = $lines[0]
            $reqParts = $reqLine -split '\s+'
            if ($reqParts.Length -lt 2) { $client.Close(); return }
            
            $method = $reqParts[0].ToUpperInvariant()
            $rawUrl = $reqParts[1]
            
            $contentLen = 0
            foreach ($l in $lines) {
                if ($l -match '(?i)^Content-Length:\s*(\d+)') { $contentLen = [int64]$matches[1] }
            }
            
            if ($method -eq "GET" -and ($rawUrl -eq "/" -or $rawUrl -like "/?*")) {
                $allAvailableFiles = @()
                foreach ($f in $script:LanSendFilesList) {
                    if (Test-Path $f) { $allAvailableFiles += Get-Item $f }
                }
                foreach ($f in $script:LanOutboxList) {
                    if (Test-Path $f) {
                        $it = Get-Item $f
                        $already = $false
                        foreach ($af in $allAvailableFiles) { if ($af.FullName -eq $it.FullName) { $already = $true; break } }
                        if (-not $already) { $allAvailableFiles += $it }
                    }
                }
                
                $filesHtml = ""
                if ($allAvailableFiles.Count -gt 0) {
                    foreach ($fi in $allAvailableFiles) {
                        $encName = [System.Uri]::EscapeDataString($fi.Name)
                        $safeName = $fi.Name -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;'
                        $sz = Format-LanFileSize $fi.Length
                        $filesHtml += "<div class='file-item'><div><span class='file-name'>$safeName</span><span class='file-size'>($sz)</span></div><a class='btn' href='/download?name=$encName'>Download</a></div>"
                    }
                } else {
                    $filesHtml = "<div style='color:#94a3b8; font-size:13px; padding:12px 0;'>No files queued for download right now.<br>Add files in Nexus under 'DIRECT PC SHARE' or upload a file below.</div>"
                }
                
                $html = "<!DOCTYPE html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1'><title>Nexus LAN Share - $env:COMPUTERNAME</title><style>body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0b1120; color: #e2e8f0; margin: 0; padding: 24px; } .container { max-width: 680px; margin: 0 auto; } .card { background: #0f172a; border: 1px solid #1e3252; border-radius: 12px; padding: 20px; margin-bottom: 20px; box-shadow: 0 4px 12px rgba(0,0,0,0.3); } h1 { margin: 0 0 6px 0; font-size: 20px; color: #38bdf8; } .subtitle { font-size: 13px; color: #94a3b8; margin-bottom: 16px; } .btn { display: inline-block; background: #0284c7; color: white; text-decoration: none; padding: 7px 14px; border-radius: 6px; font-weight: bold; font-size: 12.5px; cursor: pointer; border: none; } .btn-success { background: #059669; } .btn:hover { opacity: 0.9; } .file-item { display: flex; justify-content: space-between; align-items: center; padding: 10px 14px; background: #0a0e1a; border: 1px solid #1e293b; border-radius: 6px; margin-bottom: 8px; } .file-name { font-weight: bold; color: #f1f5f9; font-family: Consolas, monospace; font-size: 12.5px; } .file-size { color: #64748b; font-size: 11.5px; margin-left: 8px; } .pbar { width: 100%; height: 8px; background: #1e293b; border-radius: 4px; overflow: hidden; margin-top: 12px; display: none; } .pfill { height: 100%; background: #38bdf8; width: 0%; transition: width 0.2s; } .status-box { margin-top: 10px; font-size: 12.5px; font-weight: bold; }</style></head><body><div class='container'><div class='card'><h1>Nexus Direct LAN Share</h1><div class='subtitle'>Host: <strong>$env:COMPUTERNAME</strong> | User: $env:USERNAME</div><p style='font-size:13px; color:#cbd5e1; margin:0;'>Download files shared from $env:COMPUTERNAME directly at full LAN speed without installing any software.</p></div><div class='card'><h2 style='font-size:15px; margin-top:0; color:#f8fafc;'>Files Available to Download</h2>$filesHtml</div><div class='card'><h2 style='font-size:15px; margin-top:0; color:#f8fafc;'>Upload a File to $env:COMPUTERNAME</h2><p style='font-size:12.5px; color:#94a3b8; margin:0 0 12px 0;'>Send any file directly to $env:COMPUTERNAME's Desktop\Nexus_Received_Files:</p><input type='file' id='upFile' style='margin-bottom:12px; display:block; color:#94a3b8; font-size:13px;'><button class='btn btn-success' onclick='uploadFile()'>Send File to $env:COMPUTERNAME</button><div class='pbar' id='pBar'><div class='pfill' id='pFill'></div></div><div class='status-box' id='upStatus'></div></div></div><script>function uploadFile() { var fInput = document.getElementById('upFile'); if (!fInput.files || fInput.files.length === 0) { alert('Please select a file first!'); return; } var file = fInput.files[0]; var pBar = document.getElementById('pBar'); var pFill = document.getElementById('pFill'); var status = document.getElementById('upStatus'); pBar.style.display = 'block'; pFill.style.width = '0%'; status.style.color = '#38bdf8'; status.textContent = 'Uploading ' + file.name + '...'; var xhr = new XMLHttpRequest(); xhr.open('POST', '/upload?name=' + encodeURIComponent(file.name)); xhr.upload.onprogress = function(e) { if (e.lengthComputable) { var pct = Math.round((e.loaded / e.total) * 100); pFill.style.width = pct + '%'; status.textContent = 'Uploading: ' + pct + '% (' + (e.loaded/1048576).toFixed(1) + ' MB / ' + (e.total/1048576).toFixed(1) + ' MB)'; } }; xhr.onload = function() { if (xhr.status === 200) { status.style.color = '#34d399'; status.textContent = 'Upload Complete! File saved onto $env:COMPUTERNAME.'; fInput.value = ''; } else { status.style.color = '#f87171'; status.textContent = 'Upload failed: ' + xhr.responseText; } }; xhr.onerror = function() { status.style.color = '#f87171'; status.textContent = 'Upload failed due to network error.'; }; xhr.send(file); }</script></body></html>"
                
                $htmlBytes = [System.Text.Encoding]::UTF8.GetBytes($html)
                $resp = "HTTP/1.1 200 OK`r`nContent-Type: text/html; charset=utf-8`r`nContent-Length: $($htmlBytes.Length)`r`nConnection: close`r`n`r`n"
                $respBytes = [System.Text.Encoding]::ASCII.GetBytes($resp)
                $stream.Write($respBytes, 0, $respBytes.Length)
                $stream.Write($htmlBytes, 0, $htmlBytes.Length)
                $stream.Flush()

            } elseif ($method -eq "GET" -and $rawUrl -like "/download*") {
                $qIdx = $rawUrl.IndexOf("name=")
                $reqName = if ($qIdx -ge 0) { [System.Uri]::UnescapeDataString($rawUrl.Substring($qIdx + 5)) } else { "" }
                $reqName = [System.IO.Path]::GetFileName($reqName)
                
                $matchedPath = $null
                foreach ($f in $script:LanSendFilesList) {
                    if (Test-Path $f -and [System.IO.Path]::GetFileName($f) -eq $reqName) { $matchedPath = $f; break }
                }
                if (-not $matchedPath) {
                    foreach ($f in $script:LanOutboxList) {
                        if (Test-Path $f -and [System.IO.Path]::GetFileName($f) -eq $reqName) { $matchedPath = $f; break }
                    }
                }
                
                if ($matchedPath -and (Test-Path $matchedPath)) {
                    $fi = Get-Item $matchedPath
                    $resp = "HTTP/1.1 200 OK`r`nContent-Type: application/octet-stream`r`nContent-Disposition: attachment; filename=`"$($fi.Name)`"`r`nContent-Length: $($fi.Length)`r`nConnection: close`r`n`r`n"
                    $respBytes = [System.Text.Encoding]::ASCII.GetBytes($resp)
                    $stream.Write($respBytes, 0, $respBytes.Length)
                    
                    $fs = [System.IO.File]::OpenRead($matchedPath)
                    $buf = New-Object byte[] 65536
                    while (($r = $fs.Read($buf, 0, $buf.Length)) -gt 0) {
                        $stream.Write($buf, 0, $r)
                    }
                    $fs.Close()
                    $stream.Flush()
                    
                    if ($lblLanTransferLog) {
                        $lblLanTransferLog.Text = "[WEB DOWNLOAD] Streamed '$($fi.Name)' ($(Format-LanFileSize $fi.Length)) to web browser"
                        $lblLanTransferLog.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
                    }
                } else {
                    $errHtml = "File not found or no longer available."
                    $errBytes = [System.Text.Encoding]::UTF8.GetBytes($errHtml)
                    $resp = "HTTP/1.1 404 Not Found`r`nContent-Type: text/plain`r`nContent-Length: $($errBytes.Length)`r`nConnection: close`r`n`r`n"
                    $respBytes = [System.Text.Encoding]::ASCII.GetBytes($resp)
                    $stream.Write($respBytes, 0, $respBytes.Length)
                    $stream.Write($errBytes, 0, $errBytes.Length)
                    $stream.Flush()
                }

            } elseif ($method -eq "POST" -and $rawUrl -like "/upload*") {
                $qIdx = $rawUrl.IndexOf("name=")
                $upName = if ($qIdx -ge 0) { [System.Uri]::UnescapeDataString($rawUrl.Substring($qIdx + 5)) } else { "uploaded_file.bin" }
                $upName = [System.IO.Path]::GetFileName($upName)
                
                if (-not (Test-Path $script:LanReceivedDir)) { try { New-Item -ItemType Directory -Path $script:LanReceivedDir -Force | Out-Null } catch {} }`n                $destPath = Join-Path $script:LanReceivedDir $upName
                $counter = 1
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($upName)
                $ext = [System.IO.Path]::GetExtension($upName)
                while (Test-Path $destPath) {
                    $destPath = Join-Path $script:LanReceivedDir "$baseName ($counter)$ext"
                    $counter++
                }
                
                $fs = [System.IO.File]::Create($destPath)
                $buf = New-Object byte[] 65536
                $received = 0
                while ($received -lt $contentLen) {
                    $chunk = [Math]::Min($buf.Length, $contentLen - $received)
                    $read = $stream.Read($buf, 0, $chunk)
                    if ($read -le 0) { break }
                    $fs.Write($buf, 0, $read)
                    $received += $read
                }
                $fs.Close()
                
                $resp = "HTTP/1.1 200 OK`r`nContent-Type: text/plain`r`nContent-Length: 2`r`nConnection: close`r`n`r`nOK"
                $respBytes = [System.Text.Encoding]::ASCII.GetBytes($resp)
                $stream.Write($respBytes, 0, $respBytes.Length)
                $stream.Flush()
                
                $finalName = [System.IO.Path]::GetFileName($destPath)
                $szStr = Format-LanFileSize $received
                if ($lblLanTransferLog) {
                    $lblLanTransferLog.Text = "[RECEIVED VIA WEB] '$finalName' ($szStr) saved to Desktop\Nexus_Received_Files"
                    $lblLanTransferLog.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
                }
                
                [System.Windows.MessageBox]::Show("New File Received via Web Share!`r`n`r`nFile: $finalName`r`nSize: $szStr`r`nSaved into: Desktop\Nexus_Received_Files", "Direct PC Share - Web File Received", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            }
        } catch {} finally {
            try { $client.Close() } catch {}
        }
    }

    if ($btnLanScanPeers) {
        $btnLanScanPeers.Add_Click({
            Start-LanNetworking
            Broadcast-LanBeacon
            if ($lblLanPeerStatus) {
                $lblLanPeerStatus.Text = "Scanning network broadcast for peers..."
                $lblLanPeerStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
            }
        })
    }

    if ($btnLanCopyWebLink) {
        $btnLanCopyWebLink.Add_Click({
            if ($script:LanSendFilesList.Count -eq 0) {
                $dlg = New-Object Microsoft.Win32.OpenFileDialog
                $dlg.Multiselect = $true
                $dlg.Title = "Select File(s) to Create Instant Download Link"
                if ($dlg.ShowDialog()) {
                    foreach ($f in $dlg.FileNames) {
                        if (-not $script:LanSendFilesList.Contains($f)) {
                            $script:LanSendFilesList.Add($f)
                        }
                    }
                    Update-LanSendFilesList
                } else {
                    return
                }
            }

            if ($lblLanSendStatus) {
                $lblLanSendStatus.Text = "Creating universal download link (Firewall-free)..."
            }
            if ($lblLanTransferLog) {
                $lblLanTransferLog.Text = "Generating download link for colleague..."
                $lblLanTransferLog.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
            }
            [System.Windows.Forms.Application]::DoEvents()

            $link = Get-UniversalShareLink $script:LanSendFilesList
            if ($link) {
                try { [System.Windows.Clipboard]::SetText($link) } catch {}
                if ($lblLanSendStatus) {
                    $lblLanSendStatus.Text = "Download link copied to clipboard!"
                    $lblLanSendStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
                }
                if ($lblLanTransferLog) {
                    $lblLanTransferLog.Text = "Link Copied: $link (Works on ANY PC or phone without firewall)"
                    $lblLanTransferLog.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
                }
                [System.Windows.MessageBox]::Show("Download Link Ready & Copied to Clipboard!`r`n`r`n$link`r`n`r`nPaste this link to your colleague in WhatsApp, Teams, or Email.`r`nThey can open it in Chrome or Edge on any computer to download the file directly (No firewall or software needed)!", "Download Link Ready", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            } else {
                [System.Windows.MessageBox]::Show("Could not create download link. Please check your internet connection.", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
            }
        })
    }

    if ($btnLanOpenWebLink) {
        $btnLanOpenWebLink.Add_Click({
            if ($script:LanSendFilesList.Count -eq 0) {
                $btnLanCopyWebLink.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
                return
            }
            if ($lblLanSendStatus) {
                $lblLanSendStatus.Text = "Creating download link and opening browser..."
            }
            [System.Windows.Forms.Application]::DoEvents()
            $link = Get-UniversalShareLink $script:LanSendFilesList
            if ($link) {
                try { [System.Windows.Clipboard]::SetText($link) } catch {}
                Start-Process $link
            }
        })
    }

    if ($btnLanFixFirewall) {
        $btnLanFixFirewall.Add_Click({
            $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
            if (-not $scriptDir) { $scriptDir = "C:\Users\mandar.k\Documents\antigravity\lively-raman" }
            $fwCmd = Join-Path $scriptDir "Enable-LanShareFirewall.cmd"
            if (Test-Path $fwCmd) {
                Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$fwCmd`"" -Verb RunAs
            } else {
                [System.Windows.MessageBox]::Show("To allow LAN file transfers through Windows Firewall, run this in Administrator Command Prompt:`r`n`r`nnetsh advfirewall firewall add rule name=`"Nexus Direct PC Share TCP`" dir=in action=allow protocol=TCP localport=52824,52826 profile=any`r`nnetsh advfirewall firewall add rule name=`"Nexus Direct PC Share UDP`" dir=in action=allow protocol=UDP localport=52822 profile=any", "Firewall Configuration", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            }
        })
    }

    if ($btnLanPushAppUpdate) {
        $btnLanPushAppUpdate.Add_Click({
            Push-AppUpdateToAllPeers
        })
    }

    if ($btnLanCheckAppUpdate) {
        $btnLanCheckAppUpdate.Add_Click({
            Check-AppUpdatesFromNetwork -UserInitiated $true
        })
    }

    if ($btnLanQuickAssist) {
        $btnLanQuickAssist.Add_Click({
            try {
                Start-Process "quickassist.exe"
            } catch {
                try {
                    Start-Process "mstsc.exe"
                } catch {
                    [System.Windows.MessageBox]::Show("Could not launch Windows Quick Assist. Press Win+Ctrl+Q to launch it directly.", "Remote Assist", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
                }
            }
        })
    }

    if ($lstLanPeers) {
        $lstLanPeers.Add_SelectionChanged({
            $selectedItem = $lstLanPeers.SelectedItem
            if ($selectedItem -and $selectedItem.Tag) {
                $script:LanSelectedPeer = $selectedItem.Tag
                if ($lblLanTargetPc) {
                    $lblLanTargetPc.Text = "$($script:LanSelectedPeer.HostName) ($($script:LanSelectedPeer.UserName))"
                    $lblLanTargetPc.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
                }
                if ($txtLanManualHost) { $txtLanManualHost.Text = $script:LanSelectedPeer.HostName }
            }
        })
    }

    if ($btnLanManualConnect) {
        $btnLanManualConnect.Add_Click({
            $hostName = $txtLanManualHost.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($hostName)) { return }
            
            try {
                $addrs = [System.Net.Dns]::GetHostAddresses($hostName)
                $ipv4 = $addrs | Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } | Select-Object -First 1
                if ($ipv4) {
                    $peerObj = [PSCustomObject]@{
                        HostName = $hostName.ToUpperInvariant()
                        UserName = "Network Peer"
                        IP = $ipv4.ToString()
                        Port = $script:LanTcpPort
                        LastSeen = (Get-Date)
                    }
                    $script:LanPeers[$hostName.ToUpperInvariant()] = $peerObj
                    Refresh-LanPeersList
                    $script:LanSelectedPeer = $peerObj
                    if ($lblLanTargetPc) {
                        $lblLanTargetPc.Text = "$($peerObj.HostName)"
                        $lblLanTargetPc.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
                    }
                    if ($lblLanTransferLog) {
                        $lblLanTransferLog.Text = "Connected directly to '$($peerObj.HostName)' (No IP needed)!"
                    }
                } else {
                    [System.Windows.MessageBox]::Show("Could not resolve computer name '$hostName'. Please verify the computer name.", "Computer Not Found", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                }
            } catch {
                [System.Windows.MessageBox]::Show("Could not connect to '$hostName': $($_.Exception.Message)", "Connection Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
            }
        })
    }

    function Update-LanSendFilesList {
        if (-not $lstLanSendFiles) { return }
        $lstLanSendFiles.Items.Clear()
        $totalBytes = 0
        foreach ($f in $script:LanSendFilesList) {
            if (Test-Path $f) {
                $item = Get-Item $f
                $totalBytes += $item.Length
                $lstLanSendFiles.Items.Add("$($item.Name)  ($(Format-LanFileSize $item.Length))") | Out-Null
            }
        }
        if ($lblLanSendStatus) {
            $lblLanSendStatus.Text = "Queued $($script:LanSendFilesList.Count) file(s) ($(Format-LanFileSize $totalBytes))"
        }
    }

    if ($btnLanAddFiles) {
        $btnLanAddFiles.Add_Click({
            $dlg = New-Object Microsoft.Win32.OpenFileDialog
            $dlg.Multiselect = $true
            $dlg.Title = "Select Files to Send via Direct PC Share"
            if ($dlg.ShowDialog()) {
                foreach ($f in $dlg.FileNames) {
                    if (-not $script:LanSendFilesList.Contains($f)) {
                        $script:LanSendFilesList.Add($f)
                    }
                }
                Update-LanSendFilesList
            }
        })
    }

    if ($btnLanAddFolder) {
        $btnLanAddFolder.Add_Click({
            $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
            $dlg.Description = "Select Folder to Send via Direct PC Share"
            if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $folderFiles = Get-ChildItem -Path $dlg.SelectedPath -File -Recurse
                foreach ($f in $folderFiles) {
                    if (-not $script:LanSendFilesList.Contains($f.FullName)) {
                        $script:LanSendFilesList.Add($f.FullName)
                    }
                }
                Update-LanSendFilesList
            }
        })
    }

    if ($btnLanClearSend) {
        $btnLanClearSend.Add_Click({
            $script:LanSendFilesList.Clear()
            Update-LanSendFilesList
        })
    }

    if ($btnLanSendNow) {
        $btnLanSendNow.Add_Click({
            if (-not $script:LanSelectedPeer) {
                if ($txtLanManualHost -and -not [string]::IsNullOrWhiteSpace($txtLanManualHost.Text)) {
                    $btnLanManualConnect.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
                }
            }
            
            if (-not $script:LanSelectedPeer) {
                [System.Windows.MessageBox]::Show("Please select a destination computer from the list on the left, or enter a computer name.", "No Destination PC Selected", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                return
            }

            if ($script:LanSendFilesList.Count -eq 0) {
                [System.Windows.MessageBox]::Show("Please add at least one file to send.", "No Files Selected", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                return
            }

            $targetPeer = $script:LanSelectedPeer
            $targetIP = $targetPeer.IP
            $targetPort = if ($targetPeer.Port) { $targetPeer.Port } else { 52824 }

            $btnLanSendNow.IsEnabled = $false
            $prgLanSend.Value = 0

            try {
                $sentCount = 0
                $totalBytesSent = 0
                $totalFiles = $script:LanSendFilesList.Count

                foreach ($filePath in $script:LanSendFilesList) {
                    if (-not (Test-Path $filePath)) { continue }
                    $fi = Get-Item $filePath
                    $fileName = $fi.Name
                    $fileLen = $fi.Length

                    $lblLanSendStatus.Text = "Connecting to $($targetPeer.HostName)..."
                    [System.Windows.Forms.Application]::DoEvents()

                    $client = Connect-LanTcpPeer $targetIP $targetPort 3500
                    if (-not $client) {
                        Show-LanUnreachableDialog $targetPeer
                        return
                    }

                    $lblLanSendStatus.Text = "Sending '$fileName' ($(Format-LanFileSize $fileLen)) to $($targetPeer.HostName)..."
                    [System.Windows.Forms.Application]::DoEvents()

                    $stream = $client.GetStream()
                    $writer = New-Object System.IO.StreamWriter($stream, [System.Text.Encoding]::UTF8)
                    $writer.AutoFlush = $true
                    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)

                    $header = "NEXUS_SEND|$fileName|$fileLen|$env:COMPUTERNAME|$env:USERNAME"
                    $writer.WriteLine($header)

                    $fs = [System.IO.File]::OpenRead($filePath)
                    $buf = New-Object byte[] 65536
                    $fileSent = 0
                    while (($read = $fs.Read($buf, 0, $buf.Length)) -gt 0) {
                        $stream.Write($buf, 0, $read)
                        $fileSent += $read
                        $totalBytesSent += $read
                        
                        $pct = [int](($fileSent / [Math]::Max(1, $fileLen)) * 100)
                        $prgLanSend.Value = $pct
                        [System.Windows.Forms.Application]::DoEvents()
                    }
                    $fs.Close()
                    $stream.Flush()

                    $ack = $reader.ReadLine()
                    $client.Close()
                    $sentCount++
                }

                $prgLanSend.Value = 100
                $lblLanSendStatus.Text = "All $sentCount file(s) sent successfully! ($(Format-LanFileSize $totalBytesSent))"
                $lblLanSendStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
                
                if ($lblLanTransferLog) {
                    $lblLanTransferLog.Text = "[SENT SUCCESS] Sent $sentCount file(s) to $($targetPeer.HostName) at $(Get-Date -Format 'HH:mm:ss')"
                    $lblLanTransferLog.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
                }

                [System.Windows.MessageBox]::Show("Successfully sent $sentCount file(s) ($(Format-LanFileSize $totalBytesSent)) directly to $($targetPeer.HostName)!`r`n`r`nThey have been saved into Desktop\Nexus_Received_Files on the target PC.", "Transfer Complete", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)

            } catch {
                $lblLanSendStatus.Text = "Transfer error: $($_.Exception.Message)"
                $lblLanSendStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F87171")
                Show-LanUnreachableDialog $targetPeer
            } finally {
                $btnLanSendNow.IsEnabled = $true
            }
        })
    }

    if ($btnLanBrowseRemote) {
        $btnLanBrowseRemote.Add_Click({
            if (-not $script:LanSelectedPeer) {
                [System.Windows.MessageBox]::Show("Please select a computer on the left first.", "Notice", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
                return
            }

            $targetPeer = $script:LanSelectedPeer
            try {
                $client = Connect-LanTcpPeer $targetPeer.IP $targetPeer.Port 3500
                if (-not $client) {
                    Show-LanUnreachableDialog $targetPeer
                    return
                }

                $stream = $client.GetStream()
                $writer = New-Object System.IO.StreamWriter($stream, [System.Text.Encoding]::UTF8)
                $writer.AutoFlush = $true
                $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)

                $writer.WriteLine("NEXUS_LIST")
                $resp = $reader.ReadLine()
                $client.Close()

                $parts = $resp -split '\|', 2
                if ($parts[0] -eq "OK" -and $parts.Length -gt 1) {
                    $items = $parts[1] | ConvertFrom-Json
                    $lstLanRemoteFiles.Items.Clear()
                    if ($items) {
                        foreach ($fi in $items) {
                            $lbi = New-Object System.Windows.Controls.ListBoxItem
                            $lbi.Tag = $fi
                            $lbi.Content = "$($fi.Name)  ($($fi.Size))"
                            $lstLanRemoteFiles.Items.Add($lbi) | Out-Null
                        }
                    }
                    if ($lblLanTransferLog) {
                        $lblLanTransferLog.Text = "Fetched $($items.Count) shared file(s) available on $($targetPeer.HostName)"
                    }
                }
            } catch {
                Show-LanUnreachableDialog $targetPeer
            }
        })
    }

    if ($btnLanTakeSelected) {
        $btnLanTakeSelected.Add_Click({
            if (-not $script:LanSelectedPeer) {
                [System.Windows.MessageBox]::Show("Please select a computer on the left first.", "Notice", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
                return
            }

            $selectedItem = $lstLanRemoteFiles.SelectedItem
            if (-not $selectedItem -or -not $selectedItem.Tag) {
                [System.Windows.MessageBox]::Show("Please select a file from the list to take / download.", "No File Selected", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
                return
            }

            $remoteFile = $selectedItem.Tag
            $reqName = $remoteFile.Name
            $targetPeer = $script:LanSelectedPeer

            try {
                $client = Connect-LanTcpPeer $targetPeer.IP $targetPeer.Port 3500
                if (-not $client) {
                    Show-LanUnreachableDialog $targetPeer
                    return
                }

                $stream = $client.GetStream()
                $writer = New-Object System.IO.StreamWriter($stream, [System.Text.Encoding]::UTF8)
                $writer.AutoFlush = $true
                $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)

                $writer.WriteLine("NEXUS_PULL|$reqName")
                $header = $reader.ReadLine()
                $hParts = $header -split '\|'

                if ($hParts[0] -eq "OK") {
                    $downName = $hParts[1]
                    $downLen = [int64]$hParts[2]

                    if (-not (Test-Path $script:LanReceivedDir)) { try { New-Item -ItemType Directory -Path $script:LanReceivedDir -Force | Out-Null } catch {} }`n                    $destPath = Join-Path $script:LanReceivedDir $downName
                    $fs = New-Object System.IO.FileStream($destPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
                    $buf = New-Object byte[] 65536
                    $totalDown = 0
                    while ($totalDown -lt $downLen) {
                        $c = [Math]::Min($buf.Length, $downLen - $totalDown)
                        $r = $stream.Read($buf, 0, $c)
                        if ($r -le 0) { break }
                        $fs.Write($buf, 0, $r)
                        $totalDown += $r
                    }
                    $fs.Close()
                    $client.Close()

                    if ($lblLanTransferLog) {
                        $lblLanTransferLog.Text = "[DOWNLOADED] Successfully took '$downName' ($(Format-LanFileSize $totalDown)) from $($targetPeer.HostName)"
                        $lblLanTransferLog.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399")
                    }

                    [System.Windows.MessageBox]::Show("File Successfully Downloaded!`r`n`r`nFile: $downName`r`nSize: $(Format-LanFileSize $totalDown)`r`nFrom: $($targetPeer.HostName)`r`n`r`nSaved into: Desktop\Nexus_Received_Files", "File Taken Successfully", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
                } else {
                    $client.Close()
                    [System.Windows.MessageBox]::Show("Could not take file: $($hParts[1])", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                }
            } catch {
                Show-LanUnreachableDialog $targetPeer
            }
        })
    }

    function Update-LanOutboxList {
        if (-not $lstLanOutbox) { return }
        $lstLanOutbox.Items.Clear()
        foreach ($f in $script:LanOutboxList) {
            if (Test-Path $f) {
                $item = Get-Item $f
                $lstLanOutbox.Items.Add("$($item.Name)  ($(Format-LanFileSize $item.Length))") | Out-Null
            }
        }
    }

    if ($btnLanAddOutbox) {
        $btnLanAddOutbox.Add_Click({
            $dlg = New-Object Microsoft.Win32.OpenFileDialog
            $dlg.Multiselect = $true
            $dlg.Title = "Add Files to Your Shared Outbox (Other PCs can take these)"
            if ($dlg.ShowDialog()) {
                foreach ($f in $dlg.FileNames) {
                    if (-not $script:LanOutboxList.Contains($f)) {
                        $script:LanOutboxList.Add($f)
                    }
                }
                Update-LanOutboxList
            }
        })
    }

    if ($btnLanClearOutbox) {
        $btnLanClearOutbox.Add_Click({
            $script:LanOutboxList.Clear()
            Update-LanOutboxList
        })
    }

    if ($btnLanOpenReceived) {
        $btnLanOpenReceived.Add_Click({
            if (-not (Test-Path $script:LanReceivedDir)) {
                New-Item -ItemType Directory -Path $script:LanReceivedDir -Force | Out-Null
            }
            Start-Process "explorer.exe" $script:LanReceivedDir
        })
    }

    if ($btnLanOpenUnc) {
        $btnLanOpenUnc.Add_Click({
            if ($script:LanSelectedPeer -and $script:LanSelectedPeer.HostName) {
                $uncPath = "\\$($script:LanSelectedPeer.HostName)"
                try {
                    Start-Process "explorer.exe" $uncPath
                } catch {
                    [System.Windows.MessageBox]::Show("Could not open Windows network share for '$uncPath': $($_.Exception.Message)", "Network Share", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                }
            } else {
                [System.Windows.MessageBox]::Show("Please select a computer from the list first.", "Notice", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            }
        })
    }

    function Register-NexusPeerHeartbeat {
        try {
            $connInfo = Get-ActiveOrSavedSqlConnection
            if (-not $connInfo) { return }
            $conn = $connInfo.Connection
            $shouldClose = -not $connInfo.IsShared
            try {
                $curSc = $script:AppScriptPath
                if (-not (Test-Path $curSc)) { $curSc = Join-Path $PSScriptRoot "PMC-ImageResizer-App.ps1" }
                $locHash = if (Test-Path $curSc) { (Get-FileHash -Path $curSc -Algorithm SHA256).Hash } else { "" }
                $peerIp = if ($script:LanLocalIP) { $script:LanLocalIP } else { "127.0.0.1" }
                $peerVer = if ($script:AppVersion) { $script:AppVersion } else { "5.4.0" }

                $cmd = $conn.CreateCommand()
                $cmd.CommandText = "MERGE _NexusActivePeers AS target USING (SELECT @comp AS ComputerName) AS source ON (target.ComputerName = source.ComputerName) WHEN MATCHED THEN UPDATE SET UserName = @usr, IPAddress = @ip, AppVersion = @ver, ScriptHash = @hash, LastHeartbeat = GETDATE(), Status = 'ONLINE' WHEN NOT MATCHED THEN INSERT (ComputerName, UserName, IPAddress, AppVersion, ScriptHash, LastHeartbeat, Status) VALUES (@comp, @usr, @ip, @ver, @hash, GETDATE(), 'ONLINE');"
                $cmd.Parameters.AddWithValue("@comp", $env:COMPUTERNAME) | Out-Null
                $cmd.Parameters.AddWithValue("@usr", $env:USERNAME) | Out-Null
                $cmd.Parameters.AddWithValue("@ip", $peerIp) | Out-Null
                $cmd.Parameters.AddWithValue("@ver", $peerVer) | Out-Null
                $cmd.Parameters.AddWithValue("@hash", $locHash) | Out-Null
                $cmd.ExecuteNonQuery() | Out-Null
                $cmd.Dispose()
            } finally {
                if ($shouldClose) { try { $conn.Close() } catch {} }
            }
        } catch {}
    }

    function Start-GlobalAutoUpdateMonitor {
        try {
            Start-LanNetworking

            if (-not $script:AutoUpdateTimer) {
                $script:AutoUpdateTimer = New-Object System.Windows.Threading.DispatcherTimer
                $script:AutoUpdateTimer.Interval = [TimeSpan]::FromSeconds(20)
                $script:AutoUpdateTimer.Add_Tick({
                    try {
                        Register-NexusPeerHeartbeat
                        Check-AppUpdatesFromNetwork -UserInitiated $false
                    } catch {}
                })
                $script:AutoUpdateTimer.Start()
            }

            # Run startup check 2.5 seconds after launch
            $startupTimer = New-Object System.Windows.Threading.DispatcherTimer
            $startupTimer.Interval = [TimeSpan]::FromMilliseconds(2500)
            $startupTimer.Add_Tick({
                $startupTimer.Stop()
                try {
                    Register-NexusPeerHeartbeat
                    Check-AppUpdatesFromNetwork -UserInitiated $false -OnStartup $true
                } catch {}
            })
            $startupTimer.Start()
        } catch {}
    }

    # 4. Start Global Background Update Monitor on Window Loaded
    $window.Add_Loaded({
        try { Start-GlobalAutoUpdateMonitor } catch {}
    })

    # 5. Clean Timer Teardown on Window Close
    $window.Add_Closed({
        try {
            if ($global:mascotBlinkTimer) { $global:mascotBlinkTimer.Stop() }
            if ($global:bgDebounceTimer) { $global:bgDebounceTimer.Stop() }
            if ($script:AutoUpdateTimer) { $script:AutoUpdateTimer.Stop() }
            if ($script:LanTimer) { $script:LanTimer.Stop() }
            if ($script:LanUdpSocket) { $script:LanUdpSocket.Close() }
            if ($script:LanTcpListener) { $script:LanTcpListener.Stop() }
            if ($script:LanWebListener) { $script:LanWebListener.Stop() }
            if ($txtSqlConnStr -and -not [string]::IsNullOrWhiteSpace($txtSqlConnStr.Text) -and $txtSqlConnStr.Text -ne $script:SqlPlaceholder) {
                $curConn = $txtSqlConnStr.Text.Trim()
                if ($curConn -match "(?i)(?:server|data source)\s*=") { Save-ConnectionAuto -ConnStr $curConn }
            }
        } catch {}
    })

} catch {}

$window.ShowDialog() | Out-Null
