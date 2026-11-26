--[[
Exit 6 V3.1 wear -> Accessories in the standalone character test place (NOT the live place).
Run after install_exit6_v31.luau has built ServerStorage.Exit6_V31_Character, then run
install_exit6_v31.luau again to dress the StarterCharacter / display copy.

Expects ServerStorage.Imp_Exit6_{Puffer,Cargo,Sneakers,Briefs,Jewelry} (Open Cloud inserts).
Positions: the importer centres each MeshPart on its bounding box and turns plain glTF 180 deg
about Y, so a mesh whose Blender game-frame bbox centre is (x, y, z) belongs at
LowerTorso.RootRigAttachment * (-x, z, y) (BBOX below, from wear_report / Exit6_Wear_V31.blend).
]]
local SS = game:GetService("ServerStorage")
local char = SS:FindFirstChild("Exit6_V31_Character")
assert(char, "run install_exit6_v31.luau first")
local root = char.LowerTorso.RootRigAttachment.WorldCFrame

local BBOX = { -- Blender game-frame bbox centres (studs)
	Exit6_Puffer = Vector3.new(-0.0004, 0.0228, 0.8297),
	Exit6_Cargo = Vector3.new(0.0004, -0.0040, -1.1728),
	Exit6_Sneakers = Vector3.new(0.0000, -0.0655, -2.7643),
	Exit6_Briefs = Vector3.new(0.0001, 0.0005, -0.2182),
	Exit6_Chain = Vector3.new(0.0006, 0.0175, 1.5838),
	Exit6_Chain_Over = Vector3.new(0.0003, -0.0007, 1.6100),
	Exit6_Watch = Vector3.new(0.8483, -0.0310, -0.1086),
}
local ITEMS = {
	-- mesh, import model, attachment, type, layer order, tint (nil = keep colours), default on
	{ "Exit6_Briefs", "Imp_Exit6_Briefs", "WaistCenterAttachment", Enum.AccessoryType.Shorts, 1, nil, true },
	{ "Exit6_Sneakers", "Imp_Exit6_Sneakers", "LeftFootAttachment", Enum.AccessoryType.Unknown, 3, nil, true },
	{ "Exit6_Cargo", "Imp_Exit6_Cargo", "WaistCenterAttachment", Enum.AccessoryType.Pants, 4, Color3.fromRGB(92, 96, 70), true },
	{ "Exit6_Puffer", "Imp_Exit6_Puffer", "BodyFrontAttachment", Enum.AccessoryType.Jacket, 6, Color3.fromRGB(34, 34, 38), true },
	{ "Exit6_Chain", "Imp_Exit6_Jewelry", "NeckAttachment", Enum.AccessoryType.Neck, nil, nil, false },
	{ "Exit6_Chain_Over", "Imp_Exit6_Jewelry", "NeckAttachment", Enum.AccessoryType.Neck, nil, nil, true },
	{ "Exit6_Watch", "Imp_Exit6_Jewelry", "Exit6WatchAttachment", Enum.AccessoryType.Unknown, nil, nil, true },
}

-- the watch rides the forearm: give the character a dedicated attachment at the watch centre
local lla = char.LeftLowerArm
local wa = lla:FindFirstChild("Exit6WatchAttachment") or Instance.new("Attachment")
wa.Name = "Exit6WatchAttachment"; wa.Parent = lla
local b = BBOX.Exit6_Watch
wa.WorldCFrame = root * CFrame.new(-b.X, b.Z, b.Y)

local folder = SS:FindFirstChild("Exit6_V31_Wear") or Instance.new("Folder")
folder.Name = "Exit6_V31_Wear"; folder.Parent = SS
local report = {}
for _, it in ITEMS do
	local meshName, imp, attName, accType, order, tint, on = table.unpack(it)
	local model = SS:FindFirstChild(imp)
	local src = model and model:FindFirstChild(meshName, true)
	if not src then
		table.insert(report, "missing " .. meshName)
		continue
	end
	local old = folder:FindFirstChild(meshName); if old then old:Destroy() end
	local m = src:Clone()
	for _, c in m:GetChildren() do if c:IsA("JointInstance") then c:Destroy() end end
	m.Name = "Handle"; m.Anchored = false; m.CanCollide = false; m.CanQuery = false; m.CanTouch = false; m.Massless = true
	local c = BBOX[meshName]
	m.CFrame = root * CFrame.new(-c.X, c.Z, c.Y)
	local target
	for _, a in char:GetDescendants() do
		if a:IsA("Attachment") and a.Name == attName and a.Parent:IsA("BasePart") and a.Parent.Name ~= "HumanoidRootPart" then
			target = a; break
		end
	end
	assert(target, "character has no " .. attName)
	local att = Instance.new("Attachment"); att.Name = attName; att.Parent = m
	att.WorldCFrame = target.WorldCFrame
	local wl = m:FindFirstChildOfClass("WrapLayer")
	if wl and order then wl.Order = order end
	local sa = m:FindFirstChildOfClass("SurfaceAppearance")
	if sa and tint then sa.Color = tint end
	local acc = Instance.new("Accessory")
	acc.Name = meshName; acc.AccessoryType = accType
	acc:SetAttribute("DefaultOn", on)
	acc:SetAttribute("Layered", wl ~= nil)
	m.Parent = acc; acc.Parent = folder
	table.insert(report, string.format("%s layered=%s order=%s att=%s", meshName, tostring(wl ~= nil), tostring(order), attName))
end
game:GetService("ChangeHistoryService"):SetWaypoint("Install Exit6 V3.1 wear")
return report
