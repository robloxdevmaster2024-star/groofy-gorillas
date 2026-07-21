--!nonstrict
-- LobbyService.luau — Hub lobby : zones, files d'attente, countdown, lancement des rounds.
--
-- Convention map Studio :
--   ServerStorage.Venues.Lobby  →  Model avec :
--     SpawnPoints/   → BaseParts (positions de spawn lobby)
--     Zones/         → BaseParts avec Attribute("Gamemode") = "Infector" | "Dodgeball" | ...
--
-- Si aucune map "Lobby" n'existe → zones procédurales colorées générées automatiquement.

local Players           = game:GetService("Players")
local ServerStorage     = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoundRunner  = require(script.Parent.RoundRunner)
local GameSettings = require(script.Parent.GameSettings)

local GameStatus = ReplicatedStorage:WaitForChild("GameStatus")

-- RemoteEvents lobby (créés au chargement du module)
local lobbyFolder = ReplicatedStorage:FindFirstChild("LobbyEvents")
if not lobbyFolder then
	lobbyFolder = Instance.new("Folder")
	lobbyFolder.Name = "LobbyEvents"
	lobbyFolder.Parent = ReplicatedStorage
end
local function getOrCreate(parent, name)
	return parent:FindFirstChild(name) or Instance.new("RemoteEvent", parent)
end
local zoneUpdateEvent = getOrCreate(lobbyFolder, "ZoneUpdate"); zoneUpdateEvent.Name = "ZoneUpdate"
local playerZoneEvent = getOrCreate(lobbyFolder, "PlayerZone"); playerZoneEvent.Name = "PlayerZone"

-- ===== Constantes =====
local COUNTDOWN      = 15   -- secondes avant le lancement
local RETURN_DELAY   = 3    -- secondes après round avant retour lobby

local ZONE_COLORS = {
	Infector  = Color3.fromRGB(220, 50,  50),
	Dodgeball = Color3.fromRGB(50,  100, 220),
}
local DEFAULT_COLOR = Color3.fromRGB(120, 90, 200)

local ZONE_FALLBACK_POSITIONS = {
	Vector3.new(-80, 0, 0),
	Vector3.new( 80, 0, 0),
	Vector3.new(  0, 0, -80),
	Vector3.new(  0, 0,  80),
}

-- ===== État =====
local LobbyService = {}

local availableGamemodes = {}
local roundInProgress    = false
local lobbySpawns : { CFrame } = {}
local zoneParts   : { [string]: BasePart } = {}

-- queue par gamemode : { players: {[Player]: true}, inCountdown: bool }
local queues : { [string]: { players: { [Player]: boolean }, inCountdown: boolean } } = {}

-- zone actuelle de chaque joueur
local playerZone : { [Player]: string? } = {}

-- ===== Forward declarations (récursion mutuelle) =====
local checkAndMaybeCountdown
local startRound
local returnToLobby
local removeFromQueues

-- ===== Helpers =====
local function banner(text)
	GameStatus:FireAllClients({ kind = "banner", text = text })
	print("[LobbyService]", text)
end

local function getGamemode(name: string)
	for _, gm in availableGamemodes do
		if gm.Name == name then return gm end
	end
end

local function queueCount(name: string): number
	local q = queues[name]
	if not q then return 0 end
	local n = 0
	for _ in q.players do n += 1 end
	return n
end

local function minPlayers(name: string): number
	local gm = getGamemode(name)
	return gm and gm.MinPlayers or 2
end

-- ===== BillboardGui =====

local function updateBillboard(gamemodeName: string)
	local part = zoneParts[gamemodeName]
	if not part then return end

	local billboard = part:FindFirstChild("ZoneBillboard")
	local frame     = billboard and billboard:FindFirstChild("Frame")
	if not frame then return end

	local q     = queues[gamemodeName]
	local count = queueCount(gamemodeName)
	local minP  = minPlayers(gamemodeName)

	local countLbl  = frame:FindFirstChild("CountLabel")
	local statusLbl = frame:FindFirstChild("StatusLabel")

	if countLbl  then countLbl.Text = count .. " / " .. minP .. " joueurs" end
	if statusLbl then
		if roundInProgress then
			statusLbl.Text      = "⏳ Partie en cours…"
			statusLbl.TextColor3 = Color3.fromRGB(200, 150, 50)
		elseif q and q.inCountdown then
			statusLbl.Text       = "✅ Lancement…"
			statusLbl.TextColor3 = Color3.fromRGB(80, 220, 80)
		elseif count >= minP then
			statusLbl.Text       = "🟢 Prêts !"
			statusLbl.TextColor3 = Color3.fromRGB(80, 220, 80)
		else
			statusLbl.Text       = "En attente…"
			statusLbl.TextColor3 = Color3.fromRGB(160, 160, 170)
		end
	end

	-- Broadcast à tous les clients pour le HUD
	zoneUpdateEvent:FireAllClients({
		gamemodeName    = gamemodeName,
		count           = count,
		minPlayers      = minP,
		inCountdown     = q and q.inCountdown or false,
		roundInProgress = roundInProgress,
	})
end

local function setCountdownText(gamemodeName: string, text: string)
	local part  = zoneParts[gamemodeName]
	local frame = part and part:FindFirstChild("ZoneBillboard") and
	              part:FindFirstChild("ZoneBillboard"):FindFirstChild("Frame")
	local lbl   = frame and frame:FindFirstChild("StatusLabel")
	if lbl then
		lbl.Text       = text
		lbl.TextColor3 = Color3.fromRGB(80, 220, 80)
	end
end

local function buildBillboard(part: BasePart, gamemodeName: string, color: Color3)
	local gm = getGamemode(gamemodeName)

	local billboard = Instance.new("BillboardGui", part)
	billboard.Name           = "ZoneBillboard"
	billboard.Size           = UDim2.new(0, 230, 0, 120)
	billboard.StudsOffset    = Vector3.new(0, 7, 0)
	billboard.AlwaysOnTop    = false
	billboard.LightInfluence = 0.25
	billboard.MaxDistance    = 100
	billboard.ResetOnSpawn   = false

	local frame = Instance.new("Frame", billboard)
	frame.Name                   = "Frame"
	frame.Size                   = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3       = Color3.fromRGB(14, 12, 20)
	frame.BackgroundTransparency = 0.12
	frame.BorderSizePixel        = 0
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

	-- Barre de couleur haute
	local bar = Instance.new("Frame", frame)
	bar.Size             = UDim2.new(1, 0, 0, 5)
	bar.BackgroundColor3 = color
	bar.BorderSizePixel  = 0
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 10)

	local function lbl(name, text, size, bold, yPos, color3)
		local l = Instance.new("TextLabel", frame)
		l.Name               = name
		l.Size               = UDim2.new(1, -12, 0, size)
		l.Position           = UDim2.new(0, 6, 0, yPos)
		l.BackgroundTransparency = 1
		l.Font               = bold and Enum.Font.GothamBold or Enum.Font.Gotham
		l.TextSize           = size - 2
		l.TextColor3         = color3 or Color3.fromRGB(240, 240, 245)
		l.TextXAlignment     = Enum.TextXAlignment.Center
		l.Text               = text
		return l
	end

	lbl("TitleLabel",  (gm and gm.Name or gamemodeName):upper(), 22, true,  10, color)
	lbl("DescLabel",   gm and gm.Description or "",               14, false, 36, Color3.fromRGB(150, 150, 160))
	lbl("CountLabel",  "0 / 2 joueurs",                           16, true,  58, Color3.fromRGB(220, 220, 230))
	lbl("StatusLabel", "En attente…",                             14, false, 82, Color3.fromRGB(160, 160, 170))
end

-- ===== Zones =====

local function setupZonePart(part: BasePart, gamemodeName: string)
	zoneParts[gamemodeName] = part
	part.CanCollide   = false
	part.CastShadow   = false

	local color = ZONE_COLORS[gamemodeName] or DEFAULT_COLOR
	buildBillboard(part, gamemodeName, color)
	updateBillboard(gamemodeName)

	part.Touched:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if not player then return end
		if playerZone[player] ~= gamemodeName then
			-- Retirer de l'ancienne zone
			if playerZone[player] then
				removeFromQueues(player)
			end
			-- Rejoindre la nouvelle
			playerZone[player]             = gamemodeName
			queues[gamemodeName].players[player] = true
			updateBillboard(gamemodeName)
			playerZoneEvent:FireClient(player, { gamemodeName = gamemodeName })
			checkAndMaybeCountdown(gamemodeName)
		end
	end)

	-- TouchEnded + vérification heartbeat (TouchEnded peut être unreliable)
	part.TouchEnded:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if not player or playerZone[player] ~= gamemodeName then return end
		task.delay(0.3, function()
			if not player.Parent then return end
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if not hrp then return end
			local dx = hrp.Position.X - part.Position.X
			local dz = hrp.Position.Z - part.Position.Z
			local dist2D = math.sqrt(dx*dx + dz*dz)
			local threshold = math.max(part.Size.X, part.Size.Z) / 2 + 4
			if dist2D > threshold then
				removeFromQueues(player)
			end
		end)
	end)
end

local function createProceduralZone(gamemodeName: string, pos: Vector3)
	local color = ZONE_COLORS[gamemodeName] or DEFAULT_COLOR

	-- Sol visuel
	local floor = Instance.new("Part")
	floor.Size         = Vector3.new(28, 0.6, 28)
	floor.CFrame       = CFrame.new(pos.X, pos.Y + 0.3, pos.Z)
	floor.Anchored     = true
	floor.Color        = color
	floor.Material     = Enum.Material.SmoothPlastic
	floor.TopSurface   = Enum.SurfaceType.Smooth
	floor.BottomSurface = Enum.SurfaceType.Smooth
	floor.Parent       = workspace

	-- Volume trigger (invisible, couvre la hauteur du personnage)
	local trigger = Instance.new("Part")
	trigger.Size         = Vector3.new(28, 10, 28)
	trigger.CFrame       = CFrame.new(pos.X, pos.Y + 5, pos.Z)
	trigger.Anchored     = true
	trigger.Transparency = 1
	trigger.CanCollide   = false
	trigger.CastShadow   = false
	trigger.Parent       = workspace

	setupZonePart(trigger, gamemodeName)
end

-- ===== Queue / countdown =====

removeFromQueues = function(player: Player)
	local current = playerZone[player]
	playerZone[player] = nil
	if current and queues[current] then
		queues[current].players[player] = nil
		updateBillboard(current)
	end
	playerZoneEvent:FireClient(player, { gamemodeName = nil })
end

checkAndMaybeCountdown = function(gamemodeName: string)
	local q = queues[gamemodeName]
	if not q or q.inCountdown or roundInProgress then return end
	if queueCount(gamemodeName) < minPlayers(gamemodeName) then return end

	q.inCountdown = true
	local gm = getGamemode(gamemodeName)
	if gm then GameSettings.OpenPanel(gm) end
	updateBillboard(gamemodeName)

	task.spawn(function()
		for t = COUNTDOWN, 1, -1 do
			-- Annuler si pas assez de joueurs
			if queueCount(gamemodeName) < minPlayers(gamemodeName) then
				q.inCountdown = false
				GameSettings.ClosePanel()
				banner("⚠️ " .. gamemodeName .. " — pas assez de joueurs, countdown annulé")
				updateBillboard(gamemodeName)
				return
			end
			setCountdownText(gamemodeName, "🚀 Départ dans " .. t .. "s")
			zoneUpdateEvent:FireAllClients({
				gamemodeName    = gamemodeName,
				count           = queueCount(gamemodeName),
				minPlayers      = minPlayers(gamemodeName),
				inCountdown     = true,
				countdown       = t,
				roundInProgress = false,
			})
			task.wait(1)
		end

		-- Lancement
		if queueCount(gamemodeName) >= minPlayers(gamemodeName) then
			startRound(gamemodeName)
		else
			q.inCountdown = false
			GameSettings.ClosePanel()
			updateBillboard(gamemodeName)
		end
	end)
end

startRound = function(gamemodeName: string)
	local q = queues[gamemodeName]
	if not q then return end

	q.inCountdown   = false
	roundInProgress = true
	GameSettings.ClosePanel()

	-- Collecte les participants
	local players = {}
	for p in q.players do
		if p.Parent then table.insert(players, p) end
	end

	-- Vide la queue et met à jour les zones de ces joueurs
	for p in q.players do
		playerZone[p] = nil
		playerZoneEvent:FireClient(p, { gamemodeName = nil })
	end
	q.players = {}

	for _, name in queues do
		updateBillboard(name)
	end

	if #players < minPlayers(gamemodeName) then
		roundInProgress = false
		return
	end

	local gm       = getGamemode(gamemodeName)
	local settings = GameSettings.GetSettings(gamemodeName, gm.DefaultSettings)
	banner("🎮 " .. gamemodeName .. " — " .. #players .. " joueurs en route !")

	-- Lance le round dans un thread dédié
	task.spawn(function()
		RoundRunner.RunRound(gm, players, settings)
		roundInProgress = false
		returnToLobby(players)

		-- Réactive les countdowns en attente
		for name in queues do
			updateBillboard(name)
			checkAndMaybeCountdown(name)
		end
	end)
end

returnToLobby = function(players: { Player })
	task.wait(RETURN_DELAY)
	banner("🏠 Retour au lobby !")

	for _, p in players do
		if not p.Parent then continue end
		task.spawn(function()
			p:LoadCharacter()
			local char = p.Character or p.CharacterAdded:Wait()
			local hrp  = char and char:WaitForChild("HumanoidRootPart", 5)
			if hrp and #lobbySpawns > 0 then
				hrp.CFrame = lobbySpawns[math.random(1, #lobbySpawns)]
			end
		end)
	end
end

-- ===== Heartbeat : backup pour détecter les sorties de zone =====
task.spawn(function()
	while true do
		task.wait(2)
		for player, gamemodeName in playerZone do
			if not player.Parent then
				removeFromQueues(player)
				continue
			end
			local part = zoneParts[gamemodeName]
			if not part then continue end
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if not hrp then continue end
			local dx       = hrp.Position.X - part.Position.X
			local dz       = hrp.Position.Z - part.Position.Z
			local dist2D   = math.sqrt(dx*dx + dz*dz)
			local threshold = math.max(part.Size.X, part.Size.Z) / 2 + 4
			if dist2D > threshold then
				removeFromQueues(player)
			end
		end
	end
end)

-- ===== API publique =====

function LobbyService.Start(gamemodes)
	availableGamemodes = gamemodes

	-- Initialise les queues
	for _, gm in gamemodes do
		queues[gm.Name] = { players = {}, inCountdown = false }
	end

	-- Charge la map lobby si disponible
	local venuesFolder = ServerStorage:FindFirstChild("Venues")
	local lobbyModel   = venuesFolder and venuesFolder:FindFirstChild("Lobby")
	if lobbyModel then
		local cloned = lobbyModel:Clone()
		cloned.Name = "_Lobby"
		cloned.Parent = workspace

		-- Spawn points
		local spawnFolder = cloned:FindFirstChild("SpawnPoints")
		if spawnFolder then
			for _, part in spawnFolder:GetChildren() do
				if part:IsA("BasePart") then
					table.insert(lobbySpawns, part.CFrame + Vector3.new(0, 5, 0))
				end
			end
		end

		-- Zones définies dans la map (BasePart avec Attribute "Gamemode")
		for _, desc in cloned:GetDescendants() do
			if desc:IsA("BasePart") then
				local gmName = desc:GetAttribute("Gamemode")
				if gmName and queues[gmName] then
					setupZonePart(desc, gmName)
				end
			end
		end
	end

	-- Zones procédurales pour les gamemodes sans zone définie en Studio
	local posIdx = 1
	for _, gm in gamemodes do
		if not zoneParts[gm.Name] then
			local pos = ZONE_FALLBACK_POSITIONS[posIdx] or Vector3.new(0, 0, 0)
			createProceduralZone(gm.Name, pos)
			posIdx += 1
		end
	end

	-- Spawns lobby par défaut si aucun trouvé
	if #lobbySpawns == 0 then
		for i = 0, 7 do
			local a = (i / 8) * math.pi * 2
			table.insert(lobbySpawns, CFrame.new(math.cos(a) * 20, 5, math.sin(a) * 20))
		end
	end

	-- Gestion des joueurs
	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			local char = player.Character or player.CharacterAdded:Wait()
			local hrp  = char and char:WaitForChild("HumanoidRootPart", 5)
			if hrp and #lobbySpawns > 0 then
				hrp.CFrame = lobbySpawns[math.random(1, #lobbySpawns)]
			end
		end)
		banner("👋 " .. player.Name .. " a rejoint le lobby !")
	end)

	Players.PlayerRemoving:Connect(removeFromQueues)

	banner("🏠 Lobby ouvert — montez sur une zone pour jouer !")
	print("[LobbyService] démarré ✅")
end

return LobbyService
