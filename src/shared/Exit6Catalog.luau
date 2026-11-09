-- EXIT 6 store catalog: what each kind of Chester store sells, and prices in
-- Chester Cash. Server-authoritative: the server reads prices from here; the
-- client only uses it to draw the shop menu.
local Catalog = {}

Catalog.Items = {
	-- food / takeout
	chicken_box = { name = "Chicken Box (4 pc + fries)", price = 9, kind = "food" },
	wings = { name = "Wings (6) & Fries", price = 8, kind = "food" },
	fish_platter = { name = "Fried Fish Platter", price = 11, kind = "food" },
	cheesesteak = { name = "Cheesesteak", price = 10, kind = "food" },
	pizza_slice = { name = "Pizza Slice", price = 3, kind = "food" },
	lo_mein = { name = "Chicken Lo Mein", price = 8, kind = "food" },
	-- corner store / market
	soda = { name = "Soda", price = 2, kind = "drink" },
	water = { name = "Bottled Water", price = 1, kind = "drink" },
	iced_tea = { name = "Iced Tea", price = 1, kind = "drink" },
	chips = { name = "Chips", price = 1, kind = "snack" },
	hoagie = { name = "Hoagie", price = 7, kind = "food" },
	bread = { name = "Loaf of Bread", price = 3, kind = "grocery" },
	milk = { name = "Milk (half gallon)", price = 3, kind = "grocery" },
	-- phone store
	phone_case = { name = "Phone Case", price = 15, kind = "accessory" },
	charger = { name = "Phone Charger", price = 12, kind = "accessory" },
	prepaid_card = { name = "Prepaid Card", price = 25, kind = "service" },
	-- laundromat
	detergent = { name = "Detergent", price = 4, kind = "household" },
	wash_load = { name = "Wash & Dry Load", price = 6, kind = "service" },
	-- barber / salon
	edge_up = { name = "Edge Up", price = 10, kind = "service" },
	haircut = { name = "Haircut", price = 20, kind = "service" },
	-- barbershop: a new cut changes your look (Exit6Style.server), saved
	cut_fade = { name = "Fade", price = 20, kind = "haircut", style = "fade" },
	cut_waves = { name = "Waves", price = 25, kind = "haircut", style = "waves" },
	cut_twists = { name = "Twists", price = 35, kind = "haircut", style = "twists" },
	cut_afro = { name = "Shape-up Afro", price = 30, kind = "haircut", style = "afro" },
	cut_braids = { name = "Cornrows", price = 45, kind = "haircut", style = "braids" },
 cut_loc_short = { name = "Short Starter Locs", price = 35, kind = "haircut", style = "loc_short" },
 cut_loc_long = { name = "Shoulder-Length Locs", price = 55, kind = "haircut", style = "loc_long" },
 cut_high_top = { name = "High Top Fade", price = 30, kind = "haircut", style = "high_top" },
 cut_box_braids = { name = "Box Braids", price = 55, kind = "haircut", style = "box_braids" },
	cut_bald = { name = "Clean Shave", price = 15, kind = "haircut", style = "bald" },
	cut_own = { name = "Back to my own hair", price = 0, kind = "haircut", style = "own" },
	-- clothing: solid-colour fits over your avatar (slot top / bottom / hat), saved
	tee_white = { name = "White Tee", price = 12, kind = "clothing", slot = "top", color = { 236, 236, 232 } },
	tee_black = { name = "Black Tee", price = 12, kind = "clothing", slot = "top", color = { 26, 26, 28 } },
	tee_red = { name = "Red Tee", price = 12, kind = "clothing", slot = "top", color = { 160, 24, 32 } },
	hoodie_grey = { name = "Grey Hoodie", price = 35, kind = "clothing", slot = "top", color = { 128, 128, 132 }, hood = true },
	hoodie_navy = { name = "Navy Hoodie", price = 35, kind = "clothing", slot = "top", color = { 26, 38, 70 }, hood = true },
	jersey_blue = { name = "Union Blue Jersey", price = 45, kind = "clothing", slot = "top", color = { 30, 90, 170 } },
	jeans_blue = { name = "Blue Jeans", price = 30, kind = "clothing", slot = "bottom", color = { 52, 72, 110 } },
	jeans_black = { name = "Black Jeans", price = 30, kind = "clothing", slot = "bottom", color = { 30, 30, 34 } },
	sweats_grey = { name = "Grey Sweats", price = 25, kind = "clothing", slot = "bottom", color = { 120, 120, 124 } },
	cargo_khaki = { name = "Khaki Cargos", price = 30, kind = "clothing", slot = "bottom", color = { 150, 132, 96 } },
	beanie_black = { name = "Black Beanie", price = 15, kind = "clothing", slot = "hat", color = { 24, 24, 26 }, hat = "beanie" },
	cap_red = { name = "Red Fitted Cap", price = 25, kind = "clothing", slot = "hat", color = { 160, 24, 32 }, hat = "cap" },
	cap_navy = { name = "Navy Fitted Cap", price = 25, kind = "clothing", slot = "hat", color = { 26, 38, 70 }, hat = "cap" },
	durag_black = { name = "Black Durag", price = 10, kind = "clothing", slot = "hat", color = { 20, 20, 22 }, hat = "durag" },
 tracksuit_black = { name = "Black Track Jacket", price = 65, kind = "clothing", slot = "top", color = { 24, 26, 30 }, hood = true, accent = { 235, 235, 235 } },
 tracksuit_red = { name = "Red Track Jacket", price = 65, kind = "clothing", slot = "top", color = { 145, 30, 36 }, hood = true, accent = { 235, 235, 235 } },
 puffer_black = { name = "Black Puffer Jacket", price = 110, kind = "clothing", slot = "top", color = { 28, 29, 32 }, puffer = true },
 denim_jacket = { name = "Washed Denim Jacket", price = 80, kind = "clothing", slot = "top", color = { 65, 92, 133 }, accent = { 176, 187, 199 } },
 stacked_jeans = { name = "Dark Stacked Jeans", price = 65, kind = "clothing", slot = "bottom", color = { 35, 44, 67 }, stacked = true },
 track_pants = { name = "Black Track Pants", price = 45, kind = "clothing", slot = "bottom", color = { 26, 27, 30 }, accent = { 225, 225, 225 } },
 cap_black = { name = "Black Fitted Cap", price = 25, kind = "clothing", slot = "hat", color = { 24, 25, 28 }, hat = "cap" },
	fit_own = { name = "Back to my own fit", price = 0, kind = "clothing", slot = "reset" },
	-- dealership (Exit6Vehicles.server): goes in your garage, saved
	car_hatch = { name = "2009 Hatchback", price = 1800, kind = "vehicle", model = "hatch" },
	car_van = { name = "2006 Minivan", price = 2600, kind = "vehicle", model = "van" },
	car_pickup = { name = "2012 Pickup", price = 4200, kind = "vehicle", model = "pickup" },
	car_suv = { name = "2015 SUV", price = 6500, kind = "vehicle", model = "suv" },
	car_coupe = { name = "2018 Coupe", price = 9500, kind = "vehicle", model = "coupe" },
}

-- Free development collection. IDs are stable profile keys; none are sold by
-- a shop menu. The server only equips an entry when its MeshPart is installed
-- under ServerStorage.Exit6ProductionAssets.Hair.
Catalog.HairTest = {
	{ id = "sharp_low_taper", name = "Low taper fade" },
	{ id = "mid_skin_fade", name = "Mid skin fade" },
	{ id = "high_top_fade", name = "High-top fade" },
	{ id = "waves_360", name = "360 waves" },
	{ id = "starter_locs", name = "Short starter locs" },
	{ id = "medium_locs", name = "Medium locs" },
	{ id = "shoulder_locs", name = "Shoulder-length locs" },
	{ id = "two_strand_twists", name = "Two-strand twists" },
	{ id = "cornrows", name = "Cornrows" },
	{ id = "box_braids", name = "Box braids" },
	{ id = "afro_taper", name = "Afro taper" },
	{ id = "braided_ponytail", name = "Braided ponytail" },
}
for _, asset in ipairs(Catalog.HairTest) do
	Catalog.Items["test_hair_" .. asset.id] = {
		name = asset.name .. " [TEST]", price = 0, kind = "haircut",
		assetId = asset.id, testOnly = true,
	}
end

-- store kind -> items on its menu
Catalog.Menus = {
	food = { "chicken_box", "wings", "fish_platter", "cheesesteak", "soda", "water" },
	pizza = { "pizza_slice", "cheesesteak", "wings", "soda", "water" },
	chinese = { "lo_mein", "wings", "chicken_box", "soda" },
	market = { "hoagie", "chips", "soda", "iced_tea", "water", "bread", "milk" },
	gas = { "chips", "soda", "iced_tea", "water", "hoagie" },
	phone = { "phone_case", "charger", "prepaid_card" },
	laundry = { "detergent", "wash_load", "soda" },
	-- Legacy part-built looks remain in Items for existing profiles, but are
	-- withheld from new sales until production assets pass Studio visual QA.
	-- Installed Hair Test meshes are offered free at barbershops for now; server
	-- validates the actual accessory before equipping or saving.
	barber = { "test_hair_sharp_low_taper", "test_hair_mid_skin_fade", "test_hair_high_top_fade", "test_hair_waves_360", "test_hair_starter_locs", "test_hair_medium_locs", "test_hair_shoulder_locs", "test_hair_two_strand_twists", "test_hair_cornrows", "test_hair_box_braids", "test_hair_afro_taper", "test_hair_braided_ponytail", "cut_bald", "cut_own" },
	clothing = { "fit_own" },
	dealer = { "car_hatch", "car_van", "car_pickup", "car_suv", "car_coupe" },
}

-- what kind of store a name is (store names come from Street View / Overture)
local KEYWORDS = {
	{ "pizza", "pizza" }, { "house", "chinese" }, { "wok", "chinese" }, { "china", "chinese" },
	{ "chicken", "food" }, { "seafood", "food" }, { "grill", "food" }, { "cuisine", "food" },
	{ "checkers", "food" }, { "wings", "food" }, { "steak", "food" }, { "j & s", "food" },
	{ "mobile", "phone" }, { "wireless", "phone" }, { "metro", "phone" }, { "cricket", "phone" },
	{ "laund", "laundry" }, { "barber", "barber" }, { "salon", "barber" }, { "hair", "barber" }, { "beauty", "barber" },
	{ "fashion", "clothing" }, { "boutique", "clothing" }, { "apparel", "clothing" }, { "cloth", "clothing" },
	{ "footwear", "clothing" }, { "motors", "dealer" },
	{ "market", "market" }, { "deli", "market" }, { "mart", "market" }, { "grocery", "market" },
}
function Catalog.KindFor(name, isGasStation)
	if isGasStation then return "gas" end
	local low = string.lower(name or "")
	for _, kw in ipairs(KEYWORDS) do
		if string.find(low, kw[1], 1, true) then return kw[2] end
	end
	return "market"
end

-- stock-clerk shift (gas stations and markets): crates from the back room to
-- the shelves before the clock runs out
Catalog.StockShift = {
	crates = 4,
	timeLimit = 150,      -- seconds
	basePay = 30,
	speedBonus = 15,      -- full bonus when finished in half the time
	reputation = 1,
	cooldown = 120,       -- seconds between shifts at any store
}
Catalog.JobKinds = { gas = true, market = true }

-- food delivery (takeout stores): carry an order to a real front door
-- (RealBuildings tags each home's front door Exit6FrontDoor)
Catalog.Delivery = {
	minStuds = 150,       -- nearest a drop-off may be
	maxStuds = 900,       -- farthest
	basePay = 12,
	payPerStud = 0.04,    -- ~ $36 for a 600-stud run
	secondsPerStud = 0.14, -- on foot at sprint, with slack
	minSeconds = 60,
	tipSeconds = 0.5,     -- tip while under this fraction of the limit
	tip = 8,
	reputation = 1,
	cooldown = 45,
}
Catalog.DeliveryKinds = { food = true, pizza = true, chinese = true }

-- vehicles: body + handling per model (Exit6CarBuilder / Exit6CarPhysics).
-- size = body length / width / height (studs), tank in gallons, mpg as
-- studs per gallon (a tank lasts a good few trips across the city)
Catalog.Vehicles = {
	sedan = { name = "Family Sedan", body = "sedan", len = 16.4, wid = 7.2, topSpeed = 110, accel = 24, tank = 12, perGallon = 2600 },
	hatch = { name = "Hatchback", body = "hatch", len = 14.2, wid = 6.8, topSpeed = 105, accel = 26, tank = 10, perGallon = 3200 },
	van = { name = "Minivan", body = "van", len = 17.6, wid = 7.6, topSpeed = 100, accel = 20, tank = 16, perGallon = 2200 },
	pickup = { name = "Pickup", body = "pickup", len = 19, wid = 7.8, topSpeed = 112, accel = 25, tank = 20, perGallon = 1800 },
	suv = { name = "SUV", body = "suv", len = 17.8, wid = 7.8, topSpeed = 115, accel = 26, tank = 18, perGallon = 2000 },
	coupe = { name = "Coupe", body = "coupe", len = 15.6, wid = 7.2, topSpeed = 135, accel = 34, tank = 13, perGallon = 2100 },
}
Catalog.StarterVehicle = "sedan"
Catalog.FuelPrice = 3.29          -- per gallon when a station has no price sign

-- housing (Exit6Housing.server): rent a real front door in the city
Catalog.Housing = {
	rowhouse = 400, twin = 650, house = 900, apartment = 300,
	default = 450,
}

-- business ownership (Exit6Business.server): buy a store, it earns while you're in town
Catalog.Business = {
	priceByKind = { food = 6000, pizza = 5000, chinese = 5500, market = 7500, gas = 12000, phone = 4000,
		laundry = 4500, barber = 4000, clothing = 5000 },
	incomePerMinute = 0.012,   -- fraction of the price earned per minute online, collected at the register
	maxBank = 0.25,            -- the till holds at most this fraction of the price
}

-- rideshare (Exit6Rideshare.server): pick up a pedestrian, drive them across town
Catalog.Rideshare = {
	minStuds = 400, maxStuds = 1600, basePay = 15, payPerStud = 0.05, secondsPerStud = 0.09, minSeconds = 60,
	reputation = 1, cooldown = 30,
}

return Catalog
