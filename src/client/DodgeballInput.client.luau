--!nonstrict
-- DodgeballInput.client.luau — Saisie du lancer (Dodgeball) côté client.
-- Actif uniquement pendant un round Dodgeball (signal via RemoteEvent "Active").

local Players            = game:GetService("Players")
local UserInputService   = game:GetService("UserInputService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Attente des events (créés par Dodgeball.luau au démarrage serveur)
local eventsFolder = ReplicatedStorage:WaitForChild("DodgeballEvents")
local throwEvent   = eventsFolder:WaitForChild("Throw")
local activeEvent  = eventsFolder:WaitForChild("Active")

local isActive      = false
local inputConns : { RBXScriptConnection } = {}
local lastThrowTime = 0
local COOLDOWN_HINT = 1.0 -- légèrement inférieur au serveur pour absorber la latence

-- ===== Bouton mobile =====
local throwButton: TextButton?

local function createMobileButton()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DodgeballMobileUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = player.PlayerGui

	local btn = Instance.new("TextButton")
	btn.Name = "ThrowBtn"
	btn.Size = UDim2.new(0, 120, 0, 120)
	btn.Position = UDim2.new(1, -150, 1, -160)
	btn.AnchorPoint = Vector2.new(0, 0)
	btn.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Text = "🔴\nLANCER"
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 20
	btn.AutoButtonColor = true
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0.5, 0)
	btn.Parent = screenGui

	throwButton = btn
	return screenGui
end

local mobileGui: ScreenGui?

-- ===== Logique de lancer =====
local function tryThrow()
	if not isActive then return end
	local now = tick()
	if (now - lastThrowTime) < COOLDOWN_HINT then return end
	lastThrowTime = now
	throwEvent:FireServer(camera.CFrame.LookVector)
end

-- ===== Activation / désactivation =====
local function activate()
	isActive = true

	-- PC : clic gauche
	table.insert(inputConns, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			tryThrow()
		end
	end))

	-- Mobile : bouton dédié (évite le conflit avec le swipe caméra)
	if UserInputService.TouchEnabled then
		mobileGui = createMobileButton()
		if throwButton then
			table.insert(inputConns, throwButton.MouseButton1Click:Connect(tryThrow))
		end
	end
end

local function deactivate()
	isActive = false
	for _, conn in inputConns do conn:Disconnect() end
	inputConns = {}
	if mobileGui and mobileGui.Parent then mobileGui:Destroy() end
	mobileGui = nil
	throwButton = nil
end

-- ===== Écoute du signal serveur =====
activeEvent.OnClientEvent:Connect(function(active: boolean)
	if active then
		activate()
	else
		deactivate()
	end
end)
