-- Use from Roblox Studio COMMAND BAR in Edit mode, NEVER in Play mode:
-- require(game.ServerScriptService.Server.World.WaterBake).Run()
-- Save a backup of your .rbxl/.rbxlx place BEFORE running.
local RunService = game:GetService("RunService")
local Terrain = workspace.Terrain
local WaterTerrain = require(script.Parent:WaitForChild("WaterTerrain"))
local M = {}

function M.Status()
    local dataset,err = WaterTerrain.Dataset()
    if not dataset then
        warn("[EXIT6 Water Bake] dataset unavailable: " .. tostring(err))
        return false
    end
    local valid,reason = WaterTerrain.Verify(dataset)
    print(("[EXIT6 Water Bake] signature=%s tiles=%d rects=%d patches=%d status=%s")
        :format(dataset.signature,#dataset.tiles,dataset.rects,dataset.patches,
            valid and "VERIFIED" or tostring(reason)))
    return valid
end

function M.Run()
    if not RunService:IsStudio() or not RunService:IsEdit() then
        error("Water bake REFUSED. Stop Play/Run; execute in Studio Edit mode only.")
    end
    local dataset,err = WaterTerrain.Dataset()
    if not dataset then error("Water bake missing GIS source: " .. tostring(err)) end

    local existing = Terrain:GetAttribute("CW_WaterBakeSignature")
    if existing and existing ~= dataset.signature then
        error("Existing baked water uses a DIFFERENT GIS dataset. Restore a pre-water " ..
            "Studio backup before rebaking changed geography (no stale-water overlay).")
    end
    if existing then
        local valid,reason = WaterTerrain.Verify(dataset)
        if valid then
            print("[EXIT6 Water Bake] Already VERIFIED. Nothing to rebuild; save/publish the place.")
            return true
        end
        error("Existing bake verification failed: " .. tostring(reason) ..
            ". Restore your pre-bake backup rather than layering water.")
    end

    print(("[EXIT6 Water Bake] EDIT MODE: building %d tiles, %d rectangles, %d patches. " ..
        "Confirm you saved a BACKUP before this command."):format(
        #dataset.tiles,dataset.rects,dataset.patches))
    local result = WaterTerrain.Build(dataset, function(done,total)
        if done % 8192 < 32 or done == total then
            print(("[EXIT6 Water Bake] progress=%d/%d"):format(done,total))
        end
    end)
    if #result.probes < math.min(12,#dataset.tiles) then
        error("Only " .. #result.probes .. " water tiles had proof; NOT marking as baked.")
    end
    local encoded = {}
    for _,p in ipairs(result.probes) do
        table.insert(encoded,("%d,%d,%d"):format(p[1],p[2],p[3]))
    end
    -- Marker is written LAST, only after all Terrain writes return successfully.
    Terrain:SetAttribute("CW_WaterBakeProof",table.concat(encoded,";"))
    Terrain:SetAttribute("CW_WaterBakeProbeCount",#encoded)
    Terrain:SetAttribute("CW_WaterBakeSignature",dataset.signature)
    local verified,reason = WaterTerrain.Verify(dataset)
    if not verified then
        Terrain:SetAttribute("CW_WaterBakeSignature",nil)
        error("Post-bake proof FAILED: " .. tostring(reason) ..
            ". Do NOT publish. Restore the pre-bake backup.")
    end
    Terrain:SetAttribute("CW_WaterBakeFilledVoxels",result.filled)
    print(("[EXIT6 Water Bake] VERIFIED %s: tiles=%d patches=%d filled=%d " ..
        "solidProtected=%d proofTiles=%d. SAVE THE PLACE in EDIT mode!")
        :format(dataset.signature,result.tiles,result.patches,
            result.filled,result.solidProtected,#result.probes))
    return true
end

return M
