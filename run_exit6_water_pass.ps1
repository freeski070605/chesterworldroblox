# EXIT 6 GIS water export + verified GitHub push + Rojo.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

function Assert-Exit([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "EXIT 6: $Step failed (exit $LASTEXITCODE)."
    }
}

Write-Host ""
Write-Host "[EXIT6] WATER PASS - $((Get-Location).Path)" -ForegroundColor Cyan
$branch = (git branch --show-current).Trim()
Assert-Exit "Check branch"
if ($branch -ne "main") {
    throw "EXIT 6: Expected branch main; found $branch. Switch to main first."
}

# Avoid sweeping unrelated staged files into the GIS-data commit.
$alreadyStaged = @(git diff --cached --name-only | Where-Object { $_ })
Assert-Exit "Inspect staged files"
if ($alreadyStaged.Count -gt 0) {
    throw ("EXIT 6: Already staged changes found. Commit or unstage them first: " + ($alreadyStaged -join ", "))
}

Write-Host "[EXIT6] Pulling current main..."
git pull --ff-only origin main
Assert-Exit "Pull latest main"

$source = "E:\ChesterWorld\Data\16_RegionalTiles\Tiles"
if (-not (Test-Path $source -PathType Container)) {
    throw "EXIT 6: Source GIS tiles missing at $source. Cannot invent shorelines."
}
$tiles = @(Get-ChildItem -LiteralPath $source -Filter "tile_r??_c??.json" -File)
if ($tiles.Count -lt 1) {
    throw "EXIT 6: No regional tile JSON found at $source"
}

Write-Host "[EXIT6] Exporting actual water GIS from $($tiles.Count) regional tiles..."
py .\tools\build_exit6_water.py
Assert-Exit "GIS water export"

$reportPath = ".\tools\reports\exit6_water_export.json"
$manifestPath = ".\src\shared\WaterData\Manifest.lua"
$tileOut = ".\src\shared\WaterData\Tiles"
if (-not (Test-Path $reportPath) -or -not (Test-Path $manifestPath) -or -not (Test-Path $tileOut)) {
    throw "EXIT 6: Export output missing. Nothing to push."
}
$report = Get-Content -Raw $reportPath | ConvertFrom-Json
$waterCount = @(Get-ChildItem -LiteralPath $tileOut -Filter "tile_r??_c??.lua" -File).Count
if ($waterCount -lt 1 -or [int]$report.mapped_polygon_cells -lt 1) {
    throw "EXIT 6: No GIS water-polygon coverage detected. Export cannot safely continue."
}
Write-Host "[EXIT6] EXPORT: $waterCount modules, $($report.water_rectangles) rectangles, $($report.mapped_polygon_cells) polygon cells." -ForegroundColor Green

git add -- src/shared/WaterData/Manifest.lua src/shared/WaterData/Tiles tools/reports/exit6_water_export.json
Assert-Exit "Stage generated GIS files"
$staged = @(git diff --cached --name-only | Where-Object { $_ })
Assert-Exit "Inspect staged changes"
if ($staged.Count -gt 0) {
    Write-Host "[EXIT6] Committing $($staged.Count) generated file changes..."
    git commit -m "Export Chester GIS waterways for EXIT 6"
    Assert-Exit "Commit water GIS files"
} else {
    Write-Host "[EXIT6] Generated water data already committed; no new commit needed." -ForegroundColor Yellow
}

# Always push - even if the GIS file generation did not change anything.
Write-Host "[EXIT6] Pushing main to GitHub..."
git push origin main
Assert-Exit "Push main"

$localSha = (git rev-parse HEAD).Trim()
Assert-Exit "Read local commit"
git fetch origin main --quiet
Assert-Exit "Refresh origin/main"
$remoteSha = (git rev-parse origin/main).Trim()
Assert-Exit "Read remote commit"
if ($localSha -ne $remoteSha) {
    throw "EXIT 6: GitHub verification failed: HEAD=$localSha origin/main=$remoteSha"
}
Write-Host "[EXIT6] VERIFIED origin/main commit $localSha" -ForegroundColor Green
Write-Host "[EXIT6] GitHub updated. Roblox players still need Studio > File > Publish to Roblox." -ForegroundColor Yellow
Write-Host "[EXIT6] Starting Rojo; connect Studio and start a fresh Play test."
rojo serve default.project.json
Assert-Exit "Rojo"
