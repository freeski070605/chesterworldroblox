workspace:SetAttribute("CW_BootstrapComplete", false)
workspace:SetAttribute("CW_RoadConformComplete", false)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldData = Shared:WaitForChild("WorldData")
local Tiles = WorldData:WaitForChild("Tiles")
local StreetData = require(Shared:WaitForChild("StreetData"))
local WorldPlacement = require(Shared:WaitForChild("WorldPlacement"))

local TileBuilder = require(script.Parent.World:WaitForChild("TileBuilderV3"))

local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = { workspace.Terrain }
terrainParams.IgnoreWater = false

local function terrainY(x, z)
	local hit = workspace:Raycast(
		Vector3.new(x, 5000, z),
		Vector3.new(0, -10000, 0),
		terrainParams
	)
	return hit and hit.Position.Y or 0
end

local spawnX = StreetData.spawn and StreetData.spawn.x or 0
local streetSpawnZ = StreetData.spawn and StreetData.spawn.z or 0
local spawnZ = -streetSpawnZ
local spawnLabel =
	StreetData.spawn
	and StreetData.spawn.resolved
	and StreetData.spawn.label
	or "Chester"

local sourceX =
	(spawnX / WorldPlacement.STUDS_PER_METER)
	+ WorldPlacement.CENTER_X_M
local sourceZ =
	(streetSpawnZ / WorldPlacement.STUDS_PER_METER)
	+ WorldPlacement.CENTER_Z_M

local spawnColumn = math.floor(sourceX / 1000)
local spawnRow = math.floor(sourceZ / 1000)

local function tileRowColumn(name)
	local rowText, colText = string.match(name, "^tile_r(%d+)_c(%d+)$")
	if not rowText then
		return nil, nil
	end
	return tonumber(rowText), tonumber(colText)
end

local modules = Tiles:GetChildren()

table.sort(modules, function(a, b)
	local ar, ac = tileRowColumn(a.Name)
	local br, bc = tileRowColumn(b.Name)

	if ar and ac and br and bc then
		local ad = math.abs(ar - spawnRow) + math.abs(ac - spawnColumn)
		local bd = math.abs(br - spawnRow) + math.abs(bc - spawnColumn)
		if ad ~= bd then
			return ad < bd
		end
	end

	return a.Name < b.Name
end)

print(("[ChesterWorld] Loading %d generated tile module(s)..."):format(#modules))
print(("[ChesterWorld] Prioritizing spawn tile near r%02d c%02d."):format(
	spawnRow,
	spawnColumn
))

-- Optional Studio preview: graph still reads every tile, but only nearby
-- tiles are rendered for a fast 9th/Kerlin intersection check.
local quickStreetPreview = workspace:GetAttribute("CW_QuickStreetPreview") == true
local tileBuildCount = quickStreetPreview and math.min(#modules, 5) or #modules

-- Build one global road graph before any tile renders. This prevents tile-edge
-- intersections from being missed and guarantees that each junction is owned
-- and rendered exactly once.
TileBuilder.Prepare(modules)
if quickStreetPreview then
    if TileBuilder.SetExpectedTiles then TileBuilder.SetExpectedTiles(tileBuildCount) end
    warn(("[ChesterWorld] QUICK STREET PREVIEW builds %d/%d tiles near spawn; disable CW_QuickStreetPreview for full map."):format(tileBuildCount, #modules))
end

local spawnReady = false
local spawnConnectionsReady = false

local function moveCharacter(character)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end

	while not spawnReady do
		task.wait()
	end

	task.wait()
	local y = terrainY(spawnX, spawnZ) + 12
	character:PivotTo(CFrame.new(spawnX, y, spawnZ))
end

local function setupPlayer(player)
	if player.Character then
		task.spawn(moveCharacter, player.Character)
	end
	player.CharacterAdded:Connect(moveCharacter)
end

local function enableSpawn()
	if spawnReady then
		return
	end

	local spawnY = terrainY(spawnX, spawnZ) + 8
	local position = Vector3.new(spawnX, spawnY, spawnZ)

	local spawn = workspace:FindFirstChild("ChesterCitySpawn")
	if not spawn then
		spawn = Instance.new("SpawnLocation")
		spawn.Name = "ChesterCitySpawn"
		spawn.Anchored = true
		spawn.CanCollide = false
		spawn.Transparency = 1
		spawn.Size = Vector3.new(8, 1, 8)
		spawn.Neutral = true
		spawn.Parent = workspace
	end

	spawn.CFrame = CFrame.new(position)
	spawn:SetAttribute("LocationLabel", spawnLabel)

	spawnReady = true
	-- the EXIT 6 loading screen (src/loading) follows the world build
	workspace:SetAttribute("CW_SpawnReady", true)

	if not spawnConnectionsReady then
		spawnConnectionsReady = true
		for _, player in ipairs(Players:GetPlayers()) do
			setupPlayer(player)
		end
		Players.PlayerAdded:Connect(setupPlayer)
	end

	print(("[ChesterWorld] Spawn ready: %s at %.1f, %.1f, %.1f"):format(
		spawnLabel,
		position.X,
		position.Y,
		position.Z
	))
end

workspace:SetAttribute("CW_TilesTotal", tileBuildCount)
workspace:SetAttribute("CW_TilesBuilt", 0)
for index = 1, tileBuildCount do
    local module = modules[index]
	if module:IsA("ModuleScript") then
		task.wait()

		local ok, result = pcall(TileBuilder.Build, module)
		if not ok then
			warn(("[ChesterWorld] Tile %s failed: %s"):format(
				module.Name,
				tostring(result)
			))
		end

		if index == 1 then
			enableSpawn()
		end

		workspace:SetAttribute("CW_TilesBuilt", index)
		if index % 5 == 0 or index == tileBuildCount then
			print(("[ChesterWorld] Built %d/%d tiles."):format(index, tileBuildCount))
		end

		task.wait()
	end
end

do
	local ok, RealBuildings = pcall(require, script.Parent:WaitForChild("World"):WaitForChild("RealBuildings"))
	if ok and RealBuildings.stats then
		local st = RealBuildings.stats
		print(("[ChesterWorld RealBuildings] homes=%d stores=%d shops=%d storefronts=%d frontDoors=%d backDoors=%d sideDoors=%d")
			:format(st.homes, st.stores, st.shops, st.storefronts, st.frontDoors, st.backDoors, st.sideDoors))
	end
end

if not spawnReady then
	enableSpawn()
end

workspace:SetAttribute("CW_BootstrapComplete", true)
print("[ChesterWorld] Bootstrap complete.")
