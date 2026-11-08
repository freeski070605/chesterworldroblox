-- Read-only. Paste into Studio Command Bar in Edit mode, or execute with a
-- Studio Luau bridge. Copy the JSON printed after EXIT6_CAR_AUDIT_JSON=.
local HttpService = game:GetService("HttpService")
local storage = game:GetService("ServerStorage")
local folder = storage:FindFirstChild("Exit6CarMeshes")
local result = {
	placeId = game.PlaceId,
	placeName = game.Name,
	folderPresent = folder ~= nil,
	models = {},
}
if folder then
	for _, model in ipairs(folder:GetChildren()) do
		local record = {
			name = model.Name,
			class = model.ClassName,
			attributes = model:GetAttributes(),
			counts = { Part = 0, MeshPart = 0, UnionOperation = 0, EditableMesh = 0, OtherBasePart = 0 },
			geometry = {},
		}
		for _, obj in ipairs(model:GetDescendants()) do
			local class = obj.ClassName
			if record.counts[class] ~= nil then
				record.counts[class] += 1
			elseif obj:IsA("BasePart") then
				record.counts.OtherBasePart += 1
			end
			if obj:IsA("BasePart") then
				local part = {
					path = obj:GetFullName(), class = class, size = { obj.Size.X, obj.Size.Y, obj.Size.Z },
					material = obj.Material.Name, color = obj.Color:ToHex(), transparency = obj.Transparency,
					anchored = obj.Anchored, canCollide = obj.CanCollide,
				}
				if obj:IsA("MeshPart") then
					part.meshId = obj.MeshId
					part.textureId = obj.TextureID
					part.meshSize = { obj.MeshSize.X, obj.MeshSize.Y, obj.MeshSize.Z }
					part.renderFidelity = obj.RenderFidelity.Name
				elseif obj:IsA("Part") then
					part.shape = obj.Shape.Name
				end
				local special = obj:FindFirstChildWhichIsA("SpecialMesh")
				if special then
					part.specialMesh = { meshType = special.MeshType.Name, meshId = special.MeshId,
						textureId = special.TextureId }
				end
				local surface = obj:FindFirstChildWhichIsA("SurfaceAppearance")
				if surface then
					part.surfaceAppearance = { colorMap = surface.ColorMap, normalMap = surface.NormalMap,
						metalnessMap = surface.MetalnessMap, roughnessMap = surface.RoughnessMap }
				end
				table.insert(record.geometry, part)
			end
		end
		table.insert(result.models, record)
	end
end
table.sort(result.models, function(a, b) return a.name < b.name end)
local encoded = HttpService:JSONEncode(result)
print("EXIT6_CAR_AUDIT_JSON=" .. encoded)
return encoded
