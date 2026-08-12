# INO - fast web launcher (no Flutter debug / DWDS).
#
# Why: `flutter run -d chrome` (debug) loads ~1800 JS modules and needs a
# WebSocket debug service. With Chrome DevTools + iPhone emulation that
# connection often fails → blank white screen + long waits.
#
# This builds a RELEASE web bundle once (or with -Rebuild), then serves it.
# After the first build, opening the app is near-instant.
#
# Usage:
#   ./run-web-fast.ps1
#   ./run-web-fast.ps1 -Rebuild

param(
  [switch]$Rebuild,
  [int]$Port = 8080
)

$ErrorActionPreference = 'Stop'
$proj = $PSScriptRoot
Set-Location $proj

$webDir = Join-Path $proj 'build\web'
$webIndex = Join-Path $webDir 'index.html'
$needBuild = $Rebuild -or -not (Test-Path $webIndex)

if ($needBuild) {
  Write-Host 'Building release web (one-time / rebuild)...' -ForegroundColor Cyan
  flutter build web --release
  if (-not (Test-Path $webIndex)) {
    throw 'build/web/index.html missing after build'
  }
  Write-Host 'Build done.' -ForegroundColor Green
} else {
  Write-Host 'Using existing build\web (pass -Rebuild to refresh code).' -ForegroundColor Green
}

Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue |
  ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 300

$url = "http://127.0.0.1:$Port/"
Write-Host "Serving $url  (Ctrl+C to stop)" -ForegroundColor Green
Write-Host 'Leave Chrome device emulation OFF until you see the splash.' -ForegroundColor Yellow
Start-Process $url

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add($url)
$listener.Start()

$mime = @{
  '.html' = 'text/html; charset=utf-8'
  '.js'   = 'application/javascript'
  '.mjs'  = 'application/javascript'
  '.css'  = 'text/css'
  '.json' = 'application/json'
  '.png'  = 'image/png'
  '.jpg'  = 'image/jpeg'
  '.jpeg' = 'image/jpeg'
  '.svg'  = 'image/svg+xml'
  '.wasm' = 'application/wasm'
  '.ttf'  = 'font/ttf'
  '.otf'  = 'font/otf'
  '.woff' = 'font/woff'
  '.woff2'= 'font/woff2'
  '.map'  = 'application/json'
  '.ico'  = 'image/x-icon'
}

try {
  while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $reqPath = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart('/'))
    if ([string]::IsNullOrWhiteSpace($reqPath)) { $reqPath = 'index.html' }

    $full = [System.IO.Path]::GetFullPath((Join-Path $webDir $reqPath))
    if (-not $full.StartsWith([System.IO.Path]::GetFullPath($webDir))) {
      $ctx.Response.StatusCode = 403
      $ctx.Response.Close()
      continue
    }

    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
      # SPA fallback
      $full = $webIndex
    }

    $ext = [System.IO.Path]::GetExtension($full).ToLowerInvariant()
    $bytes = [System.IO.File]::ReadAllBytes($full)
    $ctx.Response.ContentType = $(if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' })
    $ctx.Response.ContentLength64 = $bytes.Length
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $ctx.Response.Close()
  }
} finally {
  $listener.Stop()
  $listener.Close()
}
