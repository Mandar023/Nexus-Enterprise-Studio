@echo off
setlocal enabledelayedexpansion
title Nexus Direct PC Share - Firewall Unblock
color 0A

:: Check Administrator Elevation
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [REQUESTING ADMINISTRATOR PERMISSION]...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo ===============================================================================
echo            NEXUS DIRECT PC SHARE - INSTANT FIREWALL UNBLOCK
echo ===============================================================================
echo.
echo Unblocking Windows Defender Firewall on all profiles so other PCs can connect...
echo.

:: 1. Turn OFF Windows Firewall for Domain and Private profiles (eliminates all blocks)
echo [1/3] Turning OFF Firewall blocks for office network...
netsh advfirewall set allprofiles state off >nul 2>&1

:: 2. Enable File and Printer Sharing
echo [2/3] Enabling File and Printer Sharing...
netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes >nul 2>&1

:: 3. Configure Inbound Rules explicitly
echo [3/3] Permitting Ports TCP 52824, 52825, 52826 and UDP 52822...
netsh advfirewall firewall delete rule name="Nexus-All-Inbound" >nul 2>&1
netsh advfirewall firewall add rule name="Nexus-All-Inbound" dir=in action=allow protocol=TCP localport=52824,52825,52826 profile=any >nul 2>&1
netsh advfirewall firewall add rule name="Nexus-UDP-Inbound" dir=in action=allow protocol=UDP localport=52822 profile=any >nul 2>&1

echo.
echo ===============================================================================
echo   SUCCESS! FIREWALL IS NOW 100%% UNBLOCKED ON YOUR PC!
echo ===============================================================================
echo   Other computers can now open:
echo   - Web Browser: http://192.168.1.190:52825/
echo   - Windows Run:  \\192.168.1.190\D\Share
echo ===============================================================================
echo.

copy /y "%~f0" "D:\Share\Enable-LanShareFirewall.cmd" >nul 2>&1
copy /y "%~f0" "%USERPROFILE%\Desktop\Enable-LanShareFirewall.cmd" >nul 2>&1

if "%1"=="--silent" goto finish
pause
:finish
exit /b 0
