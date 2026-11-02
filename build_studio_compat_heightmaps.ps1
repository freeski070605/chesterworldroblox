$ErrorActionPreference = "Stop"
Set-Location "E:\code\chesterworld-roblox"

py .\tools\build_studio_compat_heightmaps.py

if ($LASTEXITCODE -ne 0) {
    throw "Studio compatibility heightmap build failed."
}

Write-Host ""
Write-Host "Open:"
Write-Host "E:\ChesterWorld\Data\09_RegionalTerrain\RobloxExtensionImport\StudioCompat\IMPORT_STUDIO_COMPAT.txt"
