-- run in Studio (Edit) after tools/harness/studio_push_world.sh
local root = game:GetObjects("rbxasset://chesterpatch/WorldPatch.rbxm")[1]
local live = game.ServerScriptService.Server.World
local changed, added = {}, {}
local function sync(src, dst)
	for _, c in ipairs(src:GetChildren()) do
		local d = dst:FindFirstChild(c.Name)
		if not d then
			c:Clone().Parent = dst
			table.insert(added, c.Name)
		elseif c:IsA("LuaSourceContainer") then
			if d.Source ~= c.Source then d.Source = c.Source; table.insert(changed, c.Name) end
			if #c:GetChildren() > 0 then sync(c, d) end
		else
			sync(c, d)
		end
	end
end
sync(root, live)
return { changed = changed, added = added }
