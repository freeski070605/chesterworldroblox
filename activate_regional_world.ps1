$ErrorActionPreference = "Stop"

$project = "E:\code\chesterworld-roblox"
$current = Join-Path $project "src\shared\WorldPlacement.lua"
$staged = Join-Path $project "src\shared\WorldPlacement.regional.staged.lua"
$backupDir = Join-Path $project "tools\backups\regional_activation"

Set-Location $project

if (!(Test-Path $current)) {
    throw "Missing current WorldPlacement.lua: $current"
}

if (!(Test-Path $staged)) {
    throw "Missing staged regional placement: $staged"
}

New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup = Join-Path $backupDir "WorldPlacement.before_regional_$stamp.lua"

Copy-Item $current $backup -Force

$tileCount = (
    Get-ChildItem ".\src\shared\WorldData\Tiles" -Filter "*.lua" -File
).Count

if ($tileCount -lt 100) {
    throw "Expected about 102 regional tile modules, found only $tileCount. Activation stopped."
}

$stagedText = Get-Content $staged -Raw

if ($stagedText -notmatch "CENTER_X_M\s*=\s*6347\.889") {
    throw "Staged WorldPlacement does not contain CENTER_X_M = 6347.889"
}

if ($stagedText -notmatch "CENTER_Z_M\s*=\s*7201\.973") {
    throw "Staged WorldPlacement does not contain CENTER_Z_M = 7201.973"
}

Copy-Item $staged $current -Force

Write-Host ""
Write-Host "============================================================"
Write-Host "CHESTERWORLD REGIONAL PLACEMENT ACTIVATED"
Write-Host "============================================================"
Write-Host "Regional Lua tiles: $tileCount"
Write-Host "CENTER_X_M: 6347.889"
Write-Host "CENTER_Z_M: 7201.973"
Write-Host "North: -Z"
Write-Host "South: +Z"
Write-Host "East: +X"
Write-Host "West: -X"
Write-Host ""
Write-Host "Backup:"
Write-Host $backup
Write-Host ""
Write-Host "Let Rojo sync, then press Play."
Write-Host "First test: X/debug return -> 9th & Kerlin."
Write-Host "============================================================"
