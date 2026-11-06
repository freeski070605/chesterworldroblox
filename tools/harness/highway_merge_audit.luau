-- Run in the Play server (Studio MCP execute_luau). Freeway / ramp pavements
-- that overlap in plan at different top-surface heights (1.0 .. 10 studs):
-- the "stacked / stepped merge" defect. Also counts pieces steeper than 8 / 10 %.
local W = workspace
local world = W.ChesterWorld
local hw = {}
for _, t in ipairs(world:GetChildren()) do
	local r = t:FindFirstChild("Roads")
	if r then
		for _, p in ipairs(r:GetChildren()) do
			if p:GetAttribute("CW_ElevationOwner") == "HighwayProfile" then table.insert(hw, p) end
		end
	end
end
local op = OverlapParams.new()
op.FilterType = Enum.RaycastFilterType.Include
op.FilterDescendantsInstances = hw
local function topAt(part, x, z)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { part }
	local h = W:Raycast(Vector3.new(x, part.Position.Y + 60, z), Vector3.new(0, -120, 0), rp)
	return h and h.Position.Y
end
local clash, steep8, steep10 = {}, 0, 0
for i, p in ipairs(hw) do
	local lv = p.CFrame.LookVector
	local g = math.abs(lv.Y) / math.max(math.sqrt(lv.X ^ 2 + lv.Z ^ 2), 1e-3)
	if g > 0.08 then steep8 += 1 end
	if g > 0.10 then steep10 += 1 end
	for _, q in ipairs(W:GetPartBoundsInBox(p.CFrame, Vector3.new(p.Size.X * 0.8, p.Size.Y + 14, p.Size.Z * 0.8), op)) do
		if q ~= p and q.Name ~= p.Name then
			-- sample where both pavements are: midway between the centres
			local m = (p.Position + q.Position) / 2
			local a, b = topAt(p, m.X, m.Z), topAt(q, m.X, m.Z)
			if a and b then
				local dy = math.abs(a - b)
				if dy > 1.0 and dy < 10 then
					local n1, n2 = p.Name, q.Name
					if n1 > n2 then n1, n2 = n2, n1 end
					local k = string.format("%s x %s @(%d,%d)", n1, n2, math.floor(m.X / 100) * 100, math.floor(m.Z / 100) * 100)
					clash[k] = math.max(clash[k] or 0, dy)
				end
			end
		end
	end
	if i % 300 == 0 then task.wait() end
end
local c = {}
for k, v in pairs(clash) do table.insert(c, string.format("%s dy=%.1f", k, v)) end
table.sort(c)
return string.format("surface steps at overlaps: %d\n%s\nsteep>8%%: %d  >10%%: %d", #c, table.concat(c, "\n"), steep8, steep10)
