-- Designed vertical profiles for street spans whose county source records
-- carry no bridge tag although the street crosses a valley on a structure.
--
-- TileBuilderV2 samples Terrain for every road, sidewalk and centre-line
-- strip. Inside a span listed here, strips of the named street sample this
-- profile instead: a straight chord between the measured terrain heights at
-- the two bank anchors. The street is generated on the structure from the
-- start, so no steep sliver is omitted, sidewalks and paint follow the same
-- elevations, and LocalBridgeDressing supplies the visual deck and supports.
--
-- Anchors are points ON the source centre line, in source metres. Each
-- profile is applied only when the chord between anchors stays within
-- maxGrade and is not below the terrain at any sample along it; otherwise the
-- street keeps following Terrain and the builder reports the rejection.

return {
	{
		id = "KERLIN_CHESTER_CREEK",
		-- Kerlin St crossing the Chester Creek floodplain at Crozer Park,
		-- between its south bank crest and the level north bank toward
		-- Upland St. County records county:14366 (t=0.625) and county:1362
		-- (t=0.30) carry bridge=false; the DEM floor sits at -3 to -4 studs,
		-- with creek water at +1 to +4, about 16 studs below both banks.
		street = "kerlin",
		startM = { 6735.761, 7734.434 },
		finishM = { 6696.820, 7809.523 },
		corridorHalfWidthStuds = 30,
		maxGrade = 0.06,
	},
}
