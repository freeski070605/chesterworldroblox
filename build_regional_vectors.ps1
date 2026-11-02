$ErrorActionPreference = "Stop"

Set-Location "E:\code\chesterworld-roblox"

function Run-Step {
    param(
        [string]$Label,
        [string]$Script
    )

    Write-Host ""
    Write-Host "============================================================"
    Write-Host $Label
    Write-Host "============================================================"

    py $Script

    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE"
    }
}

Run-Step "1/4 DOWNLOAD + MERGE REGIONAL SOURCES" ".\tools\download_regional_sources.py"
Run-Step "2/4 BUILD REGIONAL BUILDING GENERATOR DATA" ".\tools\classify_regional_building_archetypes_v2.py"
Run-Step "3/4 BUILD REGIONAL ROAD GENERATOR DATA" ".\tools\prepare_regional_generator_roads.py"
Run-Step "4/4 REGIONAL READY AUDIT" ".\tools\audit_regional_ready.py"

Write-Host ""
Write-Host "Regional vector build + terrain audit complete."
Write-Host "Do NOT run package_regional_world_tiles.py unless the audit says REGIONAL TILING: READY."
