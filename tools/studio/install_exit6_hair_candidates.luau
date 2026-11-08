-- Run in Studio Edit mode after importing the 12 OBJ meshes into a single
-- selected Folder or Model. This preserves the original imports and installs
-- clones as candidates. It never marks assets validated or changes the shop.
local Selection = game:GetService("Selection")
local ServerStorage = game:GetService("ServerStorage")
local names = {
	sharp_low_taper = true, mid_skin_fade = true, high_top_fade = true,
	waves_360 = true, starter_locs = true, medium_locs = true,
	shoulder_locs = true, two_strand_twists = true, cornrows = true,
	box_braids = true, afro_taper = true, braided_ponytail = true,
}
local selected = Selection:Get()
assert(#selected == 1, "Select the one folder/model containing imported OBJ MeshParts")
local source = selected[1]
local imports = {}
for _, child in ipairs(source:GetDescendants()) do
	if child:IsA("MeshPart") and names[child.Name] then
		assert(not imports[child.Name], "Duplicate imported MeshPart: " .. child.Name)
		imports[child.Name] = child
	end
end
local importCount = 0
for name in pairs(names) do
	assert(imports[name], "Missing imported MeshPart: " .. name)
	importCount += 1
end
assert(importCount == 12, "Expected exactly 12 styles")
local root = ServerStorage:FindFirstChild("Exit6ProductionAssets") or Instance.new("Folder")
root.Name = "Exit6ProductionAssets"
root.Parent = ServerStorage
local hair = root:FindFirstChild("Hair") or Instance.new("Folder")
hair.Name = "Hair"
hair.Parent = root
for name in pairs(names) do
	assert(not hair:FindFirstChild(name), "Candidate already installed: " .. name)
end
local installed = {}
for name, child in pairs(imports) do
		local accessory = Instance.new("Accessory")
		accessory.Name = name
		accessory.AccessoryType = Enum.AccessoryType.Hair
		accessory:SetAttribute("Exit6AssetId", name)
		accessory:SetAttribute("Exit6Category", "hair")
		accessory:SetAttribute("Exit6Quality", "candidate_unverified")
		accessory:SetAttribute("Exit6Version", 1)
		local handle = child:Clone()
		handle.Name = "Handle"
		handle.Anchored = false
		handle.CanCollide = false
		handle.CanTouch = false
		handle.CanQuery = false
		handle.Massless = true
		handle.Material = Enum.Material.Fabric
		handle.Color = Color3.fromRGB(22, 17, 14)
		local attachment = Instance.new("Attachment")
		attachment.Name = "HairAttachment"
		attachment.Position = Vector3.new(0, 0.5, 0)
		-- Imported OBJ is authored in Head-local coordinates. Verify importer
		-- origin/pivot before equipping: a shifted origin requires a correction.
		attachment.Parent = handle
		handle.Parent = accessory
		accessory.Parent = hair
		table.insert(installed, name)
end
table.sort(installed)
print("EXIT6 installed candidate hair: " .. table.concat(installed, ", "))
assert(#installed == 12, "Expected 12 imported MeshParts; found " .. #installed)
return installed
