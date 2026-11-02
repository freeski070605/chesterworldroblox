$ErrorActionPreference = "Stop"
Set-Location "E:\code\chesterworld-roblox"
Write-Host ""
Write-Host "============================================================"
Write-Host "CHESTERWORLD REAL-WORLD PASS 2"
Write-Host "============================================================"
py .\tools\build_realworld_roads_v2.py
if ($LASTEXITCODE -ne 0) { throw "Road pass failed." }
py .\tools\prepare_realworld_regional_packager.py
if ($LASTEXITCODE -ne 0) { throw "Packager prep failed." }
py .\tools\package_regional_world_tiles_realworld.py
if ($LASTEXITCODE -ne 0) { throw "Real-world tile package failed." }
py .\tools\audit_realworld_tiles.py
if ($LASTEXITCODE -ne 0) { throw "Real-world tile audit failed." }
Write-Host ""
Write-Host "IMPORTANT: Current Roblox Lua tiles were NOT replaced."
Write-Host "This pass staged the corrected regional JSON tile set only."
