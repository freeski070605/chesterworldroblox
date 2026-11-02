$ErrorActionPreference = "Stop"

Set-Location "E:\code\chesterworld-roblox"

$worldDir = ".\src\server\World"
New-Item -ItemType Directory -Force -Path $worldDir | Out-Null

$target = Join-Path $worldDir "StreetSurfaceVisibility.server.lua"

if (Test-Path $target) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupDir = ".\tools\backups\street_surface_v51"
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

    Copy-Item `
        $target `
        (Join-Path $backupDir "StreetSurfaceVisibility.before_$stamp.server.lua") `
        -Force
}

Copy-Item `
    ".\tools\StreetSurfaceVisibility.server.lua" `
    $target `
    -Force

Write-Host ""
Write-Host "STREET SURFACE V5.1 VISIBILITY HANDOFF READY"
Write-Host "No tile rebuild. No terrain import. No mesh rebuild."
Write-Host "Let Rojo sync and Play."
Write-Host ""
Write-Host "Look for:"
Write-Host "[ChesterWorld StreetSurfaceV5.1] ..."
