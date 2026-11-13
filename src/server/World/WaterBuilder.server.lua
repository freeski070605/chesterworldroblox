-- EXIT 6 water: trust a persisted Studio bake ONLY after verifying GIS
-- signature and physical water voxels. Otherwise retain the original
-- runtime fallback after roads/highways/landmarks are finished.
local Workspace = game:GetService("Workspace")
local Terrain = Workspace.Terrain
local WaterTerrain = require(script.Parent:WaitForChild("WaterTerrain"))

Workspace:SetAttribute("CW_WaterComplete", false)
Workspace:SetAttribute("CW_WaterStatus", "checking-bake")
Workspace:SetAttribute("CW_WaterPatchesDone", 0)
Workspace:SetAttribute("CW_WaterPatchesTotal", 0)

local dataset,sourceError = WaterTerrain.Dataset()
if not dataset then
    warn("[EXIT6 Water] GIS data unavailable: " .. tostring(sourceError) ..
        "; no guessed water will be generated.")
    Workspace:SetAttribute("CW_WaterStatus","source-not-exported")
    Workspace:SetAttribute("CW_WaterComplete",true)
    return
end

local initiallyBaked,why = WaterTerrain.Verify(dataset)
if initiallyBaked then
    WaterTerrain.ApplyWaterAppearance()
    Workspace:SetAttribute("CW_WaterStatus","baked-waiting-for-final-terrain")
    print(("[EXIT6 Water] BAKED DETECTED signature=%s; awaiting final terrain clearing, " ..
        "landmarks and local bridges before certifying the playable world")
        :format(dataset.signature))
else
    warn("[EXIT6 Water] No verified Studio water bake (" .. tostring(why) ..
        "); using conservative live-server fallback.")
end

local function readyForWater()
    return Workspace:GetAttribute("CW_BootstrapComplete")==true
        and Workspace:GetAttribute("CW_RoadConformComplete")==true
        and Workspace:GetAttribute("CW_HighwayFinishComplete")==true
        and Workspace:GetAttribute("CW_ParksComplete")==true
        and Workspace:GetAttribute("CW_GasStationsComplete")==true
        and Workspace:GetAttribute("CW_RoadTerrainCleared")==true
        and Workspace:GetAttribute("CW_LandmarksComplete")==true
        and Workspace:GetAttribute("CW_LocalBridgesDressed")==true
end

local lastStage
while not readyForWater() do
    local stage = "waiting-for-structures"
    if Workspace:GetAttribute("CW_RoadTerrainCleared") ~= true then
        stage = "waiting-for-road-terrain-clear"
    elseif Workspace:GetAttribute("CW_LandmarksComplete") ~= true then
        stage = "waiting-for-landmarks"
    elseif Workspace:GetAttribute("CW_LocalBridgesDressed") ~= true then
        stage = "waiting-for-local-bridges"
    end
    if lastStage ~= stage then
        Workspace:SetAttribute("CW_WaterStatus",stage)
        lastStage = stage
    end
    task.wait(0.5)
end
if initiallyBaked then
    local stillVerified,finalReason = WaterTerrain.Verify(dataset)
    if stillVerified then
        Workspace:SetAttribute("CW_WaterPatchesTotal",dataset.patches)
        Workspace:SetAttribute("CW_WaterPatchesDone",dataset.patches)
        Workspace:SetAttribute("CW_WaterStatus","baked-verified")
        Workspace:SetAttribute("CW_WaterComplete",true)
        print(("[EXIT6 Water] BAKED VERIFIED AFTER WORLD FINISH signature=%s " ..
            "tiles=%d rects=%d savedRuntimeGeneration=true proof=%s")
            :format(dataset.signature,#dataset.tiles,dataset.rects,tostring(finalReason)))
        return
    end
    warn("[EXIT6 Water] Baked water proof failed AFTER world finish (" ..
        tostring(finalReason) .. "); repairing using the conservative runtime fallback.")
end
Workspace:SetAttribute("CW_WaterPatchesTotal",dataset.patches)
Workspace:SetAttribute("CW_WaterStatus","building")
local ok,result = pcall(WaterTerrain.Build,dataset,function(done,total)
    Workspace:SetAttribute("CW_WaterPatchesDone",done)
end)
if not ok then
    Workspace:SetAttribute("CW_WaterStatus","failed")
    Workspace:SetAttribute("CW_WaterError",tostring(result):sub(1,800))
    warn("[EXIT6 Water] FAILED: " .. tostring(result))
    return
end
Workspace:SetAttribute("CW_WaterPatchesDone",result.patches)
Workspace:SetAttribute("CW_WaterSolidCellsProtected",result.solidProtected)
Workspace:SetAttribute("CW_WaterFilledVoxels",result.filled)
Workspace:SetAttribute("CW_WaterStatus","complete")
Workspace:SetAttribute("CW_WaterComplete",true)
print(("[EXIT6 Water] COMPLETE modules=%d patches=%d waterVoxels=%d solidProtected=%d")
    :format(result.tiles,result.patches,result.filled,result.solidProtected))
