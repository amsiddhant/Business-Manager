# deploy.ps1
# Script to update packages, build the Flutter app, deploy to Firebase, and push to Git

$ErrorActionPreference = "Stop"

Write-Host "--- 🚀 Starting Deployment Process ---" -ForegroundColor Cyan

try {
    # 1. Update Packages
    Write-Host "`n[1/4] Updating packages..." -ForegroundColor Yellow
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }

    # 2. Build the Application (Web)
    Write-Host "`n[2/4] Building Flutter Web app..." -ForegroundColor Yellow
    flutter build web --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build web failed" }

    # 3. Deploy to Firebase
    Write-Host "`n[3/4] Deploying to Firebase Hosting..." -ForegroundColor Yellow
    firebase deploy --only hosting
    if ($LASTEXITCODE -ne 0) { throw "firebase deploy failed" }

    # 4. Push to Git
    Write-Host "`n[4/4] Pushing changes to Git..." -ForegroundColor Yellow
    git add .
    # Create a timestamp for the commit message
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    git commit -m "Deploy: Automated deployment on $timestamp"
    git push origin main
    if ($LASTEXITCODE -ne 0) { throw "git push failed" }

    Write-Host "`n--- ✅ Deployment Completed Successfully! ---" -ForegroundColor Green
}
catch {
    Write-Host "`n--- ❌ Deployment Failed ---" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
