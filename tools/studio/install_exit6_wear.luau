-- Studio Edit command: install the EXIT 6 wearable meshes as templates.
--
-- Uploaded assets (owner: the experience creator), newest wins by mesh name:
--   70526844842195  "Exit6 Wear v1"       all 61 meshes  -> Workspace.Exit6WearImport
--   111400965165098 "Exit6 Wear patch 1"  hair_afro_taper, cap_emblem, pendant_six
--                                          -> Workspace.Exit6WearPatch
--   116547797476710 "Exit6 Wear patch 2"  slim fit: 22 tops / sleeves / puffer /
--                                          shorts / jeans / shoes / hats / watch /
--                                          bracelet / headphones -> Workspace.Exit6WearPatch2
-- Full install: insert all three (Toolbox / insert_asset), then run this.
-- Patch only: insert just a patch into a place that already has Wear; the
-- folder is then updated in place.
-- Every MeshPart becomes ServerStorage.Exit6ProductionAssets.Wear.<name> with
-- cosmetic-safe physics. Premium px_* templates in Wear are always kept.
-- Exit6Style warns on any missing template.
-- Note: the importer turns glTF geometry 180 degrees about Y; Exit6Style
-- compensates (MESH_TURN), so do not rotate the templates here.
local ServerStorage = game:GetService("ServerStorage")
local base = workspace:FindFirstChild("Exit6WearImport")
local patches = {}
for _, name in ipairs({ "Exit6WearPatch", "Exit6WearPatch2" }) do
	local p = workspace:FindFirstChild(name)
	if p then table.insert(patches, p) end
end
local root = ServerStorage:FindFirstChild("Exit6ProductionAssets") or Instance.new("Folder")
root.Name = "Exit6ProductionAssets"
root.Parent = ServerStorage
local wear = root:FindFirstChild("Wear")
assert(base or wear, "insert asset 70526844842195 as Workspace.Exit6WearImport first")
if base then
	-- full rebuild of the base templates; premium px_* templates survive
	local fresh = Instance.new("Folder")
	fresh.Name = "Wear"
	if wear then
		for _, c in ipairs(wear:GetChildren()) do
			if c.Name:sub(1, 3) == "px_" then c.Parent = fresh end
		end
		wear:Destroy()
	end
	wear = fresh
end

local function take(src, allowReplace)
	local n = 0
	for _, d in ipairs(src:GetDescendants()) do
		if d:IsA("MeshPart") then
			local existing = wear:FindFirstChild(d.Name)
			assert(allowReplace or not existing, "duplicate mesh " .. d.Name)
			if existing then existing:Destroy() end
			local p = d:Clone()
			for _, c in ipairs(p:GetChildren()) do c:Destroy() end
			p.Anchored = false
			p.CanCollide, p.CanTouch, p.CanQuery = false, false, false
			p.Massless = true
			p.CollisionFidelity = Enum.CollisionFidelity.Box
			p.Material = Enum.Material.Fabric
			p.CFrame = CFrame.new()
			p.Parent = wear
			n += 1
		end
	end
	return n
end

if base then take(base, false) end
local patched = 0
for _, p in ipairs(patches) do patched += take(p, true) end
wear.Parent = root
if base then base:Destroy() end
for _, p in ipairs(patches) do p:Destroy() end
game:GetService("ChangeHistoryService"):SetWaypoint("Install Exit6 wear meshes")
print(("[Exit6Wear] Wear has %d templates (%d replaced by patches)"):format(#wear:GetChildren(), patched))
return #wear:GetChildren()
