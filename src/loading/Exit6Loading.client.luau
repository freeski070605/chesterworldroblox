-- EXIT 6 loading screen. Runs in ReplicatedFirst before normal player scripts.
-- Does not modify ChesterWorld's tile bootstrap or world geometry.
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Players = game:GetService("Players")
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
progress(.04,"Connecting to EXIT 6...")
waitUntil(function() return game:IsLoaded() end,25)
-- All major world phases build on the server, after a player joins.
-- Follow replicated completion flags instead of a wall-clock timeout.
-- In particular, highway finishing and gas stations can take longer
-- than 180 seconds on a cold Studio/server startup. NEVER dismiss the
-- loading screen with those phases incomplete.
local started=os.clock()
local warnedSlow=false
local function worldReady()
 return Workspace:GetAttribute("CW_SpawnReady")==true
  and Workspace:GetAttribute("CW_BootstrapComplete")==true
  and Workspace:GetAttribute("CW_RoadConformComplete")==true
  and Workspace:GetAttribute("CW_HighwayFinishComplete")==true
  and Workspace:GetAttribute("CW_ParksComplete")==true
  and Workspace:GetAttribute("CW_GasStationsComplete")==true
  and Workspace:GetAttribute("CW_LandmarksComplete")==true
  and Workspace:GetAttribute("CW_RoadTerrainCleared")==true
  and Workspace:GetAttribute("CW_LocalBridgesDressed")==true
  and Workspace:GetAttribute("CW_StreetFurnitureComplete")==true
  and Workspace:GetAttribute("CW_TreesComplete")==true
  and Workspace:GetAttribute("CW_WaterComplete")==true
end
while not worldReady() do
 local elapsed=os.clock()-started
 local total=Workspace:GetAttribute("CW_TilesTotal") or 0
 local built=Workspace:GetAttribute("CW_TilesBuilt") or 0
 local tilesDone=Workspace:GetAttribute("CW_BootstrapComplete")==true
 local roadsDone=Workspace:GetAttribute("CW_RoadConformComplete")==true
 local highwayDone=Workspace:GetAttribute("CW_HighwayFinishComplete")==true
 local parksDone=Workspace:GetAttribute("CW_ParksComplete")==true
 local gasDone=Workspace:GetAttribute("CW_GasStationsComplete")==true
 local landmarksDone=Workspace:GetAttribute("CW_LandmarksComplete")==true
 local clearingDone=Workspace:GetAttribute("CW_RoadTerrainCleared")==true
 local bridgesDone=Workspace:GetAttribute("CW_LocalBridgesDressed")==true
 local furnitureDone=Workspace:GetAttribute("CW_StreetFurnitureComplete")==true
 local treesDone=Workspace:GetAttribute("CW_TreesComplete")==true
 local waterDone=Workspace:GetAttribute("CW_WaterComplete")==true
 local waterStatus=Workspace:GetAttribute("CW_WaterStatus")
 local slow=elapsed>240
 local suffix=slow and " — large world, still working" or ""
 if not tilesDone then
  if total>0 then
   progress(.08+.65*math.clamp(built/total,0,1),
    string.format("Building Chester...  %d / %d tiles",built,total)..suffix)
  else
   progress(.06,"Waiting for the city server..."..suffix)
  end
 elseif not roadsDone then
  progress(.78,"Connecting roads and bridge approaches..."..suffix)
 elseif not highwayDone then
  progress(.86,"Finishing highways and clearing underpasses..."..suffix)
 elseif not parksDone then
  progress(.91,"Opening parks and playgrounds..."..suffix)
 elseif not gasDone then
  progress(.91,"Finishing gas stations and storefronts..."..suffix)
 elseif not landmarksDone then
  progress(.92,"Building Chester landmarks and venues..."..suffix)
 elseif not clearingDone then
  progress(.93,"Clearing terrain from completed streets..."..suffix)
 elseif not bridgesDone then
  progress(.94,"Finishing local bridges and rail crossings..."..suffix)
 elseif not furnitureDone then
  progress(.945,"Adding streetlights, signals and signs..."..suffix)
 elseif not treesDone then
  progress(.95,"Finishing trees and landscaping..."..suffix)
 elseif not waterDone then
  if waterStatus=="failed" then
   progress(.95,"Water build failed - check Studio Output for [EXIT6 Water]")
  elseif waterStatus=="waiting-for-road-terrain-clear" then
   progress(.95,"Clearing terrain from finished road surfaces..."..suffix)
  elseif waterStatus=="waiting-for-landmarks" then
   progress(.95,"Finishing Chester landmarks..."..suffix)
  elseif waterStatus=="waiting-for-local-bridges" then
   progress(.95,"Finishing local bridge structures..."..suffix)
  else
   local done=Workspace:GetAttribute("CW_WaterPatchesDone") or 0
   local totalPatches=Workspace:GetAttribute("CW_WaterPatchesTotal") or 0
   progress(.95+.03*(totalPatches>0 and math.clamp(done/totalPatches,0,1) or 0),
    string.format("Adding rivers and creeks... %d / %d",done,totalPatches)..suffix)
  end
 else
  progress(.96,"Syncing your neighborhood..."..suffix)
 end
 if slow and not warnedSlow then
  warnedSlow=true
  warn("[EXIT6] City build exceeded 240s; waiting for server completion rather than entering an unfinished world")
 end
 task.wait(.35)
end
print(("[EXIT6] World ready: tiles=%d/%d structures/roads/terrain/bridges/furniture/trees complete waterStatus=%s after %.1fs")
 :format(Workspace:GetAttribute("CW_TilesBuilt") or 0,
  Workspace:GetAttribute("CW_TilesTotal") or 0,
  tostring(Workspace:GetAttribute("CW_WaterStatus") or "unknown"),os.clock()-started))
progress(.9,"Preparing your character...")
local character=player.Character or player.CharacterAdded:Wait()
local root=character:WaitForChild("HumanoidRootPart",20)
progress(.94,"Loading the neighborhood...")
if root then
 local ok,err=pcall(function()
  -- Roblox may stream more world parts after the screen disappears.
  player:RequestStreamAroundAsync(root.Position,12)
 end)
 if not ok then warn("[EXIT6] Initial streaming request:",err) end
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
