-- Probe: every upper part flagged CW_LowClearance, grouped by road and 100-stud cell.
local seen, rows = {}, {}
for _, tile in ipairs(worldRoot:GetChildren()) do
	local roads = tile:FindFirstChild("Roads")
	if roads then
		for _, p in ipairs(roads:GetChildren()) do
			if p:GetAttribute("CW_LowClearance") then
				local name = tostring(p:GetAttribute("ChesterStreet"))
				local key = name .. math.floor(p.Position.X / 100) .. ":" .. math.floor(p.Position.Z / 100)
				if not seen[key] then
					seen[key] = 0
					table.insert(rows, { key = key, text = string.format("%s (%.0f,%.0f) y=%.1f terrain=%.1f lvl=%s grp=%s prof=%s kind=%s overpass=%s gl=%s",
						name, p.Position.X, p.Position.Z, p.Position.Y, terrain(p.Position.X, p.Position.Z),
						tostring(p:GetAttribute("CW_GradeLevel")), tostring(p:GetAttribute("CW_GradeGroup")),
						tostring(p:GetAttribute("CW_HighwayProfiled")), tostring(p:GetAttribute("CW_HighwayStructure")),
						tostring(p:GetAttribute("CW_RegistryOverpassDeck")), tostring(p:GetAttribute("CW_GradeLimited"))) })
				end
				seen[key] += 1
			end
		end
	end
end
for _, r in ipairs(rows) do print("LOWC x" .. seen[r.key] .. " " .. r.text) end
