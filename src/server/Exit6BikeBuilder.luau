-- Exit 6 Bike Life: purpose-built lightweight dirt bikes and sport quads.
-- Uses the proven raycast road suspension; narrow virtual wheel track on bikes
-- provides low-speed balance without fake visible training wheels.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Catalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Exit6Catalog"))
local BikeBuilder = {}

local function part(model, chassis, name, size, offset, colour, material, opts)
    local p = Instance.new("Part")
    p.Name, p.Size = name, size
    p.CFrame = chassis.CFrame * offset
    p.Color = colour
    p.Material = material or Enum.Material.Metal
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    p.CanCollide = opts and opts.collide == true or false
    p.CanTouch, p.Massless = false, true
    if opts and opts.shape then p.Shape = opts.shape end
    if opts and opts.transparency then p.Transparency = opts.transparency end
    p.Parent = model
    local weld = Instance.new("WeldConstraint")
    weld.Part0, weld.Part1, weld.Parent = chassis, p, p
    return p
end

function BikeBuilder.Build(id, cf, opts)
    opts = opts or {}
    local spec = Catalog.Vehicles[id]
    assert(spec and spec.rideType, "Not a Bike Life vehicle: "..tostring(id))
    local bike = spec.rideType == "bike"
    local tint = opts.paint or Color3.fromRGB(208,48,34)
    local dark = Color3.fromRGB(25,27,31)
    local metal = Color3.fromRGB(156,162,166)
    local m = Instance.new("Model")
    m.Name = opts.owner and (opts.owner.Name .. "'s " .. spec.name) or spec.name
    m:SetAttribute("Exit6Car", true) -- reuse garage, seat, fuel and security systems
    m:SetAttribute("Exit6BikeLife", spec.rideType)
    m:SetAttribute("Exit6Model",id)
    m:SetAttribute("WheelBase",spec.len*0.68)
    m:SetAttribute("TrackHalf",bike and 0.58 or (spec.wid/2-0.65))
    m:SetAttribute("WheelMountY",-0.25)
    m:SetAttribute("Rest",bike and 1.1 or 1.25)
    m:SetAttribute("Radius",bike and 1.25 or 1.45)
    m:SetAttribute("TopSpeed",spec.topSpeed)
    m:SetAttribute("EngineAccel",spec.accel)
    m:SetAttribute("Tank",spec.tank)
    m:SetAttribute("Fuel",opts.fuel or spec.tank)
    if opts.owner then m:SetAttribute("Owner",opts.owner.UserId) end

    local chassis=Instance.new("Part")
    chassis.Name="Chassis"
    chassis.Size=Vector3.new(bike and 1.9 or spec.wid-0.35,1.15,spec.len-1.1)
    chassis.CFrame=cf
    chassis.Transparency=1
    chassis.Anchored=opts.display == true
    chassis.CustomPhysicalProperties=PhysicalProperties.new(0.75,0.55,0.05,1,1)
    chassis.Parent=m
    m.PrimaryPart=chassis
    -- Reuse the same suspension parameters as the car system, but mass and
    -- collision hull reflect the narrow bike / low quad stance.
    local half=spec.len/2
    local wheelX=bike and 0 or (spec.wid/2-0.35)
    local wheelZ=spec.len*0.34
    for _,z in ipairs({-wheelZ,wheelZ}) do
        for _,x in ipairs(bike and {0} or {-wheelX,wheelX}) do
            part(m,chassis,"Tyre",Vector3.new(0.65,bike and 2.5 or 2.9,bike and 2.5 or 2.9),
                CFrame.new(x,-1.0,z),dark,Enum.Material.SmoothPlastic,{shape=Enum.PartType.Cylinder})
            part(m,chassis,"WheelHub",Vector3.new(0.7,1.35,1.35),
                CFrame.new(x,-1.0,z),metal,Enum.Material.Metal,{shape=Enum.PartType.Cylinder})
        end
    end
    if bike then
        part(m,chassis,"Frame",Vector3.new(1.1,1.5,3.5),CFrame.new(0,0.35,0),dark)
        part(m,chassis,"FuelTank",Vector3.new(1.7,1.0,2.1),CFrame.new(0,1.25,-1.05),tint)
        part(m,chassis,"Engine",Vector3.new(1.4,1.45,1.4),CFrame.new(0,-0.15,0.3),metal)
        part(m,chassis,"SeatCushion",Vector3.new(1.3,0.35,3.0),CFrame.new(0,1.65,1.05),dark,Enum.Material.SmoothPlastic)
        part(m,chassis,"FrontFender",Vector3.new(1.7,0.25,2.3),CFrame.new(0,0.22,-wheelZ),tint)
        part(m,chassis,"RearFender",Vector3.new(1.7,0.24,2.2),CFrame.new(0,0.40,wheelZ),tint)
        part(m,chassis,"Handlebars",Vector3.new(4.1,0.28,0.28),CFrame.new(0,2.18,-2.5),metal)
        part(m,chassis,"FrontFork",Vector3.new(0.5,2.45,0.5),
            CFrame.new(0,0.15,-wheelZ),metal)
    else
        part(m,chassis,"QuadLowerFrame",Vector3.new(spec.wid-0.9,1.1,4.8),CFrame.new(0,0.05,0.2),dark)
        part(m,chassis,"QuadFairing",Vector3.new(spec.wid-0.5,0.85,3.9),CFrame.new(0,0.85,-1.15),tint)
        part(m,chassis,"QuadRear",Vector3.new(spec.wid-0.8,0.8,2.8),CFrame.new(0,0.55,2.1),tint)
        part(m,chassis,"QuadSeat",Vector3.new(1.8,0.38,2.8),CFrame.new(0,1.55,0.85),dark)
        part(m,chassis,"Handlebars",Vector3.new(3.7,0.3,0.3),CFrame.new(0,2.05,-1.7),metal)
    end
    part(m,chassis,"Headlight",Vector3.new(bike and 1.3 or 3.5,0.55,0.22),
        CFrame.new(0,0.8,-half+0.1),Color3.fromRGB(248,240,208),Enum.Material.Neon)
    part(m,chassis,"TailLamp",Vector3.new(bike and 1.1 or 2.4,0.36,0.2),
        CFrame.new(0,0.5,half-0.15),Color3.fromRGB(226,32,35),Enum.Material.Neon)
    if opts.display then return m end

    local seat=Instance.new("VehicleSeat")
    seat.Name="DriverSeat"
    seat.Size=Vector3.new(1.8,0.6,1.9)
    seat.CFrame=chassis.CFrame*CFrame.new(0,1.55,0.9)
    seat.Transparency=1
    seat.CanCollide=false
    seat.Massless=true
    seat.Torque,seat.MaxSpeed,seat.HeadsUpDisplay=0,0,false
    seat.Parent=m
    local w=Instance.new("WeldConstraint")
    w.Part0,w.Part1,w.Parent=chassis,seat,seat
    local prompt=Instance.new("ProximityPrompt")
    prompt.Name="EnterPrompt"
    prompt.ActionText=bike and "Ride dirt bike" or "Ride quad"
    prompt.ObjectText=m.Name
    prompt.KeyboardKeyCode=Enum.KeyCode.E
    prompt.GamepadKeyCode=Enum.KeyCode.ButtonX
    prompt.MaxActivationDistance=12
    prompt.RequiresLineOfSight=false
    prompt.Parent=chassis
    prompt.Triggered:Connect(function(player)
        local char=player.Character
        local hum=char and char:FindFirstChildOfClass("Humanoid")
        local root=char and char:FindFirstChild("HumanoidRootPart")
        if not hum or not root or hum.Health<=0 or hum.SeatPart
            or (root.Position-chassis.Position).Magnitude>17 then return end
        local owner=m:GetAttribute("Owner")
        if (not owner or owner==player.UserId) and not seat.Occupant then seat:Sit(hum) end
    end)
    seat:GetPropertyChangedSignal("Occupant"):Connect(function()
        local occ=seat.Occupant
        local player=occ and Players:GetPlayerFromCharacter(occ.Parent)
        if player and m:GetAttribute("Owner") and m:GetAttribute("Owner")~=player.UserId then
            occ.Sit=false
            return
        end
        pcall(function() chassis:SetNetworkOwner(player) end)
        m:SetAttribute("Driver",player and player.UserId or nil)
    end)
    return m
end
-- chassis centre height above the ground at rest (display stands / spawns)
function BikeBuilder.RideHeight(id)
    return 2.25
end
return BikeBuilder
