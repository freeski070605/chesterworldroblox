-- EXIT 6 wardrobe: every wearable the city sells, built from the original
-- meshes in Exit6WearMeshes (tools/assets/build_wearables.py). Exit6Catalog
-- merges these into Catalog.Items (kind "wear"); Exit6Style fits the pieces on
-- the character; the shop and the phone Closet read the same table.
--
-- item = { name, price, slot, store, pieces = { { mesh, role[, alpha] } },
--          colors = { role = {r,g,b} }, tall?, hidesHair?, showsUnderCap? }
-- roles pick material + colour: main / trim / sole / hair / fade / metal / gem / lens
local Wardrobe = {}

Wardrobe.Slots = { "hair", "facialHair", "hat", "top", "bottom", "shoes", "chain", "neck", "watch", "bracelet", "ears", "eyes" }
Wardrobe.SlotNames = {
	hair = "Hair", facialHair = "Facial Hair", hat = "Headwear", top = "Top", bottom = "Bottoms", shoes = "Shoes", chain = "Chain",
	neck = "Neck", watch = "Watch", bracelet = "Bracelet", ears = "Earrings", eyes = "Eyewear",
}

-- material per role (colour comes from the item)
Wardrobe.Roles = {
	main = { material = Enum.Material.Fabric },
	trim = { material = Enum.Material.SmoothPlastic },
	sole = { material = Enum.Material.SmoothPlastic },
	hair = { material = Enum.Material.Fabric },
	fade = { material = Enum.Material.SmoothPlastic, alpha = 0.55 },
	metal = { material = Enum.Material.Foil },
	gem = { material = Enum.Material.Glass, reflectance = 0.25 },
	lens = { material = Enum.Material.Glass, reflectance = 0.35 },
	-- premium roles: `surface` names a PBR SurfaceAppearance set
	-- (ServerStorage.Exit6ProductionAssets.Surfaces) that Exit6Style clones onto
	-- premium meshes (which carry UVs + tangents) and tints with the role colour;
	-- `material` is the fallback when the set is missing or the mesh is a base one
	shell = { material = Enum.Material.SmoothPlastic, surface = "nylon" },
	fleece = { material = Enum.Material.Fabric, surface = "fleece" },
	accent = { material = Enum.Material.Fabric, surface = "fleece" },
	knit = { material = Enum.Material.Fabric, surface = "knit" },
	lace = { material = Enum.Material.Fabric, surface = "knit" },
	stitch = { material = Enum.Material.Fabric, surface = "knit" },
	leather = { material = Enum.Material.Leather, surface = "leather" },
	overlay = { material = Enum.Material.Leather, surface = "leather" },
	mark = { material = Enum.Material.Leather, surface = "leather" },
	rubber = { material = Enum.Material.Rubber, surface = "rubber" },
	ice = { material = Enum.Material.Glass, reflectance = 0.2, surface = "pave" },
	silver = { material = Enum.Material.Foil, surface = "metal" },
	locs = { material = Enum.Material.Fabric, surface = "locs" },
}

local HAIR = { 22, 17, 14 }
local GOLD, SILVER, ICE = { 222, 178, 72 }, { 200, 204, 210 }, { 214, 236, 248 }

local Items = {}
Wardrobe.Items = Items
local function item(id, def) Items[id] = def end

-- ---------------------------------------------------------------- hair (barbershop)
local function cut(id, name, price, pieces, extra)
	local def = { name = name, price = price, slot = "hair", store = "barber", colors = { hair = HAIR }, pieces = pieces }
	for k, v in pairs(extra or {}) do def[k] = v end
	item("hair_" .. id, def)
end
local function H(mesh) return { mesh = mesh, role = "hair" } end
local function F(mesh, a) return { mesh = mesh, role = "fade", alpha = a } end
cut("sharp_low_taper", "Low Taper + Line-Up", 20, { H("hair_sharp_low_taper"), F("fade_sharp_low_taper", 0.5) }, { showsUnderCap = true })
cut("mid_skin_fade", "Mid Skin Fade", 25, { H("hair_mid_skin_fade"), F("fade_mid_a", 0.45), F("fade_mid_b", 0.75) }, { showsUnderCap = true })
cut("waves_360", "360 Waves", 30, { H("hair_waves_360"), F("fade_waves", 0.5) }, { showsUnderCap = true })
cut("high_top_fade", "High-Top Fade", 35, { H("hair_high_top_fade"), F("fade_high_a", 0.45), F("fade_high_b", 0.75) }, { tall = true })
cut("afro_taper", "Afro Taper", 35, { H("hair_afro_taper"), F("fade_afro", 0.5) }, { tall = true })
cut("starter_locs", "Starter Locs", 40, { H("hair_starter_locs") }, { tall = true })
cut("two_strand_twists", "Two-Strand Twists", 40, { H("hair_two_strand_twists") }, { tall = true })
cut("medium_locs", "Medium Locs", 55, { H("hair_medium_locs") }, { showsUnderCap = true })
cut("shoulder_locs", "Shoulder Locs", 70, { H("hair_shoulder_locs") }, { showsUnderCap = true })
cut("cornrows", "Cornrows", 45, { H("hair_cornrows") }, { showsUnderCap = true })
cut("box_braids", "Box Braids", 65, { H("hair_box_braids") }, { showsUnderCap = true })
cut("braided_ponytail", "Braided Ponytail", 55, { H("hair_braided_ponytail") }, { showsUnderCap = true })
cut("high_bun", "High Puff Bun", 45, { H("hair_high_bun") }, { tall = true })
cut("space_buns", "Space Buns", 45, { H("hair_space_buns") }, { tall = true })
cut("long_silk_press", "Long Silk Press", 60, { H("hair_long_silk_press") }, { showsUnderCap = true })
item("hair_bald", { name = "Clean Shave", price = 15, slot = "hair", store = "barber", pieces = {}, bald = true })

-- ---------------------------------------------------------------- tops
local function P(mesh, role) return { mesh = mesh, role = role or "main" } end
local SLEEVES = { P("sleeve_upper"), P("sleeve_lower") }
local function top(id, name, price, pieces, main, trim, extra)
	local def = { name = name, price = price, slot = "top", store = "clothing", pieces = pieces,
		colors = { main = main, trim = trim } }
	for k, v in pairs(extra or {}) do def[k] = v end
	item(id, def)
end
local TEE = { P("tee_torso"), P("tee_sleeve") }
top("w_tee_white", "White Tee", 15, TEE, { 236, 236, 232 })
top("w_tee_black", "Black Tee", 15, TEE, { 26, 26, 28 })
top("w_tee_red", "Red Tee", 15, TEE, { 160, 24, 32 })
top("w_tank_white", "White Tank", 12, { P("tee_torso") }, { 238, 238, 234 })
local HOODIE = { P("hoodie_torso"), SLEEVES[1], SLEEVES[2] }
top("w_hoodie_black", "Black Hoodie", 45, HOODIE, { 24, 24, 27 }, nil, { depth = 0.03 })
top("w_hoodie_grey", "Heather Grey Hoodie", 45, HOODIE, { 132, 132, 138 }, nil, { depth = 0.03 })
top("w_hoodie_navy", "Navy Hoodie", 45, HOODIE, { 28, 40, 72 }, nil, { depth = 0.03 })
local TRACK = { P("track_torso"), P("track_trim_torso", "trim"), SLEEVES[1], SLEEVES[2],
	P("track_trim_upper", "trim"), P("track_trim_lower", "trim") }
top("w_track_navy", "Navy Track Jacket", 70, TRACK, { 26, 34, 66 }, { 236, 236, 236 })
top("w_track_black", "Black Track Jacket", 70, TRACK, { 22, 23, 27 }, { 236, 236, 236 })
top("w_track_red", "Red Track Jacket", 70, TRACK, { 150, 26, 34 }, { 236, 236, 236 })
top("w_track_grey", "Grey Zip Jacket", 65, TRACK, { 140, 140, 146 }, { 230, 230, 230 })
local PUFFER = { P("puffer_torso"), P("puffer_upper"), P("puffer_lower") }
top("w_puffer_black", "Black Puffer", 120, PUFFER, { 30, 32, 36 }, nil, { depth = 0.08 })
top("w_puffer_red", "Red Puffer", 120, PUFFER, { 150, 28, 34 }, nil, { depth = 0.08 })
top("w_puffer_olive", "Olive Puffer", 120, PUFFER, { 74, 80, 52 }, nil, { depth = 0.08 })

-- ---------------------------------------------------------------- bottoms
local function bottom(id, name, price, pieces, main, trim)
	item(id, { name = name, price = price, slot = "bottom", store = "clothing", pieces = pieces,
		colors = { main = main, trim = trim } })
end
-- the waistband slims under any top so it never shows past the hem
local WAIST = { mesh = "pants_waist", role = "main", underTop = true }
local JOGGERS = { WAIST, P("pants_upper"), P("jogger_lower") }
bottom("w_joggers_black", "Black Joggers", 35, JOGGERS, { 26, 26, 30 })
bottom("w_joggers_grey", "Grey Joggers", 35, JOGGERS, { 124, 124, 130 })
local JEANS = { WAIST, P("pants_upper"), P("jeans_stacked_lower") }
bottom("w_jeans_blue", "Stacked Jeans", 45, JEANS, { 52, 72, 112 })
bottom("w_jeans_black", "Black Stacked Jeans", 45, JEANS, { 30, 31, 36 })
local TRACKP = { WAIST, P("pants_upper"), P("jogger_lower"), P("leg_trim_upper", "trim"), P("leg_trim_lower", "trim") }
bottom("w_trackpants_navy", "Navy Track Pants", 50, TRACKP, { 26, 34, 66 }, { 236, 236, 236 })
bottom("w_trackpants_black", "Black Track Pants", 50, TRACKP, { 22, 23, 27 }, { 236, 236, 236 })
bottom("w_shorts_black", "Black Hoop Shorts", 25, { WAIST, P("shorts_upper") }, { 24, 24, 28 })
bottom("w_shorts_red", "Red Hoop Shorts", 25, { WAIST, P("shorts_upper") }, { 150, 26, 34 })

-- ---------------------------------------------------------------- shoes
local function shoes(id, name, price, pieces, main, sole)
	item(id, { name = name, price = price, slot = "shoes", store = "clothing", pieces = pieces,
		colors = { main = main, sole = sole } })
end
local SNEAKER = { P("sneaker_upper"), P("sneaker_sole", "sole") }
shoes("w_sneakers_white", "Triple White Low-Tops", 60, SNEAKER, { 240, 240, 236 }, { 244, 244, 240 })
shoes("w_sneakers_black", "Black Low-Tops", 60, SNEAKER, { 26, 26, 30 }, { 238, 238, 234 })
shoes("w_sneakers_red", "Red Low-Tops", 65, SNEAKER, { 160, 26, 34 }, { 240, 240, 236 })
local BOOT = { P("boot_upper"), P("boot_sole", "sole") }
shoes("w_boots_wheat", "Wheat Work Boots", 90, BOOT, { 196, 148, 82 }, { 70, 50, 36 })
shoes("w_boots_black", "Black Work Boots", 90, BOOT, { 30, 30, 32 }, { 26, 26, 28 })

-- ---------------------------------------------------------------- headwear
local function hat(id, name, price, pieces, main, trim, extra)
	local def = { name = name, price = price, slot = "hat", store = "clothing", pieces = pieces,
		colors = { main = main, trim = trim } }
	for k, v in pairs(extra or {}) do def[k] = v end
	item(id, def)
end
local CAP = { P("cap_fitted"), P("cap_emblem", "trim") }
hat("w_cap_red", "Red Fitted (6)", 30, CAP, { 166, 26, 34 }, { 240, 240, 236 }, { cap = true })
hat("w_cap_black", "Black Fitted (6)", 30, CAP, { 24, 24, 28 }, { 222, 178, 72 }, { cap = true })
hat("w_cap_navy", "Navy Fitted (6)", 30, CAP, { 26, 36, 70 }, { 240, 240, 236 }, { cap = true })
hat("w_beanie_black", "Black Beanie", 18, { P("beanie") }, { 26, 26, 30 }, nil, { hidesHair = true })
hat("w_beanie_red", "Red Beanie", 18, { P("beanie") }, { 150, 26, 34 }, nil, { hidesHair = true })
hat("w_durag_black", "Black Durag", 12, { P("durag") }, { 20, 20, 24 }, nil, { hidesHair = true })
hat("w_durag_red", "Red Durag", 12, { P("durag") }, { 160, 26, 34 }, nil, { hidesHair = true })
hat("w_skimask_black", "Black Ski Mask", 25, { P("ski_mask") }, { 22, 22, 26 }, nil, { hidesHair = true, mask = true })

-- ---------------------------------------------------------------- jewelry / accessories
local function jewel(id, name, price, slot, pieces, colors, store)
	item(id, { name = name, price = price, slot = slot, store = store or "jewelry", pieces = pieces, colors = colors })
end
local M = function(mesh) return { mesh = mesh, role = "metal" } end
jewel("j_cuban_gold", "Gold Cuban Link", 250, "chain", { M("chain_cuban") }, { metal = GOLD })
jewel("j_cuban_silver", "Silver Cuban Link", 180, "chain", { M("chain_cuban") }, { metal = SILVER })
jewel("j_cuban_six", "Cuban + '6' Piece", 450, "chain", { M("chain_cuban"), M("pendant_six") }, { metal = GOLD })
jewel("j_rope_gold", "Gold Rope Chain", 200, "chain", { M("chain_rope") }, { metal = GOLD })
jewel("j_rope_six_iced", "Rope + Iced '6' Piece", 520, "chain",
	{ M("chain_rope"), { mesh = "pendant_six", role = "gem" } }, { metal = SILVER, gem = ICE })
jewel("j_watch_gold", "Gold Watch", 300, "watch", { M("watch_case"), { mesh = "watch_dial", role = "trim" } },
	{ metal = GOLD, trim = { 24, 24, 28 } })
jewel("j_watch_iced", "Iced-Out Watch", 650, "watch", { M("watch_case"), { mesh = "watch_dial", role = "gem" } },
	{ metal = SILVER, gem = ICE })
jewel("j_bracelet_gold", "Gold Cuban Bracelet", 140, "bracelet", { M("bracelet_cuban") }, { metal = GOLD })
jewel("j_studs", "Diamond Studs", 90, "ears", { { mesh = "earring_studs", role = "gem" } }, { gem = ICE })
jewel("j_hoops_gold", "Gold Hoops", 70, "ears", { M("earring_hoops") }, { metal = GOLD })
jewel("w_shades_black", "Black Shades", 35, "eyes", { P("shades_frame", "trim"), { mesh = "shades_lens", role = "lens" } },
	{ trim = { 20, 20, 22 }, lens = { 16, 16, 20 } }, "clothing")
jewel("w_shades_gold", "Gold Frame Shades", 60, "eyes", { M("shades_frame"), { mesh = "shades_lens", role = "lens" } },
	{ metal = GOLD, lens = { 60, 40, 20 } }, "clothing")
jewel("w_headphones_white", "White Headphones", 90, "neck", { P("headphones_neck", "trim") }, { trim = { 236, 236, 236 } }, "clothing")
jewel("w_headphones_black", "Black Headphones", 90, "neck", { P("headphones_neck", "trim") }, { trim = { 24, 24, 28 } }, "clothing")

-- ---------------------------------------------------------------- EXIT 6 Premium (Robux)
-- Sold only through Exit6Premium products (developer products, see that
-- module). store = "premium" keeps them off every Chester Cash menu;
-- premium = true makes Exit6Style render them only for owners (or try-on).
-- bundleOnly items exist only inside an outfit bundle. Meshes: px_* from
-- tools/assets/build_premium.py (Exit6PremiumMeshes).
local BLK, CHAR, WHT = { 22, 22, 26 }, { 58, 58, 64 }, { 236, 236, 232 }
local CHROME, DIAMOND = { 206, 210, 218 }, { 232, 242, 252 }
local function premium(id, def)
	def.store = "premium"
	def.premium = true
	def.price = 0
	item(id, def)
end
local function R(mesh, role) return { mesh = mesh, role = role } end

premium("p_pendant_silver", { name = "EXIT 6 Silver Pendant Chain", slot = "chain",
	pieces = { R("px_box_chain", "silver"), R("px_pendant_s_body", "silver"), R("px_pendant_s_face", "silver") },
	colors = { silver = CHROME } })
premium("p_cuban_diamond", { name = "Diamond Cuban + EXIT 6 Piece", slot = "chain",
	pieces = { R("px_cuban_chain", "ice"), R("px_pendant_body", "silver"), R("px_pendant_face", "ice") },
	colors = { ice = DIAMOND, silver = CHROME } })
premium("p_studs_diamond", { name = "Diamond Stud Earrings", slot = "ears",
	pieces = { R("px_stud_stone", "gem"), R("px_stud_setting", "silver") },
	colors = { gem = DIAMOND, silver = CHROME } })
premium("p_watch_iced", { name = "Iced Octagon Watch", slot = "watch",
	pieces = { R("px_watch_case", "silver"), R("px_watch_ice", "ice"), R("px_watch_hands", "silver") },
	colors = { silver = CHROME, ice = DIAMOND } })

local PUFFER_P = { R("px_puffer_body", "shell"), R("px_puffer_upper", "shell"), R("px_puffer_lower", "shell"),
	R("px_puffer_cuff", "knit"), R("px_puffer_knit", "knit"), R("px_puffer_zip", "silver"), R("px_puffer_hood", "fleece") }
premium("p_puffer_black", { name = "Oversized Winter Puffer", slot = "top", pieces = PUFFER_P, depth = 0.1,
	v31Asset = "Exit6_Puffer", v31Tint = { 34, 34, 38 },
	colors = { shell = { 18, 18, 21 }, knit = BLK, silver = CHROME, fleece = CHAR } })

local TRACK_TOP = { R("px_track_jacket", "fleece"), R("px_track_rib", "knit"), R("px_track_panels", "accent"),
	R("px_track_zip", "silver"), R("px_track_logo", "silver"), R("sleeve_upper", "fleece"), R("sleeve_lower", "fleece"),
	R("track_trim_upper", "accent"), R("track_trim_lower", "accent") }
local TRACK_PANTS = { { mesh = "pants_waist", role = "fleece", underTop = true }, R("pants_upper", "fleece"),
	R("jogger_lower", "fleece"), R("leg_trim_upper", "accent"), R("leg_trim_lower", "accent") }
premium("p_track_top_black", { name = "Premium Track Jacket", slot = "top", pieces = TRACK_TOP, depth = 0.04,
	colors = { fleece = BLK, knit = BLK, accent = WHT, silver = CHROME } })
premium("p_track_pants_black", { name = "Premium Track Pants", slot = "bottom", pieces = TRACK_PANTS,
	colors = { fleece = BLK, accent = WHT } })
premium("p_track_top_nightlife", { name = "Nightlife Track Jacket (VIP)", slot = "top", pieces = TRACK_TOP, depth = 0.04,
	bundleOnly = true, colors = { fleece = { 14, 14, 17 }, knit = { 14, 14, 17 }, accent = CHROME, silver = CHROME } })
premium("p_track_pants_nightlife", { name = "Nightlife Track Pants (VIP)", slot = "bottom", pieces = TRACK_PANTS,
	bundleOnly = true, colors = { fleece = { 14, 14, 17 }, accent = CHROME } })
premium("p_cargo_black", { name = "Founder's Stacked Cargos", slot = "bottom", bundleOnly = true,
	v31Asset = "Exit6_Cargo", v31Tint = { 34, 34, 38 },
	pieces = { { mesh = "pants_waist", role = "fleece", underTop = true }, R("px_cargo_upper", "fleece"),
		R("px_cargo_snaps", "silver"), R("px_cargo_lower", "fleece") },
	colors = { fleece = BLK, silver = CHROME } })

local HIGHTOP = { R("px_hightop_base", "leather"), R("px_hightop_overlay", "overlay"), R("px_hightop_mark", "mark"),
	R("px_hightop_sole", "rubber"), R("px_hightop_laces", "lace") }
premium("p_hightops", { name = "EXIT 6 High-Tops", slot = "shoes", pieces = HIGHTOP,
	colors = { leather = WHT, overlay = BLK, mark = { 196, 28, 36 }, rubber = { 244, 244, 240 }, lace = WHT } })
premium("p_hightops_midnight", { name = "EXIT 6 High-Tops Midnight (VIP)", slot = "shoes", pieces = HIGHTOP, bundleOnly = true,
	colors = { leather = { 20, 20, 24 }, overlay = { 12, 12, 14 }, mark = CHROME, rubber = { 26, 26, 30 }, lace = { 20, 20, 24 } } })

premium("p_cap_fitted", { name = "Signature EXIT 6 Fitted", slot = "hat", cap = true,
	pieces = { R("px_cap_crown", "knit"), R("px_cap_wordmark", "stitch") },
	colors = { knit = { 16, 16, 19 }, stitch = CHROME } })

premium("p_long_locs", { name = "Long Locs", slot = "hair", showsUnderCap = true,
	pieces = { R("px_hair_long_locs", "locs"), R("px_loc_cuffs", "silver") },
	colors = { locs = { 34, 25, 20 }, silver = CHROME } })
premium("p_designer_cornrows", { name = "Designer Cornrows", slot = "hair", showsUnderCap = true,
	pieces = { R("px_hair_designer_cornrows", "locs") }, colors = { locs = { 30, 22, 18 } } })

premium("p_v31_cargo", { name = "V3.1 Premium Cargos", slot = "bottom", v31Only = true,
	pieces = {}, v31Asset = "Exit6_Cargo", v31Tint = { 34, 34, 38 } })
premium("p_v31_sneakers", { name = "V3.1 Premium Sneakers", slot = "shoes", v31Only = true,
	pieces = {}, v31Asset = "Exit6_Sneakers" })

-- skin tones (free, Closet): profile style.skin = index, 0 / nil = the avatar's own colours
Wardrobe.SkinTones = {
	{ name = "Espresso", rgb = { 58, 36, 26 } },
	{ name = "Deep Brown", rgb = { 86, 56, 40 } },
	{ name = "Mahogany", rgb = { 110, 72, 50 } },
	{ name = "Chestnut", rgb = { 132, 90, 62 } },
	{ name = "Caramel", rgb = { 160, 112, 78 } },
	{ name = "Honey", rgb = { 186, 136, 96 } },
	{ name = "Tan", rgb = { 204, 156, 116 } },
	{ name = "Sand", rgb = { 222, 184, 148 } },
	{ name = "Light", rgb = { 238, 206, 176 } },
	{ name = "Fair", rgb = { 248, 224, 204 } },
}

-- First V3.1-native catalog entries. They reuse the original fitted meshes
-- and only appear when the isolated V3.1 character system is enabled.
local function v31(id, def)
	def.v31Only = true
	def.pieces = {}
	item(id, def)
end
v31("v31_twists", { name = "V3.1 Twists", slot = "hair", store = "barber", price = 40,
	v31Asset = "Exit6_Hair_Twists" })
v31("v31_goatee", { name = "Sculpted Goatee", slot = "facialHair", store = "barber", price = 20,
	v31Asset = "Exit6_Goatee" })
v31("v31_clean_shaven", { name = "Clean Shaven", slot = "facialHair", store = "barber", price = 0,
	v31Empty = true })
v31("v31_puffer_cream", { name = "V3.1 Quilted Puffer", slot = "top", store = "clothing", price = 280,
	v31Asset = "Exit6_Puffer", v31Tint = { 235, 232, 224 },
	v31TintPalette = { { 235, 232, 224 }, { 76, 95, 119 }, { 117, 62, 64 } } })
v31("v31_cargo_olive", { name = "V3.1 Cargos", slot = "bottom", store = "clothing", price = 180,
	v31Asset = "Exit6_Cargo", v31Tint = { 92, 96, 70 },
	v31TintPalette = { { 92, 96, 70 }, { 44, 46, 50 }, { 152, 134, 106 } } })
v31("v31_sneakers", { name = "V3.1 Sneakers", slot = "shoes", store = "clothing", price = 150,
	v31Asset = "Exit6_Sneakers" })
v31("v31_chain_gold", { name = "Gold Curb Chain", slot = "chain", store = "jewelry", price = 300,
	repRequired = 10, v31Asset = "Exit6_Chain" })
v31("v31_watch_gold", { name = "Gold Wristwatch", slot = "watch", store = "jewelry", price = 240,
	repRequired = 5, v31Asset = "Exit6_Watch" })

-- free starter fit every player owns (worn by default; Closet can switch to the Roblox avatar)
Wardrobe.Starter = { top = "w_tee_white", bottom = "w_joggers_black", shoes = "w_sneakers_white" }

-- saved outfits (loadouts) in the Closet: profile style.outfits["1".."4"] = { slot = itemId }
Wardrobe.OutfitSlots = 4

-- old profile ids -> new items (part-built looks and the Hair Test collection)
Wardrobe.Legacy = {
	cut_fade = "hair_mid_skin_fade", cut_waves = "hair_waves_360", cut_twists = "hair_two_strand_twists",
	cut_afro = "hair_afro_taper", cut_braids = "hair_cornrows", cut_loc_short = "hair_starter_locs",
	cut_loc_long = "hair_shoulder_locs", cut_high_top = "hair_high_top_fade", cut_box_braids = "hair_box_braids",
	cut_bald = "hair_bald",
	tee_white = "w_tee_white", tee_black = "w_tee_black", tee_red = "w_tee_red",
	hoodie_grey = "w_hoodie_grey", hoodie_navy = "w_hoodie_navy", jersey_blue = "w_tee_black",
	tracksuit_black = "w_track_black", tracksuit_red = "w_track_red", puffer_black = "w_puffer_black",
	denim_jacket = "w_track_navy",
	jeans_blue = "w_jeans_blue", jeans_black = "w_jeans_black", sweats_grey = "w_joggers_grey",
	cargo_khaki = "w_joggers_grey", stacked_jeans = "w_jeans_blue", track_pants = "w_trackpants_black",
	beanie_black = "w_beanie_black", cap_red = "w_cap_red", cap_navy = "w_cap_navy", cap_black = "w_cap_black",
	durag_black = "w_durag_black",
}
local HAIR_TEST = { "sharp_low_taper", "mid_skin_fade", "high_top_fade", "waves_360", "starter_locs", "medium_locs",
	"shoulder_locs", "two_strand_twists", "cornrows", "box_braids", "afro_taper", "braided_ponytail" }
for _, id in ipairs(HAIR_TEST) do Wardrobe.Legacy["test_hair_" .. id] = "hair_" .. id end

-- menus for one or more store kinds (sorted by slot, then price)
local ORDER = {}
for i, s in ipairs(Wardrobe.Slots) do ORDER[s] = i end
function Wardrobe.MenuFor(...)
	local stores = {}
	for _, kind in ipairs({ ... }) do stores[kind] = true end
	local ids = {}
	for id, it in pairs(Items) do
		if stores[it.store] then table.insert(ids, id) end
	end
	table.sort(ids, function(a, b)
		local A, B = Items[a], Items[b]
		if A.slot ~= B.slot then return ORDER[A.slot] < ORDER[B.slot] end
		if A.price ~= B.price then return A.price < B.price end
		return A.name < B.name
	end)
	return ids
end

return Wardrobe
