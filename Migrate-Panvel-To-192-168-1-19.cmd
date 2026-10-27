@echo off
setlocal
cd /d "%~dp0"
title Panvel MC Photo and Plan Consolidator (To 192.168.1.19)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Migrate-Panvel-To-192-168-1-19.ps1"
if %errorlevel% neq 0 pause
exit /b %errorlevel%
