-- EXIT 6 look: barbershop cuts and clothing-store fits, worn over the
-- player's own avatar and saved in the profile (Exit6Profile.style).
-- No catalog assets: cuts and hats are built from parts on the head, fits
-- recolour the body under the avatar's own clothing (which is hidden, not
-- deleted, so "back to my own" restores it without a respawn).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Catalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Exit6Catalog"))
local Profile = require(script.Parent:WaitForChild("Exit6Profile"))

local Style = {}
local TEST_HAIR_NAME = "Exit6TestHair"
local HAIR = Color3.fromRGB(22, 17, 14)
local TOP_PARTS = { "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm" }
local SLEEVE_PARTS = { "LeftLowerArm", "RightLowerArm" }
local BOTTOM_PARTS = { "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" }
local TOP_WRAPS = {
	[Enum.AccessoryType.Shirt] = true, [Enum.AccessoryType.TShirt] = true, [Enum.AccessoryType.Jacket] = true,
	[Enum.AccessoryType.Sweater] = true, [Enum.AccessoryType.DressSkirt] = true,
}
local BOTTOM_WRAPS = { [Enum.AccessoryType.Pants] = true, [Enum.AccessoryType.Shorts] = true }

local function c3(t) return Color3.fromRGB(t[1], t[2], t[3]) end

-- hide / show an accessory's parts, remembering how it looked
local function hideAccessory(acc, hide)
	for _, p in ipairs(acc:GetDescendants()) do
		if p:IsA("BasePart") then
			if p:GetAttribute("Exit6OrigT") == nil then p:SetAttribute("Exit6OrigT", p.Transparency) end
			p.Transparency = hide and 1 or p:GetAttribute("Exit6OrigT")
		end
	end
end
local function setColor(char, names, color)
	for _, n in ipairs(names) do
		local p = char:FindFirstChild(n)
		if p and p:IsA("BasePart") then
			if p:GetAttribute("Exit6OrigColor") == nil then p:SetAttribute("Exit6OrigColor", p.Color) end
			p.Color = color or p:GetAttribute("Exit6OrigColor")
		end
	end
end
local function setClassic(char, className, hide)
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA(className) then
			local prop = className == "ShirtGraphic" and "Graphic" or (className == "Shirt" and "ShirtTemplate" or "PantsTemplate")
			if c:GetAttribute("Exit6Orig") == nil then c:SetAttribute("Exit6Orig", tostring(c[prop])) end
			c[prop] = hide and "" or c:GetAttribute("Exit6Orig")
		end
	end
end
local function accessoriesOf(char, test)
	local out = {}
	for _, a in ipairs(char:GetChildren()) do
		if a:IsA("Accessory") and test(a.AccessoryType) then table.insert(out, a) end
	end
	return out
end

local function testTemplate(assetId)
	local root = ServerStorage:FindFirstChild("Exit6ProductionAssets")
	local hair = root and root:FindFirstChild("Hair")
	local accessory = hair and hair:FindFirstChild(assetId)
	local handle = accessory and accessory:FindFirstChild("Handle")
	local attachment = handle and handle:FindFirstChild("HairAttachment")
	if accessory and accessory:IsA("Accessory") and handle and handle:IsA("MeshPart")
		and attachment and attachment:IsA("Attachment") and handle.MeshId ~= "" then
		return accessory
	end
	return nil
end

function Style.TestAssetAvailable(assetId)
	return type(assetId) == "string" and testTemplate(assetId) ~= nil
end

local function clearTestHair(char)
	local old = char:FindFirstChild(TEST_HAIR_NAME)
	if old then old:Destroy() end
end

local function applyTestHair(char, assetId)
	local template = testTemplate(assetId)
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not template or not humanoid or not char:FindFirstChild("Head") then return false end
	clearTestHair(char)
	local clone = template:Clone()
	clone.Name = TEST_HAIR_NAME
	local ok = pcall(function() humanoid:AddAccessory(clone) end)
	if not ok or clone.Parent ~= char then
		clone:Destroy()
		return false
	end
	local oldParts = char:FindFirstChild("Exit6Hair")
	if oldParts then oldParts:Destroy() end
	for _, a in ipairs(accessoriesOf(char, function(t) return t == Enum.AccessoryType.Hair end)) do
		if a ~= clone then hideAccessory(a, true) end
	end
	return true
end

-- a part welded to the head, in head space
local function headPart(char, folder, shape, size, offset, color, material)
	local head = char:FindFirstChild("Head")
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
	p.CFrame = head.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = head, p
	w.Parent = p
	p.Parent = folder
	return p
end

local function buildHair(char, style)
	local old = char:FindFirstChild("Exit6Hair")
	if old then old:Destroy() end
	local head = char:FindFirstChild("Head")
	if not head then return end
	for _, a in ipairs(accessoriesOf(char, function(t) return t == Enum.AccessoryType.Hair end)) do
		hideAccessory(a, style ~= nil and style ~= "own")
	end
	if not style or style == "own" or style == "bald" then return end
	local f = Instance.new("Folder")
	f.Name = "Exit6Hair"
	f.Parent = char
	local s = head.Size
	local top = s.Y * 0.18
	if style == "fade" or style == "waves" then
		headPart(char, f, Enum.PartType.Ball, Vector3.new(s.X * 1.03, s.Y * 0.62, s.Z * 1.03), CFrame.new(0, top, 0.02), HAIR,
			style == "waves" and Enum.Material.Fabric or Enum.Material.SmoothPlastic)
	elseif style == "afro" then
		headPart(char, f, Enum.PartType.Ball, Vector3.new(s.X * 1.55, s.Y * 1.25, s.Z * 1.5), CFrame.new(0, top + s.Y * 0.22, 0.08), HAIR,
			Enum.Material.Fabric)
	elseif style == "twists" then
		headPart(char, f, Enum.PartType.Ball, Vector3.new(s.X * 1.05, s.Y * 0.66, s.Z * 1.05), CFrame.new(0, top, 0.02), HAIR)
		for i = 0, 9 do
			local a = i / 10 * math.pi * 2
			headPart(char, f, Enum.PartType.Cylinder, Vector3.new(s.Y * 0.42, s.X * 0.16, s.X * 0.16),
				CFrame.new(math.cos(a) * s.X * 0.36, top + s.Y * 0.26, math.sin(a) * s.Z * 0.36) * CFrame.Angles(0, 0, math.rad(90))
					* CFrame.Angles(math.cos(a) * 0.35, 0, math.sin(a) * 0.35), HAIR)
		end
	elseif style == "high_top" then
  headPart(char,f,Enum.PartType.Block,Vector3.new(s.X*0.92,s.Y*0.9,s.Z*0.91),
   CFrame.new(0,s.Y*0.55,0),HAIR,Enum.Material.Fabric)
  headPart(char,f,Enum.PartType.Block,Vector3.new(s.X*0.94,s.Y*0.12,s.Z*0.94),
   CFrame.new(0,s.Y*0.14,0),HAIR)
 elseif style == "loc_short" or style == "loc_long" or style == "box_braids" then
  local long=style=="loc_long"
  local braided=style=="box_braids"
  headPart(char,f,Enum.PartType.Ball,Vector3.new(s.X*1.05,s.Y*0.5,s.Z*1.05),
   CFrame.new(0,top+s.Y*0.12,0),HAIR,Enum.Material.Fabric)
  local count=braided and 14 or (long and 16 or 12)
  for i=1,count do
   local a=(i-1)/count*math.pi*2
   local x=math.cos(a)*s.X*0.42
   local z=math.sin(a)*s.Z*0.42
   local len=(long and s.Y*0.9 or (braided and s.Y*0.75 or s.Y*0.42))
   local thickness=braided and s.X*0.075 or s.X*0.11
   headPart(char,f,Enum.PartType.Cylinder,Vector3.new(len,thickness,thickness),
    CFrame.new(x,top+s.Y*0.14-len*0.5,z),HAIR,Enum.Material.Fabric)
  end
	elseif style == "braids" then
		headPart(char, f, Enum.PartType.Ball, Vector3.new(s.X * 1.03, s.Y * 0.62, s.Z * 1.03), CFrame.new(0, top, 0.02), HAIR)
		for i = -2, 2 do
			headPart(char, f, Enum.PartType.Cylinder, Vector3.new(s.Z * 1.0, s.X * 0.12, s.X * 0.12),
				CFrame.new(i * s.X * 0.17, top + s.Y * 0.27 - math.abs(i) * s.Y * 0.05, 0.05) * CFrame.Angles(0, math.rad(90), 0), HAIR)
		end
	end
end

local function buildHat(char, itemId)
	local old = char:FindFirstChild("Exit6Hat")
	if old then old:Destroy() end
	local item = itemId and Catalog.Items[itemId]
	for _, a in ipairs(accessoriesOf(char, function(t) return t == Enum.AccessoryType.Hat end)) do
		hideAccessory(a, item ~= nil)
	end
	local head = char:FindFirstChild("Head")
	if not item or not head then return end
	local f = Instance.new("Folder")
	f.Name = "Exit6Hat"
	f.Parent = char
	local s, col = head.Size, c3(item.color)
	local top = s.Y * 0.2
	if item.hat == "beanie" then
		headPart(char, f, Enum.PartType.Ball, Vector3.new(s.X * 1.12, s.Y * 0.8, s.Z * 1.12), CFrame.new(0, top + s.Y * 0.05, 0.02), col,
			Enum.Material.Fabric)
		headPart(char, f, Enum.PartType.Cylinder, Vector3.new(s.Y * 0.16, s.X * 1.14, s.X * 1.14),
			CFrame.new(0, top - s.Y * 0.12, 0.02) * CFrame.Angles(0, 0, math.rad(90)), col, Enum.Material.Fabric)
	elseif item.hat == "cap" then
		headPart(char, f, Enum.PartType.Ball, Vector3.new(s.X * 1.1, s.Y * 0.72, s.Z * 1.1), CFrame.new(0, top + s.Y * 0.04, 0.02), col)
		headPart(char, f, Enum.PartType.Block, Vector3.new(s.X * 0.9, s.Y * 0.05, s.Z * 0.55),
			CFrame.new(0, top - s.Y * 0.06, -s.Z * 0.7), col)
	elseif item.hat == "durag" then
		headPart(char, f, Enum.PartType.Ball, Vector3.new(s.X * 1.06, s.Y * 0.68, s.Z * 1.06), CFrame.new(0, top, 0.02), col,
			Enum.Material.Fabric)
		headPart(char, f, Enum.PartType.Block, Vector3.new(s.X * 0.22, s.Y * 0.9, s.Z * 0.05),
			CFrame.new(0, -s.Y * 0.2, s.Z * 0.55), col, Enum.Material.Fabric)
	end
end

-- Lightweight garment details are welded to the body rather than recolouring
-- every item into an indistinguishable block. No marketplace asset IDs needed.
local function bodyDetail(char, folder, partName, name, size, offset, color, material)
 local body=char:FindFirstChild(partName)
 if not body or not body:IsA("BasePart") then return end
 local p=Instance.new("Part")
 p.Name=name;p.Size=size;p.Anchored=false;p.Massless=true
 p.CanCollide=false;p.CanTouch=false;p.CanQuery=false
 p.Material=material or Enum.Material.Fabric;p.Color=color
 p.CFrame=body.CFrame*offset
 local w=Instance.new("WeldConstraint")
 w.Part0=body;w.Part1=p;w.Parent=p;p.Parent=folder
end

local function buildTop(char, itemId)
	local item = itemId and Catalog.Items[itemId]
	setClassic(char, "Shirt", item ~= nil)
	setClassic(char, "ShirtGraphic", item ~= nil)
	for _, a in ipairs(accessoriesOf(char, function(t) return TOP_WRAPS[t] == true end)) do hideAccessory(a, item ~= nil) end
	setColor(char, TOP_PARTS, item and c3(item.color) or nil)
	setColor(char, SLEEVE_PARTS, item and item.hood and c3(item.color) or nil)
	local old = char:FindFirstChild("Exit6Hood")
	if old then old:Destroy() end
 local oldFit=char:FindFirstChild("Exit6TopDetails")
 if oldFit then oldFit:Destroy() end
 if item then
  local f=Instance.new("Folder");f.Name="Exit6TopDetails";f.Parent=char
  local torso=char:FindFirstChild("UpperTorso")
  if torso then
   if item.puffer then
    bodyDetail(char,f,"UpperTorso","PufferFront",Vector3.new(torso.Size.X*1.08,torso.Size.Y*0.92,0.26),
     CFrame.new(0,0,-torso.Size.Z*0.52),c3(item.color))
    for i=-1,1 do
     bodyDetail(char,f,"UpperTorso","QuiltSeam",Vector3.new(torso.Size.X*1.08,0.055,0.3),
      CFrame.new(0,i*torso.Size.Y*0.25,-torso.Size.Z*0.54),Color3.fromRGB(75,77,82))
    end
   elseif item.accent then
    bodyDetail(char,f,"UpperTorso","JacketZip",Vector3.new(0.065,torso.Size.Y*0.8,0.09),
     CFrame.new(0,0,-torso.Size.Z*0.55),c3(item.accent))
   end
  end
 end
	if item and item.hood and char:FindFirstChild("Head") then
		local f = Instance.new("Folder")
		f.Name = "Exit6Hood"
		f.Parent = char
		local s = char.Head.Size
		headPart(char, f, Enum.PartType.Block, Vector3.new(s.X * 1.25, s.Y * 0.5, s.Z * 0.5),
			CFrame.new(0, -s.Y * 0.55, s.Z * 0.45), c3(item.color), Enum.Material.Fabric)
	end
end

local function buildBottom(char, itemId)
	local item = itemId and Catalog.Items[itemId]
	setClassic(char, "Pants", item ~= nil)
	for _, a in ipairs(accessoriesOf(char, function(t) return BOTTOM_WRAPS[t] == true end)) do hideAccessory(a, item ~= nil) end
	setColor(char, BOTTOM_PARTS, item and c3(item.color) or nil)
 local old=char:FindFirstChild("Exit6BottomDetails")
 if old then old:Destroy() end
 if item and (item.stacked or item.accent) then
  local f=Instance.new("Folder");f.Name="Exit6BottomDetails";f.Parent=char
  for _,legName in ipairs({"LeftLowerLeg","RightLowerLeg"}) do
   local leg=char:FindFirstChild(legName)
   if leg then
    if item.stacked then
     for i=1,3 do
      bodyDetail(char,f,legName,"DenimFold",Vector3.new(leg.Size.X*1.06,0.08,leg.Size.Z*1.06),
       CFrame.new(0,-leg.Size.Y*0.3+(i-1)*0.18,0),Color3.fromRGB(65,76,96))
     end
    elseif item.accent then
     bodyDetail(char,f,legName,"TrackStripe",Vector3.new(0.075,leg.Size.Y*0.9,0.09),
      CFrame.new(legName=="LeftLowerLeg" and -leg.Size.X*0.51 or leg.Size.X*0.51,0,0),c3(item.accent))
    end
   end
  end
 end
end

function Style.Apply(player)
	local char = player.Character
	local p = Profile.Get(player)
	if not char or not p or not char:FindFirstChild("Head") then return end
	local st = p.style
	local hair = st.hair and Catalog.Items[st.hair]
	clearTestHair(char)
	if not (hair and hair.assetId and applyTestHair(char, hair.assetId)) then
		buildHair(char, hair and hair.style or nil)
	end
	buildHat(char, st.hat)
	buildTop(char, st.top)
	buildBottom(char, st.bottom)
end

function Style.PreviewTestHair(player, assetId)
	local char = player.Character
	if not char or not Profile.Get(player) then return false end
	return applyTestHair(char, assetId)
end

function Style.EquipTestHair(player, assetId)
	local itemId = "test_hair_" .. tostring(assetId)
	local item = Catalog.Items[itemId]
	local p = Profile.Get(player)
	if not item or not item.testOnly or not p or not testTemplate(assetId) or not player.Character then return false end
	if not applyTestHair(player.Character, assetId) then return false end
	p.style.hair = itemId
	Profile.Publish(player)
	return true
end

function Style.RestoreOwnHair(player)
	local p = Profile.Get(player)
	if not p then return false end
	p.style.hair = nil
	Profile.Publish(player)
	Style.Apply(player)
	return true
end

-- wear a bought cut / piece (catalog kinds "haircut" / "clothing")
function Style.Wear(player, itemId)
	local item = Catalog.Items[itemId]
	local p = Profile.Get(player)
	if not item or not p then return false end
	if item.testOnly then
		-- Hair Test entries may be equipped through the barbershop only when
		-- the actual mesh is installed. Keep the saved profile key unchanged.
		if item.kind ~= "haircut" or not testTemplate(item.assetId) or not player.Character then return false end
		if not applyTestHair(player.Character, item.assetId) then return false end
		p.style.hair = itemId
		Profile.Publish(player)
		return true
	end
	if item.kind == "haircut" then
		p.style.hair = (item.style ~= "own") and itemId or nil
	elseif item.kind == "clothing" then
		if item.slot == "reset" then
			p.style.top, p.style.bottom, p.style.hat = nil, nil, nil
		else
			p.style[item.slot] = itemId
		end
	else
		return false
	end
	Profile.Publish(player)
	Style.Apply(player)
	return true
end

local function hook(player)
	player.CharacterAppearanceLoaded:Connect(function() task.defer(Style.Apply, player) end)
end
Players.PlayerAdded:Connect(hook)
for _, pl in ipairs(Players:GetPlayers()) do hook(pl) end
Profile.Loaded:Connect(function(player) task.defer(Style.Apply, player) end)

return Style
