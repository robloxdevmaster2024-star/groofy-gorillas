--!nonstrict
-- InfectorInput.client.luau — Saisie du coup de batte (Infector / « Le Clown de nuit »).
-- Actif uniquement pour le(s) joueur(s) déjà transformé(s) en clown, via RemoteEvent "SetActive".

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Attente des events (créés par Infector.luau au démarrage serveur)
local eventsFolder  = ReplicatedStorage:WaitForChild("InfectorEvents")
local swingEvent    = eventsFolder:WaitForChild("Swing")
local setActiveEvent = eventsFolder:WaitForChild("SetActive")

local isActive      = false
local inputConns : { RBXScriptConnection } = {}
local lastSwingTime = 0
local COOLDOWN_HINT = 0.8 -- légèrement inférieur au serveur pour absorber la latence

-- ===== Bouton mobile =====
local swingButton: TextButton?

local function createMobileButton()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "InfectorMobileUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = player.PlayerGui

	local btn = Instance.new("TextButton")
	btn.Name = "SwingBtn"
	btn.Size = UDim2.new(0, 120, 0, 120)
	btn.Position = UDim2.new(1, -150, 1, -160)
	btn.AnchorPoint = Vector2.new(0, 0)
	btn.BackgroundColor3 = Color3.fromRGB(200, 30, 130)
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Text = "🏏\nFRAPPER"
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 20
	btn.AutoButtonColor = true
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0.5, 0)
	btn.Parent = screenGui

	swingButton = btn
	return screenGui
end

local mobileGui: ScreenGui?

-- ===== Logique du swing =====
local function trySwing()
	if not isActive then return end
	local now = tick()
	if (now - lastSwingTime) < COOLDOWN_HINT then return end
	lastSwingTime = now
	swingEvent:FireServer(camera.CFrame.LookVector)
end

-- ===== Activation / désactivation =====
local function activate()
	isActive = true

	-- PC : clic gauche
	table.insert(inputConns, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			trySwing()
		end
	end))

	-- Mobile : bouton dédié (évite le conflit avec le swipe caméra)
	if UserInputService.TouchEnabled then
		mobileGui = createMobileButton()
		if swingButton then
			table.insert(inputConns, swingButton.MouseButton1Click:Connect(trySwing))
		end
	end
end

local function deactivate()
	isActive = false
	for _, conn in inputConns do conn:Disconnect() end
	inputConns = {}
	if mobileGui and mobileGui.Parent then mobileGui:Destroy() end
	mobileGui = nil
	swingButton = nil
end

-- ===== Écoute du signal serveur =====
-- true : ce joueur vient de devenir clown (activation individuelle)
-- false : fin de round, désactivation globale (fired à tous via FireAllClients)
setActiveEvent.OnClientEvent:Connect(function(active: boolean)
	if active then
		activate()
	else
		deactivate()
	end
end)
