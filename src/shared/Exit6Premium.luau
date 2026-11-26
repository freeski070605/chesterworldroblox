-- EXIT 6 Premium: the Robux cosmetics line (products -> wardrobe items).
--
-- Each product is a Roblox *developer product* the experience owner creates in
-- the Creator Dashboard (Monetization > Developer Products). Put its id in
-- productId. While productId is 0 the product is listed as "coming soon" and
-- cannot be bought in live servers; in Studio it can be test-granted through
-- the same receipt path (Exit6PremiumStore.server). Never guess ids.
--
-- robux = the PROPOSED price for testing; the real price is whatever the
-- owner sets on the developer product (the boutique shows the live price from
-- MarketplaceService once an id is configured).
--
-- Premium items are cosmetic only: a grant may contain only Exit6Wardrobe
-- items with premium = true. Nothing here touches cash, reputation, vehicles
-- or any reputation-gated content (tools/assets/validate_premium.py checks it).
local Premium = {}

Premium.Enabled = true
-- Studio only: products with no id yet can be granted for testing
Premium.StudioTestPurchases = true

-- category: hair / clothing / shoes / jewelry / outfit (boutique tabs + which
-- city stores list it). focus: where the try-on camera looks.
Premium.Products = {
	cuban_diamond = { name = "Diamond Cuban Chain", robux = 399, productId = 0, category = "jewelry", focus = "chest",
		flagship = true, grants = { "p_cuban_diamond" },
		blurb = "Heavy pave-set Cuban links with the iced EXIT 6 piece." },
	puffer = { name = "Oversized Winter Puffer", robux = 299, productId = 0, category = "clothing", focus = "body",
		flagship = true, grants = { "p_puffer_black" },
		blurb = "Deep-baffle black puffer, tall collar, charcoal hood out over the top." },
	v31_cargo = { name = "V3.1 Premium Cargos", robux = 149, productId = 0, category = "clothing", focus = "body",
		grants = { "p_v31_cargo" }, blurb = "Tailored black cargos fitted to the V3.1 avatar." },
	v31_sneakers = { name = "V3.1 Premium Sneakers", robux = 99, productId = 0, category = "shoes", focus = "feet",
		grants = { "p_v31_sneakers" }, blurb = "Original low-top sneakers fitted to the V3.1 avatar." },
	hightops = { name = "EXIT 6 High-Tops", robux = 199, productId = 0, category = "shoes", focus = "feet",
		flagship = true, grants = { "p_hightops" },
		blurb = "White leather high-tops, black overlays, silver hex '6' patch." },
	long_locs = { name = "Long Locs", robux = 199, productId = 0, category = "hair", focus = "head",
		flagship = true, grants = { "p_long_locs" },
		blurb = "Mid-back locs with silver cuffs. Wears under fitted caps." },
	founders_fit = { name = "Founder's Full Fit", robux = 999, productId = 0, category = "outfit", focus = "body",
		flagship = true, outfit = true,
		grants = { "p_puffer_black", "p_cargo_black", "p_hightops", "p_cuban_diamond", "p_watch_iced",
			"p_studs_diamond", "p_long_locs", "p_cap_fitted" },
		blurb = "The whole EXIT 6 hero fit, plus Founder's Stacked Cargos (only in this set)." },
	pendant_silver = { name = "EXIT 6 Silver Pendant Chain", robux = 149, productId = 0, category = "jewelry",
		focus = "chest", grants = { "p_pendant_silver" },
		blurb = "Polished EXIT 6 piece on a fine box chain." },
	tracksuit = { name = "Premium Tracksuit Set", robux = 349, productId = 0, category = "clothing", focus = "body",
		grants = { "p_track_top_black", "p_track_pants_black" },
		blurb = "Black track jacket and pants, white stripes, EXIT 6 chest mark." },
	cornrows = { name = "Designer Cornrows", robux = 149, productId = 0, category = "hair", focus = "head",
		grants = { "p_designer_cornrows" },
		blurb = "S-curve rows finishing in nape braids." },
	studs = { name = "Diamond Stud Earrings", robux = 99, productId = 0, category = "jewelry", focus = "head",
		grants = { "p_studs_diamond" },
		blurb = "Faceted cushion-cut studs in four-prong settings." },
	watch = { name = "Iced Luxury Watch", robux = 249, productId = 0, category = "jewelry", focus = "wrist",
		grants = { "p_watch_iced" },
		blurb = "Octagon case, iced bezel and dial, three-row bracelet." },
	cap = { name = "Signature Fitted Cap", robux = 99, productId = 0, category = "clothing", focus = "head",
		grants = { "p_cap_fitted" },
		blurb = "Structured black fitted with a raised EXIT 6 wordmark." },
	vip_nightlife = { name = "VIP Nightlife Outfit", robux = 599, productId = 0, category = "outfit", focus = "body",
		outfit = true,
		grants = { "p_track_top_nightlife", "p_track_pants_nightlife", "p_hightops_midnight", "p_pendant_silver",
			"p_watch_iced", "p_studs_diamond", "p_designer_cornrows" },
		blurb = "All-black nightlife tracksuit with chrome piping and Midnight high-tops (only in this set)." },
}

-- boutique order
Premium.Order = { "founders_fit", "cuban_diamond", "puffer", "v31_cargo", "v31_sneakers", "hightops", "long_locs", "vip_nightlife", "tracksuit",
	"watch", "pendant_silver", "cornrows", "studs", "cap" }
Premium.Categories = { "outfit", "clothing", "shoes", "hair", "jewelry" }
Premium.CategoryNames = { outfit = "Outfits", clothing = "Clothing", shoes = "Shoes", hair = "Hair", jewelry = "Jewelry" }

-- which premium products each city store kind shows (opens the boutique)
Premium.StoreCategories = {
	barber = { hair = true },
	jewelry = { jewelry = true },
	clothing = { clothing = true, shoes = true, outfit = true, jewelry = true },
}

function Premium.ForStore(kind)
	local cats = Premium.StoreCategories[kind]
	local out = {}
	if not cats or not Premium.Enabled then return out end
	for _, sku in ipairs(Premium.Order) do
		if cats[Premium.Products[sku].category] then table.insert(out, sku) end
	end
	return out
end

-- productId -> sku (only configured ids)
function Premium.SkuForProduct(productId)
	for sku, p in pairs(Premium.Products) do
		if p.productId ~= 0 and p.productId == productId then return sku end
	end
	return nil
end

return Premium
