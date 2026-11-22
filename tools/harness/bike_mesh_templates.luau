-- Normalise Studio-generated Bike Life meshes into Exit6BikeBuilder templates.
-- Run in the Edit datamodel (Studio MCP execute_luau / command bar) after
-- generating the five rides with explicit segmentation:
--   bikes  "plastic fenders and shrouds, frame engine and seat, front wheel,
--           rear wheel, front fork and handlebars"
--   quads  "plastic fenders, frame engine and seat, front left wheel, front
--           right wheel, rear left wheel, rear right wheel, handlebars"
-- Source models are named Gen_<modelId> (bike110, bike250, bike450, quad450,
-- quad700). Result: ServerStorage.Exit6BikeMeshes.<modelId>, a Model whose
-- pivot is on the ground midway between the axles, front toward -Z, with the
-- MeshParts flattened and renamed:
--   bike: Plastics, Frame, Fork, FrontWheel, RearWheel
--   quad: Plastics, Frame, Bars, FrontLeftWheel, FrontRightWheel,
--         RearLeftWheel, RearRightWheel
-- and the attributes the builder reads (WheelBase, TrackHalf, Radius, SeatY,
-- SeatZ, BarsY, BarsZ, Len, Wid, Height).
-- Front/rear is decided by geometry, not the generator's labels: a bike's
-- front wheel is the one nearest the fork, a quad's front axle is the one
-- nearest the handlebars (the quad generations labelled them backwards).
-- ServerStorage is not synced by Rojo: save the place afterwards.
local ServerStorage = game:GetService("ServerStorage")

local TARGET_WHEELBASE = { -- studs (3 studs per metre, ~1.1x for Roblox rider proportions)
	bike110 = 4.0, bike250 = 5.1, bike450 = 5.2, quad450 = 4.4, quad700 = 4.7,
}

local folder = ServerStorage:FindFirstChild("Exit6BikeMeshes") or Instance.new("Folder")
folder.Name = "Exit6BikeMeshes"
folder.Parent = ServerStorage

local function flat(v) return Vector3.new(v.X, 0, v.Z) end
local function find(parts, ...)
	for _, p in ipairs(parts) do
		local low = string.lower(p.Name)
		local all = true
		for _, key in ipairs({ ... }) do
			if not low:find(key, 1, true) then all = false break end
		end
		if all then return p end
	end
end
local function radiusOf(w) return math.max(w.Size.Y, w.Size.Z) / 2 end

local report = {}
for id, target in pairs(TARGET_WHEELBASE) do
	local src = workspace:FindFirstChild("Gen_" .. id)
	if not src then table.insert(report, id .. ": missing Gen_" .. id) continue end
	local m = src:Clone()
	local parts = {}
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("MeshPart") then table.insert(parts, d) end
	end
	local quad = id:sub(1, 4) == "quad"
	local plastics = find(parts, "plastic")
	local frame = find(parts, "frame")
	local named, front, rear
	if quad then
		local bars = find(parts, "handlebar")
		local a = { find(parts, "front left"), find(parts, "front right") }
		local b = { find(parts, "rear left"), find(parts, "rear right") }
		if not (bars and a[1] and a[2] and b[1] and b[2] and plastics and frame) then
			table.insert(report, id .. ": missing quad parts") m:Destroy() continue
		end
		local ma, mb = (a[1].Position + a[2].Position) / 2, (b[1].Position + b[2].Position) / 2
		local fa, fb = a, b
		if (flat(bars.Position - mb)).Magnitude < (flat(bars.Position - ma)).Magnitude then fa, fb = b, a end
		front = (fa[1].Position + fa[2].Position) / 2
		rear = (fb[1].Position + fb[2].Position) / 2
		local fwd = flat(front - rear).Unit
		local rightV = Vector3.new(-fwd.Z, 0, fwd.X)
		local function lr(pair)
			if (pair[1].Position - pair[2].Position):Dot(rightV) < 0 then return pair[1], pair[2] end
			return pair[2], pair[1]
		end
		local fl, fr = lr(fa)
		local rl, rr = lr(fb)
		named = { Plastics = plastics, Frame = frame, Bars = bars,
			FrontLeftWheel = fl, FrontRightWheel = fr, RearLeftWheel = rl, RearRightWheel = rr }
	else
		local fork = find(parts, "fork")
		local w1, w2 = find(parts, "front wheel"), find(parts, "rear wheel")
		if not (fork and w1 and w2 and plastics and frame) then
			table.insert(report, id .. ": missing bike parts") m:Destroy() continue
		end
		local fw, rw = w1, w2
		if flat(fork.Position - w2.Position).Magnitude < flat(fork.Position - w1.Position).Magnitude then fw, rw = w2, w1 end
		front, rear = fw.Position, rw.Position
		named = { Plastics = plastics, Frame = frame, Fork = fork, FrontWheel = fw, RearWheel = rw }
	end
	-- flatten: every MeshPart straight under the model, nothing else
	for name, p in pairs(named) do
		p.Name = name
		p.Parent = m
	end
	for _, c in ipairs(m:GetChildren()) do
		if not c:IsA("MeshPart") then c:Destroy() end
	end
	for _, p in ipairs(m:GetChildren()) do
		p.Anchored = true
		p.CanCollide, p.CanTouch, p.CanQuery, p.Massless = false, false, false, true
	end
	-- pivot on the ground midway between the axles, front toward -Z
	local ground = math.huge
	for _, p in ipairs(m:GetChildren()) do
		if p.Name:find("Wheel") then ground = math.min(ground, p.Position.Y - radiusOf(p)) end
	end
	local mid = (front + rear) / 2
	local fwd = flat(front - rear).Unit
	m.PrimaryPart = nil
	m.WorldPivot = CFrame.lookAt(Vector3.new(mid.X, ground, mid.Z), Vector3.new(mid.X, ground, mid.Z) + fwd)
	m:ScaleTo(m:GetScale() * (target / flat(front - rear).Magnitude))
	m:PivotTo(CFrame.new(0, 0, 0))
	-- measure in the template's own frame (now the world frame)
	local function wheel(n) return m:FindFirstChild(n) end
	local radius, trackHalf, wheelBase
	if quad then
		local fl, fr, rl, rr = wheel("FrontLeftWheel"), wheel("FrontRightWheel"), wheel("RearLeftWheel"), wheel("RearRightWheel")
		radius = (radiusOf(fl) + radiusOf(fr) + radiusOf(rl) + radiusOf(rr)) / 4
		trackHalf = ((fr.Position.X - fl.Position.X) + (rr.Position.X - rl.Position.X)) / 4
		wheelBase = ((rl.Position.Z + rr.Position.Z) - (fl.Position.Z + fr.Position.Z)) / 2
	else
		local fw, rw = wheel("FrontWheel"), wheel("RearWheel")
		radius = (radiusOf(fw) + radiusOf(rw)) / 2
		trackHalf = 0
		wheelBase = rw.Position.Z - fw.Position.Z
	end
	local cf, size = m:GetBoundingBox()
	local frameP = m.Frame
	local barsP = m:FindFirstChild(quad and "Bars" or "Fork")
	-- seat: the top of the frame/seat mesh, a little behind the middle
	local seatY = frameP.Position.Y + frameP.Size.Y / 2 - (quad and 0.35 or 0.3)
	m:SetAttribute("WheelBase", wheelBase)
	m:SetAttribute("TrackHalf", trackHalf)
	m:SetAttribute("Radius", radius)
	m:SetAttribute("SeatY", seatY)
	m:SetAttribute("SeatZ", wheelBase * (quad and 0.12 or 0.16))
	m:SetAttribute("BarsY", barsP.Position.Y + barsP.Size.Y / 2 - 0.25)
	m:SetAttribute("BarsZ", quad and barsP.Position.Z or (-wheelBase / 2 + wheelBase * 0.22))
	m:SetAttribute("Len", size.Z)
	m:SetAttribute("Wid", size.X)
	m:SetAttribute("Height", size.Y)
	m:SetAttribute("BoundsCenter", cf.Position)
	m.Name = id
	local old = folder:FindFirstChild(id)
	if old then old:Destroy() end
	m.Parent = folder
	table.insert(report, string.format("%s: wb=%.2f track/2=%.2f r=%.2f seatY=%.2f len=%.2f wid=%.2f h=%.2f",
		id, wheelBase, trackHalf, radius, seatY, size.Z, size.X, size.Y))
end
return table.concat(report, "\n")
