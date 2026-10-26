@echo off
title Property Image Resizer (Under 25 KB)
color 0A
echo =======================================================
echo     PMC PROPERTY IMAGE RESIZER (JPG/PNG/ETC)
echo =======================================================
echo.
echo Target Folder: \\192.168.1.22\d\WebApplicationHost\PMCPhotoStorage.org\wwwroot\Files\PropertyImage
echo Excel Source : C:\Users\mandar.k\Downloads\ASWSWSSAAAA\New folder\indi prop.xlsx
echo Target Size  : UNDER 25 KB
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Resize-PropertyImages.ps1"
echo.
pause
