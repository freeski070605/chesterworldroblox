-- Exit 6 sports meshes (uploaded from assets/sports/*.glb).
-- `meshSize` is each uploaded mesh's MeshSize as reported by Studio
-- (AssetService:CreateEditableMeshAsync / imported MeshPart, 2026-11-25).
-- SpecialMesh renders a FileMesh at MeshSize * Scale, centred on the mesh's
-- bounding box, so builders compute Scale = wanted / meshSize and offset the
-- carrier from the bounding-box centre using the calibration below.
return {
	streetHoop = "100658647281859",
	courtPaint = "72926282853278",
	footballPaint = "127759021115688",
	bleacherSection = "118100408043489",
	-- The 560 x 260 oval's lane band (94..130 radius) does not match measured
	-- tracks; tracks are built from measured radii instead.
	sixLaneOval = "",
	sportsPalette = "",

	textures = {
		["100658647281859"] = "126867542637803",
		["72926282853278"] = "120585536734729",
		["118100408043489"] = "74507179113970",
		["73819289954224"] = "101027705159872",
		["127759021115688"] = "80747428752946",
	},

	meshSize = {
		["100658647281859"] = Vector3.new(3.785, 13.15, 6.0),
		["72926282853278"] = Vector3.new(98.154, 0.18, 58.154),
		["127759021115688"] = Vector3.new(358.205, 0.66, 158.205),
		["118100408043489"] = Vector3.new(60.0, 3.99, 9.31),
		["73819289954224"] = Vector3.new(560.11, 0.11, 260.11),
	},

	-- Street hoop, measured from the uploaded mesh's vertices (the importer
	-- turns glTF 180 deg about Y): relative to the bounding-box centre the rim
	-- centre is at (+0.7875, +3.425, 0), so the rim faces +X; the pole base
	-- is at (-1.6125, -6.575, 0). Rim height above the base is 10 studs.
	hoop = { rimOffset = Vector3.new(0.7875, 3.425, 0), baseOffset = Vector3.new(-1.6125, -6.575, 0), rimHeight = 10 },
	-- Court paint lines are centred on x = +/-49, z = +/-29; the rim (arc
	-- centre) is at x = +/-45.
	courtLines = { halfX = 49, halfZ = 29, rimX = 45 },
	-- Football paint: end lines x = +/-179, sidelines z = +/-79.
	footballLines = { halfX = 179, halfZ = 79 },
	-- Bleacher rows rise toward the mesh's -Z; the front (low) row faces +Z.
	bleacher = { frontAxis = Vector3.new(0, 0, 1) },

	-- The uploads kept Blender's primitive unwrap UVs (TEXCOORD_0) instead of
	-- the palette UVs, so their textures sample wrong colours; render plain.
	plainMeshes = true,

	pending = {
		sixLaneOval = "73819289954224",
	},
}
