# Kerlin Street / I-95 topology correction

Date: 2026-11-04. Scope: one crossing in `tile_r07_c07`. The source audit is
`E:\ChesterWorld\Data\HighwayReference\audit\kerlin_audit.md`; the crossing
inventory is `highway_crossing_audit.csv` in that directory. The pre-edit
checkpoint is `tools/backups/kerlin_topology_20261104_080846/` with a SHA-256
manifest and copies of the exporter, runtime builder, and the already modified
working tile. No terrain, DEM, heightmap, source GIS, place file, spawn, or
other tile was edited.

## Source facts and classification

The county regional tile source is
`E:\ChesterWorld\Data\18_RegionalTiles_StreetV3\Tiles\tile_r07_c07.json`.
The same eight OBJECTIDs and shared WGS84 endpoints were independently
confirmed in `E:\ChesterWorld\Data\18_StreetSystemV3\regional_motor_roads_v3.geojson`.
The reference inventory identifies **I-95 over Kerlin Street**. The county
fields `St_PosTyp=Underpass` and `LSt_Type=UPAS` label the **Kerlin** source
features 27163 and 20771. Those fields do not name the road above. County
`fr_zlev/to_zlev` is retained as source context; it is not a measured Roblox Y
or a safe numeric deck offset. None of the eight source features has an
explicit OSM bridge/tunnel value at this crossing.

| County OBJECTID | Source record | Old export | New export |
| --- | --- | --- | --- |
| 424, 425 | I-95 northbound side; `LSt_Name=I95`, z-level 0→0 | `g0`, bridge=false, shared north node with Kerlin | Same road data and default north node; upper role recorded in `grade_separations` |
| 423, 426 | I-95 southbound side; `LSt_Name=I95`, z-level 0→0 | `g0`, bridge=false, shared south node with Kerlin | Same road data and default south node; upper role recorded. Existing exported `secondary` class and 12 m width remain on this side |
| 2758 | Kerlin north approach, z-level 0→1 | `g0`, north node shared with I-95 | North endpoint in `KERLIN_I95:lower`; approach to 12th remains on default node |
| 27163 | Kerlin underpass, `Underpass/UPAS`, z-level 1→1 | `g0`, north node shared with I-95 | North endpoint in `KERLIN_I95:lower`; junction label normalized to `Kerlin` |
| 20771 | Kerlin underpass, `Underpass/UPAS`, z-level 1→1 | `g0`, south node shared with I-95 | South endpoint in `KERLIN_I95:lower`; junction label normalized to `Kerlin` |
| 20770 | Kerlin south approach, z-level 1→0 | `g0`, south node shared with I-95 | South endpoint in `KERLIN_I95:lower`; continuation toward tile boundary remains on default node |

All eight road features still have `layer=0`, `bridge=false`, and
`tunnel=false`. Their **topological** roles are upper/lower; their physical
vertical geometry remains **unmeasured and unresolved**. No Y, ramp, deck,
underside, or clearance was assigned.

## Changed files and generated evidence

- `tools/package_roblox_street_v4_world.py`: source-ID and endpoint-verified
  Kerlin override; emits a structured `grade_separations` record and four
  endpoint connection-group values. It fails if the source IDs, road names,
  county underpass fields, or four node memberships change.
- `src/server/World/TileBuilderV2.lua`: endpoint graph keys can carry an
  optional connection group independently of numeric layer. Trimming and
  centerline lookup use the same keys. A separate junction label prevents the
  source spelling change `Kerlin` → `Kerlin St` from creating a two-arm pad.
  Untagged roads keep their old key and rendering behavior.
- `src/shared/WorldData/Tiles/tile_r07_c07.lua`: regenerated only this module.
  Compared with the checkpoint, exactly four road lines gained endpoint
  connection metadata, the two underpass lines gained `junction_name`, and
  one `grade_separations` record was added after `roads`. All coordinates,
  widths, road classes, bridge flags, layers, buildings, and other road lines
  are byte-identical to the checkpoint.
- `tools/validate_kerlin_topology.py`: repeatable source-to-tile and graph
  validation.

The precise source joint nodes are local meters **(7019.645007, 7193.492148)**
for 424/425 against 2758/27163 and **(7011.453850, 7208.862662)** for
423/426 against 20771/20770. At 3 studs/m, +X east and -Z north, they are
approximately Roblox **(2015.268, 25.443)** and **(1990.695, -20.670)**.
The reference anchor **(2029.925, 19.862)** is a vicinity check, not a
substitute for either joint.

The exported graph now has two keys at each joint: default `g0` for the I-95
pair and `g0:KERLIN_I95:lower` for the Kerlin pair. Each pair remains
continuous, but there is no graph edge between them and no named junction
pad at those nodes. The legitimate 12th/Kerlin node at local
(7058.997, 7121.307) still combines source IDs 3389, 24221, 24732, and 2758.
Road slabs can still physically intersect at grade until verified bridge
geometry is added; this correction does not claim drivable clearance.

## Validation

| Check | Result |
| --- | --- |
| Python syntax (`py_compile`) and `git diff --check` | PASS |
| `python tools/validate_kerlin_topology.py` | PASS: two split nodes, both route continuities, 12th junction, unmeasured vertical state, generated tile matches source export |
| Existing highway export parser, read-only | PASS: 102 modules, 19,965 road segments |
| Neighboring tiles r07c06, r07c08, r06c07, r08c07 exported to temporary files and compared with working modules | PASS: byte-identical, no crossing override |
| Other inventory crossings: Highland (r05c03), Upland/Potter (r08c08), Chestnut/Melrose (r08c09) | PASS: all three generated modules byte-identical to existing working modules |
| Rojo 7.7.1 `build` to a new temporary `.rbxmx` model and `sourcemap` | PASS |
| Roblox Studio runtime geometry, terrain intrusion, and vehicle passability | NOT RUN: no live Studio measurements available |

No automated check failed. Rojo packaging does not prove the in-Studio
clearance or collision result.
The temporary Rojo model and sourcemap remain in the checkpoint directory:
automatic approval review rejected their `Remove-Item` cleanup command as
"blocked by policy". No existing Studio place file was changed.

## Exact Studio measurements before vertical geometry

1. Open the current world in Studio, run the active TileBuilderV3 path, and
   wait for `workspace.ChesterWorld.tile_r07_c07`. Do not move the 9th/Kerlin
   spawn. Record the place version and take an overhead and side screenshot.
2. At Roblox X/Z **(2015.268, 25.443)**, **(2002.581, 1.635)**,
   **(1990.695, -20.670)**, and the vicinity anchor **(2029.925, 19.862)**,
   cast vertical rays from Y=5000 toward Y=-5000 separately against Terrain,
   each `Roads` BasePart with `ChesterStreet` = `I 95`, `Kerlin`, or
   `Kerlin St`, and each `Intersections` BasePart. Record every hit Y, part
   full name, `CW_GradeGroup`, `CW_GradeLevel`, `CW_Bridge`, and
   `CW_IntersectionPad`. A ray on a single tilted road Part gives its actual
   top Y at that X/Z; the Part center Y is not the pavement top.
3. Measure along the **actual Kerlin centerline** between the two source
   joints at several X/Z samples, including the underpass midpoint. Record
   lower pavement top Y and Terrain hit Y at each. Record both I-95
   carriageway pavement top Y at their source joints and along the intended
   structure limits. If an exact endpoint ray misses a trimmed Part, inspect
   the Parts and sample a documented point on the same centerline; do not
   substitute the reference anchor.
4. Locate any existing bridge deck, abutment, or imported reference object in
   Studio. Record the surveyed/verified X/Z of both span ends and deck edges,
   actual deck top and underside Y, and source/version for those values. If
   there is no such object, report underside Y and physical span endpoints as
   **unavailable**. The inventory's 64 ft span, 101 ft width, and 14 ft 1 in
   minimum clearance do not determine a deck elevation or precise endpoints.
5. Only after upper and lower surface Y and a verified underside are
   available, calculate the opening as `underside Y - Kerlin pavement top Y`
   at matching X/Z. Check the entire opening for Terrain and collision
   intrusion, then drive both I-95 directions and Kerlin through it. Save the
   measured table and matching screenshots before any local bridge modeling.

Run this read-only Command Bar probe after step 1 to collect the separate
Terrain, road, and junction surface hits for steps 2–3:

```lua
local tile = workspace:WaitForChild("ChesterWorld"):WaitForChild("tile_r07_c07")
local points = {
    {"north_joint", 2015.268, 25.443},
    {"underpass_mid", 2002.581, 1.635},
    {"south_joint", 1990.695, -20.670},
    {"reference_anchor", 2029.925, 19.862},
}
local function hitAt(part, x, z)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = { part }
    return workspace:Raycast(Vector3.new(x, 5000, z),
        Vector3.new(0, -10000, 0), params)
end
for _, point in ipairs(points) do
    local label, x, z = point[1], point[2], point[3]
    print(label, "X", x, "Z", z)
    local terrainHit = hitAt(workspace.Terrain, x, z)
    print("Terrain Y", terrainHit and terrainHit.Position.Y or "no hit")
    for _, folderName in ipairs({ "Roads", "Intersections" }) do
        for _, part in ipairs(tile:WaitForChild(folderName):GetDescendants()) do
            if part:IsA("BasePart") then
                local street = part:GetAttribute("ChesterStreet")
                if folderName == "Intersections" or street == "I 95"
                    or street == "Kerlin" or street == "Kerlin St" then
                    local hit = hitAt(part, x, z)
                    if hit then
                        print(folderName, part:GetFullName(), "top Y", hit.Position.Y,
                            "street", street, "group", part:GetAttribute("CW_GradeGroup"),
                            "level", part:GetAttribute("CW_GradeLevel"),
                            "bridge", part:GetAttribute("CW_Bridge"),
                            "pad", part:GetAttribute("CW_IntersectionPad"))
                    end
                end
            end
        end
    end
end
```

For a verified deck object, use the same include filter with a ray **upward**
from below it at a matched X/Z to record underside Y. Record the exact part
and X/Z used. No such deck is identified in the current generated tile.

The current static tile cannot provide a bridge underside or measured
clearance. Geometry work is therefore intentionally pending those Studio
measurements.
