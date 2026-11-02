$ErrorActionPreference = "Stop"
Set-Location "E:\code\chesterworld-roblox"
py .\tools\audit_realworld_cleanup_pass1.py
if ($LASTEXITCODE -ne 0) { throw "Real-world cleanup pass 1 failed." }
