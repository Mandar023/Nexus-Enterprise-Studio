@echo off
title Govt Exam Photo and PDF Resizer
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PMC-ImageResizer-App.ps1"
pause
