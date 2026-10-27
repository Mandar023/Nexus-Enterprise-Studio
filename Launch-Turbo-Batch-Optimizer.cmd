@echo off
setlocal EnableDelayedExpansion
title Nexus Enterprise Turbo Batch Optimizer (Ultra-Fast 12-Core Multi-Threaded)
color 0A
cd /d "%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -Path '%~dp0' -Recurse | Unblock-File -ErrorAction SilentlyContinue" >nul 2>&1

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Turbo-Batch-Optimizer.ps1" -Interactive %*

if %ERRORLEVEL% NEQ 0 (
    echo.
    pause
)
exit /b 0
