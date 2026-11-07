-- EXIT 6 main menu, client-side. Does not modify the city or spawn system.
local Players=game:GetService("Players")
local GuiService=game:GetService("GuiService")
local UserInputService=game:GetService("UserInputService")
local TweenService=game:GetService("TweenService")
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
new("UIGradient",{Rotation=25,Color=ColorSequence.new(Color3.fromRGB(12,18,29),Color3.fromRGB(39,36,32))},bg)
local stripe=new("Frame",{Size=UDim2.new(0,7,1,0),Position=UDim2.fromScale(.08,0),BackgroundColor3=Color3.fromRGB(229,157,53),BorderSizePixel=0},bg)
local content=new("Frame",{AnchorPoint=Vector2.new(0,.5),Position=UDim2.fromScale(.13,.5),Size=UDim2.new(.72,0,.85,0),BackgroundTransparency=1},bg)
new("UISizeConstraint",{MaxSize=Vector2.new(820,800)},content)
new("TextLabel",{Size=UDim2.new(1,0,0,92),BackgroundTransparency=1,Text="EXIT 6",TextColor3=Color3.fromRGB(245,244,240),Font=Enum.Font.GothamBlack,TextScaled=true,TextXAlignment=Enum.TextXAlignment.Left},content)
new("TextLabel",{Position=UDim2.new(0,0,0,90),Size=UDim2.new(1,0,0,35),BackgroundTransparency=1,Text="MAKE IT OUT  /  CHESTER, PENNSYLVANIA",TextColor3=Color3.fromRGB(229,157,53),Font=Enum.Font.GothamBold,TextScaled=true,TextXAlignment=Enum.TextXAlignment.Left},content)
local buttons={}
local page=new("Frame",{Position=UDim2.new(0,0,0,165),Size=UDim2.new(1,0,0,330),BackgroundTransparency=1},content)
local footer=new("TextLabel",{AnchorPoint=Vector2.new(0,1),Position=UDim2.new(0,0,1,0),Size=UDim2.new(1,0,0,30),BackgroundTransparency=1,Text="A / ENTER  SELECT     B / ESC  BACK",TextColor3=Color3.fromRGB(155,164,177),Font=Enum.Font.Gotham,TextSize=15,TextXAlignment=Enum.TextXAlignment.Left},content)
local current="main"
local function clear()
 for _,child in ipairs(page:GetChildren()) do child:Destroy() end
 table.clear(buttons)
end
local function button(label,index,callback)
 local b=new("TextButton",{Name=label,Position=UDim2.new(0,0,0,(index-1)*72),Size=UDim2.new(.75,0,0,59),BackgroundColor3=Color3.fromRGB(37,44,56),Text=label,TextColor3=Color3.fromRGB(245,245,245),Font=Enum.Font.GothamBold,TextSize=23,AutoButtonColor=true,Selectable=true},page)
 new("UICorner",{CornerRadius=UDim.new(0,8)},b)
 b.Activated:Connect(callback)
 table.insert(buttons,b)
 return b
end
local showMain
local function detail(title,lines)
 current="detail";clear()
 new("TextLabel",{Size=UDim2.new(1,0,0,55),BackgroundTransparency=1,Text=title,Font=Enum.Font.GothamBold,TextSize=28,TextColor3=Color3.fromRGB(229,157,53),TextXAlignment=Enum.TextXAlignment.Left},page)
 new("TextLabel",{Position=UDim2.new(0,0,0,65),Size=UDim2.new(.95,0,0,175),BackgroundTransparency=1,Text=lines,TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top,Font=Enum.Font.Gotham,TextSize=19,TextColor3=Color3.fromRGB(240,240,240),TextXAlignment=Enum.TextXAlignment.Left},page)
 button("BACK",5,showMain)
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
-- Hide the menu behind ReplicatedFirst's loading overlay until it finishes.
showMain()
UserInputService.InputBegan:Connect(function(input,processed)
 if current=="playing" then return end
 if input.KeyCode==Enum.KeyCode.ButtonB or input.KeyCode==Enum.KeyCode.Escape then
  if current=="detail" then showMain() end
 elseif input.KeyCode==Enum.KeyCode.Return and not processed then
  local selected=GuiService.SelectedObject
  if selected and selected:IsDescendantOf(page) then selected:Activate() end
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
