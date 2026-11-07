-- EXIT 6 car physics: a raycast-suspension car (no wheel constraints), so it
-- rides the city's wedge-paved streets and part seams smoothly. Runs on
-- whoever owns the car's physics: the driver's client while it is driven
-- (Exit6Driving.client), the server while it is parked (Exit6Vehicles.server).
--
-- The car model (Exit6Vehicles.server builds it) has a PrimaryPart "Chassis"
-- and attributes on the model, all in studs / seconds:
--   WheelBase, TrackHalf, Rest (suspension travel), Radius (wheel radius)
local CarPhysics = {}

CarPhysics.Tuning = {
	staticSag = 0.7,        -- suspension compression at rest
	dampingRatio = 0.65,
	topSpeed = 110,         -- studs/s (~ 60 mph at ChesterWorld's 3.9 studs per metre)
	reverseSpeed = 30,
	engineAccel = 24,       -- studs/s^2 at a standstill
	brakeDecel = 70,
	coastDecel = 4,
	grip = 0.9,             -- fraction of sideways slip cancelled per frame (front / rear)
	mu = 1.4,               -- tyre friction vs the wheel's load
	maxSteer = math.rad(34),
	handbrakeRearGrip = 0.12,
	airDrag = 0.0009,
}
local T = CarPhysics.Tuning

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = false

-- wheel offsets in chassis space: front-left, front-right, rear-left, rear-right
local function wheels(model)
	local wb = model:GetAttribute("WheelBase") or 10.4
	local th = model:GetAttribute("TrackHalf") or 3.0
	local y = model:GetAttribute("WheelMountY") or -0.2
	return {
		{ Vector3.new(-th, y, -wb / 2), true },
		{ Vector3.new(th, y, -wb / 2), true },
		{ Vector3.new(-th, y, wb / 2), false },
		{ Vector3.new(th, y, wb / 2), false },
	}
end
CarPhysics.Wheels = wheels

-- one physics step. input: { throttle = -1..1, steer = -1..1, handbrake = bool }
-- returns forward speed (studs/s, + = forward) and grounded wheel count
function CarPhysics.Step(model, dt, input)
	local chassis = model.PrimaryPart
	if not chassis or chassis.Anchored then return 0, 0 end
	dt = math.min(dt, 1 / 30)
	local exclude = { model }
	for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
		if p.Character then table.insert(exclude, p.Character) end
	end
	params.FilterDescendantsInstances = exclude

	local mass = chassis.AssemblyMass
	local g = workspace.Gravity
	local rest = model:GetAttribute("Rest") or 1.4
	local radius = model:GetAttribute("Radius") or 1.5
	local len = rest + radius
	local k = mass * g / 4 / T.staticSag
	local c = 2 * T.dampingRatio * math.sqrt(k * mass / 4)

	local cf = chassis.CFrame
	local up = cf.UpVector
	local look = cf.LookVector
	local com = chassis.AssemblyCenterOfMass
	local vel = chassis.AssemblyLinearVelocity
	local ang = chassis.AssemblyAngularVelocity
	local speed = vel:Dot(look)
	local throttle = math.clamp(input.throttle or 0, -1, 1)
	local steer = math.clamp(input.steer or 0, -1, 1)
	-- less lock at speed
	local steerAngle = -steer * T.maxSteer / (1 + math.abs(speed) / 55)

	local grounded = 0
	local compression = {}
	for i, w in ipairs(wheels(model)) do
		local origin = cf:PointToWorldSpace(w[1])
		local hit = workspace:Raycast(origin, -up * len, params)
		if hit then
			grounded += 1
			local x = math.clamp(len - hit.Distance, 0, rest)
			compression[i] = x
			local pv = vel + ang:Cross(origin - com)
			local vUp = pv:Dot(up)
			local load = math.max(0, k * x - c * vUp)
			local n = hit.Normal
			-- suspension
			chassis:ApplyImpulseAtPosition(up * load * dt, origin)
			-- tyre directions on the ground plane
			local fwd = look
			if w[2] then fwd = (CFrame.fromAxisAngle(up, steerAngle) * look) end
			fwd = (fwd - n * fwd:Dot(n))
			if fwd.Magnitude < 1e-3 then continue end
			fwd = fwd.Unit
			local side = n:Cross(fwd).Unit
			local vF = pv:Dot(fwd)
			local vS = pv:Dot(side)
			local share = mass / 4
			local maxJ = T.mu * load * dt
			-- sideways grip
			local grip = T.grip
			if input.handbrake and not w[2] then grip = T.handbrakeRearGrip end
			local jS = math.clamp(-vS * share * grip, -maxJ, maxJ)
			-- drive / brake / coast along the tyre
			local jF = 0
			if throttle > 0.05 then
				if vF < -2 then
					jF = math.min(T.brakeDecel * share * dt, -vF * share)
				elseif not w[2] then
					local fall = 1 - math.clamp(vF / T.topSpeed, 0, 1) ^ 2
					jF = throttle * T.engineAccel * mass / 2 * fall * dt
				end
			elseif throttle < -0.05 then
				if vF > 2 then
					jF = -math.min(T.brakeDecel * share * dt, vF * share)
				elseif not w[2] then
					local fall = 1 - math.clamp(-vF / T.reverseSpeed, 0, 1) ^ 2
					jF = throttle * T.engineAccel * 0.6 * mass / 2 * fall * dt
				end
			else
				-- coasting; hold still when nearly stopped (no creeping downhill)
				local decel = (math.abs(vF) < 3) and T.brakeDecel or T.coastDecel
				jF = -math.sign(vF) * math.min(decel * share * dt, math.abs(vF) * share)
			end
			if input.handbrake and not w[2] then
				jF = -math.sign(vF) * math.min(T.brakeDecel * share * dt, math.abs(vF) * share)
			end
			jF = math.clamp(jF, -maxJ * 1.2, maxJ * 1.2)
			chassis:ApplyImpulseAtPosition(fwd * jF + side * jS, hit.Position + n * 0.3)
		else
			compression[i] = 0
		end
	end
	-- air drag
	if vel.Magnitude > 1 then
		chassis:ApplyImpulse(-vel * vel.Magnitude * T.airDrag * mass * dt)
	end
	-- keep it on its wheels: damp roll / pitch spin, and right it when flipped
	local worldUp = Vector3.yAxis
	local tilt = math.acos(math.clamp(up:Dot(worldUp), -1, 1))
	local inertia = mass * 12
	local spinRP = ang - up * ang:Dot(up)
	chassis:ApplyAngularImpulse(-spinRP * inertia * math.min(1, dt * (grounded > 0 and 2 or 6)))
	if tilt > math.rad(55) and math.abs(speed) < 8 then
		local axis = up:Cross(worldUp)
		if axis.Magnitude > 1e-3 then
			chassis:ApplyAngularImpulse(axis.Unit * inertia * 3 * dt)
		end
	end
	return speed, grounded, compression, steerAngle
end

return CarPhysics
