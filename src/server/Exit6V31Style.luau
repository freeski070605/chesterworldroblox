-- Character-specific layered wear. The installed templates come from the
-- separate V3.1 character test place; this module never creates block parts.
local ServerStorage = game:GetService("ServerStorage")
local V31 = {}

local function library(name)
	return ServerStorage:FindFirstChild(name)
end

local function source(name)
	for _, folderName in { "Exit6_V31_Wear", "Exit6_V31_Accessories" } do
		local folder = library(folderName)
		local item = folder and folder:FindFirstChild(name)
		if item and item:IsA("Accessory") then return item end
	end
	return nil
end

-- How a chain sits with each V3.1 top. `over` names the chain variant fitted to the
-- outside of that top; `under` = the skin-fitted chain stays inside the top's inner wall
-- (measured by tools/characters/check_exit6_wear_v31.py). Tops missing here hide the chain
-- rather than let it clip.
V31.ChainFit = {
	Exit6_Puffer = { over = "Exit6_Chain_Over", under = true },
}

-- "over" | "under" | nil for the chain worn with this top (nil = chain hidden)
function V31.ChainLayer(topAsset, wanted)
	if not topAsset then return "skin" end
	local fit = V31.ChainFit[topAsset]
	if not fit then return nil end
	local canOver, canUnder = fit.over ~= nil and source(fit.over) ~= nil, fit.under == true
	if wanted == "under" and canUnder then return "under" end
	if canOver then return "over" end
	if canUnder then return "under" end
	return nil
end

function V31.Ready(name)
	return source(name) ~= nil
end

function V31.SkinReady(index)
	local folder = library("Exit6_V31_SkinToneMaps")
	local entry = folder and folder:FindFirstChild(tostring(index))
	return entry ~= nil and entry:IsA("StringValue") and entry.Value:match("^rbxassetid://%d+$") ~= nil
end

local function applySkin(character, index)
	local folder = library("Exit6_V31_SkinToneMaps")
	local entry = index and folder and folder:FindFirstChild(tostring(index))
	local map = entry and entry:IsA("StringValue") and entry.Value or nil
	for _, part in character:GetChildren() do
		if part:IsA("MeshPart") and part:FindFirstChildOfClass("WrapTarget") then
			local surface = part:FindFirstChildOfClass("SurfaceAppearance")
			if surface then
				local original = surface:GetAttribute("Exit6V31OriginalColorMap")
				if original == nil then
					original = surface.ColorMap
					surface:SetAttribute("Exit6V31OriginalColorMap", original)
				end
				surface.ColorMap = map or original
			end
		end
	end
end

local function tint(accessory, rgb)
	if not rgb then return end
	local handle = accessory:FindFirstChild("Handle")
	local surface = handle and handle:FindFirstChildOfClass("SurfaceAppearance")
	if surface then surface.Color = Color3.fromRGB(rgb[1], rgb[2], rgb[3]) end
end

function V31.Apply(character, look, style, catalog)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return false end
	applySkin(character, style.skin)
	for _, item in character:GetChildren() do
		if item:IsA("Accessory") and item.Name:sub(1, 6) == "Exit6_" then
			item:Destroy()
		end
	end
	local selected = {}
	local function color(slot, item)
		if not item then return nil end
		local saved = style[slot] == look[slot] and style.tints and style.tints[slot]
		return (item.v31TintPalette and item.v31TintPalette[saved or 1]) or item.v31Tint
	end
	local function put(name, rgb)
		local template = source(name)
		if not template or selected[name] then return end
		selected[name] = true
		local accessory = template:Clone()
		tint(accessory, rgb)
		humanoid:AddAccessory(accessory)
	end
	put("Exit6_Brows")
	local hair = look.hair and catalog.Items[look.hair]
	if hair and hair.v31Asset then put(hair.v31Asset, color("hair", hair))
	elseif look.hair ~= "hair_bald" then put("Exit6_Hair_Twists") end
	local facial = look.facialHair and catalog.Items[look.facialHair]
	if facial and facial.v31Asset then put(facial.v31Asset, color("facialHair", facial))
	elseif look.facialHair == nil then put("Exit6_Goatee") end
	local top = look.top and catalog.Items[look.top]
	local bottom = look.bottom and catalog.Items[look.bottom]
	local shoes = look.shoes and catalog.Items[look.shoes]
	if not look.bottom then put("Exit6_Briefs") end
	local topAsset = nil
	if top and top.v31Asset then topAsset = top.v31Asset; put(top.v31Asset, color("top", top))
	elseif look.top then topAsset = "Exit6_Puffer"; put("Exit6_Puffer", { 34, 34, 38 }) end
	if bottom and bottom.v31Asset then put(bottom.v31Asset, color("bottom", bottom))
	elseif look.bottom then put("Exit6_Cargo", { 92, 96, 70 }) end
	if shoes and shoes.v31Asset then put(shoes.v31Asset, color("shoes", shoes))
	elseif look.shoes then put("Exit6_Sneakers") end
	for _, slot in { "chain", "watch", "ears", "bracelet", "neck", "hat" } do
		local item = look[slot] and catalog.Items[look[slot]]
		if item and item.v31Asset then
			local name = item.v31Asset
			if slot == "chain" and name == "Exit6_Chain" then
				local layer = V31.ChainLayer(topAsset, style.chainLayer)
				if layer == "over" then name = V31.ChainFit[topAsset].over
				elseif layer == nil then name = nil end
			end
			if name then put(name, color(slot, item)) end
		end
	end
	-- SurfaceAppearance tint is supported for dark variants of the baked skin.
	-- A full light-tone range needs uploaded neutral skin maps before release.
	return true
end

return V31
