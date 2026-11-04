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

for _, part in ipairs(allRoads) do
    local level = tonumber(part:GetAttribute("CW_GradeLevel")) or 0
    local isBridge = part:GetAttribute("CW_Bridge") == true or level > 0
    if isBridge then
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
        if highwayRoad(part) and level == 0 then
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
    if t > 0.02 and t < 0.98 and u > 0.02 and u < 0.98 then
        return t, u
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
                    local matchName = attr(part, "ChesterStreet") == bridgeName
                    local score = dot + (matchName and 0.5 or 0)
                    if dot > 0.24 and score > bestScore then
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
local stats = {
    groups = 0, components = 0, bridgeParts = 0, bridgeConformed = 0,
    bridgeNoTerrain = 0, failed = 0, tunnelParts = tunnelParts,
    rampParts = 0, rampGroups = 0, marked = 0,
    crossingChecks = 0, clearanceWarnings = 0, steepGroups = 0,
    terrainClearanceWarnings = 0,
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
    local startGround = terrainY(lowPoint.X, lowPoint.Z)
    local endGround = terrainY(highPoint.X, highPoint.Z)
    if not startGround or not endGround then
        stats.bridgeNoTerrain += #parts
        return nil
    end

    local span = math.max(high - low, 0.1)
    local bridgeName = attr(parts[1], "ChesterStreet")
    local rampStart, startLength = {}, 0
    local rampEnd, endLength = {}, 0
    if highwayRoad(parts[1]) then
        rampStart, startLength = findApproachChain(lowPoint, -direction, bridgeName)
        rampEnd, endLength = findApproachChain(highPoint, direction, bridgeName)
    end

    -- A smoothstep transition has a maximum derivative of 1.5.
    -- Limit bridge terminal lift to what an actual adjacent ramp can absorb.
    local startLift = math.min(nominalClearance, startLength * MAX_GRADE / 1.5)
    local endLift = math.min(nominalClearance, endLength * MAX_GRADE / 1.5)
    local targetLift = nominalClearance

    -- Ground streets are left untouched; raise a deck enough to clear them.
    local crossings = {}
    for _, rec in ipairs(records) do
        for _, lower in ipairs(underRoadsForSegment(rec.a, rec.b)) do
            local x, y = endpoints(lower)
            local t, u = crossingT(rec.a, rec.b, x, y)
            if t then
                local position = rec.a:Lerp(rec.b, t)
                local station = (position.X * direction.X
                    + position.Z * direction.Z - low) / span
                local groundTop = lerp(x.Y, y.Y, u) + lower.Size.Y / 2
                local baseline = lerp(startGround, endGround, station)
                    + ROAD_OFFSET + rec.part.Size.Y / 2
                local needed = groundTop + CLEARANCE
                    + (Config.HIGHWAY_DECK_THICKNESS_STUDS or 1.6) - baseline
                targetLift = math.max(targetLift, needed)
                table.insert(crossings, {t = station, needed = needed})
            end
        end
    end
    -- The previous solver checked the HIGH point only, yet some decks were
    -- still embedded on their sloping quarters. Record actual requirements
    -- at each bridge station and solve for the lifted envelope at THAT t.
    -- Ends are abutments and may be buried in the bank; we sample a little
    -- inside the span to avoid incorrectly requiring an elevated terminal.
    local terrainRequirements = {}
    local deckDepth = Config.HIGHWAY_DECK_THICKNESS_STUDS or 1.6
    for _, rec in ipairs(records) do
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
                        t=t,needed=gy+1.0-baseline,
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
            targetLift = math.clamp(math.max(targetLift, requestedPeak),
                nominalClearance, math.max(MAX_LIFT, nominalClearance))
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

    -- A bridge's tagged source span can be short. Report unsafe profiles rather
    -- than silently pretending the designed 10% ramp grade was achieved.
    local maxLeftGrade = 1.5 * math.abs(targetLift - startLift) / (span * fraction)
    local maxRightGrade = 1.5 * math.abs(targetLift - endLift) / (span * fraction)
    if math.max(maxLeftGrade, maxRightGrade) > 0.20 then
        stats.steepGroups += 1
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

    local profile = {
        group = groupKey, parts = parts,
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

for key, group in pairs(bridges) do
    stats.groups += 1
    stats.bridgeParts += #group
    for _, component in ipairs(components(group)) do
        stats.components += 1
        conformComponent(component, key)
        task.wait()
    end
end

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
    local marks = marksByGroup[profile.group] or {}
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

local conformed = #atGrade - stats.rampParts + stats.rampParts
    + stats.bridgeConformed
Workspace:SetAttribute("CW_RoadConformTotal", #allRoads)
Workspace:SetAttribute("CW_RoadConformedCount", conformed)
Workspace:SetAttribute("CW_RoadConformComplete", true)

print(("[ChesterWorld RoadTerrainConformer] final=%d groundPreserved=%d bridgeConformed=%d conformed=%d noTerrain=%d failed=%d bridgeGroups=%d bridgeComponents=%d bridgeParts=%d tunnelParts=%d rampParts=%d rampGroups=%d marked=%d crossingChecks=%d clearanceWarnings=%d terrainClearanceWarnings=%d steepGroups=%d smoothDecks=true")
    :format(#allRoads, #atGrade-stats.rampParts, stats.bridgeConformed,
    conformed, stats.bridgeNoTerrain, stats.failed, stats.groups,
    stats.components, stats.bridgeParts, stats.tunnelParts,
    stats.rampParts, stats.rampGroups, stats.marked, stats.crossingChecks,
    stats.clearanceWarnings, stats.terrainClearanceWarnings,stats.steepGroups))
if stats.clearanceWarnings > 0 then
    warn(("[ChesterWorld Highway] %d bridge crossings need additional surveyed vertical data / ramp length to guarantee clearance."):format(stats.clearanceWarnings))
end
