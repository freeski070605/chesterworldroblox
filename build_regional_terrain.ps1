$ErrorActionPreference = "Stop"

Set-Location "E:\code\chesterworld-roblox"

Write-Host ""
Write-Host "============================================================"
Write-Host "EXPAND REGIONAL 3DEP TERRAIN"
Write-Host "============================================================"

py .\tools\expand_regional_terrain.py
if ($LASTEXITCODE -ne 0) {
    throw "Regional terrain expansion failed."
}

Write-Host ""
Write-Host "============================================================"
Write-Host "RE-RUN REGIONAL READINESS AUDIT"
Write-Host "============================================================"

py .\tools\audit_regional_ready.py
if ($LASTEXITCODE -ne 0) {
    throw "Regional readiness audit failed."
}

Write-Host ""
Write-Host "If the audit says REGIONAL TILING: READY, the next command is:"
Write-Host "py .\tools\package_regional_world_tiles.py"
