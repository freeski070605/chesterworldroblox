# One-pass ChesterWorld GIS water export and sync.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
function Check-Step([string]$Name) {
    if ($LASTEXITCODE -ne 0) { throw "$Name failed (exit $LASTEXITCODE)" }
}
$alreadyStaged = @(git diff --cached --name-only)
Check-Step "Staged check"
if ($alreadyStaged.Count -gt 0) {
    throw "You already have staged changes. Commit/unstage them before the water pass."
}
git pull --ff-only origin main
Check-Step "git pull"
py .\tools\build_exit6_water.py
Check-Step "GIS water export"
git add -- src/shared/WaterData/Manifest.lua src/shared/WaterData/Tiles tools/reports/exit6_water_export.json
Check-Step "Stage water GIS data"
git diff --cached --quiet
if ($LASTEXITCODE -eq 1) {
    git commit -m "Export mapped Chester waterways to native Terrain water tiles"
    Check-Step "Commit GIS coverage"
    git push origin main
    Check-Step "Push GIS coverage"
} elseif ($LASTEXITCODE -ne 0) {
    throw "git diff failed ($LASTEXITCODE)"
}
Write-Host ""
Write-Host "EXIT 6 GIS WATER PASS READY. Connect Rojo in Studio and start a fresh Play test."
Write-Host "Expected log: [EXIT6 Water] COMPLETE ... waterVoxels=..."
Write-Host "Expected log: [EXIT6] World ready: ... roads/highway/parks/gas/water complete"
rojo serve default.project.json
Check-Step "Rojo"
