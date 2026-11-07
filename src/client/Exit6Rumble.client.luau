-- EXIT 6 provocation HUD. The RECEIVER sees tension caused by each nearby player.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local player=Players.LocalPlayer
local remote=ReplicatedStorage:WaitForChild("Exit6RumbleEvent")
local gui=Instance.new("ScreenGui")
gui.Name="Exit6ConflictHUD";gui.ResetOnSpawn=false;gui.Parent=player:WaitForChild("PlayerGui")
local function button(text,y)
 local b=Instance.new("TextButton")
 b.Size=UDim2.new(0,310,0,46);b.Position=UDim2.new(.5,-155,1,y)
 b.BackgroundColor3=Color3.fromRGB(39,43,52);b.TextColor3=Color3.new(1,1,1)
 b.TextSize=17;b.Font=Enum.Font.GothamBold;b.Text=text;b.Parent=gui
 return b
end
local meter=button("TENSION 0/100",-160);meter.Active=false
local rumble=button("START A RUMBLE",-108);rumble.Visible=false
local cool=button("WALK AWAY / COOL DOWN",-56);cool.Visible=false
local accept=button("ACCEPT RUMBLE",-270);accept.Visible=false
local decline=button("DECLINE",-218);decline.Visible=false
local status=Instance.new("TextLabel")
status.Size=UDim2.new(0,440,0,42);status.Position=UDim2.new(.5,-220,0,60)
status.BackgroundColor3=Color3.fromRGB(24,29,38);status.TextColor3=Color3.new(1,1,1)
status.TextSize=18;status.Text="";status.Parent=gui
local values={}
local incoming=nil
local active=false
local function nearestProvoker()
 local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
 if not root then return nil end
 local best,dist=nil,12
 for _,p in ipairs(Players:GetPlayers()) do
  if p~=player and (values[p.UserId] or 0)>0 then
   local r=p.Character and p.Character:FindFirstChild("HumanoidRootPart")
   if r then
    local d=(r.Position-root.Position).Magnitude
    if d<dist then best,dist=p,d end
   end
  end
 end
 return best
end
local function refresh()
 local target=nearestProvoker()
 meter.Visible=target~=nil and not active
 rumble.Visible=target~=nil and not active and (values[target.UserId] or 0)>=100
 cool.Visible=target~=nil and not active
 if target then meter.Text="TENSION vs "..target.DisplayName.."  "..(values[target.UserId] or 0).."/100" end
end
rumble.Activated:Connect(function() local p=nearestProvoker();if p then remote:FireServer("Challenge",p.UserId) end end)
cool.Activated:Connect(function() local p=nearestProvoker();if p then remote:FireServer("Deescalate",p.UserId) end end)
accept.Activated:Connect(function() if incoming then remote:FireServer("Accept");incoming=nil;accept.Visible=false;decline.Visible=false end end)
decline.Activated:Connect(function() if incoming then remote:FireServer("Decline");incoming=nil;accept.Visible=false;decline.Visible=false end end)
remote.OnClientEvent:Connect(function(kind,a,b,c)
 if kind=="Provocation" then
  values[a]=b
  local p=Players:GetPlayerByUserId(a)
  status.Text=(p and p.DisplayName or "Someone").." — "..tostring(c).." (tension "..b..")"
 elseif kind=="BreakingPoint" then
  status.Text="BREAKING POINT! Choose whether to challenge or walk away."
 elseif kind=="Challenge" then
  incoming=a;accept.Visible=true;decline.Visible=true
  local p=Players:GetPlayerByUserId(a);status.Text=(p and p.DisplayName or "Someone").." wants to rumble."
 elseif kind=="Start" then
  active=true;incoming=nil;accept.Visible=false;decline.Visible=false
  status.Text="RUMBLE STARTED — combat mechanics pending"
 elseif kind=="End" then active=false;status.Text="RUMBLE ENDED: "..tostring(a)
 elseif kind=="Notice" then status.Text=tostring(a) end
 refresh()
end)
task.spawn(function() while gui.Parent do refresh();task.wait(.3) end end)
