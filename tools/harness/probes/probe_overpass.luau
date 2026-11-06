-- Probe: what holds the highway up under the named local overpasses.
local HP = Mock.require(Mock.methods.FindFirstChild(World, "HighwayProfile"))
local NAMES = { "chester pke", "flower", "chester riverfront", "crosby", "csx phila" }
local function wanted(name)
	name = string.lower(tostring(name))
	for _, n in ipairs(NAMES) do
		if string.find(name, n, 1, true) and not string.find(name, " to ", 1, true) then
			return true
		end
	end
	return false
end
for _, stroke in ipairs(HP.Strokes()) do
	if stroke.G then
		local ds, count = stroke.ds, #stroke.G
		for _, cross in ipairs(stroke.crossings or {}) do
			if wanted(cross.other.road.name) then
				local k = math.clamp(math.floor(cross.station / ds + 0.5) + 1, 1, count)
				local rim = cross.shared.rims and cross.shared.rims[cross.other]
				print(string.format("OVERPASS %s %s s=%.0f over=%s rel=%s basis=%s (%.0f,%.0f) G=%.2f t=%.2f f=%.2f minReq=%s rim=%s",
					stroke.id, tostring(stroke.parts[1].seg.road.name), cross.station, tostring(cross.other.road.name),
					tostring(cross.relation), tostring(cross.basis), cross.x, cross.z, stroke.G[k], stroke.t[k], stroke.f[k],
					tostring(stroke.minReq[k]), rim and string.format("%.2f", rim) or "-"))
				for _, other in ipairs(stroke.crossings) do
					if other ~= cross and math.abs(other.station - cross.station) < 250 then
						print(string.format("   near s=%.0f %s rel=%s basis=%s lowerG=%s clr=%s",
							other.station, tostring(other.other.road.name), tostring(other.relation), tostring(other.basis),
							other.lowerG and string.format("%.1f", other.lowerG) or "-", tostring(other.clearance)))
					end
				end
				local lo, hi = math.max(1, k - 40), math.min(count, k + 40)
				local row = {}
				for j = lo, hi, 5 do
					table.insert(row, string.format("%.0f:%.1f/%.1f", (j - 1) * ds, stroke.G[j], stroke.t[j]))
				end
				print("   G/t " .. table.concat(row, " "))
			end
		end
	end
end
