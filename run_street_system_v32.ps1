$ErrorActionPreference = "Stop"

Set-Location "E:\code\chesterworld-roblox"

Write-Host ""
Write-Host "================================================================"
Write-Host "CHESTERWORLD STREET SYSTEM V3.2 - ORDER + JUNCTION FIX"
Write-Host "================================================================"
Write-Host ""

# Regenerate ONLY StreetFinishData from the same known-good road source.
py .\tools\build_street_system_v32.py
if ($LASTEXITCODE -ne 0) {
    throw "Street System V3.2 source build failed."
}

# Patch Bootstrap ordering and install deterministic runtime scripts.
py .\tools\install_street_system_v32.py
if ($LASTEXITCODE -ne 0) {
    throw "Street System V3.2 install failed."
}

# Validate before Studio.
py .\tools\audit_street_system_v32.py
if ($LASTEXITCODE -ne 0) {
    throw "Street System V3.2 file audit failed."
}

Write-Host ""
Write-Host "================================================================"
Write-Host "STREET SYSTEM V3.2 READY"
Write-Host "================================================================"
Write-Host ""
Write-Host "No tile rebuild."
Write-Host "No terrain import."
Write-Host "No building export."
Write-Host ""
Write-Host "Let Rojo sync, then Play."
Write-Host ""
Write-Host "Expected runtime order:"
Write-Host "  [ChesterWorld] Built 102/102 tiles."
Write-Host "  [ChesterWorld] Bootstrap complete."
Write-Host "  [ChesterWorld RoadTerrainConformer] final=..."
Write-Host "  [ChesterWorld StreetSystemV3.2] ..."
