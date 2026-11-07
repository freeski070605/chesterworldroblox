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
}

-- store kind -> items on its menu
Catalog.Menus = {
	food = { "chicken_box", "wings", "fish_platter", "cheesesteak", "soda", "water" },
	pizza = { "pizza_slice", "cheesesteak", "wings", "soda", "water" },
	chinese = { "lo_mein", "wings", "chicken_box", "soda" },
	market = { "hoagie", "chips", "soda", "iced_tea", "water", "bread", "milk" },
	gas = { "chips", "soda", "iced_tea", "water", "hoagie" },
	phone = { "phone_case", "charger", "prepaid_card" },
	laundry = { "detergent", "wash_load", "soda" },
	barber = { "edge_up", "haircut" },
}

-- what kind of store a name is (store names come from Street View / Overture)
local KEYWORDS = {
	{ "pizza", "pizza" }, { "house", "chinese" }, { "wok", "chinese" }, { "china", "chinese" },
	{ "chicken", "food" }, { "seafood", "food" }, { "grill", "food" }, { "cuisine", "food" },
	{ "checkers", "food" }, { "wings", "food" }, { "steak", "food" }, { "j & s", "food" },
	{ "mobile", "phone" }, { "wireless", "phone" }, { "metro", "phone" }, { "cricket", "phone" },
	{ "laund", "laundry" }, { "barber", "barber" }, { "salon", "barber" }, { "hair", "barber" },
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

return Catalog
