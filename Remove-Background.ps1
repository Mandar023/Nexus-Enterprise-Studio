<#
.SYNOPSIS
    Nexus Background Remover & Signature Extractor
    Removes backgrounds from photos or isolates signatures/handwriting onto transparent PNG or pure white canvas.

.PARAMETER InputPath
    Path to the source image file (.png, .jpg, .jpeg, .bmp, .webp, .tif).

.PARAMETER OutputPath
    Optional output file path. Defaults to [filename]_nobg.png on Desktop.

.PARAMETER Mode
    Processing mode: 'Signature' (default, extracts ink to transparent PNG) or 'Portrait' (removes photo background).

.PARAMETER BgType
    Output background type: 'Transparent' (default), 'White', or 'Blue'.

.PARAMETER Tolerance
    Tolerance / sensitivity percentage (1 to 100, default: 50).

.PARAMETER EnhanceInk
    Switch to darken and sharpen signature ink strokes.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $false)]
    [string]$InputPath = "",

    [Parameter(Position = 1, Mandatory = $false)]
    [string]$OutputPath = "",

    [ValidateSet("Auto", "Signature", "Portrait")]
    [string]$Mode = "Auto",

    [ValidateSet("Transparent", "White", "Blue", "WMF")]
    [string]$BgType = "Transparent",

    [int]$Tolerance = 50,

    [switch]$EnhanceInk,

    [switch]$AutoCrop
)

Add-Type -AssemblyName System.Drawing, System.Windows.Forms

# --- Compile BackgroundRemovalEngine in C# ---
$csharp = @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public class BackgroundRemovalEngine
{
    [DllImport("gdi32.dll")]
    public static extern bool DeleteEnhMetaFile(IntPtr hemf);

    [DllImport("gdiplus.dll", SetLastError = true)]
    public static extern int GdipEmfToWmfBits(IntPtr hEmf, int uBufferSize, byte[] bBuffer, int iMappingMode, int flags);

    public static Bitmap LoadAnyImage(string filePath)
    {
        using (Image img = Image.FromFile(filePath))
        {
            int w = img.Width > 0 ? img.Width : 700;
            int h = img.Height > 0 ? img.Height : 700;
            Bitmap bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
            bmp.SetResolution(96, 96);
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.Clear(Color.White);
                g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.HighQuality;
                g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
                g.DrawImage(img, 0, 0, w, h);
            }
            return bmp;
        }
    }

    public static bool DetectIsSignature(Bitmap bmp)
    {
        int w = bmp.Width;
        int h = bmp.Height;
        int brightCount = 0;
        int totalSampled = 0;
        int lowSaturationCount = 0;

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
                if (lum > 172.0) brightCount++;

                int maxC = Math.Max(r, Math.Max(g, b));
                int minC = Math.Min(r, Math.Min(g, b));
                if ((maxC - minC) < 32) lowSaturationCount++;
            }
        }

        double brightRatio = (double)brightCount / Math.Max(1, totalSampled);
        double lowSatRatio = (double)lowSaturationCount / Math.Max(1, totalSampled);

        return (brightRatio > 0.60 && lowSatRatio > 0.55);
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

        // Divide into local blocks (32x32) to compute local paper background illumination model
        int blockSize = Math.Max(16, Math.Min(48, Math.Min(w, h) / 15));
        int gridW = (w + blockSize - 1) / blockSize;
        int gridH = (h + blockSize - 1) / blockSize;
        double[,] bgGrid = new double[gridW, gridH];

        for (int gy = 0; gy < gridH; gy++)
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
        }

        double sensFactor = sensitivity / 100.0;
        double normThreshold = 0.88 + (sensFactor - 0.5) * 0.12;
        double solidInkThreshold = normThreshold * 0.68;

        byte[] destBuf = new byte[totalBytes];
        int minX = w, maxX = 0, minY = h, maxY = 0;
        bool hasForeground = false;

        for (int y = 0; y < h; y++)
        {
            int rowIdx = y * stride;
            double gy = (double)y / blockSize;
            int gy0 = Math.Min(gridH - 1, (int)gy);
            int gy1 = Math.Min(gridH - 1, gy0 + 1);
            double yFrac = gy - gy0;

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
                    hasForeground = true;
                    if (x < minX) minX = x;
                    if (x > maxX) maxX = x;
                    if (y < minY) minY = y;
                    if (y > maxY) maxY = y;

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
        }

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

    public static bool SaveAsCleanWmf(Bitmap bmp, string outputPath, int dpi)
    {
        string tempEmf = outputPath + ".tmp.emf";
        try
        {
            if (File.Exists(tempEmf)) File.Delete(tempEmf);

            int runW = bmp.Width;
            int runH = bmp.Height;

            using (Bitmap refBmp = new Bitmap(1, 1))
            {
                refBmp.SetResolution(dpi, dpi);
                using (Graphics refG = Graphics.FromImage(refBmp))
                {
                    IntPtr hdc = refG.GetHdc();
                    using (Metafile emf = new Metafile(tempEmf, hdc, new RectangleF(0, 0, runW, runH), MetafileFrameUnit.Pixel, EmfType.EmfOnly))
                    {
                        refG.ReleaseHdc(hdc);
                        using (Graphics emfG = Graphics.FromImage(emf))
                        {
                            emfG.CompositingQuality = System.Drawing.Drawing2D.CompositingQuality.HighQuality;
                            emfG.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                            emfG.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                            emfG.Clear(Color.White);
                            emfG.DrawImage(bmp, 0, 0, runW, runH);
                        }
                    }
                }
            }

            using (Metafile savedEmf = new Metafile(tempEmf))
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
                                header[0] = 0xD7; header[1] = 0xCD; header[2] = 0xC6; header[3] = 0x9A; // Aldus Placeable Header
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

                                string dir = Path.GetDirectoryName(outputPath);
                                if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir)) Directory.CreateDirectory(dir);

                                File.WriteAllBytes(outputPath, full);
                                return true;
                            }
                        }
                    }
                    finally
                    {
                        DeleteEnhMetaFile(hEmf);
                    }
                }
            }
        }
        catch
        {
            return false;
        }
        finally
        {
            if (File.Exists(tempEmf))
            {
                try { File.Delete(tempEmf); } catch {}
            }
        }
        return false;
    }

    public static bool SaveImage(Bitmap bmp, string outputPath, string format)
    {
        try
        {
            string dir = Path.GetDirectoryName(outputPath);
            if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir)) Directory.CreateDirectory(dir);

            if (format.Equals("WMF", StringComparison.OrdinalIgnoreCase))
            {
                return SaveAsCleanWmf(bmp, outputPath, 96);
            }
            else if (format.Equals("PNG", StringComparison.OrdinalIgnoreCase))
            {
                bmp.Save(outputPath, ImageFormat.Png);
                return true;
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
                return true;
            }
        }
        catch { return false; }
    }

    public static bool SaveImage(Bitmap bmp, string outputPath, bool asPng)
    {
        return SaveImage(bmp, outputPath, asPng ? "PNG" : "JPG");
    }
}
"@

try {
    Add-Type -TypeDefinition $csharp -ReferencedAssemblies System.Drawing
} catch {}

# --- Load Nexus AI Vision Engine (ONNX Runtime + U-2-Net Neural Segmentation) ---
$global:hasAiVision = $false
try {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    if (-not $scriptRoot) { $scriptRoot = "C:\Users\mandar.k\Documents\antigravity\lively-raman" }
    $aiBinDir = Join-Path $scriptRoot "bin"
    if (-not (Test-Path $aiBinDir)) {
        $aiBinDir = "C:\Users\mandar.k\Documents\antigravity\lively-raman\bin"
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

function Show-Header {
    Write-Host "===============================================================================" -ForegroundColor Cyan
    Write-Host "   NEXUS BACKGROUND REMOVER & SIGNATURE / WMF EXTRACTOR                        " -ForegroundColor Cyan
    Write-Host "===============================================================================" -ForegroundColor Cyan
    Write-Host "  Modes Supported   : Auto-Detect | Signature (Ink) | Photo (Portrait)         " -ForegroundColor Yellow
    Write-Host "  Background Output : Transparent PNG | Pure Solid White | Passport Blue | WMF " -ForegroundColor Yellow
    Write-Host "  WMF Compatibility : Standard Placeable WMF (Crystal Reports Safe, Solid White)" -ForegroundColor Yellow
    Write-Host "===============================================================================" -ForegroundColor Cyan
    Write-Host ""
}

Show-Header

# Interactive File Dialog if no parameter passed
if (-not $InputPath -or -not (Test-Path -LiteralPath $InputPath)) {
    Write-Host "[?] Please select an image or WMF file (signature, person photo, stamp, plan):" -ForegroundColor White
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Select Image or WMF File to Remove Background"
    $dialog.Filter = "Image & Vector Files (*.png;*.jpg;*.jpeg;*.bmp;*.webp;*.tif;*.wmf;*.emf)|*.png;*.jpg;*.jpeg;*.bmp;*.webp;*.tif;*.wmf;*.emf|WMF Vector Files (*.wmf;*.emf)|*.wmf;*.emf|All Files (*.*)|*.*"
    $dialog.InitialDirectory = [Environment]::GetFolderPath("Desktop")
    
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $InputPath = $dialog.FileName
    } else {
        $InputPath = Read-Host "Enter Image / WMF File Path"
        $InputPath = $InputPath.Trim('"').Trim("'")
    }
}

if (-not $InputPath -or -not (Test-Path -LiteralPath $InputPath)) {
    Write-Host "[ERROR] No valid image file provided. Exiting." -ForegroundColor Red
    exit 1
}

# Determine default output path
if (-not $OutputPath) {
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $fileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($InputPath)
    $ext = if ($BgType -eq "WMF") {
        ".wmf"
    } elseif ($BgType -eq "Transparent") {
        ".png"
    } else {
        ".jpg"
    }
    $suffix = if ($Mode -eq "Signature") { "_clean_sign" } else { "_nobg" }
    $OutputPath = Join-Path $desktopPath "${fileNameWithoutExt}${suffix}${ext}"
}

$outFormat = if ($BgType -eq "WMF" -or $OutputPath.EndsWith(".wmf", [System.StringComparison]::OrdinalIgnoreCase)) {
    "WMF"
} elseif ($BgType -eq "Transparent" -or $OutputPath.EndsWith(".png", [System.StringComparison]::OrdinalIgnoreCase)) {
    "PNG"
} else {
    "JPG"
}

$isTrans = ($BgType -eq "Transparent" -and $outFormat -ne "WMF")
$replaceColor = switch ($BgType) {
    "White" { [System.Drawing.Color]::White }
    "WMF"   { [System.Drawing.Color]::White }
    "Blue"  { [System.Drawing.Color]::FromArgb(255, 0, 114, 198) }
    default { [System.Drawing.Color]::White }
}

Write-Host "[*] Processing Image : $InputPath" -ForegroundColor Cyan
Write-Host "[*] Mode Requested   : $Mode" -ForegroundColor Cyan
Write-Host "[*] Output Format    : $outFormat (Bg: $BgType)" -ForegroundColor Cyan
Write-Host "[*] Sensitivity      : $Tolerance%" -ForegroundColor Cyan
Write-Host "[*] Output Path      : $OutputPath" -ForegroundColor Green

try {
    $srcBmp = [BackgroundRemovalEngine]::LoadAnyImage($InputPath)
    $outBmp = $null

    $effectiveMode = $Mode
    if ($effectiveMode -eq "Auto") {
        $isSign = [BackgroundRemovalEngine]::DetectIsSignature($srcBmp)
        $effectiveMode = if ($isSign) { "Signature" } else { "Portrait" }
        Write-Host "[*] AI Auto-Detected: $effectiveMode" -ForegroundColor Yellow
    }

    if ($effectiveMode -eq "Signature") {
        $outBmp = [BackgroundRemovalEngine]::ExtractSignature($srcBmp, $Tolerance, $EnhanceInk.IsPresent, $replaceColor, $isTrans, $AutoCrop.IsPresent)
    } else {
        if ($global:hasAiVision) {
            Write-Host "[*] Engine            : Neural AI Vision Segmentation (U-2-Net ONNX)" -ForegroundColor Green
            $outBmp = [Nexus.AI.AiBackgroundRemover]::RemoveBackground($srcBmp, $replaceColor, $isTrans, $AutoCrop.IsPresent)
        } else {
            Write-Host "[*] Engine            : Geometric Color/Edge Engine" -ForegroundColor Yellow
            $outBmp = [BackgroundRemovalEngine]::RemovePhotoBackground($srcBmp, $Tolerance, $replaceColor, $isTrans)
        }
    }

    $ok = [BackgroundRemovalEngine]::SaveImage($outBmp, $OutputPath, $outFormat)

    $srcBmp.Dispose()
    if ($outBmp) { $outBmp.Dispose() }

    if ($ok -and (Test-Path -LiteralPath $OutputPath)) {
        $outSizeKB = [Math]::Round(((Get-Item -LiteralPath $OutputPath).Length / 1KB), 1)
        Write-Host ""
        Write-Host "===============================================================================" -ForegroundColor Green
        Write-Host " [SUCCESS] Background removed successfully!" -ForegroundColor Green
        Write-Host " File saved: $OutputPath ($outSizeKB KB)" -ForegroundColor Green
        Write-Host "===============================================================================" -ForegroundColor Green
        
        try {
            Start-Process "explorer.exe" -ArgumentList "/select,`"$OutputPath`""
        } catch {}
    } else {
        Write-Host "[ERROR] Could not save output image." -ForegroundColor Red
    }
} catch {
    Write-Host "[ERROR] Processing error: $($_.Exception.Message)" -ForegroundColor Red
}
