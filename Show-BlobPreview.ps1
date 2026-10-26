<#
.SYNOPSIS
    Decodes and displays a live visual preview of any BLOB Image or WMF vector file.
    Supports SQL Server Hex strings (0x...), Base64 strings, raw byte arrays, and binary files.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string] $BlobData = "",

    [string] $FilePath = "",
    [switch] $FromClipboard,
    [string] $SaveTo   = ""
)

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing, System.Windows.Forms

function Convert-BlobToBytes {
    param([object]$inputData)
    $bytes = $null

    if ($inputData -is [byte[]]) {
        return $inputData
    }

    $str = [string]$inputData
    if ([string]::IsNullOrWhiteSpace($str)) { return $null }
    $str = $str.Trim()

    if (Test-Path $str -PathType Leaf) {
        return [System.IO.File]::ReadAllBytes($str)
    }

    # SQL Hex string (0x...) or pure hex
    if ($str.StartsWith("0x", [System.StringComparison]::OrdinalIgnoreCase) -or ($str -match '^[0-9A-Fa-f]{8,}$' -and $str.Length % 2 -eq 0)) {
        $clean = $str
        if ($clean.StartsWith("0x", [System.StringComparison]::OrdinalIgnoreCase)) { $clean = $clean.Substring(2) }
        $clean = $clean -replace '[\s,\r\n]+', ''
        $len = [int]($clean.Length / 2)
        $bytes = New-Object byte[] $len
        for ($i = 0; $i -lt $len; $i++) {
            $bytes[$i] = [Convert]::ToByte($clean.Substring($i * 2, 2), 16)
        }
        return $bytes
    }

    # Base64
    if ($str.StartsWith("data:") -or $str.Length % 4 -eq 0) {
        try {
            $clean = $str
            if ($clean -match 'data:image\/[^;]+;base64,(.+)') { $clean = $Matches[1] }
            $clean = $clean -replace '[\s\r\n]+', ''
            return [Convert]::FromBase64String($clean)
        } catch {}
    }

    return $null
}

# Resolve input data
$rawInput = $BlobData
if ($FromClipboard) {
    if ([System.Windows.Forms.Clipboard]::ContainsText()) {
        $rawInput = [System.Windows.Forms.Clipboard]::GetText()
    }
} elseif ($FilePath -and (Test-Path $FilePath)) {
    $rawInput = $FilePath
}

if (-not $rawInput) {
    Write-Host "No BLOB data provided. Use -BlobData, -FilePath, or -FromClipboard." -ForegroundColor Yellow
    exit 1
}

$bytes = Convert-BlobToBytes $rawInput
if (-not $bytes -or $bytes.Length -eq 0) {
    Write-Host "Error: Failed to decode BLOB data into valid binary bytes." -ForegroundColor Red
    exit 1
}

# Detect Format
$sig = ($bytes[0..[Math]::Min(7, $bytes.Length-1)] | ForEach-Object { $_.ToString("X2") }) -join " "
$formatName = "Unknown Format"
$ext = ".bin"

if ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xD8) { $formatName = "JPEG / JPG"; $ext = ".jpg" }
elseif ($bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47) { $formatName = "PNG Image"; $ext = ".png" }
elseif ($bytes[0] -eq 0xD7 -and $bytes[1] -eq 0xCD -and $bytes[2] -eq 0xC6 -and $bytes[3] -eq 0x9A) { $formatName = "WMF (Placeable Metafile)"; $ext = ".wmf" }
elseif ($bytes[0] -eq 0x42 -and $bytes[1] -eq 0x4D) { $formatName = "BMP (Bitmap)"; $ext = ".bmp" }
elseif ($bytes[0] -eq 0x47 -and $bytes[1] -eq 0x49 -and $bytes[2] -eq 0x46) { $formatName = "GIF"; $ext = ".gif" }
elseif (($bytes[0] -eq 0x49 -and $bytes[1] -eq 0x49) -or ($bytes[0] -eq 0x4D -and $bytes[1] -eq 0x4D)) { $formatName = "TIFF"; $ext = ".tif" }

$ms = New-Object System.IO.MemoryStream($bytes, 0, $bytes.Length)
$img = $null
$width = 0; $height = 0; $dpi = 96
try {
    $img = [System.Drawing.Image]::FromStream($ms)
    $width = $img.Width
    $height = $img.Height
    if ($width -le 0) { $width = 700 }
    if ($height -le 0) { $height = 700 }
    $dpi = [Math]::Max(72, [int][Math]::Round($img.HorizontalResolution))
} catch {
    Write-Host "Warning: Could not read image dimensions: $($_.Exception.Message)" -ForegroundColor Yellow
}

$sizeKb = [Math]::Round($bytes.Length / 1KB, 2)

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "             BLOB IMAGE DECODE RESULT                  " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host " Format       : $formatName" -ForegroundColor Green
Write-Host " Dimensions   : $width x $height px" -ForegroundColor White
Write-Host " Resolution   : $dpi DPI" -ForegroundColor White
Write-Host " File Size    : $sizeKb KB ($($bytes.Length) bytes)" -ForegroundColor Yellow
Write-Host " Hex Header   : $sig" -ForegroundColor DarkCyan
Write-Host "=======================================================" -ForegroundColor Cyan

if ($SaveTo) {
    [System.IO.File]::WriteAllBytes($SaveTo, $bytes)
    Write-Host "Saved decoded image to: $SaveTo" -ForegroundColor Green
    exit 0
}

# --- WPF Preview Window with White Canvas ---
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="BLOB Image / WMF Previewer" 
        Height="680" Width="840" 
        WindowStartupLocation="CenterScreen" 
        Background="#0B1120" FontFamily="Segoe UI">
    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Border Grid.Row="0" Background="#131F37" CornerRadius="8" Padding="14" Margin="0,0,0,12" BorderBrush="#253555" BorderThickness="1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0">
                    <TextBlock Text="BLOB Image Preview" FontSize="18" FontWeight="Bold" Foreground="#38BDF8"/>
                    <TextBlock Text="$formatName  |  $width x $height px  |  $sizeKb KB  |  $dpi DPI" FontSize="12" Foreground="#94A3B8" Margin="0,3,0,0"/>
                </StackPanel>
                <Border Grid.Column="1" Background="#0284C7" CornerRadius="6" Padding="10,4" VerticalAlignment="Center">
                    <TextBlock Text="$sizeKb KB" FontWeight="Bold" Foreground="White" FontSize="12"/>
                </Border>
            </Grid>
        </Border>

        <!-- Image Container with White Canvas -->
        <Border Grid.Row="1" Background="#FFFFFF" CornerRadius="8" Padding="10" Margin="0,0,0,12" BorderBrush="#CBD5E1" BorderThickness="2">
            <ScrollViewer HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto">
                <Image x:Name="imgPreview" Stretch="Uniform" RenderOptions.BitmapScalingMode="HighQuality"/>
            </ScrollViewer>
        </Border>

        <!-- Action Controls -->
        <Grid Grid.Row="2">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>

            <TextBlock Grid.Column="0" Text="Header: $sig" VerticalAlignment="Center" Foreground="#64748B" FontSize="11" FontFamily="Consolas"/>
            <Button x:Name="btnCopyHex" Grid.Column="1" Content="Copy SQL Hex" Background="#334155" Foreground="White" FontWeight="SemiBold" Padding="16,8" Margin="0,0,10,0" BorderThickness="0" Cursor="Hand"/>
            <Button x:Name="btnSaveAs" Grid.Column="2" Content="Save As Image / WMF..." Background="#059669" Foreground="White" FontWeight="Bold" Padding="18,8" BorderThickness="0" Cursor="Hand"/>
        </Grid>
    </Grid>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

$imgPreview = $window.FindName("imgPreview")
$btnCopyHex  = $window.FindName("btnCopyHex")
$btnSaveAs   = $window.FindName("btnSaveAs")

# Convert bytes to Pure White Background WPF BitmapImage
$pngMs = New-Object System.IO.MemoryStream
$whiteBmp = $null
$g = $null

if ($img) {
    $whiteBmp = New-Object System.Drawing.Bitmap($width, $height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $whiteBmp.SetResolution($dpi, $dpi)
    $g = [System.Drawing.Graphics]::FromImage($whiteBmp)
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::White)
    $g.DrawImage($img, 0, 0, $width, $height)

    $whiteBmp.Save($pngMs, [System.Drawing.Imaging.ImageFormat]::Png)
    $pngMs.Position = 0

    $bmpImg = New-Object System.Windows.Media.Imaging.BitmapImage
    $bmpImg.BeginInit()
    $bmpImg.StreamSource = $pngMs
    $bmpImg.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bmpImg.EndInit()
    $bmpImg.Freeze()

    $imgPreview.Source = $bmpImg
}

$btnCopyHex.Add_Click({
    $hexOutput = "0x" + (($bytes | ForEach-Object { $_.ToString("X2") }) -join "")
    [System.Windows.Forms.Clipboard]::SetText($hexOutput)
    [System.Windows.MessageBox]::Show("SQL Hex string copied to clipboard! (Length: $($hexOutput.Length) chars)", "Copied", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
})

$btnSaveAs.Add_Click({
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Title = "Save Decoded BLOB Image"
    $sfd.Filter = "Detected Format (*$ext)|*$ext|All Files (*.*)|*.*"
    $sfd.FileName = "Decoded_Image$ext"
    if ($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        [System.IO.File]::WriteAllBytes($sfd.FileName, $bytes)
        [System.Windows.MessageBox]::Show("Image saved successfully to:`n$($sfd.FileName)", "Saved", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
})

$window.ShowDialog() | Out-Null
if ($g) { $g.Dispose() }
if ($whiteBmp) { $whiteBmp.Dispose() }
if ($img) { $img.Dispose() }
if ($ms) { $ms.Dispose() }
if ($pngMs) { $pngMs.Dispose() }
