$ErrorActionPreference = "Stop"

Set-Location "E:\code\chesterworld-roblox"

Write-Host ""
Write-Host "============================================================"
Write-Host "BUILD REGIONAL ROBLOX TERRAIN EXTENSION"
Write-Host "============================================================"

py .\tools\build_regional_roblox_terrain_extension.py

if ($LASTEXITCODE -ne 0) {
    throw "Regional Roblox terrain extension build failed."
}

Write-Host ""
Write-Host "Heightmaps are ready."
Write-Host "Open:"
Write-Host "E:\ChesterWorld\Data\09_RegionalTerrain\RobloxExtensionImport\IMPORT_INSTRUCTIONS.txt"
Write-Host ""
Write-Host "Do NOT activate WorldPlacement until all extension heightmaps are imported."
