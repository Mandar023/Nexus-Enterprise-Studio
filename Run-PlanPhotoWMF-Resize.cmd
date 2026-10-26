@echo off
title PlanPhoto WMF Resizer (Under 25 KB)
color 0B
echo =======================================================
echo     PMC PLANPHOTO WMF RESIZER & OPTIMIZER
echo =======================================================
echo.
echo Target Folder: \\192.168.1.22\d\WebApplicationHost\PMCPhotoStorage.org\wwwroot\Files\PlanPhoto
echo Excel Source : C:\Users\mandar.k\Downloads\ASWSWSSAAAA\New folder\indi prop.xlsx
echo Target Size  : UNDER 25 KB
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Resize-PlanPhotoWMF.ps1"
echo.
pause
