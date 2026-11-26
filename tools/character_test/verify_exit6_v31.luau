-- Run in the separate character test place after importing the revised assets.
local SS = game:GetService("ServerStorage")
local SP = game:GetService("StarterPlayer")
local char = SP:FindFirstChild("StarterCharacter")
assert(char and char:GetAttribute("Exit6V31") == true, "V3.1 StarterCharacter missing")
local hum = char:FindFirstChildOfClass("Humanoid")
assert(hum and hum.RigType == Enum.HumanoidRigType.R15, "expected R15 Humanoid")
assert(char:FindFirstChild("HumanoidRootPart"), "HumanoidRootPart missing")
local body = { "Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
	"RightUpperLeg", "RightLowerLeg", "RightFoot" }
for _, name in body do
	local part = char:FindFirstChild(name)
	assert(part and part:IsA("MeshPart") and part:FindFirstChildOfClass("WrapTarget"), name .. " cage missing")
end
local wear = SS:FindFirstChild("Exit6_V31_Wear")
assert(wear, "wear library missing")
for name, order in { Exit6_Briefs = 1, Exit6_Sneakers = 3, Exit6_Cargo = 4, Exit6_Puffer = 6 } do
	local accessory = wear:FindFirstChild(name)
	local handle = accessory and accessory:FindFirstChild("Handle")
	local layer = handle and handle:FindFirstChildOfClass("WrapLayer")
	assert(layer and layer.Order == order, name .. " WrapLayer/order missing")
end
assert(wear:FindFirstChild("Exit6_Chain") and wear:FindFirstChild("Exit6_Chain_Over"),
	"chain variants missing")
local seen = {}
for _, item in char:GetChildren() do
	if item:IsA("Accessory") then seen[item.Name] = true end
end
assert(seen.Exit6_Chain_Over and not seen.Exit6_Chain, "jacket should use chain-over variant")
return { bodyParts = #body, rigType = tostring(hum.RigType), hipHeight = hum.HipHeight,
	wrapOrder = "briefs < sneakers < cargo < puffer", chain = "over" }
