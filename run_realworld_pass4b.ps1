$ErrorActionPreference = "Stop"

Set-Location "E:\code\chesterworld-roblox"

Write-Host ""
Write-Host "============================================================"
Write-Host "CHESTERWORLD REAL-WORLD PASS 4B"
Write-Host "CORRECTED SIDEWALKS + SMALLER INTERSECTION PADS"
Write-Host "============================================================"

$worldDir = ".\src\server\World"
New-Item -ItemType Directory -Force -Path $worldDir | Out-Null

$target = Join-Path $worldDir "StreetFinishBuilder.server.lua"

if (Test-Path $target) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupDir = ".\tools\backups\realworld_pass4b"
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

    Copy-Item `
        $target `
        (Join-Path $backupDir "StreetFinishBuilder.before_$stamp.server.lua") `
        -Force
}

Copy-Item `
    ".\tools\StreetFinishBuilder.server.lua" `
    $target `
    -Force

Write-Host ""
Write-Host "Installed corrected StreetFinishBuilder."
Write-Host "Let Rojo sync and press Play."
Write-Host ""
Write-Host "Look for:"
Write-Host "[ChesterWorld StreetFinish 4B] ..."
Write-Host ""
Write-Host "No terrain or tile rebuild required."
