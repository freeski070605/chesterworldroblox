local HP = Mock.require(Mock.methods.FindFirstChild(World, "HighwayProfile"))
local WANT = { HW22 = true, HW46 = true, HW56 = true, HW2 = true }
local PTS = { { -884.7, 7458.2 }, { 11504.2, -6853.0 }, { 10161.1, -10514.6 } }
for _, stroke in ipairs(HP.Strokes()) do
	if WANT[stroke.id] and stroke.G then
		print(string.format("ENDS %s %s len=%.0f parts=%d", stroke.id, tostring(stroke.parts[1].seg.road.name), stroke.length, #stroke.parts))
		for pi, part in ipairs(stroke.parts) do
			for which = 1, 2 do
				local node = part.seg.nodes[which]
				local x = which == 1 and part.seg.ax or part.seg.bx
				local z = which == 1 and part.seg.az or part.seg.bz
				local near = false
				for _, p in ipairs(PTS) do
					if (p[1] - x) ^ 2 + (p[2] - z) ^ 2 < 60 ^ 2 then near = true end
				end
				if near or pi == 1 or pi == #stroke.parts then
					local key = which == 1 and part.seg.k1 or part.seg.k2
					print(string.format("  part%d end%d %s (%.1f, %.1f) key=%s mixed=%s arms=%d nodeH=%s terrain=%.2f",
						pi, which, tostring(part.seg.road.name), x, z, key, tostring(node.mixed), #node.arms,
						node.height and string.format("%.2f", node.height) or "-", terrain(x, z)))
				end
			end
		end
	end
end
-- non-corridor roads ending near each step point
for _, p in ipairs(PTS) do
	for _, seg in ipairs(ALLSEG) do
		for e = 0, 1 do
			local x, z = seg[1 + 2 * e], seg[2 + 2 * e]
			if (p[1] - x) ^ 2 + (p[2] - z) ^ 2 < 25 ^ 2 then
				print(string.format("NEAR (%.0f,%.0f): %s end at (%.1f, %.1f)", p[1], p[2], seg[5], x, z))
			end
		end
	end
end
