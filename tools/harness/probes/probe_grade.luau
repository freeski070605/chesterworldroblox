-- Probe: where are HighwayProfile grade violations and deep cuts?
local HP = Mock.require(Mock.methods.FindFirstChild(World, "HighwayProfile"))
local DECK_STACK = 0.45 + 1.6 + 0.05
for _, stroke in ipairs(HP.Strokes()) do
	local G = stroke.G
	if G then
		local ds, g = stroke.ds, stroke.grade
		local name = tostring(stroke.parts[1].seg.road.name)
		local nViol, worst, worstK = 0, 0, nil
		local nCut, worstCut, cutK = 0, 0, nil
		for k = 2, #G do
			local gr = math.abs(G[k] - G[k - 1]) / ds
			if gr > g * 1.25 then
				nViol += 1
				if gr > worst then worst, worstK = gr, k end
			end
		end
		for k = 1, #G do
			local c = stroke.tl[k] - (G[k] - 0.2)
			if c > 0.5 then
				nCut += 1
				if c > worstCut then worstCut, cutK = c, k end
			end
		end
		if nViol > 0 or worstCut > 3 then
			print(string.format("PROBE %s %s len=%.0f link=%s grade=%.2f viol=%d", stroke.id, name, stroke.length, tostring(stroke.isLink), g, nViol))
			if worstK then
				local k = worstK
				print(string.format("  worstGrade=%.1f%% at s=%.0f (%.1f,%.1f) G=%.2f->%.2f t=%.2f f=%.2f minReq=%s",
					worst * 100, (k - 1) * ds, stroke.xs[k], stroke.zs[k], G[k - 1], G[k], stroke.t[k], stroke.f[k],
					stroke.minReq[k] > -math.huge and string.format("%.1f", stroke.minReq[k]) or "-"))
				local row = {}
				for m = math.max(1, k - 8), math.min(#G, k + 8) do
					table.insert(row, string.format("%.1f", G[m]))
				end
				print("  G window: " .. table.concat(row, " "))
				row = {}
				for m = math.max(1, k - 8), math.min(#G, k + 8) do
					table.insert(row, string.format("%.1f", stroke.f[m]))
				end
				print("  f window: " .. table.concat(row, " "))
			end
			if cutK then
				local k = cutK
				print(string.format("  cuts=%d worstCut=%.1f at s=%.0f (%.1f,%.1f) G=%.2f t=%.2f tl=%.2f kind=%s",
					nCut, worstCut, (k - 1) * ds, stroke.xs[k], stroke.zs[k], G[k], stroke.t[k], stroke.tl[k], tostring(stroke.kind[k])))
			end
			for _, c in ipairs(stroke.crossings or {}) do
				if worstK and math.abs(c.station - (worstK - 1) * ds) < 150 then
					print(string.format("  near crossing %s rel=%s basis=%s at s=%.0f", tostring(c.other.road.name), c.relation, tostring(c.basis), c.station))
				end
			end
		end
	end
end
