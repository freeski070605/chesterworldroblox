local POINTS = {
	{ "2nd", -884.7, 7458.2 }, { "2nd", -753.4, 7370.6 },
	{ "i 476 to i 95", 11504.2, -6853.0 }, { "i 95 to macdade blvd", 10161.1, -10514.6 },
}
for _, pt in ipairs(POINTS) do
	print(string.format("STEPAT %s (%.1f, %.1f) terrain=%.2f", pt[1], pt[2], pt[3], terrain(pt[2], pt[3])))
	for dz = -4, 4, 4 do
		for _, h in ipairs(hitsAt(pt[2], pt[3] + dz)) do
			local p = h.item.p
			if h.item.role ~= "structure" then
				print(string.format("  dz=%d %s %s top=%.2f class=%s lvl=%s hp=%s stroke=%s bridge=%s group=%s",
					dz, h.item.role, tostring(p:GetAttribute("ChesterStreet")), h.top,
					tostring(p:GetAttribute("CW_RoadClass")), tostring(p:GetAttribute("CW_GradeLevel")),
					tostring(p:GetAttribute("CW_HighwayProfiled")), tostring(p:GetAttribute("CW_StrokeId")),
					tostring(p:GetAttribute("CW_BridgeProfiled")), tostring(p:GetAttribute("CW_GradeGroup"))))
			end
		end
	end
end
