$ErrorActionPreference = "Stop"

Set-Location "E:\code\chesterworld-roblox"

Write-Host ""
Write-Host "================================================================"
Write-Host "CHESTERWORLD INTERSECTION SURFACE V6.1"
Write-Host "ENDPOINT-AWARE ROAD + SIDEWALK TRIMMING FIX"
Write-Host "================================================================"
Write-Host ""

$worldDir = ".\src\server\World"
New-Item -ItemType Directory -Force -Path $worldDir | Out-Null

$target = Join-Path $worldDir "IntersectionSurfaceBuilder.server.lua"

$backupDir = ".\tools\backups\intersection_surface_v61"
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"

if (Test-Path $target) {
    Copy-Item `
        $target `
        (Join-Path $backupDir ("IntersectionSurfaceBuilder.v6_" + $stamp + ".server.lua")) `
        -Force
}

Copy-Item `
    ".\tools\IntersectionSurfaceBuilder.server.lua" `
    $target `
    -Force

# Make absolutely sure no full-network V4/V5 runtime came back.
$remove = @(
    "StreetSurfaceBuilder.server.lua",
    "StreetSurfaceMeshBuilder.server.lua",
    "StreetSurfaceVisibility.server.lua",
    "StreetSurfaceVisibilityV54.server.lua",
    "StreetSurfaceRollback.server.lua"
)

foreach ($name in $remove) {
    $path = Join-Path $worldDir $name

    if (Test-Path $path) {
        Copy-Item `
            $path `
            (Join-Path $backupDir ($name + ".before_v61_" + $stamp)) `
            -Force
        Remove-Item $path -Force
    }
}

Write-Host ""
Write-Host "INTERSECTION SURFACE V6.1 READY"
Write-Host ""
Write-Host "No data rebuild required."
Write-Host "No terrain import."
Write-Host "No tile rebuild."
Write-Host ""
Write-Host "STOP the current Play session."
Write-Host "Let Rojo sync."
Write-Host "Start a FRESH Play session."
Write-Host ""
Write-Host "Look for:"
Write-Host "[ChesterWorld IntersectionSurfaceV6.1] ..."
