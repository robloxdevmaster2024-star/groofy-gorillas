--!nonstrict
-- ClownSurvivalSprint.client.luau — Sprint + glissade pour tout le monde (clowns et survivants)
-- pendant le round Clown Survival.
-- PC : maintenir Shift pour sprinter, Ctrl pendant le sprint pour glisser.
-- Mobile : maintenir le bouton 🏃 pour sprinter, taper le bouton 🛼 pour glisser.
-- Toute la logique (vitesse, vidange/recharge de la jauge, validité de la glissade) est gérée
-- côté serveur — ce script se contente d'envoyer l'intention et d'afficher la jauge reçue.

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local eventsFolder        = ReplicatedStorage:WaitForChild("ClownSurvivalEvents")
local sprintAvailableEvent = eventsFolder:WaitForChild("SprintAvailable")
local setSprintingEvent    = eventsFolder:WaitForChild("SetSprinting")
local staminaUpdateEvent   = eventsFolder:WaitForChild("StaminaUpdate")
local slideEvent           = eventsFolder:WaitForChild("Slide")

local isActive = false
local isSprinting = false
local inputConns: { RBXScriptConnection } = {}

-- ===== UI : jauge de stamina =====
local gui = Instance.new("ScreenGui")
gui.Name = "ClownSurvivalSprintUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.Parent = playerGui

local barBg = Instance.new("Frame")
barBg.Name = "StaminaBar"
barBg.AnchorPoint = Vector2.new(0.5, 1)
barBg.Position = UDim2.new(0.5, 0, 1, -20)
barBg.Size = UDim2.new(0, 260, 0, 16)
barBg.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
barBg.BackgroundTransparency = 0.25
barBg.Parent = gui
Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 8)

local barFill = Instance.new("Frame")
barFill.Name = "Fill"
barFill.AnchorPoint = Vector2.new(0, 0.5)
barFill.Position = UDim2.new(0, 3, 0.5, 0)
barFill.Size = UDim2.new(1, -6, 1, -6)
barFill.BackgroundColor3 = Color3.fromRGB(90, 220, 120)
barFill.BorderSizePixel = 0
barFill.Parent = barBg
Instance.new("UICorner", barFill).CornerRadius = UDim.new(0, 6)

local function colorForStamina(fraction: number): Color3
	if fraction <= 0.25 then return Color3.fromRGB(230, 70, 70) end
	if fraction <= 0.55 then return Color3.fromRGB(240, 200, 60) end
	return Color3.fromRGB(90, 220, 120)
end

-- Le serveur n'envoie une valeur que ~10x/s (throttle réseau) : sans interpolation, la barre
-- "saute" visiblement d'une valeur à l'autre. On tween donc vers chaque nouvelle valeur avec une
-- durée un peu plus longue que l'intervalle d'envoi, pour un mouvement continu et fluide.
local STAMINA_TWEEN_DURATION = 0.15
local staminaTween: Tween? = nil

staminaUpdateEvent.OnClientEvent:Connect(function(fraction: number)
	if typeof(fraction) ~= "number" then return end
	fraction = math.clamp(fraction, 0, 1)

	if staminaTween then
		staminaTween:Cancel()
	end
	staminaTween = TweenService:Create(
		barFill,
		TweenInfo.new(STAMINA_TWEEN_DURATION, Enum.EasingStyle.Linear),
		{ Size = UDim2.new(fraction, -6 * fraction, 1, -6) }
	)
	staminaTween:Play()

	barFill.BackgroundColor3 = colorForStamina(fraction)
end)

-- ===== Boutons mobile (maintenir pour courir / taper pour glisser) =====
local sprintButton: TextButton?
local slideButton: TextButton?
local mobileGui: ScreenGui?

local function createMobileButtons()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ClownSurvivalSprintMobileUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = playerGui

	local sprintBtn = Instance.new("TextButton")
	sprintBtn.Name = "SprintBtn"
	sprintBtn.Size = UDim2.new(0, 110, 0, 110)
	sprintBtn.Position = UDim2.new(0, 30, 1, -160)
	sprintBtn.AnchorPoint = Vector2.new(0, 0)
	sprintBtn.BackgroundColor3 = Color3.fromRGB(40, 150, 90)
	sprintBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	sprintBtn.Text = "🏃\nCOURIR"
	sprintBtn.Font = Enum.Font.GothamBold
	sprintBtn.TextSize = 18
	sprintBtn.AutoButtonColor = true
	Instance.new("UICorner", sprintBtn).CornerRadius = UDim.new(0.5, 0)
	sprintBtn.Parent = screenGui

	local slideBtn = Instance.new("TextButton")
	slideBtn.Name = "SlideBtn"
	slideBtn.Size = UDim2.new(0, 90, 0, 90)
	slideBtn.Position = UDim2.new(0, 150, 1, -110)
	slideBtn.AnchorPoint = Vector2.new(0, 0)
	slideBtn.BackgroundColor3 = Color3.fromRGB(60, 110, 200)
	slideBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	slideBtn.Text = "🛼\nGLISSER"
	slideBtn.Font = Enum.Font.GothamBold
	slideBtn.TextSize = 14
	slideBtn.AutoButtonColor = true
	Instance.new("UICorner", slideBtn).CornerRadius = UDim.new(0.5, 0)
	slideBtn.Parent = screenGui

	sprintButton = sprintBtn
	slideButton = slideBtn
	return screenGui
end

-- ===== Logique du sprint =====
local function setSprinting(value: boolean)
	if not isActive then value = false end
	if value == isSprinting then return end
	isSprinting = value
	setSprintingEvent:FireServer(value)
end

-- ===== Logique de la glissade =====
-- Aucun check côté client sur l'état de sprint : le serveur tolère une glissade juste après
-- avoir sprinté (pas besoin de tenir Shift ET Ctrl exactement en même temps), c'est donc lui
-- seul juge de la fenêtre de tolérance.
local function trySlide()
	if not isActive then return end
	slideEvent:FireServer()
end

local function activate()
	isActive = true
	gui.Enabled = true

	-- PC : maintenir Shift pour sprinter, Ctrl (pendant le sprint) pour glisser
	table.insert(inputConns, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			setSprinting(true)
		elseif input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
			trySlide()
		end
	end))
	table.insert(inputConns, UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			setSprinting(false)
		end
	end))

	-- Mobile : bouton 🏃 à maintenir pour courir, bouton 🛼 à taper pour glisser
	if UserInputService.TouchEnabled then
		mobileGui = createMobileButtons()
		if sprintButton then
			table.insert(inputConns, sprintButton.MouseButton1Down:Connect(function()
				setSprinting(true)
			end))
			table.insert(inputConns, sprintButton.MouseButton1Up:Connect(function()
				setSprinting(false)
			end))
			table.insert(inputConns, sprintButton.MouseLeave:Connect(function()
				setSprinting(false)
			end))
		end
		if slideButton then
			table.insert(inputConns, slideButton.MouseButton1Click:Connect(trySlide))
		end
	end
end

local function deactivate()
	isActive = false
	gui.Enabled = false
	setSprinting(false)
	for _, conn in inputConns do conn:Disconnect() end
	inputConns = {}
	if mobileGui and mobileGui.Parent then mobileGui:Destroy() end
	mobileGui = nil
	sprintButton = nil
	slideButton = nil
end

sprintAvailableEvent.OnClientEvent:Connect(function(active: boolean)
	if active then
		activate()
	else
		deactivate()
	end
end)
