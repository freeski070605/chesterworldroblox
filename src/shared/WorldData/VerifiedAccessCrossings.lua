-- Verified vehicle access points that are not OSM ways (AccessCrossings).
-- Mapped OSM surface-parking polygons are read from ParkingSurfaceData; the
-- entries here are lots the game uses that OSM does not map as parking.
-- Points are on the street sidewalk centre line, in studs.

return {
	{
		-- J&S / Boost Mobile / 5 Points Market front lot (county building
		-- 93584), home of Exit 6 Motors. DVRPC 2025 orthophoto
		-- (build/aerial/js_lot_93584.png): the lot pavement meets the
		-- Concord Ave sidewalk along its whole NE frontage. Point = Concord
		-- south sidewalk (tools/harness/probes/js_lot_fit.py) opposite the
		-- dealership test-ride spawn.
		id = "JS_LOT_CONCORD",
		street = "Concord",
		point = { 2951.0, 1547.0 },
		width = 18,
	},
	{
		-- Same lot, Kerlin St frontage (Kerlin east sidewalk, js_lot_fit.py).
		id = "JS_LOT_KERLIN",
		street = "Kerlin",
		point = { 2855.3, 1574.0 },
		width = 16,
	},
}
