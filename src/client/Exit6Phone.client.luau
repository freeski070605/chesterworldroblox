-- EXIT 6 shop menu, job HUD and phone (Wallet / Bag / Job). Client-side only:
-- every purchase / use goes through Exit6Remotes and is decided by the server
-- (Exit6Shop.server.luau). Keyboard, mouse, touch and gamepad.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Exit6Config"))
if not Config.ShopSystem then return end
local Catalog = require(Shared:WaitForChild("Exit6Catalog"))
local remotes = ReplicatedStorage:WaitForChild("Exit6Remotes")
local ShopOpen = remotes:WaitForChild("ShopOpen")
local Purchase = remotes:WaitForChild("Purchase")
local StyleAction = remotes:WaitForChild("StyleAction")
local Wardrobe = require(Shared:WaitForChild("Exit6Wardrobe"))
local UseItem = remotes:WaitForChild("UseItem")
local QuitJob = remotes:WaitForChild("QuitJob")

local INK = Color3.fromRGB(18, 21, 27)
local CARD = Color3.fromRGB(37, 44, 56)
local ACCENT = Color3.fromRGB(229, 157, 53)
local TEXT = Color3.fromRGB(245, 245, 242)
local DIM = Color3.fromRGB(155, 164, 177)

local gui = Instance.new("ScreenGui")
gui.Name = "Exit6Phone"
gui.ResetOnSpawn = false
gui.DisplayOrder = 50
gui.Parent = player:WaitForChild("PlayerGui")

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end
local function round(o, r) new("UICorner", { CornerRadius = UDim.new(0, r or 10) }, o) end
local function cash()
	local ls = player:FindFirstChild("leaderstats")
	local c = ls and ls:FindFirstChild("Chester Cash")
	local r = ls and ls:FindFirstChild("Reputation")
	return c and c.Value or 0, r and r.Value or 0
end
local function bag()
	local raw = player:GetAttribute("Exit6Inventory")
	local ok, t = pcall(function() return raw and HttpService:JSONDecode(raw) end)
	return ok and type(t) == "table" and t or {}
end

-- a scrolling list panel used by both the shop and the phone
local function panel(name, width)
	local f = new("Frame", { Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(width, 420), BackgroundColor3 = INK, BackgroundTransparency = 0.05, Visible = false }, gui)
	round(f, 14)
	new("UISizeConstraint", { MaxSize = Vector2.new(width, 420) }, f)
	local title = new("TextLabel", { Name = "Title", Position = UDim2.fromOffset(18, 12), Size = UDim2.new(1, -36, 0, 30),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 22, TextColor3 = TEXT,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, f)
	local sub = new("TextLabel", { Name = "Sub", Position = UDim2.fromOffset(18, 42), Size = UDim2.new(1, -36, 0, 20),
		BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 14, TextColor3 = ACCENT,
		TextXAlignment = Enum.TextXAlignment.Left }, f)
	local list = new("ScrollingFrame", { Name = "List", Position = UDim2.fromOffset(12, 72), Size = UDim2.new(1, -24, 1, -112),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, Selectable = false }, f)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	new("TextLabel", { Name = "Hint", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 18, 1, -10),
		Size = UDim2.new(1, -36, 0, 22), BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 13,
		TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Left }, f)
	return f, title, sub, list
end
local function clearList(list)
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
end
local function row(list, order, left, right, onClick)
	local b = new("TextButton", { LayoutOrder = order, Size = UDim2.new(1, -8, 0, 44), BackgroundColor3 = CARD,
		AutoButtonColor = onClick ~= nil, Selectable = onClick ~= nil, Text = "", Active = onClick ~= nil }, list)
	round(b, 8)
	new("TextLabel", { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -110, 1, 0), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, TextSize = 17, TextColor3 = TEXT, Text = left,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, b)
	new("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 0), Size = UDim2.new(0, 90, 1, 0),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 17, TextColor3 = ACCENT, Text = right or "",
		TextXAlignment = Enum.TextXAlignment.Right }, b)
	if onClick then b.Activated:Connect(onClick) end
	return b
end

-- ------------------------------------------------------------------ shop menu
local shop, shopTitle, shopSub, shopList = panel("Shop", 440)
shop.Hint.Text = "A / CLICK  BUY       B / BACKSPACE  CLOSE"
local openShop = nil  -- the payload of the store currently open
local busy = false
local tryOnId = nil   -- wearable currently tried on at this counter (not bought)

local function profile()
	local raw = player:GetAttribute("Exit6Profile")
	local ok, t = pcall(function() return raw and HttpService:JSONDecode(raw) end)
	return ok and type(t) == "table" and t or {}
end
local function cancelTryOn()
	if not tryOnId then return end
	tryOnId = nil
	task.spawn(function() pcall(function() StyleAction:InvokeServer("cancel") end) end)
end

local function closeAll()
	cancelTryOn()
	shop.Visible = false
	openShop = nil
	GuiService.SelectedObject = nil
end

local function drawShop()
	if not openShop then return end
	local c = cash()
	shopTitle.Text = openShop.title
	shopSub.Text = string.format("Cashier  |  you have $%d", c)
	-- keep the gamepad selection on the same row across a redraw
	local sel = GuiService.SelectedObject
	local keep = sel and sel:IsDescendantOf(shopList) and sel.LayoutOrder
	clearList(shopList)
	local first
	local st = profile().style or {}
	local owned = type(st.owned) == "table" and st.owned or {}
	local lastSlot = nil
	local wearShop = false
	for i, it in ipairs(openShop.items) do
		local order = i * 2
		if it.slot and it.slot ~= lastSlot then
			-- slot headings (not selectable: the gamepad skips them)
			lastSlot = it.slot
			wearShop = true
			local h = row(shopList, order - 1, string.upper(Wardrobe.SlotNames[it.slot] or it.slot), "")
			h.BackgroundTransparency = 1
		end
		local right = "$" .. it.price
		if it.slot then
			if st[it.slot] == it.id then right = "WEARING"
			elseif owned[it.id] then right = "OWNED"
			elseif tryOnId == it.id then right = "BUY $" .. it.price end
		end
		local b = row(shopList, order, (tryOnId == it.id and "> " or "") .. it.name, right, function()
			if busy then return end
			busy = true
			if it.slot and not owned[it.id] and tryOnId ~= it.id then
				-- first press tries it on; pressing again buys it
				local ok, done = pcall(function() return StyleAction:InvokeServer("preview", openShop and openShop.storeId, it.id) end)
				if ok and done then tryOnId = it.id end
			else
				-- the server answers with a notice either way (Exit6HUD toast)
				local ok, bought = pcall(function() return Purchase:InvokeServer(openShop and openShop.storeId, it.id) end)
				if ok and bought then tryOnId = nil end
			end
			busy = false
			drawShop()
		end)
		if it.price > c and not owned[it.id] then b.BackgroundColor3 = Color3.fromRGB(52, 40, 40) end
		if tryOnId == it.id then b.BackgroundColor3 = Color3.fromRGB(70, 58, 30) end
		if keep == order or not first then first = b end
	end
	shop.Hint.Text = wearShop and "A  TRY ON / BUY     B  CLOSE" or "A / CLICK  BUY       B / BACKSPACE  CLOSE"
	local leave = row(shopList, 999, "Leave", "", closeAll)
	leave.BackgroundColor3 = Color3.fromRGB(28, 32, 40)
	if GuiService.SelectedObject == nil or not GuiService.SelectedObject:IsDescendantOf(shop) then
		GuiService.SelectedObject = (keep == 999) and leave or first or leave
	end
end

ShopOpen.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	cancelTryOn()
	gui.Phone.Visible = false
	openShop = payload
	shop.Visible = true
	GuiService.SelectedObject = nil
	drawShop()
end)

-- ------------------------------------------------------------------ phone
local phone, phoneTitle, phoneSub, phoneList = panel("Phone", 400)
phone.AnchorPoint = Vector2.new(1, 1)
phone.Position = UDim2.new(1, -16, 1, -16)
phone.Hint.Text = "P / ▲ / B  CLOSE      A  SELECT"
local tab = "wallet"
local tabs = new("Frame", { Position = UDim2.fromOffset(12, 64), Size = UDim2.new(1, -24, 0, 30), BackgroundTransparency = 1 }, phone)
phoneList.Position = UDim2.fromOffset(12, 102)
phoneList.Size = UDim2.new(1, -24, 1, -142)
local drawPhone
local bikeState = nil   -- latest Bike Life status (Exit6BikeLife.server)
local openTab
local tabButtons = {}
local TABS = { { "wallet", "Wallet" }, { "bag", "Bag" }, { "job", "Job" }, { "car", "Car" }, { "rideout", "Ride" }, { "home", "Home" }, { "biz", "Biz" }, { "music", "Music" }, { "closet", "Closet" } }
for i, t in ipairs(TABS) do
	local b = new("TextButton", { Name = t[1], Position = UDim2.new((i - 1) / #TABS, 2, 0, 0), Size = UDim2.new(1 / #TABS, -4, 1, 0),
		BackgroundColor3 = CARD, Text = t[2], Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = TEXT }, tabs)
	round(b, 6)
	b.Activated:Connect(function() openTab(t[1]) end)
	tabButtons[t[1]] = b
end
phoneSub.Position = UDim2.fromOffset(18, 40)

local function jobInfo()
	local raw = player:GetAttribute("Exit6Job")
	local ok, j = pcall(function() return raw and HttpService:JSONDecode(raw) end)
	return ok and type(j) == "table" and j or nil
end
local function myRoot()
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end
local function nearestPlayer(range)
	local me = myRoot()
	if not me then return nil end
	local best, bd = nil, range
	for _, p in ipairs(Players:GetPlayers()) do
		local r = p ~= player and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if r and (r.Position - me.Position).Magnitude < bd then best, bd = p, (r.Position - me.Position).Magnitude end
	end
	return best
end
local function nearestStore(range)
	local me = myRoot()
	if not me then return nil end
	local best, bd = nil, range
	for _, tagName in ipairs({ "Exit6Store", "Exit6GasStation" }) do
		for _, m in ipairs(CollectionService:GetTagged(tagName)) do
			local a = m:GetAttribute("Exit6StoreKey") and m:FindFirstChild("Exit6StoreAnchor", true)
			if a and (a.Position - me.Position).Magnitude < bd then best, bd = m, (a.Position - me.Position).Magnitude end
		end
	end
	return best
end
local function remoteNamed(name) return remotes:FindFirstChild(name) end
local function act(fn)
	return function()
		pcall(fn)
		task.wait(0.25)
		drawPhone()
	end
end

-- a local HOME marker (phone > Home > Show my home)
local homeMarker = nil
local function markHome(pos, label)
	if homeMarker then homeMarker:Destroy() homeMarker = nil end
	if typeof(pos) ~= "Vector3" then return end
	local marker = new("Part", { Name = "Exit6HomeMarker", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
		Transparency = 1, Size = Vector3.one, CFrame = CFrame.new(pos) }, Workspace)
	homeMarker = marker
	local bb = new("BillboardGui", { Size = UDim2.fromOffset(120, 40), StudsOffset = Vector3.new(0, 7, 0), AlwaysOnTop = true,
		LightInfluence = 0, MaxDistance = 100000 }, marker)
	new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BackgroundTransparency = 0.2, TextColor3 = ACCENT,
		Font = Enum.Font.GothamBlack, TextSize = 18, Text = label or "HOME" }, bb)
	task.delay(90, function() if homeMarker == marker then markHome(nil) end end)
end

-- FOR RENT markers on the nearest vacant rentals (phone > Home)
local rentMarkers = {}
local function markRentals()
	for _, m in ipairs(rentMarkers) do m:Destroy() end
	table.clear(rentMarkers)
	local me = myRoot()
	if not me then return 0 end
	local list = {}
	for _, d in ipairs(CollectionService:GetTagged("Exit6FrontDoor")) do
		if d:GetAttribute("Exit6Rentable") and not d:GetAttribute("Exit6OccupantName") then
			table.insert(list, { d = d, dist = (d.Position - me.Position).Magnitude })
		end
	end
	table.sort(list, function(a, b) return a.dist < b.dist end)
	for i = 1, math.min(5, #list) do
		local d = list[i].d
		local price = Catalog.Housing[d:GetAttribute("Exit6HomeStyle") or ""] or Catalog.Housing.default
		local bb = new("BillboardGui", { Size = UDim2.fromOffset(150, 40), StudsOffset = Vector3.new(0, 7, 0), AlwaysOnTop = true,
			LightInfluence = 0, MaxDistance = 100000, Adornee = d }, gui)
		new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(240, 240, 236), TextColor3 = Color3.fromRGB(190, 24, 28),
			Font = Enum.Font.GothamBlack, TextSize = 16, Text = "FOR RENT  $" .. price }, bb)
		table.insert(rentMarkers, bb)
	end
	task.delay(120, function()
		for _, m in ipairs(rentMarkers) do m:Destroy() end
		table.clear(rentMarkers)
	end)
	return math.min(5, #list)
end

drawPhone = function()
	local c, r = cash()
	local prof = profile()
	local previous = GuiService.SelectedObject
	local fromList = tab == "closet" and previous and previous:IsDescendantOf(phoneList)
	local keepOrder = fromList and previous.LayoutOrder
	local listRows = {}
	phoneTitle.Text = os.date("%I:%M %p"):gsub("^0", "")
	phoneSub.Text = "Chester, PA"
	phone.Hint.Text = "P / B  CLOSE      A  SELECT"
	for k, b in pairs(tabButtons) do b.BackgroundColor3 = (k == tab) and ACCENT or CARD end
	clearList(phoneList)
	if tab == "wallet" then
		row(phoneList, 1, "Chester Cash", "$" .. c)
		row(phoneList, 2, "Reputation", tostring(r))
		local other = nearestPlayer(12)
		if other then
			for i, amount in ipairs({ 10, 50 }) do
				row(phoneList, 2 + i, "Give $" .. amount .. " to " .. other.DisplayName, "", act(function()
					ReplicatedStorage:WaitForChild("Exit6RumbleEvent"):FireServer("GiveCash", other.UserId, amount)
				end))
			end
		else
			row(phoneList, 3, "Stand by someone to give cash", "")
		end
	elseif tab == "closet" then
		-- everything you own, by slot: A wears it, A on what you wear takes it off
		phoneTitle.Text = "CLOSET"
		phoneSub.Text = "Your EXIT 6 fits - saved"
		phone.Hint.Text = "A  WEAR / TAKE OFF    B  CLOSE"
		local st = type(prof.style) == "table" and prof.style or {}
		local owned = type(st.owned) == "table" and st.owned or {}
		local n = 0
		local function add(left, right, fn)
			n += 1
			local b = row(phoneList, n, left, right, fn)
			if fn then table.insert(listRows, b) end
			return b
		end
		local function closet(verb, a)
			return act(function() StyleAction:InvokeServer(verb, a) end)
		end
		for _, slot in ipairs(Wardrobe.Slots) do
			local ids = {}
			for id in pairs(owned) do
				local it = Catalog.Items[id]
				if it and it.kind == "wear" and it.slot == slot then table.insert(ids, id) end
			end
			if #ids > 0 then
				table.sort(ids, function(x, y) return Catalog.Items[x].name < Catalog.Items[y].name end)
				local h = add(string.upper(Wardrobe.SlotNames[slot]), st[slot] and "" or "NONE")
				h.BackgroundTransparency = 1
				for _, id in ipairs(ids) do
					local on = st[slot] == id
					local b = add(Catalog.Items[id].name, on and "ON" or "WEAR", on and closet("unequip", slot) or closet("equip", id))
					if on then b.BackgroundColor3 = Color3.fromRGB(70, 58, 30) end
				end
			end
		end
		add("Put the starter fit back on", "FREE", closet("starter"))
		add("Wear my Roblox avatar", "", closet("avatar"))
		add("Cuts: barbershops. Fits: clothing stores.", "")
		add("Chains & watches: clothing stores, jewelers", "")
		-- gamepad: tab -> first row, rows chain up / down
		if #listRows > 0 then
			tabButtons.closet.NextSelectionDown = listRows[1]
			for i, button in ipairs(listRows) do
				button.NextSelectionUp = listRows[i - 1] or tabButtons.closet
				button.NextSelectionDown = listRows[i + 1]
			end
		end
	elseif tab == "car" then
		local out = nil
		local folder = Workspace:FindFirstChild("Exit6Vehicles")
		for _, m in ipairs(folder and folder:GetChildren() or {}) do
			if m:GetAttribute("Owner") == player.UserId then out = m end
		end
		local ids = {}
		for id in pairs(prof.vehicles or {}) do table.insert(ids, id) end
		table.sort(ids)
		local n = 0
		for _, id in ipairs(ids) do
			local spec = Catalog.Vehicles[id]
			if spec then
				n += 1
				local isOut = out and out:GetAttribute("Exit6Model") == id
				local fuel = isOut and (out:GetAttribute("Fuel") or 0) or (prof.vehicles[id].fuel or 0)
				row(phoneList, n, (isOut and "> " or "") .. spec.name, math.floor(fuel / spec.tank * 100 + 0.5) .. "% gas",
					act(function() remoteNamed("CallCar"):InvokeServer(id) end))
			end
		end
		if out then
			row(phoneList, 20, "Send it home", "", act(function() remoteNamed("SendCarHome"):FireServer() end))
		end
		row(phoneList, 21, "Tap a car to call it", "")
		row(phoneList, 22, "More cars: Exit 6 Motors", "")
	elseif tab == "rideout" then
		-- Bike Life (Exit6BikeLife.server): rideouts, wheelie stats, your rides
		phoneTitle.Text = "BIKE LIFE"
		phoneSub.Text = "Rideouts / wheelies / your rides"
		local remote = remoteNamed("BikeLifeAction")
		local st = bikeState
		if remote and not st then
			local ok, r = pcall(function() return remote:InvokeServer("status") end)
			if ok and type(r) == "table" then st, bikeState = r, r end
		end
		if not remote or not st then
			row(phoneList, 1, "Bike Life loading...", "")
		else
			local n = 0
			local function line(l, r, f) n += 1 return row(phoneList, n, l, r, f) end
			local function cmd(c, v)
				return act(function()
					local r = remote:InvokeServer(c, v)
					if type(r) == "table" and type(r.status) == "table" then bikeState = r.status end
				end)
			end
			local mine = st.mine
			if mine then
				local stage = mine.started and (mine.done and "DONE: " or "LIVE: ") or "MEETUP: "
				line(stage .. mine.route, #mine.members .. "/" .. mine.max .. " riders")
				if mine.next then
					local label = mine.started and string.format("Next %d/%d: %s", mine.next.index - 1, mine.stops - 1, mine.next.name)
						or ("Meet at " .. mine.next.name)
					line(label, "MARK", act(function() markHome(mine.next.pos, "RIDEOUT") end))
				end
				line(mine.place and ("You finished #" .. mine.place) or "Your rideout points", tostring(mine.score) .. " pts")
				for i, m in ipairs(mine.members) do
					if i <= 8 then
						local pos = m.place and ("#" .. m.place) or (mine.started and (m.cp - 1 .. "/" .. (mine.stops - 1)) or "-")
						line(pos .. "  " .. m.name .. (m.leader and " (lead)" or "") .. "  " .. (m.ride or "on foot"), m.score .. " pts")
					end
				end
				if mine.isLeader and not mine.started then
					line("START RIDEOUT (on your ride at the meetup)", "", cmd("start"))
					local invited = 0
					for _, p in ipairs(Players:GetPlayers()) do
						if p ~= player and invited < 6 then
							invited += 1
							line("Invite " .. p.DisplayName, "", cmd("invite", p.UserId))
						end
					end
				end
				line(mine.isLeader and "End rideout" or "Leave rideout", "", cmd(mine.isLeader and "finish" or "leave"))
			else
				for i, r in ipairs(st.routes or {}) do
					line("Start rideout: " .. r.name, r.from, cmd("create", i))
				end
				for i, o in ipairs(st.open or {}) do
					if i <= 6 then
						line((o.invited and "INVITED: " or "Join ") .. o.leaderName .. " (" .. o.riders .. ")", o.route, cmd("join", o.leaderId))
					end
				end
			end
			local stats = st.stats or {}
			line("Personal best wheelie", string.format("%.1fs", stats.bestWheelie or 0))
			line("Rideouts ridden / finished", (stats.rideouts or 0) .. " / " .. (stats.finished or 0))
			line("Wheelie time / best rideout", (stats.totalWheelie or 0) .. "s / " .. (stats.bestRide or 0))
			for i, b in ipairs(st.board or {}) do
				if i <= 5 then
					line(string.format("#%d %s%s", i, b.name, b.me and " (you)" or ""), string.format("%.1fs  PB %.1fs", b.session, b.best))
				end
			end
			local bikes = {}
			for id in pairs(prof.vehicles or {}) do
				if Catalog.Vehicles[id] and Catalog.Vehicles[id].rideType then table.insert(bikes, id) end
			end
			table.sort(bikes)
			for _, id in ipairs(bikes) do
				line("Call my " .. Catalog.Vehicles[id].name, "", act(function() remoteNamed("CallCar"):InvokeServer(id) end))
			end
			line("Bike shop & test rides: Exit 6 Motors", "MARK", act(function()
				markHome(Workspace:GetAttribute("Exit6DealershipAt"), "EXIT 6 MOTORS")
			end))
			line("Ride: RT/W gas  LT/S brake  A/Space wheelie  X/F off", "")
		end
	elseif tab == "bag" then
		local items, n = bag(), 0
		local ids = {}
		for id in pairs(items) do table.insert(ids, id) end
		table.sort(ids)
		for _, id in ipairs(ids) do
			local item = Catalog.Items[id]
			if item then
				n += 1
				row(phoneList, n, item.name, "x" .. items[id], act(function() UseItem:InvokeServer(id) end))
			end
		end
		if n == 0 then row(phoneList, 1, "Empty - buy something at a store", "") end
	elseif tab == "home" then
		if prof.home then
			row(phoneList, 1, "Home on " .. tostring(prof.home.street), "")
			row(phoneList, 2, "Show my home", "", act(function() markHome(remoteNamed("HomeAction"):InvokeServer("where")) end))
			local n = 2
			-- stash (works at the front door)
			for id, count in pairs(prof.stash or {}) do
				local item = Catalog.Items[id]
				if item then
					n += 1
					row(phoneList, n, "Take " .. item.name, "x" .. count, act(function() remoteNamed("HomeAction"):InvokeServer("take", id) end))
				end
			end
			for id, count in pairs(bag()) do
				local item = Catalog.Items[id]
				if item then
					n += 1
					row(phoneList, n, "Stash " .. item.name, "x" .. count, act(function() remoteNamed("HomeAction"):InvokeServer("stash", id) end))
				end
			end
			local out = row(phoneList, 99, "Move out", "", act(function() remoteNamed("HomeAction"):InvokeServer("moveout") end))
			out.BackgroundColor3 = Color3.fromRGB(70, 36, 36)
		else
			row(phoneList, 1, "No place yet", "")
			row(phoneList, 2, "Show homes for rent nearby", "", act(markRentals))
			row(phoneList, 3, "Every house in Chester is for rent", "")
			row(phoneList, 4, "At a door: Y / E move in, X / F look", "")
		end
	elseif tab == "music" then
		local m = prof.music or {}
		row(phoneList, 1, string.format("Pen %d  Flow %d  Beats %d", m.pen or 0, m.flow or 0, m.beats or 0), "")
		row(phoneList, 2, "Fans", tostring(m.fans or 0))
		local n = 2
		for i, t in ipairs(m.tracks or {}) do
			n += 1
			if t.rel then
				row(phoneList, n, string.format("%s  (q%d)", t.name, t.q), t.streams .. " plays")
			else
				row(phoneList, n, "Release \"" .. t.name .. "\"  (q" .. t.q .. ")", "", act(function()
					remoteNamed("MusicAction"):InvokeServer("release", i)
				end))
			end
		end
		if n == 2 then row(phoneList, 3, "No tracks yet", "") end
		row(phoneList, 50, "Find Exit 6 Sound (studio)", "", act(function()
			local at = Workspace:GetAttribute("Exit6StudioAt")
			if typeof(at) == "Vector3" then markHome(at, "STUDIO") end
		end))
	elseif tab == "biz" then
		local n = 0
		local here = nearestStore(30)
		if here then
			local key = here:GetAttribute("Exit6StoreKey")
			local mine = prof.business and prof.business[key]
			local owner = here:GetAttribute("Exit6OwnerName")
			n += 1
			row(phoneList, n, tostring(here:GetAttribute("ShopName") or here.Name),
				mine and "YOURS" or (owner and "TAKEN" or ("$" .. tostring(here:GetAttribute("Exit6StorePrice")))))
			if mine then
				n += 1
				row(phoneList, n, "Collect the till", "$" .. mine.bank, act(function() remoteNamed("BusinessAction"):InvokeServer("collect") end))
			elseif not owner then
				n += 1
				row(phoneList, n, "Buy this business", "", act(function() remoteNamed("BusinessAction"):InvokeServer("buy") end))
			end
		end
		for _, b in pairs(prof.business or {}) do
			n += 1
			row(phoneList, n, b.name, "$" .. b.bank .. " till")
		end
		if n == 0 then
			row(phoneList, 1, "Own a Chester store", "")
			row(phoneList, 2, "Stand in one and open Biz", "")
		end
	else
		local j = jobInfo()
		if j and j.type == "delivery" then
			row(phoneList, 1, "Delivery: " .. j.store, "$" .. (j.pay or 0))
			row(phoneList, 2, "To " .. tostring(j.address), "")
			row(phoneList, 3, "Follow the orange line", "")
		elseif j and j.type == "ride" then
			row(phoneList, 1, "Rideshare", "$" .. (j.pay or 0))
			row(phoneList, 2, (j.stage == "pickup" and "Pick up on " or "Drop off on ") .. tostring(j.address), "")
			row(phoneList, 3, "Stop next to the marker", "")
		elseif j then
			row(phoneList, 1, "Stock shift: " .. j.store, "")
			row(phoneList, 2, "Crates stocked", j.done .. "/" .. j.total)
			row(phoneList, 3, j.carrying and "Carry it to a shelf" or "Grab a crate (back room)", "")
		else
			row(phoneList, 1, "Drive rideshare (in your car)", "", act(function() remoteNamed("StartRideshare"):InvokeServer() end))
			row(phoneList, 2, "Gas stations & markets: stock shifts", "")
			row(phoneList, 3, "Takeout spots: food deliveries", "")
			row(phoneList, 4, "Ask at the counter: F / X", "")
		end
		if j then
			local quit = row(phoneList, 9, "Quit job", "", function() QuitJob:FireServer() end)
			quit.BackgroundColor3 = Color3.fromRGB(70, 36, 36)
		end
	end
	if tab == "closet" and phone.Visible and fromList then
		-- keep the gamepad on the same row across a redraw
		local target = nil
		for _, b in ipairs(listRows) do
			if b.LayoutOrder == keepOrder then target = b break end
		end
		GuiService.SelectedObject = target or listRows[1] or tabButtons.closet
	end
end

-- Bike Life pushes its state whenever a rideout / wheelie / stat changes
task.spawn(function()
	local event = remotes:WaitForChild("BikeLifeChanged", 60)
	if event then
		event.OnClientEvent:Connect(function(state)
			if type(state) == "table" then bikeState = state end
			if phone.Visible and tab == "rideout" and drawPhone then drawPhone() end
		end)
	end
end)

openTab = function(name)
	if shop.Visible then closeAll() end
	tab = name
	phone.Visible = true
	drawPhone()
	GuiService.SelectedObject = tabButtons[tab]
end
task.spawn(function()
	local ev = remotes:WaitForChild("OpenPhoneTab", 60)
	if ev then ev.OnClientEvent:Connect(function(name) if tabButtons[name] then openTab(name) end end) end
end)

local function togglePhone()
	if shop.Visible then closeAll() return end
	phone.Visible = not phone.Visible
	if phone.Visible then
		drawPhone()
		GuiService.SelectedObject = tabButtons[tab]
	else
		GuiService.SelectedObject = nil
	end
end

-- P, D-pad Up (on foot; in tester flight it is the speed tier) or View / Select
ContextActionService:BindActionAtPriority("Exit6Phone", function(_, state, input)
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
	local mainMenu = player.PlayerGui:FindFirstChild("Exit6MainMenu")
	if mainMenu and mainMenu.Enabled then return Enum.ContextActionResult.Pass end
	if input.KeyCode == Enum.KeyCode.DPadUp and player:GetAttribute("CW_Flying") then return Enum.ContextActionResult.Pass end
	togglePhone()
	return Enum.ContextActionResult.Sink
end, false, 3000, Enum.KeyCode.P, Enum.KeyCode.DPadUp, Enum.KeyCode.ButtonSelect)

-- on-screen phone button (mouse / touch; also shows the keys)
local phoneButton = new("TextButton", { Name = "PhoneButton", AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -16, 1, -16), Size = UDim2.fromOffset(150, 44), BackgroundColor3 = INK,
	BackgroundTransparency = 0.1, Text = "PHONE  [P / ▲]", Font = Enum.Font.GothamBold, TextSize = 16,
	TextColor3 = ACCENT, AutoButtonColor = true, Selectable = false }, gui)
round(phoneButton, 10)
phoneButton.Activated:Connect(togglePhone)
RunService.Heartbeat:Connect(function()
	phoneButton.Visible = not phone.Visible and not shop.Visible
end)

local function closePhoneAndShop()
	if not (shop.Visible or phone.Visible) then return end
	closeAll()
	phone.Visible = false
	GuiService.SelectedObject = nil
end

-- Explicit close button for mouse/touch and gamepad selection.
local closePhoneButton = new("TextButton", {
	Name = "ClosePhone", AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 8), Size = UDim2.fromOffset(44, 44),
	BackgroundColor3 = CARD, Text = "X", Font = Enum.Font.GothamBold,
	TextSize = 22, TextColor3 = TEXT, ZIndex = 5,
}, phone)
round(closePhoneButton, 8)
closePhoneButton.Activated:Connect(closePhoneAndShop)

ContextActionService:BindActionAtPriority("Exit6CloseShop", function(_, state)
	if state ~= Enum.UserInputState.Begin or not (shop.Visible or phone.Visible) then
		return Enum.ContextActionResult.Pass
	end
	closePhoneAndShop()
	return Enum.ContextActionResult.Sink
end, false, 4000, Enum.KeyCode.Backspace, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)

for _, name in ipairs({ "Exit6Inventory", "Exit6Job", "Exit6Profile" }) do
	player:GetAttributeChangedSignal(name):Connect(function()
		if phone.Visible then drawPhone() end
		if name == "Exit6Profile" and shop.Visible then drawShop() end
	end)
end
task.spawn(function()
	local ls = player:WaitForChild("leaderstats", 30)
	local c = ls and ls:WaitForChild("Chester Cash", 10)
	if c then
		c:GetPropertyChangedSignal("Value"):Connect(function()
			if shop.Visible then drawShop() end
			if phone.Visible then drawPhone() end
		end)
	end
end)

-- walking away from the counter closes the shop
RunService.Heartbeat:Connect(function()
	if not openShop then return end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or (typeof(openShop.pos) == "Vector3" and (root.Position - openShop.pos).Magnitude > 22) then
		closeAll()
	end
end)

-- ------------------------------------------------------------------ job HUD
local hud = new("Frame", { Name = "JobHUD", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 116),
	Size = UDim2.fromOffset(380, 56), BackgroundColor3 = INK, BackgroundTransparency = 0.15, Visible = false }, gui)
round(hud, 10)
local hudTop = new("TextLabel", { Position = UDim2.fromOffset(14, 4), Size = UDim2.new(1, -28, 0, 24), BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold, TextSize = 17, TextColor3 = TEXT, TextXAlignment = Enum.TextXAlignment.Left }, hud)
local hudBottom = new("TextLabel", { Position = UDim2.fromOffset(14, 28), Size = UDim2.new(1, -28, 0, 22), BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium, TextSize = 14, TextColor3 = ACCENT, TextXAlignment = Enum.TextXAlignment.Left }, hud)
local job = nil
player:GetAttributeChangedSignal("Exit6Job"):Connect(function() job = jobInfo() end)
job = jobInfo()
RunService.RenderStepped:Connect(function()
	hud.Visible = job ~= nil
	if not job then return end
	local left = math.max(0, math.floor(job.deadline - Workspace:GetServerTimeNow()))
	if job.type == "delivery" or job.type == "ride" then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local t = job.target
		local d = (root and t) and math.floor((root.Position - Vector3.new(t[1], t[2], t[3])).Magnitude) or 0
		hudTop.Text = job.type == "ride" and string.format("RIDESHARE  %s   $%d", job.stage == "pickup" and "PICK UP" or "DROP OFF", job.pay or 0)
			or string.format("DELIVERY  %s   $%d", job.store, job.pay or 0)
		hudBottom.Text = string.format("To %s  -  %d studs   %d:%02d", tostring(job.address), d, left // 60, left % 60)
	else
		hudTop.Text = string.format("STOCK SHIFT  %s   %d/%d", job.store, job.done, job.total)
		hudBottom.Text = string.format("%s   %d:%02d", job.carrying and "Carry the crate to a shelf" or "Grab a crate from the back room",
			left // 60, left % 60)
	end
end)

-- ------------------------------------------------------------------ delivery waypoint
-- a local marker, line and "Deliver" prompt at the drop-off door: only the
-- courier sees them; the server checks the courier is there (Exit6Delivery)
local marker = nil
local function clearMarker()
	if marker then marker:Destroy() marker = nil end
end
local function showMarker()
	clearMarker()
	if not job or (job.type ~= "delivery" and job.type ~= "ride") or type(job.target) ~= "table" then return end
	local t = Vector3.new(job.target[1], job.target[2], job.target[3])
	marker = new("Part", { Name = "Exit6DropOff", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
		Transparency = 1, Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(t + Vector3.new(0, 1.5, 0)) }, Workspace)
	local ring = new("Part", { Name = "Ring", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
		Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = ACCENT, Transparency = 0.35,
		Size = Vector3.new(0.2, 7, 7), CFrame = CFrame.new(t - Vector3.new(0, 1.4, 0)) * CFrame.Angles(0, 0, math.rad(90)) }, marker)
	local bb = new("BillboardGui", { Size = UDim2.fromOffset(170, 44), StudsOffset = Vector3.new(0, 6, 0), AlwaysOnTop = true,
		LightInfluence = 0, MaxDistance = 100000 }, marker)
	new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BackgroundTransparency = 0.2, TextColor3 = ACCENT,
		Font = Enum.Font.GothamBlack, TextSize = 18, Text = (job.type == "ride" and job.stage == "pickup") and "PICKUP" or "DROP-OFF" }, bb)
	local a1 = new("Attachment", {}, marker)
	if job.type == "delivery" then
		local prompt = new("ProximityPrompt", { ActionText = "Deliver order", ObjectText = job.store, HoldDuration = 0.4,
			MaxActivationDistance = 10, RequiresLineOfSight = false }, marker)
		prompt.Triggered:Connect(function() remotes:WaitForChild("Deliver"):FireServer() end)
	end
	local function link()
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not root or not marker then return end
		local a0 = root:FindFirstChild("Exit6WaypointAttach") or new("Attachment", { Name = "Exit6WaypointAttach" }, root)
		new("Beam", { Attachment0 = a0, Attachment1 = a1, Color = ColorSequence.new(ACCENT), Width0 = 0.6, Width1 = 0.6,
			FaceCamera = true, LightEmission = 0.6, Transparency = NumberSequence.new(0.25), Segments = 1 }, marker)
	end
	link()
end
local lastTarget = nil
local function onJob()
	job = jobInfo()
	local key = job and (job.type == "delivery" or job.type == "ride") and table.concat(job.target or {}, ",") or nil
	if key ~= lastTarget then
		lastTarget = key
		showMarker()
	end
end
player:GetAttributeChangedSignal("Exit6Job"):Connect(onJob)
player.CharacterAdded:Connect(function() lastTarget = nil onJob() end)
onJob()
