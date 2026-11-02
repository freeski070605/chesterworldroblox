$ErrorActionPreference = "Stop"

Set-Location "E:\code\chesterworld-roblox"

Write-Host ""
Write-Host "================================================================"
Write-Host "CHESTERWORLD STREET SURFACE V5"
Write-Host "CONTINUOUS EDITABLEMESH ASPHALT"
Write-Host "================================================================"
Write-Host ""

py .\tools\build_street_surface_v5.py
if ($LASTEXITCODE -ne 0) {
    throw "Street Surface V5 data build failed."
}

$worldDir = ".\src\server\World"
New-Item -ItemType Directory -Force -Path $worldDir | Out-Null

$backupDir = ".\tools\backups\street_surface_v5"
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"

$oldV4 = Join-Path $worldDir "StreetSurfaceBuilder.server.lua"
if (Test-Path $oldV4) {
    Copy-Item `
        $oldV4 `
        (Join-Path $backupDir "StreetSurfaceBuilder.v4_$stamp.server.lua") `
        -Force
    Remove-Item $oldV4 -Force
}

$target = Join-Path $worldDir "StreetSurfaceMeshBuilder.server.lua"
if (Test-Path $target) {
    Copy-Item `
        $target `
        (Join-Path $backupDir "StreetSurfaceMeshBuilder.before_$stamp.server.lua") `
        -Force
}

Copy-Item `
    ".\tools\StreetSurfaceMeshBuilder.server.lua" `
    $target `
    -Force

py .\tools\audit_street_surface_v5.py
if ($LASTEXITCODE -ne 0) {
    throw "Street Surface V5 file audit failed."
}

Write-Host ""
Write-Host "================================================================"
Write-Host "STREET SURFACE V5 READY"
Write-Host "================================================================"
Write-Host ""
Write-Host "IMPORTANT BEFORE PLAY:"
Write-Host "Enable Allow Mesh / Image APIs in Experience Settings > Security."
Write-Host ""
Write-Host "No tile rebuild."
Write-Host "No terrain import."
Write-Host "No building export."
Write-Host "V3.2 stays installed underneath."
Write-Host ""
Write-Host "After Rojo sync, Play and look for:"
Write-Host "[ChesterWorld StreetSurfaceV5] ..."
