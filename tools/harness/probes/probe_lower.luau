-- Probe: profiled highway parts crossing the bridge-tagged pieces of one road
-- near a point (why a lower road was / was not grounded by the conformer).
local NAME, PX, PZ, R = "2nd", 30, 6810, 120
local function ends(p)
	local s = p.CFrame.LookVector * p.Size.Z / 2
	return p.Position - s, p.Position + s
end
local mine, highway = {}, {}
for _, tile in ipairs(worldRoot:GetChildren()) do
	local roads = tile:FindFirstChild("Roads")
	if roads then
		for _, p in ipairs(roads:GetChildren()) do
			if math.abs(p.Position.X - PX) < R and math.abs(p.Position.Z - PZ) < R then
				if p:GetAttribute("ChesterStreet") == NAME then
					table.insert(mine, p)
				elseif p:GetAttribute("CW_HighwayProfiled") == true then
					table.insert(highway, p)
				end
			end
		end
	end
end
for _, p in ipairs(mine) do
	print(string.format("MINE %s group=%s level=%s y=%.1f lower=%s at (%.1f, %.1f) terrain=%.1f", NAME,
		tostring(p:GetAttribute("CW_GradeGroup")), tostring(p:GetAttribute("CW_GradeLevel")), p.Position.Y,
		tostring(p:GetAttribute("CW_LowerRoadUnderStructure")), p.Position.X, p.Position.Z, terrain(p.Position.X, p.Position.Z)))
end
local seen = {}
for _, h in ipairs(highway) do
	local key = tostring(h:GetAttribute("ChesterStreet")) .. tostring(h:GetAttribute("CW_HighwayStructure"))
		.. math.floor(h.Position.X / 40) .. math.floor(h.Position.Z / 40)
	if not seen[key] then
		seen[key] = true
		local top = h.Position.Y + h.Size.Y / 2
		print(string.format("HWY %s kind=%s top=%.1f terrain=%.1f at (%.1f, %.1f) basis=%s", tostring(h:GetAttribute("ChesterStreet")),
			tostring(h:GetAttribute("CW_HighwayStructure")), top, terrain(h.Position.X, h.Position.Z), h.Position.X, h.Position.Z,
			tostring(h:GetAttribute("CW_StructureBasis"))))
	end
end
