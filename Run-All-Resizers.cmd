@echo off
title PMC Master Image Resizer
color 0E
:MENU
cls
echo =======================================================
echo              PMC IMAGE RESIZER UTILITY
echo =======================================================
echo.
echo  [1] Resize Property Images (.JPG, .PNG, etc.)
echo  [2] Resize PlanPhoto WMF Files (.WMF)
echo  [3] Run BOTH (Property Images + PlanPhoto WMF)
echo  [4] Exit
echo.
echo =======================================================
set /p choice="Enter your choice (1-4): "

if "%choice%"=="1" goto RUN_PROP
if "%choice%"=="2" goto RUN_WMF
if "%choice%"=="3" goto RUN_BOTH
if "%choice%"=="4" goto EXIT
goto MENU

:RUN_PROP
cls
echo Starting Property Images Resizer...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Resize-PropertyImages.ps1"
echo.
pause
goto MENU

:RUN_WMF
cls
echo Starting PlanPhoto WMF Resizer...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Resize-PlanPhotoWMF.ps1"
echo.
pause
goto MENU

:RUN_BOTH
cls
echo =======================================================
echo STEP 1/2: Processing Property Images (.JPG, .PNG)
echo =======================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Resize-PropertyImages.ps1"
echo.
echo =======================================================
echo STEP 2/2: Processing PlanPhoto (.WMF)
echo =======================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Resize-PlanPhotoWMF.ps1"
echo.
echo All operations complete!
pause
goto MENU

:EXIT
exit
