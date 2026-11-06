-- ChesterWorld - I-95 / bridge / ramp elevation owner.
-- Ground intersections stay owned by TileBuilderV3, with zero modification.
-- This script runs after all regional tiles have been built.
-- Orientation lock: NORTH=-Z, EAST=+X.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("WorldConfig"))
local Terrain = Workspace.Terrain

Workspace:SetAttribute("CW_RoadConformComplete", false)
while Workspace:GetAttribute("CW_BootstrapComplete") ~= true do task.wait(0.2) end
local world = Workspace:WaitForChild("ChesterWorld")

local CELL = 120
local END_CELL = 12
local CONNECT = Config.HIGHWAY_BRIDGE_CONNECT_TOLERANCE_STUDS or 6
local ROAD_OFFSET = Config.ROAD_SURFACE_OFFSET_STUDS or 0.3
local MARK_OFFSET = Config.CENTERLINE_SURFACE_OFFSET_STUDS or 0.58
local CLEARANCE = Config.HIGHWAY_MIN_CLEARANCE_STUDS or 18
local MAX_LIFT = Config.HIGHWAY_MAX_DECK_LIFT_STUDS or 65
local MAX_RAMP = Config.HIGHWAY_APPROACH_LENGTH_STUDS or 300
local MAX_GRADE = Config.HIGHWAY_MAX_APPROACH_GRADE or 0.10

local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = {Terrain}
terrainParams.IgnoreWater = false

local function terrainY(x, z)
    local result = Workspace:Raycast(
        Vector3.new(x, 3000, z), Vector3.new(0, -6000, 0), terrainParams)
    return result and result.Position.Y or nil
end

-- Estimated small import-seam gaps; do not extrapolate farther than 16 studs.
local function terrainYNearby(x, z)
    local exact = terrainY(x, z)
    if exact then return exact, false end
    for _, radius in ipairs({8, 16}) do
        local samples = {}
        for _, vector in ipairs({
            {1,0}, {-1,0}, {0,1}, {0,-1},
            {0.707,0.707}, {-0.707,0.707},
            {0.707,-0.707}, {-0.707,-0.707},
        }) do
            local y = terrainY(x + vector[1]*radius, z + vector[2]*radius)
            if y then table.insert(samples, y) end
        end
        if #samples >= 2 then
            local total = 0
            for _, y in ipairs(samples) do total += y end
            return total/#samples, true
        end
    end
    return nil, false
end

local function hdist(a, b)
    local dx, dz = a.X - b.X, a.Z - b.Z
    return math.sqrt(dx * dx + dz * dz)
end

local function smoothstep(t)
    t = math.clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end

local function lerp(a, b, t) return a + (b - a) * math.clamp(t, 0, 1) end
local function attr(p, name) return tostring(p:GetAttribute(name) or "") end

local function endpoints(part)
    -- TileBuilder uses length on Size.Z and CFrame.lookAt. Use its TRUE 3D
    -- endpoints, not Size.Z as a horizontal distance (that made bridge gaps).
    local delta = part.CFrame.LookVector * (part.Size.Z / 2)
    return part.Position - delta, part.Position + delta
end

local function setEndpoints(part, a, b)
    local diff = b - a
    if diff.Magnitude < 0.1 then return false end
    local width, thickness = part.Size.X, part.Size.Y
    part.Size = Vector3.new(width, thickness, diff.Magnitude)
    part.CFrame = CFrame.lookAt((a + b) / 2, b, Vector3.yAxis)
    return true
end

local function horizontalUnit(v)
    local h = Vector3.new(v.X, 0, v.Z)
    return h.Magnitude > 0.01 and h.Unit or nil
end

local function gridKey(x, z, cell)
    return math.floor(x / cell) .. ":" .. math.floor(z / cell)
end

local function addEndpoint(index, point, obj)
    local key = gridKey(point.X, point.Z, END_CELL)
    index[key] = index[key] or {}
    table.insert(index[key], {pos = point, obj = obj})
end

local function nearbyEndpoints(index, point)
    local cx, cz = math.floor(point.X / END_CELL), math.floor(point.Z / END_CELL)
    local results = {}
    for dx = -1, 1 do
        for dz = -1, 1 do
            for _, item in ipairs(index[(cx + dx) .. ":" .. (cz + dz)] or {}) do
                if hdist(item.pos, point) <= CONNECT then
                    table.insert(results, item)
                end
            end
        end
    end
    return results
end

local function highwayRoad(part)
    local cls = string.lower(attr(part, "CW_RoadClass"))
    local name = string.lower(attr(part, "ChesterStreet"))
    return cls == "motorway" or cls == "motorway_link"
        or cls == "trunk" or cls == "trunk_link"
        or string.find(name, "i 95", 1, true) ~= nil
        or string.find(name, "i-95", 1, true) ~= nil
end

-- Names from county and OSM often vary only in punctuation/suffix.
-- Match continuity by actual road name without joining unrelated streets.
local function normalizedRoadName(name)
    local value = string.lower(tostring(name or ""))
    value = value:gsub("[^%w%s]", " "):gsub("%s+", " ")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    local suffixes = {
        "%s+street$", "%s+st$", "%s+avenue$", "%s+ave$",
        "%s+boulevard$", "%s+blvd$", "%s+road$", "%s+rd$",
    }
    for _, suffix in ipairs(suffixes) do
        value = value:gsub(suffix, "")
    end
    return value
end

local function collectParts(folderName)
    local result = {}
    for _, tile in ipairs(world:GetChildren()) do
        local folder = tile:FindFirstChild(folderName)
        if folder then
            for _, obj in ipairs(folder:GetDescendants()) do
                if obj:IsA("BasePart") then table.insert(result, obj) end
            end
        end
    end
    return result
end

local allRoads = collectParts("Roads")
local allMarks = collectParts("RoadMarkings")
local atGrade, bridges, tunnelParts = {}, {}, 0
local approachIndex, underRoadGrid = {}, {}

local function addGroundGrid(part)
    local a, b = endpoints(part)
    local halfWidth = part.Size.X / 2
    local minX = math.min(a.X, b.X) - halfWidth
    local maxX = math.max(a.X, b.X) + halfWidth
    local minZ = math.min(a.Z, b.Z) - halfWidth
    local maxZ = math.max(a.Z, b.Z) + halfWidth
    for gx = math.floor(minX / CELL), math.floor(maxX / CELL) do
        for gz = math.floor(minZ / CELL), math.floor(maxZ / CELL) do
            local key = gx .. ":" .. gz
            underRoadGrid[key] = underRoadGrid[key] or {}
            table.insert(underRoadGrid[key], part)
        end
    end
end

local highwayProfiledParts = 0
for _, part in ipairs(allRoads) do
    local level = tonumber(part:GetAttribute("CW_GradeLevel")) or 0
    local isBridge = part:GetAttribute("CW_Bridge") == true or level > 0
    if part:GetAttribute("CW_HighwayProfiled") == true then
        -- Elevation is owned by HighwayProfile (TileBuilderV2). Never move
        -- it here, never use it as a ramp approach, but DO keep it as a
        -- lower road so local overpasses are lifted to clear it.
        highwayProfiledParts += 1
        table.insert(atGrade, part)
        addGroundGrid(part)
    elseif isBridge then
        local key = attr(part, "CW_GradeGroup")
        if key == "" then
            key = attr(part, "ChesterStreet") .. ":g" .. level
        end
        bridges[key] = bridges[key] or {}
        table.insert(bridges[key], part)
    else
        table.insert(atGrade, part)
        addGroundGrid(part)
        if part:GetAttribute("CW_Tunnel") == true or level < 0 then
            tunnelParts += 1
        end
        -- All bridge types need realistic approaches, not just I-95.
        -- Index named ground roads; the chain search below still requires
        -- name/direction agreement, so cross streets cannot be pulled upward.
        local cls = string.lower(attr(part, "CW_RoadClass"))
        if level == 0 and part:GetAttribute("CW_Tunnel") ~= true
            and normalizedRoadName(attr(part, "ChesterStreet")) ~= ""
            and normalizedRoadName(attr(part, "ChesterStreet")) ~= "road"
            and cls ~= "service" and cls ~= "alley" then
            local a, b = endpoints(part)
            addEndpoint(approachIndex, a, part)
            addEndpoint(approachIndex, b, part)
        end
        part:SetAttribute("CW_TerrainConformed", true)
        part:SetAttribute("CW_ElevationOwner", "TileBuilderV3")
    end
end

-- A grade group may have several disconnected spans or carriageways.
-- Never force unrelated components through one shared start/end profile.
local function components(parts)
    local groups, seen = {}, {}
    for _, first in ipairs(parts) do
        if not seen[first] then
            local queue, component = {first}, {}
            seen[first] = true
            local head = 1
            while head <= #queue do
                local part = queue[head]
                head += 1
                table.insert(component, part)
                local a, b = endpoints(part)
                for _, other in ipairs(parts) do
                    if not seen[other] then
                        local x, y = endpoints(other)
                        if hdist(a, x) <= CONNECT or hdist(a, y) <= CONNECT
                            or hdist(b, x) <= CONNECT or hdist(b, y) <= CONNECT then
                            seen[other] = true
                            table.insert(queue, other)
                        end
                    end
                end
            end
            table.insert(groups, component)
        end
    end
    return groups
end

local function dominantDirection(parts)
    local total, ref = Vector3.zero, nil
    for _, part in ipairs(parts) do
        local a, b = endpoints(part)
        local v = horizontalUnit(b - a)
        if v then
            if not ref then ref = v end
            if v:Dot(ref) < 0 then v = -v end
            total += v * hdist(a, b)
        end
    end
    return horizontalUnit(total) or ref or Vector3.new(1, 0, 0)
end

local function crossingT(a, b, c, d)
    local rx, rz = b.X - a.X, b.Z - a.Z
    local sx, sz = d.X - c.X, d.Z - c.Z
    local det = rx * sz - rz * sx
    if math.abs(det) < 0.001 then return nil end
    local dx, dz = c.X - a.X, c.Z - a.Z
    local t = (dx * sz - dz * sx) / det
    local u = (dx * rz - dz * rx) / det
    -- Source roads are split exactly AT their crossing vertex, so a real
    -- crossing usually touches a segment end (t or u = 0/1). Accept closed
    -- intervals; reject shallow angles (same-road continuations). Callers
    -- reject crossings at the bridge component's own terminals.
    local e = 1e-4
    if t >= -e and t <= 1 + e and u >= -e and u <= 1 + e then
        local sine = math.abs(det) / math.max(
            math.sqrt(rx * rx + rz * rz) * math.sqrt(sx * sx + sz * sz), 1e-6)
        if sine > 0.26 then
            return math.clamp(t, 0, 1), math.clamp(u, 0, 1)
        end
    end
    return nil
end

local function underRoadsForSegment(a, b)
    local visited, found = {}, {}
    local minGX = math.floor(math.min(a.X, b.X) / CELL) - 1
    local maxGX = math.floor(math.max(a.X, b.X) / CELL) + 1
    local minGZ = math.floor(math.min(a.Z, b.Z) / CELL) - 1
    local maxGZ = math.floor(math.max(a.Z, b.Z) / CELL) + 1
    for gx = minGX, maxGX do
        for gz = minGZ, maxGZ do
            for _, road in ipairs(underRoadGrid[gx .. ":" .. gz] or {}) do
                if not visited[road] then
                    visited[road] = true
                    table.insert(found, road)
                end
            end
        end
    end
    return found
end

local rampUsed = {}
local function findApproachChain(terminal, outward, bridgeName)
    local chain, used = {}, {}
    local current = terminal
    local distance = 0
    while distance < MAX_RAMP do
        local best, bestScore, bestFar = nil, -math.huge, nil
        for _, item in ipairs(nearbyEndpoints(approachIndex, current)) do
            local part = item.obj
            if not used[part] and not rampUsed[part] then
                local x, y = endpoints(part)
                local far = hdist(x, item.pos) < hdist(y, item.pos) and y or x
                local away = horizontalUnit(far - current)
                if away and hdist(far, current) > 0.5 then
                    local dot = away:Dot(outward)
                    local partName = attr(part, "ChesterStreet")
                    local matchName =
                        normalizedRoadName(partName) ~= ""
                        and normalizedRoadName(partName) == normalizedRoadName(bridgeName)
                    local cls = string.lower(attr(part, "CW_RoadClass"))
                    local isLink = cls == "motorway_link" or cls == "trunk_link"
                    local bridgeI95 = string.find(string.lower(bridgeName),
                        "i 95",1,true) ~= nil or
                        string.find(string.lower(bridgeName),
                        "i-95",1,true) ~= nil
                    local approachI95 = string.find(string.lower(partName),
                        "i 95",1,true) ~= nil or
                        string.find(string.lower(partName),
                        "i-95",1,true) ~= nil
                    local related = matchName or
                        (bridgeI95 and approachI95) or
                        (isLink and bridgeI95)
                    -- Don't follow arbitrary nearby streets through a sharp
                    -- turn. The old 0.24 dot threshold could grab a road at
                    -- ~76 degrees and manufacture a steep "ramp".
                    local score = dot + (matchName and 0.5 or 0)
                    if related and dot > 0.70 and score > bestScore then
                        best, bestScore, bestFar = part, score, far
                    end
                end
            end
        end
        if not best then break end
        local near = current
        local segmentLength = hdist(near, bestFar)
        table.insert(chain, {
            part = best, near = near, far = bestFar,
            startDistance = distance,
            endDistance = distance + segmentLength,
        })
        used[best] = true
        distance += segmentLength
        local newAway = horizontalUnit(bestFar - near)
        if newAway then outward = newAway end
        current = bestFar
    end
    return chain, math.min(distance, MAX_RAMP)
end

local profilesByGroup = {}
local rampsByGroup = {}

-- Source grade_group is usually a single county feature ID. Adjacent pieces
-- of the SAME elevated roadway often get different IDs; profiling each one
-- creates dozens of 24-60 stud "bridges" with no room for a real slope.
-- Group by normalized name + elevation layer, then split by actual shared
-- endpoints. Two parallel carriageways remain separate unless connected.
local corridorBridges = {}
local sourceBridgeGroups = 0
for _, group in pairs(bridges) do
    sourceBridgeGroups += 1
    for _, part in ipairs(group) do
        local level = tonumber(part:GetAttribute("CW_GradeLevel")) or 0
        local cleanName = normalizedRoadName(attr(part, "ChesterStreet"))
        local key = cleanName .. ":elevation:" .. tostring(level)
        if cleanName == "" or cleanName == "road" then
            key = attr(part, "CW_GradeGroup")
        end
        corridorBridges[key] = corridorBridges[key] or {}
        table.insert(corridorBridges[key], part)
    end
end

local stats = {
    groups = 0, components = 0, bridgeParts = 0, bridgeConformed = 0,
    bridgeNoTerrain = 0, failed = 0, tunnelParts = tunnelParts,
    rampParts = 0, rampGroups = 0, marked = 0,
    crossingChecks = 0, clearanceWarnings = 0, steepGroups = 0,
    terrainClearanceWarnings = 0, terrainEndpointEstimates = 0,
    insufficientApproachLength = 0, gradeLimitedParts = 0,
    actualSteepParts = 0, baselineSteepGroups = 0,
}

local function conformComponent(parts, groupKey)
    local direction = dominantDirection(parts)
    local records, low, high = {}, math.huge, -math.huge
    local lowPoint, highPoint = nil, nil
    local nominalClearance = CLEARANCE

    for _, part in ipairs(parts) do
        local a, b = endpoints(part)
        local ta = a.X * direction.X + a.Z * direction.Z
        local tb = b.X * direction.X + b.Z * direction.Z
        if ta > tb then a, b, ta, tb = b, a, tb, ta end
        table.insert(records, {part = part, a = a, b = b, pa = ta, pb = tb})
        if ta < low then low, lowPoint = ta, a end
        if tb > high then high, highPoint = tb, b end
        nominalClearance = math.max(nominalClearance,
            tonumber(part:GetAttribute("CW_GradeClearanceStuds")) or 0)
    end

    if not lowPoint or not highPoint then return nil end
    local startGround, estimatedStart = terrainYNearby(lowPoint.X, lowPoint.Z)
    local endGround, estimatedEnd = terrainYNearby(highPoint.X, highPoint.Z)
    if not startGround or not endGround then
        stats.bridgeNoTerrain += #parts
        return nil
    end

    if estimatedStart or estimatedEnd then
        stats.terrainEndpointEstimates +=
            (estimatedStart and 1 or 0) + (estimatedEnd and 1 or 0)
        for _, part in ipairs(parts) do
            part:SetAttribute("CW_TerrainEndpointEstimated", true)
        end
    end

    local span = math.max(high - low, 0.1)
    local bridgeName = attr(parts[1], "ChesterStreet")
    local rampStart, startLength = {}, 0
    local rampEnd, endLength = {}, 0
    -- This applies to I-95 AND short local overpasses such as Macdade,
    -- Flower and Melrose. With no valid matching continuation, leave it
    -- flagged rather than attaching an unrelated roadway.
    rampStart, startLength = findApproachChain(lowPoint, -direction, bridgeName)
    rampEnd, endLength = findApproachChain(highPoint, direction, bridgeName)

    -- A smoothstep transition has a maximum derivative of 1.5.
    -- Limit bridge terminal lift to what an actual adjacent ramp can absorb.
    local startLift = math.min(nominalClearance, startLength * MAX_GRADE / 1.5)
    local endLift = math.min(nominalClearance, endLength * MAX_GRADE / 1.5)
    local targetLift = nominalClearance

    -- Ground streets are left untouched; raise a deck enough to clear them.
    local crossings = {}
    local seenCrossing = {}
    local bridgeNameKey = normalizedRoadName(attr(parts[1], "ChesterStreet"))
    for _, rec in ipairs(records) do
        for _, lower in ipairs(underRoadsForSegment(rec.a, rec.b)) do
            local x, y = endpoints(lower)
            local t, u = crossingT(rec.a, rec.b, x, y)
            local position = t and rec.a:Lerp(rec.b, t)
            local station = position and (position.X * direction.X
                + position.Z * direction.Z - low) / span
            -- Touching the deck at its own terminal is an at-grade junction,
            -- and a same-name road is this bridge's own approach.
            if t and (station <= 0.03 or station >= 0.97
                or normalizedRoadName(attr(lower, "ChesterStreet")) == bridgeNameKey
                or seenCrossing[lower]) then
                t = nil
            end
            if t then
                seenCrossing[lower] = true
                local groundTop = lerp(x.Y, y.Y, u) + lower.Size.Y / 2
                local baseline = lerp(startGround, endGround, station)
                    + ROAD_OFFSET + rec.part.Size.Y / 2
                local needed = groundTop + CLEARANCE
                    + (Config.HIGHWAY_DECK_THICKNESS_STUDS or 1.6) - baseline
                targetLift = math.max(targetLift, needed)
                table.insert(crossings, {t = station, needed = needed,
                    label = "over " .. attr(lower, "ChesterStreet")})
            end
        end
    end
    -- No road or track passes under this deck: it is a creek / ravine
    -- crossing (Chester Creek at 2nd, 7th, 9th and Bridgewater; Brookhaven,
    -- Chestnut, Morton - DVRPC 2025 aerial, crossing_aerial.py st_*). Those
    -- are level street bridges straight across the valley between the two
    -- banks; the clearance lift and bank-terrain requirements only gave them
    -- humps of 17-37 % grade. Deck = straight chord between the bank ends.
    local waterCrossing = #crossings == 0
    if waterCrossing then
        nominalClearance, startLift, endLift, targetLift = 0, 0, 0, 0
        stats.waterCrossings = (stats.waterCrossings or 0) + 1
        -- The county bridge segment often lies in the valley floor (Chestnut:
        -- banks 27-30, floor 6; Brookhaven: banks 43, floor 30) and the real
        -- bridge spans the ravine at bank height. Scan the ground outward
        -- from each end to the top of the valley side and hang the deck chord
        -- between the two bank tops.
        local function bankTop(point, outward)
            local ys = {}
            for i = 0, 40 do
                local p = point + outward * (i * 6)
                ys[i] = terrainY(p.X, p.Z)
                if not ys[i] then break end
            end
            local y0 = ys[0]
            if not y0 then return nil end
            for i = 5, #ys do
                if ys[i] and ys[i - 5] and ys[i] > y0 + 3 and ys[i] - ys[i - 5] < 1.5 then
                    return ys[i]
                end
            end
            return nil
        end
        local bankA = bankTop(lowPoint, -direction)
        local bankB = bankTop(highPoint, direction)
        -- a ravine has a bank on BOTH sides and a near-level deck between
        -- them; a one-sided rise is a hillside street (Bridgewater), not a bank
        local spanLen = math.max(high - low, 1)
        if bankA and bankB and (bankA > startGround + 3 or bankB > endGround + 3)
            and math.abs(math.max(bankA, startGround) - math.max(bankB, endGround)) / spanLen <= 0.08 then
            if bankA > startGround then startGround = bankA end
            if bankB > endGround then endGround = bankB end
            stats.bankRaised = (stats.bankRaised or 0) + 1
        end
    end

    -- The previous solver checked the HIGH point only, yet some decks were
    -- still embedded on their sloping quarters. Record actual requirements
    -- at each bridge station and solve for the lifted envelope at THAT t.
    -- Ends are abutments and may be buried in the bank; we sample a little
    -- inside the span to avoid incorrectly requiring an elevated terminal.
    local terrainRequirements = {}
    local deckDepth = Config.HIGHWAY_DECK_THICKNESS_STUDS or 1.6
    for _, rec in ipairs(waterCrossing and {} or records) do
        for _, fractionAlong in ipairs({0.15, 0.35, 0.5, 0.65, 0.85}) do
            local point = rec.a:Lerp(rec.b, fractionAlong)
            local gy = terrainY(point.X, point.Z)
            if gy then
                local t = math.clamp(
                    (point.X*direction.X + point.Z*direction.Z-low)/span,0,1)
                if t > 0.025 and t < 0.975 then
                    local baseline = lerp(startGround,endGround,t)
                        + ROAD_OFFSET-rec.part.Size.Y/2-deckDepth
                    table.insert(terrainRequirements,{
                        t=t,needed=gy+1.0-baseline,label="terrain",
                    })
                end
            end
        end
    end
    targetLift = math.clamp(targetLift,nominalClearance,
        math.max(MAX_LIFT,nominalClearance))
    stats.crossingChecks += #crossings

    -- Smooth transition inside the tagged bridge region. Approach roads, when
    -- available, absorb much of the climb without touching city intersections.
    local fraction = math.clamp(Config.BRIDGE_RAMP_FRACTION or 0.38, 0.20, 0.49)

    -- Crossing clearance must be checked at the crossing's station, NOT only
    -- against the highest plateau. If it lies on a ramp, solve for the deck
    -- peak needed to clear that lower road at the actual intersection point.
    -- Never exceed MAX_LIFT; impossible crossings stay flagged by the audit.
    local drivenBy = "nominal"
    local allRequirements = {}
    for _, requirement in ipairs(crossings) do
        table.insert(allRequirements,requirement)
    end
    for _, requirement in ipairs(terrainRequirements) do
        table.insert(allRequirements,requirement)
    end
    for _, crossing in ipairs(allRequirements) do
        local t = crossing.t
        local ease = 1
        local terminalLift = 0
        if t < fraction then
            ease = smoothstep(t / fraction)
            terminalLift = startLift
        elseif t > 1 - fraction then
            ease = smoothstep((1 - t) / fraction)
            terminalLift = endLift
        end
        if ease > 0.001 then
            local requestedPeak = (crossing.needed
                - terminalLift * (1 - ease)) / ease
            if requestedPeak > targetLift then
                drivenBy = string.format("%s@t=%.2f", crossing.label or "?", t)
            end
            targetLift = math.clamp(math.max(targetLift, requestedPeak),
                nominalClearance, math.max(MAX_LIFT, nominalClearance))
        end
    end
    -- HARD SLOPE CAP: a 25-stud county bridge can NOT gain 18 studs in
    -- its 9-stud transition section. Prior code warned but still GENERATED
    -- a 100%-300% rise. Respect capacity on BOTH approaches first.
    -- Smoothstep has a peak derivative of 1.5. Its allowed height change
    -- is therefore distance * MAX_GRADE / 1.5.
    local requestedLift = targetLift
    local innerCapacity = (span * fraction) * MAX_GRADE / 1.5
    local outerStartCapacity = startLength * MAX_GRADE / 1.5
    local outerEndCapacity = endLength * MAX_GRADE / 1.5
    local feasiblePeak = math.max(0, math.min(requestedLift,
        innerCapacity + outerStartCapacity,
        innerCapacity + outerEndCapacity))
    local noApproachClearance = requestedLift - feasiblePeak > 0.5
    targetLift = feasiblePeak
    startLift = math.min(targetLift, outerStartCapacity)
    endLift = math.min(targetLift, outerEndCapacity)
    if noApproachClearance then
        stats.insufficientApproachLength += 1
        stats.gradeLimitedParts += #parts
        for _, rec in ipairs(records) do
            rec.part:SetAttribute("CW_GradeLimited", true)
            rec.part:SetAttribute("CW_RequestedDeckLift", requestedLift)
            rec.part:SetAttribute("CW_AchievableDeckLift", targetLift)
        end
        if stats.insufficientApproachLength <= 12 then
            warn(("[ChesterWorld BridgeGradeLimited] name=%s group=%s x=%.1f z=%.1f span=%.1f requested=%.1f feasible=%.1f rampStart=%.1f rampEnd=%.1f drivenBy=%s"):format(
                bridgeName, groupKey,
                (lowPoint.X+highPoint.X)/2, (lowPoint.Z+highPoint.Z)/2,
                span, requestedLift, targetLift, startLength, endLength, drivenBy))
        end
    end

    local function liftAt(t)
        if t < fraction then
            return lerp(startLift, targetLift, smoothstep(t / fraction))
        elseif t > 1 - fraction then
            return lerp(endLift, targetLift,
                smoothstep((1 - t) / fraction))
        end
        return targetLift
    end
    local function centerY(t)
        return lerp(startGround, endGround, t) + ROAD_OFFSET + liftAt(t)
    end
    local function atXZ(x, z)
        local station = math.clamp((x * direction.X + z * direction.Z - low)
            / span, 0, 1)
        return centerY(station)
    end

    for _, rec in ipairs(records) do
        local t0 = math.clamp((rec.pa - low) / span, 0, 1)
        local t1 = math.clamp((rec.pb - low) / span, 0, 1)
        local a = Vector3.new(rec.a.X, centerY(t0), rec.a.Z)
        local b = Vector3.new(rec.b.X, centerY(t1), rec.b.Z)
        if setEndpoints(rec.part, a, b) then
            rec.part:SetAttribute("CW_TerrainConformed", true)
            rec.part:SetAttribute("CW_BridgeProfiled", true)
            rec.part:SetAttribute("CW_ElevationOwner", "RoadTerrainConformer:BridgeDeck")
            rec.part:SetAttribute("CW_DeckLiftCenter", liftAt((t0 + t1) / 2))
            stats.bridgeConformed += 1
        else
            stats.failed += 1
        end
    end

    -- Absolute roadway grade includes the REAL bare-earth baseline.
    -- Limiting only artificial lift doesn't make a naturally steep hillside
    -- driveable. Measure the fully rendered segment endpoints as well.
    local actualMaxGrade, segmentSteep = 0, 0
    for _, rec in ipairs(records) do
        local a, b = endpoints(rec.part)
        local horizontal = hdist(a, b)
        if horizontal > 0.1 then
            local grade = math.abs(a.Y-b.Y)/horizontal
            actualMaxGrade = math.max(actualMaxGrade, grade)
            if grade > MAX_GRADE * 1.15 then
                segmentSteep += 1
                rec.part:SetAttribute("CW_HighwayUnsafeGrade", true)
                rec.part:SetAttribute("CW_HighwayMaxGrade", grade)
                -- Skip structural dressing on places that still require
                -- terrain reconstruction / surveyed bridge endpoint levels.
                rec.part:SetAttribute("CW_GradeLimited", true)
            end
        end
    end
    if segmentSteep > 0 then
        stats.actualSteepParts += segmentSteep
        stats.baselineSteepGroups += 1
    end

    -- A bridge's tagged source span can be short. Report unsafe profiles rather
    -- than silently pretending the designed 10% ramp grade was achieved.
    local maxLeftGrade = 1.5 * math.abs(targetLift - startLift) / (span * fraction)
    local maxRightGrade = 1.5 * math.abs(targetLift - endLift) / (span * fraction)
    local worstGrade = math.max(maxLeftGrade,maxRightGrade)
    if worstGrade > 0.20 then
        stats.steepGroups += 1
        -- Report the physical impossibility instead of labeling a smooth
        -- interpolation as a safe highway ramp.
        if stats.steepGroups <= 12 then
            warn(("[ChesterWorld UnsafeBridgeProfile] name=%s group=%s x=%.1f z=%.1f span=%.1f studs maxGrade=%.1f%% rampStart=%.1f rampEnd=%.1f peakLift=%.1f"):format(
                bridgeName,groupKey,
                (lowPoint.X+highPoint.X)/2,(lowPoint.Z+highPoint.Z)/2,
                span,worstGrade*100,startLength,endLength,targetLift))
        end
        for _, rec in ipairs(records) do
            rec.part:SetAttribute("CW_HighwayUnsafeGrade",true)
            rec.part:SetAttribute("CW_HighwayMaxGrade",worstGrade)
        end
    end
    -- Track unresolved terrain and lower-road requirements distinctly.
    local terrainUnresolved = 0
    for _, requirement in ipairs(terrainRequirements) do
        if liftAt(requirement.t) + 0.25 < requirement.needed then
            terrainUnresolved += 1
        end
    end
    stats.terrainClearanceWarnings += terrainUnresolved
    for _, crossing in ipairs(crossings) do
        if liftAt(crossing.t) + 0.5 < crossing.needed then
            stats.clearanceWarnings += 1
        end
    end

    local sourceGroups = {}
    for _, part in ipairs(parts) do
        local originalGroup = attr(part, "CW_GradeGroup")
        if originalGroup ~= "" then sourceGroups[originalGroup] = true end
    end
    local profile = {
        group = groupKey, sourceGroups = sourceGroups, parts = parts,
        atXZ = atXZ, low = low, high = high,
        centerY = centerY, direction = direction,
        start = lowPoint, finish = highPoint,
    }
    table.insert(profilesByGroup, profile)

    -- Build ramp approaches only after the deck is positioned, and join their
    -- source endpoints exactly to the new bridge terminal heights.
    local function applyRamp(chain, totalLength, bridgeEnd, deckY)
        if #chain == 0 or totalLength < 0.1 then return end
        local nearRoad = chain[1].part
        local x, y = endpoints(nearRoad)
        local initialNear = hdist(x, bridgeEnd) < hdist(y, bridgeEnd) and x or y
        local lift = deckY - initialNear.Y
        -- Preserve at-grade city roads. Never lift arbitrary local approaches.
        local fade = math.max(totalLength, 0.1)
        local changed = 0
        for _, seg in ipairs(chain) do
            if rampUsed[seg.part] then break end
            local startPoint, endPoint = endpoints(seg.part)
            local near = hdist(startPoint, seg.near) <= hdist(endPoint, seg.near)
                and startPoint or endPoint
            local far = near == startPoint and endPoint or startPoint
            local d0 = math.min(seg.startDistance, fade)
            local d1 = math.min(seg.endDistance, fade)
            local lift0 = lift * (1 - smoothstep(d0 / fade))
            local lift1 = lift * (1 - smoothstep(d1 / fade))
            local na = Vector3.new(near.X, near.Y + lift0, near.Z)
            local nb = Vector3.new(far.X, far.Y + lift1, far.Z)
            if setEndpoints(seg.part, na, nb) then
                rampUsed[seg.part] = true
                seg.part:SetAttribute("CW_RampProfiled", true)
                seg.part:SetAttribute("CW_RampLiftCenter", (lift0 + lift1) / 2)
                seg.part:SetAttribute("CW_TerrainConformed", true)
                seg.part:SetAttribute("CW_ElevationOwner", "RoadTerrainConformer:HighwayRamp")
                rampsByGroup[attr(seg.part, "CW_GradeGroup")] =
                    rampsByGroup[attr(seg.part, "CW_GradeGroup")] or {}
                table.insert(rampsByGroup[attr(seg.part, "CW_GradeGroup")], seg.part)
                stats.rampParts += 1
                changed += 1
            end
        end
        if changed > 0 then
            stats.rampGroups += 1
            if math.abs(lift) * 1.5 / fade > MAX_GRADE * 1.2 then
                stats.steepGroups += 1
            end
        end
    end

    applyRamp(rampStart, startLength, lowPoint, centerY(0))
    applyRamp(rampEnd, endLength, highPoint, centerY(1))
    return profile
end

-- The county source tags the LOWER road's pieces under a structure as bridge
-- too (2nd under the Barry approach, the MacDade ramp under Bullens Lane).
-- A tagged component that passes under a profiled highway span or elevated
-- highway, or under a road the structure registry names as its upper road,
-- is a ground road: it stays on the terrain and overpasses clear it.
local Registry = require(Shared:WaitForChild("HighwayStructureRegistry"))
local ELEVATED_HIGHWAY = Config.HIGHWAY_LOWER_ROAD_DETECT_STUDS or 8
local bridgeGrid = {}
for _, group in pairs(corridorBridges) do
    for _, part in ipairs(group) do
        local a, b = endpoints(part)
        for gx = math.floor(math.min(a.X, b.X) / CELL), math.floor(math.max(a.X, b.X) / CELL) do
            for gz = math.floor(math.min(a.Z, b.Z) / CELL), math.floor(math.max(a.Z, b.Z) / CELL) do
                local cellKey = gx .. ":" .. gz
                bridgeGrid[cellKey] = bridgeGrid[cellKey] or {}
                table.insert(bridgeGrid[cellKey], part)
            end
        end
    end
end
local function upperRoadOver(component)
    for _, part in ipairs(component) do
        local a, b = endpoints(part)
        local myName = attr(part, "ChesterStreet")
        local myKey = normalizedRoadName(myName)
        local candidates = underRoadsForSegment(a, b)
        for gx = math.floor(math.min(a.X, b.X) / CELL) - 1, math.floor(math.max(a.X, b.X) / CELL) + 1 do
            for gz = math.floor(math.min(a.Z, b.Z) / CELL) - 1, math.floor(math.max(a.Z, b.Z) / CELL) + 1 do
                for _, other in ipairs(bridgeGrid[gx .. ":" .. gz] or {}) do
                    table.insert(candidates, other)
                end
            end
        end
        for _, other in ipairs(candidates) do
            local otherName = attr(other, "ChesterStreet")
            if other ~= part and normalizedRoadName(otherName) ~= myKey then
                local c, d = endpoints(other)
                local t, u = crossingT(a, b, c, d)
                if t then
                    local position = a:Lerp(b, t)
                    local elevatedHighway = false
                    if other:GetAttribute("CW_HighwayProfiled") == true then
                        local top = lerp(c.Y, d.Y, u) + other.Size.Y / 2
                        local ground = terrainY(position.X, position.Z)
                        elevatedHighway = other:GetAttribute("CW_HighwayStructure") == "span"
                            or (ground ~= nil and top - ground > ELEVATED_HIGHWAY)
                    end
                    if elevatedHighway
                        or Registry.NamedRelation(otherName, myName, position.X, position.Z) then
                        return otherName, position
                    end
                end
            end
        end
    end
    return nil
end
local bridgeComponents = {}
local lowerRoadParts, lowerRoadComponents = 0, 0
local loweredGroups = {}
for key, group in pairs(corridorBridges) do
    stats.groups += 1
    stats.bridgeParts += #group
    for _, component in ipairs(components(group)) do
        local upperName, position = upperRoadOver(component)
        if not upperName then
            for _, part in ipairs(component) do
                local grounded = Registry.Grounded(attr(part, "CW_GradeGroup"))
                if grounded then
                    upperName, position = "no structure (" .. grounded.id .. ")", part.Position
                    break
                end
            end
        end
        if upperName then
            for _, part in ipairs(component) do
                -- TileBuilderV2 built it terrain-following at the level proxy
                -- height; drop it back to the terrain.
                local level = tonumber(part:GetAttribute("CW_GradeLevel")) or 1
                local drop = math.max(level, 0) * (Config.GRADE_SEPARATION_CLEARANCE_STUDS or 0)
                if drop > 0 then
                    part.CFrame -= Vector3.new(0, drop, 0)
                    loweredGroups[attr(part, "CW_GradeGroup")] = drop
                end
                part:SetAttribute("CW_LowerRoadUnderStructure", upperName)
                part:SetAttribute("CW_TerrainConformed", true)
                part:SetAttribute("CW_ElevationOwner", "TileBuilderV3")
                table.insert(atGrade, part)
                addGroundGrid(part)
                lowerRoadParts += 1
            end
            lowerRoadComponents += 1
            if lowerRoadComponents <= 12 then
                print(("[ChesterWorld LowerRoadNotLifted] %s under %s at (%.1f, %.1f)")
                    :format(attr(component[1], "ChesterStreet"), upperName, position.X, position.Z))
            end
        else
            table.insert(bridgeComponents, { parts = component, key = key })
        end
    end
end
for _, marking in ipairs(allMarks) do
    local drop = loweredGroups[attr(marking, "CW_GradeGroup")]
    if drop then
        marking.CFrame -= Vector3.new(0, drop, 0)
    end
end
for _, item in ipairs(bridgeComponents) do
    stats.components += 1
    conformComponent(item.parts, item.key)
    task.wait()
end
print(("[ChesterWorld RoadTerrainConformer] lowerRoadPartsNotLifted=%d (county bridge tags on the road beneath a structure)")
    :format(lowerRoadParts))

-- Reposition yellow lane markings using the same grade group and X/Z deck
-- profile. They must never be left hovering at the old 18-stud proxy height.
local marksByGroup = {}
for _, marking in ipairs(allMarks) do
    local gradeGroup = attr(marking, "CW_GradeGroup")
    if gradeGroup ~= "" and attr(marking, "MarkingType") == "CenterLine" then
        marksByGroup[gradeGroup] = marksByGroup[gradeGroup] or {}
        table.insert(marksByGroup[gradeGroup], marking)
    end
end

local function profileDistance(profile, position)
    local nearest = math.huge
    for _, part in ipairs(profile.parts) do
        local a, b = endpoints(part)
        local segment = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
        local length2 = segment:Dot(segment)
        if length2 > 0.01 then
            local delta = Vector3.new(position.X-a.X, 0, position.Z-a.Z)
            local t = math.clamp(delta:Dot(segment) / length2, 0, 1)
            local p = a + (b-a)*t
            nearest = math.min(nearest, hdist(p, position))
        end
    end
    return nearest
end

for _, profile in ipairs(profilesByGroup) do
    local marks = {}
    for originalGroup in pairs(profile.sourceGroups) do
        for _, marking in ipairs(marksByGroup[originalGroup] or {}) do
            table.insert(marks, marking)
        end
    end
    for _, marking in ipairs(marks) do
        local a, b = endpoints(marking)
        local halfWidth = marking.Size.X
        if profileDistance(profile, marking.Position) <= math.max(halfWidth + 7, 15) then
            local offset = MARK_OFFSET - ROAD_OFFSET
            local ma = Vector3.new(a.X, profile.atXZ(a.X, a.Z) + offset, a.Z)
            local mb = Vector3.new(b.X, profile.atXZ(b.X, b.Z) + offset, b.Z)
            if setEndpoints(marking, ma, mb) then
                marking:SetAttribute("CW_ElevationOwner", "RoadTerrainConformer:BridgeMarking")
                stats.marked += 1
            end
        end
    end
end

-- Grade-0 motorway ramps can share a source group with other at-grade pieces.
-- Raise only markers whose actual road centerline belongs to a profiled ramp.
for groupKey, parts in pairs(rampsByGroup) do
    for _, marking in ipairs(marksByGroup[groupKey] or {}) do
        local a, b = endpoints(marking)
        local function markY(point)
            local best, bestDistance = nil, math.huge
            for _, road in ipairs(parts) do
                local x, y = endpoints(road)
                local d = Vector3.new(y.X-x.X,0,y.Z-x.Z)
                local d2 = d:Dot(d)
                if d2 > 0.01 then
                    local t = math.clamp(Vector3.new(point.X-x.X,0,point.Z-x.Z):Dot(d)/d2,0,1)
                    local nearest = x:Lerp(y,t)
                    local distance = hdist(nearest,point)
                    if distance < bestDistance then
                        bestDistance = distance
                        best = nearest.Y
                    end
                end
            end
            return bestDistance < 15 and best and best + (MARK_OFFSET-ROAD_OFFSET) or nil
        end
        local ya, yb = markY(a), markY(b)
        if ya and yb and setEndpoints(marking,
            Vector3.new(a.X, ya, a.Z), Vector3.new(b.X, yb, b.Z)) then
            marking:SetAttribute("CW_ElevationOwner", "RoadTerrainConformer:RampMarking")
            stats.marked += 1
        end
    end
end

-- Registry-confirmed local overpasses (Edgmont, Madison, Melrose over I-95).
-- County data shares vertices between the street and the highway beneath it,
-- so the street's bridge pieces start on the highway centreline and the
-- bare-earth DEM has no deck: both put the street down in the highway cut.
-- Hold the street at deck level over each carriageway (street rim, and never
-- less than the highway top + clearance), easing back to the terrain-
-- following street at MAX_GRADE. Only raises; never lowers a street.
local HighwayProfile = require(script.Parent:WaitForChild("HighwayProfile"))
local OVERPASS_PLATEAU = 20
local overpassDecks = {}
local overpassByName = {}
for _, crossing in ipairs(HighwayProfile.LocalOverpasses()) do
    local highwayTop = -math.huge
    local key = normalizedRoadName(crossing.name)
    for _, part in ipairs(allRoads) do
        -- (a street with motorway-classed pieces is profiled too: skip itself)
        if part:GetAttribute("CW_HighwayProfiled") == true
            and normalizedRoadName(attr(part, "ChesterStreet")) ~= key
            and math.abs(part.Position.X - crossing.x) < 40
            and math.abs(part.Position.Z - crossing.z) < 40 then
            local a, b = endpoints(part)
            local d = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
            local d2 = d:Dot(d)
            if d2 > 0.01 then
                local t = math.clamp(Vector3.new(crossing.x - a.X, 0, crossing.z - a.Z):Dot(d) / d2, 0, 1)
                local p = a:Lerp(b, t)
                if hdist(p, Vector3.new(crossing.x, 0, crossing.z)) < part.Size.X / 2 + 2 then
                    highwayTop = math.max(highwayTop, p.Y + part.Size.Y / 2)
                end
            end
        end
    end
    local deck = {
        x = crossing.x, z = crossing.z,
        -- deck surface; part centre/marking offsets are added per part
        surface = math.max(crossing.rim,
            highwayTop + crossing.clearance + (Config.HIGHWAY_DECK_THICKNESS_STUDS or 1.6)),
    }
    overpassByName[key] = overpassByName[key] or {}
    table.insert(overpassByName[key], deck)
    table.insert(overpassDecks, deck)
end
-- The streets over I-95 also bridge the CSX, which runs at grade beside the
-- freeway (tools/fit_roads_to_buildings.py grounds it). Hold rail clearance
-- where an overpass street's pieces cross a rail bed near its structure.
local RAIL_CLEARANCE = 20     -- ~7 m (23 ft) over top of rail
do
    local railBeds = {}
    for _, part in ipairs(allRoads) do
        if part:GetAttribute("CW_Rail") == true and part.Name ~= "Rail" then
            table.insert(railBeds, part)
        end
    end
    local function cross2D(a, b, c, d)
        local r = Vector2.new(b.X - a.X, b.Z - a.Z)
        local s = Vector2.new(d.X - c.X, d.Z - c.Z)
        local den = r.X * s.Y - r.Y * s.X
        if math.abs(den) < 1e-6 then return nil end
        local q = Vector2.new(c.X - a.X, c.Z - a.Z)
        local t = (q.X * s.Y - q.Y * s.X) / den
        local u = (q.X * r.Y - q.Y * r.X) / den
        if t >= 0 and t <= 1 and u >= 0 and u <= 1 then return t, u end
        return nil
    end
    local railDecks = 0
    for key, decks in pairs(overpassByName) do
        task.wait()
        local base = decks[1]
        for _, part in ipairs(allRoads) do
            if normalizedRoadName(attr(part, "ChesterStreet")) == key
                and part:GetAttribute("CW_HighwayProfiled") ~= true
                and math.abs(part.Position.X - base.x) < 400 and math.abs(part.Position.Z - base.z) < 400 then
                local a, b = endpoints(part)
                for _, rail in ipairs(railBeds) do
                    if math.abs(rail.Position.X - part.Position.X) < 200
                        and math.abs(rail.Position.Z - part.Position.Z) < 200 then
                        local c, d = endpoints(rail)
                        local t, u = cross2D(a, b, c, d)
                        if t then
                            local top = lerp(c.Y, d.Y, u) + rail.Size.Y / 2
                            local p = a:Lerp(b, t)
                            table.insert(decks, { x = p.X, z = p.Z,
                                surface = top + RAIL_CLEARANCE + (Config.HIGHWAY_DECK_THICKNESS_STUDS or 1.6) })
                            railDecks += 1
                        end
                    end
                end
            end
        end
    end
    print(("[ChesterWorld RegistryOverpass] railCrossings=%d"):format(railDecks))
end
-- Approach anchors: where the overpass street meets a differently-named
-- ground street (Edgmont Ave / Edgmont at Providence) the county pieces of
-- the overpass street sat several studs below the junction, so the approach
-- dipped before climbing onto the deck. The junction's ground surface is held
-- as a zero-length plateau the approach eases away from at MAX_GRADE.
local ANCHOR_REACH = 60       -- ground street end this close (across a junction pad) joins the approach
local ANCHOR_ZONE = 260       -- only near the structure itself
do
    -- ground street ends near any structure, bucketed on a grid
    local CELL = ANCHOR_REACH
    local grid = {}
    local function cellKey(x, z) return math.floor(x / CELL) .. ":" .. math.floor(z / CELL) end
    for i, part in ipairs(allRoads) do
        if part:GetAttribute("CW_HighwayProfiled") ~= true
            and part:GetAttribute("CW_Rail") ~= true then
            local nearStructure = false
            for _, deck in ipairs(overpassDecks) do
                if math.abs(part.Position.X - deck.x) < ANCHOR_ZONE + 200
                    and math.abs(part.Position.Z - deck.z) < ANCHOR_ZONE + 200 then
                    nearStructure = true
                    break
                end
            end
            if nearStructure then
                -- (same-key streets count: "Edgmont" and "Edgmont Ave" share one)
                local a, b = endpoints(part)
                local key = normalizedRoadName(attr(part, "ChesterStreet"))
                for _, p in ipairs({ a, b }) do
                    local k = cellKey(p.X, p.Z)
                    grid[k] = grid[k] or {}
                    table.insert(grid[k], { p = p, top = p.Y + part.Size.Y / 2, part = part, key = key })
                end
            end
        end
        if i % 4000 == 0 then task.wait() end
    end
    local anchors = 0
    for key, decks in pairs(overpassByName) do
        local extra = {}
        for _, part in ipairs(allRoads) do
            if normalizedRoadName(attr(part, "ChesterStreet")) == key
                and part:GetAttribute("CW_HighwayProfiled") ~= true then
                local a, b = endpoints(part)
                for _, p in ipairs({ a, b }) do
                    local nearDeck = false
                    for _, deck in ipairs(decks) do
                        if hdist(p, Vector3.new(deck.x, 0, deck.z)) < ANCHOR_ZONE then nearDeck = true break end
                    end
                    if nearDeck then
                        local own = p.Y + part.Size.Y / 2 + 0.5
                        local best = nil
                        local cx, cz = math.floor(p.X / CELL), math.floor(p.Z / CELL)
                        for ix = cx - 1, cx + 1 do
                            for iz = cz - 1, cz + 1 do
                                for _, g in ipairs(grid[ix .. ":" .. iz] or {}) do
                                    -- (another overpass street's ends are not ground)
                                    if g.part ~= part and (g.key == key or not overpassByName[g.key])
                                        and g.top > own and (not best or g.top > best)
                                        and hdist(p, g.p) < ANCHOR_REACH then
                                        best = g.top
                                    end
                                end
                            end
                        end
                        if best then
                            table.insert(extra, { x = p.X, z = p.Z, surface = best, plateau = 0 })
                        end
                    end
                end
            end
        end
        for _, anchor in ipairs(extra) do
            table.insert(decks, anchor)
            anchors += 1
        end
        task.wait()
    end
    print(("[ChesterWorld RegistryOverpass] approachAnchors=%d"):format(anchors))
end
local function overpassSurface(decks, point)
    local best = -math.huge
    for _, deck in ipairs(decks) do
        local distance = hdist(point, Vector3.new(deck.x, 0, deck.z))
        best = math.max(best, deck.surface - math.max(0, distance - (deck.plateau or OVERPASS_PLATEAU)) * MAX_GRADE)
    end
    return best
end
local overpassParts, overpassLiftMax, overpassMarks = 0, 0, 0
local overpassLiftAt = ""
local overpassGroups = {}
if #overpassDecks > 0 then
    -- pass 1: required centre height at each endpoint (shared endpoints keyed
    -- by position so neighbouring pieces stay joined)
    local planned = {}
    local endpointNeed = {}
    local function endpointKey(part, point)
        return normalizedRoadName(attr(part, "ChesterStreet")) .. "|"
            .. math.floor(point.X + 0.5) .. ":" .. math.floor(point.Z + 0.5)
    end
    for _, part in ipairs(allRoads) do
        local decks = overpassByName[normalizedRoadName(attr(part, "ChesterStreet"))]
        -- only near the structure: a same-named street elsewhere in the city
        -- (Chestnut in Upland, 7000 studs from Chestnut St over I-95) is not
        -- part of this overpass
        local nearStructure = false
        if decks then
            for _, deck in ipairs(decks) do
                if math.abs(part.Position.X - deck.x) < 600 and math.abs(part.Position.Z - deck.z) < 600 then
                    nearStructure = true
                    break
                end
            end
        end
        if nearStructure and part:GetAttribute("CW_HighwayProfiled") ~= true then
            local a, b = endpoints(part)
            local half = part.Size.Y / 2
            local ya = math.max(a.Y, overpassSurface(decks, a) + half)
            local yb = math.max(b.Y, overpassSurface(decks, b) + half)
            -- A piece spanning a crossing is straight between its endpoints:
            -- raise both ends until its chord clears the deck there too.
            local inZone = false
            local d = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
            local d2 = d:Dot(d)
            for _, deck in ipairs(decks) do
                local t = d2 > 0.01 and math.clamp(Vector3.new(deck.x - a.X, 0, deck.z - a.Z):Dot(d) / d2, 0, 1) or 0
                local p = a:Lerp(b, t)
                if hdist(p, Vector3.new(deck.x, 0, deck.z)) <= OVERPASS_PLATEAU + 40 then
                    inZone = true
                    local short = overpassSurface(decks, p) + half - lerp(ya, yb, t)
                    if short > 0 then
                        ya += short
                        yb += short
                    end
                end
            end
            if inZone then
                part:SetAttribute("CW_RegistryOverpassDeck", true)
            end
            table.insert(planned, { part = part, a = a, b = b, half = half })
            for _, item in ipairs({ { a, ya }, { b, yb } }) do
                local key = endpointKey(part, item[1])
                endpointNeed[key] = math.max(endpointNeed[key] or -math.huge, item[2])
            end
        end
    end
    -- pass 2: apply
    local raisedByGroup = {}
    for _, plan in ipairs(planned) do
        local a, b, part = plan.a, plan.b, plan.part
        local ya = math.max(a.Y, endpointNeed[endpointKey(part, a)])
        local yb = math.max(b.Y, endpointNeed[endpointKey(part, b)])
        local lift = math.max(ya - a.Y, yb - b.Y)
        if lift > 0.05 and setEndpoints(part, Vector3.new(a.X, ya, a.Z), Vector3.new(b.X, yb, b.Z)) then
            part:SetAttribute("CW_RegistryOverpassDeck", true)
            part:SetAttribute("CW_ElevationOwner", "RoadTerrainConformer:RegistryOverpass")
            local gradeGroup = attr(part, "CW_GradeGroup")
            raisedByGroup[gradeGroup] = raisedByGroup[gradeGroup] or {}
            table.insert(raisedByGroup[gradeGroup], part)
            overpassParts += 1
            if lift > overpassLiftMax then
                overpassLiftMax = lift
                overpassLiftAt = ("%s at (%.0f, %.0f)"):format(attr(part, "ChesterStreet"), part.Position.X, part.Position.Z)
            end
        end
    end
    -- markings follow the raised piece they lie on
    for _, marking in ipairs(allMarks) do
        local parts = raisedByGroup[attr(marking, "CW_GradeGroup")]
        if parts then
            local function markY(point)
                local best, bestDistance = nil, math.huge
                for _, road in ipairs(parts) do
                    local x, y = endpoints(road)
                    local d = Vector3.new(y.X - x.X, 0, y.Z - x.Z)
                    local d2 = d:Dot(d)
                    if d2 > 0.01 then
                        local t = math.clamp(Vector3.new(point.X - x.X, 0, point.Z - x.Z):Dot(d) / d2, 0, 1)
                        local nearest = x:Lerp(y, t)
                        local distance = hdist(nearest, point)
                        if distance < bestDistance then
                            bestDistance, best = distance, nearest.Y
                        end
                    end
                end
                return bestDistance < 15 and best and best + (MARK_OFFSET - ROAD_OFFSET) or nil
            end
            local a, b = endpoints(marking)
            local ya, yb = markY(a), markY(b)
            if ya and yb and (ya > a.Y + 0.05 or yb > b.Y + 0.05)
                and setEndpoints(marking, Vector3.new(a.X, math.max(a.Y, ya), a.Z), Vector3.new(b.X, math.max(b.Y, yb), b.Z)) then
                overpassMarks += 1
            end
        end
    end
    -- Streets that join a raised overpass street at its deck end (Bethel Rd
    -- at the north end of the Engle St bridge: a 9.5-stud step, audit
    -- 2026-11-06) are lifted to meet it and eased back down along their own
    -- pieces at MAX_GRADE. Only raises; never touches freeway or rail.
    do
        local GRID = 8
        local endGrid = {}
        local raisedSet = {}
        for _, parts in pairs(raisedByGroup) do
            for _, road in ipairs(parts) do raisedSet[road] = true end
        end
        local function gk(x, z) return math.floor(x / GRID) .. ":" .. math.floor(z / GRID) end
        for _, road in ipairs(allRoads) do
            if not raisedSet[road] and road:GetAttribute("CW_HighwayProfiled") ~= true
                and road:GetAttribute("CW_Rail") ~= true and road.Name ~= "Rail" then
                local a, b = endpoints(road)
                for i, p in ipairs({ a, b }) do
                    local k = gk(p.X, p.Z)
                    endGrid[k] = endGrid[k] or {}
                    table.insert(endGrid[k], { road = road, index = i })
                end
            end
        end
        local function near(p, radius)
            local out = {}
            local gx, gz = math.floor(p.X / GRID), math.floor(p.Z / GRID)
            for ix = gx - 1, gx + 1 do
                for iz = gz - 1, gz + 1 do
                    for _, e in ipairs(endGrid[ix .. ":" .. iz] or {}) do
                        local a, b = endpoints(e.road)
                        local q = e.index == 1 and a or b
                        if hdist(p, q) <= radius then table.insert(out, e) end
                    end
                end
            end
            return out
        end
        local followed = 0
        local queue = {}
        for road in pairs(raisedSet) do
            local a, b = endpoints(road)
            for _, p in ipairs({ a, b }) do
                for _, e in ipairs(near(p, 4)) do
                    -- a street sharing the vertex but passing UNDER sits at
                    -- least a clearance below: only small steps are joins
                    local ea, eb = endpoints(e.road)
                    local q = e.index == 1 and ea or eb
                    if p.Y - q.Y < 12 then
                        table.insert(queue, { road = e.road, index = e.index, y = p.Y })
                    end
                end
            end
        end
        local guard = 0
        while #queue > 0 and guard < 4000 do
            guard += 1
            local item = table.remove(queue, 1)
            local a, b = endpoints(item.road)
            local here = item.index == 1 and a or b
            local there = item.index == 1 and b or a
            if item.y > here.Y + 0.5 then
                local need = item.y - MAX_GRADE * hdist(here, there)
                local newHere = Vector3.new(here.X, item.y, here.Z)
                local newThere = Vector3.new(there.X, math.max(there.Y, need), there.Z)
                local na, nb = newHere, newThere
                if item.index == 2 then na, nb = newThere, newHere end
                if setEndpoints(item.road, na, nb) then
                    item.road:SetAttribute("CW_ElevationOwner", "RoadTerrainConformer:OverpassFollower")
                    followed += 1
                    if newThere.Y > there.Y + 0.5 then
                        -- keep easing down the next piece of that street
                        for _, e in ipairs(near(there, 3)) do
                            if e.road ~= item.road then
                                table.insert(queue, { road = e.road, index = e.index, y = newThere.Y })
                            end
                        end
                    end
                end
            end
        end
        print(("[ChesterWorld RegistryOverpass] junctionFollowers=%d"):format(followed))
    end
    -- sidewalks beside a raised piece were left down in the highway cut
    -- (Edgmont Ave / Providence under the deck): lift them alongside it, or
    -- drop the ones that would hang off the deck's open side
    local raisedByKey = {}
    for _, parts in pairs(raisedByGroup) do
        for _, road in ipairs(parts) do
            local key = normalizedRoadName(attr(road, "ChesterStreet"))
            raisedByKey[key] = raisedByKey[key] or {}
            table.insert(raisedByKey[key], road)
        end
    end
    local walksLifted, walksDropped = 0, 0
    local road_half_reach = 30   -- widest street half-width + sidewalk, studs
    for _, walk in ipairs(collectParts("Sidewalks")) do
        local parts = raisedByKey[normalizedRoadName(attr(walk, "ChesterStreet"))]
        if parts then
            local function roadY(point)
                local best, bestDistance = nil, math.huge
                for _, road in ipairs(parts) do
                    local x, y = endpoints(road)
                    local d = Vector3.new(y.X - x.X, 0, y.Z - x.Z)
                    local d2 = d:Dot(d)
                    if d2 > 0.01 then
                        local t = math.clamp(Vector3.new(point.X - x.X, 0, point.Z - x.Z):Dot(d) / d2, 0, 1)
                        local nearest = x:Lerp(y, t)
                        local distance = hdist(nearest, point)
                        if distance < bestDistance then
                            bestDistance, best = distance, nearest.Y
                        end
                    end
                end
                return bestDistance < road_half_reach and best or nil
            end
            local a, b = endpoints(walk)
            local ya, yb = roadY(a), roadY(b)
            local mid = roadY(walk.Position)
            if mid and mid > walk.Position.Y + 1.5 then
                if ya and yb then
                    if setEndpoints(walk, Vector3.new(a.X, math.max(a.Y, ya + 0.4), a.Z),
                        Vector3.new(b.X, math.max(b.Y, yb + 0.4), b.Z)) then
                        walk:SetAttribute("CW_ElevationOwner", "RoadTerrainConformer:RegistryOverpassWalk")
                        walksLifted += 1
                    end
                else
                    walk:Destroy()
                    walksDropped += 1
                end
            end
        end
    end
    print(("[ChesterWorld RegistryOverpass] sidewalksLifted=%d sidewalksDropped=%d"):format(walksLifted, walksDropped))
end
print(("[ChesterWorld RegistryOverpass] crossings=%d parts=%d marks=%d maxLift=%.1f %s")
    :format(#overpassDecks, overpassParts, overpassMarks, overpassLiftMax, overpassLiftAt))

-- County bridge tags often cover a structure's approach embankments (Bullens
-- Ln from Governors Rd, the Highland and Upland approaches). The deck line
-- between a component's ends then runs below that fill. Never let a bridge
-- piece's surface sit below the terrain; a piece left resting on the ground
-- is an embankment approach, not a deck over terrain.
local DECK_DEPTH = Config.HIGHWAY_DECK_THICKNESS_STUDS or 1.6
local embankmentPlans, embankmentNeed = {}, {}
-- keyed by street too: a different road's piece can end at the same point
local function embankmentKey(part, point)
    return normalizedRoadName(attr(part, "ChesterStreet")) .. "|"
        .. math.floor(point.X + 0.5) .. ":" .. math.floor(point.Z + 0.5)
end
for _, item in ipairs(bridgeComponents) do
    for _, part in ipairs(item.parts) do
        if part.Parent and part:GetAttribute("CW_HighwayProfiled") ~= true
            and part:GetAttribute("CW_LowerRoadUnderStructure") == nil then
            local a, b = endpoints(part)
            local ga, gb = terrainY(a.X, a.Z), terrainY(b.X, b.Z)
            local ya = math.max(a.Y, ga and ga + ROAD_OFFSET or -math.huge)
            local yb = math.max(b.Y, gb and gb + ROAD_OFFSET or -math.huge)
            for _, t in ipairs({0.25, 0.5, 0.75}) do
                local p = a:Lerp(b, t)
                local g = terrainY(p.X, p.Z)
                local short = g and (g + ROAD_OFFSET - lerp(ya, yb, t)) or 0
                if short > 0 then
                    ya += short
                    yb += short
                end
            end
            table.insert(embankmentPlans, {part = part, a = a, b = b})
            for _, pair in ipairs({{a, ya}, {b, yb}}) do
                local key = embankmentKey(part, pair[1])
                embankmentNeed[key] = math.max(embankmentNeed[key] or -math.huge, pair[2])
            end
        end
    end
end
local embankmentRaised, embankmentResting, embankmentLiftMax = 0, 0, 0
local embankmentLiftAt = ""
local embankmentRaisedGroups = {}
for _, plan in ipairs(embankmentPlans) do
    local a, b, part = plan.a, plan.b, plan.part
    local ya = math.max(a.Y, embankmentNeed[embankmentKey(part, a)])
    local yb = math.max(b.Y, embankmentNeed[embankmentKey(part, b)])
    local lift = math.max(ya - a.Y, yb - b.Y)
    if lift > 0.05 and setEndpoints(part, Vector3.new(a.X, ya, a.Z), Vector3.new(b.X, yb, b.Z)) then
        embankmentRaised += 1
        if lift > embankmentLiftMax then
            embankmentLiftMax = lift
            embankmentLiftAt = ("%s %s at (%.0f, %.0f)"):format(attr(part, "ChesterStreet"),
                attr(part, "CW_GradeGroup"), part.Position.X, part.Position.Z)
        end
        embankmentRaisedGroups[attr(part, "CW_GradeGroup")] = true
        a, b = Vector3.new(a.X, ya, a.Z), Vector3.new(b.X, yb, b.Z)
    end
    for _, t in ipairs({0.2, 0.4, 0.5, 0.6, 0.8}) do
        local p = a:Lerp(b, t)
        local g = terrainY(p.X, p.Z)
        if g and p.Y - part.Size.Y / 2 - DECK_DEPTH < g + 0.25 then
            part:SetAttribute("CW_OnEmbankment", true)
            embankmentResting += 1
            break
        end
    end
end
-- centre-line markings follow the raised pieces
if embankmentRaised > 0 then
    local raisedParts = {}
    for _, plan in ipairs(embankmentPlans) do
        local gradeGroup = attr(plan.part, "CW_GradeGroup")
        if embankmentRaisedGroups[gradeGroup] then
            raisedParts[gradeGroup] = raisedParts[gradeGroup] or {}
            table.insert(raisedParts[gradeGroup], plan.part)
        end
    end
    for _, marking in ipairs(allMarks) do
        local parts = raisedParts[attr(marking, "CW_GradeGroup")]
        if parts then
            local function markY(point)
                local best, bestDistance = nil, math.huge
                for _, road in ipairs(parts) do
                    local x, y = endpoints(road)
                    local d = Vector3.new(y.X - x.X, 0, y.Z - x.Z)
                    local d2 = d:Dot(d)
                    if d2 > 0.01 then
                        local t = math.clamp(Vector3.new(point.X - x.X, 0, point.Z - x.Z):Dot(d) / d2, 0, 1)
                        local nearest = x:Lerp(y, t)
                        local distance = hdist(nearest, point)
                        if distance < bestDistance then
                            bestDistance, best = distance, nearest.Y
                        end
                    end
                end
                return bestDistance < 15 and best and best + (MARK_OFFSET - ROAD_OFFSET) or nil
            end
            local a, b = endpoints(marking)
            local ya, yb = markY(a), markY(b)
            if ya and yb and (ya > a.Y + 0.05 or yb > b.Y + 0.05) then
                setEndpoints(marking, Vector3.new(a.X, math.max(a.Y, ya), a.Z), Vector3.new(b.X, math.max(b.Y, yb), b.Z))
            end
        end
    end
end
print(("[ChesterWorld BridgeEmbankment] raised=%d resting=%d maxLift=%.1f %s")
    :format(embankmentRaised, embankmentResting, embankmentLiftMax, embankmentLiftAt))

local conformed = #atGrade - stats.rampParts + stats.rampParts
    + stats.bridgeConformed
Workspace:SetAttribute("CW_RoadConformTotal", #allRoads)
Workspace:SetAttribute("CW_RoadConformedCount", conformed)
Workspace:SetAttribute("CW_RoadConformComplete", true)

print(("[ChesterWorld RoadTerrainConformer] highwayProfiledPartsLeftToHighwayProfile=%d"):format(highwayProfiledParts))
-- V-dips between lifted pieces: where two RoadTerrainConformer-owned pieces
-- of a street meet at a joint lower than both their far ends (Upland St,
-- Bethel / Engle: 1-stud dips on 4-stud pieces, 15-25 % kinks), lift the
-- joint onto the line between the far ends. Raise only, at most 2 studs, so
-- no clearance can shrink.
do
    local joints = {}
    local function jk(p) return math.floor(p.X * 2 + 0.5) .. ":" .. math.floor(p.Z * 2 + 0.5) end
    for _, part in ipairs(allRoads) do
        local owner = attr(part, "CW_ElevationOwner")
        if string.sub(owner, 1, 20) == "RoadTerrainConformer" and part.Parent then
            local a, b = endpoints(part)
            for i, p in ipairs({ a, b }) do
                local k = jk(p)
                joints[k] = joints[k] or {}
                table.insert(joints[k], { part = part, index = i })
            end
        end
    end
    local smoothed = 0
    for _, list in pairs(joints) do
        if #list == 2 then
            local e1, e2 = list[1], list[2]
            local a1, b1 = endpoints(e1.part)
            local a2, b2 = endpoints(e2.part)
            local here1, far1 = (e1.index == 1 and a1 or b1), (e1.index == 1 and b1 or a1)
            local here2, far2 = (e2.index == 1 and a2 or b2), (e2.index == 1 and b2 or a2)
            local here = math.max(here1.Y, here2.Y)
            local d1, d2 = hdist(here1, far1), hdist(here2, far2)
            if d1 > 0.1 and d2 > 0.1 and far1.Y > here + 0.2 and far2.Y > here + 0.2 then
                local line = far1.Y + (far2.Y - far1.Y) * d1 / (d1 + d2)
                local target = math.min(line, here + 2)
                if target > here + 0.1 then
                    for _, e in ipairs({ { e1, a1, b1 }, { e2, a2, b2 } }) do
                        local entry, a, b = e[1], e[2], e[3]
                        if entry.index == 1 then
                            setEndpoints(entry.part, Vector3.new(a.X, target, a.Z), b)
                        else
                            setEndpoints(entry.part, a, Vector3.new(b.X, target, b.Z))
                        end
                    end
                    smoothed += 1
                end
            end
        end
    end
    print(("[ChesterWorld RoadTerrainConformer] vDipsSmoothed=%d"):format(smoothed))
end
print(("[ChesterWorld RoadTerrainConformer] waterCrossings=%d bankRaisedEnds=%d notchRims=%d"):format(stats.waterCrossings or 0, stats.bankRaised or 0, stats.notchRims or 0))
print(("[ChesterWorld RoadTerrainConformer] final=%d groundPreserved=%d bridgeConformed=%d conformed=%d noTerrain=%d failed=%d bridgeGroups=%d sourceBridgeGroups=%d bridgeComponents=%d bridgeParts=%d tunnelParts=%d rampParts=%d rampGroups=%d marked=%d crossingChecks=%d clearanceWarnings=%d terrainClearanceWarnings=%d terrainEndpointEstimates=%d steepGroups=%d gradeLimitedGroups=%d gradeLimitedParts=%d actualSteepParts=%d baselineSteepGroups=%d smoothDecks=true")
    :format(#allRoads, #atGrade-stats.rampParts, stats.bridgeConformed,
    conformed, stats.bridgeNoTerrain, stats.failed, stats.groups,
    sourceBridgeGroups, stats.components, stats.bridgeParts, stats.tunnelParts,
    stats.rampParts, stats.rampGroups, stats.marked, stats.crossingChecks,
    stats.clearanceWarnings, stats.terrainClearanceWarnings,
    stats.terrainEndpointEstimates,stats.steepGroups,
    stats.insufficientApproachLength,stats.gradeLimitedParts,
    stats.actualSteepParts,stats.baselineSteepGroups))
if stats.clearanceWarnings > 0 then
    warn(("[ChesterWorld Highway] %d bridge crossings need additional surveyed vertical data / ramp length to guarantee clearance."):format(stats.clearanceWarnings))
end
