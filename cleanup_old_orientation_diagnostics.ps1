# ChesterWorld temporary orientation diagnostics cleanup
$root = "E:\code\chesterworld-roblox"

$old = @(
    "$root\src\client\RouteProof.client.lua",
    "$root\src\client\OrientationTruthMarkers.client.lua"
)

foreach ($path in $old) {
    if (Test-Path $path) {
        Remove-Item $path -Force
        Write-Host "Removed old diagnostic: $path"
    }
}

Write-Host "Old pre-reflection route/orientation markers cleared."
