-- Exit 6 Bike Life: server-owned neighborhood rideouts and wheelie scoring.
-- No client-supplied cash, scores, vehicle ownership, or coordinates are trusted.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Catalog=require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Exit6Catalog"))
local Profile=require(script.Parent:WaitForChild("Exit6Profile"))
local remotes=ReplicatedStorage:WaitForChild("Exit6Remotes")
local action=Instance.new("RemoteFunction")
action.Name="BikeLifeAction"
action.Parent=remotes
local changed=Instance.new("RemoteEvent")
changed.Name="BikeLifeChanged"
changed.Parent=remotes

local rides={} -- leader userId -> {leader, members, waypoint, started, best, score}
local current={} -- userId -> leader userId
local cooldown={}
local checkpoints={
    {name="9th & Kerlin",pos=Vector3.new(2810,61,1519)},
    {name="9th & Concord",pos=Vector3.new(3040,61,1690)},
    {name="9th & Lincoln",pos=Vector3.new(2400,61,1430)},
}
local function locationFor(player)
    local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    return root and root.Position
end
local function getRide(player)
    local key=current[player.UserId]
    return key and rides[key]
end
local function count(ride)
    local n=0
    for _ in pairs(ride.members) do n+=1 end
    return n
end
local function status(player)
    local mine=getRide(player)
    local open={}
    for leaderId,ride in pairs(rides) do
        if not ride.started then
            table.insert(open,{leaderId=leaderId,leaderName=ride.leader.DisplayName,
                riders=count(ride),meet=checkpoints[ride.waypoint].name})
        end
    end
    table.sort(open,function(a,b)return a.leaderId<b.leaderId end)
    if not mine then return {mine=nil,open=open} end
    return {mine={leaderId=mine.leader.UserId,leaderName=mine.leader.DisplayName,
        riders=count(mine),started=mine.started,meet=checkpoints[mine.waypoint].name,
        meetPos=checkpoints[mine.waypoint].pos,
        score=math.floor(mine.score),best=math.floor(mine.best)},open=open}
end
local function emit()
    for _,player in ipairs(Players:GetPlayers()) do changed:FireClient(player,status(player)) end
end
local function drop(player)
    local ride=getRide(player)
    if not ride then return end
    ride.members[player.UserId]=nil
    current[player.UserId]=nil
    if player == ride.leader or count(ride)==0 then
        for uid in pairs(ride.members) do current[uid]=nil end
        rides[ride.leader.UserId]=nil
    end
    emit()
end
action.OnServerInvoke=function(player,command,value)
    if type(command)~="string" then return status(player) end
    if command=="status" then return status(player) end
    local now=os.clock()
    if cooldown[player] and now-cooldown[player]<1.25 then return status(player) end
    cooldown[player]=now
    if command=="buy" and type(value)=="string" then
        local item=Catalog.Items[value]
        local spec=item and Catalog.Vehicles[item.model]
        local prof=Profile.Get(player)
        local stats=player:FindFirstChild("leaderstats")
        local cash=stats and stats:FindFirstChild("Chester Cash")
        local rep=stats and stats:FindFirstChild("Reputation")
        if player:GetAttribute("Exit6DataReady")==true and item and spec and spec.rideType
            and item.kind=="vehicle" and prof and cash and rep then
            if prof.vehicles[item.model] then
                player:SetAttribute("Exit6Notice","You already own this ride.")
            elseif item.repRequired and rep.Value<item.repRequired then
                player:SetAttribute("Exit6Notice","Requires "..item.repRequired.." reputation.")
            elseif cash.Value<item.price then
                player:SetAttribute("Exit6Notice","Not enough Chester Cash.")
            else
                cash.Value-=item.price
                prof.vehicles[item.model]={fuel=spec.tank,paint=1}
                prof.active=item.model
                Profile.Publish(player)
                player:SetAttribute("Exit6Notice","Bought "..spec.name.."! Call it from Car.")
            end
            player:SetAttribute("Exit6NoticeId",(player:GetAttribute("Exit6NoticeId") or 0)+1)
        end
    if command=="paint" and type(value)=="table" then
        local id=type(value.model)=="string" and value.model or ""
        local spec=Catalog.Vehicles[id]
        local color=tonumber(value.color)
        local prof=Profile.Get(player)
        local stats=player:FindFirstChild("leaderstats")
        local cash=stats and stats:FindFirstChild("Chester Cash")
        if player:GetAttribute("Exit6DataReady")==true and spec and spec.rideType
            and prof and prof.vehicles[id] and color and color%1==0 and color>=1 and color<=8
            and cash and cash.Value>=100 then
            cash.Value-=100
            prof.vehicles[id].paint=color
            Profile.Publish(player)
            player:SetAttribute("Exit6Notice","Custom paint saved ($100). Re-call your ride to apply.")
            player:SetAttribute("Exit6NoticeId",(player:GetAttribute("Exit6NoticeId") or 0)+1)
        end
    if command=="create" and not getRide(player) and #Players:GetPlayers()>0 then
        local i=math.clamp(math.floor(tonumber(value) or 1),1,#checkpoints)
        rides[player.UserId]={leader=player,members={[player.UserId]=true},
            waypoint=i,started=false,score=0,best=0}
        current[player.UserId]=player.UserId
    elseif command=="join" and not getRide(player) then
        local id=tonumber(value)
        local ride=id and rides[id]
        if ride and not ride.started and count(ride)<12 then
            ride.members[player.UserId]=true
            current[player.UserId]=id
        end
    elseif command=="leave" then
        drop(player)
    elseif command=="start" then
        local ride=getRide(player)
        if ride and ride.leader==player and not ride.started then
            local pos=locationFor(player)
            if pos and (pos-checkpoints[ride.waypoint].pos).Magnitude<400 then
                ride.started=true
            end
        end
    elseif command=="finish" then
        local ride=getRide(player)
        if ride and ride.leader==player and ride.started then drop(player) end
    end
    emit()
    return status(player)
end
local elapsed=0
RunService.Heartbeat:Connect(function(dt)
    elapsed+=dt
    if elapsed<0.25 then return end
    local step=math.min(elapsed,0.5)
    elapsed=0
    for _,ride in pairs(rides) do
        if ride.started then
            for uid in pairs(ride.members) do
                local player=Players:GetPlayerByUserId(uid)
                local hum=player and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
                local seat=hum and hum.SeatPart
                local vehicle=seat and seat.Parent
                if seat and seat:IsA("VehicleSeat") and vehicle and vehicle:GetAttribute("Exit6BikeLife")
                    and vehicle:GetAttribute("Owner")==uid and vehicle.PrimaryPart then
                    local chassis=vehicle.PrimaryPart
                    local speed=chassis.AssemblyLinearVelocity.Magnitude
                    local pitch=chassis.CFrame.LookVector.Y
                    -- Score only actually moving, front-elevated owned rides.
                    if speed>12 and speed<145 and pitch>0.11 and pitch<0.7 then
                        local points=step*(1+math.min(3,pitch*4))
                        ride.score+=points
                        ride.best=math.max(ride.best,ride.score)
                        player:SetAttribute("BikeLifeWheelieScore",math.floor(ride.score))
                    end
                end
            end
        end
    end
end)
Players.PlayerRemoving:Connect(function(player)
    drop(player)
    cooldown[player]=nil
end)
print("[Exit6 Bike Life] rideout server ready")
