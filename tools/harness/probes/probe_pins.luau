-- Probe: nodes that pin a stroke inside a station window (pin conflicts).
-- Edit WANT to the stroke ids / station windows printed by
-- [HighwayProfilePinConflict].
local HP = Mock.require(Mock.methods.FindFirstChild(World, "HighwayProfile"))
local WANT = { HW6 = { 5300, 5900 } }
for _, stroke in ipairs(HP.Strokes()) do
	local window = WANT[stroke.id]
	if window and stroke.G then
		print(string.format("PINS %s %s len=%.0f", stroke.id, tostring(stroke.parts[1].seg.road.name), stroke.length))
		for pi, part in ipairs(stroke.parts) do
			for which = 1, 2 do
				local seg = part.seg
				local info = HP.Lookup(seg.road)
				local s = info and HP.StationAt(info, which == 1 and 0 or 1) or -1
				if s >= window[1] and s <= window[2] then
					local node = seg.nodes[which]
					local x = which == 1 and seg.ax or seg.bx
					local z = which == 1 and seg.az or seg.bz
					local others = {}
					for _, arm in ipairs(node.arms) do
						table.insert(others, string.format("%s[%s lvl%d %s]", tostring(arm.seg.road.name),
							arm.seg.stroke and arm.seg.stroke.id or "?", arm.seg.level, tostring(arm.seg.road.grade_group)))
					end
					print(string.format("  s=%.0f part%d end%d %s lvl=%d (%.1f, %.1f) node=%s mixed=%s height=%s terrain=%.2f G=%.2f",
						s, pi, which, tostring(seg.road.name), seg.level, x, z, node.id, tostring(node.mixed),
						node.height and string.format("%.2f", node.height) or "-", terrain(x, z), HP.GradeAt(info, which == 1 and 0 or 1)))
					print("    arms: " .. table.concat(others, "; "))
				end
			end
		end
	end
end
