@echo off
setlocal
cd /d "%~dp0"
title Nexus Background Remover ^& Signature Extractor

echo ===============================================================================
echo   NEXUS BACKGROUND REMOVER ^& SIGNATURE EXTRACTOR (PORTABLE)
echo ===============================================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Remove-Background.ps1" %*

echo.
pause
