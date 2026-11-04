--!nocheck
-- Minimal offline Roblox runtime for ChesterWorld world-generation scripts.
-- Implements only what Bootstrap / TileBuilderV2/V3 / HighwayProfile /
-- RoadTerrainConformer / HighwayInfrastructure use. Terrain is an analytic
-- height function supplied by the harness (HARNESS_TERRAIN).
--
-- NOT a Roblox emulator: physics, rendering, replication and non-vertical
-- part raycasts are not modelled. It exists so geometry and audit logic can
-- be executed and measured outside Studio.

local M = {}

-- ---------------------------------------------------------------- Vector3
local Vector3 = {}
local V3mt = {}
local function v3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3mt)
end
V3mt.__add = function(a, b) return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3mt.__sub = function(a, b) return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3mt.__unm = function(a) return v3(-a.X, -a.Y, -a.Z) end
V3mt.__mul = function(a, b)
	if type(a) == "number" then return v3(b.X * a, b.Y * a, b.Z * a) end
	if type(b) == "number" then return v3(a.X * b, a.Y * b, a.Z * b) end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3mt.__div = function(a, b)
	if type(b) == "number" then return v3(a.X / b, a.Y / b, a.Z / b) end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3mt.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V3mt.__tostring = function(a) return string.format("%.3f, %.3f, %.3f", a.X, a.Y, a.Z) end
local V3methods = {}
function V3methods.Dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
function V3methods.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V3methods.Lerp(a, b, t) return v3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t) end
V3mt.__index = function(a, k)
	if k == "Magnitude" then return math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z) end
	if k == "Unit" then
		local m = math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z)
		if m == 0 then return v3(0 / 0, 0 / 0, 0 / 0) end
		return v3(a.X / m, a.Y / m, a.Z / m)
	end
	return V3methods[k]
end
Vector3.new = v3
Vector3.zero = v3(0, 0, 0)
Vector3.one = v3(1, 1, 1)
Vector3.xAxis = v3(1, 0, 0)
Vector3.yAxis = v3(0, 1, 0)
Vector3.zAxis = v3(0, 0, 1)
M.Vector3 = Vector3

local Vector2 = {}
local V2mt = {}
V2mt.__index = function(a, k)
	if k == "Magnitude" then return math.sqrt(a.X * a.X + a.Y * a.Y) end
	if k == "Unit" then local m = math.sqrt(a.X * a.X + a.Y * a.Y); return Vector2.new(a.X / m, a.Y / m) end
	return nil
end
V2mt.__sub = function(a, b) return Vector2.new(a.X - b.X, a.Y - b.Y) end
V2mt.__add = function(a, b) return Vector2.new(a.X + b.X, a.Y + b.Y) end
function Vector2.new(x, y) return setmetatable({ X = x or 0, Y = y or 0 }, V2mt) end
M.Vector2 = Vector2

-- ---------------------------------------------------------------- CFrame
-- Rotation stored as columns R (right), U (up), B (back); LookVector = -B.
local CFrame = {}
local CFmt = {}
local function cf(p, R, U, B)
	return setmetatable({ p = p, R = R, U = U, B = B }, CFmt)
end
local IDR, IDU, IDB = v3(1, 0, 0), v3(0, 1, 0), v3(0, 0, 1)
local function rot(c, v) -- R*v
	return v3(
		c.R.X * v.X + c.U.X * v.Y + c.B.X * v.Z,
		c.R.Y * v.X + c.U.Y * v.Y + c.B.Y * v.Z,
		c.R.Z * v.X + c.U.Z * v.Y + c.B.Z * v.Z)
end
local function rotT(c, v) -- R^T * v
	return v3(c.R:Dot(v), c.U:Dot(v), c.B:Dot(v))
end
CFmt.__mul = function(a, b)
	if getmetatable(b) == CFmt then
		return cf(a.p + rot(a, b.p), rot(a, b.R), rot(a, b.U), rot(a, b.B))
	end
	return a.p + rot(a, b)
end
CFmt.__index = function(c, k)
	if k == "Position" then return c.p end
	if k == "LookVector" then return -c.B end
	if k == "RightVector" then return c.R end
	if k == "UpVector" then return c.U end
	if k == "X" then return c.p.X end
	if k == "Y" then return c.p.Y end
	if k == "Z" then return c.p.Z end
	if k == "Inverse" then
		return function(self)
			local Rt = v3(self.R.X, self.U.X, self.B.X)
			local Ut = v3(self.R.Y, self.U.Y, self.B.Y)
			local Bt = v3(self.R.Z, self.U.Z, self.B.Z)
			local inv = cf(v3(0, 0, 0), Rt, Ut, Bt)
			return cf(-rot(inv, self.p), Rt, Ut, Bt)
		end
	end
	if k == "PointToObjectSpace" then
		return function(self, v) return rotT(self, v - self.p) end
	end
	if k == "VectorToObjectSpace" then
		return function(self, v) return rotT(self, v) end
	end
	return nil
end
function CFrame.new(x, y, z)
	if x == nil then return cf(v3(0, 0, 0), IDR, IDU, IDB) end
	if type(x) == "table" then return cf(x, IDR, IDU, IDB) end
	return cf(v3(x, y, z), IDR, IDU, IDB)
end
function CFrame.lookAt(at, target, up)
	up = up or Vector3.yAxis
	local look = (target - at).Unit
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		right = look:Cross(v3(0, 0, 1))
		if right.Magnitude < 1e-6 then right = look:Cross(v3(1, 0, 0)) end
	end
	right = right.Unit
	local upv = right:Cross(look).Unit
	return cf(at, right, upv, -look)
end
function CFrame.fromMatrix(pos, vx, vy, vz)
	vz = vz or vx:Cross(vy).Unit
	return cf(pos, vx, vy, vz)
end
function CFrame.Angles(rx, ry, rz)
	local function rx_(a) local c, s = math.cos(a), math.sin(a); return cf(v3(), v3(1, 0, 0), v3(0, c, s), v3(0, -s, c)) end
	local function ry_(a) local c, s = math.cos(a), math.sin(a); return cf(v3(), v3(c, 0, -s), v3(0, 1, 0), v3(s, 0, c)) end
	local function rz_(a) local c, s = math.cos(a), math.sin(a); return cf(v3(), v3(c, s, 0), v3(-s, c, 0), v3(0, 0, 1)) end
	return rx_(rx) * ry_(ry) * rz_(rz)
end
M.CFrame = CFrame

-- ---------------------------------------------------------------- misc types
M.Color3 = {
	fromRGB = function(r, g, b) return { R = r / 255, G = g / 255, B = b / 255 } end,
	new = function(r, g, b) return { R = r, G = g, B = b } end,
}
M.UDim2 = {
	fromOffset = function(x, y) return { x = x, y = y } end,
	fromScale = function(x, y) return { x = x, y = y } end,
	new = function(...) return { ... } end,
}
M.UDim = { new = function(a, b) return { a, b } end }
local function enumNode(path)
	return setmetatable({}, {
		__index = function(_, k) return enumNode(path .. "." .. k) end,
		__tostring = function() return path end,
	})
end
M.Enum = enumNode("Enum")
M.RaycastParams = { new = function() return { FilterDescendantsInstances = {}, FilterType = nil, IgnoreWater = false } end }
M.OverlapParams = { new = function() return { FilterDescendantsInstances = {}, MaxParts = 0 } end }

-- ---------------------------------------------------------------- Instances
local generation = 0
local Instance = {}
local Imt = {}
local methods = {}
local BASEPART = { Part = true, WedgePart = true, SpawnLocation = true, MeshPart = true }
local nextId = 0

local function newInstance(className)
	nextId += 1
	local obj = setmetatable({
		__props = { Name = className, ClassName = className },
		__children = {}, __attrs = {}, __id = nextId,
	}, Imt)
	if BASEPART[className] then
		obj.__props.Size = v3(4, 1, 2)
		obj.__props.CFrame = CFrame.new()
		obj.__props.CanCollide = true
		obj.__props.Anchored = false
		obj.__props.Transparency = 0
	end
	return obj
end
Instance.new = newInstance
M.Instance = Instance

local function detach(obj)
	local parent = obj.__props.Parent
	if parent then
		local list = parent.__children
		for i = #list, 1, -1 do
			if list[i] == obj then table.remove(list, i) break end
		end
	end
end

Imt.__index = function(obj, k)
	local m = methods[k]
	if m then return m end
	local props = rawget(obj, "__props")
	if k == "Position" and props.CFrame then return props.CFrame.p end
	local v = props[k]
	if v ~= nil then return v end
	for _, child in ipairs(rawget(obj, "__children")) do
		if child.__props.Name == k then return child end
	end
	return nil
end
Imt.__newindex = function(obj, k, v)
	local props = rawget(obj, "__props")
	if k == "Parent" then
		detach(obj)
		props.Parent = v
		if v then table.insert(v.__children, obj) end
		generation += 1
		return
	end
	if k == "Position" then
		local c = props.CFrame
		props.CFrame = cf(v, c.R, c.U, c.B)
		generation += 1
		return
	end
	if k == "CFrame" or k == "Size" then generation += 1 end
	props[k] = v
end
Imt.__tostring = function(obj) return obj.__props.Name end

function methods.IsA(obj, class)
	local c = obj.__props.ClassName
	if c == class then return true end
	if class == "BasePart" then return BASEPART[c] == true end
	if class == "Instance" then return true end
	if class == "LuaSourceContainer" then return c == "ModuleScript" or c == "Script" end
	return false
end
function methods.GetChildren(obj) return table.clone(obj.__children) end
function methods.GetDescendants(obj)
	local out = {}
	local function walk(o)
		for _, c in ipairs(o.__children) do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(obj)
	return out
end
function methods.FindFirstChild(obj, name, recursive)
	for _, c in ipairs(obj.__children) do
		if c.__props.Name == name then return c end
	end
	if recursive then
		for _, c in ipairs(obj.__children) do
			local found = methods.FindFirstChild(c, name, true)
			if found then return found end
		end
	end
	return nil
end
function methods.FindFirstChildOfClass(obj, class)
	for _, c in ipairs(obj.__children) do
		if c.__props.ClassName == class then return c end
	end
	return nil
end
function methods.WaitForChild(obj, name)
	local c = methods.FindFirstChild(obj, name)
	if not c then error("WaitForChild: missing " .. tostring(name) .. " under " .. obj.__props.Name, 2) end
	return c
end
function methods.ClearAllChildren(obj)
	for _, c in ipairs(table.clone(obj.__children)) do
		c.__props.Parent = nil
	end
	obj.__children = {}
	generation += 1
end
function methods.Destroy(obj)
	detach(obj)
	obj.__props.Parent = nil
	generation += 1
end
function methods.SetAttribute(obj, k, v) obj.__attrs[k] = v end
function methods.GetAttribute(obj, k) return obj.__attrs[k] end
function methods.GetAttributes(obj) return table.clone(obj.__attrs) end
function methods.GetFullName(obj)
	local names = {}
	local o = obj
	while o do
		table.insert(names, 1, o.__props.Name)
		o = o.__props.Parent
		if o and o.__props.ClassName == "DataModel" then break end
	end
	return table.concat(names, ".")
end
function methods.GetPivot(obj) return obj.__props.CFrame or CFrame.new() end
function methods.PivotTo(obj, c) obj.__props.CFrame = c end
function methods.GetService(obj, name) return methods.FindFirstChild(obj, name) end
local fakeSignal = { Connect = function() return { Disconnect = function() end } end }
function methods.GetPropertyChangedSignal() return fakeSignal end
function methods.GetAttributeChangedSignal() return fakeSignal end

-- ---------------------------------------------------------------- world
local game = newInstance("DataModel")
game.Name = "game"
local Workspace = newInstance("Workspace")
Workspace.Name = "Workspace"
Workspace.Parent = game
local Terrain = newInstance("Terrain")
Terrain.Name = "Terrain"
Terrain.Parent = Workspace
for _, name in ipairs({ "ReplicatedStorage", "ServerScriptService", "StarterPlayer", "Lighting", "AssetService" }) do
	local s = newInstance(name)
	s.Name = name
	s.Parent = game
end
local Players = newInstance("Players")
Players.Name = "Players"
Players.Parent = game
Players.__props.PlayerAdded = fakeSignal
function methods.GetPlayers() return {} end
local RunService = newInstance("RunService")
RunService.Name = "RunService"
RunService.Parent = game
function methods.IsStudio() return true end
function methods.IsServer() return true end
function methods.IsClient() return false end
M.game, M.Workspace, M.Terrain = game, Workspace, Terrain

-- terrain function: set by harness
M.terrainFn = function(_x, _z) return 0 end

-- part spatial index for vertical raycasts
local INDEX_CELL = 48
local cache = {}
local function partsFor(list)
	local key = {}
	for _, inst in ipairs(list) do table.insert(key, tostring(inst.__id)) end
	key = table.concat(key, ",")
	local entry = cache[key]
	if entry and entry.gen == generation then return entry end
	local grid = {}
	local function add(p)
		local c = p.__props.CFrame
		local s = p.__props.Size
		local hx, hy, hz = s.X / 2, s.Y / 2, s.Z / 2
		local ex = math.abs(c.R.X) * hx + math.abs(c.U.X) * hy + math.abs(c.B.X) * hz
		local ez = math.abs(c.R.Z) * hx + math.abs(c.U.Z) * hy + math.abs(c.B.Z) * hz
		for gx = math.floor((c.p.X - ex) / INDEX_CELL), math.floor((c.p.X + ex) / INDEX_CELL) do
			for gz = math.floor((c.p.Z - ez) / INDEX_CELL), math.floor((c.p.Z + ez) / INDEX_CELL) do
				local k = gx * 100003 + gz
				local b = grid[k]
				if not b then b = {}; grid[k] = b end
				table.insert(b, p)
			end
		end
	end
	for _, inst in ipairs(list) do
		if inst ~= Terrain then
			if BASEPART[inst.__props.ClassName] then add(inst) end
			for _, d in ipairs(methods.GetDescendants(inst)) do
				if BASEPART[d.__props.ClassName] then add(d) end
			end
		end
	end
	entry = { gen = generation, grid = grid }
	cache[key] = entry
	return entry
end

local function rayBox(p, o, d)
	local c = p.__props.CFrame
	local s = p.__props.Size
	local lo = rotT(c, o - c.p)
	local ld = rotT(c, d)
	local tmin, tmax = 0, 1
	for _, axis in ipairs({ { lo.X, ld.X, s.X / 2 }, { lo.Y, ld.Y, s.Y / 2 }, { lo.Z, ld.Z, s.Z / 2 } }) do
		local oo, dd, h = axis[1], axis[2], axis[3]
		if math.abs(dd) < 1e-12 then
			if oo < -h or oo > h then return nil end
		else
			local t1, t2 = (-h - oo) / dd, (h - oo) / dd
			if t1 > t2 then t1, t2 = t2, t1 end
			tmin = math.max(tmin, t1)
			tmax = math.min(tmax, t2)
			if tmin > tmax then return nil end
		end
	end
	return tmin
end

function methods.Raycast(_ws, origin, direction, params)
	local list = (params and params.FilterDescendantsInstances) or {}
	local best, bestT, bestInst = nil, math.huge, nil
	local terrainIncluded = false
	for _, inst in ipairs(list) do
		if inst == Terrain then terrainIncluded = true end
	end
	if terrainIncluded then
		local y = M.terrainFn(origin.X, origin.Z)
		if y then
			local t = (y - origin.Y) / direction.Y
			if t >= 0 and t <= 1 then bestT, best, bestInst = t, v3(origin.X, y, origin.Z), Terrain end
		end
	end
	if #list > (terrainIncluded and 1 or 0) then
		local entry = partsFor(list)
		local k = math.floor(origin.X / INDEX_CELL) * 100003 + math.floor(origin.Z / INDEX_CELL)
		for _, p in ipairs(entry.grid[k] or {}) do
			if p.__props.Parent then
				local t = rayBox(p, origin, direction)
				if t and t < bestT then
					bestT, best, bestInst = t, origin + direction * t, p
				end
			end
		end
	end
	if not best then return nil end
	return { Position = best, Instance = bestInst, Normal = v3(0, 1, 0), Material = "Asphalt" }
end
function methods.GetPartBoundsInBox() return {} end
function methods.GetPartsInPart() return {} end

-- ---------------------------------------------------------------- scripts
M.sources = {} -- instance -> source string
local loaded = {}
local baseEnv
local function runSource(inst)
	local src = M.sources[inst]
	if not src then error("no source for " .. methods.GetFullName(inst)) end
	local fn, err = loadstring(src, "=" .. methods.GetFullName(inst))
	if not fn then error(err) end
	local env = setmetatable({ script = inst }, { __index = baseEnv })
	setfenv(fn, env)
	return fn()
end
local function mockRequire(inst)
	if type(inst) ~= "table" then error("require expects an Instance") end
	local cached = loaded[inst]
	if cached ~= nil then return cached.value end
	local value = runSource(inst)
	loaded[inst] = { value = value }
	return value
end
M.require = mockRequire
M.runScript = runSource

baseEnv = setmetatable({
	game = game, workspace = Workspace, Workspace = Workspace,
	Vector3 = Vector3, Vector2 = Vector2, CFrame = CFrame, Color3 = M.Color3,
	UDim2 = M.UDim2, UDim = M.UDim, Enum = M.Enum, Instance = Instance,
	RaycastParams = M.RaycastParams, OverlapParams = M.OverlapParams,
	require = mockRequire,
	task = {
		wait = function() return 0 end,
		spawn = function(f, ...) return f(...) end,
		defer = function(f, ...) return f(...) end,
		delay = function(_, f, ...) return f(...) end,
	},
	wait = function() return 0 end,
	warn = function(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
		print("WARN " .. table.concat(parts, " "))
	end,
	typeof = function(v)
		local mt = getmetatable(v)
		if mt == V3mt then return "Vector3" end
		if mt == CFmt then return "CFrame" end
		if mt == Imt then return "Instance" end
		return type(v)
	end,
}, { __index = getfenv(0) })
M.env = baseEnv

function M.makeFolder(parent, name, class)
	local f = newInstance(class or "Folder")
	f.Name = name
	f.Parent = parent
	return f
end
function M.addModule(parent, name, source, class)
	local m = newInstance(class or "ModuleScript")
	m.Name = name
	m.Parent = parent
	M.sources[m] = source
	return m
end
M.methods = methods
M.rayBox = rayBox
M.generation = function() return generation end
M.isBasePart = function(o) return BASEPART[o.__props.ClassName] == true end
return M
