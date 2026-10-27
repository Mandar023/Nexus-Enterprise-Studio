# ==============================================================================
# NEXUS OPTIMIZER - AUTOMATED GITHUB REPOSITORY CREATOR & UPLOADER
# Authenticates via GitHub Web / OAuth and uploads the complete repository.
# ==============================================================================

[Console]::Title = "Nexus Optimizer - GitHub Repository Creator & Uploader"
Clear-Host

# Ensure tools are in PATH
$gitCmdPath = "$env:LOCALAPPDATA\Programs\Git\cmd"
$ghBinPath  = "$env:LOCALAPPDATA\Programs\GitHub CLI"
$env:Path = "$gitCmdPath;$ghBinPath;$env:Path"

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  NEXUS OPTIMIZER - GITHUB REPOSITORY CREATOR & UPLOADER" -ForegroundColor Yellow
Write-Host "  Enterprise Release v5.5.0" -ForegroundColor White
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""

$ghExe = Join-Path $ghBinPath "gh.exe"
$gitExe = Join-Path $gitCmdPath "git.exe"

if (-not (Test-Path $ghExe) -or -not (Test-Path $gitExe)) {
    Write-Host "ERROR: Git or GitHub CLI not found in user programs directory." -ForegroundColor Red
    pause
    exit 1
}

# 1. Check Authentication Status
Write-Host "[STEP 1/4] Checking GitHub Authentication..." -ForegroundColor Yellow
$authStatus = & $ghExe auth status 2>&1
$isLoggedIn = ($LASTEXITCODE -eq 0 -and $authStatus -match 'Logged in to github.com')

if (-not $isLoggedIn) {
    Write-Host "You are not logged in yet. Launching GitHub Web Authorization..." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "INSTRUCTIONS:" -ForegroundColor Yellow
    Write-Host "  1. A one-time code will be displayed below." -ForegroundColor White
    Write-Host "  2. Press Enter to open the GitHub authorization page in your browser." -ForegroundColor White
    Write-Host "  3. Enter/paste the code and click 'Authorize github'." -ForegroundColor White
    Write-Host ""
    
    & $ghExe auth login --web -h github.com -p https -s repo,workflow,read:org
    
    # Re-verify
    $authStatus = & $ghExe auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "`nERROR: GitHub authentication was not completed. Please try again." -ForegroundColor Red
        pause
        exit 1
    }
}

# Get Authenticated User Details
$ghUser = (& $ghExe api user --jq .login).Trim()
Write-Host "Successfully authenticated as GitHub user: $ghUser" -ForegroundColor Green

# 2. Configure Git Credentials
Write-Host "`n[STEP 2/4] Configuring Git Credentials & Identity..." -ForegroundColor Yellow
$ghEmail = (& $ghExe api user --jq .email).Trim()
if ([string]::IsNullOrWhiteSpace($ghEmail) -or $ghEmail -eq "null") {
    $ghEmail = "$ghUser@users.noreply.github.com"
}

& $gitExe config --global user.name "$ghUser"
& $gitExe config --global user.email "$ghEmail"
& $ghExe auth setup-git

Write-Host "Git user: $ghUser <$ghEmail>" -ForegroundColor Cyan

# 3. Prepare Repository Workspace
Write-Host "`n[STEP 3/4] Preparing Git Workspace & Staging Files..." -ForegroundColor Yellow
$workspaceDir = "C:\Users\mandar.k\Documents\antigravity\lively-raman"
Set-Location -Path $workspaceDir

if (-not (Test-Path (Join-Path $workspaceDir ".git"))) {
    & $gitExe init -b main
    Write-Host "Initialized new Git repository with default branch 'main'." -ForegroundColor Green
} else {
    & $gitExe branch -M main
}

# Ensure .gitignore exists and excludes scratch / temp files
$gitignorePath = Join-Path $workspaceDir ".gitignore"
if (-not (Test-Path $gitignorePath)) {
    $giContent = @"
scratch/
sim_panvel/
sim_full/
*.tmp
*.log
*.zip
.vscode/
"@
    [System.IO.File]::WriteAllText($gitignorePath, $giContent, [System.Text.Encoding]::ASCII)
}

& $gitExe add -A

$commitMsg = @"
feat: Nexus Enterprise Release v5.5.0 - Multi-Server Consolidator & Municipal Optimizer

- Added Multi-Server Consolidator (whole images to PropertyImage, plans to PlanPhoto)
- Added automatic deduplication & common-file ignore heuristics
- Integrated Ward Reference Extractor with dual-column Excel/CSV export (Options A, B, C)
- Implemented Crystal Reports Safe solid pure-white canvas WMF processing (<25KB)
- Integrated Beyond Compare 5 folder & binary diff studio
- Zero AST parser syntax errors, 100% pure ASCII compliance
"@

$status = (& $gitExe status --porcelain)
if ($status) {
    & $gitExe commit -m $commitMsg
    Write-Host "Committed release files with enterprise commit message!" -ForegroundColor Green
} else {
    Write-Host "Working directory clean; ready to push." -ForegroundColor Cyan
}

# 4. Create Repository on GitHub and Push
Write-Host "`n[STEP 4/4] Creating Repository on GitHub & Pushing..." -ForegroundColor Yellow
$repoName = "Nexus-Photo-Optimizer"
$repoDesc = "Enterprise Municipal Photo & Document Optimizer with Multi-Server Sync, PlanPhoto WMF/EMF Vector White-Canvas Processing, Ward Crawling, and SQL Hub Releases"

$repoCheck = & $ghExe repo view "$ghUser/$repoName" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Creating new repository '$repoName' under $ghUser..." -ForegroundColor Cyan
    & $ghExe repo create "$repoName" --public --description "$repoDesc" --source=. --remote=origin --push
} else {
    Write-Host "Repository '$ghUser/$repoName' already exists on GitHub. Pushing latest changes..." -ForegroundColor Cyan
    & $gitExe remote set-url origin "https://github.com/$ghUser/$repoName.git"
    & $gitExe push -u origin main
}

if ($LASTEXITCODE -eq 0) {
    $repoUrl = "https://github.com/$ghUser/$repoName"
    Write-Host ""
    Write-Host "======================================================================" -ForegroundColor Green
    Write-Host "  SUCCESSFULLY UPLOADED TO GITHUB!" -ForegroundColor Green
    Write-Host "  Repository URL : $repoUrl" -ForegroundColor Yellow
    Write-Host "======================================================================" -ForegroundColor Green
    
    # Open repository in default browser
    Start-Process "$repoUrl"
} else {
    Write-Host "`nPush failed. Please check network connection or permissions." -ForegroundColor Red
}

Write-Host ""
pause
