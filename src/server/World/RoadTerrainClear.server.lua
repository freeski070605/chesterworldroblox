-- Clears terrain poking up through road, junction and sidewalk surfaces.
--
-- Street pieces are straight slabs between terrain samples, so where the
-- bare-earth DEM bulges between those samples (and where the baked land-cover
-- pavement sits a little high) grass, dirt or terrain pavement shows through
-- the street. Audit 2026-11-06: 25,845 samples in ~6,700 spots, worst on the
-- I-95 / Barry corridors; terrain also filled the space under overpass decks
-- (DEM embankments across I-95 under Edgmont / Upland).
--
-- After the world is built and the highway finish has run, the terrain above
-- every street part is emptied over the part's own footprint, from 2 studs
-- below its top surface (a half voxel, so no partly-filled voxel can render
-- above the street; the part itself hides that band) up CLEAR_HEIGHT studs.
-- Checking each part first missed bumps between the probes and left
-- half-voxels showing; clearing all of them is simpler and as fast (~24 s for
-- ~115k parts on the 2026-11-06 world). Tunnels are left alone. Only terrain
-- above the street surface is touched. Sets CW_RoadTerrainCleared.
-- Verified: 0.4 % of 185k street-surface samples still under terrain after
-- the pass, nearly all within 1 stud (was 14 %).
local Workspace = game:GetService("Workspace")
local Terrain = Workspace.Terrain

while Workspace:GetAttribute("CW_HighwayFinishComplete") ~= true do task.wait(0.5) end
if Workspace:GetAttribute("CW_RoadTerrainCleared") then return end

local world = Workspace:WaitForChild("ChesterWorld")
local FOLDERS = { Roads = true, Intersection = true, Intersections = true, Sidewalks = true }
local BELOW_TOP = 2          -- start this far under the street top (half a voxel)
local CLEAR_HEIGHT = 40      -- studs emptied above that (reaches overpass decks)

local started = os.clock()
local cleared = 0
for _, tile in ipairs(world:GetChildren()) do
	for _, folder in ipairs(tile:GetChildren()) do
		if FOLDERS[folder.Name] then
			for _, part in ipairs(folder:GetDescendants()) do
				if part:IsA("BasePart") and part.Transparency < 1 and part.Name ~= "Rail"
					and part:GetAttribute("CW_Tunnel") ~= true then
					local size = part.Size
					Terrain:FillBlock(part.CFrame * CFrame.new(0, size.Y / 2 - BELOW_TOP + CLEAR_HEIGHT / 2, 0),
						Vector3.new(size.X, CLEAR_HEIGHT, size.Z), Enum.Material.Air)
					cleared += 1
					if cleared % 800 == 0 then task.wait() end
				end
			end
		end
	end
end

print(("[ChesterWorld RoadTerrainClear] cleared=%d seconds=%.1f"):format(cleared, os.clock() - started))
Workspace:SetAttribute("CW_RoadTerrainCleared", true)
