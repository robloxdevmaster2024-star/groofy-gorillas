--!nonstrict
-- ClownSurvivalClownAbilities.client.luau — Capacités actives du clown : Dash (mobilité courte,
-- cooldown court) et Vision (révèle les survivants à travers les murs, cooldown long).
-- PC : touche Q (dash) / R (vision). Mobile : boutons dédiés 💨/👁️.
--
-- Le cooldown affiché ne démarre qu'à la CONFIRMATION serveur (DashPerformed pour soi-même /
-- VisionGranted), jamais de façon optimiste au clic — sinon un appui refusé (encore en cooldown,
-- déjà mort, etc.) laisserait le bouton bloqué en cooldown alors que rien ne s'est passé (même
-- classe de bug que le bouton "se coucher" avant sa correction).

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Lighting          = game:GetService("Lighting")
local TweenService      = game:GetService("TweenService")

local player  = Players.LocalPlayer
local camera  = workspace.CurrentCamera

local eventsFolder         = ReplicatedStorage:WaitForChild("ClownSurvivalEvents")
local dashAvailableEvent   = eventsFolder:WaitForChild("DashAvailable")
local dashRequestEvent     = eventsFolder:WaitForChild("DashRequest")
local dashPerformedEvent   = eventsFolder:WaitForChild("DashPerformed")
local visionAvailableEvent = eventsFolder:WaitForChild("VisionAvailable")
local visionRequestEvent   = eventsFolder:WaitForChild("VisionRequest")
local visionGrantedEvent   = eventsFolder:WaitForChild("VisionGranted")

-- Doivent rester synchronisés avec les constantes serveur (ClownSurvival.luau) : purement pour
-- l'affichage du compte à rebours, le serveur reste seul juge de la validité réelle.
local DASH_COOLDOWN   = 6.0
local DASH_DURATION   = 1.2 -- s, pour caler les effets (FOV/traînée) sur la durée réelle du dash
local VISION_COOLDOWN = 35.0
local REQUEST_LOCKOUT = 0.5 -- anti-spam pendant l'aller-retour réseau, avant confirmation

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- ===== UI =====
local gui = Instance.new("ScreenGui")
gui.Name = "ClownSurvivalAbilitiesUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local function buildAbilityButton(order: number, icon: string, label: string, keyHintText: string, color: Color3): (TextButton, TextLabel, TextLabel)
	local button = Instance.new("TextButton")
	button.Name = label .. "Btn"
	button.AnchorPoint = Vector2.new(0, 0.5)
	button.Position = UDim2.new(0, 20, 0.5, (order - 1) * 74 - 37)
	button.Size = UDim2.new(0, 150, 0, 64)
	button.BackgroundColor3 = color
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

	local iconLabel = Instance.new("TextLabel")
	iconLabel.BackgroundTransparency = 1
	iconLabel.Size = UDim2.new(0, 34, 0, 34)
	iconLabel.Text = icon
	iconLabel.TextScaled = true
	iconLabel.LayoutOrder = 1
	iconLabel.Parent = button

	local column = Instance.new("Frame")
	column.BackgroundTransparency = 1
	column.Size = UDim2.new(0, 90, 1, 0)
	column.LayoutOrder = 2
	column.Parent = button

	local columnLayout = Instance.new("UIListLayout")
	columnLayout.FillDirection = Enum.FillDirection.Vertical
	columnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	columnLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	columnLayout.Parent = column

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0, 20)
	nameLabel.Text = label
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextScaled = true
	nameLabel.LayoutOrder = 1
	nameLabel.Parent = column

	local statusLabel = Instance.new("TextLabel")
	statusLabel.BackgroundTransparency = 1
	statusLabel.Size = UDim2.new(1, 0, 0, 16)
	statusLabel.Text = isMobile and "Prêt" or keyHintText
	statusLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.TextScaled = true
	statusLabel.LayoutOrder = 2
	statusLabel.Parent = column

	return button, statusLabel, nameLabel
end

local dashButton, dashStatus = buildAbilityButton(1, "💨", "DASH", "Touche Q", Color3.fromRGB(60, 90, 160))
local visionButton, visionStatus = buildAbilityButton(2, "👁️", "VISION", "Touche R", Color3.fromRGB(90, 60, 140))
dashButton.Visible = false
visionButton.Visible = false

-- ===== Cooldown visuel générique =====
local function runCooldownDisplay(button: TextButton, statusLabel: TextLabel, keyHintText: string, duration: number)
	button.AutoButtonColor = false
	local startTime = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function()
		local remaining = duration - (os.clock() - startTime)
		if remaining <= 0 then
			statusLabel.Text = isMobile and "Prêt" or keyHintText
			button.AutoButtonColor = true
			conn:Disconnect()
			return
		end
		statusLabel.Text = string.format("%.1fs", remaining)
	end)
end

-- ===== Dash =====
local dashLocked = false

local function tryDash()
	if dashLocked then return end
	dashLocked = true
	task.delay(REQUEST_LOCKOUT, function() dashLocked = false end)
	dashRequestEvent:FireServer() -- direction calculée côté serveur (mouvement/orientation du perso, pas la caméra)
end

-- Traînée visuelle (renforcée : deux brins + largeur/durée calées sur DASH_DURATION), vue par
-- tout le monde, sur le personnage qui vient de dasher.
local function playDashTrail(dashPlayer: Player)
	local char = dashPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end

	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, 1.6, 0)
	top.Parent = hrp
	local mid = Instance.new("Attachment")
	mid.Position = Vector3.new(0, 0, 0)
	mid.Parent = hrp
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -1.6, 0)
	bottom.Parent = hrp

	local trailLifetime = DASH_DURATION + 0.15

	local function makeTrail(a0: Attachment, a1: Attachment, color: Color3, widthMax: number)
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = trailLifetime
		trail.Color = ColorSequence.new(color)
		trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, widthMax), NumberSequenceKeypoint.new(1, 0) })
		trail.Parent = hrp
		return trail
	end

	local trailTop = makeTrail(top, mid, Color3.fromRGB(230, 30, 130), 1)
	local trailBottom = makeTrail(mid, bottom, Color3.fromRGB(255, 220, 90), 0.6)

	task.delay(trailLifetime + 0.2, function()
		trailTop:Destroy()
		trailBottom:Destroy()
		top:Destroy()
		mid:Destroy()
		bottom:Destroy()
	end)
end

-- Kick de FOV : uniquement pour le clown qui dashe (sensation subjective de vitesse), la traînée
-- ci-dessus étant elle vue par tout le monde.
local function playDashFovKick()
	local baseFov = camera.FieldOfView
	camera.FieldOfView = baseFov + 12
	TweenService:Create(
		camera,
		TweenInfo.new(DASH_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FieldOfView = baseFov }
	):Play()
end

dashPerformedEvent.OnClientEvent:Connect(function(dashPlayer: Player)
	playDashTrail(dashPlayer)
	if dashPlayer == player then
		runCooldownDisplay(dashButton, dashStatus, "Touche Q", DASH_COOLDOWN)
		playDashFovKick()
	end
end)

-- ===== Vision =====
local VISION_FILL_TRANSPARENCY    = 0.6
local VISION_OUTLINE_TRANSPARENCY = 0
local VISION_FADE_TIME            = 0.3 -- s, fondu d'entrée ET de sortie du glow des survivants

local visionLocked = false
local activeVisionHighlights: { Highlight } = {}
local visionTint: ColorCorrectionEffect? = nil

local function tryVision()
	if visionLocked then return end
	visionLocked = true
	task.delay(REQUEST_LOCKOUT, function() visionLocked = false end)
	visionRequestEvent:FireServer()
end

-- Nettoyage immédiat (défensif, ex. un nouvel appui arrive avant la fin de l'activation
-- précédente) : pas de fondu ici, juste de la robustesse.
local function clearVisionHighlightsInstant()
	for _, hl in activeVisionHighlights do
		if hl.Parent then hl:Destroy() end
	end
	activeVisionHighlights = {}
	if visionTint then
		visionTint:Destroy()
		visionTint = nil
	end
end

-- Fin normale de la vision : fondu de sortie du glow avant de le détruire.
local function fadeOutVisionHighlights()
	local highlights = activeVisionHighlights
	activeVisionHighlights = {}

	for _, hl in highlights do
		if not hl.Parent then continue end
		local tween = TweenService:Create(
			hl,
			TweenInfo.new(VISION_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ FillTransparency = 1, OutlineTransparency = 1 }
		)
		tween:Play()
		tween.Completed:Connect(function()
			hl:Destroy()
		end)
	end

	if visionTint then
		visionTint:Destroy()
		visionTint = nil
	end
end

visionGrantedEvent.OnClientEvent:Connect(function(duration: number)
	if typeof(duration) ~= "number" then return end
	runCooldownDisplay(visionButton, visionStatus, "Touche R", VISION_COOLDOWN)

	clearVisionHighlightsInstant() -- au cas où (ne devrait pas arriver, cooldown serveur > durée)

	-- Un survivant = un personnage sans InfectedHighlight/EliminatedHighlight (posés par le
	-- serveur, répliqués à tout le monde). Highlight créé ICI, par ce LocalScript : ne se réplique
	-- à personne d'autre, donc seul le clown voit la révélation.
	for _, other in Players:GetPlayers() do
		if other == player then continue end
		local char = other.Character
		if not char then continue end
		if char:FindFirstChild("InfectedHighlight") or char:FindFirstChild("EliminatedHighlight") then
			continue
		end

		local hl = Instance.new("Highlight")
		hl.Name = "VisionHighlight"
		hl.FillColor = Color3.fromRGB(80, 220, 255)
		hl.FillTransparency = 1 -- fondu d'entrée : part invisible
		hl.OutlineColor = Color3.fromRGB(200, 250, 255)
		hl.OutlineTransparency = 1
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop -- visible à travers les murs
		hl.Parent = char
		table.insert(activeVisionHighlights, hl)

		TweenService:Create(
			hl,
			TweenInfo.new(VISION_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ FillTransparency = VISION_FILL_TRANSPARENCY, OutlineTransparency = VISION_OUTLINE_TRANSPARENCY }
		):Play()
	end

	-- Léger effet "mode détection" sur l'écran du clown, purement cosmétique.
	visionTint = Instance.new("ColorCorrectionEffect")
	visionTint.Name = "ClownSurvivalVisionTint"
	visionTint.TintColor = Color3.fromRGB(210, 235, 255)
	visionTint.Saturation = 0.15
	visionTint.Parent = Lighting

	task.delay(duration, fadeOutVisionHighlights)
end)

-- ===== Activation / désactivation (une capacité à la fois, chacune gérée indépendamment) =====
local dashInputConns: { RBXScriptConnection } = {}
local visionInputConns: { RBXScriptConnection } = {}

local function activateDash()
	gui.Enabled = true
	dashButton.Visible = true
	if not isMobile then
		table.insert(dashInputConns, UserInputService.InputBegan:Connect(function(input, processed)
			if processed then return end
			if input.KeyCode == Enum.KeyCode.Q then
				tryDash()
			end
		end))
	end
	table.insert(dashInputConns, dashButton.MouseButton1Click:Connect(tryDash))
end

local function deactivateDash()
	dashButton.Visible = false
	for _, conn in dashInputConns do conn:Disconnect() end
	dashInputConns = {}
end

local function activateVision()
	gui.Enabled = true
	visionButton.Visible = true
	if not isMobile then
		table.insert(visionInputConns, UserInputService.InputBegan:Connect(function(input, processed)
			if processed then return end
			if input.KeyCode == Enum.KeyCode.R then
				tryVision()
			end
		end))
	end
	table.insert(visionInputConns, visionButton.MouseButton1Click:Connect(tryVision))
end

local function deactivateVision()
	visionButton.Visible = false
	clearVisionHighlightsInstant()
	for _, conn in visionInputConns do conn:Disconnect() end
	visionInputConns = {}
end

dashAvailableEvent.OnClientEvent:Connect(function(active: boolean)
	if active then activateDash() else deactivateDash() end
end)

visionAvailableEvent.OnClientEvent:Connect(function(active: boolean)
	if active then activateVision() else deactivateVision() end
end)
