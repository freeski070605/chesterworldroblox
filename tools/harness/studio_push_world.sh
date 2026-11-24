#!/bin/sh
# Rojo plugin disconnected? Build src/server/World as a model into Studio's
# content folder; then run the sync snippet in tools/harness/studio_sync_world.luau
# with the Studio MCP (execute_luau, Edit) to copy changed sources in.
set -e
cd "$(dirname "$0")/../.."
mkdir -p build/studio_patch
printf '{"name": "WorldPatch", "tree": {"$path": "../../src/server/World"}}' > build/studio_patch/world.project.json
rojo build build/studio_patch/world.project.json -o build/studio_patch/WorldPatch.rbxm
for d in "$LOCALAPPDATA"/Roblox/Versions/*/; do
  if [ -f "$d/RobloxStudioBeta.exe" ]; then mkdir -p "$d/content/chesterpatch"; cp build/studio_patch/WorldPatch.rbxm "$d/content/chesterpatch/"; echo "copied to $d"; fi
done
