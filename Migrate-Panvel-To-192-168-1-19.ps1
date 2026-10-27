# ==============================================================================
# PANVEL MUNICIPAL CORPORATION - MULTI-SERVER PHOTO & PLAN CONSOLIDATOR
# Consolidates whole images and plans from \\192.168.1.11 (Wards) and
# \\192.168.1.22 into Target \\192.168.1.19 with automated common-file ignore.
# ==============================================================================

[Console]::Title = "Panvel MC - Multi-Server Consolidator to 192.168.1.19"
Clear-Host

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  PANVEL MC MULTI-SERVER PHOTO & PLAN CONSOLIDATOR" -ForegroundColor Yellow
Write-Host "  Target Server : \\192.168.1.19 (Tabcollection.Panvelmc.org\Files)" -ForegroundColor Green
Write-Host "  Source 1      : \\192.168.1.11\d\Images\NTIS_4030 (Ward Folders)" -ForegroundColor White
Write-Host "  Source 2      : \\192.168.1.22\d\WebApplicationHost\PMCPhotoStorage.org" -ForegroundColor White
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""

$targetImgDir  = "\\192.168.1.19\d\NewWebApps\Tabcollection.Panvelmc.org\Files\PropertyImage"
$targetPlanDir = "\\192.168.1.19\d\NewWebApps\Tabcollection.Panvelmc.org\Files\PlanPhoto"

$src11WardRoot = "\\192.168.1.11\d\Images\NTIS_4030"
$src22ImgDir   = "\\192.168.1.22\d\WebApplicationHost\PMCPhotoStorage.org\wwwroot\Files\PropertyImage"
$src22PlanDir  = "\\192.168.1.22\d\WebApplicationHost\PMCPhotoStorage.org\wwwroot\Files\PlanPhoto"

Write-Host "Select Migration Mode:" -ForegroundColor Yellow
Write-Host "  1. FULL MIGRATION: Both Whole Images & Plans (Consolidate All to 19)" -ForegroundColor Green
Write-Host "  2. WHOLE IMAGES ONLY: Property Photos -> PropertyImage" -ForegroundColor Cyan
Write-Host "  3. PLANS ONLY: All Plan Drawings & WMFs -> PlanPhoto" -ForegroundColor Magenta
Write-Host "  4. AUDIT / DRY-RUN: Scan & Compare Only (No copying)" -ForegroundColor White
Write-Host "  Q. Quit" -ForegroundColor DarkGray
Write-Host ""
$choice = Read-Host "Enter Choice [1/2/3/4/Q] (Default: 1)"
if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1" }
if ($choice -match '(?i)q') { exit 0 }

$migratePhotos = ($choice -eq "1" -or $choice -eq "2" -or $choice -eq "4")
$migratePlans  = ($choice -eq "1" -or $choice -eq "3" -or $choice -eq "4")
$isDryRun      = ($choice -eq "4")

Write-Host "`n[STEP 1] Testing Connectivity to Target and Sources..." -ForegroundColor Yellow
$tgtImgReachable = Test-Path -LiteralPath $targetImgDir
$tgtPlanReachable = Test-Path -LiteralPath $targetPlanDir
$src11Reachable = Test-Path -LiteralPath $src11WardRoot
$src22ImgReachable = Test-Path -LiteralPath $src22ImgDir
$src22PlanReachable = Test-Path -LiteralPath $src22PlanDir

Write-Host "  Target 19 Images : $(if ($tgtImgReachable) {'CONNECTED'} else {'WILL CREATE / INACCESSIBLE'})" -ForegroundColor $(if ($tgtImgReachable) {'Green'} else {'Yellow'})
Write-Host "  Target 19 Plans  : $(if ($tgtPlanReachable) {'CONNECTED'} else {'WILL CREATE / INACCESSIBLE'})" -ForegroundColor $(if ($tgtPlanReachable) {'Green'} else {'Yellow'})
Write-Host "  Source 11 Wards  : $(if ($src11Reachable) {'CONNECTED'} else {'INACCESSIBLE'})" -ForegroundColor $(if ($src11Reachable) {'Green'} else {'Red'})
Write-Host "  Source 22 Images : $(if ($src22ImgReachable) {'CONNECTED'} else {'INACCESSIBLE'})" -ForegroundColor $(if ($src22ImgReachable) {'Green'} else {'Red'})
Write-Host "  Source 22 Plans  : $(if ($src22PlanReachable) {'CONNECTED'} else {'INACCESSIBLE'})" -ForegroundColor $(if ($src22PlanReachable) {'Green'} else {'Red'})

# Index Existing Target Files for Instant Deduplication
Write-Host "`n[STEP 2] Indexing Target \\192.168.1.19 Existing Files for Deduplication..." -ForegroundColor Yellow
$existingImages = [System.Collections.Generic.Dictionary[string, long]]::new([System.StringComparer]::OrdinalIgnoreCase)
$existingPlans  = [System.Collections.Generic.Dictionary[string, long]]::new([System.StringComparer]::OrdinalIgnoreCase)

if ($tgtImgReachable) {
    try {
        foreach ($f in [System.IO.Directory]::GetFiles($targetImgDir, "*.*")) {
            $existingImages[[System.IO.Path]::GetFileName($f)] = (Get-Item -LiteralPath $f).Length
        }
    } catch {}
}
if ($tgtPlanReachable) {
    try {
        foreach ($f in [System.IO.Directory]::GetFiles($targetPlanDir, "*.*")) {
            $existingPlans[[System.IO.Path]::GetFileName($f)] = (Get-Item -LiteralPath $f).Length
        }
    } catch {}
}
Write-Host "  Existing on Target 19 -> Images: $($existingImages.Count), Plans: $($existingPlans.Count)" -ForegroundColor Cyan

# Extensions
$imgExts  = @('.jpg', '.jpeg', '.png', '.bmp', '.webp', '.tif', '.tiff')
$planExts = @('.wmf', '.emf', '.jpg', '.jpeg', '.png', '.bmp', '.tif', '.tiff', '.webp', '.pdf', '.dwg', '.dxf', '.svg')

$commonImagesIgnored = [System.Collections.Generic.List[string]]::new()
$commonPlansIgnored  = [System.Collections.Generic.List[string]]::new()
$newImagesToTransfer = [System.Collections.Generic.List[PSCustomObject]]::new()
$newPlansToTransfer  = [System.Collections.Generic.List[PSCustomObject]]::new()
$totalScanned = ($existingImages.Count + $existingPlans.Count)

# Scan Source 1: 192.168.1.11 Wards
if ($src11Reachable) {
    Write-Host "`n[STEP 3A] Scanning Source 11 Wards ($src11WardRoot)..." -ForegroundColor Yellow
    $q = [System.Collections.Generic.Queue[string]]::new()
    $q.Enqueue($src11WardRoot)

    while ($q.Count -gt 0) {
        $curr = $q.Dequeue()
        try {
            $dirName = [System.IO.Path]::GetFileName($curr)
            $isPhotoFolder = ($dirName -match '(?i)^(photo|photos|propertyimage|propimage)$')
            $isPlanFolder  = ($dirName -match '(?i)^(plan|plans|planphoto)$')

            if ($isPhotoFolder) {
                if ($migratePhotos) {
                    foreach ($fl in [System.IO.Directory]::GetFiles($curr, "*.*")) {
                        $totalScanned++
                        $ext = [System.IO.Path]::GetExtension($fl).ToLower()
                        if ($imgExts -contains $ext) {
                            $fn = [System.IO.Path]::GetFileName($fl)
                            if ($existingImages.ContainsKey($fn)) {
                                $commonImagesIgnored.Add($fn)
                            } else {
                                $newImagesToTransfer.Add([PSCustomObject]@{ Source = $fl; FileName = $fn; Category = "Image"; Origin = "192.168.1.11" })
                                $existingImages[$fn] = 1
                            }
                        }
                    }
                }
            } elseif ($isPlanFolder) {
                if ($migratePlans) {
                    foreach ($fl in [System.IO.Directory]::GetFiles($curr, "*.*")) {
                        $totalScanned++
                        $ext = [System.IO.Path]::GetExtension($fl).ToLower()
                        if ($planExts -contains $ext) {
                            $fn = [System.IO.Path]::GetFileName($fl)
                            if ($existingPlans.ContainsKey($fn)) {
                                $commonPlansIgnored.Add($fn)
                            } else {
                                $newPlansToTransfer.Add([PSCustomObject]@{ Source = $fl; FileName = $fn; Category = "Plan"; Origin = "192.168.1.11" })
                                $existingPlans[$fn] = 1
                            }
                        }
                    }
                }
            }

            foreach ($sd in [System.IO.Directory]::GetDirectories($curr)) {
                $sName = [System.IO.Path]::GetFileName($sd)
                if ($sName -notmatch '(?i)backup' -and -not $sName.StartsWith('.')) {
                    $q.Enqueue($sd)
                }
            }
        } catch {}
    }
}

# Scan Source 2: 192.168.1.22 Images
if ($src22ImgReachable -and $migratePhotos) {
    Write-Host "`n[STEP 3B] Scanning Source 22 Photos ($src22ImgDir)..." -ForegroundColor Yellow
    try {
        foreach ($fl in [System.IO.Directory]::GetFiles($src22ImgDir, "*.*")) {
            $totalScanned++
            $ext = [System.IO.Path]::GetExtension($fl).ToLower()
            if ($imgExts -contains $ext) {
                $fn = [System.IO.Path]::GetFileName($fl)
                if ($existingImages.ContainsKey($fn)) {
                    $commonImagesIgnored.Add($fn)
                } else {
                    $newImagesToTransfer.Add([PSCustomObject]@{ Source = $fl; FileName = $fn; Category = "Image"; Origin = "192.168.1.22" })
                    $existingImages[$fn] = 1
                }
            }
        }
    } catch {}
}

# Scan Source 2: 192.168.1.22 Plans
if ($src22PlanReachable -and $migratePlans) {
    Write-Host "`n[STEP 3C] Scanning Source 22 Plans ($src22PlanDir)..." -ForegroundColor Yellow
    try {
        foreach ($fl in [System.IO.Directory]::GetFiles($src22PlanDir, "*.*")) {
            $totalScanned++
            $ext = [System.IO.Path]::GetExtension($fl).ToLower()
            if ($planExts -contains $ext) {
                $fn = [System.IO.Path]::GetFileName($fl)
                if ($existingPlans.ContainsKey($fn)) {
                    $commonPlansIgnored.Add($fn)
                } else {
                    $newPlansToTransfer.Add([PSCustomObject]@{ Source = $fl; FileName = $fn; Category = "Plan"; Origin = "192.168.1.22" })
                    $existingPlans[$fn] = 1
                }
            }
        }
    } catch {}
}

Write-Host "`n======================================================================" -ForegroundColor Cyan
Write-Host "  AUDIT & COMPARISON SUMMARY" -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  Total Files Scanned      : $totalScanned" -ForegroundColor White
Write-Host "  Common Images Ignored    : $($commonImagesIgnored.Count)" -ForegroundColor DarkGray
Write-Host "  Common Plans Ignored     : $($commonPlansIgnored.Count)" -ForegroundColor DarkGray
Write-Host "  Total Common Skipped     : $($commonImagesIgnored.Count + $commonPlansIgnored.Count)" -ForegroundColor Yellow
Write-Host "  New Images to Transfer   : $($newImagesToTransfer.Count) -> $targetImgDir" -ForegroundColor Green
Write-Host "  New Plans to Transfer    : $($newPlansToTransfer.Count) -> $targetPlanDir" -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Cyan

$totalToTransfer = $newImagesToTransfer.Count + $newPlansToTransfer.Count

if ($isDryRun) {
    Write-Host "`nDry-Run Audit Complete! No files were copied." -ForegroundColor Green
    Read-Host "`nPress Enter to exit..."
    exit 0
}

if ($totalToTransfer -eq 0) {
    Write-Host "`nTarget Server \\192.168.1.19 is already 100% up to date!" -ForegroundColor Green
    Write-Host "Zero new files need to be copied. All files are already common." -ForegroundColor White
    Read-Host "`nPress Enter to exit..."
    exit 0
}

Write-Host "`nReady to migrate $totalToTransfer new files to \\192.168.1.19." -ForegroundColor Yellow
$confirm = Read-Host "Proceed with file transfer? [Y/N] (Default: Y)"
if ($confirm -match '(?i)n') { exit 0 }

# Ensure Target Folders Exist
if (-not (Test-Path -LiteralPath $targetImgDir))  { New-Item -ItemType Directory -Path $targetImgDir -Force | Out-Null }
if (-not (Test-Path -LiteralPath $targetPlanDir)) { New-Item -ItemType Directory -Path $targetPlanDir -Force | Out-Null }

$copiedImgs = 0
$copiedPlans = 0
$currIdx = 0

Write-Host "`n[STEP 4] Transferring Files to \\192.168.1.19..." -ForegroundColor Yellow

# Copy Images
foreach ($im in $newImagesToTransfer) {
    $currIdx++
    $dest = Join-Path $targetImgDir $im.FileName
    try {
        [System.IO.File]::Copy($im.Source, $dest, $true)
        $copiedImgs++
        Write-Host "[$currIdx/$totalToTransfer] Copied Image: $($im.FileName) from $($im.Origin)" -ForegroundColor Cyan
    } catch {
        Write-Host "[$currIdx/$totalToTransfer] ERROR copying image $($im.FileName): $_" -ForegroundColor Red
    }
}

# Copy Plans
foreach ($pl in $newPlansToTransfer) {
    $currIdx++
    $dest = Join-Path $targetPlanDir $pl.FileName
    try {
        [System.IO.File]::Copy($pl.Source, $dest, $true)
        $copiedPlans++
        Write-Host "[$currIdx/$totalToTransfer] Copied Plan : $($pl.FileName) from $($pl.Origin)" -ForegroundColor Magenta
    } catch {
        Write-Host "[$currIdx/$totalToTransfer] ERROR copying plan $($pl.FileName): $_" -ForegroundColor Red
    }
}

Write-Host "`n======================================================================" -ForegroundColor Green
Write-Host "  MIGRATION TO \\192.168.1.19 COMPLETED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Green
Write-Host "  New Images Migrated : $copiedImgs" -ForegroundColor White
Write-Host "  New Plans Migrated  : $copiedPlans" -ForegroundColor White
Write-Host "  Total Files Copied  : $($copiedImgs + $copiedPlans)" -ForegroundColor Green
Write-Host "  Common Skipped      : $($commonImagesIgnored.Count + $commonPlansIgnored.Count)" -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor Green

Read-Host "`nPress Enter to exit..."
