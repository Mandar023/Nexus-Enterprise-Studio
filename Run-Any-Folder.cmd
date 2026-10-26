@echo off
title PMC Image Resizer - Any Folder / Any Excel
color 0A
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Interactive-Resizer.ps1"
echo.
pause
