-- EXIT 6 persistent-world conflict foundation (session state; no forced PvP).
-- Provocation accumulates on the RECEIVER, separately for each instigator.
-- Other server gameplay scripts may use _G.Exit6Conflict.ReportIncident(source, victim, kind).
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local remote=ReplicatedStorage:FindFirstChild("Exit6RumbleEvent") or Instance.new("RemoteEvent")
remote.Name="Exit6RumbleEvent";remote.Parent=ReplicatedStorage
local MAX_DISTANCE=12
local incidentValues={Insult=8,Threat=18,Shove=20,Hit=30,Humiliation=22,Theft=28,Apology=-20,Deescalate=-15}
local state={} -- state[victimUserId][sourceUserId] = {value, lastIncident, breaking}
local requests={}
local matches={}
local function get(victim,source)
 state[victim.UserId]=state[victim.UserId] or {}
 local row=state[victim.UserId]
 row[source.UserId]=row[source.UserId] or {value=0,lastIncident=0,breaking=false}
 return row[source.UserId]
end
local function near(a,b)
 local ca,cb=a.Character,b.Character
 local ra=ca and ca:FindFirstChild("HumanoidRootPart")
 local rb=cb and cb:FindFirstChild("HumanoidRootPart")
 local ha=ca and ca:FindFirstChildOfClass("Humanoid")
 local hb=cb and cb:FindFirstChildOfClass("Humanoid")
 return ra and rb and ha and hb and ha.Health>0 and hb.Health>0 and (ra.Position-rb.Position).Magnitude<=MAX_DISTANCE
end
local function report(source,victim,kind)
 if typeof(source)~="Instance" or typeof(victim)~="Instance" or not source:IsA("Player") or not victim:IsA("Player") then return false end
 if source==victim or source.Parent~=Players or victim.Parent~=Players then return false end
 local change=incidentValues[kind]
 if not change then return false end
 local record=get(victim,source)
 if os.clock()-record.lastIncident<.65 then return false end
 record.lastIncident=os.clock()
 record.value=math.clamp(record.value+change,0,100)
 remote:FireClient(victim,"Provocation",source.UserId,record.value,kind)
 remote:FireClient(source,"Incident",victim.UserId,kind)
 if record.value>=100 and not record.breaking then
  record.breaking=true
  remote:FireClient(victim,"BreakingPoint",source.UserId)
 end
 if record.value<70 then record.breaking=false end
 return true
end
_G.Exit6Conflict={ReportIncident=report,GetProvocation=function(victim,source) return get(victim,source).value end}
local function endMatch(a,b,reason)
 if matches[a]~=b then return end
 matches[a]=nil;matches[b]=nil
 if a.Parent==Players then remote:FireClient(a,"End",reason) end
 if b.Parent==Players then remote:FireClient(b,"End",reason) end
end
remote.OnServerEvent:Connect(function(player,action,targetId)
 if action=="Decline" then
  local challenger=requests[player]
  requests[player]=nil
  if challenger then remote:FireClient(challenger,"Notice","Rumble declined.") end
  return
 end
 if action=="Accept" then
  local challenger=requests[player]
  requests[player]=nil
  if not challenger or matches[player] or matches[challenger] or not near(player,challenger) then return end
  -- Only the provoked party can initiate the rumble.
  if get(challenger,player).value<100 then return end
  matches[player]=challenger;matches[challenger]=player
  remote:FireClient(player,"Start",challenger.UserId,60)
  remote:FireClient(challenger,"Start",player.UserId,60)
  task.delay(60,function() endMatch(player,challenger,"Time up") end)
  return
 end
 if typeof(targetId)~="number" then return end
 local target=Players:GetPlayerByUserId(targetId)
 if not target or target==player or not near(player,target) then return end
 if action=="Challenge" then
  if matches[player] or matches[target] or requests[target] then return end
  if get(player,target).value<100 then return end
  requests[target]=player
  remote:FireClient(target,"Challenge",player.UserId)
  remote:FireClient(player,"Notice","Rumble request sent.")
  task.delay(15,function()
   if requests[target]==player then requests[target]=nil;remote:FireClient(player,"Notice","Challenge expired.") end
  end)
 elseif action=="Deescalate" then
  report(target,player,"Deescalate")
 end
end)
Players.PlayerRemoving:Connect(function(player)
 local opponent=matches[player]
 if opponent then endMatch(player,opponent,"Opponent left") end
 state[player.UserId]=nil;requests[player]=nil
 for _,row in pairs(state) do row[player.UserId]=nil end
 for target,challenger in pairs(requests) do if challenger==player then requests[target]=nil end end
end)
