# Exit 6 citywide reconstruction — rollout

## Why this exists
A building can be close to its original county footprint yet have the wrong storefront edge, mislabeled business, disconnected gameplay anchor, or a speculative shape. Stop fixing isolated signs and stores by searching UI names. Apply a consistent, source-traceable correction pipeline to all 102 tiles.

## Existing work to integrate (NOT blindly merge)
- Draft PR #4, branch `feature/chester-reconstruction-pilot`: 47 OSM polygons, 36 high-threshold matches, 10 review, 1 unmatched at 9th/Kerlin, opt-in noncolliding geometry preview, HouseKit roofs and walls.
- Existing `World/RealBuildings.lua`: shops can already carry street-front bearings and stable county building IDs. Keep those IDs stable.
- Original street index & building tiles are in the 3-studs/m source projection, world +X east / -Z north; source geometry coordinates must use exactly the project transform.
- Never infer exact front doors, business names, building height, or roof shapes solely from an OSM footprint.

## Workstream and gates
1. **Audit and manifest:** For every building, capture source polygon/county ID, existing placement, matching confidence, business names, entrance edge(s), road/sidewalk relation, corner status and confidence. Record evidence/attribution and unresolved cases. Produce machine-readable conflicts per tile.
2. **Frontage:** Use verified address, street imagery, entrance evidence and road relation to select side. A corner business may have two front faces. Do not use nearest road alone as ground truth.
3. **Geometry:** Rebuild only approved geometry within parcel polygon, ground-matched, with collision checks and no road overlap. Preserve indoor/shop links via stable ID.
4. **Named anchor corrections:** J&S at 9th/Kerlin/Concord is a **front lot placement in front of Boost Mobile and 5 Points Deli, facing W 9th**, not alongside or behind. Record parcel polygon and explicit coordinates; no hardcoded guessed marker. Check Cashing faces W 9th as an attached but independently interactive business. Street signs and light poles require sidewalk clearance.
5. **Progressive rollout:** 9th/Kerlin pilot; then district batches, never swap the entire 102-tile city without geometry and gameplay tests.
6. **Performance:** Part budgets, loading milestones, StreamingEnabled, network/physics impact, Xbox driving and business prompts. Reject improvements that make city startup hang.
7. **Bike Life:** Preserve bikes, quads, car garage, profile, phone, reputation gates and existing terrain. Building reconstruction is not a road/highway work restart.

## New audit: status and use
`src/server/World/BuildingFrontageAudit.server.luau` is a **read-only opt-in diagnostic** and does NOT automatically repair frontages.

In Studio, with this branch Rojo-synced, set Workspace boolean attribute `CW_FrontageAudit` to `true` before Play, then review Output `[CW FrontageAudit]`. It checks existing tagged shops/gas stations, measures whether storefront anchors point toward the nearest generated named road, and prints at most 80 suspicious candidates with building IDs and X/Z. It treats a wrong-facing nearest road as **review needed**, not a verified error (corner stores may face a different named road). Attribute absent/false incurs no scan.

## Status
- Pilot geometry and matching lives on separate draft branch and is not merged into the playable game.
- This branch has the read-only audit, but **has not executed in Roblox Studio** and no citywide replacements are approved.
- Exact business-to-parcel assignments and verified storefront-facing images remain to be collected/checked before automatic repairs.
