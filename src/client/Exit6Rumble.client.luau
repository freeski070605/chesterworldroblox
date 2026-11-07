-- EXIT 6 Rumble v1: nearest-player targeting, keyboard/Xbox buttons and consent prompt.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local ContextActionService=game:GetService("ContextActionService")
local player=Players.LocalPlayer
local remote=ReplicatedStorage:WaitForChild("Exit6RumbleEvent")
local gui=Instance.new("ScreenGui");gui.Name="Exit6RumbleHUD";gui.ResetOnSpawn=false;gui.Parent=player:WaitForChild("PlayerGui")
local function make(name,text,y)
 local b=Instance.new("TextButton");b.Name=name;b.Size=UDim2.new(0,280,0,46);b.Position=UDim2.new(.5,-140,1,y);b.BackgroundColor3=Color3.fromRGB(34,40,51);b.TextColor3=Color3.new(1,1,1);b.TextSize=17;b.Font=Enum.Font.GothamBold;b.Text=text;b.Parent=gui
 return b
end
local meter=make("Meter","RUMBLE 0 / 100",-160);meter.Active=false
local hit=make("Hit","TAG / BUILD RUMBLE",-108)
local challenge=make("Challenge","START A RUMBLE",-56);challenge.Visible=false
local accept=make("Accept","ACCEPT RUMBLE",-265);accept.Visible=false
local decline=make("Decline","DECLINE",-212);decline.Visible=false
local notice=Instance.new("TextLabel");notice.Size=UDim2.new(0,440,0,45);notice.Position=UDim2.new(.5,-220,0,65);notice.BackgroundTransparency=.25;notice.BackgroundColor3=Color3.fromRGB(20,25,34);notice.TextColor3=Color3.new(1,1,1);notice.TextSize=18;notice.Text="";notice.Parent=gui
local progress={} ;local incoming=nil;local fighting=false
local function nearest()
 local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
 if not root then return nil end
 local best,bestDist=nil,11
 for _,other in ipairs(Players:GetPlayers()) do
  if other~=player then
   local r=other.Character and other.Character:FindFirstChild("HumanoidRootPart")
   local h=other.Character and other.Character:FindFirstChildOfClass("Humanoid")
   if r and h and h.Health>0 then
    local d=(root.Position-r.Position).Magnitude
    if d<bestDist then best,bestDist=other,d end
   end
  end
 end
 return best
end
local function refresh()
 local target=nearest()
 meter.Visible=target~=nil and not fighting
 hit.Visible=target~=nil and not fighting
 challenge.Visible=target~=nil and not fighting and (progress[target.UserId] or 0)>=100
 if target then meter.Text="RUMBLE vs "..target.DisplayName.."  "..tostring(progress[target.UserId] or 0).."/100" end
end
hit.Activated:Connect(function() local t=nearest();if t and not fighting then remote:FireServer("Hit",t.UserId) end end)
challenge.Activated:Connect(function() local t=nearest();if t and not fighting then remote:FireServer("Challenge",t.UserId) end end)
accept.Activated:Connect(function() if incoming then remote:FireServer("Accept");incoming=nil;accept.Visible=false;decline.Visible=false end end)
decline.Activated:Connect(function() if incoming then remote:FireServer("Decline");incoming=nil;accept.Visible=false;decline.Visible=false end end)
remote.OnClientEvent:Connect(function(kind,a,b)
 if kind=="Meter" then progress[a]=b
 elseif kind=="Challenge" then
  incoming=a;accept.Visible=true;decline.Visible=true
  local p=Players:GetPlayerByUserId(a);notice.Text=(p and p.DisplayName or "Someone").." challenged you!"
 elseif kind=="Start" then
  fighting=true;incoming=nil;accept.Visible=false;decline.Visible=false
  notice.Text="RUMBLE STARTED — "..tostring(b).." seconds"
 elseif kind=="End" then fighting=false;notice.Text="RUMBLE ENDED: "..tostring(a)
 elseif kind=="Notice" then notice.Text=tostring(a) end
 refresh()
end)
ContextActionService:BindAction("Exit6RumbleTag",function(_,state)
 if state==Enum.UserInputState.Begin and hit.Visible then hit:Activate() end
 return Enum.ContextActionResult.Sink
end,false,Enum.KeyCode.F,Enum.KeyCode.ButtonR2)
ContextActionService:BindAction("Exit6RumbleChallenge",function(_,state)
 if state==Enum.UserInputState.Begin and challenge.Visible then challenge:Activate() end
 return Enum.ContextActionResult.Sink
end,false,Enum.KeyCode.G,Enum.KeyCode.ButtonY)
task.spawn(function() while gui.Parent do refresh();task.wait(.3) end end)
