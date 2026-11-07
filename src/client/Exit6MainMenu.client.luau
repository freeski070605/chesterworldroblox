-- EXIT 6 main menu, client-side. Does not modify the city or spawn system.
local Players=game:GetService("Players")
local GuiService=game:GetService("GuiService")
local UserInputService=game:GetService("UserInputService")
local TweenService=game:GetService("TweenService")
local RunService=game:GetService("RunService")
local Workspace=game:GetService("Workspace")
local player=Players.LocalPlayer
local gui=Instance.new("ScreenGui")
gui.Name="Exit6MainMenu";gui.IgnoreGuiInset=true;gui.ResetOnSpawn=false;gui.DisplayOrder=900;gui.Parent=player:WaitForChild("PlayerGui")
local function new(class,props,parent)
 local obj=Instance.new(class)
 for k,v in pairs(props) do obj[k]=v end
 obj.Parent=parent
 return obj
end
local bg=new("Frame",{Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.fromRGB(11,15,23),BorderSizePixel=0},gui)
-- dark behind the menu, clearing to the right so the city flythrough shows
new("UIGradient",{Rotation=0,Color=ColorSequence.new(Color3.fromRGB(12,18,29),Color3.fromRGB(39,36,32)),
 Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.05),NumberSequenceKeypoint.new(0.45,0.25),NumberSequenceKeypoint.new(1,0.9)})},bg)
local stripe=new("Frame",{Size=UDim2.new(0,7,1,0),Position=UDim2.fromScale(.08,0),BackgroundColor3=Color3.fromRGB(229,157,53),BorderSizePixel=0},bg)
local content=new("Frame",{AnchorPoint=Vector2.new(0,.5),Position=UDim2.fromScale(.13,.5),Size=UDim2.new(.72,0,.85,0),BackgroundTransparency=1},bg)
new("UISizeConstraint",{MaxSize=Vector2.new(820,800)},content)
new("TextLabel",{Size=UDim2.new(1,0,0,92),BackgroundTransparency=1,Text="EXIT 6",TextColor3=Color3.fromRGB(245,244,240),Font=Enum.Font.GothamBlack,TextScaled=true,TextXAlignment=Enum.TextXAlignment.Left},content)
new("TextLabel",{Position=UDim2.new(0,0,0,90),Size=UDim2.new(1,0,0,35),BackgroundTransparency=1,Text="MAKE IT OUT  /  CHESTER, PENNSYLVANIA",TextColor3=Color3.fromRGB(229,157,53),Font=Enum.Font.GothamBold,TextScaled=true,TextXAlignment=Enum.TextXAlignment.Left},content)
local buttons={}
-- compact enough for a 720p TV / short Studio window: 4 buttons + footer under them
local page=new("Frame",{Position=UDim2.new(0,0,0,142),Size=UDim2.new(1,0,0,240),BackgroundTransparency=1},content)
local footer=new("TextLabel",{Position=UDim2.new(0,0,0,142+4*58+6),Size=UDim2.new(1,0,0,30),BackgroundTransparency=1,Text="A / ENTER  SELECT     B / BACKSPACE  BACK",TextColor3=Color3.fromRGB(155,164,177),Font=Enum.Font.Gotham,TextSize=15,TextXAlignment=Enum.TextXAlignment.Left},content)
local current="main"
local function clear()
 for _,child in ipairs(page:GetChildren()) do child:Destroy() end
 table.clear(buttons)
end
local function button(label,index,callback)
 local b=new("TextButton",{Name=label,Position=UDim2.new(0,0,0,(index-1)*58),Size=UDim2.new(.75,0,0,50),BackgroundColor3=Color3.fromRGB(37,44,56),Text=label,TextColor3=Color3.fromRGB(245,245,245),Font=Enum.Font.GothamBold,TextSize=23,AutoButtonColor=true,Selectable=true},page)
 new("UICorner",{CornerRadius=UDim.new(0,8)},b)
 b.Activated:Connect(callback)
 table.insert(buttons,b)
 return b
end
local showMain
local function detail(title,lines)
 current="detail";clear()
 new("TextLabel",{Size=UDim2.new(1,0,0,55),BackgroundTransparency=1,Text=title,Font=Enum.Font.GothamBold,TextSize=28,TextColor3=Color3.fromRGB(229,157,53),TextXAlignment=Enum.TextXAlignment.Left},page)
 new("TextLabel",{Position=UDim2.new(0,0,0,58),Size=UDim2.new(.95,0,0,112),BackgroundTransparency=1,Text=lines,TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top,Font=Enum.Font.Gotham,TextSize=19,TextColor3=Color3.fromRGB(240,240,240),TextXAlignment=Enum.TextXAlignment.Left},page)
 button("BACK",4,showMain)
 GuiService.SelectedObject=buttons[1]
end
local entered=false
local function play()
 if entered then return end
 entered=true
 current="playing"
 GuiService.SelectedObject=nil
 local fade=TweenService:Create(bg,TweenInfo.new(.4),{BackgroundTransparency=1})
 fade:Play()
 for _,v in ipairs(bg:GetDescendants()) do
  if v:IsA("TextLabel") or v:IsA("TextButton") then
   TweenService:Create(v,TweenInfo.new(.35),{TextTransparency=1,BackgroundTransparency=1}):Play()
  elseif v:IsA("Frame") then
   TweenService:Create(v,TweenInfo.new(.35),{BackgroundTransparency=1}):Play()
  end
 end
 fade.Completed:Wait()
 gui:Destroy()
 player:SetAttribute("Exit6EnteredCity",true)
end
showMain=function()
 current="main";clear()
 button("PLAY  /  ENTER CHESTER",1,play)
 button("SETTINGS",2,function()
  detail("SETTINGS","Camera, audio, and graphics options are coming soon. Use Roblox's in-game settings for now.")
 end)
 button("CONTROLS",3,function()
  detail("CONTROLS","Xbox: Left stick move  •  Right stick camera  •  L3 sprint  •  A jump/select  •  B back\nPC: WASD move  •  Mouse camera  •  Shift sprint  •  Enter select  •  Esc back")
 end)
 button("CREDITS",4,function()
  detail("CREDITS","EXIT 6  |  MAKE IT OUT\nA DFB Solutions production\nInspired by Chester, Pennsylvania\nCurrently in development")
 end)
 GuiService.SelectedObject=buttons[1]
end
-- Other HUDs (location banner, inspector, EXIT 6 cash panel, Hide HUD
-- button) wait behind the menu until Play.
local hidden={}
local function hideGui(g)
 -- (Freecam is Roblox's own developer camera GUI: leave it alone)
 if g~=gui and g:IsA("ScreenGui") and g.Name~="Exit6Loading" and g.Name~="Freecam" and g.Enabled then
  g.Enabled=false
  hidden[g]=true
 end
end
local playerGui=player:WaitForChild("PlayerGui")
for _,g in ipairs(playerGui:GetChildren()) do hideGui(g) end
local hideConn=playerGui.ChildAdded:Connect(function(g) if not entered then task.defer(hideGui,g) end end)
-- some HUD scripts switch their own GUI back on (inspector): keep them off
task.spawn(function()
 while not entered do
  for _,g in ipairs(playerGui:GetChildren()) do hideGui(g) end
  task.wait(0.3)
 end
end)

-- Cinematic flythrough behind the menu once the city is built: the Barry
-- Bridge, 9th & Kerlin, Kerlin St to the Sunoco pylon, the NEC viaduct.
-- Each shot asks Roblox to stream its area in first (StreamingEnabled).
local BARRY=Vector3.new(2748,190,10226)   -- the truss main span over the Delaware
local ALONG,ACROSS=Vector3.new(0.63,0,0.776),Vector3.new(0.776,0,-0.63)
-- (opens near spawn, which is streamed already; the Barry Bridge model is
-- Persistent - LandmarkBuilder - so it is always there)
local SHOTS={
 {focus=Vector3.new(2780,58,1500),from=Vector3.new(2960,150,1660),to=Vector3.new(2600,130,1680),time=13},
 -- close in: the city's atmosphere hazes anything ~500 studs off to grey
 {focus=BARRY,from=BARRY-ALONG*260+ACROSS*160+Vector3.new(0,10,0),to=BARRY+ALONG*260+ACROSS*160+Vector3.new(0,40,0),time=16},
 {focus=Vector3.new(2780,62,1505),from=Vector3.new(2690,64,1285),to=Vector3.new(2745,64,1390),time=11},
 {focus=Vector3.new(6150,40,1210),from=Vector3.new(6010,80,990),to=Vector3.new(6230,95,1000),time=13},
}
local cinematic=true
local camera=Workspace.CurrentCamera
task.spawn(function()
 while Workspace:GetAttribute("CW_HighwayFinishComplete")~=true and cinematic do task.wait(0.5) end
 local i=0
 while cinematic do
  i=i%#SHOTS+1
  local shot=SHOTS[i]
  pcall(function() player:RequestStreamAroundAsync(shot.focus,6) end)
  if not cinematic then break end
  camera.CameraType=Enum.CameraType.Scriptable
  local t0=os.clock()
  while cinematic and os.clock()-t0<shot.time do
   local a=(os.clock()-t0)/shot.time
   a=a*a*(3-2*a)
   camera.CFrame=CFrame.lookAt(shot.from:Lerp(shot.to,a),shot.focus)
   RunService.RenderStepped:Wait()
  end
 end
end)
local function endCinematic()
 cinematic=false
 camera.CameraType=Enum.CameraType.Custom
 local character=player.Character
 local humanoid=character and character:FindFirstChildOfClass("Humanoid")
 if humanoid then camera.CameraSubject=humanoid end
 hideConn:Disconnect()
 for g in pairs(hidden) do if g.Parent then g.Enabled=true end end
 table.clear(hidden)
end
player:GetAttributeChangedSignal("Exit6EnteredCity"):Connect(function()
 if player:GetAttribute("Exit6EnteredCity") then endCinematic() end
end)
showMain()
UserInputService.InputBegan:Connect(function(input,processed)
 if current=="playing" then return end
 -- (Esc is Roblox's own menu on PC)
 if input.KeyCode==Enum.KeyCode.ButtonB or input.KeyCode==Enum.KeyCode.Backspace then
  if current=="detail" then showMain() end
 end
end)
-- Prevent character movement while menu is open; restore after Play.
local controls
pcall(function()
 local playerModule=require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
 controls=playerModule:GetControls()
 controls:Disable()
end)
player:GetAttributeChangedSignal("Exit6EnteredCity"):Connect(function()
 if player:GetAttribute("Exit6EnteredCity") and controls then controls:Enable() end
end)
