$ErrorActionPreference = "Stop"

Set-Location "E:\code\chesterworld-roblox"

Write-Host ""
Write-Host "================================================================"
Write-Host "CHESTERWORLD INTERSECTION SURFACE V6"
Write-Host "RESTORE V3.2 ROADS + SURGICAL JUNCTION REPLACEMENT"
Write-Host "================================================================"
Write-Host ""

# 1) Build source-derived intersection-only meshes.
py .\tools\build_intersection_surface_v6.py
if ($LASTEXITCODE -ne 0) {
    throw "Intersection Surface V6 data build failed."
}

# 2) Disable every experimental full-network surface runtime.
$worldDir = ".\src\server\World"
New-Item -ItemType Directory -Force -Path $worldDir | Out-Null

$backupDir = ".\tools\backups\intersection_surface_v6"
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"

$remove = @(
    "StreetSurfaceBuilder.server.lua",
    "StreetSurfaceMeshBuilder.server.lua",
    "StreetSurfaceVisibility.server.lua",
    "StreetSurfaceVisibilityV54.server.lua",
    "StreetSurfaceRollback.server.lua",
    "9thKerlinVisualAudit.server.lua"
)

foreach ($name in $remove) {
    $path = Join-Path $worldDir $name

    if (Test-Path $path) {
        Copy-Item `
            $path `
            (Join-Path $backupDir ($name + ".before_v6_" + $stamp)) `
            -Force

        Remove-Item $path -Force
        Write-Host "Disabled $name"
    }
}

# 3) Install the intersection-only runtime.
$target = Join-Path $worldDir "IntersectionSurfaceBuilder.server.lua"

if (Test-Path $target) {
    Copy-Item `
        $target `
        (Join-Path $backupDir ("IntersectionSurfaceBuilder.before_" + $stamp + ".server.lua")) `
        -Force
}

Copy-Item `
    ".\tools\IntersectionSurfaceBuilder.server.lua" `
    $target `
    -Force

# 4) Strict audit.
py .\tools\audit_intersection_surface_v6.py
if ($LASTEXITCODE -ne 0) {
    throw "Intersection Surface V6 final audit failed."
}

Write-Host ""
Write-Host "================================================================"
Write-Host "INTERSECTION SURFACE V6 READY"
Write-Host "================================================================"
Write-Host ""
Write-Host "KEPT:"
Write-Host "  V3.2 roads visible everywhere"
Write-Host "  RoadTerrainConformer"
Write-Host "  StreetSystemV3.2 sidewalks"
Write-Host ""
Write-Host "DISABLED:"
Write-Host "  all V4/V5 full-road replacement runtimes"
Write-Host ""
Write-Host "V6 only trims road/sidewalk ends at true intersections"
Write-Host "and fills those junctions with source-derived asphalt meshes."
Write-Host ""
Write-Host "Let Rojo sync, STOP current Play session, then start fresh."
Write-Host ""
Write-Host "Look for:"
Write-Host "[ChesterWorld IntersectionSurfaceV6] ..."
