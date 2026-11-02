$ErrorActionPreference = "Stop"

Set-Location "E:\code\chesterworld-roblox"

Write-Host ""
Write-Host "================================================================"
Write-Host "CHESTERWORLD STREET SYSTEM V3 - COMPLETE CORRECTION PASS"
Write-Host "================================================================"
Write-Host ""

# 1) Source cleanup + source-derived sidewalk/junction data
py .\tools\build_street_system_v3.py
if ($LASTEXITCODE -ne 0) {
    throw "Street source build failed."
}

# 2) Prepare staged whole-building tile packager + Roblox exporter
py .\tools\prepare_street_v3_packagers.py
if ($LASTEXITCODE -ne 0) {
    throw "Street V3 packager prep failed."
}

# 3) Repackage the full regional world with motor roads only
py .\tools\package_regional_world_tiles_street_v3.py
if ($LASTEXITCODE -ne 0) {
    throw "Street V3 regional tile packaging failed."
}

# 4) Remove tiny asphalt slivers before Roblox export
py .\tools\sanitize_street_v3_tiles.py
if ($LASTEXITCODE -ne 0) {
    throw "Street V3 tile sanitizer failed."
}

# 5) Promote corrected 102-tile road set into Roblox
py .\tools\package_roblox_street_v3_world.py --all
if ($LASTEXITCODE -ne 0) {
    throw "Street V3 Roblox export failed. Lua backup is under tools\backups\street_system_v3."
}

# 6) Install source-level street finish runtime
$worldDir = ".\src\server\World"
New-Item -ItemType Directory -Force -Path $worldDir | Out-Null

$finishTarget = Join-Path $worldDir "StreetFinishBuilder.server.lua"

if (Test-Path $finishTarget) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupDir = ".\tools\backups\street_system_v3"
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

    Copy-Item `
        $finishTarget `
        (Join-Path $backupDir "StreetFinishBuilder.before_$stamp.server.lua") `
        -Force
}

Copy-Item `
    ".\tools\StreetFinishBuilder.server.lua" `
    $finishTarget `
    -Force

# 7) Final file audit
py .\tools\audit_street_system_v3.py
if ($LASTEXITCODE -ne 0) {
    throw "Street System V3 final audit failed."
}

Write-Host ""
Write-Host "================================================================"
Write-Host "STREET SYSTEM V3 READY"
Write-Host "================================================================"
Write-Host ""
Write-Host "Let Rojo sync, then Play."
Write-Host ""
Write-Host "Do NOT run Pass 4C first. This replaces it."
Write-Host "Do NOT re-import terrain."
Write-Host ""
Write-Host "Look for both:"
Write-Host "[ChesterWorld RoadTerrainConformer] ..."
Write-Host "[ChesterWorld StreetSystemV3] ..."
