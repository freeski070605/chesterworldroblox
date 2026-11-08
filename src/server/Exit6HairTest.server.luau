-- Server-authoritative, free development collection for Xbox fit testing.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Exit6Catalog"))
local Style = require(script.Parent:WaitForChild("Exit6Style"))
local remotes = ReplicatedStorage:WaitForChild("Exit6Remotes")
local action = Instance.new("RemoteFunction")
action.Name = "HairTestAction"
action.Parent = remotes

local allowed = {}
for _, entry in ipairs(Catalog.HairTest) do allowed[entry.id] = true end
local lastCall = {}
local function list()
	local result = {}
	for _, entry in ipairs(Catalog.HairTest) do
		table.insert(result, { id = entry.id, name = entry.name,
			installed = Style.TestAssetAvailable(entry.id) })
	end
	return result
end

action.OnServerInvoke = function(player, verb, assetId)
	if verb == "list" then return true, list() end
	if player:GetAttribute("Exit6DataReady") ~= true then return false, "Appearance not loaded" end
	if verb == "cancel" then
		Style.Apply(player)
		return true
	end
	local now = os.clock()
	if lastCall[player] and now - lastCall[player] < .15 then return false, "Wait a moment" end
	lastCall[player] = now
	if verb == "restore" then
		return Style.RestoreOwnHair(player)
	elseif type(assetId) ~= "string" or not allowed[assetId] then
		return false, "Unknown hairstyle"
	elseif not Style.TestAssetAvailable(assetId) then
		return false, "Mesh not installed in this place"
	elseif verb == "preview" then
		local ok = Style.PreviewTestHair(player, assetId)
		return ok, ok and nil or "Could not attach hair to this character"
	elseif verb == "equip" then
		local ok = Style.EquipTestHair(player, assetId)
		return ok, ok and nil or "Could not save this hairstyle"
	end
	return false, "Unknown action"
end

Players.PlayerRemoving:Connect(function(player) lastCall[player] = nil end)
