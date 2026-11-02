$ErrorActionPreference = "Stop"

Set-Location "E:\code\chesterworld-roblox"

Write-Host ""
Write-Host "============================================================"
Write-Host "CHESTERWORLD REAL-WORLD PASS 3"
Write-Host "PROMOTE CLEAN TILES + ROAD/TERRAIN CONFORMANCE"
Write-Host "============================================================"

New-Item -ItemType Directory -Force -Path ".\src\server\World" | Out-Null

# Back up an existing conformer separately if one exists.
if (Test-Path ".\src\server\World\RoadTerrainConformer.server.lua") {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    New-Item -ItemType Directory -Force -Path ".\tools\backups\realworld_pass3" | Out-Null
    Copy-Item `
        ".\src\server\World\RoadTerrainConformer.server.lua" `
        ".\tools\backups\realworld_pass3\RoadTerrainConformer.before_$stamp.server.lua" `
        -Force
}

Copy-Item `
    ".\tools\RoadTerrainConformer.server.lua" `
    ".\src\server\World\RoadTerrainConformer.server.lua" `
    -Force

py .\tools\prepare_realworld_lua_promotion.py
if ($LASTEXITCODE -ne 0) {
    throw "Promotion preparation failed."
}

py .\tools\package_roblox_realworld_world.py
if ($LASTEXITCODE -ne 0) {
    throw "Real-world Roblox export failed. Previous Lua tile backup is under tools\backups\realworld_pass3."
}

py .\tools\audit_realworld_lua_export.py
if ($LASTEXITCODE -ne 0) {
    throw "Lua export audit failed."
}

Write-Host ""
Write-Host "============================================================"
Write-Host "PASS 3 FILE PROMOTION COMPLETE"
Write-Host "============================================================"
Write-Host ""
Write-Host "Let Rojo sync, then press Play."
Write-Host ""
Write-Host "In Roblox Output, look for:"
Write-Host "[ChesterWorld RoadTerrainConformer] ..."
Write-Host ""
Write-Host "Then inspect Chester -> Parkside -> Upland -> Brookhaven."
Write-Host "Do NOT re-import terrain."
