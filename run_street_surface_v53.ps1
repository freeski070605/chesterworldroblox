$ErrorActionPreference = "Stop"

Set-Location "E:\code\chesterworld-roblox"

Write-Host ""
Write-Host "================================================================"
Write-Host "CHESTERWORLD STREET SURFACE V5.3"
Write-Host "2x2 SUBTILE MESH FIX FOR 2048-STUD ENGINE LIMIT"
Write-Host "================================================================"
Write-Host ""

# 1) Rebuild only the V5 visual road-surface data into 2x2 subtiles.
py .\tools\build_street_surface_v53.py
if ($LASTEXITCODE -ne 0) {
    throw "Street Surface V5.3 data build failed."
}

# 2) Install the V5.3 runtime.
$worldDir = ".\src\server\World"
New-Item -ItemType Directory -Force -Path $worldDir | Out-Null

$backupDir = ".\tools\backups\street_surface_v53"
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"

$meshTarget = Join-Path $worldDir "StreetSurfaceMeshBuilder.server.lua"

if (Test-Path $meshTarget) {
    Copy-Item `
        $meshTarget `
        (Join-Path $backupDir "StreetSurfaceMeshBuilder.before_$stamp.server.lua") `
        -Force
}

Copy-Item `
    ".\tools\StreetSurfaceMeshBuilder.server.lua" `
    $meshTarget `
    -Force

# V5.3 owns visibility itself. Back up/remove V5.1 if it still exists.
$visibility = Join-Path $worldDir "StreetSurfaceVisibility.server.lua"

if (Test-Path $visibility) {
    Copy-Item `
        $visibility `
        (Join-Path $backupDir "StreetSurfaceVisibility.before_$stamp.server.lua") `
        -Force

    Remove-Item $visibility -Force
}

# Old V4 runtime must stay off.
$oldV4 = Join-Path $worldDir "StreetSurfaceBuilder.server.lua"

if (Test-Path $oldV4) {
    Copy-Item `
        $oldV4 `
        (Join-Path $backupDir "StreetSurfaceBuilder.v4_$stamp.server.lua") `
        -Force

    Remove-Item $oldV4 -Force
}

# 3) Strict extent audit before Studio.
py .\tools\audit_street_surface_v53.py
if ($LASTEXITCODE -ne 0) {
    throw "Street Surface V5.3 file audit failed."
}

Write-Host ""
Write-Host "================================================================"
Write-Host "STREET SURFACE V5.3 READY"
Write-Host "================================================================"
Write-Host ""
Write-Host "No regional tile rebuild."
Write-Host "No terrain import."
Write-Host "No building export."
Write-Host "V3.2 roads and sidewalks remain underneath."
Write-Host ""
Write-Host "Let Rojo sync and Play."
Write-Host ""
Write-Host "Look for:"
Write-Host "[ChesterWorld StreetSurfaceV5.3] ..."
