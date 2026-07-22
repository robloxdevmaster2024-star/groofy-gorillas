--!nonstrict
-- ClownSurvivalTaunt.client.luau — Bouton "TAUNT" affiché uniquement pour les survivants
-- (pas les clowns) pendant le round Clown Survival. PC : touche F. Mobile : appui direct sur le bouton.

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player  = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local eventsFolder        = ReplicatedStorage:WaitForChild("ClownSurvivalEvents")
local tauntAvailableEvent = eventsFolder:WaitForChild("TauntAvailable")
local tauntEvent          = eventsFolder:WaitForChild("Taunt")

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local lastTauntTime = 0
local TAUNT_COOLDOWN_HINT = 1.8 -- légèrement inférieur au cooldown serveur (2s)
-- Le son du rire est désormais joué par le serveur, en positionnel sur le personnage
-- (voir ClownSurvival.luau → playTauntSound()), pour être entendu par les autres joueurs à proximité.

-- ===== Construction du bouton =====
local gui = Instance.new("ScreenGui")
gui.Name = "ClownSurvivalTauntUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.Parent = playerGui

local button = Instance.new("TextButton")
button.Name = "TauntBtn"
button.AnchorPoint = Vector2.new(1, 0.5)
button.Position = UDim2.new(1, -20, 0.5, 0)
button.Size = UDim2.new(0, 150, 0, 64)
button.BackgroundColor3 = Color3.fromRGB(60, 30, 90)
button.BackgroundTransparency = 0.1
button.AutoButtonColor = true
button.Text = ""
button.Parent = gui
Instance.new("UICorner", button).CornerRadius = UDim.new(0, 14)

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Padding = UDim.new(0, 4)
layout.Parent = button

local trollIcon = Instance.new("TextLabel")
trollIcon.BackgroundTransparency = 1
trollIcon.Size = UDim2.new(0, 34, 0, 34)
trollIcon.Text = "🧌"
trollIcon.TextScaled = true
trollIcon.LayoutOrder = 1
trollIcon.Parent = button

local labelColumn = Instance.new("Frame")
labelColumn.BackgroundTransparency = 1
labelColumn.Size = UDim2.new(0, 80, 1, 0)
labelColumn.LayoutOrder = 2
labelColumn.Parent = button

local columnLayout = Instance.new("UIListLayout")
columnLayout.FillDirection = Enum.FillDirection.Vertical
columnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
columnLayout.VerticalAlignment = Enum.VerticalAlignment.Center
columnLayout.Parent = labelColumn

local tauntLabel = Instance.new("TextLabel")
tauntLabel.BackgroundTransparency = 1
tauntLabel.Size = UDim2.new(1, 0, 0, 22)
tauntLabel.Text = "TAUNT"
tauntLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
tauntLabel.Font = Enum.Font.FredokaOne
tauntLabel.TextScaled = true
tauntLabel.LayoutOrder = 1
tauntLabel.Parent = labelColumn

-- Sur mobile, pas de touche clavier à afficher : juste "TAUNT" + le troll, tap direct.
if not isMobile then
	local keyHint = Instance.new("TextLabel")
	keyHint.BackgroundTransparency = 1
	keyHint.Size = UDim2.new(1, 0, 0, 18)
	keyHint.Text = "Touche F"
	keyHint.TextColor3 = Color3.fromRGB(220, 190, 255)
	keyHint.Font = Enum.Font.GothamBold
	keyHint.TextScaled = true
	keyHint.LayoutOrder = 2
	keyHint.Parent = labelColumn
end

-- ===== Logique du taunt =====
local function tryTaunt()
	local now = tick()
	if (now - lastTauntTime) < TAUNT_COOLDOWN_HINT then return end
	lastTauntTime = now
	tauntEvent:FireServer()
end

button.MouseButton1Click:Connect(tryTaunt)

local inputConn: RBXScriptConnection? = nil

local function activate()
	gui.Enabled = true
	if not isMobile and not inputConn then
		inputConn = UserInputService.InputBegan:Connect(function(input, processed)
			if processed then return end
			if input.KeyCode == Enum.KeyCode.F then
				tryTaunt()
			end
		end)
	end
end

local function deactivate()
	gui.Enabled = false
	if inputConn then
		inputConn:Disconnect()
		inputConn = nil
	end
end

tauntAvailableEvent.OnClientEvent:Connect(function(active: boolean)
	if active then
		activate()
	else
		deactivate()
	end
end)
