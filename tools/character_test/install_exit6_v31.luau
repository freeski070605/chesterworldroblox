--[[
Exit 6 male V3.1 -> standalone character test place (E:\RobloxStudio\Exit6_CharacterTest.rbxl).
NOT for the live Exit 6 place.

Expects in ServerStorage (inserted from Open Cloud uploads):
  Exit6_V31_BodyImport   body asset: R15 MeshParts + WrapTargets + Humanoid + HumanoidRootPart
  Exit6_V31_PartsImport  separate pieces: Hair_Geo, Eyes_Geo, Brows_Geo, Goatee_Geo, Briefs_Geo
Optional (wear pipeline): ServerStorage.Exit6_V31_Wear.<Item> models with WrapLayer meshes, Exit6_Jewelry.

Builds:
  ServerStorage.Exit6_V31_Character   rig with accessories (hair / brows / goatee) and eyes welded to Head
  StarterPlayer.StarterCharacter      copy of it, so Play spawns as V3.1 with default R15 animations
  Workspace.Exit6_V31_Display         anchored copy beside the spawn for screenshots
Returns a report table.
]]
local SS = game:GetService("ServerStorage")
local body0 = SS:FindFirstChild("Exit6_V31_BodyImport")
local parts0 = SS:FindFirstChild("Exit6_V31_PartsImport")
assert(body0 and parts0, "insert the V3.1 body and parts assets into ServerStorage first")

local report = { moved = {}, accessories = {}, warnings = {} }

-- accessory attachment -> body part (Roblox R15 convention)
local ATT_PART = {
	FaceCenterAttachment = "Head", FaceFrontAttachment = "Head", HairAttachment = "Head", HatAttachment = "Head",
	NeckAttachment = "UpperTorso", BodyFrontAttachment = "UpperTorso", BodyBackAttachment = "UpperTorso",
	LeftCollarAttachment = "UpperTorso", RightCollarAttachment = "UpperTorso",
	WaistCenterAttachment = "LowerTorso", WaistFrontAttachment = "LowerTorso", WaistBackAttachment = "LowerTorso",
	LeftShoulderAttachment = "LeftUpperArm", RightShoulderAttachment = "RightUpperArm",
	LeftGripAttachment = "LeftHand", RightGripAttachment = "RightHand",
	LeftFootAttachment = "LeftFoot", RightFootAttachment = "RightFoot",
}

local char = body0:Clone()
char.Name = "Exit6_V31_Character"
for _, d in char:GetDescendants() do
	if d:IsA("PackageLink") then d:Destroy() end
end
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
assert(hrp and hum, "body import has no HumanoidRootPart / Humanoid")
char.PrimaryPart = hrp

-- 1) accessory attachments: the importer put them on HumanoidRootPart; move them onto their parts
for _, a in hrp:GetChildren() do
	if a:IsA("Attachment") and ATT_PART[a.Name] then
		local part = char:FindFirstChild(ATT_PART[a.Name])
		if part then
			local wcf = a.WorldCFrame
			a.Parent = part
			a.WorldCFrame = wcf
			local ov = a:FindFirstChild("OriginalPosition")
			if ov then ov.Value = a.Position end
			table.insert(report.moved, a.Name .. "->" .. part.Name)
		end
	end
end

-- watch attachment on the forearm (Blender game-frame watch centre (0.8483, -0.031, -0.1086))
do
	local wa = Instance.new("Attachment"); wa.Name = "Exit6WatchAttachment"; wa.Parent = char.LeftLowerArm
	wa.WorldCFrame = char.LowerTorso.RootRigAttachment.WorldCFrame * CFrame.new(-0.8483, -0.1086, -0.031)
end

-- 2) align the parts model to the body: both were exported with the rig root at the LowerTorso joint
local pieces = parts0:Clone()
for _, d in pieces:GetDescendants() do
	if d:IsA("PackageLink") then d:Destroy() end
end
local rootBone = pieces:FindFirstChild("Root", true)
local lt = char:FindFirstChild("LowerTorso")
local ltRoot = lt and lt:FindFirstChild("RootRigAttachment")
assert(rootBone and ltRoot, "cannot find the rig roots to align the parts")
-- the importer turns plain glTF geometry 180 deg about Y but not the skinned body: undo that turn
local delta = ltRoot.WorldCFrame * CFrame.Angles(0, math.pi, 0) * rootBone.WorldCFrame:Inverse()
for _, p in pieces:GetDescendants() do
	if p:IsA("BasePart") then p.CFrame = delta * p.CFrame end
end

local function bareMesh(name)
	local m = pieces:FindFirstChild(name, true)
	if not m then
		table.insert(report.warnings, "missing " .. name)
		return nil
	end
	for _, c in m:GetChildren() do
		if c:IsA("JointInstance") then c:Destroy() end
	end
	m.Anchored = false; m.CanCollide = false; m.CanQuery = false; m.CanTouch = false; m.Massless = true
	return m
end

local function makeAccessory(meshName, accName, attName, accType)
	local m = bareMesh(meshName)
	if not m then return end
	local target
	for _, a in char:GetDescendants() do
		if a:IsA("Attachment") and a.Name == attName and a.Parent ~= hrp then target = a break end
	end
	if not target then
		table.insert(report.warnings, "no character attachment " .. attName)
		return
	end
	local acc = Instance.new("Accessory")
	acc.Name = accName
	acc.AccessoryType = accType
	m.Name = "Handle"
	local att = Instance.new("Attachment")
	att.Name = attName
	att.Parent = m
	att.WorldCFrame = target.WorldCFrame -- the piece is already in place: the handle attachment coincides
	m.Parent = acc
	acc.Parent = SS
	table.insert(report.accessories, accName .. "@" .. attName)
	return acc
end

local accessories = {
	makeAccessory("Hair_Geo", "Exit6_Hair_Twists", "HairAttachment", Enum.AccessoryType.Hair),
	makeAccessory("Brows_Geo", "Exit6_Brows", "FaceFrontAttachment", Enum.AccessoryType.Eyebrow),
	makeAccessory("Goatee_Geo", "Exit6_Goatee", "FaceFrontAttachment", Enum.AccessoryType.Face),
}

-- 3) eyes are part of the head: weld them
local eyes = bareMesh("Eyes_Geo")
if eyes then
	eyes.Name = "Eyes"
	eyes.Parent = char.Head
	local w = Instance.new("WeldConstraint"); w.Part0 = char.Head; w.Part1 = eyes; w.Parent = eyes
end

-- keep the separate pieces as reusable templates
local lib = SS:FindFirstChild("Exit6_V31_Accessories") or Instance.new("Folder")
lib.Name = "Exit6_V31_Accessories"; lib.Parent = SS
for _, acc in accessories do
	if acc then
		local old = lib:FindFirstChild(acc.Name); if old then old:Destroy() end
		acc.Parent = lib
	end
end
local briefs = bareMesh("Briefs_Geo")
if briefs then briefs.Parent = lib; briefs.Name = "Briefs_Static" end
pieces:Destroy()

-- 4) dress: accessories via the Humanoid (joins them to the matching attachments)
for _, acc in accessories do
	if acc then
		hum:AddAccessory(acc:Clone())
	end
end
-- layered wear when present (Exit6_V31_Wear.<Item> = Accessory with a WrapLayer handle)
local wear = SS:FindFirstChild("Exit6_V31_Wear")
if wear then
	for _, acc in wear:GetChildren() do
		if acc:IsA("Accessory") and acc:GetAttribute("DefaultOn") ~= false then
			hum:AddAccessory(acc:Clone())
			table.insert(report.accessories, "wear:" .. acc.Name)
		end
	end
end

hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
local old = SS:FindFirstChild("Exit6_V31_Character"); if old and old ~= char then old:Destroy() end
char.Parent = SS

-- 5) StarterCharacter + display copy
local sp = game:GetService("StarterPlayer")
local oldStarter = sp:FindFirstChild("StarterCharacter"); if oldStarter then oldStarter:Destroy() end
local starter = char:Clone(); starter.Name = "StarterCharacter"; starter.Parent = sp

local oldDisp = workspace:FindFirstChild("Exit6_V31_Display"); if oldDisp then oldDisp:Destroy() end
local disp = char:Clone(); disp.Name = "Exit6_V31_Display"
for _, p in disp:GetDescendants() do
	if p:IsA("BasePart") then p.Anchored = (p.Name == "HumanoidRootPart") end
end
disp.Parent = workspace
local h = disp:FindFirstChildOfClass("Humanoid")
local hip = h.HipHeight
disp:PivotTo(CFrame.new(0, hrp.Size.Y / 2 + hip, 0))

-- report
local minY, maxY = math.huge, -math.huge
for _, p in disp:GetDescendants() do
	if p:IsA("MeshPart") and p.Parent == disp then
		minY = math.min(minY, p.Position.Y - p.Size.Y / 2); maxY = math.max(maxY, p.Position.Y + p.Size.Y / 2)
	end
end
report.height = maxY - minY
report.feetY = minY
report.hipHeight = hip
report.rigType = tostring(h.RigType)
local wraps = 0
for _, d in disp:GetDescendants() do if d:IsA("WrapTarget") then wraps += 1 end end
report.wrapTargets = wraps
game:GetService("ChangeHistoryService"):SetWaypoint("Install Exit6 V3.1 test character")
return report
