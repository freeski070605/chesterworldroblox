# Exit 6 integration instructions — Bike Life branch

## Implemented in source
- StreetFurniture: curb placement for street blades and light poles, eliminate unsafe traffic-signal road fallback, attach name blades to nearby generated light/signal poles.
- GasStationBuilder: 9th-facing check-cashing facade selected from nearby generated 9th Street road parts; separate tagged business/anchor inside the still-connected gas station structure.
- Exit6Vehicles: removes automatic random unrelated lot placement for Exit 6 Motors. Requires a precise J&S frontage anchor.

## J&S placement requirement
The repository's presently checked-in city data does not identify which model/lot is J&S. Rather than guess a random coordinate that might block a road or gas-pump driveway, place an **anchored BasePart** named exactly `Exit6JSLotFront` in Workspace from Studio at the front-center of the verified J&S lot:
- Transform: center at the desired dealership lot ground plane, local -Z facing the street.
- Size at least 1,1,1; Transparency 1; CanCollide false; CanQuery false.
- The dealership footprint currently occupies 64 x 46 studs centered on this CFrame. Check it fits the actual lot before publishing.
- The dealer now reports `CW_Exit6DealershipStatus=J&S-front-marker-missing` and spawns nothing if the marker is missing; this is deliberate, safer than putting the business on the wrong property.
- Anchor must persist in the Studio place file and not be overwritten by Rojo mapping. Set after opening the place or place it in a persisted Studio source asset.

## Test
1. Rojo sync this branch into your test place; do not publish to production yet.
2. Check Output for script errors and status flags `CW_StreetFurnitureComplete`, `CW_GasStationsComplete` and `CW_Exit6DealershipStatus`.
3. Drive around 9th/Concord and 9th/Kerlin. All poles and street-name blades must be clear of lanes; streetlight specifically should be on the sidewalk across from the sign (verify actual corner side).
4. Inspect Check Cashing from 9th and Kerlin. Ensure sign faces 9th, its business interaction differs from the gas station, and no shop wall clips the station.
5. Add the correct J&S marker. Check 64x46 footprint does not obstruct roads, neighboring buildings, stations or lot approaches. Dealership should register once.
6. Xbox verification, StreamingEnabled reload and regression test of old car calling/fuel and phone.

## Limitations
The local J&S frontage was not inferable from reliable repository geography. No live Roblox Studio/Xbox test has been performed. These are source patches, not confirmation of the finished scene. Bike Life ride physics are not implemented by these placement commits.
