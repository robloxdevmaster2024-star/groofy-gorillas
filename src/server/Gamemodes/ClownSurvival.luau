--!nonstrict
-- ClownSurvival.luau — « Le Clown de nuit » : le clown chasse les enfants à la batte,
-- un coup réussi les propulse (knockback façon Smash Bros) et les transforme en clowns.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting          = game:GetService("Lighting")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local GameStatus = ReplicatedStorage:WaitForChild("GameStatus") -- créé par le RoundManager

-- ===== RemoteEvents créés dès le chargement du module =====
local eventsFolder = ReplicatedStorage:FindFirstChild("ClownSurvivalEvents")
if not eventsFolder then
	eventsFolder = Instance.new("Folder")
	eventsFolder.Name = "ClownSurvivalEvents"
	eventsFolder.Parent = ReplicatedStorage
end
local function getOrCreate(parent, name)
	return parent:FindFirstChild(name) or Instance.new("RemoteEvent", parent)
end
local swingEvent    = getOrCreate(eventsFolder, "Swing");    swingEvent.Name    = "Swing"
local setActiveEvent = getOrCreate(eventsFolder, "SetActive"); setActiveEvent.Name = "SetActive"
local tauntAvailableEvent = getOrCreate(eventsFolder, "TauntAvailable"); tauntAvailableEvent.Name = "TauntAvailable"
local tauntEvent          = getOrCreate(eventsFolder, "Taunt");          tauntEvent.Name          = "Taunt"
local cameraShakeEvent    = getOrCreate(eventsFolder, "CameraShake");    cameraShakeEvent.Name    = "CameraShake"
local hitFlashEvent       = getOrCreate(eventsFolder, "HitFlash");       hitFlashEvent.Name       = "HitFlash"
local comboUpdateEvent    = getOrCreate(eventsFolder, "ComboUpdate");    comboUpdateEvent.Name    = "ComboUpdate"
local sprintAvailableEvent = getOrCreate(eventsFolder, "SprintAvailable"); sprintAvailableEvent.Name = "SprintAvailable"
local setSprintingEvent    = getOrCreate(eventsFolder, "SetSprinting");    setSprintingEvent.Name    = "SetSprinting"
local staminaUpdateEvent   = getOrCreate(eventsFolder, "StaminaUpdate");   staminaUpdateEvent.Name   = "StaminaUpdate"
local slideEvent           = getOrCreate(eventsFolder, "Slide");           slideEvent.Name           = "Slide"

local ClownSurvival = {}

-- ===== Métadonnées =====
ClownSurvival.Name = "Clown Survival"
ClownSurvival.Description = "🤡 Un clown chasse les enfants à la batte, la nuit, dans l'aire de jeu."
ClownSurvival.MinPlayers = 2
ClownSurvival.RoundDuration = 180 -- 3 minutes
ClownSurvival.DefaultSettings = {
	meleeRange            = 8,   -- portée du swing (studs)
	meleeCooldown         = 1.0, -- s entre deux coups de batte
	knockbackForce        = 90,  -- studs/s, composante horizontale
	knockbackUpward       = 40,  -- studs/s, composante verticale
	knockbackStunDuration = 0.8, -- s pendant lesquelles la victime ne contrôle plus son perso
}
ClownSurvival.SettingsSchema = {
	{ key = "meleeRange",        label = "Portée de la batte (studs)", min = 4,   max = 15, step = 1   },
	{ key = "meleeCooldown",     label = "Délai entre coups (s)",    min = 0.3, max = 3.0, step = 0.1 },
	{ key = "knockbackForce",    label = "Force du knockback",       min = 30,  max = 200, step = 10  },
}

-- Nombre de clowns de départ = 1 pour CLOWNS_PLAYER_RATIO joueurs (mini 1), ex. 12 joueurs → 2 clowns.
local CLOWNS_PLAYER_RATIO = 6

-- Plafond de clowns simultanés : ~40% de l'effectif ENCORE PRÉSENT (recalculé à chaque coup de
-- batte, pas figé au début du round — des joueurs peuvent se déconnecter en cours de partie,
-- ce qui doit réduire le plafond en conséquence). Le "+1" par rapport au nombre de clowns
-- actuels garantit qu'au moins une contamination/élimination de plus reste toujours possible
-- (sinon le plafond bloquerait toute progression dès le début dans les petites parties).
-- Une fois le plafond atteint, un coup de batte n'ajoute plus de clown : la victime est
-- ÉLIMINÉE (sort de la partie) plutôt que contaminée.
local CLOWN_CAP_RATIO = 0.4

-- Cône de frappe devant le clown (dot product minimal entre direction visée et direction vers la cible)
local MELEE_CONE_DOT = 0.6 -- ≈ 53°

-- ===== État du round (remis à zéro à chaque Start) =====
local participants: { [Player]: boolean } = {}
local infected: { [Player]: boolean } = {}
local eliminated: { [Player]: boolean } = {}  -- sortis de la partie (plafond de clowns atteint)
local originalClowns: { [Player]: boolean } = {}  -- infecteurs du départ uniquement
local lastSwing: { [Player]: number } = {}
local lastTaunt: { [Player]: number } = {}
local TAUNT_COOLDOWN = 2.0 -- s, anti-spam du bouton taunt
local connections: { RBXScriptConnection } = {}
local running = false
local settings = ClownSurvival.DefaultSettings
local savedLighting: { [string]: any }? = nil

-- Combo de frappes : incrémenté par clown à chaque coup qui touche, remis à 1 si trop de temps
-- s'est écoulé depuis le dernier coup. But : donner une récompense visuelle qui monte en flèche
-- plus le clown enchaîne les coups rapidement (boucle "envie de re-taper").
local comboCount: { [Player]: number } = {}
local comboLastHit: { [Player]: number } = {}
local COMBO_RESET_WINDOW = 4.0 -- s sans coup avant que le combo retombe à 1

-- Micro hit-stop : on gèle très brièvement la victime au moment de l'impact (avant l'envol/le
-- ragdoll) pour donner du poids au coup, façon "influence frame" des jeux de combat/anime.
local HIT_STOP_DURATION = 0.08 -- s

-- Sprint (tous les participants, clowns comme survivants) : Humanoid.WalkSpeed contrôlé par le
-- serveur selon l'état "sprinting" du joueur, limité par une jauge de stamina qui se vide en
-- courant et se recharge à l'arrêt. Le client ne fait que demander (SetSprinting) et afficher
-- (StaminaUpdate) — toute la logique/anti-triche reste côté serveur.
local BASE_WALK_SPEED       = 16
local SPRINT_WALK_SPEED     = 26
local MAX_STAMINA           = 100
local STAMINA_DRAIN_PER_SEC = 25 -- ~4s de sprint continu pour vider la jauge
local STAMINA_REGEN_PER_SEC = 15 -- recharge plus lente que la vidange
local STAMINA_BROADCAST_INTERVAL = 0.1 -- s entre deux mises à jour envoyées au client (throttle réseau)

-- Fatigue : si la jauge tombe à 0, pénalité de vitesse + sprint bloqué pendant EXHAUSTION_DURATION,
-- pour inciter à gérer sa stamina plutôt qu'à tout claquer d'un coup.
local EXHAUSTION_DURATION  = 2.0 -- s
local EXHAUSTED_WALK_SPEED = 12  -- < BASE_WALK_SPEED

local stamina: { [Player]: number } = {}
local sprinting: { [Player]: boolean } = {}
local exhaustedUntil: { [Player]: number } = {} -- os.clock() jusqu'à laquelle le joueur est fatigué

-- Glissade : seulement possible en plein sprint, coûte 1/6 de la jauge MAX d'un coup, puis
-- décélère linéairement (friction constante = réaliste) jusqu'à l'arrêt. La hitbox est vraiment
-- abaissée (BodyHeightScale + HipHeight réduits, pas juste visuel) pour pouvoir passer sous des
-- obstacles bas — la détection des coups de batte n'en tient pas compte (pas de check de hauteur).
local SLIDE_DURATION       = 0.55 -- s
local SLIDE_INITIAL_SPEED  = 34   -- studs/s, un peu plus que le sprint pour un vrai "boost"
local SLIDE_STAMINA_COST   = MAX_STAMINA / 6
local SLIDE_WALK_SPEED     = 4    -- pendant la glissade : le contrôle normal du joueur pèse peu
-- face à la vélocité de glissade qu'on impose nous-mêmes (évite que les deux se battent).
local SLIDE_BODY_HEIGHT_SCALE = 0.55 -- R15 uniquement (pas de scale sur R6)
local SLIDE_HIP_HEIGHT_FACTOR = 0.5

-- Fenêtre de tolérance : sur PC, tenir Shift + appuyer sur Ctrl EN MÊME TEMPS est peu naturel
-- (aucun jeu ne demande ça). On autorise donc la glissade si le joueur sprinte encore OU s'il a
-- démarré un sprint il y a moins de SLIDE_GRACE_WINDOW secondes (même s'il a relâché Shift).
local SLIDE_GRACE_WINDOW = 0.8 -- s

local sliding: { [Player]: any } = {} -- { direction, startTime, originalHipHeight, bodyHeightScale, originalBodyHeightScale }
local lastSprintStart: { [Player]: number } = {}

-- Cri périodique des survivants (pas les clowns) : aide les clowns à les repérer au son
-- (audio positionnel — Sound parenté au HumanoidRootPart, atténué avec la distance).
local SCREAM_INTERVAL = 25 -- s
local SCREAM_SOUND_ID = "rbxassetid://9125652432"
local roundId = 0 -- incrémenté à chaque Start() pour invalider la boucle de cri du round précédent

-- Rire du taunt : même principe que le cri (audio positionnel serveur), pour être entendu par
-- les joueurs à proximité et pas seulement par celui qui appuie sur le bouton.
local LAUGH_SOUND_ID = "rbxassetid://133312610824902"

-- Impact du coup de batte (SFX + petit effet visuel).
local HIT_SOUND_ID = "rbxassetid://107321119653126"

-- ===== Animation du swing (baseball) =====
-- Le swing n'anime plus seulement le poignet : on pilote aussi l'épaule et le coude (R15) pour
-- un vrai mouvement de bras — préparation "mains au-dessus de l'épaule", puis swing jusqu'à
-- l'horizontale. Chaque joint anime entre une pose "PRÊT" (READY) et une pose "IMPACT" (SWING),
-- exactement comme avant pour la batte, mais sur plusieurs articulations en parallèle.
--
-- Convention des axes (identique à l'animation de marche par défaut de Roblox pour ces joints) :
--   - rotation locale Z = balancement avant/arrière du membre (c'est l'axe qui fait le gros du
--     mouvement de swing, de "levé au-dessus de l'épaule" à "tendu à l'horizontale") ;
--   - rotation locale X = léger écart du bras par rapport au corps (évite que le coude ne
--     traverse le torse visuellement).
-- ⚠️ Réglages "à l'œil" sans preview 3D possible ici : si le bras part dans le mauvais sens une
-- fois testé en Studio, il suffit d'inverser le signe des angles ci-dessous (aucune autre
-- logique à toucher).
local SHOULDER_READY_ROT = CFrame.Angles(math.rad(-20), 0, math.rad(-150)) -- bras levé, au-dessus de l'épaule
local SHOULDER_SWING_ROT = CFrame.Angles(math.rad(-10), 0, math.rad(-50))  -- bras tendu, à l'horizontale
local ELBOW_READY_ROT    = CFrame.Angles(0, 0, math.rad(-100)) -- coude plié (batte ramenée près de la tête)
local ELBOW_SWING_ROT    = CFrame.Angles(0, 0, math.rad(-20))  -- coude tendu (extension pendant le swing)

-- R6 (avatar de test Studio) : un seul joint "Right Shoulder", pas de coude — amplitude un peu
-- réduite car le bras entier est rigide (pas d'extension de coude pour ajouter du mouvement).
local R6_SHOULDER_READY_ROT = CFrame.Angles(math.rad(-15), 0, math.rad(-140))
local R6_SHOULDER_SWING_ROT = CFrame.Angles(math.rad(-10), 0, math.rad(-55))

-- Pose de la batte dans la main : reste la même orientation de prise qu'avant, avec juste un
-- petit "snap" de poignet en plus (le gros du mouvement vient maintenant du bras, pas du poignet).
local BAT_REST_C0  = CFrame.new(0, -0.6, -0.25) * CFrame.Angles(math.rad(90), 0, math.rad(90))
local BAT_SWING_C0 = BAT_REST_C0 * CFrame.Angles(0, 0, math.rad(-45))

local SWING_OUT_TIME  = 0.25 -- s : aller vers la pose d'impact (~0.55s l'aller-retour, assez lisible)
local SWING_BACK_TIME = 0.30 -- s : retour vers la pose prête

-- Cherche un Motor6D par nom n'importe où dans le personnage (le 2e argument `true` de
-- FindFirstChild rend la recherche récursive), sans dépendre de sa profondeur exacte dans le rig.
local function findMotor(character: Model, name: string): Motor6D?
	local inst = character:FindFirstChild(name, true)
	return inst and inst:IsA("Motor6D") and inst or nil
end

-- Batte + bras de chaque clown : { joints = { {motor, baseC0, restC0, swingC0}, ... },
-- animPhase ("out"|"back"|nil), animStart }. `joints` contient toujours le Motor6D de la batte,
-- et en plus l'épaule/le coude si le rig les expose (R15) ou juste l'épaule (R6).
-- animPhase/animStart sont mis à jour par stepBatAnimations() (Heartbeat), sans dépendre
-- du comportement implicite de TweenService sur un Motor6D créé à la volée.
local batRigs: { [Player]: any } = {}

-- ===== Helpers =====
local function getHRP(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") or nil
end

local function applyInfectedLook(player: Player)
	local char = player.Character
	if not char or char:FindFirstChild("InfectedHighlight") then return end
	local hl = Instance.new("Highlight")
	hl.Name = "InfectedHighlight"
	hl.FillColor = Color3.fromRGB(230, 30, 130)   -- rose/rouge criard "clown"
	hl.OutlineColor = Color3.fromRGB(255, 255, 255)
	hl.FillTransparency = 0.4
	hl.Parent = char
end

local function removeInfectedLook(player: Player)
	local char = player.Character
	local hl = char and char:FindFirstChild("InfectedHighlight")
	if hl then hl:Destroy() end
end

-- Sortie de partie (plafond de clowns atteint) : grisé + immobilisé, comme les éliminés Dodgeball.
local function applyEliminatedLook(player: Player)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then hum.WalkSpeed = 0; hum.JumpHeight = 0 end
	if char:FindFirstChild("EliminatedHighlight") then return end
	local hl = Instance.new("Highlight")
	hl.Name = "EliminatedHighlight"
	hl.FillColor = Color3.fromRGB(80, 80, 80)
	hl.OutlineColor = Color3.fromRGB(140, 140, 140)
	hl.FillTransparency = 0.25
	hl.Parent = char
end

local function removeEliminatedLook(player: Player)
	local char = player.Character
	if not char then return end
	local hl = char:FindFirstChild("EliminatedHighlight")
	if hl then hl:Destroy() end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then hum.WalkSpeed = 16; hum.JumpHeight = 7.2 end
end

-- Joue un cri positionnel sur le HumanoidRootPart du survivant (audible par les clowns proches).
local function playScreamSound(player: Player)
	local hrp = getHRP(player)
	if not hrp then return end

	local sound = Instance.new("Sound")
	sound.Name = "SurvivorScream"
	sound.SoundId = SCREAM_SOUND_ID
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMaxDistance = 120
	sound.Volume = 1
	sound.Parent = hrp

	sound.Ended:Once(function() sound:Destroy() end)
	sound:Play()
	task.delay(5, function()
		if sound.Parent then sound:Destroy() end
	end)
end

-- Joue le rire du taunt en positionnel sur le HumanoidRootPart (audible par les proches, clowns compris).
local function playTauntSound(player: Player)
	local hrp = getHRP(player)
	if not hrp then return end

	local sound = Instance.new("Sound")
	sound.Name = "TauntLaugh"
	sound.SoundId = LAUGH_SOUND_ID
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMaxDistance = 120
	sound.Volume = 1
	sound.Parent = hrp

	sound.Ended:Once(function() sound:Destroy() end)
	sound:Play()
	task.delay(5, function()
		if sound.Parent then sound:Destroy() end
	end)
end

-- SFX + petite gerbe de particules au point d'impact du coup de batte (dès qu'une cible est
-- touchée, qu'elle soit ensuite contaminée ou éliminée). Le texture par défaut du ParticleEmitter
-- est un asset intégré à Roblox (rbxasset://...) : aucun asset à uploader pour l'effet visuel.
local function playHitEffect(target: Player)
	local hrp = getHRP(target)
	if not hrp then return end

	local sound = Instance.new("Sound")
	sound.Name = "BatHitSfx"
	sound.SoundId = HIT_SOUND_ID
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMaxDistance = 80
	sound.Volume = 1
	sound.Parent = hrp
	sound.Ended:Once(function() sound:Destroy() end)
	sound:Play()

	local attachment = Instance.new("Attachment")
	attachment.Name = "BatHitImpact"
	attachment.Parent = hrp

	-- Gerbe de particules grossie pour un impact plus lisible/spectaculaire.
	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 210, 40))
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	particles.Lifetime = NumberRange.new(0.25, 0.45)
	particles.Speed = NumberRange.new(14, 24)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Rate = 0
	particles.Parent = attachment

	particles:Emit(24)
	task.delay(1, function()
		attachment:Destroy()
	end)

	-- Étoile d'impact façon manga ("POW") : un BillboardGui fait toujours face à la caméra de
	-- chaque joueur, donc pas besoin d'orienter quoi que ce soit — juste un emoji qui "pop" en
	-- grossissant puis s'estompe, comme une case de manga.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "MangaImpact"
	billboard.Adornee = hrp
	billboard.Size = UDim2.new(0, 220, 0, 220)
	billboard.StudsOffset = Vector3.new(0, 1.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = hrp

	local star = Instance.new("TextLabel")
	star.BackgroundTransparency = 1
	star.AnchorPoint = Vector2.new(0.5, 0.5)
	star.Position = UDim2.new(0.5, 0, 0.5, 0)
	star.Size = UDim2.new(0, 0, 0, 0)
	star.Text = "💥"
	star.TextScaled = true
	star.Rotation = math.random(-15, 15)
	star.Parent = billboard

	local pop = TweenService:Create(
		star,
		TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(1, 0, 1, 0) }
	)
	pop.Completed:Once(function()
		TweenService:Create(
			star,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Size = UDim2.new(1.3, 0, 1.3, 0), TextTransparency = 1 }
		):Play()
	end)
	pop:Play()

	task.delay(0.5, function()
		billboard:Destroy()
	end)

	-- Étoiles "assommé" façon cartoon, qui tournent brièvement autour de la tête — visibles par
	-- tout le monde puisque rattachées au personnage (comme le reste de l'effet d'impact).
	local head = target.Character and target.Character:FindFirstChild("Head")
	if head then
		local starsBillboard = Instance.new("BillboardGui")
		starsBillboard.Name = "DizzyStars"
		starsBillboard.Adornee = head
		starsBillboard.Size = UDim2.new(0, 140, 0, 140)
		starsBillboard.StudsOffset = Vector3.new(0, 1.4, 0)
		starsBillboard.AlwaysOnTop = true
		starsBillboard.Parent = head

		local DIZZY_STAR_COUNT = 3
		local DIZZY_DURATION = 1.1 -- s
		local dizzyStars = {}
		for i = 1, DIZZY_STAR_COUNT do
			local dizzyStar = Instance.new("TextLabel")
			dizzyStar.BackgroundTransparency = 1
			dizzyStar.AnchorPoint = Vector2.new(0.5, 0.5)
			dizzyStar.Size = UDim2.new(0, 14, 0, 14)
			dizzyStar.Text = "⭐"
			dizzyStar.TextScaled = true
			dizzyStar.Parent = starsBillboard
			table.insert(dizzyStars, dizzyStar)
		end

		task.spawn(function()
			local start = os.clock()
			while starsBillboard.Parent and (os.clock() - start) < DIZZY_DURATION do
				local t = os.clock() - start
				for i, dizzyStar in dizzyStars do
					local angle = t * 6 + (i - 1) * (2 * math.pi / DIZZY_STAR_COUNT)
					dizzyStar.Position = UDim2.new(0.5, math.cos(angle) * 55, 0.5, math.sin(angle) * 22)
				end
				task.wait()
			end
			if starsBillboard.Parent then
				starsBillboard:Destroy()
			end
		end)
	end

	task.delay(5, function()
		if sound.Parent then sound:Destroy() end
	end)
end

-- Boucle de cri : toutes les SCREAM_INTERVAL secondes, chaque survivant (pas les clowns) crie.
-- `thisRound` invalide la boucle si un nouveau round démarre avant que celui-ci soit terminé.
local function startScreamLoop(thisRound: number)
	task.spawn(function()
		while thisRound == roundId do
			task.wait(SCREAM_INTERVAL)
			if thisRound ~= roundId or not running then break end
			for player in participants do
				if not infected[player] and not eliminated[player] then
					playScreamSound(player)
				end
			end
		end
	end)
end

local function applyDarkAtmosphere()
	savedLighting = {
		Brightness      = Lighting.Brightness,
		ClockTime       = Lighting.ClockTime,
		Ambient         = Lighting.Ambient,
		OutdoorAmbient  = Lighting.OutdoorAmbient,
		FogColor        = Lighting.FogColor,
		FogStart        = Lighting.FogStart,
		FogEnd          = Lighting.FogEnd,
	}
	Lighting.ClockTime      = 0 -- minuit
	Lighting.Brightness     = 1
	Lighting.Ambient        = Color3.fromRGB(20, 20, 30)
	Lighting.OutdoorAmbient = Color3.fromRGB(15, 15, 25)
	Lighting.FogColor       = Color3.fromRGB(10, 10, 15)
	Lighting.FogStart       = 15
	Lighting.FogEnd         = 90
end

local function restoreAtmosphere()
	if not savedLighting then return end
	for key, value in savedLighting do
		Lighting[key] = value
	end
	savedLighting = nil
end

-- Ragdoll R15 : remplace chaque Motor6D par une BallSocketConstraint jumelle (mêmes C0/C1),
-- ce qui laisse les membres libres de tourner/flotter tout en restant accrochés aux articulations.
-- Rétablit tout automatiquement après `duration` secondes.
-- Important : une fois les Motor6D désactivés, le corps n'est plus UN SEUL bloc rigide — chaque
-- membre redevient sa propre "assembly" physique. Donner la vélocité d'impact seulement au
-- HumanoidRootPart (comme avant) ne fait bouger que cette boîte invisible : le corps visible
-- (torse, bras, jambes) reste immobile. Il faut donc appliquer la vélocité à CHAQUE membre.
local function ragdollCharacter(character: Model, duration: number, knockbackVelocity: Vector3)
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	local motors = {}
	local sockets = {}
	local ragdollAttachments = {}
	local allParts: { BasePart } = {}

	for _, obj in character:GetDescendants() do
		if obj:IsA("Motor6D") and obj.Part0 and obj.Part1 then
			local part0 = obj.Part0
			local part1 = obj.Part1

			local a0 = Instance.new("Attachment")
			a0.Name = "RagdollAttachment0"
			a0.CFrame = obj.C0
			a0.Parent = part0

			local a1 = Instance.new("Attachment")
			a1.Name = "RagdollAttachment1"
			a1.CFrame = obj.C1
			a1.Parent = part1

			-- Pas de limites : articulations totalement libres pour un envol chaotique
			-- ("virevolter très fortement"). Avec LimitsEnabled = true, l'angle par défaut
			-- (UpperAngle = 0) verrouille complètement la rotation, ce qui rend le ragdoll
			-- rigide.
			local socket = Instance.new("BallSocketConstraint")
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.LimitsEnabled = false
			socket.TwistLimitsEnabled = false
			socket.Parent = part0

			-- Motor6D.Enabled = false NE SUFFIT PAS : le joint reste rigide (comme un Weld)
			-- même désactivé, seul l'Animator cesse de le piloter. Il faut vraiment détacher
			-- Part0 pour casser le lien rigide (c'était le bug : le joueur restait figé debout).
			table.insert(motors, { motor = obj, part0 = part0 })
			table.insert(sockets, socket)
			table.insert(ragdollAttachments, a0)
			table.insert(ragdollAttachments, a1)
			obj.Part0 = nil
		elseif obj:IsA("BasePart") then
			-- On NE rend PAS les membres collidables entre eux : en R15 ils se chevauchent
			-- normalement (bras/torse, etc.). Les rendre collidables d'un coup fait que le moteur
			-- physique "sépare" ces membres qui se touchent avec des impulsions internes qui
			-- annulent/aléatoirisent la vélocité de knockback qu'on vient de leur donner
			-- (c'était le bug : le joueur retombait sur place sans force visible).
			table.insert(allParts, obj)
		end
	end

	hum.PlatformStand = true

	-- Vélocité d'impact sur CHAQUE membre (sinon seul HumanoidRootPart s'envolerait) + rotation
	-- aléatoire par membre pour un envol chaotique ("virevolte"), HumanoidRootPart INCLUS cette
	-- fois — sinon le tronc (qui porte tout le vol) ne culbute jamais et le corps a l'air "tout
	-- droit" même si bras/jambes bougent.
	--
	-- Important : bras/jambes/torse sont allongés sur leur axe LOCAL Y. Un axe de rotation
	-- totalement aléatoire (X/Y/Z égaux) finit statistiquement souvent aligné avec cette longueur
	-- → le membre tourne sur lui-même, mouvement quasi invisible (même bug que la batte qui
	-- tournait sur son propre axe). On calcule donc la rotation en ESPACE LOCAL de la partie, avec
	-- la composante Y fortement réduite, puis on la convertit en espace monde — l'essentiel de la
	-- rotation se fait sur X/Z, PERPENDICULAIRE à la longueur, donc un vrai battement visible.
	local MAX_ANGULAR_SPEED = 18 -- rad/s
	for _, part in allParts do
		part.AssemblyLinearVelocity = knockbackVelocity

		local localAngularVelocity = Vector3.new(
			(math.random() * 2 - 1) * MAX_ANGULAR_SPEED,
			(math.random() * 2 - 1) * MAX_ANGULAR_SPEED * 0.15,
			(math.random() * 2 - 1) * MAX_ANGULAR_SPEED
		)
		part.AssemblyAngularVelocity = part.CFrame:VectorToWorldSpace(localAngularVelocity)
	end

	task.delay(duration, function()
		for _, socket in sockets do
			pcall(function() socket:Destroy() end)
		end
		for _, attachment in ragdollAttachments do
			pcall(function() attachment:Destroy() end)
		end
		for _, entry in motors do
			if entry.motor.Parent then
				entry.motor.Part0 = entry.part0
			end
		end
		if hum.Parent then hum.PlatformStand = false end
	end)
end

-- Propulsion façon Smash Bros : vélocité d'impact + ragdoll (membres qui virevoltent le temps du vol).
local function applyKnockback(player: Player, direction: Vector3)
	local char = player.Character
	local hrp = getHRP(player)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not hrp or not hum then return end

	local horizontal = direction * (settings.knockbackForce or 90)
	local vertical = Vector3.new(0, settings.knockbackUpward or 40, 0)
	local duration = settings.knockbackStunDuration or 0.8

	ragdollCharacter(char, duration, horizontal + vertical)
end

-- Gèle très brièvement la victime (HumanoidRootPart ancré) avant de lancer le knockback, pour un
-- petit temps d'arrêt façon "influence frame" qui donne plus de poids au coup avant l'envol.
local function applyKnockbackWithHitStop(player: Player, direction: Vector3)
	local hrp = getHRP(player)
	if not hrp then
		applyKnockback(player, direction)
		return
	end

	hrp.Anchored = true
	task.delay(HIT_STOP_DURATION, function()
		if hrp.Parent then
			hrp.Anchored = false
		end
		applyKnockback(player, direction)
	end)
end

-- Construit le modèle physique de la batte (deux cylindres soudés, pas d'asset requis).
local function createBatModel(): Model
	local bat = Instance.new("Model")
	bat.Name = "ClownSurvivalBat"

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Shape = Enum.PartType.Cylinder
	handle.Size = Vector3.new(1.4, 0.35, 0.35)
	handle.Color = Color3.fromRGB(120, 70, 20)
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false
	handle.CanQuery = false
	handle.Massless = true
	handle.Parent = bat

	local barrel = Instance.new("Part")
	barrel.Name = "Barrel"
	barrel.Shape = Enum.PartType.Cylinder
	barrel.Size = Vector3.new(1.6, 0.65, 0.65)
	barrel.Color = Color3.fromRGB(210, 180, 120)
	barrel.Material = Enum.Material.Wood
	barrel.CanCollide = false
	barrel.CanQuery = false
	barrel.Massless = true
	barrel.CFrame = handle.CFrame * CFrame.new(1.5, 0, 0)
	barrel.Parent = bat

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = barrel
	weld.Parent = handle

	bat.PrimaryPart = handle
	return bat
end

-- R15 : "RightHand". R6 (avatar de test Studio par ex.) : "Right Arm".
-- L'offset de la pose de repos diffère car le bloc R6 est bien plus gros que la main R15.
local function getRightHandInfo(char: Model): (BasePart?, CFrame, CFrame)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and hum.RigType == Enum.HumanoidRigType.R6 then
		local arm = char:FindFirstChild("Right Arm") :: BasePart?
		local restC0 = CFrame.new(0, -1.2, -0.2) * CFrame.Angles(math.rad(90), 0, math.rad(90))
		return arm, restC0, restC0 * CFrame.Angles(0, 0, math.rad(-45))
	end
	local hand = char:FindFirstChild("RightHand") :: BasePart?
	return hand, BAT_REST_C0, BAT_SWING_C0
end

-- Ajoute à `joints` une entrée pour le Motor6D `name` s'il existe dans le personnage, avec sa
-- pose "prête" et sa pose "impact" calculées à partir de sa pose neutre actuelle (`baseC0`).
-- `baseC0` est conservé pour pouvoir restaurer le bras à la normale dans unequipBat().
local function addJoint(joints: { any }, character: Model, name: string, readyRot: CFrame, swingRot: CFrame)
	local motor = findMotor(character, name)
	if not motor then return end
	local baseC0 = motor.C0
	table.insert(joints, {
		motor = motor,
		baseC0 = baseC0,
		restC0 = baseC0 * readyRot,
		swingC0 = baseC0 * swingRot,
	})
end

-- Attache la batte à la main droite du clown via un Motor6D, et prépare l'animation de tout le
-- bras (épaule + coude en R15, épaule seule en R6) pour un vrai swing façon baseball.
local function equipBat(player: Player)
	local char = player.Character
	if not char or char:FindFirstChild("ClownSurvivalBat") then return end

	local hand, restC0, swingC0 = getRightHandInfo(char)
	if not hand then
		warn("[Clown Survival] Impossible d'équiper la batte : main droite introuvable pour " .. player.Name)
		return
	end

	local bat = createBatModel()
	bat.Parent = char

	local handle = bat.PrimaryPart :: BasePart
	local motor = Instance.new("Motor6D")
	motor.Name = "BatGrip"
	motor.Part0 = hand
	motor.Part1 = handle
	motor.C0 = restC0
	motor.Parent = hand

	local joints = { { motor = motor, baseC0 = restC0, restC0 = restC0, swingC0 = swingC0 } }

	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and hum.RigType == Enum.HumanoidRigType.R6 then
		addJoint(joints, char, "Right Shoulder", R6_SHOULDER_READY_ROT, R6_SHOULDER_SWING_ROT)
	else
		addJoint(joints, char, "RightShoulder", SHOULDER_READY_ROT, SHOULDER_SWING_ROT)
		addJoint(joints, char, "RightElbow", ELBOW_READY_ROT, ELBOW_SWING_ROT)
	end

	batRigs[player] = { joints = joints, animPhase = nil, animStart = 0 }
	print("[Clown Survival] Batte équipée pour " .. player.Name .. " (main: " .. hand.Name .. ", " .. #joints .. " articulation(s) animée(s))")
end

local function unequipBat(player: Player)
	local char = player.Character
	local rig = batRigs[player]
	if rig then
		-- Remet l'épaule/le coude à leur pose neutre (sinon le bras resterait figé en position
		-- "prêt à frapper" après la fin du round, puisque leur Motor6D n'est pas détruit avec la batte).
		for _, j in rig.joints do
			if j.motor.Parent then
				j.motor.C0 = j.baseC0
			end
		end
	end
	local bat = char and char:FindFirstChild("ClownSurvivalBat")
	if bat then bat:Destroy() end
	batRigs[player] = nil
end

-- Démarre l'animation de swing (aller vers la pose de frappe, puis retour).
-- La progression réelle est calculée à chaque frame par stepBatAnimations().
local function playSwingAnimation(player: Player)
	local rig = batRigs[player]
	if not rig then
		warn("[Clown Survival] Swing sans batte équipée pour " .. player.Name .. " (rig introuvable)")
		return
	end
	rig.animPhase = "out"
	rig.animStart = os.clock()
end

-- Fait avancer toutes les animations de swing en cours (appelé chaque Heartbeat pendant le round).
-- Anime en parallèle tous les joints du rig (batte + épaule/coude) sur la même progression, pour
-- que le bras et la batte bougent ensemble comme un seul geste.
local function stepBatAnimations()
	local now = os.clock()
	for _, rig in batRigs do
		if rig.animPhase then
			local duration = rig.animPhase == "out" and SWING_OUT_TIME or SWING_BACK_TIME
			local alpha = math.clamp((now - rig.animStart) / duration, 0, 1)
			-- Easing : accélération à l'aller (coup qui part vite), décélération au retour
			-- (le bras se "range" en douceur) — plus lisible/"propre" qu'une interpolation linéaire.
			local eased = (rig.animPhase == "out") and (alpha * alpha) or (1 - (1 - alpha) * (1 - alpha))

			for _, j in rig.joints do
				local fromC0 = (rig.animPhase == "out") and j.restC0 or j.swingC0
				local toC0   = (rig.animPhase == "out") and j.swingC0 or j.restC0
				j.motor.C0 = fromC0:Lerp(toC0, eased)
			end

			if alpha >= 1 then
				if rig.animPhase == "out" then
					rig.animPhase = "back"
					rig.animStart = now
				else
					rig.animPhase = nil
					for _, j in rig.joints do
						j.motor.C0 = j.restC0
					end
				end
			end
		end
	end
end

-- Fait avancer la stamina de tous les participants (vidange en sprint, recharge à l'arrêt),
-- applique le WalkSpeed résultant, et diffuse la valeur au client (throttlé pour le réseau).
-- Les joueurs éliminés sont ignorés : leur WalkSpeed reste géré par applyEliminatedLook().
local staminaBroadcastAccum = 0
local function stepStamina(dt: number)
	staminaBroadcastAccum += dt
	local shouldBroadcast = staminaBroadcastAccum >= STAMINA_BROADCAST_INTERVAL
	if shouldBroadcast then
		staminaBroadcastAccum = 0
	end

	local now = os.clock()

	for player in participants do
		if eliminated[player] then continue end
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum then continue end

		local current = stamina[player] or MAX_STAMINA
		if sprinting[player] then
			current = math.max(0, current - STAMINA_DRAIN_PER_SEC * dt)
			if current <= 0 then
				sprinting[player] = false
				exhaustedUntil[player] = now + EXHAUSTION_DURATION
			end
		else
			current = math.min(MAX_STAMINA, current + STAMINA_REGEN_PER_SEC * dt)
		end
		stamina[player] = current

		local isExhausted = exhaustedUntil[player] and now < exhaustedUntil[player]
		if sliding[player] then
			-- La vélocité de glissade est imposée directement par stepSlides() ; on réduit juste
			-- le WalkSpeed pour que le contrôle normal du joueur n'aille pas à l'encontre.
			hum.WalkSpeed = SLIDE_WALK_SPEED
		elseif isExhausted then
			hum.WalkSpeed = EXHAUSTED_WALK_SPEED
		else
			hum.WalkSpeed = sprinting[player] and SPRINT_WALK_SPEED or BASE_WALK_SPEED
		end

		if shouldBroadcast then
			staminaUpdateEvent:FireClient(player, current / MAX_STAMINA)
		end
	end
end

-- Restaure la hitbox normale (HipHeight + BodyHeightScale) à la fin d'une glissade.
local function endSlide(player: Player)
	local data = sliding[player]
	if not data then return end
	sliding[player] = nil

	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.HipHeight = data.originalHipHeight
	end
	if data.bodyHeightScale and data.bodyHeightScale.Parent then
		data.bodyHeightScale.Value = data.originalBodyHeightScale
	end
end

-- Fait avancer les glissades en cours : vélocité horizontale imposée, qui décroît linéairement
-- (friction constante, décélération réaliste) jusqu'à l'arrêt, puis restaure la hitbox normale.
local function stepSlides()
	local now = os.clock()
	for player, data in sliding do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp or not char.Parent then
			sliding[player] = nil
			continue
		end

		local elapsed = now - data.startTime
		if elapsed >= SLIDE_DURATION then
			endSlide(player)
			continue
		end

		local speed = SLIDE_INITIAL_SPEED * (1 - elapsed / SLIDE_DURATION)
		local currentVelocity = hrp.AssemblyLinearVelocity
		hrp.AssemblyLinearVelocity = Vector3.new(
			data.direction.X * speed,
			currentVelocity.Y,
			data.direction.Z * speed
		)
	end
end

local function grantWeapon(player: Player)
	setActiveEvent:FireClient(player, true)
	equipBat(player)
end

local function countActiveClowns(): number
	local count = 0
	for player in infected do
		if player.Parent then
			count += 1
		end
	end
	return count
end

-- Recompte les joueurs encore présents (certains ont pu se déconnecter en cours de round)
-- et en déduit le plafond de clowns du moment. Coût négligeable : une boucle sur la poignée
-- de participants du round, appelée seulement lors d'un coup de batte (pas chaque frame).
local function computeMaxClowns(activeClownCount: number): number
	local activePlayers = 0
	for player in participants do
		if player.Parent then
			activePlayers += 1
		end
	end
	return math.max(activeClownCount + 1, math.ceil(activePlayers * CLOWN_CAP_RATIO))
end

-- Élimine un joueur (plafond de clowns atteint) : il sort de la partie au lieu d'être contaminé.
local function eliminatePlayer(player: Player, knockbackDir: Vector3?)
	if eliminated[player] or infected[player] then return end
	eliminated[player] = true
	if knockbackDir then
		applyKnockbackWithHitStop(player, knockbackDir)
	end
	applyEliminatedLook(player)
	tauntAvailableEvent:FireClient(player, false) -- plus dans la partie, plus de bouton taunt
	GameStatus:FireClient(player, { kind = "banner", text = "💀 Trop de clowns dans le parc, tu es éliminé !" })
end

-- Retourne true si la contamination a eu lieu, false si le plafond de clowns l'a empêchée
-- (le joueur est alors éliminé au lieu d'être contaminé, voir eliminatePlayer()).
local function infectPlayer(player: Player, knockbackDir: Vector3?): boolean
	if infected[player] or eliminated[player] then return false end

	local activeClowns = countActiveClowns()
	if activeClowns >= computeMaxClowns(activeClowns) then
		eliminatePlayer(player, knockbackDir)
		return false
	end

	infected[player] = true
	applyInfectedLook(player)
	if knockbackDir then
		applyKnockbackWithHitStop(player, knockbackDir)
	end
	grantWeapon(player)
	tauntAvailableEvent:FireClient(player, false) -- le bouton taunt est réservé aux non-clowns
	GameStatus:FireClient(player, { kind = "banner", text = "🤡 Tu es devenu un CLOWN ! Chasse les autres enfants !" })
	return true
end

-- Incrémente le combo de frappes du clown (remis à 1 si trop de temps depuis le dernier coup).
-- Retourne le nouveau compteur, envoyé au client pour l'affichage qui monte en flèche.
local function registerCombo(attacker: Player): number
	local now = tick()
	if comboLastHit[attacker] and (now - comboLastHit[attacker]) <= COMBO_RESET_WINDOW then
		comboCount[attacker] = (comboCount[attacker] or 0) + 1
	else
		comboCount[attacker] = 1
	end
	comboLastHit[attacker] = now
	return comboCount[attacker]
end

-- Trouve la victime la plus proche dans le cône de frappe devant le clown.
local function findMeleeTarget(attacker: Player, aimDir: Vector3): Player?
	local attackerHRP = getHRP(attacker)
	if not attackerHRP then return nil end

	local range = settings.meleeRange or 8
	local best: Player? = nil
	local bestDist = math.huge

	for target in participants do
		if target ~= attacker and not infected[target] and not eliminated[target] then
			local targetHRP = getHRP(target)
			if targetHRP then
				local offset = targetHRP.Position - attackerHRP.Position
				local dist = offset.Magnitude
				if dist <= range and dist > 0.01 then
					local dot = aimDir:Dot(offset.Unit)
					if dot >= MELEE_CONE_DOT and dist < bestDist then
						best = target
						bestDist = dist
					end
				end
			end
		end
	end

	return best
end

-- ===== Cycle de vie =====
function ClownSurvival.Start(ctx)
	participants, infected, eliminated, originalClowns, lastSwing, lastTaunt, connections = {}, {}, {}, {}, {}, {}, {}
	comboCount, comboLastHit = {}, {}
	stamina, sprinting, exhaustedUntil, sliding, lastSprintStart = {}, {}, {}, {}, {}
	running = true
	settings = ctx.Settings or ClownSurvival.DefaultSettings
	roundId += 1

	for _, player in ctx.Players do
		participants[player] = true
		stamina[player] = MAX_STAMINA
		sprinting[player] = false
	end

	applyDarkAtmosphere()

	-- choisit le(s) clown(s) de départ au hasard : ratio 1 clown / CLOWNS_PLAYER_RATIO joueurs
	local pool = table.clone(ctx.Players)
	local numStartingClowns = math.max(1, math.floor(#pool / CLOWNS_PLAYER_RATIO))
	for _ = 1, math.min(numStartingClowns, #pool) do
		local chosen = table.remove(pool, math.random(1, #pool))
		if chosen then
			infected[chosen] = true
			originalClowns[chosen] = true
			applyInfectedLook(chosen)
			grantWeapon(chosen)
			GameStatus:FireClient(chosen, { kind = "banner", text = "🤡 Tu es LE CLOWN ! Chasse les enfants à la batte !" })
		end
	end

	GameStatus:FireAllClients({ kind = "banner", text = "🎪 LE CLOWN DE NUIT — fuyez avant d'être frappé !" })

	-- Le bouton taunt n'est visible que pour les survivants (pas les clowns de départ)
	for _, player in ctx.Players do
		if not infected[player] then
			tauntAvailableEvent:FireClient(player, true)
		end
	end

	startScreamLoop(roundId)

	-- Fait avancer les animations de swing des battes en cours
	local heartbeatConn = RunService.Heartbeat:Connect(stepBatAnimations)
	table.insert(connections, heartbeatConn)

	-- Sprint disponible pour tout le monde (clowns et survivants) dès le début du round.
	sprintAvailableEvent:FireAllClients(true)

	local staminaConn = RunService.Heartbeat:Connect(stepStamina)
	table.insert(connections, staminaConn)

	-- Écoute les demandes de sprint (le serveur reste seul juge : stamina, statut du joueur).
	local sprintConn = setSprintingEvent.OnServerEvent:Connect(function(player, wantsSprint)
		if not running or not participants[player] or eliminated[player] then return end
		if typeof(wantsSprint) ~= "boolean" then return end
		if wantsSprint then
			if (stamina[player] or 0) <= 0 then return end
			if exhaustedUntil[player] and os.clock() < exhaustedUntil[player] then return end
			if not sprinting[player] then
				lastSprintStart[player] = os.clock() -- démarre la fenêtre de tolérance pour la glissade
			end
		end
		sprinting[player] = wantsSprint
	end)
	table.insert(connections, sprintConn)

	local slideStepConn = RunService.Heartbeat:Connect(stepSlides)
	table.insert(connections, slideStepConn)

	-- Écoute les demandes de glissade : possible en plein sprint, ou juste après (fenêtre de
	-- tolérance) — pas besoin de tenir Shift ET Ctrl exactement en même temps.
	local slideConn = slideEvent.OnServerEvent:Connect(function(player)
		if not running or not participants[player] or eliminated[player] then return end
		if sliding[player] then return end -- déjà en cours

		local recentlySprinted = lastSprintStart[player] and (os.clock() - lastSprintStart[player]) <= SLIDE_GRACE_WINDOW
		if not sprinting[player] and not recentlySprinted then return end
		if (stamina[player] or 0) < SLIDE_STAMINA_COST then return end

		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hum or not hrp then return end

		stamina[player] = (stamina[player] or MAX_STAMINA) - SLIDE_STAMINA_COST
		sprinting[player] = false -- on ne sprinte plus, on glisse

		local direction = hum.MoveDirection
		if direction.Magnitude < 0.1 then
			direction = hrp.CFrame.LookVector
		end
		direction = Vector3.new(direction.X, 0, direction.Z)
		if direction.Magnitude < 0.01 then
			direction = hrp.CFrame.LookVector
		end
		direction = direction.Unit

		local bodyHeightScale = hum:FindFirstChild("BodyHeightScale")
		local originalHipHeight = hum.HipHeight
		local originalBodyHeightScale = bodyHeightScale and bodyHeightScale.Value

		hum.HipHeight = originalHipHeight * SLIDE_HIP_HEIGHT_FACTOR
		if bodyHeightScale then
			bodyHeightScale.Value = originalBodyHeightScale * SLIDE_BODY_HEIGHT_SCALE
		end

		sliding[player] = {
			direction = direction,
			startTime = os.clock(),
			originalHipHeight = originalHipHeight,
			bodyHeightScale = bodyHeightScale,
			originalBodyHeightScale = originalBodyHeightScale,
		}
	end)
	table.insert(connections, slideConn)

	-- Écoute les taunts (réservés aux survivants, pas aux clowns) — pas de message banner, juste
	-- le rire joué en positionnel par le serveur (entendu par les proches, clowns compris).
	local tauntConn = tauntEvent.OnServerEvent:Connect(function(player)
		if not running or not participants[player] or infected[player] or eliminated[player] then return end
		local now = tick()
		if lastTaunt[player] and (now - lastTaunt[player]) < TAUNT_COOLDOWN then return end
		lastTaunt[player] = now
		playTauntSound(player)
	end)
	table.insert(connections, tauntConn)

	-- Écoute les coups de batte des clowns
	local swingConn = swingEvent.OnServerEvent:Connect(function(player, aimDirection)
		if not running then return end
		if not infected[player] or not participants[player] then return end
		if typeof(aimDirection) ~= "Vector3" then return end

		local dir = aimDirection.Unit
		if dir ~= dir or dir.Magnitude < 0.9 then return end -- garde-fou NaN/inf

		local now = tick()
		if lastSwing[player] and (now - lastSwing[player]) < (settings.meleeCooldown or 1.0) then return end
		lastSwing[player] = now

		playSwingAnimation(player)

		local target = findMeleeTarget(player, dir)
		print("[Clown Survival] " .. player.Name .. " frappe — cible: " .. (target and target.Name or "aucune"))
		if target then
			playHitEffect(target)

			-- Secousse de caméra pour les deux joueurs impliqués : plus forte pour l'enfant
			-- touché (il se fait smasher), plus légère pour le clown (feedback du coup porté).
			cameraShakeEvent:FireClient(target, 1)
			cameraShakeEvent:FireClient(player, 0.4)

			-- Flash + lignes de vitesse : effet subjectif, uniquement sur l'écran de la victime.
			hitFlashEvent:FireClient(target)

			-- Combo du clown : récompense visuelle qui monte en flèche s'il enchaîne les coups.
			comboUpdateEvent:FireClient(player, registerCombo(player))

			local attackerHRP = getHRP(player)
			local targetHRP = getHRP(target)
			local knockDir = attackerHRP and targetHRP
				and (targetHRP.Position - attackerHRP.Position).Unit
				or dir
			if infectPlayer(target, knockDir) then
				GameStatus:FireAllClients({ kind = "banner", text = target.Name .. " a été transformé en clown ! 🤡" })
			elseif eliminated[target] then
				GameStatus:FireAllClients({ kind = "banner", text = target.Name .. " a été éliminé ! 💀" })
			end
		end
	end)
	table.insert(connections, swingConn)
end

function ClownSurvival.CheckWin()
	local survivors, infectors, eliminatedCount = {}, {}, 0
	for player in participants do
		if player.Parent then
			if eliminated[player] then
				eliminatedCount += 1
			elseif infected[player] then
				table.insert(infectors, player)
			else
				table.insert(survivors, player)
			end
		end
	end

	-- Défense en profondeur : que ce soit par contamination, élimination ou déconnexions en
	-- cascade, s'il ne reste plus qu'un seul joueur actif (ou aucun), la partie n'a plus de sens
	-- à continuer. Le survivant restant gagne par défaut (comme "dernier debout" en Dodgeball) ;
	-- s'il ne reste qu'un clown ou personne, il n'y a simplement pas de gagnant.
	local totalActive = #survivors + #infectors + eliminatedCount
	if totalActive <= 1 then
		return survivors, "Plus assez de joueurs pour continuer la partie !"
	end

	if #infectors == 0 then return survivors, "Plus de clowns en jeu !" end

	if #survivors == 0 then
		-- Qu'il n'y ait plus que des clowns (contamination normale) ou que des clowns + des
		-- éliminés (déconnexions ayant vidé le camp survivant), le résultat est le même : plus
		-- aucun enfant à chasser. Seuls les infecteurs ORIGINAUX gagnent (les contaminés en
		-- cours de round ont perdu).
		local winners = {}
		for player in originalClowns do
			if player.Parent then table.insert(winners, player) end
		end
		return winners, "Tous les survivants ont été infectés ou éliminés !"
	end

	return nil, nil -- le round continue
end

function ClownSurvival.ResolveTimeout()
	local survivors = {}
	for player in participants do
		if player.Parent and not infected[player] and not eliminated[player] then
			table.insert(survivors, player)
		end
	end
	return survivors, "Temps écoulé ! Les survivants ont résisté. 🛡️"
end

-- Appelé par le RoundManager avant Stop() pour enrichir le contexte achievements.
function ClownSurvival.GetWinnerRoles(winners: { Player })
	local roles = {}
	for _, player in winners do
		roles[player] = originalClowns[player] and "clown" or "survivor"
	end
	return roles
end

function ClownSurvival.OnPlayerRemoving(player)
	participants[player] = nil
	infected[player] = nil
	eliminated[player] = nil
	originalClowns[player] = nil
	lastSwing[player] = nil
	lastTaunt[player] = nil
	batRigs[player] = nil
	comboCount[player] = nil
	comboLastHit[player] = nil
	stamina[player] = nil
	sprinting[player] = nil
	exhaustedUntil[player] = nil
	sliding[player] = nil
	lastSprintStart[player] = nil
end

function ClownSurvival.Stop()
	running = false

	for _, conn in connections do
		pcall(function() conn:Disconnect() end)
	end
	connections = {}

	for player in participants do
		removeInfectedLook(player)
		removeEliminatedLook(player)
		unequipBat(player)
		endSlide(player) -- restaure HipHeight/BodyHeightScale si le joueur glissait encore
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.PlatformStand = false
			hum.WalkSpeed = BASE_WALK_SPEED
		end
	end

	setActiveEvent:FireAllClients(false)
	tauntAvailableEvent:FireAllClients(false)
	sprintAvailableEvent:FireAllClients(false)
	restoreAtmosphere()

	participants, infected, eliminated, originalClowns, lastSwing, lastTaunt, batRigs = {}, {}, {}, {}, {}, {}, {}
	comboCount, comboLastHit = {}, {}
	stamina, sprinting, exhaustedUntil, sliding, lastSprintStart = {}, {}, {}, {}, {}
end

return ClownSurvival