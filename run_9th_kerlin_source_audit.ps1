$ErrorActionPreference = "Stop"

Set-Location "E:\code\chesterworld-roblox"

Write-Host ""
Write-Host "============================================================"
Write-Host "CHESTERWORLD - 9TH & KERLIN SOURCE ROAD AUDIT"
Write-Host "============================================================"
Write-Host ""

py .\tools\audit_9th_kerlin_source_roads.py

if ($LASTEXITCODE -ne 0) {
    throw "9th & Kerlin source road audit failed."
}
