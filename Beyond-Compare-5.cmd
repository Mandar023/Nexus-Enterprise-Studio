@echo off
setlocal EnableDelayedExpansion
title Beyond Compare 5
cd /d "%~dp0"

set "PS_SCRIPT=%~dp0Beyond-Compare-5.ps1"
if not exist "%PS_SCRIPT%" set "PS_SCRIPT=%~dp0Nexus-Photo-Optimizer-Portable\Beyond-Compare-5.ps1"
if not exist "%PS_SCRIPT%" set "PS_SCRIPT=C:\Users\mandar.k\Nexus-Photo-Optimizer-Portable\Beyond-Compare-5.ps1"
if not exist "%PS_SCRIPT%" set "PS_SCRIPT=C:\Users\mandar.k\Documents\antigravity\lively-raman\Beyond-Compare-5.ps1"

:: 1. Silently unblock all files in directory to eradicate SmartScreen / ExecutionPolicy blocks
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "Get-ChildItem -Path '%~dp0' -Recurse | Unblock-File -ErrorAction SilentlyContinue" >nul 2>&1

:: 2. If already running as Administrator, execute immediately with zero prompt
net session >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PS_SCRIPT%" %*
    exit /b 0
)

:: 3. Try running via elevated Scheduled Task (Full Admin with ZERO UAC Prompts)
schtasks /run /tn "BeyondCompare5Admin" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    exit /b 0
)

:: 4. Check if current user is in local administrators group (has S-1-5-32-544 in groups)
whoami /groups | findstr /i "S-1-5-32-544" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%PS_SCRIPT%\"' -Verb RunAs" >nul 2>&1
    if %ERRORLEVEL% EQU 0 (
        exit /b 0
    )
)

:: 5. Direct launch: Standard user or fallback, run directly without blocking or asking for permission
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PS_SCRIPT%" %*
exit /b 0
