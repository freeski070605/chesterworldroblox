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
	-- dealership (Exit6Vehicles.server): goes in your garage, saved
	car_hatch = { name = "2009 Hatchback", price = 1800, kind = "vehicle", model = "hatch" },
	car_van = { name = "2006 Minivan", price = 2600, kind = "vehicle", model = "van" },
	car_pickup = { name = "2012 Pickup", price = 4200, kind = "vehicle", model = "pickup" },
	car_suv = { name = "2015 SUV", price = 6500, kind = "vehicle", model = "suv" },
	car_coupe = { name = "2018 Coupe", price = 9500, kind = "vehicle", model = "coupe" },
	-- Bike Life (Exit6BikeLife.server / Exit6Garage): bought at the Exit 6 Motors
	-- kiosk or counter, owned for good; reputation gates are checked before cash
	bike_110 = { name = "110 Trail Dirt Bike", price = 1200, kind = "vehicle", model = "bike110" },
	bike_250 = { name = "250 MX Dirt Bike", price = 2600, kind = "vehicle", model = "bike250" },
	bike_450 = { name = "450 MX Dirt Bike", price = 4200, kind = "vehicle", model = "bike450", repRequired = 25 },
	quad_450 = { name = "450 Sport Quad", price = 4700, kind = "vehicle", model = "quad450" },
	quad_700 = { name = "700 Sport Quad", price = 6900, kind = "vehicle", model = "quad700", repRequired = 45 },
}

-- wearables (Exit6Wardrobe): hair at the barber, fits and accessories at
-- clothing stores (which also carry jewelry), chains / watches / earrings at the jeweller
local Wardrobe = require(script.Parent:WaitForChild("Exit6Wardrobe"))
for id, def in pairs(Wardrobe.Items) do
	def.kind = "wear"
	Catalog.Items[id] = def
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
	barber = Wardrobe.MenuFor("barber"),
	-- clothing stores carry the jewelry too (jewellers are rare in the city data)
	clothing = Wardrobe.MenuFor("clothing", "jewelry"),
	jewelry = Wardrobe.MenuFor("jewelry"),
	dealer = { "car_hatch", "car_van", "car_pickup", "car_suv", "car_coupe", "bike_110", "bike_250", "bike_450", "quad_450", "quad_700" },
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
	{ "jewel", "jewelry" }, { "diamond", "jewelry" },
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
-- studs per gallon. tools/validate_fuel_range.py measures the shipped road
-- network circuit and checks every full tank has at least 25% reserve.
Catalog.Vehicles = {
	sedan = { name = "Family Sedan", body = "sedan", len = 16.4, wid = 7.2, topSpeed = 110, accel = 24, tank = 12, perGallon = 10000 },
	hatch = { name = "Hatchback", body = "hatch", len = 14.2, wid = 6.8, topSpeed = 105, accel = 26, tank = 10, perGallon = 11200 },
	van = { name = "Minivan", body = "van", len = 17.6, wid = 7.6, topSpeed = 100, accel = 20, tank = 16, perGallon = 7200 },
	pickup = { name = "Pickup", body = "pickup", len = 19, wid = 7.8, topSpeed = 112, accel = 25, tank = 20, perGallon = 6000 },
	suv = { name = "SUV", body = "suv", len = 17.8, wid = 7.8, topSpeed = 115, accel = 26, tank = 18, perGallon = 6400 },
	coupe = { name = "Coupe", body = "coupe", len = 15.6, wid = 7.2, topSpeed = 135, accel = 34, tank = 13, perGallon = 8400 },
	-- Bike Life rides (Exit6BikeBuilder / Exit6BikePhysics). Speeds in studs/s
	-- (the speedo reads ~1.75 studs/s per mph), accel in studs/s^2, steerLock in
	-- degrees, wheelie = the balance-point pitch in degrees at full throttle.
	bike110 = { name = "110 Trail", body = "dirtbike", rideType = "bike", len = 5.9, wid = 2.5, topSpeed = 58, accel = 22,
		brake = 60, grip = 1.15, steerLock = 36, wheelie = 24, mass = 22, tank = 2.3, perGallon = 48000 },
	bike250 = { name = "250 MX", body = "dirtbike", rideType = "bike", len = 7.5, wid = 3.0, topSpeed = 80, accel = 31,
		brake = 66, grip = 1.2, steerLock = 33, wheelie = 30, mass = 26, tank = 2.8, perGallon = 40000 },
	bike450 = { name = "450 MX", body = "dirtbike", rideType = "bike", len = 7.8, wid = 3.2, topSpeed = 96, accel = 40,
		brake = 70, grip = 1.25, steerLock = 32, wheelie = 34, mass = 28, tank = 3.2, perGallon = 35000 },
	quad450 = { name = "450 Sport Quad", body = "sportquad", rideType = "quad", len = 6.8, wid = 4.4, topSpeed = 82, accel = 30,
		brake = 64, grip = 1.3, steerLock = 32, wheelie = 18, mass = 44, tank = 3.6, perGallon = 31000 },
	quad700 = { name = "700 Sport Quad", body = "sportquad", rideType = "quad", len = 7.2, wid = 4.8, topSpeed = 96, accel = 37,
		brake = 68, grip = 1.35, steerLock = 30, wheelie = 22, mass = 50, tank = 4.0, perGallon = 28000 },
}
Catalog.StarterVehicle = "sedan"
Catalog.FuelPrice = 3.29          -- per gallon when a station has no price sign

-- Bike Life customisation and upgrades (server-priced; Exit6Garage)
Catalog.BikeLife = {
	-- plastics colours; 0 = factory graphics (the mesh's own textures)
	paints = {
		{ name = "Race Red", rgb = { 196, 28, 32 } }, { name = "Factory Blue", rgb = { 24, 76, 186 } },
		{ name = "Lime", rgb = { 118, 196, 30 } }, { name = "Orange", rgb = { 236, 110, 20 } },
		{ name = "Yellow", rgb = { 240, 196, 20 } }, { name = "White", rgb = { 236, 236, 232 } },
		{ name = "Blackout", rgb = { 26, 26, 28 } }, { name = "Purple", rgb = { 110, 48, 170 } },
		{ name = "Teal", rgb = { 20, 150, 150 } }, { name = "Pink", rgb = { 230, 80, 150 } },
	},
	paintPrice = 150,
	-- number plate / grips / seat trim accent
	accents = {
		{ name = "White", rgb = { 240, 240, 236 } }, { name = "Black", rgb = { 22, 22, 24 } },
		{ name = "Red", rgb = { 196, 28, 32 } }, { name = "Blue", rgb = { 24, 76, 186 } },
		{ name = "Yellow", rgb = { 240, 196, 20 } }, { name = "Green", rgb = { 40, 160, 60 } },
	},
	accentPrice = 60,
	numberPrice = 25,
	-- engine: top speed / acceleration; handling: grip, steering, wheelie control
	upgrades = {
		engine = { name = "Engine", maxLevel = 3, priceFactor = { 0.18, 0.32, 0.5 }, rep = { 0, 10, 30 },
			topSpeed = 0.06, accel = 0.1 },
		handling = { name = "Suspension & tyres", maxLevel = 3, priceFactor = { 0.12, 0.22, 0.36 }, rep = { 0, 5, 20 },
			grip = 0.06, steer = 0.04, wheelie = 0.12 },
	},
	testRideSeconds = 120,
	testRideRadius = 700,   -- studs from the dealership before the test ride returns itself
	shopReach = 40,         -- studs from the kiosk / a display ride to use the shop
	-- wheelies (server-observed): minimum pitch, minimum speed, scoring
	wheelieMinPitch = 8, wheelieMinSpeed = 8, wheelieMinSeconds = 1.0, wheeliePointsPerSecond = 10,
	-- rideouts: routes are named junctions on the city's real street graph; the
	-- server snaps each to the rendered intersection pad (Exit6BikeLife.server).
	-- Source metres = county road-centreline endpoints shared by both streets.
	routes = {
		{ id = "fivepoints", name = "Five Points Loop", stops = {
			{ "9th & Kerlin", 7284.6, 6695.7 }, { "8th & Kerlin", 7336.1, 6582.4 }, { "8th & Concord", 7451.5, 6637.0 },
			{ "9th & Parker", 7403.0, 6756.2 }, { "9th & Kerlin", 7284.6, 6695.7 } } },
		{ id = "butler", name = "Butler Run", stops = {
			{ "9th & Butler", 7154.1, 6636.6 }, { "8th & Butler", 7205.0, 6523.0 }, { "8th & Kerlin", 7336.1, 6582.4 },
			{ "10th & Kerlin", 7211.2, 6835.6 }, { "10th & Concord", 7101.0, 6778.0 } } },
		{ id = "lincoln", name = "Lincoln Cruise", stops = {
			{ "9th & Lincoln", 7024.0, 6577.0 }, { "10th & Lincoln", 6961.0, 6711.0 }, { "10th & Kerlin", 7211.2, 6835.6 },
			{ "9th & Kerlin", 7284.6, 6695.7 } } },
	},
	checkpointRadius = 45,
	meetRadius = 160,           -- riders inside this at the start ride along
	maxRiders = 12,
	finishCash = { 60, 40, 25 }, -- by finishing place; everyone else who finishes gets the last
	finishRep = 1,
}

-- housing (Exit6Housing.server): rent a real front door in the city
Catalog.Housing = {
	rowhouse = 400, twin = 650, house = 900, apartment = 300,
	default = 450,
}

-- business ownership (Exit6Business.server): buy a store, it earns while you're in town
Catalog.Business = {
	priceByKind = { food = 6000, pizza = 5000, chinese = 5500, market = 7500, gas = 12000, phone = 4000,
		laundry = 4500, barber = 4000, clothing = 5000, jewelry = 9000 },
	incomePerMinute = 0.012,   -- fraction of the price earned per minute online, collected at the register
	maxBank = 0.25,            -- the till holds at most this fraction of the price
}

-- rideshare (Exit6Rideshare.server): pick up a pedestrian, drive them across town
Catalog.Rideshare = {
	minStuds = 400, maxStuds = 1600, basePay = 15, payPerStud = 0.05, secondsPerStud = 0.09, minSeconds = 60,
	reputation = 1, cooldown = 30,
}

return Catalog
