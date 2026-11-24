-- Studio Edit command: install the EXIT 6 Premium meshes + texture sets.
--
-- 1. Insert, newest last (a later import replaces meshes of the same name):
--      79525151931765  "Exit6 Premium v1"       all 36 meshes -> Workspace.Exit6PremiumImport
--      129965163941748 "Exit6 Premium patch 1"  9 lighter puffer / cargo / high-top meshes
--                                                -> Workspace.Exit6PremiumPatch1
-- 2. Run this. Every px_* MeshPart becomes a template in
--    ServerStorage.Exit6ProductionAssets.Wear (next to the base wardrobe), and
--    every texture set becomes ServerStorage.Exit6ProductionAssets.Surfaces.<set>
--    (a SurfaceAppearance Exit6Style clones onto pieces and tints per item).
-- Image ids: assets/wear/premium/uploads.json. Re-running replaces both.
-- Setting SurfaceAppearance maps needs plugin security (command bar / MCP Edit).
-- Save / publish the place afterwards: templates live only in the place file.
local ServerStorage = game:GetService("ServerStorage")

local SETS = {
	pave = { 96263780496031, 101855855010741, 120971305455033, 72219169611011 },
	metal = { 124141951325839, 78198224979243, 123632756044323, 106795537735599 },
	nylon = { 72582694948204, 71758027244946, 97652630943071 },
	fleece = { 139694740890408, 103214488899613, 93783746180419 },
	knit = { 128687101975894, 97432176287209, 90489567031265 },
	leather = { 106253754689630, 123900542500442, 72500476441774 },
	rubber = { 77654006650020, 114443497046839, 82166193064545 },
	locs = { 106508338453156, 133289455080385, 129663155916191 },
}

local root = ServerStorage:FindFirstChild("Exit6ProductionAssets")
assert(root and root:FindFirstChild("Wear"), "install the base wardrobe first (install_exit6_wear.luau)")
local wear = root.Wear

local moved = 0
for _, importName in ipairs({ "Exit6PremiumImport", "Exit6PremiumPatch1" }) do
	local import = workspace:FindFirstChild(importName)
	if not import then continue end
	for _, d in ipairs(import:GetDescendants()) do
		if d:IsA("MeshPart") and d.Name:sub(1, 3) == "px_" then
			local old = wear:FindFirstChild(d.Name)
			if old then old:Destroy() end
			local p = d:Clone()
			for _, c in ipairs(p:GetChildren()) do c:Destroy() end
			p.Anchored = false
			p.CanCollide, p.CanTouch, p.CanQuery = false, false, false
			p.Massless = true
			p.CastShadow = true
			p.CollisionFidelity = Enum.CollisionFidelity.Box
			p.RenderFidelity = Enum.RenderFidelity.Automatic
			p.Material = Enum.Material.SmoothPlastic
			p.CFrame = CFrame.new()
			p.Parent = wear
			moved += 1
		end
	end
	import:Destroy()
end

local old = root:FindFirstChild("Surfaces")
if old then old:Destroy() end
local surfaces = Instance.new("Folder")
surfaces.Name = "Surfaces"
for name, ids in pairs(SETS) do
	local sa = Instance.new("SurfaceAppearance")
	sa.Name = name
	sa.ColorMap = "rbxassetid://" .. ids[1]
	sa.NormalMap = "rbxassetid://" .. ids[2]
	sa.RoughnessMap = "rbxassetid://" .. ids[3]
	if ids[4] then sa.MetalnessMap = "rbxassetid://" .. ids[4] end
	sa.AlphaMode = Enum.AlphaMode.Overlay
	sa.Parent = surfaces
end
surfaces.Parent = root

local px = 0
for _, c in ipairs(wear:GetChildren()) do
	if c.Name:sub(1, 3) == "px_" then px += 1 end
end
game:GetService("ChangeHistoryService"):SetWaypoint("Install Exit6 premium meshes")
print(("[Exit6Premium] %d meshes moved, %d px_ templates in Wear, %d surface sets"):format(moved, px, #surfaces:GetChildren()))
return { moved = moved, px = px, surfaces = #surfaces:GetChildren() }
