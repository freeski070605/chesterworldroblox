-- EXIT 6 look: mesh wearables (Exit6Wardrobe) fitted onto the player's R15
-- body and saved in the profile (Exit6Profile.style).
--
-- Every piece is an original MeshPart template in
-- ServerStorage.Exit6ProductionAssets.Wear (tools/studio/install_exit6_wear.luau),
-- authored in one body part's space at the canonical R15 size
-- (Exit6WearMeshes). A piece is scaled by (part size / canonical size) and
-- welded to that part, so it fits any body scale and survives animation.
-- Each slot lives in its own folder on the character and is rebuilt only when
-- that slot changes; respawns rebuild everything from the profile.
-- The avatar's own clothing / accessories under an EXIT 6 slot are hidden,
-- not deleted, so the Closet can hand the Roblox avatar back without a respawn.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Exit6Catalog"))
local Wardrobe = require(Shared:WaitForChild("Exit6Wardrobe"))
local Meshes = require(Shared:WaitForChild("Exit6WearMeshes"))
local PremiumMeshes = require(Shared:WaitForChild("Exit6PremiumMeshes"))
local Profile = require(script.Parent:WaitForChild("Exit6Profile"))
local V31 = require(script.Parent:WaitForChild("Exit6V31Style"))

local Style = {}

-- the Roblox importer turns glTF geometry 180 degrees about Y (glTF faces +Z)
local MESH_TURN = CFrame.Angles(0, math.pi, 0)
local LEFT_TURN = CFrame.Angles(0, math.pi, 0)
-- generic limb keys fit both sides; sleeves / legs turn for the left side,
-- shoes do not (the toe must stay forward)
local LIMB = { UpperArm = true, LowerArm = true, UpperLeg = true, LowerLeg = true, Foot = true }
local TURN_LEFT = { UpperArm = true, LowerArm = true, UpperLeg = true, LowerLeg = true }

-- the avatar's own pieces each slot covers
local AT = Enum.AccessoryType
local HIDES = {
	top = { [AT.Shirt] = true, [AT.TShirt] = true, [AT.Jacket] = true, [AT.Sweater] = true, [AT.DressSkirt] = true,
		[AT.Front] = true, [AT.Neck] = true, [AT.Shoulder] = true, [AT.Waist] = true },
	bottom = { [AT.Pants] = true, [AT.Shorts] = true, [AT.DressSkirt] = true },
	shoes = { [AT.LeftShoe] = true, [AT.RightShoe] = true },
	eyes = { [AT.Face] = true },
}

local templates = nil
local function template(name)
	if not templates then
		local root = ServerStorage:FindFirstChild("Exit6ProductionAssets")
		templates = root and root:FindFirstChild("Wear")
		if not templates then return nil end
	end
	local t = templates:FindFirstChild(name)
	return (t and t:IsA("MeshPart")) and t or nil
end

-- fit data: base wardrobe meshes, then the premium (px_*) meshes
local function meshInfo(name)
	return Meshes.Meshes[name] or PremiumMeshes.Meshes[name]
end
Style.MeshInfo = meshInfo

-- PBR sets (tools/studio/install_exit6_premium.luau); nil -> plain materials
local function surface(name)
	local root = ServerStorage:FindFirstChild("Exit6ProductionAssets")
	local folder = root and root:FindFirstChild("Surfaces")
	local sa = folder and folder:FindFirstChild(name)
	return (sa and sa:IsA("SurfaceAppearance")) and sa or nil
end

function Style.Installed()
	for name in pairs(Meshes.Meshes) do
		if not template(name) then return false, name end
	end
	return true
end

-- every piece of an item has its template in the place (premium items are
-- never sold or shown while their meshes are missing)
function Style.ItemReady(itemId)
	local it = Catalog.Items[itemId]
	if not it or it.kind ~= "wear" then return false end
	if game:GetAttribute("Exit6V31CharacterEnabled") == true then
		return it.v31Empty == true or (it.v31Asset ~= nil and V31.Ready(it.v31Asset))
	end
	if it.v31Only then return false end
	for _, piece in ipairs(it.pieces) do
		if not meshInfo(piece.mesh) or not template(piece.mesh) then return false, piece.mesh end
	end
	return true
end

local function c3(t) return Color3.fromRGB(t[1], t[2], t[3]) end

-- ---------------------------------------------------------------- avatar hiding
local function hideParts(inst, hide)
	for _, p in ipairs(inst:GetDescendants()) do
		if p:IsA("BasePart") then
			if p:GetAttribute("Exit6OrigT") == nil then p:SetAttribute("Exit6OrigT", p.Transparency) end
			p.Transparency = hide and 1 or p:GetAttribute("Exit6OrigT")
		end
	end
end
local function setClassic(char, className, hide)
	local prop = className == "ShirtGraphic" and "Graphic" or (className == "Shirt" and "ShirtTemplate" or "PantsTemplate")
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA(className) then
			if c:GetAttribute("Exit6Orig") == nil then c:SetAttribute("Exit6Orig", tostring(c[prop])) end
			c[prop] = hide and "" or c:GetAttribute("Exit6Orig")
		end
	end
end
local function hideOwn(char, look)
	-- the avatar's own hair goes under any EXIT 6 cut, and under headwear
	-- that covers the head (beanie / durag / mask / fitted cap)
	local hat = look.hat and Catalog.Items[look.hat]
	local hideHair = look.hair ~= nil or (hat ~= nil and (hat.hidesHair or hat.cap) == true)
	local hideHat = look.hat ~= nil or look.hair ~= nil
	for _, a in ipairs(char:GetChildren()) do
		if a:IsA("Accessory") then
			local t = a.AccessoryType
			local hide = (t == AT.Hair and hideHair) or (t == AT.Hat and hideHat)
			for slot, types in pairs(HIDES) do
				if look[slot] and types[t] then hide = true end
			end
			hideParts(a, hide)
		end
	end
	setClassic(char, "Shirt", look.top ~= nil)
	setClassic(char, "ShirtGraphic", look.top ~= nil)
	setClassic(char, "Pants", look.bottom ~= nil)
end

-- ---------------------------------------------------------------- fitting
local function weldPiece(char, folder, piece, item, offset, underTop)
	local info = meshInfo(piece.mesh)
	local tpl = template(piece.mesh)
	if not info or not tpl then return 0 end
	local role = Wardrobe.Roles[piece.role] or Wardrobe.Roles.main
	local color = item.colors and item.colors[piece.role]
	local key = info.part:gsub("^Left", ""):gsub("^Right", "")
	local canon = Meshes.Canon[key]
	local targets
	if LIMB[info.part] then
		targets = { { "Left" .. key, TURN_LEFT[key] }, { "Right" .. key, false } }
	else
		targets = { { info.part, false } }
	end
	local made = 0
	for _, t in ipairs(targets) do
		local body = char:FindFirstChild(t[1])
		if body and body:IsA("BasePart") and canon then
			local k = body.Size / canon
			local shift = offset or Vector3.zero
			if key == "Foot" then
				-- tall stylised feet: keep shoes / boot shafts at the footprint's
				-- scale and stand them on the sole instead of stretching them
				-- (average footprint scale: long narrow feet must not make
				-- boot shafts / high-top collars tower up the shin)
				local ky = math.min(k.Y, (k.X + k.Z) / 2)
				shift += Vector3.new(0, -(body.Size.Y - canon.Y * ky) / 2, 0)
				k = Vector3.new(k.X, ky, k.Z)
			end
			local local_ = (t[2] and LEFT_TURN or CFrame.identity) * CFrame.new(info.center * k + shift) * MESH_TURN
			local mp = tpl:Clone()
			mp.Name = piece.mesh
			mp.Size = info.size * k * ((underTop and piece.underTop) and Vector3.new(0.88, 1, 0.94) or Vector3.one)
			mp.CFrame = body.CFrame * local_
			mp.Material = role.material
			mp.Color = color and c3(color) or Color3.fromRGB(30, 30, 34)
			mp.Reflectance = role.reflectance or 0
			mp.Transparency = piece.alpha or role.alpha or 0
			mp.CastShadow = piece.role ~= "fade" and info.size.Magnitude > 0.35
			-- premium meshes carry UVs + tangents for their PBR set; tint it
			local sa = info.tex and role.surface and surface(role.surface)
			if sa then
				local s = sa:Clone()
				s.Color = mp.Color
				s.Parent = mp
			end
			local w = Instance.new("Weld")
			w.Name = "Exit6Fit"
			w.Part0, w.Part1 = body, mp
			w.C0 = local_
			w.Parent = mp
			mp.Parent = folder
			made += 1
		end
	end
	return made
end

-- what is actually worn: saved style + session preview, with the
-- hat / hair interplay resolved
local previews = {}   -- player -> { slot = itemId }
local function lookFor(player)
	local p = Profile.Get(player)
	local st = p and p.style or {}
	local pv = previews[player] or {}
	local look = {}
	local owned = st.owned or {}
	for _, slot in ipairs(Wardrobe.Slots) do
		local id = pv[slot]
		local previewed = id ~= nil
		if id == nil then id = st[slot] end
		local it = type(id) == "string" and Catalog.Items[id]
		-- premium pieces only render for owners (or while trying them on)
		if it and it.slot == slot and (previewed or not it.premium or owned[id] == true) then look[slot] = id end
	end
	local hat = look.hat and Catalog.Items[look.hat]
	local hair = look.hair and Catalog.Items[look.hair]
	if hat and hair and (hat.hidesHair or (hat.cap and not hair.showsUnderCap)) then
		look.hairHidden = true
	end
	return look
end

local function buildSlot(char, slot, itemId, look)
	local folderName = "Exit6Look_" .. slot
	local current = char:FindFirstChild(folderName)
	local want = itemId or ""
	if slot == "hair" and look.hairHidden then want = want .. "#hidden" end
	if slot == "chain" or slot == "neck" then want = want .. "@" .. tostring(look.top) end
	if slot == "bottom" and look.top then want = want .. "@top" end
	if current and current:GetAttribute("Item") == want then return end
	if current then current:Destroy() end
	if not itemId then return end
	local item = Catalog.Items[itemId]
	local folder = Instance.new("Folder")
	folder.Name = folderName
	folder:SetAttribute("Item", want)
	if not (slot == "hair" and look.hairHidden) then
		-- neck pieces sit on top of a bulky jacket
		local offset
		if slot == "chain" or slot == "neck" then
			local top = look.top and Catalog.Items[look.top]
			local depth = top and top.depth or 0
			offset = Vector3.new(0, depth * 0.4, -depth)
		end
		for _, piece in ipairs(item.pieces) do
			weldPiece(char, folder, piece, item, offset, look.top ~= nil)
		end
	end
	folder.Parent = char
end

-- skin tone: recolour the body through BodyColors (and the parts directly,
-- for rigs without one); the avatar's own colours are remembered for "off"
local SKIN_PARTS = {
	HeadColor3 = { "Head" },
	TorsoColor3 = { "UpperTorso", "LowerTorso" },
	LeftArmColor3 = { "LeftUpperArm", "LeftLowerArm", "LeftHand" },
	RightArmColor3 = { "RightUpperArm", "RightLowerArm", "RightHand" },
	LeftLegColor3 = { "LeftUpperLeg", "LeftLowerLeg", "LeftFoot" },
	RightLegColor3 = { "RightUpperLeg", "RightLowerLeg", "RightFoot" },
}
local function applySkin(char, index)
	local tone = type(index) == "number" and Wardrobe.SkinTones[index]
	local bc = char:FindFirstChildOfClass("BodyColors")
	for prop, parts in pairs(SKIN_PARTS) do
		if bc then
			if bc:GetAttribute("Exit6Orig" .. prop) == nil then bc:SetAttribute("Exit6Orig" .. prop, bc[prop]) end
			bc[prop] = tone and c3(tone.rgb) or bc:GetAttribute("Exit6Orig" .. prop)
		end
		for _, name in ipairs(parts) do
			local p = char:FindFirstChild(name)
			if p and p:IsA("BasePart") then
				if p:GetAttribute("Exit6OrigColor") == nil then p:SetAttribute("Exit6OrigColor", p.Color) end
				p.Color = tone and c3(tone.rgb) or p:GetAttribute("Exit6OrigColor")
			end
		end
	end
end

function Style.Apply(player)
	local char = player.Character
	local p = Profile.Get(player)
	if not char or not p or not char:FindFirstChild("Head") then return end
	local look = lookFor(player)
	if char:GetAttribute("Exit6V31") == true then
		V31.Apply(char, look, p.style, Catalog)
		local worn = {}
		for _, slot in ipairs(Wardrobe.Slots) do worn[slot] = look[slot] end
		player:SetAttribute("Exit6Wearing", game:GetService("HttpService"):JSONEncode(worn))
		return
	end
	for _, slot in ipairs(Wardrobe.Slots) do
		buildSlot(char, slot, look[slot], look)
	end
	hideOwn(char, look)
	applySkin(char, p.style.skin)
	-- mirror the worn look for the client (phone Closet / shop markers)
	local worn = {}
	for _, slot in ipairs(Wardrobe.Slots) do worn[slot] = look[slot] end
	player:SetAttribute("Exit6Wearing", game:GetService("HttpService"):JSONEncode(worn))
end

-- ---------------------------------------------------------------- actions
local function wearable(itemId)
	local it = Catalog.Items[itemId]
	return (it and it.kind == "wear") and it or nil
end

function Style.Owns(player, itemId)
	local p = Profile.Get(player)
	return p ~= nil and p.style.owned[itemId] == true
end

-- try an item on for this session only (shop counter)
function Style.Preview(player, itemId)
	local it = wearable(itemId)
	if not it or not Style.ItemReady(itemId) or not player.Character then return false end
	previews[player] = { [it.slot] = itemId }
	Style.Apply(player)
	return true
end

-- try a whole look on (premium boutique: an outfit bundle or one product);
-- look = { slot = itemId }, session only
function Style.PreviewLook(player, look)
	if not player.Character or type(look) ~= "table" then return false end
	local pv = {}
	for slot, id in pairs(look) do
		local it = wearable(id)
		if not it or it.slot ~= slot or not Style.ItemReady(id) then return false end
		pv[slot] = id
	end
	previews[player] = pv
	Style.Apply(player)
	return true
end

function Style.CancelPreview(player)
	if previews[player] then
		previews[player] = nil
		Style.Apply(player)
	end
end

function Style.Grant(player, itemId)
	local p = Profile.Get(player)
	if not p or not wearable(itemId) then return false end
	p.style.owned[itemId] = true
	return true
end

-- put on an owned item (bought now or earlier)
function Style.Equip(player, itemId)
	local it = wearable(itemId)
	local p = Profile.Get(player)
	if not it or not Style.ItemReady(itemId) or not p or not p.style.owned[itemId] then return false end
	p.style[it.slot] = itemId
	if p.style.tints then p.style.tints[it.slot] = nil end
	previews[player] = nil
	Profile.Publish(player)
	Style.Apply(player)
	return true
end

function Style.Unequip(player, slot)
	local p = Profile.Get(player)
	if not p or not Wardrobe.SlotNames[slot] then return false end
	p.style[slot] = nil
	if p.style.tints then p.style.tints[slot] = nil end
	previews[player] = nil
	Profile.Publish(player)
	Style.Apply(player)
	return true
end

-- back to the plain Roblox avatar (nothing from EXIT 6 worn)
function Style.UseOwnAvatar(player)
	local p = Profile.Get(player)
	if not p then return false end
	for _, slot in ipairs(Wardrobe.Slots) do p.style[slot] = nil end
	p.style.skin = nil
	previews[player] = nil
	Profile.Publish(player)
	Style.Apply(player)
	return true
end

-- skin tone (free): index into Wardrobe.SkinTones, 0 = the avatar's own colours
function Style.SetSkin(player, index)
	local p = Profile.Get(player)
	if not p or type(index) ~= "number" or index % 1 ~= 0
		or index < 0 or index > #Wardrobe.SkinTones then return false end
	if player.Character and player.Character:GetAttribute("Exit6V31") == true
		and index > 0 and not V31.SkinReady(index) then return false end
	p.style.skin = index > 0 and index or nil
	Profile.Publish(player)
	Style.Apply(player)
	return true
end

function Style.Recolor(player, slot, index)
	local p = Profile.Get(player)
	local id = p and p.style[slot]
	local item = id and Catalog.Items[id]
	if not item or not item.v31TintPalette or not Style.Owns(player, id)
		or type(index) ~= "number" or index % 1 ~= 0 or index < 1
		or index > #item.v31TintPalette then return false end
	p.style.tints = p.style.tints or {}
	p.style.tints[slot] = index
	Profile.Publish(player)
	Style.Apply(player)
	return true
end

-- chain over or under a compatible top (V3.1 layered wear; saved with the style and outfits)
function Style.SetChainLayer(player, layer)
	local p = Profile.Get(player)
	if not p or (layer ~= "over" and layer ~= "under") then return false end
	p.style.chainLayer = layer
	Profile.Publish(player)
	Style.Apply(player)
	return true
end

-- saved outfits (loadouts): up to Wardrobe.OutfitSlots looks in the profile
function Style.SaveOutfit(player, index)
	local p = Profile.Get(player)
	if not p or type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > Wardrobe.OutfitSlots then return false end
	local look = {}
	for _, slot in ipairs(Wardrobe.Slots) do
		if p.style[slot] then look[slot] = p.style[slot] end
	end
	look.tints = table.clone(p.style.tints or {})
	look.chainLayer = p.style.chainLayer
	p.style.outfits = p.style.outfits or {}
	p.style.outfits[tostring(index)] = look
	Profile.Publish(player)
	return true
end

function Style.WearOutfit(player, index)
	local p = Profile.Get(player)
	local outfits = p and p.style.outfits
	local look = type(index) == "number" and outfits and outfits[tostring(index)]
	if not look then return false end
	-- only what the player still owns; everything else in the outfit is off
	for _, slot in ipairs(Wardrobe.Slots) do
		local id = look[slot]
		local it = id and wearable(id)
		p.style[slot] = (it and it.slot == slot and p.style.owned[id]) and id or nil
	end
	p.style.tints = table.clone(look.tints or {})
	p.style.chainLayer = look.chainLayer
	previews[player] = nil
	Profile.Publish(player)
	Style.Apply(player)
	return true
end

function Style.ClearOutfit(player, index)
	local p = Profile.Get(player)
	if not p or not p.style.outfits or type(index) ~= "number" then return false end
	p.style.outfits[tostring(index)] = nil
	Profile.Publish(player)
	return true
end

-- wear several owned items at once (a bought outfit bundle)
function Style.EquipMany(player, ids)
	local p = Profile.Get(player)
	if not p then return false end
	for _, id in ipairs(ids) do
		local it = wearable(id)
		if it and p.style.owned[id] then p.style[it.slot] = id end
	end
	previews[player] = nil
	Profile.Publish(player)
	Style.Apply(player)
	return true
end

-- the free starter fit, put back on in one go
function Style.WearStarter(player)
	local p = Profile.Get(player)
	if not p then return false end
	for slot, id in pairs(Wardrobe.Starter) do
		p.style.owned[id] = true
		p.style[slot] = id
	end
	previews[player] = nil
	Profile.Publish(player)
	Style.Apply(player)
	return true
end

local function hook(player)
	player.CharacterAdded:Connect(function() task.defer(Style.Apply, player) end)
	player.CharacterAppearanceLoaded:Connect(function() task.defer(Style.Apply, player) end)
end
Players.PlayerAdded:Connect(hook)
for _, pl in ipairs(Players:GetPlayers()) do hook(pl) end
Players.PlayerRemoving:Connect(function(player) previews[player] = nil end)
Profile.Loaded:Connect(function(player) task.defer(Style.Apply, player) end)

-- Studio-only test hook: MCP play tests run in their own VM, so they dress
-- a player through this BindableFunction (never created in live servers)
if game:GetService("RunService"):IsStudio() then
	local hookFn = Instance.new("BindableFunction")
	hookFn.Name = "Exit6StyleTest"
	hookFn.OnInvoke = function(player, look)
		if look == "roundtrip" then
			-- save -> load through the real import path
			Profile.Import(player, Profile.Export(player))
			Style.Apply(player)
			return Profile.Get(player).style
		elseif type(look) == "table" and look.legacy then
			-- an old-format save (part-built / Hair Test ids, no owned list)
			Profile.Import(player, { style = look.legacy })
			Style.Apply(player)
			return Profile.Get(player).style
		end
		local p = Profile.Get(player)
		if not p then return false end
		if look.skin ~= nil then p.style.skin = look.skin ~= 0 and look.skin or nil end
		for _, slot in ipairs(Wardrobe.Slots) do
			local id = look[slot]
			if id ~= nil then
				p.style[slot] = id ~= false and id or nil
				if id then p.style.owned[id] = true end
			end
		end
		previews[player] = nil
		Profile.Publish(player)
		Style.Apply(player)
		return true
	end
	hookFn.Parent = ServerStorage
end

task.defer(function()
	local ok, missing = Style.Installed()
	if not ok then
		warn("[Exit6Style] wear mesh template missing: " .. tostring(missing)
			.. " (run tools/studio/install_exit6_wear.luau in the place)")
	end
end)

return Style
