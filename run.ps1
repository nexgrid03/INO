# INO — safe launcher for Windows.
#
# The recurring Gradle error "Unable to delete directory ... mergeDebugAssets"
# happens when a leftover dart/java/adb process (usually a previous `flutter run`
# that wasn't stopped) still holds files inside build\. This script kills any
# such lockers, clears build\, then runs the app — so every launch starts clean.
#
# Usage: from the project folder, run:  ./run.ps1
# (Use this INSTEAD of the VS Code "Run" button until the lock stops recurring.)

$ErrorActionPreference = 'SilentlyContinue'
$proj = $PSScriptRoot

Write-Host 'Stopping any leftover dart/java processes...' -ForegroundColor Cyan
Get-Process dart, java -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500

Write-Host 'Clearing the build folder...' -ForegroundColor Cyan
Remove-Item -Path (Join-Path $proj 'build') -Recurse -Force -ErrorAction SilentlyContinue

$ephemeral = Join-Path $proj 'ios\Flutter\ephemeral'
if (Test-Path $ephemeral) {
    Write-Host 'Clearing read-only attributes and removing ios/Flutter/ephemeral...' -ForegroundColor Cyan
    attrib -r "$ephemeral\*" /s /d
    Remove-Item -Path $ephemeral -Recurse -Force -ErrorAction SilentlyContinue
}

if (Test-Path (Join-Path $proj 'build')) {
    Write-Host 'WARNING: build\ is still locked. Close any File Explorer window' -ForegroundColor Yellow
    Write-Host 'open inside build\, and fully close the app on your phone, then retry.' -ForegroundColor Yellow
}

Write-Host 'Launching the app...' -ForegroundColor Green
flutter run

