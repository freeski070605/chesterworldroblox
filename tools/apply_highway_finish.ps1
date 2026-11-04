# ChesterWorld I-95, ramps and underpass rebuild / source audit
# Does NOT import, erase or modify Roblox Terrain.
$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

Write-Host ""
Write-Host "=============================================================="
Write-Host "CHESTERWORLD - I-95 OVERPASSES / UNDERPASSES / RAMP FINISH"
Write-Host "=============================================================="
Write-Host ""

$source = "E:\ChesterWorld\Data\18_RegionalTiles_StreetV3"
if (-not (Test-Path $source)) {
    throw "Missing regional road source: $source"
}

$needed = @(
    ".\tools\package_roblox_street_v4_world.py",
    ".\tools\audit_highway_export.py",
    ".\src\server\World\RoadTerrainConformer.server.lua",
    ".\src\server\World\HighwayInfrastructure.server.lua",
    ".\src\server\World\TileBuilderV2.lua",
    ".\src\server\World\TileBuilderV3.lua"
)
foreach ($path in $needed) {
    if (-not (Test-Path $path)) { throw "Missing file: $path" }
}

# The working single-owner intersection system must remain in place.
$bootstrap = Get-Content ".\src\server\Bootstrap.server.lua" -Raw
if ($bootstrap -notmatch 'TileBuilderV3') {
    throw "Expected the working TileBuilderV3 in Bootstrap. STOP."
}
if (Test-Path ".\src\server\World\IntersectionPadRefiner.server.lua") {
    throw "Obsolete intersection refiner detected. STOP."
}
$tileDir = ".\src\shared\WorldData\Tiles"
$existing = @(Get-ChildItem $tileDir -Filter "tile_r*_c*.lua" -File)
if ($existing.Count -ne 102) {
    throw "Before rebuild: expected 102 tile modules, found $($existing.Count)."
}

# Preserve an exact pre-highway source-tile snapshot.
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup = ".\tools\backups\highway_finish_$stamp"
New-Item -ItemType Directory -Force -Path $backup | Out-Null
Copy-Item -Path "$tileDir\*.lua" -Destination $backup -Force
Write-Host "Backed up the 102 existing tile modules: $backup"

py -m py_compile .\tools\package_roblox_street_v4_world.py .\tools\audit_highway_export.py
if ($LASTEXITCODE -ne 0) {
    throw "Exporter/audit Python syntax check failed."
}

# Required: the files checked into GitHub may predate the local grade export.
# Rebuild only Luau road/building data from the existing non-destructive source.
py .\tools\package_roblox_street_v4_world.py --all
if ($LASTEXITCODE -ne 0) {
    throw "Grade-aware export failed. Backup: $backup"
}

py .\tools\audit_highway_export.py
if ($LASTEXITCODE -ne 0) {
    throw "Highway source metadata audit FAILED. Backup: $backup"
}

$conformer = Get-Content ".\src\server\World\RoadTerrainConformer.server.lua" -Raw
$infrastructure = Get-Content ".\src\server\World\HighwayInfrastructure.server.lua" -Raw
$builder = Get-Content ".\src\server\World\TileBuilderV2.lua" -Raw

foreach ($token in @("CW_RampProfiled", "crossingChecks", "CW_RoadConformComplete")) {
    if ($conformer -notmatch [regex]::Escape($token)) {
        throw "Conformer missing $token"
    }
}
foreach ($token in @("CW_HighwayFinishComplete", "lowClearance", "tunnelObstructions")) {
    if ($infrastructure -notmatch [regex]::Escape($token)) {
        throw "Infrastructure runtime missing $token"
    }
}
if ($builder -notmatch 'CW_GradeGroup' -or $builder -notmatch 'MarkingType') {
    throw "Builder not exporting grade ownership into lane markings"
}

Write-Host ""
Write-Host "=============================================================="
Write-Host "HIGHWAY SOURCE / FILE AUDIT: PASS"
Write-Host "=============================================================="
Write-Host "Working 9th/Kerlin intersection builder: PRESERVED"
Write-Host "Regional terrain: UNCHANGED"
Write-Host "Grade-aware tiles: 102"
Write-Host "Tile backup: $backup"
Write-Host ""
Write-Host "IMPORTANT in Roblox Studio (while STOPPED):"
Write-Host '  workspace:SetAttribute("CW_QuickStreetPreview", false)'
Write-Host ""
Write-Host "Sync Rojo and start a fresh FULL Play session."
Write-Host "Look for:"
Write-Host "  [ChesterWorld RoadTerrainConformer] ... rampParts=... crossingChecks=..."
Write-Host "  [ChesterWorld HighwayFinish] ... crossings=... lowClearance=... tunnelObstructions=..."
Write-Host ""
Write-Host "Any lowClearance or tunnelObstructions above zero REQUIRE review."
