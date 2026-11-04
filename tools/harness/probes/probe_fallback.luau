for _, tile in ipairs(worldRoot:GetChildren()) do
	local roads = tile:FindFirstChild("Roads")
	if roads then
		for _, p in ipairs(roads:GetChildren()) do
			if p:GetAttribute("CW_SteepHighwayFallback") == true then
				print(string.format("FALLBACK %s %s class=%s level=%s grade=%.0f%% at (%.1f, %.1f) conformed=%s y=%.1f",
					tile.Name, tostring(p:GetAttribute("ChesterStreet")), tostring(p:GetAttribute("CW_RoadClass")),
					tostring(p:GetAttribute("CW_GradeLevel")), (tonumber(p:GetAttribute("CW_ObservedSurfaceGrade")) or 0) * 100,
					p.Position.X, p.Position.Z, tostring(p:GetAttribute("CW_BridgeProfiled")), p.Position.Y))
			end
		end
	end
end
