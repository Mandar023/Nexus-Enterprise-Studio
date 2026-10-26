<#
.SYNOPSIS
    Interactive Launcher for PMC Property Image & PlanPhoto WMF Resizers.
    Allows selecting ANY folder and ANY Excel file using GUI browser or manual input.
#>

Add-Type -AssemblyName System.Windows.Forms

function Select-Folder([string]$title, [string]$defaultPath) {
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = $title
    $fbd.SelectedPath = $defaultPath
    $fbd.ShowNewFolderButton = $false
    if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $fbd.SelectedPath
    }
    return $defaultPath
}

function Select-File([string]$title, [string]$filter, [string]$defaultPath) {
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Title = $title
    $ofd.Filter = $filter
    if ($defaultPath -and (Test-Path $defaultPath)) {
        $ofd.InitialDirectory = [System.IO.Path]::GetDirectoryName($defaultPath)
    }
    if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $ofd.FileName
    }
    return $defaultPath
}

Clear-Host
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "          PMC IMAGE RESIZER & OPTIMIZER                " -ForegroundColor Cyan
Write-Host "             [SUPPORT FOR ANY FOLDER]                  " -ForegroundColor Yellow
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Select what you want to process:" -ForegroundColor White
Write-Host "  [1] Property Photos (.JPG, .PNG, .BMP, etc.)"
Write-Host "  [2] PlanPhoto WMF Files (.WMF)"
Write-Host "  [3] Exit"
Write-Host ""

$mode = Read-Host "Enter option (1-3)"

if ($mode -ne "1" -and $mode -ne "2") {
    Write-Host "Exiting..."
    exit 0
}

# Defaults
$defaultImgFolder = "\\192.168.1.22\d\WebApplicationHost\PMCPhotoStorage.org\wwwroot\Files\PropertyImage"
$defaultWmfFolder = "\\192.168.1.22\d\WebApplicationHost\PMCPhotoStorage.org\wwwroot\Files\PlanPhoto"
$defaultExcel = "C:\Users\mandar.k\Downloads\ASWSWSSAAAA\New folder\indi prop.xlsx"

$currentFolder = if ($mode -eq "1") { $defaultImgFolder } else { $defaultWmfFolder }

Write-Host "`n-------------------------------------------------------" -ForegroundColor Cyan
Write-Host "STEP 1: SELECT IMAGE FOLDER" -ForegroundColor Yellow
Write-Host "Current default: $currentFolder"
Write-Host "  [1] Use default server folder"
Write-Host "  [2] Browse to select ANY other folder (GUI Popup)"
Write-Host "  [3] Type or Paste custom folder path"
$folderChoice = Read-Host "Choose (1-3)"

$targetFolder = $currentFolder
if ($folderChoice -eq "2") {
    $targetFolder = Select-Folder "Select the folder containing images to resize" $currentFolder
} elseif ($folderChoice -eq "3") {
    $inputFolder = Read-Host "Paste folder path"
    if ($inputFolder -and (Test-Path $inputFolder)) {
        $targetFolder = $inputFolder.Trim('"', "'")
    } else {
        Write-Host "Path not found or empty. Using default." -ForegroundColor Yellow
    }
}

Write-Host "Selected Folder: $targetFolder" -ForegroundColor Green

Write-Host "`n-------------------------------------------------------" -ForegroundColor Cyan
Write-Host "STEP 2: SELECT EXCEL FILE" -ForegroundColor Yellow
Write-Host "Current default: $defaultExcel"
Write-Host "  [1] Use default Excel file"
Write-Host "  [2] Browse to select ANY other Excel file (GUI Popup)"
Write-Host "  [3] Type or Paste custom Excel file path"
$excelChoice = Read-Host "Choose (1-3)"

$targetExcel = $defaultExcel
if ($excelChoice -eq "2") {
    $targetExcel = Select-File "Select Excel file (.xlsx)" "Excel Files (*.xlsx;*.xls)|*.xlsx;*.xls" $defaultExcel
} elseif ($excelChoice -eq "3") {
    $inputXl = Read-Host "Paste Excel path"
    if ($inputXl -and (Test-Path $inputXl)) {
        $targetExcel = $inputXl.Trim('"', "'")
    } else {
        Write-Host "File not found or empty. Using default." -ForegroundColor Yellow
    }
}

Write-Host "Selected Excel: $targetExcel" -ForegroundColor Green

Write-Host "`n-------------------------------------------------------" -ForegroundColor Cyan
Write-Host "STEP 3: MAX FILE SIZE (KB)" -ForegroundColor Yellow
$maxKbInput = Read-Host "Enter Max KB (Press Enter for default: 25)"
$targetMaxKB = 25
if ($maxKbInput -match '^\d+$') {
    $targetMaxKB = [int]$maxKbInput
}

Write-Host "`n=======================================================" -ForegroundColor Green
Write-Host "STARTING EXECUTION WITH YOUR SETTINGS:" -ForegroundColor Green
Write-Host "  Mode         : $(if ($mode -eq '1') {'Property Images'} else {'PlanPhoto WMF'})"
Write-Host "  Target Folder: $targetFolder"
Write-Host "  Excel File   : $targetExcel"
Write-Host "  Max File Size: $targetMaxKB KB"
Write-Host "=======================================================" -ForegroundColor Green
Write-Host ""

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = "C:\Users\mandar.k\Documents\antigravity\lively-raman" }

if ($mode -eq "1") {
    $scriptPath = Join-Path $scriptDir "Resize-PropertyImages.ps1"
    & $scriptPath -TargetFolder $targetFolder -ExcelPath $targetExcel -MaxKB $targetMaxKB
} else {
    $scriptPath = Join-Path $scriptDir "Resize-PlanPhotoWMF.ps1"
    & $scriptPath -TargetFolder $targetFolder -ExcelPath $targetExcel -MaxKB $targetMaxKB
}
