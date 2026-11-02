$ErrorActionPreference = "Stop"

Set-Location "E:\code\chesterworld-roblox"

Write-Host ""
Write-Host "================================================================"
Write-Host "CHESTERWORLD STREET SURFACE V4"
Write-Host "SOURCE-DERIVED JOINED INTERSECTION CAPS"
Write-Host "================================================================"
Write-Host ""

py .\tools\build_street_surface_v4.py
if ($LASTEXITCODE -ne 0) {
    throw "Street Surface V4 source build failed."
}

$worldDir = ".\src\server\World"
New-Item -ItemType Directory -Force -Path $worldDir | Out-Null

$target = Join-Path $worldDir "StreetSurfaceBuilder.server.lua"

if (Test-Path $target) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupDir = ".\tools\backups\street_surface_v4"
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

    Copy-Item `
        $target `
        (Join-Path $backupDir "StreetSurfaceBuilder.before_$stamp.server.lua") `
        -Force
}

Copy-Item `
    ".\tools\StreetSurfaceBuilder.server.lua" `
    $target `
    -Force

py .\tools\audit_street_surface_v4.py
if ($LASTEXITCODE -ne 0) {
    throw "Street Surface V4 file audit failed."
}

Write-Host ""
Write-Host "================================================================"
Write-Host "STREET SURFACE V4 READY"
Write-Host "================================================================"
Write-Host ""
Write-Host "No tile rebuild."
Write-Host "No terrain import."
Write-Host "No building export."
Write-Host "V3.2 remains installed."
Write-Host ""
Write-Host "Let Rojo sync, then Play."
Write-Host ""
Write-Host "Look for:"
Write-Host "[ChesterWorld StreetSurfaceV4] ..."
