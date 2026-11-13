# EXIT 6 — bake native GIS water once in Roblox Studio

The first live test finished: 52 water modules, 151,079 Terrain patches, 14.67M
water voxels. The 91.4-second water phase need not repeat on each new server
once verified water is baked into the saved Roblox place.

## Procedure (save an original terrain backup first)

1. Update your local repo:
       cd E:\code\chesterworld-roblox
       git pull --ff-only origin main
       rojo serve default.project.json
   If Rojo is already running, restart it if needed and reconnect the Studio plugin.
2. Open the actual EXIT 6 place in Roblox Studio. STOP any Play/Run session.
3. Save a separate BACKUP copy of the place before editing the Terrain.
   This is a destructive world edit (only Air voxels are written, but the
   saved Terrain itself will change). Don't proceed without a backup.
4. In Studio's Command Bar (EDIT MODE, not Play), execute this ONE line:
       require(game.ServerScriptService.Server.World.WaterBake).Run()
   This uses the same tile modules and water-voxel writer as the runtime
   fallback; it should show [EXIT6 Water Bake] VERIFIED at the end.
   Studio must stay open during the edit. Avoid multi-line persistent commands.
5. Confirm in Edit mode with:
       require(game.ServerScriptService.Server.World.WaterBake).Status()
   Expect status=VERIFIED. Inspect the Delaware River shoreline,
   Chester Creek and visible banks. This first pass still has incomplete
   Riverfront GIS/terrain alignment and no automated riverbed excavation.
6. SAVE the place while still in Edit mode (File > Save or Ctrl+S). The
   published game is unchanged until File > Publish to Roblox is used.
7. Start Play from the saved Edit place. In Output expect:
       [EXIT6 Water] BAKED DETECTED ...
       [EXIT6 Water] BAKED VERIFIED AFTER WORLD FINISH ... savedRuntimeGeneration=true
       [EXIT6] World ready: ... waterStatus=baked-verified
   The second verification happens AFTER land clearing, landmarks and local
   bridge construction (which can modify Terrain). The loading screen waits
   for road terrain clearing, landmarks, bridges, street furniture and trees.
   There must be no [EXIT6 Water] COMPLETE ... fallback build message.
   If post-build proof fails, runtime rebuilds missing water before entry;
   do not publish until visually checked.
8. Publish only AFTER visual and gameplay tests pass. Do NOT commit a copy of
   the .rbxl terrain to GitHub unless you explicitly want an enormous binary.

## Safety
- Studio bake refuses Play/Run mode.
- It refuses a different water dataset on an already-baked place to avoid
  leaving stale waterways in the previous shoreline.
- The bake marker is set only at the END of the successful data write.
- The runtime checks a fingerprint computed from every GIS rectangle and
  multiple actual water voxels; it never skips work based on a flag alone.
- Terrain changes that remove a checked voxel invalidate the bake on startup
  and enable the original runtime fallback until you restore a valid place.
- Because native Terrain data lives inside the Studio place, a git push only
  updates code. It does not upload or publish the baked water.
- Road/highway/Industrial systems stay untouched. Steep Macdade road
  gaps and ambiguous Riverfront pavement need separate geographic repairs.
