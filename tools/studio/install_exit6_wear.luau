-- Studio Edit command: install the EXIT 6 wearable meshes as templates.
--
-- Uploaded assets (owner: the experience creator), newest wins by mesh name:
--   70526844842195  "Exit6 Wear v1"       all 61 meshes  -> Workspace.Exit6WearImport
--   111400965165098 "Exit6 Wear patch 1"  hair_afro_taper, cap_emblem, pendant_six
--                                          -> Workspace.Exit6WearPatch
-- Insert both (Toolbox / insert_asset), then run this. Every MeshPart becomes
-- ServerStorage.Exit6ProductionAssets.Wear.<name> with cosmetic-safe physics.
-- Re-running replaces the folder. Exit6Style warns on any missing template.
-- Note: the importer turns glTF geometry 180 degrees about Y; Exit6Style
-- compensates (MESH_TURN), so do not rotate the templates here.
local ServerStorage = game:GetService("ServerStorage")
local base = workspace:FindFirstChild("Exit6WearImport")
local patch = workspace:FindFirstChild("Exit6WearPatch")
assert(base, "insert asset 70526844842195 as Workspace.Exit6WearImport first")
local root = ServerStorage:FindFirstChild("Exit6ProductionAssets") or Instance.new("Folder")
root.Name = "Exit6ProductionAssets"
root.Parent = ServerStorage
local old = root:FindFirstChild("Wear")
if old then old:Destroy() end
local wear = Instance.new("Folder")
wear.Name = "Wear"

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

local count = take(base, false)
local patched = patch and take(patch, true) or 0
wear.Parent = root
base:Destroy()
if patch then patch:Destroy() end
game:GetService("ChangeHistoryService"):SetWaypoint("Install Exit6 wear meshes")
print(("[Exit6Wear] installed %d meshes (%d replaced by the patch)"):format(#wear:GetChildren(), patched))
return #wear:GetChildren()
