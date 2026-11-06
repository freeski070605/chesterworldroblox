-- Bake land-cover materials into the terrain surface (Studio Edit, via the MCP
-- execute_luau tool). Data: tools/build_ground_cover.py -> build/groundcover,
-- served with `python -m http.server 8765 --bind 127.0.0.1 --directory build/groundcover`.
-- Only the material of the top solid voxels changes; occupancy (the land shape)
-- is written back unchanged. Set FIRST/LAST to the index.json tiles to bake.
local FIRST, LAST = tonumber(FIRST_TILE) or 1, tonumber(LAST_TILE) or 1

local Http = game:GetService("HttpService")
local Terrain = workspace.Terrain
local BASE = "http://127.0.0.1:8765/"
local STUDS_PER_M = 3
local X_OFF, Z_OFF = 8397592 - 6347.889, -4837229 - 7201.973
local BLOCK = 192
local MATERIAL = {
	[1] = Enum.Material.Grass, [2] = Enum.Material.LeafyGrass, [3] = Enum.Material.Pavement,
	[4] = Enum.Material.Asphalt, [5] = Enum.Material.Pavement, [6] = Enum.Material.Mud,
	[7] = Enum.Material.Ground,
}
local AIR, WATER = Enum.Material.Air, Enum.Material.Water

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = { Terrain }

local wasEnabled = Http.HttpEnabled
Http.HttpEnabled = true
local function fetch(name)
	return Http:GetAsync(BASE .. name)
end
local ok, err = pcall(function()
	local index = Http:JSONDecode(fetch("index.json"))
	for t = FIRST, math.min(LAST, #index) do
		local tile = index[t]
		local w, h = tile.w, tile.h
		local cell = tile.cell_m * STUDS_PER_M
		local grid = buffer.create(w * h)
		local offset = 0
		for line in string.gmatch(fetch(tile.file), "[^\n]+") do
			for token in string.gmatch(line, "[^,]+") do
				local length = tonumber(string.sub(token, 2), 36)
				buffer.fill(grid, offset, tonumber(string.sub(token, 1, 1)), length)
				offset += length
			end
		end
		local x0 = (tile.xmin + X_OFF) * STUDS_PER_M
		local z0 = -(tile.ymax + Z_OFF) * STUDS_PER_M
		local blocks = 0
		for bx = x0, x0 + w * cell, BLOCK do
			for bz = z0, z0 + h * cell, BLOCK do
				local lo, hi = math.huge, -math.huge
				for _, f in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 }, { 0.5, 0.5 }, { 0.5, 0 }, { 0, 0.5 }, { 1, 0.5 }, { 0.5, 1 } }) do
					local r = workspace:Raycast(Vector3.new(bx + f[1] * BLOCK, 3000, bz + f[2] * BLOCK), Vector3.new(0, -6000, 0), params)
					if r then
						lo, hi = math.min(lo, r.Position.Y), math.max(hi, r.Position.Y)
					end
				end
				if lo < math.huge then
					local region = Region3.new(Vector3.new(bx, lo - 12, bz), Vector3.new(bx + BLOCK, hi + 8, bz + BLOCK)):ExpandToGrid(4)
					local materials, occupancy = Terrain:ReadVoxels(region, 4)
					local size = materials.Size
					local origin = region.CFrame.Position - region.Size / 2
					for ix = 1, size.X do
						local j = math.floor((origin.X + (ix - 0.5) * 4 - x0) / cell)
						if j >= 0 and j < w then
							local mx = materials[ix]
							local ox = occupancy[ix]
							for iz = 1, size.Z do
								local i = math.floor((origin.Z + (iz - 0.5) * 4 - z0) / cell)
								if i >= 0 and i < h then
									local material = MATERIAL[buffer.readu8(grid, i * w + j)]
									if material then
										for iy = size.Y, 1, -1 do
											local m = mx[iy][iz]
											if m ~= AIR and m ~= WATER and ox[iy][iz] > 0 then
												mx[iy][iz] = material
												if iy > 1 and mx[iy - 1][iz] ~= AIR then
													mx[iy - 1][iz] = material
												end
												break
											end
										end
									end
								end
							end
						end
					end
					Terrain:WriteVoxels(region, 4, materials, occupancy)
					blocks += 1
					if blocks % 8 == 0 then
						task.wait()
					end
				end
			end
		end
		workspace:SetAttribute("CW_GroundCoverBaked_" .. tile.file, blocks)
	end
end)
Http.HttpEnabled = wasEnabled
return ok and ("baked tiles " .. FIRST .. "-" .. LAST) or ("error: " .. tostring(err))
