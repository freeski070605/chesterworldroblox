-- EXIT 6 performance probe (diagnostics for console testing): publishes the
-- server's memory and instance numbers for the client overlay
-- (Exit6PerfHUD.client) - Xbox has no developer console. Remove for release.
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")

task.spawn(function()
	while true do
		Workspace:SetAttribute("Exit6SrvMemMB", math.floor(Stats:GetTotalMemoryUsageMb()))
		local ok, lua = pcall(function() return Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.LuaHeap) end)
		Workspace:SetAttribute("Exit6SrvLuaMB", ok and math.floor(lua) or -1)
		Workspace:SetAttribute("Exit6SrvHeartbeat", math.floor(Stats.HeartbeatTimeMs * 10) / 10)
		task.wait(2)
	end
end)
