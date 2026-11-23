-- ChesterWorld | Geographic reconstruction inspector, 2026-11-22
-- VISUALIZATION ONLY: outlines and labels; never edits buildings.
-- Play (full city) -> Server Command Bar:
--   require(game.ServerScriptService.Server.World.ReconstructionInspector).Run()
--   require(game.ServerScriptService.Server.World.ReconstructionInspector).Run({radius = 600})
--   require(game.ServerScriptService.Server.World.ReconstructionInspector).Clear()
-- Colours (ReconstructionStatus set by TileBuilderV2 from
-- PropertyReconstruction.lua / BuildingReviewOverrides.lua):
--   green  reconstructed    pose-verified structure applied
--   teal   finish_verified  only the photographed finish applied
--   yellow photo_override   older single-photo review, camera pose unchecked
--   red    fallback with a conflict or needing imagery
--   grey   fallback         county footprint + procedural kit
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local NeighborhoodScope = require(script.Parent:WaitForChild("NeighborhoodScope"))

local Inspector = {}
local FOLDER = "CW_ReconstructionInspector_TEMP"
local COLOURS = {
	reconstructed = Color3.fromRGB(60, 220, 90),
	finish_verified = Color3.fromRGB(60, 200, 200),
	photo_override = Color3.fromRGB(240, 210, 60),
	conflict = Color3.fromRGB(235, 60, 50),
	fallback = Color3.fromRGB(150, 150, 150),
}

local function log(status, message)
	print(("RECON_INSPECT | %s | %s"):format(status, message))
end

function Inspector.Clear()
	local old = Workspace:FindFirstChild(FOLDER)
	if old then old:Destroy() end
	log("CLEAR", "removed inspector outlines")
end

function Inspector.Run(options)
	options = options or {}
	Inspector.Clear()
	local folder = Instance.new("Folder")
	folder.Name = FOLDER
	folder.Parent = Workspace
	local centre
	local player = Players:GetPlayers()[1]
	if options.radius and player and player.Character and player.Character.PrimaryPart then
		centre = player.Character.PrimaryPart.Position
	end
	local counts, changed = {}, {}
    local seenNeighborhood = {}
    local relevant = 0
	for _, model in ipairs(Workspace:GetDescendants()) do
		local status = model:IsA("Model") and model:GetAttribute("ReconstructionStatus")
		if status and (not options.neighborhood or NeighborhoodScope[tostring(model:GetAttribute("ChesterBuildingId"))]) then
            local buildingId=tostring(model:GetAttribute("ChesterBuildingId"))
            if NeighborhoodScope[buildingId] then
                seenNeighborhood[buildingId]=true
                relevant+=1
                if buildingId=="147448" then
                    log("777_PARTS",("id=%s photoParts=%s photoReconstruction=%s style=%s loc=%s")
                        :format(buildingId,tostring(model:GetAttribute("777PhotoPartCount")),
                            tostring(model:GetAttribute("777PhotoReconstruction")),
                            tostring(model:GetAttribute("BuildingStyle")),
                            tostring(model:GetPivot().Position)))
                end
            end
			local evidence = model:GetAttribute("ReconstructionEvidenceStatus")
			local key = status
			if status == "fallback" and (evidence == "conflict" or evidence == "needs_imagery") then key = "conflict" end
			counts[key] = (counts[key] or 0) + 1
			local near = true
			if centre then
				local ok, pivot = pcall(model.GetPivot, model)
				near = ok and (pivot.Position - centre).Magnitude <= options.radius
			end
			if near then
				local box = Instance.new("SelectionBox")
				box.Adornee = model
				box.Color3 = COLOURS[key] or COLOURS.fallback
				box.LineThickness = 0.35
				box.SurfaceTransparency = 1
				box.Parent = folder
				local label = Instance.new("BillboardGui")
				label.Adornee = model
				label.Size = UDim2.fromOffset(220, 46)
				label.StudsOffsetWorldSpace = Vector3.new(0, 18, 0)
				label.AlwaysOnTop = true
				label.MaxDistance = 400
				label.Parent = folder
				local text = Instance.new("TextLabel")
				text.Size = UDim2.fromScale(1, 1)
				text.BackgroundTransparency = 0.35
				text.BackgroundColor3 = Color3.new(0, 0, 0)
				text.TextColor3 = COLOURS[key] or COLOURS.fallback
				text.TextScaled = true
				text.Font = Enum.Font.Code
				text.Text = ("%s %s\n%s %s"):format(tostring(model:GetAttribute("ChesterBuildingId")), key,
					tostring(model:GetAttribute("BuildingStyle") or ""), tostring(model:GetAttribute("ReconstructionSpec") or ""))
				text.Parent = label
			end
			if status == "reconstructed" then
				table.insert(changed, tostring(model:GetAttribute("ChesterBuildingId")))
			end
		end
	end
    if options.neighborhood then
        local missing={}
        local total=0
        for id in pairs(NeighborhoodScope) do
            total+=1
            if not seenNeighborhood[id] then table.insert(missing,id) end
        end
        table.sort(missing,function(a,b)return tonumber(a)<tonumber(b)end)
        log("9TH_KERLIN",("loaded=%d expected=%d seen=%d missing=%d")
            :format(relevant,total,total-#missing,#missing))
        if #missing>0 then log("MISSING_IDS",table.concat(missing,", ")) end
    end
	for key, n in pairs(counts) do log("COUNT", ("%s=%d"):format(key, n)) end
	table.sort(changed, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
	log("RECONSTRUCTED", table.concat(changed, " "))
	return counts
end

return Inspector
