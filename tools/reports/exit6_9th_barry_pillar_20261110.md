# 9th Street / Commodore Barry pillar correction (2026-11-10)

The user's Play screenshot shows a tall narrow block standing on the 9th Street
carriageway near Commodore John Barry. A prior full-city Studio diagnostic of
the saved `Exit6Backup.rbxl` found the collidable instance
`Workspace.ChesterWorld.tile_r05_c05.Buildings.33123` in that road column. The
tile source placed its 2.015 m by 1.941 m footprint at `(5812.274, 5794.135)`
meters, or about `(-1606.845, 4223.514)` studs. Its generated height was
27.5 studs. The footprint center was about 10.7 studs from the 9th Street
centerline, inside the 12-stud road half-width. It extended above the
intersection pavement at about Y=55.7. This is a building source record,
not a `HighwayPier` or `BridgeSupport`.

Commit `833d005` removes only that erroneous building record from
`src/shared/WorldData/Tiles/tile_r05_c05.lua`. It does not alter Terrain,
roads, other buildings, or the saved Roblox place. A disposable Studio
one-tile preview with that source edit generated no `Buildings.33123` and
retained collidable `IntersectionAsphalt` at the footprint, 9th midpoint,
and both Barry junction endpoints (Y=55.47–55.79). Source-chain validation
and a Rojo build passed.

The early one-tile preview also showed the much larger `Buildings.70596`
overlapping this area before highway cleanup. That part was absent from the
previous completed full-city collision column, so its transient presence in
the one-tile preview is not evidence of a remaining final-scene obstruction.
The new full-city verification attempt exhausted Studio graphics memory at
45/102 tiles while other Studio windows were open. A final visual drive of
9th Street after syncing this source edit into a **copied** Terrain-bearing
test place is still required.

The working backup at `E:\RobloxStudio\Exit6Backup.rbxl` was neither saved
over nor published. Rojo remained stopped during this correction.
