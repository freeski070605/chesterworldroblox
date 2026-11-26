-- Reversible place-level character switch. Set the DataModel attribute
-- Exit6V31CharacterEnabled in the isolated test/integration place only.
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local backup
local installed
local function update()
	local enabled = game:GetAttribute("Exit6V31CharacterEnabled") == true
	local source = ServerStorage:FindFirstChild("Exit6_V31_Character")
	if enabled and source and not installed then
		local old = StarterPlayer:FindFirstChild("StarterCharacter")
		if old then
			if old:GetAttribute("Exit6V31") ~= true then backup = old:Clone() end
			old:Destroy()
		end
		installed = source:Clone()
		installed.Name = "StarterCharacter"
		installed:SetAttribute("Exit6V31", true)
		installed.Parent = StarterPlayer
	elseif (not enabled or not source) and installed then
		if installed.Parent then installed:Destroy() end
		installed = nil
		if backup then backup.Parent = StarterPlayer; backup = nil end
	end
end

game:GetAttributeChangedSignal("Exit6V31CharacterEnabled"):Connect(update)
ServerStorage.ChildAdded:Connect(function(child)
	if child.Name == "Exit6_V31_Character" then update() end
end)
update()
