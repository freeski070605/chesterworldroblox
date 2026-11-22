-- EXIT 6 Bike Life physics: two-wheel dirt bikes and four-wheel sport quads.
-- Runs wherever the ride's physics is owned - the rider's client while it is
-- ridden (Exit6Riding.client), the server while it is parked
-- (Exit6Vehicles.server). Cars keep Exit6CarPhysics; nothing here touches them.
--
-- Movement is impulses on the chassis assembly only (no CFrame writes):
--   * raycast suspension at each real wheel (2 on a bike, 4 on a quad),
--     spring + damper sized from the assembly mass (rider included);
--   * a tyre at each contact: lateral grip cancels slip up to mu x load,
--     the rear tyre(s) drive, both ends brake, the front steers;
--   * one AlignOrientation ("Balance", PrimaryAxisParallel on the chassis up
--     axis) does what a rider does: leans a bike into the turn by the lean a
--     real motorcycle needs for that speed and steering (tan(lean) =
--     v^2 tan(steer) / (wheelbase g)), puts it on its feet when stopped, holds
--     the balance point of a wheelie, and rights a fallen ride. Quads use it as
--     an anti-roll / wheelie controller only - they never lean.
-- Model attributes (Exit6BikeBuilder): Exit6BikeLife ("bike" | "quad"),
-- WheelBase, TrackHalf, Radius, Rest, TopSpeed, EngineAccel, Brake, Grip,
-- SteerLock (deg), WheelieMax (deg), Fuel.
local Players = game:GetService("Players")

local BikePhysics = {}

BikePhysics.Tuning = {
	sag = 0.45,             -- suspension compression at rest (studs)
	rest = 1.0,             -- suspension travel (studs)
	damping = 0.7,          -- of critical
	mu = 1.0,               -- tyre friction x Grip attribute
	lateralGrip = 0.85,     -- fraction of sideways slip cancelled per step
	coastDecel = 5,         -- engine braking, studs/s^2
	holdSpeed = 1.2,        -- below this with no input the ride holds still
	reverseSpeed = { bike = 5, quad = 16 }, -- a bike rider paddles backward; a quad has reverse
	airDrag = 0.0007,
	maxLean = math.rad(42),
	-- cornering: the steering is limited so the turn never asks the tyres for
	-- more than this sideways acceleration (studs/s^2); a real rider barely
	-- moves the bars at speed. Lean is drawn against leanGravity so a hard
	-- corner reads as a proper knee-down lean.
	maxLateral = { bike = 60, quad = 52 },
	leanGravity = 85,
	steerRate = 4.5,          -- full lock per second from a digital key
	frontGrip = 0.62,         -- front tyre lets go before the rear: understeer, never a spin
	yawControl = 5,           -- pull toward the turn rate the steering asks for
	balanceTorque = { bike = 1100, quad = 520 }, -- x assembly mass
	balanceResponse = { bike = 16, quad = 10 },
	kickstand = math.rad(8),  -- a parked bike rests on its stand (leans left)
	rake = math.rad(24),      -- bike steering axis (visuals)
}
local T = BikePhysics.Tuning
BikePhysics.ChassisHeight = function(radius) return T.rest + radius - T.sag end

-- wheel mounts in chassis space: { offset, isFront, name }
local function wheels(model)
	local wb = model:GetAttribute("WheelBase") or 5
	local th = model:GetAttribute("TrackHalf") or 0
	if model:GetAttribute("Exit6BikeLife") == "quad" then
		return {
			{ Vector3.new(-th, 0, -wb / 2), true, "FrontLeftWheel" },
			{ Vector3.new(th, 0, -wb / 2), true, "FrontRightWheel" },
			{ Vector3.new(-th, 0, wb / 2), false, "RearLeftWheel" },
			{ Vector3.new(th, 0, wb / 2), false, "RearRightWheel" },
		}
	end
	return {
		{ Vector3.new(0, 0, -wb / 2), true, "FrontWheel" },
		{ Vector3.new(0, 0, wb / 2), false, "RearWheel" },
	}
end
BikePhysics.Wheels = wheels

-- raycasts ignore the ride and every character (rebuilt twice a second)
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = false
local characters, charactersAt = {}, -1
local function excludeFor(model)
	local now = os.clock()
	if now - charactersAt > 0.5 then
		charactersAt = now
		table.clear(characters)
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then table.insert(characters, p.Character) end
		end
	end
	local list = table.clone(characters)
	table.insert(list, model)
	params.FilterDescendantsInstances = list
end

local states = setmetatable({}, { __mode = "k" }) -- model -> smoothed lean / wheelie pitch, stuck timer
local function stateOf(model)
	local s = states[model]
	if not s then
		s = { lean = 0, pitch = 0, stuck = nil, hop = 0, steer = 0 }
		states[model] = s
	end
	return s
end

-- one physics step. input = { throttle 0..1, brake 0..1, steer -1..1,
-- wheelie = bool, rearBrake = bool, parked = bool }
-- returns { speed, front = grounded, rear = grounded, grounded = n,
--           wheelie = bool (front up, rear down), steerAngle, lean, pitch }
function BikePhysics.Step(model, dt, input)
	local chassis = model.PrimaryPart
	if not chassis or chassis.Anchored then return nil end
	dt = math.min(dt, 1 / 30)
	excludeFor(model)
	local isBike = model:GetAttribute("Exit6BikeLife") ~= "quad"
	local kind = isBike and "bike" or "quad"
	local st = stateOf(model)

	local mass = chassis.AssemblyMass
	local g = workspace.Gravity
	local radius = model:GetAttribute("Radius") or 1.2
	local rest = model:GetAttribute("Rest") or T.rest
	local wb = model:GetAttribute("WheelBase") or 5
	local list = wheels(model)
	local nW = #list
	local k = mass * g / nW / T.sag
	local c = 2 * T.damping * math.sqrt(k * mass / nW)

	local cf = chassis.CFrame
	local look = cf.LookVector
	local fwdFlat = Vector3.new(look.X, 0, look.Z)
	if fwdFlat.Magnitude < 0.2 then
		-- pointing at the sky / the ground (fallen): use the up axis to find "forward"
		local up = cf.UpVector
		fwdFlat = Vector3.new(-up.X, 0, -up.Z)
		if fwdFlat.Magnitude < 1e-3 then fwdFlat = Vector3.new(0, 0, -1) end
	end
	fwdFlat = fwdFlat.Unit
	local rightFlat = Vector3.new(-fwdFlat.Z, 0, fwdFlat.X)
	local com = chassis.AssemblyCenterOfMass
	local vel = chassis.AssemblyLinearVelocity
	local ang = chassis.AssemblyAngularVelocity
	local speed = vel:Dot(fwdFlat)
	local speedAbs = math.abs(speed)

	local throttle = math.clamp(input.throttle or 0, 0, 1)
	local brake = math.clamp(input.brake or 0, 0, 1)
	local steer = math.clamp(input.steer or 0, -1, 1)
	local noFuel = (model:GetAttribute("Fuel") or 1) <= 0
	local topSpeed = model:GetAttribute("TopSpeed") or 80
	local accel = model:GetAttribute("EngineAccel") or 30
	local brakeDecel = model:GetAttribute("Brake") or 64
	local grip = (model:GetAttribute("Grip") or 1.2) * T.mu
	local lock = math.rad(model:GetAttribute("SteerLock") or 32)
	local wheelieMax = math.rad(model:GetAttribute("WheelieMax") or 25)
	if st.pitch > 0.05 then topSpeed *= 0.82 end
	-- keys are all-or-nothing: ease the bars toward the input
	local ds = steer - st.steer
	st.steer += math.clamp(ds, -T.steerRate * dt, T.steerRate * dt)
	steer = st.steer
	-- the most lock this speed can carry without asking for more than
	-- maxLateral of cornering (tan(steer) = wheelbase * a / v^2)
	local aMax = T.maxLateral[kind] * (grip / 1.2)
	local speedLock = speedAbs > 1 and math.atan(wb * aMax / (speedAbs * speedAbs)) or lock
	local steerAngle = -steer * math.min(lock, speedLock)

	-- lean of a bike tilts the wheel: its contact sits radius * cos(lean) below the hub
	local cosLean = math.cos(st.lean)
	local reach = (rest + radius) * (isBike and cosLean or 1)
	local nDriven = isBike and 1 or 2
	local grounded, frontDown, rearDown = 0, false, false
	local normalSum = Vector3.zero
	for _, w in ipairs(list) do
		local origin = cf:PointToWorldSpace(w[1])
		local hit = workspace:Raycast(origin, Vector3.new(0, -(reach + 0.4), 0), params)
		if hit and hit.Distance <= reach then
			grounded += 1
			if w[2] then frontDown = true else rearDown = true end
			normalSum += hit.Normal
			local x = math.clamp((reach - hit.Distance) / (isBike and cosLean or 1), 0, rest)
			local pv = vel + ang:Cross(origin - com)
			local load = math.max(0, k * x - c * pv.Y)
			chassis:ApplyImpulseAtPosition(Vector3.yAxis * load * dt, origin)

			-- the tyre
			local n = hit.Normal
			local fwd = w[2] and (CFrame.fromAxisAngle(Vector3.yAxis, steerAngle) * fwdFlat) or fwdFlat
			fwd = fwd - n * fwd:Dot(n)
			if fwd.Magnitude > 1e-3 then
				fwd = fwd.Unit
				local side = n:Cross(fwd).Unit
				local contact = hit.Position
				local cpv = vel + ang:Cross(contact - com)
				local vF, vS = cpv:Dot(fwd), cpv:Dot(side)
				local share = mass / nW
				local maxJ = grip * load * dt
				local latGrip = w[2] and T.lateralGrip * T.frontGrip or T.lateralGrip
				if not w[2] and input.rearBrake then latGrip = isBike and 0.35 or 0.25 end
				local jS = math.clamp(-vS * share * latGrip, -maxJ, maxJ)
				local jF = 0
				local driven = not w[2]
				if throttle > 0.02 then
					if vF < -1.5 then
						jF = math.min(brakeDecel * share * dt, -vF * share)
					elseif driven and not noFuel then
						local fall = 1 - math.clamp(vF / topSpeed, 0, 1) ^ 2
						jF = throttle * accel * mass / nDriven * fall * dt
					end
				end
				if brake > 0.02 then
					if vF > 1 then
						-- front brake does most of the stopping, as on a real bike
						local bias = w[2] and 1.15 or 0.85
						jF -= math.min(brakeDecel * brake * bias * share * dt, vF * share)
					elseif driven and throttle <= 0.02 and not noFuel then
						local rev = T.reverseSpeed[kind]
						local fall = 1 - math.clamp(-vF / rev, 0, 1) ^ 2
						jF -= brake * accel * 0.5 * mass / nDriven * fall * dt
					end
				end
				if driven and input.rearBrake and vF > 1 then
					jF -= math.min(brakeDecel * share * dt, vF * share)
				end
				if throttle <= 0.02 and brake <= 0.02 and not input.rearBrake then
					local decel = (math.abs(vF) < T.holdSpeed) and brakeDecel or T.coastDecel
					jF = -math.sign(vF) * math.min(decel * share * dt, math.abs(vF) * share)
				end
				jF = math.clamp(jF, -maxJ * 1.1, maxJ * 1.1)
				-- drive / brake at the contact patch (nose lifts under power, dives
				-- under braking - the balance controller decides how far); side
				-- grip at the centre of mass height on a bike so cornering force
				-- does not flip it - lean does that job - and part-way up on a quad
				local sideAt = Vector3.new(contact.X, com.Y, contact.Z)
				if not isBike then sideAt = contact:Lerp(sideAt, 0.6) end
				chassis:ApplyImpulseAtPosition(fwd * jF, contact + n * 0.2)
				chassis:ApplyImpulseAtPosition(side * jS, sideAt)
			end
		end
	end

	-- the turn rate the steering asks for (bicycle model); pull the ride toward
	-- it so a ride never spins up beyond what its wheels are pointing at
	if frontDown and rearDown and speedAbs > 2 then
		local want = speed * math.tan(steerAngle) / wb
		local inertia = mass * (wb * wb / 12 + 0.6)
		chassis:ApplyAngularImpulse(Vector3.yAxis * (want - ang.Y) * inertia * math.min(1, dt * T.yawControl))
	end
	-- front wheel in the air on a bike / quad doing a wheelie: steer with the hips
	if rearDown and not frontDown and speedAbs > 2 then
		local wantYaw = -steer * 1.1 * math.sign(speed)
		local yawErr = wantYaw - ang.Y
		chassis:ApplyAngularImpulse(Vector3.yAxis * yawErr * mass * 2.5 * math.min(1, dt * 8))
	end

	-- wedged against a kerb or seam with the throttle open: hop it over
	if throttle > 0.5 and speedAbs < 1.5 and grounded >= 1 and not noFuel then
		local now = os.clock()
		st.stuck = st.stuck or now
		if now - st.stuck > 1.0 and now - st.hop > 1.5 then
			st.hop, st.stuck = now, nil
			chassis:ApplyImpulse((Vector3.yAxis * 18 + fwdFlat * 9) * mass)
		end
	else
		st.stuck = nil
	end
	if vel.Magnitude > 1 then
		chassis:ApplyImpulse(-vel * vel.Magnitude * T.airDrag * mass * dt)
	end

	-- the rider: lean, feet, wheelie balance point
	local groundUp = grounded > 0 and normalSum.Unit or Vector3.yAxis
	local leanTarget = 0
	if isBike then
		if input.parked then
			leanTarget = -T.kickstand
		elseif speedAbs > 3 and frontDown then
			local need = math.atan(speed * speed * math.tan(-steerAngle) / (wb * T.leanGravity))
			leanTarget = math.clamp(need, -T.maxLean, T.maxLean)
		end
	end
	st.lean += (leanTarget - st.lean) * math.min(1, dt * 6)
	local pitchTarget = 0
	if input.wheelie and throttle > 0.2 and rearDown and speedAbs > 4 and not noFuel then
		pitchTarget = wheelieMax * (0.45 + 0.55 * throttle) * (1 - 0.7 * brake)
	end
	local rate = pitchTarget > st.pitch and 2.2 or 3.5
	st.pitch += (pitchTarget - st.pitch) * math.min(1, dt * rate)
	if st.pitch < 0.003 then st.pitch = 0 end
	-- lifting the front means rotating the whole ride and rider about the rear
	-- contact: the engine's drive reaction supplies that torque (m g wb/2), so
	-- the balance controller only has to hold the balance point. It fades with
	-- the wheelie, so letting go brings the front wheel back down.
	if rearDown and st.pitch > 0.01 then
		local share = math.clamp(st.pitch / math.rad(6), 0, 1)
		chassis:ApplyAngularImpulse(cf.RightVector * mass * g * (wb / 2) * math.cos(st.pitch) * share * dt)
	end
	local upT = groundUp * math.cos(st.lean) + rightFlat * math.sin(st.lean)
	upT = upT * math.cos(st.pitch) - fwdFlat * math.sin(st.pitch)
	local align = chassis:FindFirstChild("Balance")
	if align and align:IsA("AlignOrientation") then
		align.PrimaryAxis = upT.Unit
		local airborne = grounded == 0
		align.Responsiveness = airborne and 6 or (st.pitch > 0.05 and 9 or T.balanceResponse[kind])
		align.MaxTorque = mass * T.balanceTorque[kind] * (airborne and 0.35 or 1)
	end

	local pitchNow = math.asin(math.clamp(look.Y, -1, 1))
	return {
		speed = speed, grounded = grounded, front = frontDown, rear = rearDown,
		wheelie = rearDown and not frontDown and pitchNow > math.rad(6),
		steerAngle = steerAngle, lean = st.lean, pitch = pitchNow,
	}
end

return BikePhysics
