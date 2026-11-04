-- ChesterWorld | Kerlin/I-95 | Studio-only finish preview on existing test bridge.
-- This module adds *noncolliding* visual surfaces, stripes, and edge parapets
-- onto KerlinDrivableTest_TEMP. It never edits terrain, GIS, source roads,
-- highway collision, or the drivable-test Parts themselves.
--
-- Precondition: In a Studio Play Server Command Bar, after all world phases:
--   require(game.ServerScriptService.Server.World.KerlinDrivableTest)
--       .Run({isolateLegacy=true})
-- Run:
--   require(game.ServerScriptService.Server.World.KerlinBridgeFinishPreview).Run()
-- Remove overlay without removing test pavement:
--   require(game.ServerScriptService.Server.World.KerlinBridgeFinishPreview).Clear()
-- Remove everything: Clear the finish preview first, then KerlinDrivableTest.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local M = {}
local ROAD_TEST_NAME = "KerlinDrivableTest_TEMP"
local FINISH_NAME = "KerlinBridgeFinishPreview_TEMP"
local TEST_OWNER = "CW_KerlinDrivableTestOwned"
local FINISH_OWNER = "CW_KerlinBridgeFinishOwned"

-- All geometry is for visual validation only, NOT engineering-verified.
local SKIN_THICKNESS = 0.040
local STRIPE_THICKNESS = 0.028
local STRIPE_WIDTH = 0.24
local STRIPE_INSET = 1.6
local PARAPET_HEIGHT = 1.9
local PARAPET_WIDTH = 0.65
local PARAPET_OUTSET = 0.35
local NO_SHADOW = false

local ROAD_COLOR = Color3.fromRGB(76, 79, 84)
local EDGE_WHITE = Color3.fromRGB(224, 224, 218)
local EDGE_YELLOW = Color3.fromRGB(242, 188, 61)
local CONCRETE = Color3.fromRGB(145, 147, 149)

local function log(stage, status, msg)
    print(("KERLIN_FINISH | %s | %s | %s"):format(stage, status, msg))
end

local function getWorld()
    if not RunService:IsStudio() or not RunService:IsServer() then
        log("READY", "FAIL", "Use Roblox Studio Play, Server Command Bar")
        return nil
    end
    local world = Workspace:FindFirstChild("ChesterWorld")
    if not world then
        log("READY", "FAIL", "Workspace.ChesterWorld is not present")
        return nil
    end
    return world
end

local function findOwned(parent, name, ownerAttribute)
    local folder = parent:FindFirstChild(name)
    if folder and folder:GetAttribute(ownerAttribute) ~= true then
        log("OWNER", "FAIL", "Refusing to modify unowned " .. folder:GetFullName())
        return nil, false
    end
    return folder, true
end

local function makeVisual(parent, name, size, frame, color, material)
    local p = Instance.new("Part")
    p.Name = name
    p.Size = size
    p.CFrame = frame
    p.Color = color
    p.Material = material
    p.Anchored = true
    p.CanCollide = false
    p.CanTouch = false
    p.CanQuery = false
    p.CastShadow = NO_SHADOW
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p:SetAttribute(FINISH_OWNER, true)
    p:SetAttribute("CW_ExperimentalVisualOnly", true)
    p.Parent = parent
    return p
end

function M.Clear()
    local world = getWorld()
    if not world then return false end
    local old, safe = findOwned(world, FINISH_NAME, FINISH_OWNER)
    if not safe then return false end
    if old then old:Destroy() end
    log("CLEAR", "PASS", "Removed only noncolliding finish visuals; test pavement and original city untouched")
    return true
end

local function sortedRoadPieces(routeFolder)
    local result = {}
    for _, instance in ipairs(routeFolder:GetChildren()) do
        if instance:IsA("BasePart")
            and instance:GetAttribute(TEST_OWNER) == true
            and instance.Name:match("^Road_")
        then
            table.insert(result, instance)
        end
    end
    -- Sorted by the negative/positive numeric station at start of the name.
    table.sort(result, function(a, b)
        local aStart = tonumber(a.Name:match("^Road_([%+%-]?%d+)_")) or 0
        local bStart = tonumber(b.Name:match("^Road_([%+%-]?%d+)_")) or 0
        return aStart < bStart
    end)
    return result
end

function M.Run()
    local world = getWorld()
    if not world then return false end
    if Workspace:GetAttribute("CW_HighwayFinishComplete") ~= true then
        log("READY", "FAIL", "Wait for road conforming and highway finishing")
        return false
    end
    local test, safe = findOwned(world, ROAD_TEST_NAME, TEST_OWNER)
    if not safe then return false end
    if not test or test:GetAttribute("CW_KerlinTestIsolated") ~= true then
        log("READY", "FAIL", "First run KerlinDrivableTest.Run({isolateLegacy=true})")
        return false
    end
    local old, allowed = findOwned(world, FINISH_NAME, FINISH_OWNER)
    if not allowed then return false end
    if old then old:Destroy() end

    local folder = Instance.new("Folder")
    folder.Name = FINISH_NAME
    folder:SetAttribute(FINISH_OWNER, true)
    folder:SetAttribute("CW_ExperimentalVisualOnly", true)
    folder.Parent = world

    local counters = {skins = 0, edges = 0, lane = 0, parapets = 0, routes = 0}
    local ok, err = pcall(function()
        for _, routeFolder in ipairs(test:GetChildren()) do
            if routeFolder:IsA("Folder") and routeFolder.Name:match("^Route%d+_") then
                local pieces = sortedRoadPieces(routeFolder)
                if #pieces == 0 then error("No test road sections in " .. routeFolder.Name) end
                counters.routes += 1
                local group = Instance.new("Folder")
                group.Name = routeFolder.Name
                group.Parent = folder

                for index, road in ipairs(pieces) do
                    -- This module never modifies the collision Part.
                    local halfW = road.Size.X / 2
                    local topOffset = road.Size.Y / 2
                    local skinY = topOffset + SKIN_THICKNESS / 2 + 0.012
                    local length = road.Size.Z - 0.12
                    if length > 0.2 then
                        makeVisual(group, "AsphaltSkin", Vector3.new(road.Size.X, SKIN_THICKNESS, length),
                            road.CFrame * CFrame.new(0, skinY, 0), ROAD_COLOR, Enum.Material.Asphalt)
                        counters.skins += 1

                        for _, side in ipairs({-1, 1}) do
                            local offsetX = side * (halfW - STRIPE_INSET)
                            local lineColor = side == -1 and EDGE_YELLOW or EDGE_WHITE
                            makeVisual(group, "ShoulderEdge", Vector3.new(STRIPE_WIDTH, STRIPE_THICKNESS, length),
                                road.CFrame * CFrame.new(offsetX, skinY + (SKIN_THICKNESS + STRIPE_THICKNESS) / 2 + 0.015, 0),
                                lineColor, Enum.Material.SmoothPlastic)
                            counters.edges += 1
                        end
                        -- Deliberately generic dashed guide line: lane count and
                        -- exact real striping pattern still require validation.
                        if index % 3 ~= 0 then
                            makeVisual(group, "CenterGuide", Vector3.new(STRIPE_WIDTH, STRIPE_THICKNESS, length),
                                road.CFrame * CFrame.new(0, skinY + (SKIN_THICKNESS + STRIPE_THICKNESS) / 2 + 0.015, 0),
                                EDGE_WHITE, Enum.Material.SmoothPlastic)
                            counters.lane += 1
                        end

                        -- Only on the experimental 1.6-stud structural sections.
                        -- Noncolliding until deck-edge clearance/vehicle driving are verified.
                        if (road:GetAttribute("CW_AssumedThicknessStuds") or 0) > 1 then
                            for _, side in ipairs({-1, 1}) do
                                local barrierX = side * (halfW + PARAPET_OUTSET)
                                local barrierY = topOffset + PARAPET_HEIGHT / 2
                                makeVisual(group, "BridgeParapetVisual", Vector3.new(PARAPET_WIDTH, PARAPET_HEIGHT, length),
                                    road.CFrame * CFrame.new(barrierX, barrierY, 0), CONCRETE, Enum.Material.Concrete)
                                counters.parapets += 1
                            end
                        end
                    end
                end
            end
        end
        if counters.routes ~= 2 then
            error("Expected 2 tested I-95 carriageway routes; found " .. tostring(counters.routes))
        end
    end)
    if not ok then
        if folder.Parent then folder:Destroy() end
        log("ROLLBACK", "FAIL", tostring(err))
        return false
    end
    log("BEGIN", "PASS", "Noncolliding visual finish on existing KerlinDrivableTest only")
    log("DETAILS", "ILLUSTRATIVE", ("routes=%d surfaceSkins=%d edgeStripes=%d dashedGuides=%d parapetSections=%d"):
        format(counters.routes, counters.skins, counters.edges, counters.lane, counters.parapets))
    log("LIMITS", "UNVERIFIED", "No source pavement, underside, abutment, collision, terrain, or highway profile changed. Cosmetic striping and parapets are NOT confirmed field dimensions")
    log("END", "PASS", "Call KerlinBridgeFinishPreview.Clear() before clearing KerlinDrivableTest")
    return true
end

return M
