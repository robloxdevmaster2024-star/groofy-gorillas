--!nonstrict
-- StatusHud.client.luau — Affiche les messages du serveur.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameStatus = ReplicatedStorage:WaitForChild("GameStatus")
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "GoofyStatus"
gui.ResetOnSpawn = false
gui.Parent = playerGui

-- Bandeau d'annonces (centre haut)
local banner = Instance.new("TextLabel")
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0.06, 0)
banner.Size = UDim2.new(0, 620, 0, 56)
banner.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
banner.BackgroundTransparency = 0.25
banner.TextColor3 = Color3.fromRGB(255, 255, 255)
banner.TextScaled = true
banner.Font = Enum.Font.FredokaOne
banner.Text = ""
banner.Visible = false
banner.Parent = gui
Instance.new("UICorner", banner).CornerRadius = UDim.new(0, 14)

-- Timer (coin haut droit)
local timer = Instance.new("TextLabel")
timer.AnchorPoint = Vector2.new(1, 0)
timer.Position = UDim2.new(1, -16, 0, 16)
timer.Size = UDim2.new(0, 120, 0, 44)
timer.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
timer.BackgroundTransparency = 0.25
timer.TextColor3 = Color3.fromRGB(255, 230, 120)
timer.TextScaled = true
timer.Font = Enum.Font.FredokaOne
timer.Text = ""
timer.Parent = gui
Instance.new("UICorner", timer).CornerRadius = UDim.new(0, 10)

-- Affiche un bandeau puis le masque après 4s (le dernier message gagne)
local token = 0
local function showBanner(text)
	banner.Text = text
	banner.Visible = true
	token += 1
	local my = token
	task.delay(4, function()
		if my == token then banner.Visible = false end
	end)
end

GameStatus.OnClientEvent:Connect(function(msg)
	if type(msg) ~= "table" then return end
	if msg.kind == "timer" then
		timer.Text = msg.text
	elseif msg.kind == "banner" then
		showBanner(msg.text)
	end
end)