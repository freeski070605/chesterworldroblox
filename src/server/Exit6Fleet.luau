-- EXIT 6 fleet (server only): the one vehicle each player has out in the
-- world - a called car, an owned dirt bike / quad, or a dealership test ride.
-- Exit6Vehicles.server (garage calls, fuel, parked physics) and
-- Exit6BikeLife.server (test rides, wheelie scoring) share this table, so
-- there is never more than one ride per player and nothing scans Workspace.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Profile = require(script.Parent:WaitForChild("Exit6Profile"))

local Fleet = {}
Fleet.cars = {}   -- player -> model

local folder = Workspace:FindFirstChild("Exit6Vehicles")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Exit6Vehicles"
	folder.Parent = Workspace
end
Fleet.folder = folder

local changed = Instance.new("BindableEvent")
Fleet.Changed = changed.Event   -- (player, model | nil)

function Fleet.Get(player)
	local car = Fleet.cars[player]
	if car and not car.Parent then
		Fleet.cars[player] = nil
		return nil
	end
	return car
end

-- remember the tank (test rides are the dealer's fuel, not the player's)
function Fleet.SaveFuel(player, car)
	if not car or car:GetAttribute("TestRide") then return end
	local p = Profile.Get(player)
	local id = car:GetAttribute("Exit6Model")
	if p and id and p.vehicles[id] then
		p.vehicles[id].fuel = math.floor((car:GetAttribute("FuelExact") or car:GetAttribute("Fuel") or 0) * 100 + 0.5) / 100
	end
end

function Fleet.Despawn(player)
	local car = Fleet.cars[player]
	Fleet.cars[player] = nil
	if car then
		-- nobody stays seated on a vehicle that is about to vanish
		local seat = car:FindFirstChild("DriverSeat")
		local occ = seat and seat.Occupant
		if occ then occ.Sit = false end
		Fleet.SaveFuel(player, car)
		car:Destroy()
		Profile.Publish(player)
		changed:Fire(player, nil)
	end
end

-- hand a freshly built model to the player (their previous ride goes home)
function Fleet.Put(player, car)
	Fleet.Despawn(player)
	car.Parent = folder
	pcall(function() car.PrimaryPart:SetNetworkOwner(nil) end)
	Fleet.cars[player] = car
	changed:Fire(player, car)
	return car
end

-- a spot is clear when nothing that stands up off the ground (a signal pole,
-- a bench, a wall, another vehicle) is inside the footprint box `cf`/`size`
function Fleet.SpotClear(cf, size, groundY, ignore)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	for _, b in ipairs(Workspace:GetPartBoundsInBox(cf, size, params)) do
		if b.CanCollide and b.Position.Y + b.Size.Y / 2 > groundY + 1.2 then return false end
	end
	return true
end

Players.PlayerRemoving:Connect(Fleet.Despawn)

return Fleet
