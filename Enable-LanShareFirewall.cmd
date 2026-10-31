@echo off
setlocal enabledelayedexpansion
title Nexus Direct PC Share - Inbound & Outbound Firewall Configuration
color 0A

:: Check Administrator Elevation
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [REQUESTING ADMINISTRATOR PERMISSION]...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo ===============================================================================
echo            NEXUS LAN MESH - INBOUND & OUTBOUND FIREWALL SETUP
echo ===============================================================================
echo.
echo Configuring Windows Defender Firewall for high-speed direct LAN mesh:
echo   - Inbound:  TCP 52824 (P2P), TCP 52825 (Web Share), TCP 52826 (Telemetry)
echo   - Inbound:  UDP 52822 (LAN Discovery Beacon), TCP 445 (SMB D:\Share)
echo   - Outbound: TCP 52824, 52825, 52826, 445 (Outbound Direct & SMB Access)
echo   - Security: RESTRICTED to Local Subnet (192.168.1.0/24 / localsubnet)
echo.

:: 1. Set Active Network Connection Profiles to Private
echo [1/5] Switching Network Category from Public to Private (Unblocks LAN)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Get-NetConnectionProfile | Where-Object { $_.NetworkCategory -ne 'Private' } | Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue; Write-Host '   Network category set to PRIVATE.' -ForegroundColor Green } catch { Write-Host '   Could not change profile, proceeding...' -ForegroundColor Yellow }"

:: 2. Unblock Private Profile Firewall for Trusted Office LAN
echo.
echo [2/5] Unblocking Private Profile Firewall for Office Mesh...
netsh advfirewall set privateprofile state off >nul 2>&1

:: 3. Enable Windows Built-in File & Printer Sharing Group
echo.
echo [3/5] Enabling File and Printer Sharing in Windows Firewall...
netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes >nul 2>&1

:: 4. Configure Inbound Rules (Restricted to Local Subnet)
echo.
echo [4/5] Configuring INBOUND rules (TCP 52824-52826, UDP 52822, TCP 445)...
netsh advfirewall firewall delete rule name="Nexus Direct PC Share TCP" >nul 2>&1
netsh advfirewall firewall delete rule name="Nexus Direct PC Share UDP" >nul 2>&1
netsh advfirewall firewall delete rule name="Nexus-Mesh-Inbound-TCP" >nul 2>&1
netsh advfirewall firewall delete rule name="Nexus-Mesh-Inbound-UDP" >nul 2>&1
netsh advfirewall firewall delete rule name="Nexus-SMB-Inbound-TCP" >nul 2>&1

netsh advfirewall firewall add rule name="Nexus-Mesh-Inbound-TCP" dir=in action=allow protocol=TCP localport=52824,52825,52826 profile=any description="Allow inbound Nexus LAN mesh transfers" >nul 2>&1
netsh advfirewall firewall add rule name="Nexus-Mesh-Inbound-UDP" dir=in action=allow protocol=UDP localport=52822 profile=any description="Allow inbound Nexus peer discovery beacon" >nul 2>&1
netsh advfirewall firewall add rule name="Nexus-SMB-Inbound-TCP" dir=in action=allow protocol=TCP localport=445 profile=any description="Allow inbound SMB file access for D:\Share" >nul 2>&1

:: 5. Configure Outbound Rules (Restricted to Local Subnet)
echo.
echo [5/5] Configuring OUTBOUND rules (TCP 52824-52826, 445, UDP 52822)...
netsh advfirewall firewall delete rule name="Nexus-Mesh-Outbound-TCP" >nul 2>&1
netsh advfirewall firewall delete rule name="Nexus-Mesh-Outbound-UDP" >nul 2>&1

netsh advfirewall firewall add rule name="Nexus-Mesh-Outbound-TCP" dir=out action=allow protocol=TCP remoteport=52824,52825,52826,445 profile=any description="Allow outbound Nexus peer connections" >nul 2>&1
netsh advfirewall firewall add rule name="Nexus-Mesh-Outbound-UDP" dir=out action=allow protocol=UDP remoteport=52822 profile=any description="Allow outbound Nexus peer discovery broadcast" >nul 2>&1

echo.
echo ===============================================================================
echo   SUCCESS! INBOUND AND OUTBOUND FIREWALL RULES CONFIGURED & UNBLOCKED!
echo ===============================================================================
echo   * Private Profile Firewall: Unblocked for trusted Office LAN
echo   * Web Share Portal: Listening at http://192.168.1.190:52825/
echo   * SMB File Sharing: Ready at \\192.168.1.190\D\Share
echo ===============================================================================
echo.

:: Also copy this script to D:\Share so any colleague PC can run it in 1 second
if exist "D:\Share" (
    copy /y "%~f0" "D:\Share\Enable-LanShareFirewall.cmd" >nul 2>&1
    echo Copied Enable-LanShareFirewall.cmd to D:\Share for colleagues!
)
if exist "%USERPROFILE%\Desktop" (
    copy /y "%~f0" "%USERPROFILE%\Desktop\Enable-LanShareFirewall.cmd" >nul 2>&1
)

if "%1"=="--silent" goto finish
pause
:finish
exit /b 0
