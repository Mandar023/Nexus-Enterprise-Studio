@echo off
title Nexus Direct PC Share - Firewall Configuration
color 0A
echo ===============================================================================
echo            NEXUS DIRECT PC SHARE - FIREWALL CONFIGURATION
echo ===============================================================================
echo.
echo Adding Windows Firewall rules for Direct LAN File Sharing...
echo Ports: TCP 52824 (Direct Transfer), TCP 52826 (Web Share), UDP 52822 (Discovery)
echo.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [REQUESTING ADMINISTRATOR PERMISSION]...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

netsh advfirewall firewall delete rule name="Nexus Direct PC Share TCP" >nul 2>&1
netsh advfirewall firewall delete rule name="Nexus Direct PC Share UDP" >nul 2>&1

netsh advfirewall firewall add rule name="Nexus Direct PC Share TCP" dir=in action=allow protocol=TCP localport=52824,52826 profile=any
netsh advfirewall firewall add rule name="Nexus Direct PC Share UDP" dir=in action=allow protocol=UDP localport=52822 profile=any

echo.
echo ===============================================================================
echo   SUCCESS! Windows Firewall rules configured for Nexus Direct PC Share!
echo ===============================================================================
echo.
pause
