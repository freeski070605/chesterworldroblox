$ErrorActionPreference = "Stop"

Set-Location "E:\code\chesterworld-roblox"

Write-Host ""
Write-Host "============================================================"
Write-Host "PREP REGIONAL ROBLOX EXPORTER"
Write-Host "============================================================"

py .\tools\prepare_regional_roblox_export.py

if ($LASTEXITCODE -ne 0) {
    throw "Regional Roblox exporter prep failed."
}

Write-Host ""
Write-Host "============================================================"
Write-Host "EXPORT REGIONAL LUA MODULES"
Write-Host "============================================================"
Write-Host ""
Write-Host "This will run the regional COPY of the exporter."
Write-Host "The original package_roblox_world.py remains unchanged."
Write-Host ""

py .\tools\package_roblox_regional_world.py --all

if ($LASTEXITCODE -ne 0) {
    throw "Regional Roblox Lua export failed."
}

Write-Host ""
Write-Host "============================================================"
Write-Host "REGIONAL LUA EXPORT FINISHED"
Write-Host "============================================================"
Write-Host ""
Write-Host "IMPORTANT:"
Write-Host "Do NOT replace WorldPlacement.lua with the staged regional file yet."
Write-Host "Do NOT press Play in Studio yet if regional terrain has not been imported."
