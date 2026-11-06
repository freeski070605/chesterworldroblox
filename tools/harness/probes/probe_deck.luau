-- Probe: a local overpass deck and the roads/terrain around it after the full run.
local NAMES, PX, PZ, R = { ["Melrose Ave"] = true, ["Chestnut St"] = true }, 8500, -3500, 500
local rows = {}
for _, tile in ipairs(worldRoot:GetChildren()) do
	local roads = tile:FindFirstChild("Roads")
	if roads then
		for _, p in ipairs(roads:GetChildren()) do
			local name = p:GetAttribute("ChesterStreet")
			if math.abs(p.Position.X - PX) < R and math.abs(p.Position.Z - PZ) < R
				and (NAMES[name] or name == "I 95") then
				local s = p.CFrame.LookVector * p.Size.Z / 2
				local a, b = p.Position - s, p.Position + s
				table.insert(rows, string.format("%s lvl=%s grp=%s kind=%s a=(%.0f,%.0f,%.1f t%.1f) b=(%.0f,%.0f,%.1f t%.1f) gl=%s req=%s",
					name, tostring(p:GetAttribute("CW_GradeLevel")), tostring(p:GetAttribute("CW_GradeGroup")),
					tostring(p:GetAttribute("CW_HighwayStructure")), a.X, a.Z, a.Y, terrain(a.X, a.Z), b.X, b.Z, b.Y, terrain(b.X, b.Z),
					tostring(p:GetAttribute("CW_GradeLimited")), tostring(p:GetAttribute("CW_RequestedDeckLift"))))
			end
		end
	end
end
table.sort(rows)
for _, r in ipairs(rows) do print("DECK " .. r) end
