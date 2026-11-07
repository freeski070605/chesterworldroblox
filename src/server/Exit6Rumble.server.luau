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
-- rumble combat (session only; rumble HP is separate from Humanoid health,
-- nobody dies): hp[player], blocking[player], last punch / social action times
local RUMBLE_SECONDS=60
local PUNCH_RANGE=7
local PUNCH_COOLDOWN=.55
local PUNCH_DAMAGE={7,12}
local BLOCK_FACTOR=.3
local WIN_REPUTATION=2
local SOCIAL_COOLDOWN=1.5
local hp,blocking,lastPunch,lastSocial={},{},{},{}
local matchToken={} -- a rematch must not be ended by the previous match's timer
local rng=Random.new()
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
 -- winner: knockout, or more rumble HP left when time is up
 local ha,hb=hp[a] or 0,hp[b] or 0
 local winner=(reason~="Opponent left" and ha~=hb) and (ha>hb and a or b) or nil
 if reason=="Opponent left" then winner=b end -- PlayerRemoving passes the leaver as a
 hp[a],hp[b],blocking[a],blocking[b]=nil,nil,nil,nil
 if winner and winner.Parent==Players then
  local ls=winner:FindFirstChild("leaderstats")
  local rep=ls and ls:FindFirstChild("Reputation")
  if rep then rep.Value+=WIN_REPUTATION end
 end
 -- settled: the tension between the two is spent
 if state[a.UserId] then state[a.UserId][b.UserId]=nil end
 if state[b.UserId] then state[b.UserId][a.UserId]=nil end
 local text=reason..(winner and (" - "..winner.DisplayName.." wins") or " - draw")
 if a.Parent==Players then remote:FireClient(a,"End",text,winner and winner.UserId or 0) end
 if b.Parent==Players then remote:FireClient(b,"End",text,winner and winner.UserId or 0) end
end
local function punch(attacker)
 local target=matches[attacker]
 if not target or not near(attacker,target) then return end
 local ra=attacker.Character.HumanoidRootPart
 local rb=target.Character.HumanoidRootPart
 if (ra.Position-rb.Position).Magnitude>PUNCH_RANGE then return end
 local now=os.clock()
 if lastPunch[attacker] and now-lastPunch[attacker]<PUNCH_COOLDOWN then return end
 lastPunch[attacker]=now
 if blocking[attacker] then return end
 local dmg=rng:NextInteger(PUNCH_DAMAGE[1],PUNCH_DAMAGE[2])
 if blocking[target] then dmg=math.max(1,math.floor(dmg*BLOCK_FACTOR)) end
 hp[target]=math.max(0,(hp[target] or 100)-dmg)
 local dir=(rb.Position-ra.Position)*Vector3.new(1,0,1)
 dir=dir.Magnitude>0 and dir.Unit or Vector3.zAxis
 remote:FireClient(target,"Hit",attacker.UserId,hp[target],dmg,blocking[target]==true,dir)
 remote:FireClient(attacker,"Landed",target.UserId,hp[target],dmg,blocking[target]==true)
 if hp[target]<=0 then endMatch(attacker,target,"Knockout") end
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
  hp[player],hp[challenger]=100,100
  remote:FireClient(player,"Start",challenger.UserId,RUMBLE_SECONDS)
  remote:FireClient(challenger,"Start",player.UserId,RUMBLE_SECONDS)
  local token={}
  matchToken[player]=token
  task.delay(RUMBLE_SECONDS,function()
   if matchToken[player]==token then endMatch(player,challenger,"Time up") end
  end)
  return
 end
 if action=="Punch" then punch(player) return end
 if action=="Block" then blocking[player]=matches[player]~=nil and targetId==true or nil return end
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
 elseif action=="Insult" or action=="Shove" or action=="Apology" then
  -- what a player does to another: it builds (or cools) the OTHER player's tension
  if matches[player] then return end
  local now=os.clock()
  if lastSocial[player] and now-lastSocial[player]<SOCIAL_COOLDOWN then return end
  lastSocial[player]=now
  if report(player,target,action) and action=="Shove" then
   local dir=(target.Character.HumanoidRootPart.Position-player.Character.HumanoidRootPart.Position)*Vector3.new(1,0,1)
   remote:FireClient(target,"Shoved",player.UserId,dir.Magnitude>0 and dir.Unit or Vector3.zAxis)
  end
 end
end)
Players.PlayerRemoving:Connect(function(player)
 local opponent=matches[player]
 if opponent then endMatch(player,opponent,"Opponent left") end
 state[player.UserId]=nil;requests[player]=nil
 hp[player],blocking[player],lastPunch[player],lastSocial[player]=nil,nil,nil,nil
 for _,row in pairs(state) do row[player.UserId]=nil end
 for target,challenger in pairs(requests) do if challenger==player then requests[target]=nil end end
end)
