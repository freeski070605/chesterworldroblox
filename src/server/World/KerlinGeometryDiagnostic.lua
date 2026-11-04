-- Read-only Studio probe. Run from the SERVER Command Bar after a full Play load:
-- require(game.ServerScriptService.Server.World.KerlinGeometryDiagnostic).Run()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Placement = require(Shared:WaitForChild("WorldPlacement"))
local TileModule = Shared:WaitForChild("WorldData"):WaitForChild("Tiles"):WaitForChild("tile_r07_c07")
local Diagnostic = {}

local TILE_ID = "tile_r07_c07"
local IDS = { 424, 425, 423, 426, 2758, 27163, 20771, 20770 }
local EXPECTED = {
    north = { x = 7019.645, z = 7193.492, upper = { 424, 425 }, lower = { 2758, 27163 } },
    south = { x = 7011.454, z = 7208.863, upper = { 423, 426 }, lower = { 20771, 20770 } },
}
local RAY_TOP = 5000
local RAY_DEPTH = 10000
local SAMPLE_STEP = 10
local GAP_TOLERANCE = 1.0
local SLOPE_LIMIT = 0.40

local function out(section, status, message)
    print(("KERLIN | %s | %s | %s"):format(section, status, message))
end

local function number(value)
    return value and ("%.3f"):format(value) or "MISSING"
end

local function point(x, z)
    return ("X=%.3f Z=%.3f"):format(x, z)
end

local function studs(x, z)
    return (x - Placement.CENTER_X_M) * Placement.STUDS_PER_METER,
        -(z - Placement.CENTER_Z_M) * Placement.STUDS_PER_METER
end

local function params(instances)
    local p = RaycastParams.new()
    p.FilterType = Enum.RaycastFilterType.Include
    p.FilterDescendantsInstances = instances
    p.IgnoreWater = false
    return p
end

local function vertical(instance, x, z, upward)
    if not instance then return nil end
    local origin = Vector3.new(x, upward and -RAY_TOP or RAY_TOP, z)
    local direction = Vector3.new(0, upward and RAY_DEPTH or -RAY_DEPTH, 0)
    return Workspace:Raycast(origin, direction, params({ instance }))
end

local function surface(parts, x, z, upward)
    local best
    for _, part in ipairs(parts) do
        if part.CanQuery then
            local hit = vertical(part, x, z, upward)
            if hit and (not best or (upward and hit.Position.Y < best.y)
                or (not upward and hit.Position.Y > best.y)) then
                best = { y = hit.Position.Y, part = part, material = hit.Material }
            end
        end
    end
    return best
end

local function deckUnderside(part, x, z)
    local hit = vertical(part, x, z, true)
    if hit then return { y = hit.Position.Y, method = "RAYCAST" } end
    -- HighwayInfrastructure makes decorative decks CanQuery=false. Read their
    -- actual bottom face from CFrame/Size without changing CanQuery.
    if not part:IsA("Part") then return nil end
    local normal = part.CFrame.UpVector
    if math.abs(normal.Y) < 0.01 then return nil end
    local face = part.Position - normal * (part.Size.Y / 2)
    local y = face.Y - (normal.X * (x - face.X) + normal.Z * (z - face.Z)) / normal.Y
    local localPoint = part.CFrame:PointToObjectSpace(Vector3.new(x, y, z))
    if math.abs(localPoint.X) <= part.Size.X / 2 + 0.01
        and math.abs(localPoint.Z) <= part.Size.Z / 2 + 0.01 then
        return { y = y, method = "PART_FACE_GEOMETRY" }
    end
    return nil
end

local function roadId(road)
    return tonumber(string.match(tostring(road.grade_group or ""), "^county:(%d+):"))
end

local function segmentLength(road)
    local x1, z1 = studs(road.x1, road.z1)
    local x2, z2 = studs(road.x2, road.z2)
    return math.sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2)
end

local function sourcePoint(road, t)
    return studs(road.x1 + (road.x2 - road.x1) * t,
        road.z1 + (road.z2 - road.z1) * t)
end

local function attributes(part)
    return ("path=%s group=%s street=%s owner=%s bridge=%s grade=%s collide=%s query=%s size=%s")
        :format(part:GetFullName(), tostring(part:GetAttribute("CW_GradeGroup")),
            tostring(part:GetAttribute("ChesterStreet")),
            tostring(part:GetAttribute("CW_ElevationOwner")),
            tostring(part:GetAttribute("CW_Bridge")),
            tostring(part:GetAttribute("CW_GradeLevel")), tostring(part.CanCollide),
            tostring(part.CanQuery), tostring(part.Size))
end

local function endpointAt(road, x, z)
    local x1, z1 = sourcePoint(road, 0)
    local x2, z2 = sourcePoint(road, 1)
    if math.sqrt((x1 - x) ^ 2 + (z1 - z) ^ 2) < 0.01 then return 1 end
    if math.sqrt((x2 - x) ^ 2 + (z2 - z) ^ 2) < 0.01 then return 2 end
    return nil
end

local function nearestRoadEnd(parts, x, z)
    local best
    for _, part in ipairs(parts) do
        local delta = part.CFrame.LookVector * (part.Size.Z / 2)
        for _, endpoint in ipairs({ part.Position - delta, part.Position + delta }) do
            local distance = math.sqrt((endpoint.X - x) ^ 2 + (endpoint.Z - z) ^ 2)
            if not best or distance < best.distance then
                best = { position = endpoint, distance = distance, part = part }
            end
        end
    end
    return best
end

local function partIntervals(road, parts)
    local ax, az = sourcePoint(road, 0)
    local bx, bz = sourcePoint(road, 1)
    local dx, dz = bx - ax, bz - az
    local length = math.sqrt(dx * dx + dz * dz)
    if length < 0.01 then return {} end
    local ux, uz = dx / length, dz / length
    local intervals = {}
    for _, part in ipairs(parts) do
        local shift = part.CFrame.LookVector * (part.Size.Z / 2)
        local p, q = part.Position - shift, part.Position + shift
        local center = part.Position
        local cross = math.abs((center.X - ax) * uz - (center.Z - az) * ux)
        local s = (p.X - ax) * ux + (p.Z - az) * uz
        local e = (q.X - ax) * ux + (q.Z - az) * uz
        local lo, hi = math.min(s, e), math.max(s, e)
        if cross < 2.0 and hi > 0 and lo < length then
            table.insert(intervals, { lo = math.max(lo, 0), hi = math.min(hi, length), part = part })
        end
    end
    table.sort(intervals, function(a, b) return a.lo < b.lo end)
    return intervals
end

local function tileReady()
    if not game:GetService("RunService"):IsStudio() then
        out("READY", "FAIL", "Studio only")
        return nil
    end
    if not game:GetService("RunService"):IsServer() then
        out("READY", "FAIL", "run in the Server Command Bar during Play")
        return nil
    end
    if Workspace:GetAttribute("CW_QuickStreetPreview") == true then
        out("READY", "FAIL", "CW_QuickStreetPreview=true; restart with a full tile load")
        return nil
    end
    if Workspace:GetAttribute("CW_BootstrapComplete") ~= true
        or Workspace:GetAttribute("CW_RoadConformComplete") ~= true
        or Workspace:GetAttribute("CW_HighwayFinishComplete") ~= true then
        out("READY", "FAIL", "wait for CW_BootstrapComplete, CW_RoadConformComplete, CW_HighwayFinishComplete")
        return nil
    end
    local world = Workspace:FindFirstChild("ChesterWorld")
    local tile = world and world:FindFirstChild(TILE_ID)
    if not tile or not tile:FindFirstChild("Roads") or not tile:FindFirstChild("Intersections") then
        out("READY", "FAIL", "fully loaded workspace.ChesterWorld." .. TILE_ID .. " missing")
        return nil
    end
    return tile
end

function Diagnostic.Run()
    out("BEGIN", "PASS", "read-only Studio measurement; units=studs; tile=" .. TILE_ID)
    local tile = tileReady()
    if not tile then return end
    local data = require(TileModule)
    local gradeRecord
    for _, record in ipairs(data.grade_separations or {}) do
        if record.id == "KERLIN_I95" then gradeRecord = record end
    end
    local function containsAll(actual, expected)
        local found = {}
        for _, value in ipairs(actual or {}) do found[value] = true end
        for _, value in ipairs(expected) do
            if not found[value] then return false end
        end
        return true
    end
    if not gradeRecord or gradeRecord.vertical_status ~= "unmeasured"
        or not containsAll(gradeRecord.upper_source_ids,
            { "county:423", "county:424", "county:425", "county:426" })
        or not containsAll(gradeRecord.lower_source_ids,
            { "county:2758", "county:27163", "county:20771", "county:20770" }) then
        out("SOURCE_ROLE", "FAIL", "KERLIN_I95 unmeasured grade-separation record missing or changed")
        return
    end
    out("SOURCE_ROLE", "PASS", "KERLIN_I95 upper=I95 lower=Kerlin verticalStatus=unmeasured")
    local source = {}
    local runtime = {}
    for _, id in ipairs(IDS) do
        source[id] = {}
        runtime[id] = {}
    end
    for _, road in ipairs(data.roads or {}) do
        local id = roadId(road)
        if source[id] then table.insert(source[id], road) end
    end
    for _, item in ipairs(tile.Roads:GetDescendants()) do
        if item:IsA("BasePart") then
            local id = tonumber(string.match(tostring(item:GetAttribute("CW_GradeGroup") or ""), "^county:(%d+):"))
            if runtime[id] then table.insert(runtime[id], item) end
        end
    end
    out("READY", "PASS", ("tile=%s bootstrap=%s conform=%s finish=%s scale=%.3f center=(%.3f,%.3f)")
        :format(tile:GetFullName(), tostring(Workspace:GetAttribute("CW_BootstrapComplete")),
            tostring(Workspace:GetAttribute("CW_RoadConformComplete")),
            tostring(Workspace:GetAttribute("CW_HighwayFinishComplete")),
            Placement.STUDS_PER_METER, Placement.CENTER_X_M, Placement.CENTER_Z_M))
    local tileStatus = true
    for _, id in ipairs(IDS) do
        local segments, parts = source[id], runtime[id]
        local status = #segments > 0 and #parts > 0 and "PASS" or "FAIL"
        if status == "FAIL" then tileStatus = false end
        out("IDENTITY", status, ("id=%d sourceSegments=%d roadParts=%d"):format(id, #segments, #parts))
        for _, part in ipairs(parts) do out("PART", "MEASURED", attributes(part)) end
    end
    if not tileStatus then
        out("END", "UNKNOWN", "missing source/runtime road identity; measurements incomplete")
        return
    end

    local terrain = Workspace.Terrain
    local function sample(label, id, x, z)
        local road = surface(runtime[id], x, z, false)
        local collision = {}
        for _, part in ipairs(runtime[id]) do
            if part.CanCollide then table.insert(collision, part) end
        end
        local collisionTop = surface(collision, x, z, false)
        local collisionBottom = surface(collision, x, z, true)
        local ground = vertical(terrain, x, z, false)
        local terrainY = ground and ground.Position.Y or nil
        local status = road and collisionTop and collisionBottom and terrainY and "PASS" or "UNKNOWN"
        local intrusion = road and terrainY and terrainY >= road.y - 0.10
        if intrusion then status = "FAIL" end
        out("SAMPLE", status, ("label=%s id=%d %s roadTop=%s collisionTop=%s collisionBottom=%s terrain=%s terrainPenetration=%s roadPath=%s collisionPath=%s")
            :format(label, id, point(x, z), number(road and road.y),
                number(collisionTop and collisionTop.y), number(collisionBottom and collisionBottom.y),
                number(terrainY), intrusion == nil and "UNKNOWN" or tostring(intrusion),
                road and road.part:GetFullName() or "MISSING",
                collisionTop and collisionTop.part:GetFullName() or "MISSING"))
        return { road = road, top = collisionTop, bottom = collisionBottom, terrain = terrainY }
    end

    local sourceGraphGood = true
    for label, joint in pairs(EXPECTED) do
        local x, z = studs(joint.x, joint.z)
        local sourceUpper, sourceLower = {}, {}
        for _, id in ipairs(joint.upper) do
            local found = false
            for _, road in ipairs(source[id]) do
                local endpoint = endpointAt(road, x, z)
                if endpoint and not road["node" .. endpoint .. "_connection_group"] then
                    found = true
                end
            end
            sourceUpper[id] = found
        end
        for _, id in ipairs(joint.lower) do
            local found = false
            for _, road in ipairs(source[id]) do
                local endpoint = endpointAt(road, x, z)
                if endpoint then
                    found = road["node" .. endpoint .. "_connection_group"] == "KERLIN_I95:lower"
                end
            end
            sourceLower[id] = found
        end
        local graphOK = true
        for _, id in ipairs(joint.upper) do graphOK = graphOK and sourceUpper[id] end
        for _, id in ipairs(joint.lower) do graphOK = graphOK and sourceLower[id] end
        sourceGraphGood = sourceGraphGood and graphOK
        out("SOURCE_GRAPH", graphOK and "PASS" or "FAIL",
            ("joint=%s %s I95=%d,%d Kerlin=%d,%d lowerGroup=KERLIN_I95:lower")
                :format(label, point(x, z), joint.upper[1], joint.upper[2], joint.lower[1], joint.lower[2]))
        for _, pair in ipairs({ { name = "I95", ids = joint.upper }, { name = "Kerlin", ids = joint.lower } }) do
            local a = nearestRoadEnd(runtime[pair.ids[1]], x, z)
            local b = nearestRoadEnd(runtime[pair.ids[2]], x, z)
            if a and b then
                local horizontal = math.sqrt((a.position.X - b.position.X) ^ 2
                    + (a.position.Z - b.position.Z) ^ 2)
                local vertical = math.abs(a.position.Y - b.position.Y)
                local pass = horizontal <= GAP_TOLERANCE and vertical <= GAP_TOLERANCE
                out("PATH_JOIN", pass and "PASS" or "FAIL",
                    ("joint=%s road=%s endpointGapXZ=%.3f endpointGapY=%.3f partA=%s partB=%s")
                        :format(label, pair.name, horizontal, vertical,
                            a.part:GetFullName(), b.part:GetFullName()))
            else
                out("PATH_JOIN", "UNKNOWN", "joint=" .. label .. " road=" .. pair.name .. " missing runtime endpoint")
            end
        end
        local upper = {}
        local lower = {}
        for _, id in ipairs(joint.upper) do
            local s = sample(label .. ":I95", id, x, z)
            if s.top and s.bottom then table.insert(upper, s) end
        end
        for _, id in ipairs(joint.lower) do
            local s = sample(label .. ":Kerlin", id, x, z)
            if s.top and s.bottom then table.insert(lower, s) end
        end
        local measured = false
        for _, u in ipairs(upper) do
            for _, l in ipairs(lower) do
                measured = true
                local opening = u.bottom.y - l.top.y
                local overlap = u.bottom.y <= l.top.y and l.bottom.y <= u.top.y
                out("CROSSING", overlap and "FAIL" or "PASS",
                    ("joint=%s upper=%s lower=%s collisionVerticalGap=%.3f collisionOverlap=%s upperBottom=%.3f lowerTop=%.3f")
                        :format(label, u.top.part:GetFullName(), l.top.part:GetFullName(),
                            opening, tostring(overlap), u.bottom.y, l.top.y))
                local bridge = u.top.part:GetAttribute("CW_Bridge") == true
                    or u.top.part:GetAttribute("CW_BridgeProfiled") == true
                if bridge and opening > 0 then
                    out("CLEARANCE", "MEASURED", ("joint=%s roadUndersideToKerlinTop=%.3f; inspect separate deck underside below")
                        :format(label, opening))
                else
                    out("CLEARANCE", "UNKNOWN", "joint=" .. label .. " no verified bridge underside/overpass geometry")
                end
            end
        end
        if not measured then
            out("CROSSING", "UNKNOWN", "joint=" .. label .. " both collidable road volumes not measurable at exact X/Z")
            out("CLEARANCE", "UNKNOWN", "joint=" .. label .. " no measured upper underside and lower pavement pair")
        end
        local pads = tile.Intersections:GetDescendants()
        local padHits = 0
        for _, part in ipairs(pads) do
            if part:IsA("BasePart") and part:GetAttribute("CW_IntersectionPad") == true then
                local hit = vertical(part, x, z, false)
                if hit then
                    padHits += 1
                    out("PAD", "FAIL", ("joint=%s Y=%.3f path=%s collide=%s")
                        :format(label, hit.Position.Y, part:GetFullName(), tostring(part.CanCollide)))
                end
            end
        end
        if padHits == 0 then out("PAD", "PASS", "joint=" .. label .. " no intersection pad ray hit") end
    end

    local anchorX, anchorZ = 2029.925, 19.862
    out("ANCHOR", "REFERENCE", point(anchorX, anchorZ) .. " vicinity only; no source joint assumed")
    local anchorTerrain = vertical(terrain, anchorX, anchorZ, false)
    out("ANCHOR_TERRAIN", anchorTerrain and "MEASURED" or "UNKNOWN",
        "terrainY=" .. number(anchorTerrain and anchorTerrain.Position.Y))
    local anchorRoads = 0
    for _, id in ipairs(IDS) do
        local hit = surface(runtime[id], anchorX, anchorZ, false)
        if hit then
            anchorRoads += 1
            out("ANCHOR_ROAD", "MEASURED", ("id=%d topY=%.3f path=%s")
                :format(id, hit.y, hit.part:GetFullName()))
        end
    end
    if anchorRoads == 0 then
        out("ANCHOR_ROAD", "UNKNOWN", "no identified county road ray hit at vicinity anchor")
    end
    for label, joint in pairs(EXPECTED) do
        local x, z = studs(joint.x, joint.z)
        local distance = math.sqrt((anchorX - x) ^ 2 + (anchorZ - z) ^ 2)
        out("SOURCE_POINT", "VERIFIED", ("joint=%s sourceMeters=(%.3f,%.3f) %s anchorDistance=%.3f")
            :format(label, joint.x, joint.z, point(x, z), distance))
    end
    local midX, midZ = studs(7015.416, 7201.428)
    for _, id in ipairs({ 27163, 20771 }) do sample("KerlinUnderpassMid", id, midX, midZ) end

    -- Profile every source segment, including neighboring approach records.
    for _, id in ipairs(IDS) do
        for segmentIndex, road in ipairs(source[id]) do
            local length = segmentLength(road)
            local count = math.max(2, math.ceil(length / SAMPLE_STEP))
            local previous, missing, unknownTerrain, unknownCollision = nil, 0, 0, 0
            local spike, penetration = 0, 0
            local intervals = partIntervals(road, runtime[id])
            local internalGaps, internalOverlaps = 0, 0
            for i = 2, #intervals do
                local delta = intervals[i].lo - intervals[i - 1].hi
                if delta > GAP_TOLERANCE or delta < -GAP_TOLERANCE then
                    if delta > 0 then internalGaps += 1 else internalOverlaps += 1 end
                    out("SEGMENT_JOIN", "FAIL", ("id=%d sourceSegment=%d gapSigned=%.3f partA=%s partB=%s")
                        :format(id, segmentIndex, delta,
                            intervals[i - 1].part:GetFullName(), intervals[i].part:GetFullName()))
                end
            end
            for i = 1, count - 1 do
                local t = i / count
                local x, z = sourcePoint(road, t)
                local result = sample(("profile:%d:%d:%d/%d"):format(id, segmentIndex, i, count), id, x, z)
                if not result.road then missing += 1 end
                if not result.terrain then unknownTerrain += 1 end
                if not result.top or not result.bottom then unknownCollision += 1 end
                if result.road and result.terrain and result.terrain >= result.road.y - 0.10 then
                    penetration += 1
                end
                if previous and result.road then
                    local run = math.sqrt((x - previous.x) ^ 2 + (z - previous.z) ^ 2)
                    local rise = math.abs(result.road.y - previous.y)
                    local grade = rise / math.max(run, 0.001)
                    if grade > SLOPE_LIMIT then
                        spike += 1
                        out("SLOPE", "FAIL", ("id=%d segment=%d from=%s to=%s grade=%.3f rise=%.3f run=%.3f")
                            :format(id, segmentIndex, point(previous.x, previous.z), point(x, z), grade, rise, run))
                    end
                end
                previous = result.road and { x = x, z = z, y = result.road.y } or nil
            end
            local failed = missing > 0 or spike > 0 or penetration > 0
                or internalGaps > 0 or internalOverlaps > 0
            local status = failed and "FAIL"
                or (#intervals == 0 or unknownTerrain > 0 or unknownCollision > 0) and "UNKNOWN"
                or "PASS"
            out("PROFILE", status, ("id=%d segment=%d length=%.3f interiorSamples=%d parts=%d missing=%d unknownTerrain=%d unknownCollision=%d slopeSpikes=%d terrainPenetrations=%d internalGaps=%d internalOverlaps=%d; endpoints handled by PATH_JOIN")
                :format(id, segmentIndex, length, count - 1, #intervals, missing,
                    unknownTerrain, unknownCollision, spike, penetration,
                    internalGaps, internalOverlaps))
        end
        -- Several county IDs contain consecutive source records. Check those
        -- record boundaries too, including the neighboring approaches.
        for aIndex = 1, #source[id] do
            for bIndex = aIndex + 1, #source[id] do
                for _, aEnd in ipairs({ 0, 1 }) do
                    for _, bEnd in ipairs({ 0, 1 }) do
                        local ax, az = sourcePoint(source[id][aIndex], aEnd)
                        local bx, bz = sourcePoint(source[id][bIndex], bEnd)
                        if math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2) < 0.01 then
                            local first = nearestRoadEnd(runtime[id], ax, az)
                            local others = {}
                            for _, part in ipairs(runtime[id]) do
                                if not first or part ~= first.part then table.insert(others, part) end
                            end
                            local second = nearestRoadEnd(others, ax, az)
                            if first and second then
                                local dx = first.position.X - second.position.X
                                local dz = first.position.Z - second.position.Z
                                local gapXZ = math.sqrt(dx * dx + dz * dz)
                                local gapY = math.abs(first.position.Y - second.position.Y)
                                out("SOURCE_SEGMENT_JOIN",
                                    gapXZ <= GAP_TOLERANCE and gapY <= GAP_TOLERANCE and "PASS" or "FAIL",
                                    ("id=%d records=%d,%d %s gapXZ=%.3f gapY=%.3f partA=%s partB=%s")
                                        :format(id, aIndex, bIndex, point(ax, az), gapXZ, gapY,
                                            first.part:GetFullName(), second.part:GetFullName()))
                            else
                                out("SOURCE_SEGMENT_JOIN", "UNKNOWN",
                                    ("id=%d records=%d,%d %s insufficient runtime Parts")
                                        :format(id, aIndex, bIndex, point(ax, az)))
                            end
                        end
                    end
                end
            end
        end
    end

    -- A separate deck slab is only reported if an actual runtime ray hit exists.
    local infrastructure = tile.Parent:FindFirstChild("HighwayInfrastructure")
    local deckCount = 0
    if infrastructure then
        for _, part in ipairs(infrastructure:GetDescendants()) do
            if part:IsA("BasePart") and part.Name == "BridgeDeck" then
                for label, joint in pairs(EXPECTED) do
                    local x, z = studs(joint.x, joint.z)
                    local bottom = deckUnderside(part, x, z)
                    if bottom then
                        deckCount += 1
                        out("DECK", "MEASURED", ("joint=%s undersideY=%.3f method=%s %s")
                            :format(label, bottom.y, bottom.method, attributes(part)))
                        local lowerTop
                        for _, id in ipairs(joint.lower) do
                            local hit = surface(runtime[id], x, z, false)
                            if hit and (not lowerTop or hit.y > lowerTop.y) then lowerTop = hit end
                        end
                        local terrainHit = vertical(terrain, x, z, false)
                        if lowerTop then
                            local opening = bottom.y - lowerTop.y
                            local blocked = terrainHit and terrainHit.Position.Y >= lowerTop.y + 0.10
                            local obstructionCount = 0
                            if opening > 0.2 then
                                local candidates = Workspace:GetPartBoundsInBox(
                                    CFrame.new(x, (bottom.y + lowerTop.y) / 2, z),
                                    Vector3.new(2, opening, 2))
                                for _, candidate in ipairs(candidates) do
                                    if candidate ~= part and candidate.CanCollide and candidate.CanQuery then
                                        local top = vertical(candidate, x, z, false)
                                        local underside = vertical(candidate, x, z, true)
                                        if top and underside and top.Position.Y > lowerTop.y + 0.10
                                            and underside.Position.Y < bottom.y - 0.10 then
                                            obstructionCount += 1
                                            out("OBSTRUCTION", "FAIL", ("joint=%s object=%s top=%.3f bottom=%.3f")
                                                :format(label, candidate:GetFullName(),
                                                    top.Position.Y, underside.Position.Y))
                                        end
                                    end
                                end
                            end
                            local status = not terrainHit and "UNKNOWN"
                                or (opening > 0 and not blocked and obstructionCount == 0 and "PASS" or "FAIL")
                            out("OVERHEAD_CLEARANCE", status,
                                ("joint=%s deckUnderside=%.3f KerlinTop=%.3f opening=%.3f terrainY=%s terrainBlocks=%s colliderObstructions=%d deckCollide=%s deck=%s lower=%s")
                                    :format(label, bottom.y, lowerTop.y, opening,
                                        number(terrainHit and terrainHit.Position.Y),
                                        blocked == nil and "UNKNOWN" or tostring(blocked),
                                        obstructionCount, tostring(part.CanCollide),
                                        part:GetFullName(), lowerTop.part:GetFullName()))
                        else
                            out("OVERHEAD_CLEARANCE", "UNKNOWN", "joint=" .. label .. " Kerlin surface unavailable beneath deck")
                        end
                    end
                end
            end
        end
    end
    if deckCount == 0 then out("DECK", "UNKNOWN", "no BridgeDeck underside ray hit at either source joint; exact span/underside unavailable") end
    out("SOURCE_NAVIGATION", sourceGraphGood and "PASS" or "FAIL", "source endpoint groups separate I-95 and Kerlin")
    out("RUNTIME_NAVIGATION", "UNKNOWN", "no runtime navigation graph exposed; visual and collision checks above are separate")
    out("END", "PASS", "read-only probe complete; PASS in profiles means sampled points only; inspect Output FAIL/UNKNOWN lines")
end

return Diagnostic
