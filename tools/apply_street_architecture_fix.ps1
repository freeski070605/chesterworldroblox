$ErrorActionPreference = "Stop"

Set-Location "E:\code\chesterworld-roblox"

Write-Host ""
Write-Host "================================================================"
Write-Host "CHESTERWORLD - SINGLE OWNER STREET ARCHITECTURE"
Write-Host "INTERSECTIONS + GRADE SEPARATION"
Write-Host "================================================================"
Write-Host ""

$required = @(
    ".\src\server\World\TileBuilderV2.lua",
    ".\src\server\World\RoadTerrainConformer.server.lua",
    ".\tools\package_roblox_street_v4_world.py"
)

foreach ($path in $required) {
    if (-not (Test-Path $path)) {
        throw "Required file missing: $path"
    }
}

$forbidden = @(
    ".\src\server\World\StreetFinishBuilder.server.lua",
    ".\src\server\World\IntersectionSurfaceBuilder.server.lua",
    ".\src\server\World\StreetSurfaceBuilder.server.lua",
    ".\src\server\World\StreetSurfaceMeshBuilder.server.lua",
    ".\src\server\World\StreetSurfaceVisibility.server.lua",
    ".\src\server\World\StreetSurfaceVisibilityV54.server.lua"
)

foreach ($path in $forbidden) {
    if (Test-Path $path) {
        throw "Competing runtime street owner still exists: $path"
    }
}

Write-Host "Architecture check: PASS - TileBuilderV2 is the only street geometry owner."
Write-Host ""

py -m py_compile .\tools\package_roblox_street_v4_world.py
if ($LASTEXITCODE -ne 0) {
    throw "Grade-aware exporter Python syntax check failed."
}

Write-Host "Exporter syntax check: PASS"
Write-Host ""

py .\tools\package_roblox_street_v4_world.py --all
if ($LASTEXITCODE -ne 0) {
    throw "Grade-aware 102-tile Roblox export failed."
}

$tileDir = ".\src\shared\WorldData\Tiles"
$tileModules = @(
    Get-ChildItem $tileDir -File |
        Where-Object { $_.Extension -in @(".lua", ".luau") }
)

if ($tileModules.Count -ne 102) {
    throw "Expected exactly 102 generated tile modules; found $($tileModules.Count)."
}

$bootstrap = Get-Content ".\src\server\Bootstrap.server.lua" -Raw
if ($bootstrap -notmatch 'TileBuilderV2') {
    throw "Bootstrap is not using TileBuilderV2."
}
if ($bootstrap -notmatch 'TileBuilder\.Prepare\(modules\)') {
    throw "Bootstrap does not prepare the global road graph."
}

$conformer = Get-Content ".\src\server\World\RoadTerrainConformer.server.lua" -Raw
foreach ($token in @("CW_GradeLevel", "CW_Bridge", "bridgeProfile", "bridgeGroups")) {
    if ($conformer -notmatch [regex]::Escape($token)) {
        throw "Grade-aware conformer is missing token: $token"
    }
}

$generatedText = Get-Content ($tileModules | Select-Object -First 1).FullName -Raw
if ($generatedText -notmatch 'road_class=') {
    throw "Generated Lua tile does not contain road_class metadata."
}
if ($generatedText -notmatch 'bridge=') {
    throw "Generated Lua tile does not contain bridge metadata."
}
if ($generatedText -notmatch 'layer=') {
    throw "Generated Lua tile does not contain layer metadata."
}

Write-Host ""
Write-Host "================================================================"
Write-Host "CHESTERWORLD STREET ARCHITECTURE FIX READY"
Write-Host "================================================================"
Write-Host "Tile modules: 102"
Write-Host "Street geometry owner: TileBuilderV2 ONLY"
Write-Host "Elevation owner: RoadTerrainConformer ONLY"
Write-Host "Global junction graph: ENABLED"
Write-Host "Road asphalt intersection trimming: ENABLED"
Write-Host "Duplicate arm/crosswalk filtering: ENABLED"
Write-Host "Bridge/tunnel/layer metadata: ENABLED"
Write-Host "Grade-separated intersection keys: ENABLED"
Write-Host ""
Write-Host "Let Rojo sync. Stop any active Play session and start fresh."
Write-Host "Look for:"
Write-Host "  [ChesterWorld TileBuilderV2] prepared global road graph: ..."
Write-Host "  [ChesterWorld RoadTerrainConformer] ... bridgeGroups=... bridgeParts=... tunnelParts=..."
