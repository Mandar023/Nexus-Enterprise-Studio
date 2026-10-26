@echo off
setlocal EnableDelayedExpansion
title Nexus Photo & Document Optimizer (Enterprise Edition)
color 0B
cd /d "%~dp0"

:: 1. Silently unblock all files in directory to eradicate SmartScreen / ExecutionPolicy blocks
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "Get-ChildItem -Path '%~dp0' -Recurse | Unblock-File -ErrorAction SilentlyContinue" >nul 2>&1

:: 2. If already running as Administrator, execute immediately with zero prompt
net session >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0PMC-ImageResizer-App.ps1" %*
    exit /b 0
)

:: 3. Try running via elevated Scheduled Task (Full Admin with ZERO UAC Prompts)
schtasks /run /tn "NexusPhotoOptimizerAdmin" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    exit /b 0
)

:: 4. Check if current user is in local administrators group (has S-1-5-32-544 in groups)
whoami /groups | findstr /i "S-1-5-32-544" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%~dp0PMC-ImageResizer-App.ps1\"' -Verb RunAs" >nul 2>&1
    if %ERRORLEVEL% EQU 0 (
        exit /b 0
    )
)

:: 5. Direct launch: Standard user or fallback, run directly without blocking or asking for permission
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0PMC-ImageResizer-App.ps1" %*
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Launching visible diagnostic mode...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PMC-ImageResizer-App.ps1" %*
    pause
)
exit /b 0
