@echo off
title Quick OTP Decryptor
powershell.exe -ExecutionPolicy Bypass -File "%~dp0Decode-OTP.ps1" -FromClipboard
if %ERRORLEVEL% NEQ 0 (
    powershell.exe -ExecutionPolicy Bypass -File "%~dp0Decode-OTP.ps1"
)
pause
