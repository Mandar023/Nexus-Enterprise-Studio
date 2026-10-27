@echo off
setlocal
cd /d "%~dp0"
title Nexus Optimizer - Upload to GitHub
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Users\mandar.k\Documents\antigravity\lively-raman\Upload-To-GitHub.ps1"
if %errorlevel% neq 0 pause
exit /b %errorlevel%
