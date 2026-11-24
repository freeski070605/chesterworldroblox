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
local Profile = require(script.Parent:WaitForChild("Exit6Profile"))

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

function Style.Installed()
	for name in pairs(Meshes.Meshes) do
		if not template(name) then return false, name end
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
	local info = Meshes.Meshes[piece.mesh]
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
				local ky = math.min(k.Y, math.max(k.X, k.Z))
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
			mp.CastShadow = piece.role ~= "fade"
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
	for _, slot in ipairs(Wardrobe.Slots) do
		local id = pv[slot]
		if id == nil then id = st[slot] end
		local it = type(id) == "string" and Catalog.Items[id]
		if it and it.slot == slot then look[slot] = id end
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

function Style.Apply(player)
	local char = player.Character
	if not char or not Profile.Get(player) or not char:FindFirstChild("Head") then return end
	local look = lookFor(player)
	for _, slot in ipairs(Wardrobe.Slots) do
		buildSlot(char, slot, look[slot], look)
	end
	hideOwn(char, look)
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
	if not it or not player.Character then return false end
	previews[player] = { [it.slot] = itemId }
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
	if not it or not p or not p.style.owned[itemId] then return false end
	p.style[it.slot] = itemId
	previews[player] = nil
	Profile.Publish(player)
	Style.Apply(player)
	return true
end

function Style.Unequip(player, slot)
	local p = Profile.Get(player)
	if not p or not Wardrobe.SlotNames[slot] then return false end
	p.style[slot] = nil
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
