@echo off
title PMC SQL Proxy Service
echo.
echo  Starting PMC SQL Proxy Service...
echo  ──────────────────────────────────
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0PMC-SqlProxy-Service.ps1" %*
pause
