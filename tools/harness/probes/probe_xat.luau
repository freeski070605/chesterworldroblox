-- Probe: every profile crossing near the given points (decision and envelope).
local HP = Mock.require(Mock.methods.FindFirstChild(World, "HighwayProfile"))
local POINTS = { { 9459, -11609 } }
for _, stroke in ipairs(HP.Strokes()) do
	for _, cross in ipairs(stroke.G and stroke.crossings or {}) do
		for _, p in ipairs(POINTS) do
			if math.abs(cross.x - p[1]) < 40 and math.abs(cross.z - p[2]) < 40 then
				local k = math.clamp(math.floor(cross.station / stroke.ds + 0.5) + 1, 1, #stroke.G)
				print(string.format("XAT %s %s x %s rel=%s basis=%s (%.0f,%.0f) G=%.2f t=%.2f lowerG=%s clr=%s sine=%.2f",
					stroke.id, tostring(stroke.parts[1].seg.road.name), tostring(cross.other.road.name), tostring(cross.relation),
					tostring(cross.basis), cross.x, cross.z, stroke.G[k], stroke.t[k],
					cross.lowerG and string.format("%.2f", cross.lowerG) or "-", tostring(cross.clearance), cross.sine or -1))
			end
		end
	end
end
