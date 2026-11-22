# W 9th Street, Lincoln to Concord/five-point junction

The county polygon intersection envelope is longitude -75.37465 to -75.37020,
latitude 39.84720 to 39.84870. It includes both W 9th frontages and their
adjoining 8th-to-10th blocks. The reproducible 68-OBJECTID list, footprint
centres, local photo paths and review status are in `9th_kerlin_footprints.csv`.
`tools/reconstruction/kerlin_neighborhood.py` rebuilds that list and the runtime
`NeighborhoodScope.lua` from the county GeoJSON. It uses polygon intersection,
not a tenant-name search. Existing county footprints and all 102 world tiles
remain the placement source.

Full-size Google building photos were visually screened in four neighborhood
contact sheets alongside a 2025 DVRPC aerial overlay of the county footprints.
The sheets were temporary private reference files. Every changed ID has its
specific local image path and confidence in `BuildingReviewOverrides.lua`.
`medium` records a visible type/material/porch match where the single view does
not prove all sides or individual-unit details. Photo-reviewed buildings use
fixed source-matched finishes and forms in both server and client house kits;
unreviewed IDs keep their tile footprint and get `ReconstructionStatus=unverified`.

## Applied to the live world

- 42 buildings: 32 residential structures, two named storefront structures
  (147448 and 93584), three garage structures (23871, 97558, 44085), one
  other commercial structure (28482), and four institutional structures
  (25111, 82905, 20046, 17618). The three sections of 97558 get separate
  roll-up bays and upper windows, matching its mixed-use frontage.
- 147448 is the 900 W 9th / Lincoln corner parcel. The 2024 photograph shows
  **777 Food Market**, its door toward W 9th and an opaque side wall. The
  conflicting older Sherllynn building sign is removed; the existing 777 store
  gameplay section and stable ID remain.
- 93584 is the county footprint of the five-point strip. Its photographed
  white side wall, glazed front, sign/front direction and lack of a projecting
  metal canopy are applied. The 2020 photo cannot distinguish the Boost and
  J&S unit doors, so their existing gameplay sections are retained.
- Exit 6 Motors uses the paved frontage at source metres (7381, 6660), east of
  93584 and south of W 9th in the 2025 aerial, facing the street. Its old
  unrelated free-lot fallback is removed. The placement refuses to overlap a
  generated building and reports `J&S-front-unavailable` if the forecourt is
  obstructed at runtime. This is one reconstructed parking/dealer lot layout.

## Remaining evidence limits

14 IDs have a local image, but the available view is obstructed, covers a
neighbor or rear, or cannot establish a per-building facade or tenant door:
33881, 185789, 20571, 158068, 107445, 191030, 170780,
58063, 133503, 156812, 415, 50221, 154877, 113749.
The station views among these remain in their existing builders.

12 IDs have no local building photo: 161384, 84792, 128777, 171786, 6108,
120546, 40756, 92299, 194208, 157435, 203535, 91150. Several are tiny
county outbuilding polygons. No parcel GIS was supplied for vacant-lot legal
boundaries, so those boundaries are not asserted from pixels in the aerial.

## Studio check

Run from the existing 9th/Kerlin spawn. Walk both sides of W 9th from Lincoln
to Concord, and the adjoining side streets. Inspect 147448's W 9th door and
opaque Lincoln wall, 97558's garage bays, the porch rows and Exit 6 Motors in
front of 93584. Confirm `Workspace.CW_Exit6DealershipPlacement` reads `J&S-front`,
then enter the 777 and five-point stores and use a rental door. Check no car
route or sidewalk is blocked at the dealer forecourt. Studio/Xbox was not run
in this source checkout.
