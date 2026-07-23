--!nonstrict
-- ClownSurvivalProne.client.luau — Bouton "SE COUCHER" affiché uniquement pour les survivants
-- (pas les clowns) pendant le round Clown Survival. Bascule (toggle) : PC = touche C,
-- mobile = tap direct sur le bouton. Toute la logique (validité, hitbox, vitesse) est gérée
-- côté serveur — ce script ne fait qu'envoyer l'intention et refléter l'état côté affichage.

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local eventsFolder        = ReplicatedStorage:WaitForChild("ClownSurvivalEvents")
local proneAvailableEvent = eventsFolder:WaitForChild("ProneAvailable")
local proneEvent          = eventsFolder:WaitForChild("ToggleProne")
local proneStateEvent     = eventsFolder:WaitForChild("ProneState")

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- État affiché localement, basculé de façon optimiste au clic pour un retour instantané, MAIS
-- toujours resynchronisé sur la confirmation serveur (ProneState) juste après : le serveur peut
-- refuser (ex. épuisé, glissade en cours), auquel cas le bouton doit revenir à son état réel au
-- lieu de rester bloqué sur "SE RELEVER" pendant que le personnage ne fait rien.
local isProne = false

-- ===== Construction du bouton =====
local gui = Instance.new("ScreenGui")
gui.Name = "ClownSurvivalProneUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.Parent = playerGui

local button = Instance.new("TextButton")
button.Name = "ProneBtn"
button.AnchorPoint = Vector2.new(1, 0.5)
button.Position = UDim2.new(1, -20, 0.5, -80)
button.Size = UDim2.new(0, 150, 0, 64)
button.BackgroundColor3 = Color3.fromRGB(50, 60, 40)
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

local icon = Instance.new("TextLabel")
icon.BackgroundTransparency = 1
icon.Size = UDim2.new(0, 34, 0, 34)
icon.Text = "🧎"
icon.TextScaled = true
icon.LayoutOrder = 1
icon.Parent = button

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

local actionLabel = Instance.new("TextLabel")
actionLabel.BackgroundTransparency = 1
actionLabel.Size = UDim2.new(1, 0, 0, 22)
actionLabel.Text = "SE COUCHER"
actionLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
actionLabel.Font = Enum.Font.FredokaOne
actionLabel.TextScaled = true
actionLabel.LayoutOrder = 1
actionLabel.Parent = labelColumn

-- Sur mobile, pas de touche clavier à afficher : juste le texte + l'icône, tap direct.
local keyHint: TextLabel? = nil
if not isMobile then
	keyHint = Instance.new("TextLabel")
	keyHint.BackgroundTransparency = 1
	keyHint.Size = UDim2.new(1, 0, 0, 18)
	keyHint.Text = "Touche C"
	keyHint.TextColor3 = Color3.fromRGB(210, 230, 190)
	keyHint.Font = Enum.Font.GothamBold
	keyHint.TextScaled = true
	keyHint.LayoutOrder = 2
	keyHint.Parent = labelColumn
end

-- ===== Logique du toggle =====
local function refreshVisual()
	if isProne then
		icon.Text = "🧎‍♂️"
		actionLabel.Text = "SE RELEVER"
		button.BackgroundColor3 = Color3.fromRGB(90, 110, 60)
	else
		icon.Text = "🧎"
		actionLabel.Text = "SE COUCHER"
		button.BackgroundColor3 = Color3.fromRGB(50, 60, 40)
	end
end

local function toggleProne()
	isProne = not isProne
	refreshVisual()
	proneEvent:FireServer()
end

button.MouseButton1Click:Connect(toggleProne)

local inputConn: RBXScriptConnection? = nil

local function activate()
	isProne = false
	refreshVisual()
	gui.Enabled = true
	if not isMobile and not inputConn then
		inputConn = UserInputService.InputBegan:Connect(function(input, processed)
			if processed then return end
			if input.KeyCode == Enum.KeyCode.C then
				toggleProne()
			end
		end)
	end
end

local function deactivate()
	gui.Enabled = false
	isProne = false
	if inputConn then
		inputConn:Disconnect()
		inputConn = nil
	end
end

proneAvailableEvent.OnClientEvent:Connect(function(active: boolean)
	if active then
		activate()
	else
		deactivate()
	end
end)

-- Confirmation de l'état réel par le serveur : corrige le bouton si le dernier appui a été refusé
-- (ou si l'état a changé sans appui, ex. forcé debout par un autre système).
proneStateEvent.OnClientEvent:Connect(function(actual: boolean)
	if actual ~= isProne then
		isProne = actual
		refreshVisual()
	end
end)
