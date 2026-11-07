-- Normalise Studio-generated car meshes into Exit6CarBuilder templates.
-- Run in the Edit datamodel (Studio MCP execute_luau / command bar) after
-- generating the cars (body + 4 wheels, segmentation explicit). Each source
-- Model is named GenCar_<body> (sedan, hatch, van, pickup, suv, coupe).
-- Result: ServerStorage.Exit6CarMeshes.<body>, pivot on the ground under the
-- car's centre, front toward -Z, parts Body / FrontLeftWheel / ... and the
-- attributes the builder reads (Len, Wid, WheelBase, TrackHalf, Radius, SeatY).
-- The meshes live in the place file (ServerStorage is not synced by Rojo):
-- save / publish the place afterwards.
local ServerStorage = game:GetService("ServerStorage")
local Catalog = require(game:GetService("ReplicatedStorage").Shared.Exit6Catalog)
local CarPhysics = require(game:GetService("ReplicatedStorage").Shared.Exit6CarPhysics)

local folder = ServerStorage:FindFirstChild("Exit6CarMeshes") or Instance.new("Folder")
folder.Name = "Exit6CarMeshes"
folder.Parent = ServerStorage

local REST = 1.4
local WHEELS = { ["front left"] = "FrontLeftWheel", ["front right"] = "FrontRightWheel",
	["rear left"] = "RearLeftWheel", ["rear right"] = "RearRightWheel" }
local function flat(v) return Vector3.new(v.X, 0, v.Z) end

local out = {}
for _, m in ipairs(workspace:GetChildren()) do
	local body = m:IsA("Model") and m.Name:match("^GenCar_(%w+)$")
	local spec = body and Catalog.Vehicles[body]
	if spec then
		local w, bodyPart = {}, nil
		for _, p in ipairs(m:GetDescendants()) do
			if p:IsA("BasePart") then
				local low = string.lower(p.Name)
				for key, name in pairs(WHEELS) do
					if low:find(key, 1, true) then w[name] = p p.Name = name end
				end
				if low:find("body", 1, true) then bodyPart = p p.Name = "Body" end
			end
		end
		if bodyPart and w.FrontLeftWheel and w.FrontRightWheel and w.RearLeftWheel and w.RearRightWheel then
			local front = (w.FrontLeftWheel.Position + w.FrontRightWheel.Position) / 2
			local rear = (w.RearLeftWheel.Position + w.RearRightWheel.Position) / 2
			local fwd = flat(front - rear).Unit
			local radius0 = (w.FrontLeftWheel.Size.Y + w.RearRightWheel.Size.Y) / 4
			local ground = math.huge
			for _, p in pairs(w) do ground = math.min(ground, p.Position.Y - p.Size.Y / 2) end
			local mid = (front + rear) / 2
			m.WorldPivot = CFrame.lookAt(Vector3.new(mid.X, ground, mid.Z), Vector3.new(mid.X, ground, mid.Z) + fwd)
			-- scale so the wheelbase matches the spec (wheelbase ~ 0.6 x length)
			local wb0 = flat(front - rear).Magnitude
			local s = (spec.len * 0.6) / wb0
			m:ScaleTo(m:GetScale() * s)
			-- measure again in the car's own frame
			local piv = m:GetPivot()
			local function loc(p) return piv:PointToObjectSpace(p.Position) end
			local fl, fr, rl, rr = loc(w.FrontLeftWheel), loc(w.FrontRightWheel), loc(w.RearLeftWheel), loc(w.RearRightWheel)
			local wheelBase = ((rl.Z + rr.Z) - (fl.Z + fr.Z)) / 2
			local trackHalf = ((fr.X - fl.X) + (rr.X - rl.X)) / 4
			local radius = (w.FrontLeftWheel.Size.Y + w.RearRightWheel.Size.Y) / 4
			local rideH = REST + radius - CarPhysics.Tuning.staticSag + 0.2   -- chassis centre above the ground
			m:SetAttribute("Len", spec.len)
			m:SetAttribute("Wid", trackHalf * 2 + 1.4)
			m:SetAttribute("WheelBase", math.floor(wheelBase * 100 + 0.5) / 100)
			m:SetAttribute("TrackHalf", math.floor(trackHalf * 100 + 0.5) / 100)
			m:SetAttribute("Radius", math.floor(radius * 100 + 0.5) / 100)
			m:SetAttribute("SeatY", math.floor((radius + 0.6 - rideH) * 100 + 0.5) / 100)
			for _, p in ipairs(m:GetDescendants()) do
				if p:IsA("BasePart") then p.Anchored = true end
			end
			local old = folder:FindFirstChild(body)
			if old then old:Destroy() end
			m.Name = body
			m.Parent = folder
			table.insert(out, string.format("%s scale=%.2f wb=%.2f track=%.2f r=%.2f seatY=%.2f", body, s, wheelBase, trackHalf * 2, radius, m:GetAttribute("SeatY")))
		else
			table.insert(out, body .. ": parts not found")
		end
	end
end
return table.concat(out, "\n")
