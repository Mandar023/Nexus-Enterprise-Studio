@echo off
setlocal EnableDelayedExpansion
title Beyond Compare 5

:: 1. Auto-reset evaluation trial keys so official Beyond Compare 5 never expires
reg delete "HKCU\Software\Scooter Software\Beyond Compare 5" /v "Expired" /f >nul 2>&1
reg delete "HKCU\Software\Scooter Software\Beyond Compare 5" /v "CacheID" /f >nul 2>&1
reg delete "HKCU\Software\Scooter Software\Beyond Compare 4" /v "Expired" /f >nul 2>&1
reg delete "HKCU\Software\Scooter Software\Beyond Compare 4" /v "CacheID" /f >nul 2>&1

:: 2. Find and launch the official Beyond Compare 5 64-bit binary
set "BC_EXE=C:\Program Files\Beyond Compare 5\BCompare.exe"
if exist "%BC_EXE%" goto :LAUNCH

set "BC_EXE=%~dp0Beyond Compare 5\BCompare.exe"
if exist "%BC_EXE%" goto :LAUNCH

set "BC_EXE=C:\Program Files (x86)\Beyond Compare 5\BCompare.exe"
if exist "%BC_EXE%" goto :LAUNCH

set "BC_EXE=%LOCALAPPDATA%\Programs\Beyond Compare 5\BCompare.exe"
if exist "%BC_EXE%" goto :LAUNCH

set "BC_EXE=C:\Program Files\Beyond Compare 4\BCompare.exe"
if exist "%BC_EXE%" goto :LAUNCH

:: 3. Fallback: If no native binary is found, run the PowerShell diff studio
set "PS_SCRIPT=%~dp0Beyond-Compare-5.ps1"
if not exist "%PS_SCRIPT%" set "PS_SCRIPT=C:\Users\mandar.k\Nexus-Photo-Optimizer-Portable\Beyond-Compare-5.ps1"
if not exist "%PS_SCRIPT%" set "PS_SCRIPT=C:\Users\mandar.k\Documents\antigravity\lively-raman\Beyond-Compare-5.ps1"
if exist "%PS_SCRIPT%" (
    start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PS_SCRIPT%" %*
    exit /b 0
)

start "" "C:\Program Files\Beyond Compare 5\BCompare.exe" %*
exit /b 0

:LAUNCH
start "" "%BC_EXE%" %*
exit /b 0
