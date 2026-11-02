$ErrorActionPreference = "Stop"

Set-Location "E:\code\chesterworld-roblox"

Write-Host ""
Write-Host "============================================================"
Write-Host "BUILD FRESH UNIFORM REGIONAL TERRAIN"
Write-Host "============================================================"

py .\tools\build_fresh_uniform_regional_terrain.py

if ($LASTEXITCODE -ne 0) {
    throw "Fresh uniform regional terrain build failed."
}

Write-Host ""
Write-Host "Build complete."
Write-Host "Open:"
Write-Host "E:\ChesterWorld\Data\09_RegionalTerrain\RobloxFreshUniformImport\IMPORT_ALL_9.txt"
