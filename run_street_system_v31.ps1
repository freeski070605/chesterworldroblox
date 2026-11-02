$ErrorActionPreference = "Stop"

Set-Location "E:\code\chesterworld-roblox"

Write-Host ""
Write-Host "================================================================"
Write-Host "CHESTERWORLD STREET SYSTEM V3.1 - REPAIR + CLEAN EXPORT"
Write-Host "================================================================"
Write-Host ""

# 1) Patch sidewalk density and clear stale tile modules.
py .\tools\repair_street_system_v31.py
if ($LASTEXITCODE -ne 0) {
    throw "Street V3.1 repair prep failed."
}

# 2) Rebuild source-derived street finish with lower part count.
py .\tools\build_street_system_v3.py
if ($LASTEXITCODE -ne 0) {
    throw "Street source rebuild failed."
}

# 3) Rebuild regional tiles from motor-road-only source.
py .\tools\package_regional_world_tiles_street_v3.py
if ($LASTEXITCODE -ne 0) {
    throw "Street V3 regional tile packaging failed."
}

# 4) Remove tiny road slivers.
py .\tools\sanitize_street_v3_tiles.py
if ($LASTEXITCODE -ne 0) {
    throw "Street V3 tile sanitizer failed."
}

# 5) Export into the now-clean Lua tile folder.
py .\tools\package_roblox_street_v3_world.py --all
if ($LASTEXITCODE -ne 0) {
    throw "Street V3 Roblox export failed."
}

# 6) StreetFinishBuilder is already source-level V3.
# Re-copy from tools in case Rojo source was not updated on the prior failed run.
$worldDir = ".\src\server\World"
New-Item -ItemType Directory -Force -Path $worldDir | Out-Null

Copy-Item `
    ".\tools\StreetFinishBuilder.server.lua" `
    (Join-Path $worldDir "StreetFinishBuilder.server.lua") `
    -Force

# 7) Strict audit: exactly 102 modules and reasonable sidewalk part budget.
py .\tools\audit_street_system_v31.py
if ($LASTEXITCODE -ne 0) {
    throw "Street System V3.1 final audit failed."
}

Write-Host ""
Write-Host "================================================================"
Write-Host "STREET SYSTEM V3.1 READY"
Write-Host "================================================================"
Write-Host ""
Write-Host "Let Rojo sync, then Play."
Write-Host "Do NOT re-import terrain."
Write-Host ""
Write-Host "Look for:"
Write-Host "[ChesterWorld RoadTerrainConformer] ..."
Write-Host "[ChesterWorld StreetSystemV3] ..."
