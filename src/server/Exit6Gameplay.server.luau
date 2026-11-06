-- EXIT 6 server-owned player progression and proximity interactions.
-- Does not alter ChesterWorld geometry, spawn, or existing bootstrap.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Exit6Config"))
local store = DataStoreService:GetDataStore(Config.DataStoreName)
local sessions = {}
local function key(player) return "player_" .. player.UserId end
local function save(player)
 local data = sessions[player]
 if not data or data.persist == false then return end
 local stats = player:FindFirstChild("leaderstats")
 local cash = stats and stats:FindFirstChild("Chester Cash")
 local rep = stats and stats:FindFirstChild("Reputation")
 local snapshot = {cash = cash and cash.Value or data.cash, reputation = rep and rep.Value or data.reputation}
 local ok, err = pcall(function()
  store:UpdateAsync(key(player), function(old)
   old = type(old) == "table" and old or {}
   old.cash = snapshot.cash
   old.reputation = snapshot.reputation
   return old
  end)
 end)
 if not ok then warn("[EXIT6] Save failed for", player.UserId, err) end
 return ok
end
Players.PlayerAdded:Connect(function(player)
 local data = {cash = Config.StartingCash, reputation = Config.StartingReputation}
 local ok, loaded = pcall(function() return store:GetAsync(key(player)) end)
 if ok and type(loaded) == "table" then
  data.cash = math.max(0, math.floor(tonumber(loaded.cash) or data.cash))
  data.reputation = math.max(0, math.floor(tonumber(loaded.reputation) or data.reputation))
 elseif not ok and RunService:IsStudio() then
  -- Studio without "Enable Studio Access to API Services": play an unsaved
  -- session from the starting values so the gameplay can still be tested
  warn("[EXIT6] DataStore unavailable in Studio; unsaved test session for", player.UserId)
  data.persist = false
 elseif not ok then
  warn("[EXIT6] Data load failed; progression changes disabled for", player.UserId)
  player:SetAttribute("Exit6DataReady", false)
  return
 end
 sessions[player] = data
 local stats = Instance.new("Folder")
 stats.Name = "leaderstats"
 stats.Parent = player
 local cash = Instance.new("IntValue")
 cash.Name = "Chester Cash"
 cash.Value = data.cash
 cash.Parent = stats
 local rep = Instance.new("IntValue")
 rep.Name = "Reputation"
 rep.Value = data.reputation
 rep.Parent = stats
 player:SetAttribute("Exit6DataReady", true)
end)
Players.PlayerRemoving:Connect(function(player)
 save(player)
 sessions[player] = nil
end)
game:BindToClose(function()
 for _, player in ipairs(Players:GetPlayers()) do save(player) end
end)
-- autosave: a server crash otherwise loses the whole session's earnings
task.spawn(function()
 while true do
  task.wait(Config.AutosaveSeconds or 120)
  for _, player in ipairs(Players:GetPlayers()) do
   if sessions[player] then task.spawn(save, player) end
  end
 end
end)
-- Interactions are server-authoritative: proximity prompts run on the server.
-- Tag a part with the CollectionService tag "Exit6Interactable" to create a prompt
-- (attributes Exit6Action / Exit6Name set its text).
local CollectionService = game:GetService("CollectionService")
local function setup(part)
 if not part:IsA("BasePart") or part:FindFirstChild("Exit6Prompt") then return end
 local prompt = Instance.new("ProximityPrompt")
 prompt.Name = "Exit6Prompt"
 prompt.ActionText = part:GetAttribute("Exit6Action") or "Interact"
 prompt.ObjectText = part:GetAttribute("Exit6Name") or "EXIT 6"
 prompt.MaxActivationDistance = Config.InteractionDistance
 prompt.RequiresLineOfSight = false
 prompt.Parent = part
 prompt.Triggered:Connect(function(player)
  if not sessions[player] then return end
  local character = player.Character
  local root = character and character:FindFirstChild("HumanoidRootPart")
  if not root or (root.Position - part.Position).Magnitude > Config.InteractionDistance + 3 then return end
  player:SetAttribute("Exit6LastInteraction", part:GetAttribute("Exit6Name") or part.Name)
 end)
end
for _, part in ipairs(CollectionService:GetTagged("Exit6Interactable")) do setup(part) end
CollectionService:GetInstanceAddedSignal("Exit6Interactable"):Connect(setup)
