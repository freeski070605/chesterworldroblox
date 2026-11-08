-- EXIT 6 lots: find a free, flat piece of ground beside a city street for a
-- gameplay building that has no real Chester address (Exit 6 Sound, event
-- stages...). Same rules the dealership uses: nothing built on it at all
-- (paving included), level within a few studs, clear of the gas stations, the
-- 9th & Kerlin corner and anything listed in opts.keepClear.
--   Lots.Find({ near = Vector3, size = Vector3(alongRoad, 0, depth),
--               keepClear = { { Vector3, radius } }, minRoadWidth = 18 })
--   -> CFrame (on the ground, -Z facing the street), street name   or nil
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WorldConfig"))

local Lots = {}

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { Workspace.Terrain }
local function groundAt(x, z)
	local hit = Workspace:Raycast(Vector3.new(x, 600, z), Vector3.new(0, -900, 0), terrainOnly)
	return hit and hit.Position.Y
end

local claimed = {}   -- lots already handed out this server

function Lots.Find(opts)
	local world = Workspace:FindFirstChild("ChesterWorld")
	if not world then return nil end
	local size = opts.size
	local region = opts.region or WorldConfig.REAL_BUILDINGS_REGION
	local keep = { { Vector3.new(2810, 0, 1518), 250 } }
	for _, k in ipairs(opts.keepClear or {}) do table.insert(keep, k) end
	for _, c in ipairs(claimed) do table.insert(keep, c) end
	local stations = Workspace:FindFirstChild("ChesterGasStations")
	for _, st in ipairs(stations and stations:GetChildren() or {}) do
		local ok, pv = pcall(function() return st:GetPivot().Position end)
		if ok then table.insert(keep, { pv, 150 }) end
	end
	local function away(pos)
		for _, k in ipairs(keep) do
			if (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(k[1].X, 0, k[1].Z)).Magnitude < k[2] then return false end
		end
		return true
	end
	local blockParams = OverlapParams.new()
	blockParams.FilterType = Enum.RaycastFilterType.Exclude
	blockParams.FilterDescendantsInstances = { Workspace.Terrain }
	blockParams.MaxParts = 1
	local function free(cf)
		return #Workspace:GetPartBoundsInBox(cf * CFrame.new(0, 12, 0), Vector3.new(size.X + 6, 23.5, size.Z + 2), blockParams) == 0
	end
	-- candidate streets: the tiles' Roads folders (never world:GetDescendants())
	local cands = {}
	for _, tile in ipairs(world:GetChildren()) do
		local f = tile:FindFirstChild("Roads")
		if f then
			task.wait()
			for _, p in ipairs(f:GetChildren()) do
				if p:IsA("BasePart") and p:GetAttribute("ChesterStreet") and not p:GetAttribute("CW_HighwayProfiled") then
					local pos = p.Position
					if pos.X > region.minX and pos.X < region.maxX and pos.Z > region.minZ and pos.Z < region.maxZ then
						local width = math.min(p.Size.X, p.Size.Z)
						if width >= (opts.minRoadWidth or 18) and math.max(p.Size.X, p.Size.Z) >= 40 then
							table.insert(cands, { p = p, d = (pos - opts.near).Magnitude })
						end
					end
				end
			end
		end
	end
	table.sort(cands, function(a, b) return a.d < b.d end)
	for i, c in ipairs(cands) do
		if i > 500 then break end
		if i % 25 == 0 then task.wait() end
		local p = c.p
		local axis = (p.Size.Z > p.Size.X) and p.CFrame.LookVector or p.CFrame.RightVector
		axis = Vector3.new(axis.X, 0, axis.Z).Unit
		local width = math.min(p.Size.X, p.Size.Z)
		local right = Vector3.new(-axis.Z, 0, axis.X)
		for _, side in ipairs({ 1, -1 }) do
			local centre = p.Position + right * side * (width / 2 + 14 + size.Z / 2)
			local gy = away(centre) and groundAt(centre.X, centre.Z)
			if gy then
				local flat = true
				for _, o in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
					local cp = centre + axis * o[1] * size.X / 2 + right * o[2] * size.Z / 2
					local y = groundAt(cp.X, cp.Z)
					if not y or math.abs(y - gy) > 2.5 then flat = false break end
				end
				local at = Vector3.new(centre.X, gy, centre.Z)
				local cf = CFrame.lookAt(at, at - right * side)
				if flat and free(cf) then
					table.insert(claimed, { at, math.max(size.X, size.Z) })
					return cf, p:GetAttribute("ChesterStreet")
				end
			end
		end
	end
	return nil
end

return Lots
