-- Read-only place audit after batch import. Run in Studio Edit mode.
local ServerStorage = game:GetService("ServerStorage")
local Catalog = require(game:GetService("ReplicatedStorage").Shared.Exit6Catalog)
local root = ServerStorage:FindFirstChild("Exit6ProductionAssets")
local hair = root and root:FindFirstChild("Hair")
local expected = {}
local installed = 0
for _, entry in ipairs(Catalog.HairTest) do
	expected[entry.id] = true
	local accessory = hair and hair:FindFirstChild(entry.id)
	local handle = accessory and accessory:FindFirstChild("Handle")
	local attachment = handle and handle:FindFirstChild("HairAttachment")
	local good = accessory and accessory:IsA("Accessory") and handle and handle:IsA("MeshPart")
		and handle.MeshId ~= "" and attachment and attachment:IsA("Attachment")
	if good then installed += 1 end
	print(string.format("EXIT6 HAIR %s %s mesh=%s size=%s", entry.id,
		good and "INSTALLED" or "MISSING/INVALID", handle and handle:IsA("MeshPart") and handle.MeshId or "",
		handle and tostring(handle.Size) or ""))
end
local extra = 0
for _, child in ipairs(hair and hair:GetChildren() or {}) do
	if not expected[child.Name] then extra += 1 warn("Unexpected hair asset: " .. child.Name) end
end
print(string.format("EXIT6 HAIR TEST LIBRARY: %d/12 installed; %d extra", installed, extra))
return installed == 12 and extra == 0
