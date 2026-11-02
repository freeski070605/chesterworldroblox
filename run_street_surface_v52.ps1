$ErrorActionPreference = "Stop"
Set-Location "E:\code\chesterworld-roblox"
$worldDir = ".\src\server\World"
New-Item -ItemType Directory -Force -Path $worldDir | Out-Null
$backupDir = ".\tools\backups\street_surface_v52"
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$meshTarget = Join-Path $worldDir "StreetSurfaceMeshBuilder.server.lua"
if (Test-Path $meshTarget) {
    Copy-Item $meshTarget (Join-Path $backupDir "StreetSurfaceMeshBuilder.before_$stamp.server.lua") -Force
}
Copy-Item ".\tools\StreetSurfaceMeshBuilder.server.lua" $meshTarget -Force
$visibility = Join-Path $worldDir "StreetSurfaceVisibility.server.lua"
if (Test-Path $visibility) {
    Copy-Item $visibility (Join-Path $backupDir "StreetSurfaceVisibility.v51_$stamp.server.lua") -Force
    Remove-Item $visibility -Force
}
$oldV4 = Join-Path $worldDir "StreetSurfaceBuilder.server.lua"
if (Test-Path $oldV4) {
    Copy-Item $oldV4 (Join-Path $backupDir "StreetSurfaceBuilder.v4_$stamp.server.lua") -Force
    Remove-Item $oldV4 -Force
}
Write-Host ""
Write-Host "STREET SURFACE V5.2 READY"
Write-Host "No mesh-data rebuild. No tile rebuild. No terrain import."
Write-Host "Let Rojo sync and Play."
Write-Host "Look for: [ChesterWorld StreetSurfaceV5.2] ..."
