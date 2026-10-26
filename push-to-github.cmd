@echo off
setlocal EnableDelayedExpansion
title Nexus Suite - Push to GitHub
color 0B
cd /d "%~dp0"

echo ===============================================================================
echo            NEXUS SUITE - ONE-CLICK GITHUB REPOSITORY PUBLISHER
echo ===============================================================================
echo.
echo Your local Git repository is initialized, committed, and ready on branch 'main'.
echo.
echo Step 1: Go to https://github.com/new in your browser.
echo Step 2: Create a new repository (e.g., 'nexus-photo-optimizer').
echo         (Do NOT initialize with README, .gitignore, or license).
echo Step 3: Copy the HTTPS repository URL (e.g., https://github.com/username/repo.git).
echo.
echo ===============================================================================
set /p REPO_URL="Enter your GitHub Repository URL: "

if "%REPO_URL%"=="" (
    echo.
    echo [ERROR] No URL provided. Operation cancelled.
    pause
    exit /b 1
)

echo.
echo Configuring remote 'origin'...
git remote remove origin >nul 2>&1
git remote add origin %REPO_URL%

echo.
echo Pushing branch 'main' to GitHub...
git push -u origin main

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ===============================================================================
    echo [SUCCESS] Your repository has been published to GitHub successfully!
    echo URL: %REPO_URL%
    echo ===============================================================================
) else (
    echo.
    echo [NOTE] If prompted for authentication, enter your GitHub Personal Access Token (PAT).
)

echo.
pause
