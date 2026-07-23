--!nonstrict
-- ClownSurvivalCombo.client.luau — Compteur de combo affiché "sur" le clown qui enchaîne les coups.
-- But : boucle de récompense visuelle qui monte en flèche (couleur + taille) pour donner envie
-- de re-frapper vite. Le compteur (et son reset après COMBO_RESET_WINDOW sans coup) est calculé
-- côté serveur — ce script ne fait qu'afficher/animer la valeur reçue.
--
-- Rendu façon jeu de combat : un stamp incliné en diagonale qui pop au-dessus de la tête du
-- clown (BillboardGui ancré au personnage, pas un bandeau HUD fixe), qui grossit puis s'envole
-- en s'estompant à chaque nouveau coup.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player = Players.LocalPlayer

local eventsFolder     = ReplicatedStorage:WaitForChild("ClownSurvivalEvents")
local comboUpdateEvent = eventsFolder:WaitForChild("ComboUpdate")

local BAR_DURATION = 10.0 -- s : doit rester synchro avec COMBO_RESET_WINDOW côté serveur
local BASE_TILT    = -12  -- degrés : inclinaison diagonale façon "stamp" de jeu de combat
local TILT_JITTER  = 6    -- variation aléatoire par coup pour casser la répétition visuelle

-- Couleur qui monte avec le combo : dégradé continu blanc → rouge (pas de palier visible),
-- plein rouge atteint à COMBO_COLOR_MAX coups et au-delà.
local COMBO_COLOR_MAX = 10
local COLOR_WHITE = Color3.fromRGB(255, 255, 255)
local COLOR_RED   = Color3.fromRGB(255, 40, 40)

local function colorForCombo(n: number): Color3
	local t = math.clamp((n - 1) / (COMBO_COLOR_MAX - 1), 0, 1)
	return COLOR_WHITE:Lerp(COLOR_RED, t)
end

local billboard: BillboardGui? = nil
local label: TextLabel? = nil
local flashLabel: TextLabel? = nil
local impactRing: Frame? = nil
local barBack: Frame? = nil
local barFill: Frame? = nil
local activeToken = 0
local barTween: Tween? = nil
local MILESTONE_STEP = 2 -- tous les X coups : impact renforcé (ring plus gros, flash plus fort)

-- (Re)crée le BillboardGui ancré à la tête du personnage courant. Nécessaire à chaque respawn
-- puisque le Character (et sa tête) est détruit/recréé par Roblox.
local function attachToCharacter(character: Model)
	if billboard then
		billboard:Destroy()
	end

	local head = character:WaitForChild("Head", 5)
	if not head then return end

	-- Le canevas du BillboardGui est volontairement bien plus grand que le stamp texte/barre :
	-- un BillboardGui RECADRE tout ce qui dépasse de son Size, et le flash/l'onde de choc du
	-- combo (ajoutés plus tard) débordent largement des 110x44 d'origine — sans cette marge, ces
	-- effets étaient invisibles (coupés), c'était le bug derrière "je ne vois aucune différence".
	local gui = Instance.new("BillboardGui")
	gui.Name = "ClownSurvivalComboStamp"
	gui.Size = UDim2.fromOffset(340, 340) -- marge généreuse : les éclats voyagent jusqu'à ~150px
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.AlwaysOnTop = true
	gui.Enabled = false
	gui.ResetOnSpawn = false
	gui.Adornee = head
	gui.Parent = head

	-- Le texte et la barre partagent le même Frame incliné, pour rester parfaitement alignés
	-- quel que soit l'angle du "stamp" (la barre tourne avec le texte, pas indépendamment).
	-- Taille en Offset (pas Scale) : le "punch" anime CE Frame, pas le BillboardGui lui-même —
	-- sinon agrandir le canevas pour laisser de la place au flash/à l'onde de choc ferait aussi
	-- grossir le texte, ce qu'on ne veut pas.
	local tilted = Instance.new("Frame")
	tilted.Name = "Tilted"
	tilted.AnchorPoint = Vector2.new(0.5, 0.5)
	tilted.Position = UDim2.fromScale(0.5, 0.5)
	tilted.Size = UDim2.fromOffset(110, 44)
	tilted.BackgroundTransparency = 1
	tilted.ZIndex = 2 -- au-dessus du flash panel/de l'onde de choc (sinon ils masqueraient le texte)
	tilted.Rotation = BASE_TILT
	tilted.Parent = gui

	local text = Instance.new("TextLabel")
	text.Name = "ComboLabel"
	text.AnchorPoint = Vector2.new(0.5, 0)
	text.Position = UDim2.new(0.5, 0, 0, 0)
	text.Size = UDim2.new(1, 0, 0, 29)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextStrokeTransparency = 0.2
	text.TextStrokeColor3 = Color3.fromRGB(30, 15, 40)
	text.Text = ""
	text.ZIndex = 2
	text.Parent = tilted

	-- Halo néon autour du texte (en plus du fin contour sombre ci-dessus, gardé pour la
	-- lisibilité) : un UIStroke épais et coloré qui "flicker" à chaque coup façon enseigne néon.
	local neonGlow = Instance.new("UIStroke")
	neonGlow.Name = "NeonGlow"
	neonGlow.Thickness = 2
	neonGlow.Color = Color3.fromRGB(255, 255, 255)
	neonGlow.Transparency = 1
	neonGlow.Parent = text

	-- Calque blanc superposé au texte : flashe à pleine opacité à chaque coup puis s'efface vite,
	-- façon "camera flash" des compteurs de combo de jeux de combat (Guilty Gear, MK...).
	local flash = Instance.new("TextLabel")
	flash.Name = "FlashLabel"
	flash.AnchorPoint = text.AnchorPoint
	flash.Position = text.Position
	flash.Size = text.Size
	flash.BackgroundTransparency = 1
	flash.Font = text.Font
	flash.TextScaled = true
	flash.TextColor3 = Color3.fromRGB(255, 255, 255)
	flash.TextStrokeTransparency = 1
	flash.TextTransparency = 1
	flash.Text = ""
	flash.ZIndex = 3
	flash.Parent = tilted

	-- Onde de choc circulaire (remplie, pas juste un contour fin) qui explose depuis le centre à
	-- chaque coup et s'efface, renforcée aux paliers (tous les MILESTONE_STEP).
	local ring = Instance.new("Frame")
	ring.Name = "ImpactRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5) -- centré sur "tilted" (même centre que le gui)
	ring.Size = UDim2.fromScale(0, 0)
	ring.BackgroundTransparency = 1
	ring.BorderSizePixel = 0
	ring.ZIndex = 1
	ring.Parent = gui

	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0)
	ringCorner.Parent = ring

	local ringStroke = Instance.new("UIStroke")
	ringStroke.Thickness = 3
	ringStroke.Transparency = 1
	ringStroke.Parent = ring

	local back = Instance.new("Frame")
	back.Name = "BarBack"
	back.AnchorPoint = Vector2.new(0.5, 0)
	back.Position = UDim2.new(0.5, 0, 0, 31)
	back.Size = UDim2.new(1, 0, 0, 7)
	back.BackgroundColor3 = Color3.fromRGB(20, 15, 25)
	back.BackgroundTransparency = 0.25
	back.BorderSizePixel = 0
	back.Parent = tilted

	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(1, 0)
	backCorner.Parent = back

	local fill = Instance.new("Frame")
	fill.Name = "BarFill"
	fill.AnchorPoint = Vector2.new(0, 0.5)
	fill.Position = UDim2.new(0, 0, 0.5, 0)
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BorderSizePixel = 0
	fill.Parent = back

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	billboard = gui
	label = text
	flashLabel = flash
	impactRing = ring
	barBack = back
	barFill = fill
end

-- Éclats qui jaillissent du centre du stamp à chaque coup (simulés en UI, pas de vrai
-- ParticleEmitter possible sur un BillboardGui) : petits cercles colorés qui partent dans des
-- directions aléatoires en rétrécissant et en s'effaçant, façon confetti/étincelles.
local function spawnParticles(gui: BillboardGui, color: Color3, count: number)
	for _ = 1, count do
		local particle = Instance.new("Frame")
		particle.Name = "ComboParticle"
		particle.AnchorPoint = Vector2.new(0.5, 0.5)
		particle.Position = UDim2.fromScale(0.5, 0.5)
		local size = math.random(12, 22)
		particle.Size = UDim2.fromOffset(size, size)
		particle.BackgroundColor3 = color
		particle.BackgroundTransparency = 0
		particle.BorderSizePixel = 0
		particle.ZIndex = 5
		particle.Parent = gui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = particle

		-- Liseré blanc bien net : sans ça les éclats se fondent dans le flash/l'onde de choc.
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1.5
		stroke.Color = Color3.fromRGB(255, 255, 255)
		stroke.Transparency = 0.2
		stroke.Parent = particle

		local angle = math.random() * math.pi * 2
		local dist  = math.random(70, 150)
		local targetPosition = UDim2.new(0.5, math.cos(angle) * dist, 0.5, math.sin(angle) * dist)

		local tween = TweenService:Create(
			particle,
			TweenInfo.new(math.random(40, 65) / 100, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = targetPosition, Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1 }
		)
		local strokeTween = TweenService:Create(
			stroke,
			TweenInfo.new(math.random(40, 65) / 100, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Transparency = 1 }
		)
		tween:Play()
		strokeTween:Play()
		tween.Completed:Connect(function()
			particle:Destroy()
		end)
	end
end

local function onCombo(count: number)
	if typeof(count) ~= "number" then return end

	local character = player.Character
	if not character then return end

	-- Réattache si besoin (premier coup du round, ou personnage recréé après respawn).
	if not billboard or billboard.Parent == nil or billboard.Adornee ~= character:FindFirstChild("Head") then
		attachToCharacter(character)
	end
	if not billboard or not label or not flashLabel or not impactRing or not barBack or not barFill then return end

	local gui, text, flash, ring, back, fill = billboard, label, flashLabel, impactRing, barBack, barFill
	local tilted = back.Parent :: Frame
	local isMilestone = count > 1 and count % MILESTONE_STEP == 0

	activeToken += 1
	local myToken = activeToken

	if barTween then
		barTween:Cancel()
		barTween = nil
	end

	local tilt = BASE_TILT + math.random(-TILT_JITTER, TILT_JITTER)
	local punchScale = 1 + math.min(count, 10) * 0.09
	local color = colorForCombo(count)

	gui.Enabled = true
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	text.TextColor3 = color
	text.TextTransparency = 0
	text.TextStrokeTransparency = 0.2
	text.Text = "COMBO x" .. count
	back.BackgroundTransparency = 0.25
	fill.BackgroundColor3 = color
	fill.BackgroundTransparency = 0

	-- La barre repart pleine à chaque coup : c'est le temps restant avant que le combo retombe.
	fill.Size = UDim2.new(1, 0, 1, 0)
	barTween = TweenService:Create(
		fill,
		TweenInfo.new(BAR_DURATION, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, 0, 1, 0) }
	)
	barTween:Play()

	-- "Pop" façon stamp de jeu de combat : parti en surtaille + sur-inclinaison, claque en place
	-- avec un léger rebond élastique (dépasse la cible puis rebondit dessus, plus vivant qu'un
	-- simple ease-out). Le texte ET la barre sont enfants du même Frame incliné, donc ils
	-- restent toujours alignés.
	tilted.Rotation = tilt * 2.2
	tilted.Size = UDim2.fromOffset(110 * punchScale * 1.7, 44 * punchScale * 1.7)
	TweenService:Create(
		tilted,
		TweenInfo.new(0.28, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
		{ Rotation = tilt }
	):Play()
	TweenService:Create(
		tilted,
		TweenInfo.new(0.32, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(110 * punchScale, 44 * punchScale) }
	):Play()

	-- Flash blanc superposé au texte lui-même, pour un vrai "coup de flash".
	flash.Text = text.Text
	flash.TextTransparency = 0
	flash.TextStrokeTransparency = isMilestone and 0 or 0.5
	TweenService:Create(
		flash,
		TweenInfo.new(isMilestone and 0.35 or 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	):Play()

	-- Halo néon : flicker coloré autour du texte (façon enseigne néon qui s'allume) puis
	-- disparaît TOTALEMENT à la fin (le flicker seul ne redescendait qu'à une valeur encore
	-- visible, ce qui laissait une trace en permanence).
	local neonGlow = text:FindFirstChild("NeonGlow") :: UIStroke?
	if neonGlow then
		neonGlow.Color = isMilestone and Color3.fromRGB(255, 225, 110) or color
		neonGlow.Thickness = isMilestone and 3 or 2
		neonGlow.Transparency = 0.05
		local flickerTween = TweenService:Create(
			neonGlow,
			TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true),
			{ Transparency = 0.5 }
		)
		flickerTween:Play()
		flickerTween.Completed:Connect(function()
			if myToken ~= activeToken then return end -- un coup plus récent gère déjà son propre glow
			TweenService:Create(
				neonGlow,
				TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Transparency = 1 }
			):Play()
		end)
	end

	-- Éclats qui jaillissent du centre, renforcés aux paliers (plus nombreux + dorés), couleur
	-- toujours chaude/saturée (pas blanche) pour ressortir sur le flash blanc derrière.
	local sparkColor = (isMilestone and Color3.fromRGB(255, 210, 90)) or color:Lerp(Color3.fromRGB(255, 180, 60), 0.5)
	spawnParticles(gui, sparkColor, isMilestone and 16 or 9)

	-- Onde de choc circulaire REMPLIE (pas juste un contour fin, trop discret) qui explose depuis
	-- le centre et s'efface, renforcée aux paliers.
	local ringSize = isMilestone and 200 or 110
	local ringColor = isMilestone and Color3.fromRGB(255, 220, 90) or color
	ring.Size = UDim2.fromOffset(0, 0)
	ring.BackgroundColor3 = ringColor
	ring.BackgroundTransparency = isMilestone and 0.35 or 0.55
	local ringStroke = ring:FindFirstChildOfClass("UIStroke")
	if ringStroke then
		ringStroke.Color = ringColor
		ringStroke.Transparency = 0
		ringStroke.Thickness = isMilestone and 5 or 3
	end
	TweenService:Create(
		ring,
		TweenInfo.new(isMilestone and 0.45 or 0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(ringSize, ringSize), BackgroundTransparency = 1 }
	):Play()
	if ringStroke then
		TweenService:Create(
			ringStroke,
			TweenInfo.new(isMilestone and 0.45 or 0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Transparency = 1 }
		):Play()
	end

	-- Petit "kick" de position : recul vertical bref puis retour, amplitude croissante avec le
	-- combo (plafonnée), pour une sensation de plus en plus explosive à mesure que ça enchaîne.
	local kick = math.min(count, 10) * 0.035
	gui.StudsOffset = Vector3.new(0, 2.6 - kick, 0)
	TweenService:Create(
		gui,
		TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ StudsOffset = Vector3.new(0, 2.6, 0) }
	):Play()

	task.delay(BAR_DURATION, function()
		if myToken ~= activeToken then return end -- un coup plus récent a déjà repris la main

		-- Barre à zéro sans nouveau coup : le combo retombe, le stamp s'envole en s'estompant.
		TweenService:Create(
			gui,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ StudsOffset = Vector3.new(0, 4.2, 0) }
		):Play()
		TweenService:Create(
			back,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ BackgroundTransparency = 1 }
		):Play()
		TweenService:Create(
			fill,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ BackgroundTransparency = 1 }
		):Play()
		local fadeTween = TweenService:Create(
			text,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ TextTransparency = 1, TextStrokeTransparency = 1 }
		)
		fadeTween:Play()
		fadeTween.Completed:Connect(function()
			if myToken == activeToken then
				gui.Enabled = false
			end
		end)
	end)
end

if player.Character then
	attachToCharacter(player.Character)
end
player.CharacterAdded:Connect(attachToCharacter)

comboUpdateEvent.OnClientEvent:Connect(onCombo)
