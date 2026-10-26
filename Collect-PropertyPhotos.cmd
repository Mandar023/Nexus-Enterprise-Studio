@echo off
title Nexus Photo & PlanPhoto (WMF) Extractor
color 0B
echo ===============================================================================
echo      NEXUS PROPERTY PHOTO & PLANPHOTO (WMF) EXTRACTOR (TO DESKTOP)
echo ===============================================================================
echo.
echo Select Extraction Mode:
echo   [1] Property Photos (JPG / Under 25KB) from PropertyImage
echo   [2] PlanPhoto WMF/EMF Vector (Solid White Canvas for Crystal Reports) from PlanPhoto
echo   [3] Both (Photos + WMF PlanPhotos)
echo.
set /p choice="Enter choice (1, 2, or 3) [Default: 1]: "
if "%choice%"=="" set choice=1

if "%choice%"=="2" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Collect-PropertyPhotos.ps1" -Mode "WMF" -WhiteCanvas
) else if "%choice%"=="3" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Collect-PropertyPhotos.ps1" -Mode "Both" -WhiteCanvas
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Collect-PropertyPhotos.ps1" -Mode "Photos"
)

echo.
pause
