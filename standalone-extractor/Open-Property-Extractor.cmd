@echo off
title PMC Property Extractor Launcher
color 0B
cd /d "%~dp0"
echo ===============================================================================
echo            PMC PROPERTY ASSET & WMF PLAN EXTRACTOR v5.5
echo ===============================================================================
echo Launching Extractor Studio...
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0PMC-Property-Extractor.ps1"
if %errorlevel% neq 0 (
    echo.
    echo Notice: Launching in visible mode...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PMC-Property-Extractor.ps1"
    pause
)
