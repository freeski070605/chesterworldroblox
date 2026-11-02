$ErrorActionPreference = "Stop"

Set-Location "E:\code\chesterworld-roblox"

Write-Host ""
Write-Host "================================================================"
Write-Host "CHESTERWORLD STREET SURFACE V5.4 - VISIBILITY HANDOFF FIX"
Write-Host "================================================================"
Write-Host ""

$worldDir = ".\src\server\World"
New-Item -ItemType Directory -Force -Path $worldDir | Out-Null

$target = Join-Path $worldDir "StreetSurfaceVisibilityV54.server.lua"

if (Test-Path $target) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupDir = ".\tools\backups\street_surface_v54"
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

    Copy-Item `
        $target `
        (Join-Path $backupDir "StreetSurfaceVisibilityV54.before_$stamp.server.lua") `
        -Force
}

Copy-Item `
    ".\tools\StreetSurfaceVisibilityV54.server.lua" `
    $target `
    -Force

$oldVisibility = Join-Path $worldDir "StreetSurfaceVisibility.server.lua"

if (Test-Path $oldVisibility) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupDir = ".\tools\backups\street_surface_v54"
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

    Copy-Item `
        $oldVisibility `
        (Join-Path $backupDir "StreetSurfaceVisibility.v51_$stamp.server.lua") `
        -Force

    Remove-Item $oldVisibility -Force
}

Write-Host "V5.4 visibility handoff installed."
Write-Host ""
Write-Host "No mesh rebuild."
Write-Host "No tile rebuild."
Write-Host "No terrain import."
Write-Host ""
Write-Host "Let Rojo sync and Play."
Write-Host ""
Write-Host "Look for:"
Write-Host "[ChesterWorld StreetSurfaceV5.4] ..."
