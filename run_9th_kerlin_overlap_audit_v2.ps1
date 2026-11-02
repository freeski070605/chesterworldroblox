$ErrorActionPreference = "Stop"

Set-Location "E:\code\chesterworld-roblox"

py .\tools\audit_9th_kerlin_overlap_v2.py

if ($LASTEXITCODE -ne 0) {
    throw "9th & Kerlin overlap audit V2 failed."
}
