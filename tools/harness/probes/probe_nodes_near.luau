-- Probe: corridor nodes near given points (id, arms, freeway-split ":X" ids).
-- Edit WANT to the coordinates under investigation.
local HP = Mock.require(Mock.methods.FindFirstChild(World, "HighwayProfile"))
local WANT = {
	{ -2837.6, 2131.5 }, { -2784.9, 2167.9 }, { -2911.9, 2096.5 }, { 9510.5, -12228.7 },
}
local RADIUS = 12
local seen = {}
for _, stroke in ipairs(HP.Strokes()) do
	for _, part in ipairs(stroke.parts) do
		local seg = part.seg
		for which = 1, 2 do
			local node = seg.nodes[which]
			local x = which == 1 and seg.ax or seg.bx
			local z = which == 1 and seg.az or seg.bz
			for _, p in ipairs(WANT) do
				if (x - p[1]) ^ 2 + (z - p[2]) ^ 2 <= RADIUS * RADIUS and not seen[node] then
					seen[node] = true
					local arms = {}
					for _, arm in ipairs(node.arms) do
						table.insert(arms, string.format("%s[%s %s]", tostring(arm.seg.road.name),
							arm.seg.stroke and arm.seg.stroke.id or "?", tostring(arm.seg.road.grade_group)))
					end
					print(string.format("NODE near (%.0f, %.0f): %s at (%.1f, %.1f) mixed=%s arms: %s", p[1], p[2],
						node.id, x, z, tostring(node.mixed), table.concat(arms, "; ")))
				end
			end
		end
	end
end
