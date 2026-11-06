-- Marks players allowed to use tester flight / fast travel (CW_Tester), per
-- WorldConfig.TESTER_FLIGHT_ALL / TESTER_USER_IDS. The client flight script
-- (DebugFlight.client.lua) waits for this attribute outside Studio.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WorldConfig"))

local allowed = {}
for _, id in ipairs(WorldConfig.TESTER_USER_IDS or {}) do
	allowed[id] = true
end

local function grant(player)
	local ok = WorldConfig.TESTER_FLIGHT_ALL == true or allowed[player.UserId] == true
	player:SetAttribute("CW_Tester", ok)
end

Players.PlayerAdded:Connect(grant)
for _, player in ipairs(Players:GetPlayers()) do
	grant(player)
end
