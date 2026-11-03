local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldConfig = require(Shared:WaitForChild("WorldConfig"))

local BaseBuilder = require(script.Parent:WaitForChild("TileBuilderV2"))

local TileBuilderV3 = {}

local PAD_MARGIN_STUDS = 1.5
local totalTiles = 0
local builtTiles = 0
local meshPadsReplaced = 0
local fallbackPadsKept = 0
local solidPadsBuilt = 0

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

	return hit and hit.Position.Y or nil
end

local function intersectionFrame(x, z, radius)
	local centerGround = terrainY(x, z)
	if centerGround == nil then
		return nil
	end

	local sample = math.clamp(radius * 0.28, 4, 12)
	local east = terrainY(x + sample, z) or centerGround
	local west = terrainY(x - sample, z) or centerGround
	local south = terrainY(x, z + sample) or centerGround
	local north = terrainY(x, z - sample) or centerGround

	local gradeX = math.clamp(
		(east - west) / (sample * 2),
		-WorldConfig.INTERSECTION_MAX_GRADE,
		WorldConfig.INTERSECTION_MAX_GRADE
	)

	local gradeZ = math.clamp(
		(south - north) / (sample * 2),
		-WorldConfig.INTERSECTION_MAX_GRADE,
		WorldConfig.INTERSECTION_MAX_GRADE
	)

	local up = Vector3.new(-gradeX, 1, -gradeZ).Unit
	local right = Vector3.new(1, gradeX, 0).Unit
	local back = right:Cross(up).Unit
	right = up:Cross(back).Unit

	return CFrame.fromMatrix(
		Vector3.new(
			x,
			centerGround + WorldConfig.ROAD_SURFACE_OFFSET_STUDS,
			z
		),
		right,
		up,
		back
	)
end

local function copyIntersectionLabel(source, target)
	local label = source:GetAttribute("Intersection")
	if label ~= nil then
		target:SetAttribute("Intersection", label)
	end
end

local function buildSolidPad(source)
	local sizeX = math.max(source.Size.X + PAD_MARGIN_STUDS * 2, 8)
	local sizeZ = math.max(source.Size.Z + PAD_MARGIN_STUDS * 2, 8)
	local thickness = WorldConfig.ROAD_THICKNESS_STUDS + 0.10
	local radius = math.max(sizeX, sizeZ) / 2

	local frame = intersectionFrame(
		source.Position.X,
		source.Position.Z,
		radius
	)

	if not frame then
		return nil
	end

	local pad = Instance.new("Part")
	pad.Name = "Intersection"
	pad.Anchored = true
	pad.CanCollide = true
	pad.CanTouch = true
	pad.CanQuery = true
	pad.CastShadow = true
	pad.Material = WorldConfig.INTERSECTION_MATERIAL
	pad.Color = WorldConfig.INTERSECTION_COLOR
	pad.TopSurface = Enum.SurfaceType.Smooth
	pad.BottomSurface = Enum.SurfaceType.Smooth
	pad.Size = Vector3.new(sizeX, thickness, sizeZ)
	pad.CFrame = frame
	pad:SetAttribute("CW_IntersectionPad", true)
	pad:SetAttribute("CW_IntersectionSolid", true)
	pad:SetAttribute("CW_IntersectionOwner", "TileBuilderV3")
	pad:SetAttribute("CW_GradeLevel", 0)
	copyIntersectionLabel(source, pad)
	pad.Parent = source.Parent

	return pad
end

local function solidifyIntersections(tileFolder)
	local intersections = tileFolder:FindFirstChild("Intersections")
	if not intersections then
		return
	end

	for _, item in ipairs(intersections:GetChildren()) do
		if item:GetAttribute("CW_IntersectionPad") then
			if item:IsA("MeshPart") then
				local solidPad = buildSolidPad(item)
				if solidPad then
					meshPadsReplaced += 1
					solidPadsBuilt += 1
					item:Destroy()
				end
			elseif item:IsA("BasePart") then
				item:SetAttribute("CW_IntersectionOwner", "TileBuilderV3Fallback")
				fallbackPadsKept += 1
			end
		end
	end
end

function TileBuilderV3.Prepare(tileModules)
	totalTiles = #tileModules
	builtTiles = 0
	meshPadsReplaced = 0
	fallbackPadsKept = 0
	solidPadsBuilt = 0

	BaseBuilder.Prepare(tileModules)

	print((
		"[ChesterWorld TileBuilderV3] prepared deterministic solid intersection centers: tiles=%d"
	):format(totalTiles))
end

function TileBuilderV3.Build(tileModule)
	local tileFolder = BaseBuilder.Build(tileModule)
	solidifyIntersections(tileFolder)

	builtTiles += 1

	if builtTiles == totalTiles then
		print((
			"[ChesterWorld TileBuilderV3] complete tiles=%d solidPads=%d meshPadsReplaced=%d fallbackPads=%d editableMeshIntersections=false"
		):format(
			builtTiles,
			solidPadsBuilt,
			meshPadsReplaced,
			fallbackPadsKept
		))
	end

	return tileFolder
end

return TileBuilderV3
