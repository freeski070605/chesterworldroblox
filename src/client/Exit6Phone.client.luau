-- EXIT 6 shop menu, job HUD and phone (Wallet / Bag / Job). Client-side only:
-- every purchase / use goes through Exit6Remotes and is decided by the server
-- (Exit6Shop.server.luau). Keyboard, mouse, touch and gamepad.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")
local HttpService = game:GetService("HttpService")
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
local UseItem = remotes:WaitForChild("UseItem")

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

local function closeAll()
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
	for i, it in ipairs(openShop.items) do
		local b = row(shopList, i, it.name, "$" .. it.price, function()
			if busy then return end
			busy = true
			-- the server answers with a notice either way (Exit6HUD toast)
			pcall(function() Purchase:InvokeServer(openShop and openShop.storeId, it.id) end)
			busy = false
			drawShop()
		end)
		if it.price > c then b.BackgroundColor3 = Color3.fromRGB(52, 40, 40) end
		if keep == i or not first then first = b end
	end
	local leave = row(shopList, 999, "Leave", "", closeAll)
	leave.BackgroundColor3 = Color3.fromRGB(28, 32, 40)
	if GuiService.SelectedObject == nil or not GuiService.SelectedObject:IsDescendantOf(shop) then
		GuiService.SelectedObject = (keep == 999) and leave or first or leave
	end
end

ShopOpen.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	gui.Phone.Visible = false
	openShop = payload
	shop.Visible = true
	GuiService.SelectedObject = nil
	drawShop()
end)

-- ------------------------------------------------------------------ phone
local phone, phoneTitle, phoneSub, phoneList = panel("Phone", 340)
phone.AnchorPoint = Vector2.new(1, 1)
phone.Position = UDim2.new(1, -16, 1, -16)
phone.Hint.Text = "P / SELECT  CLOSE      A  USE ITEM"
local tab = "wallet"
local tabs = new("Frame", { Position = UDim2.fromOffset(12, 64), Size = UDim2.new(1, -24, 0, 30), BackgroundTransparency = 1 }, phone)
phoneList.Position = UDim2.fromOffset(12, 102)
phoneList.Size = UDim2.new(1, -24, 1, -142)
local drawPhone
local tabButtons = {}
for i, t in ipairs({ { "wallet", "Wallet" }, { "bag", "Bag" }, { "job", "Job" } }) do
	local b = new("TextButton", { Name = t[1], Position = UDim2.new((i - 1) / 3, 2, 0, 0), Size = UDim2.new(1 / 3, -4, 1, 0),
		BackgroundColor3 = CARD, Text = t[2], Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = TEXT }, tabs)
	round(b, 6)
	b.Activated:Connect(function() tab = t[1] drawPhone() end)
	tabButtons[t[1]] = b
end
phoneSub.Position = UDim2.fromOffset(18, 40)

local function jobInfo()
	local raw = player:GetAttribute("Exit6Job")
	local ok, j = pcall(function() return raw and HttpService:JSONDecode(raw) end)
	return ok and type(j) == "table" and j or nil
end

drawPhone = function()
	local c, r = cash()
	phoneTitle.Text = os.date("%I:%M %p"):gsub("^0", "")
	phoneSub.Text = "Chester, PA"
	for k, b in pairs(tabButtons) do b.BackgroundColor3 = (k == tab) and ACCENT or CARD end
	clearList(phoneList)
	if tab == "wallet" then
		row(phoneList, 1, "Chester Cash", "$" .. c)
		row(phoneList, 2, "Reputation", tostring(r))
	elseif tab == "bag" then
		local items, n = bag(), 0
		local ids = {}
		for id in pairs(items) do table.insert(ids, id) end
		table.sort(ids)
		for _, id in ipairs(ids) do
			local item = Catalog.Items[id]
			if item then
				n += 1
				row(phoneList, n, item.name, "x" .. items[id], function()
					UseItem:InvokeServer(id)
					drawPhone()
				end)
			end
		end
		if n == 0 then row(phoneList, 1, "Empty - buy something at a store", "") end
	else
		local j = jobInfo()
		if j then
			row(phoneList, 1, "Stock shift: " .. j.store, "")
			row(phoneList, 2, "Crates stocked", j.done .. "/" .. j.total)
			row(phoneList, 3, j.carrying and "Carry it to a shelf" or "Grab a crate (back room)", "")
		else
			row(phoneList, 1, "No shift", "")
			row(phoneList, 2, "Gas stations & markets are hiring", "")
			row(phoneList, 3, "Talk at the counter: F / X", "")
		end
	end
end

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

ContextActionService:BindAction("Exit6Phone", function(_, state)
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
	if gui.Parent and player.PlayerGui:FindFirstChild("Exit6MainMenu") then return Enum.ContextActionResult.Pass end
	togglePhone()
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.P, Enum.KeyCode.ButtonSelect)

ContextActionService:BindAction("Exit6CloseShop", function(_, state)
	if state ~= Enum.UserInputState.Begin or not (shop.Visible or phone.Visible) then
		return Enum.ContextActionResult.Pass
	end
	closeAll()
	phone.Visible = false
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.Backspace, Enum.KeyCode.ButtonB)

for _, name in ipairs({ "Exit6Inventory", "Exit6Job" }) do
	player:GetAttributeChangedSignal(name):Connect(function()
		if phone.Visible then drawPhone() end
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
local hud = new("Frame", { Name = "JobHUD", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12),
	Size = UDim2.fromOffset(360, 56), BackgroundColor3 = INK, BackgroundTransparency = 0.15, Visible = false }, gui)
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
	hudTop.Text = string.format("STOCK SHIFT  %s   %d/%d", job.store, job.done, job.total)
	hudBottom.Text = string.format("%s   %d:%02d", job.carrying and "Carry the crate to a shelf" or "Grab a crate from the back room",
		left // 60, left % 60)
end)
