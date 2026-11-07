-- EXIT 6 Rumble v1: server-owned meter, challenge, consent and timed match.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local remote=Instance.new("RemoteEvent")
remote.Name="Exit6RumbleEvent";remote.Parent=ReplicatedStorage
local MAX_DISTANCE=11
local COOLDOWN=.65
local HIT_GAIN=20
local MATCH_SECONDS=60
local lastHit,meters,requests,matches={}, {}, {}, {}
local function state(p) return meters[p] or {} end
local function update(p,target)
 if p.Parent==Players then remote:FireClient(p,"Meter",target.UserId,(state(p))[target.UserId] or 0) end
end
local function nearby(a,b)
 local ca,cb=a.Character,b.Character
 local ra=ca and ca:FindFirstChild("HumanoidRootPart")
 local rb=cb and cb:FindFirstChild("HumanoidRootPart")
 local ha=ca and ca:FindFirstChildOfClass("Humanoid")
 local hb=cb and cb:FindFirstChildOfClass("Humanoid")
 return ra and rb and ha and hb and ha.Health>0 and hb.Health>0 and (ra.Position-rb.Position).Magnitude<=MAX_DISTANCE
end
local function finish(a,b,reason)
 if matches[a]~=b then return end
 matches[a]=nil;matches[b]=nil
 if a.Parent==Players then remote:FireClient(a,"End",reason) end
 if b.Parent==Players then remote:FireClient(b,"End",reason) end
end
remote.OnServerEvent:Connect(function(player,action,targetId)
 if action=="Decline" then
  local challenger=requests[player]
  requests[player]=nil
  if challenger and challenger.Parent==Players then remote:FireClient(challenger,"Notice","Rumble declined.") end
  return
 end
 if action=="Accept" then
  local challenger=requests[player]
  requests[player]=nil
  if not challenger or matches[player] or matches[challenger] or not nearby(player,challenger) then return end
  if (state(challenger))[player.UserId]~=100 then return end
  meters[challenger][player.UserId]=0;update(challenger,player)
  matches[player]=challenger;matches[challenger]=player
  remote:FireClient(player,"Start",challenger.UserId,MATCH_SECONDS)
  remote:FireClient(challenger,"Start",player.UserId,MATCH_SECONDS)
  task.delay(MATCH_SECONDS,function() finish(player,challenger,"Time up") end)
  return
 end
 if typeof(targetId)~="number" then return end
 local target=Players:GetPlayerByUserId(targetId)
 if not target or target==player or not nearby(player,target) then return end
 if action=="Hit" then
  if matches[player] or matches[target] then
   if matches[player]==target then remote:FireClient(player,"Notice","Rumble active — combat damage is not implemented yet.") end
   return
  end
  if os.clock()-(lastHit[player] or 0)<COOLDOWN then return end
  lastHit[player]=os.clock()
  -- Meter is earned through validated close-range sparring tags; no damage before consent.
  meters[player]=meters[player] or {}
  meters[player][targetId]=math.min(100,(meters[player][targetId] or 0)+HIT_GAIN)
  update(player,target)
 elseif action=="Challenge" then
  if matches[player] or matches[target] or (state(player))[targetId]~=100 then return end
  if requests[target] then return end
  requests[target]=player
  remote:FireClient(target,"Challenge",player.UserId)
  remote:FireClient(player,"Notice","Rumble request sent.")
  task.delay(15,function()
   if requests[target]==player then
    requests[target]=nil
    if player.Parent==Players then remote:FireClient(player,"Notice","Rumble request expired.") end
   end
  end)
 end
end)
Players.PlayerRemoving:Connect(function(p)
 local opponent=matches[p]
 if opponent then finish(p,opponent,"Opponent left") end
 meters[p]=nil;lastHit[p]=nil;requests[p]=nil
 for target,challenger in pairs(requests) do if challenger==p then requests[target]=nil end end
end)
