# Exit 6 — J&S Lot / 9th Street Storefront Placement

Requested Nov 21, 2026. This is a building/signage placement correction only; the general roads/highways reconstruction remains paused.

## Required final layout
1. **Exit 6 Motors** must sit at the **front of the lot where J&S is**, not at its current in-world position. Put the dealership frontage/entry on the street-facing side of the J&S lot based on verified lot geometry. Relocate associated dealership sign, display vehicles and customer spawn/interactions with the storefront; remove any duplicate at the old location.
2. **Check Cashing** storefront must face **9th Street**, not Kerlin Street. Rotate/reposition the sign and storefront-facing entrance for visibility from 9th Street.
3. Check Cashing is a **separate business** from the gas station: distinct signage, entrance, interactive shop identity, and interior/interaction trigger. But it must remain **physically connected/attached to the gas station building** as part of the same connected site, not become a detached building.
4. Preserve the J&S lot layout, station pumps/access and existing street geometry. Do not block car/bike driveways, customer circulation, sidewalks, or spawn.
5. Use the actual 9th/Kerlin storefront orientation and frontage from source imagery/site geometry. Don't invent offsets, rotate the whole gas station, or claim a fix without Roblox Studio testing.

## Implementation checklist
- Inspect actual source placement scripts and asset hierarchy (J&S, Exit 6 Motors, Check Cashing, gas station).
- Determine existing anchors, parcel boundaries, 9th and Kerlin street vectors, building entrance locations.
- Apply targeted idempotent position/orientation overrides, keeping station and separate storefront as one physically joined structure.
- Update collision, signs, service prompts, dealership displays, and any map icons/navigation tied to prior anchor.
- Check from 9th street and Kerlin street; test driving into lot from both directions, on dirt bike, quad and car; validate Xbox render/streaming.
- Confirm separate Check Cashing interaction does not accidentally launch the gas station shop.

## Status
Requirements documented; **no in-world position changes verified yet**. Asset identifiers / active spawning code have not been found through current GitHub code search. Do not mark complete without implementation and inspection.
