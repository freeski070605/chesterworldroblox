$ErrorActionPreference = "Stop"

Set-Location "E:\code\chesterworld-roblox"

Write-Host ""
Write-Host "============================================================"
Write-Host "CHESTERWORLD REAL-WORLD PASS 4"
Write-Host "INTERSECTIONS + SIDEWALK EDGE FINISH"
Write-Host "============================================================"

$worldDir = ".\src\server\World"
New-Item -ItemType Directory -Force -Path $worldDir | Out-Null

$target = Join-Path $worldDir "StreetFinishBuilder.server.lua"

if (Test-Path $target) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupDir = ".\tools\backups\realworld_pass4"
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
Write-Host "Installed:"
Write-Host $target
Write-Host ""
Write-Host "Let Rojo sync, then press Play."
Write-Host ""
Write-Host "Look in Output for:"
Write-Host "[ChesterWorld StreetFinish] ..."
Write-Host ""
Write-Host "No terrain re-import and no tile rebuild are required."
