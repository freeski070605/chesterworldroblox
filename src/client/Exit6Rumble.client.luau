-- EXIT 6 provocation HUD. The RECEIVER sees tension caused by each nearby player.
-- Social actions (what you do to the nearest player), the consent challenge and
-- the rumble itself; every outcome is decided by Exit6Rumble.server.
--   near a player   T / DPad-Left  talk trash    G / DPad-Right  shove
--                   Y              apologize     C / DPad-Down   walk away (cool down), or apologize
--                                                                 when nobody has provoked you
--   tension 100     R / ButtonY    start a rumble (challenge)
--   challenged      R / ButtonY    accept        X-key / ButtonB decline
--   rumble          Click / R2     punch         Q / L2 (hold)   block
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local ContextActionService=game:GetService("ContextActionService")
local Workspace=game:GetService("Workspace")
local player=Players.LocalPlayer
local remote=ReplicatedStorage:WaitForChild("Exit6RumbleEvent")
local gui=Instance.new("ScreenGui")
gui.Name="Exit6ConflictHUD";gui.ResetOnSpawn=false;gui.Parent=player:WaitForChild("PlayerGui")
local function button(text,y)
 local b=Instance.new("TextButton")
 b.Size=UDim2.new(0,310,0,46);b.Position=UDim2.new(.5,-155,1,y)
 b.BackgroundColor3=Color3.fromRGB(39,43,52);b.TextColor3=Color3.new(1,1,1)
 b.TextSize=17;b.Font=Enum.Font.GothamBold;b.Text=text;b.Parent=gui
 local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,8);c.Parent=b
 return b
end
local meter=button("TENSION 0/100",-160);meter.Active=false;meter.Selectable=false;meter.AutoButtonColor=false
local rumble=button("START A RUMBLE  [R / Y]",-108);rumble.Visible=false
local cool=button("WALK AWAY / COOL DOWN  [C]",-56);cool.Visible=false
local accept=button("ACCEPT RUMBLE  [R / Y]",-270);accept.Visible=false
local decline=button("DECLINE  [X / B]",-218);decline.Visible=false
-- social bar: shown with any player in arm's reach
local social=Instance.new("TextLabel")
social.Size=UDim2.new(0,620,0,30);social.Position=UDim2.new(.5,-310,1,-196)
social.BackgroundColor3=Color3.fromRGB(18,21,27);social.BackgroundTransparency=.2;social.TextColor3=Color3.fromRGB(229,157,53)
social.TextSize=15;social.Font=Enum.Font.GothamMedium;social.Visible=false;social.Parent=gui
local sc=Instance.new("UICorner");sc.CornerRadius=UDim.new(0,8);sc.Parent=social
-- status line under the location banner and the job HUD; hidden when empty
local status=Instance.new("TextLabel")
status.Size=UDim2.new(0,440,0,38);status.Position=UDim2.new(.5,-220,0,178)
status.BackgroundColor3=Color3.fromRGB(24,29,38);status.BackgroundTransparency=.1;status.TextColor3=Color3.new(1,1,1)
status.TextSize=17;status.Font=Enum.Font.GothamBold;status.Text="";status.Visible=false;status.Parent=gui
local stc=Instance.new("UICorner");stc.CornerRadius=UDim.new(0,8);stc.Parent=status
local statusId=0
local function say(text,seconds)
 statusId+=1
 local id=statusId
 status.Text=text;status.Visible=text~=""
 if seconds then task.delay(seconds,function() if statusId==id then status.Visible=false end end) end
end
-- rumble HUD: both health bars and the clock
local fight=Instance.new("Frame")
fight.Size=UDim2.new(0,520,0,64);fight.Position=UDim2.new(.5,-260,1,-150)
fight.BackgroundColor3=Color3.fromRGB(18,21,27);fight.BackgroundTransparency=.1;fight.Visible=false;fight.Parent=gui
local fc=Instance.new("UICorner");fc.CornerRadius=UDim.new(0,10);fc.Parent=fight
local function bar(x,align)
 local back=Instance.new("Frame");back.Size=UDim2.new(.42,0,0,14);back.Position=UDim2.new(x,0,0,36)
 back.BackgroundColor3=Color3.fromRGB(60,30,30);back.BorderSizePixel=0;back.Parent=fight
 local fill=Instance.new("Frame");fill.Size=UDim2.fromScale(1,1);fill.AnchorPoint=Vector2.new(align,0);fill.Position=UDim2.fromScale(align,0)
 fill.BackgroundColor3=Color3.fromRGB(229,157,53);fill.BorderSizePixel=0;fill.Parent=back
 local name=Instance.new("TextLabel");name.BackgroundTransparency=1;name.Size=UDim2.new(.42,0,0,22);name.Position=UDim2.new(x,0,0,8)
 name.TextColor3=Color3.new(1,1,1);name.Font=Enum.Font.GothamBold;name.TextSize=15
 name.TextXAlignment=align==0 and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right;name.Parent=fight
 return fill,name
end
local myBar,myName=bar(.04,0)
local theirBar,theirName=bar(.54,1)
local clock=Instance.new("TextLabel");clock.BackgroundTransparency=1;clock.Size=UDim2.new(.12,0,0,30);clock.Position=UDim2.new(.44,0,0,8)
clock.TextColor3=Color3.fromRGB(229,157,53);clock.Font=Enum.Font.GothamBlack;clock.TextSize=20;clock.Parent=fight
local values={}
local incoming=nil
local active=false
local opponent=nil
local endsAt=0
local function root(p)
 return p.Character and p.Character:FindFirstChild("HumanoidRootPart")
end
local function nearestPlayer(range,needTension)
 local me=root(player)
 if not me then return nil end
 local best,dist=nil,range
 for _,p in ipairs(Players:GetPlayers()) do
  if p~=player and (not needTension or (values[p.UserId] or 0)>0) then
   local r=root(p)
   if r then
    local d=(r.Position-me.Position).Magnitude
    if d<dist then best,dist=p,d end
   end
  end
 end
 return best
end
local function nearestProvoker() return nearestPlayer(12,true) end
local function refresh()
 local target=nearestProvoker()
 meter.Visible=target~=nil and not active
 rumble.Visible=target~=nil and not active and (values[target.UserId] or 0)>=100
 cool.Visible=target~=nil and not active
 if target then meter.Text="TENSION vs "..target.DisplayName.."  "..(values[target.UserId] or 0).."/100" end
 local other=not active and nearestPlayer(9,false)
 social.Visible=other~=nil and other~=false
 if social.Visible then
  social.Text=other.DisplayName..":  [T / ◀] talk trash   [G / ▶] shove   [Y / ▼] apologize   [V / R1] dap"
 end
 fight.Visible=active
 if active then clock.Text=tostring(math.max(0,math.ceil(endsAt-os.clock()))) end
 -- tells tester flight (DebugFlight) to leave the shared buttons alone
 local context=(active and "rumble") or (incoming and "challenge") or ((social.Visible or meter.Visible) and "social") or nil
 if player:GetAttribute("Exit6Context")~=context then player:SetAttribute("Exit6Context",context) end
end
local function challenge() local p=nearestProvoker();if p and (values[p.UserId] or 0)>=100 then remote:FireServer("Challenge",p.UserId) end end
local function coolDown() local p=nearestProvoker();if p then remote:FireServer("Deescalate",p.UserId) end end
local function answer(yes)
 if not incoming then return end
 remote:FireServer(yes and "Accept" or "Decline");incoming=nil;accept.Visible=false;decline.Visible=false
end
rumble.Activated:Connect(challenge)
cool.Activated:Connect(coolDown)
accept.Activated:Connect(function() answer(true) end)
decline.Activated:Connect(function() answer(false) end)

-- keyboard / gamepad
local function bind(name,fn,...)
 ContextActionService:BindAction(name,function(_,state)
  if state~=Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
  if player.PlayerGui:FindFirstChild("Exit6MainMenu") then return Enum.ContextActionResult.Pass end
  if fn()==false then return Enum.ContextActionResult.Pass end
  return Enum.ContextActionResult.Sink
 end,false,...)
end
local function socialAct(kind)
 return function()
  if active then return false end
  local p=nearestPlayer(9,false)
  if not p then return false end
  remote:FireServer(kind,p.UserId)
 end
end
bind("Exit6Insult",socialAct("Insult"),Enum.KeyCode.T,Enum.KeyCode.DPadLeft)
bind("Exit6Shove",socialAct("Shove"),Enum.KeyCode.G,Enum.KeyCode.DPadRight)
bind("Exit6Apology",socialAct("Apology"),Enum.KeyCode.Y)
bind("Exit6Dap",socialAct("Dap"),Enum.KeyCode.V,Enum.KeyCode.ButtonR1)
local apologize=socialAct("Apology")
bind("Exit6CoolDown",function()
 if active then return false end
 if nearestProvoker() then coolDown() return end
 -- nobody has provoked you: the same button apologizes to whoever is near
 return apologize()
end,Enum.KeyCode.C,Enum.KeyCode.DPadDown)
bind("Exit6RumbleYes",function()
 if incoming then answer(true) return end
 if active or not rumble.Visible then return false end
 challenge()
end,Enum.KeyCode.R,Enum.KeyCode.ButtonY)
bind("Exit6RumbleNo",function() if not incoming then return false end answer(false) end,Enum.KeyCode.X,Enum.KeyCode.ButtonB)
-- rumble controls exist only while a rumble is on
local function setFightControls(on)
 if on then
  ContextActionService:BindAction("Exit6Punch",function(_,state)
   if state==Enum.UserInputState.Begin then remote:FireServer("Punch") end
   return Enum.ContextActionResult.Sink
  end,false,Enum.UserInputType.MouseButton1,Enum.KeyCode.ButtonR2)
  ContextActionService:BindAction("Exit6Block",function(_,state)
   if state==Enum.UserInputState.Begin then remote:FireServer("Block",true)
   elseif state==Enum.UserInputState.End or state==Enum.UserInputState.Cancel then remote:FireServer("Block",false) end
   return Enum.ContextActionResult.Sink
  end,false,Enum.KeyCode.Q,Enum.KeyCode.ButtonL2)
 else
  ContextActionService:UnbindAction("Exit6Punch")
  ContextActionService:UnbindAction("Exit6Block")
 end
end
local function knock(dir,speed)
 local r=root(player)
 if r then r.AssemblyLinearVelocity=r.AssemblyLinearVelocity+dir*speed+Vector3.new(0,speed*.35,0) end
end
remote.OnClientEvent:Connect(function(kind,a,b,c,d,e)
 if kind=="Provocation" then
  values[a]=b
  local p=Players:GetPlayerByUserId(a)
  say((p and p.DisplayName or "Someone").." - "..tostring(c).." (tension "..b..")",4)
 elseif kind=="Incident" then
  local p=Players:GetPlayerByUserId(a)
  say("You: "..tostring(b).." -> "..(p and p.DisplayName or "someone"),2)
 elseif kind=="BreakingPoint" then
  say("BREAKING POINT! [R] challenge them or [C] walk away.",6)
 elseif kind=="Challenge" then
  incoming=a;accept.Visible=true;decline.Visible=true
  local p=Players:GetPlayerByUserId(a);say((p and p.DisplayName or "Someone").." wants to rumble.",15)
 elseif kind=="Start" then
  active=true;incoming=nil;accept.Visible=false;decline.Visible=false
  opponent=Players:GetPlayerByUserId(a);endsAt=os.clock()+(b or 60)
  myName.Text=player.DisplayName.."  100";theirName.Text="100  "..(opponent and opponent.DisplayName or "?")
  myBar.Size=UDim2.fromScale(1,1);theirBar.Size=UDim2.fromScale(1,1)
  setFightControls(true)
  say("RUMBLE!  Click / R2 punch   Q / L2 block",4)
 elseif kind=="Hit" then
  myBar.Size=UDim2.fromScale(b/100,1);myName.Text=player.DisplayName.."  "..b
  if typeof(e)=="Vector3" then knock(e,d and 6 or 18) end
 elseif kind=="Landed" then
  theirBar.Size=UDim2.fromScale(b/100,1);theirName.Text=b.."  "..(opponent and opponent.DisplayName or "?")
 elseif kind=="Shoved" then
  if typeof(b)=="Vector3" then knock(b,32) end
 elseif kind=="End" then
  if opponent then values[opponent.UserId]=nil end
  active=false;opponent=nil;setFightControls(false)
  say("RUMBLE OVER: "..tostring(a),6)
 elseif kind=="Notice" then say(tostring(a),4) end
 refresh()
end)
task.spawn(function() while gui.Parent do refresh();task.wait(.3) end end)
