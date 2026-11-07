-- EXIT 6 loading screen. Runs in ReplicatedFirst before normal player scripts.
-- Does not modify ChesterWorld's tile bootstrap or world geometry.
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer
pcall(function() ReplicatedFirst:RemoveDefaultLoadingScreen() end)

local gui = Instance.new("ScreenGui")
gui.Name = "Exit6Loading"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 10000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")
local function ui(class, props, parent)
 local obj=Instance.new(class)
 for k,v in pairs(props) do obj[k]=v end
 obj.Parent=parent
 return obj
end
local backdrop=ui("Frame",{Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.fromRGB(10,14,21),BorderSizePixel=0},gui)
local accent=ui("Frame",{Size=UDim2.new(1,0,0,5),BackgroundColor3=Color3.fromRGB(226,155,54),BorderSizePixel=0},backdrop)
local container=ui("Frame",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.new(.86,0,0,250),BackgroundTransparency=1},backdrop)
ui("UISizeConstraint",{MaxSize=Vector2.new(760,300)},container)
ui("TextLabel",{Position=UDim2.fromScale(0,0),Size=UDim2.new(1,0,0,100),BackgroundTransparency=1,Font=Enum.Font.GothamBlack,Text="EXIT 6",TextColor3=Color3.fromRGB(246,246,242),TextScaled=true},container)
ui("TextLabel",{Position=UDim2.new(0,0,0,101),Size=UDim2.new(1,0,0,34),BackgroundTransparency=1,Font=Enum.Font.GothamBold,Text="MAKE IT OUT  •  CHESTER, PA",TextColor3=Color3.fromRGB(226,155,54),TextScaled=true},container)
local status=ui("TextLabel",{Position=UDim2.new(0,0,0,157),Size=UDim2.new(1,0,0,24),BackgroundTransparency=1,Font=Enum.Font.GothamMedium,Text="Connecting to the city...",TextColor3=Color3.fromRGB(204,208,216),TextSize=17,TextXAlignment=Enum.TextXAlignment.Left},container)
local track=ui("Frame",{Position=UDim2.new(0,0,0,193),Size=UDim2.new(1,0,0,9),BackgroundColor3=Color3.fromRGB(52,59,69),BorderSizePixel=0},container)
ui("UICorner",{CornerRadius=UDim.new(1,0)},track)
local fill=ui("Frame",{Size=UDim2.fromScale(0,1),BackgroundColor3=Color3.fromRGB(226,155,54),BorderSizePixel=0},track)
ui("UICorner",{CornerRadius=UDim.new(1,0)},fill)
local percent=ui("TextLabel",{Position=UDim2.new(0,0,0,212),Size=UDim2.new(1,0,0,23),BackgroundTransparency=1,Font=Enum.Font.Gotham,Text="0%",TextColor3=Color3.fromRGB(167,176,191),TextSize=14,TextXAlignment=Enum.TextXAlignment.Right},container)
local function progress(p,label)
 p=math.clamp(p,0,1)
 status.Text=label
 percent.Text=string.format("%d%%",math.floor(p*100+.5))
 TweenService:Create(fill,TweenInfo.new(.3,Enum.EasingStyle.Quad),{Size=UDim2.fromScale(p,1)}):Play()
end
local function waitUntil(check,seconds)
 local started=os.clock()
 repeat
  if check() then return true end
  task.wait(.15)
 until os.clock()-started>=seconds
 return check()
end
progress(.12,"Connecting to EXIT 6...")
waitUntil(function() return game:IsLoaded() end,25)
progress(.32,"Preparing your character...")
local character=player.Character or player.CharacterAdded:Wait()
local root=character:WaitForChild("HumanoidRootPart",20)
progress(.52,"Loading the neighborhood...")
if root then
 local ok,err=pcall(function()
  -- Roblox may stream more world parts after the screen disappears.
  player:RequestStreamAroundAsync(root.Position,12)
 end)
 if not ok then warn("[EXIT6] Initial streaming request:",err) end
end
progress(.78,"Preparing nearby assets...")
-- Preload only a bounded sample of assets already replicated near the player.
-- Preloading the whole city would make the loading screen take too long.
local assets={}
if root then
 for _,obj in ipairs(Workspace:GetPartBoundsInRadius(root.Position,180)) do
  if #assets>=75 then break end
  for _,child in ipairs(obj:GetDescendants()) do
   if child:IsA("Decal") or child:IsA("Texture") or child:IsA("MeshPart") or child:IsA("SpecialMesh") then
    table.insert(assets,child)
    if #assets>=75 then break end
   end
  end
 end
end
if #assets>0 then
 local ok,err=pcall(function() ContentProvider:PreloadAsync(assets) end)
 if not ok then warn("[EXIT6] Asset preload:",err) end
end
progress(.95,"Welcome to Chester...")
task.wait(.5)
progress(1,"You're in.")
task.wait(.4)
local tween=TweenService:Create(backdrop,TweenInfo.new(.55),{BackgroundTransparency=1})
tween:Play()
for _,desc in ipairs(backdrop:GetDescendants()) do
 if desc:IsA("TextLabel") then TweenService:Create(desc,TweenInfo.new(.5),{TextTransparency=1}):Play()
 elseif desc:IsA("Frame") then TweenService:Create(desc,TweenInfo.new(.5),{BackgroundTransparency=1}):Play() end
end
tween.Completed:Wait()
gui:Destroy()
