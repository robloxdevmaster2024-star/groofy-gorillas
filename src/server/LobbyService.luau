--!nonstrict
-- LobbyService.luau — Hub lobby : files d'attente, countdown, lancement des rounds.
--
-- Rejoindre une file se fait UNIQUEMENT via le bouton "JOUER" (voir PlayButton.client.luau) —
-- pas de zone physique à marcher dessus dans le monde.
--
-- Convention map Studio :
--   ServerStorage.Venues.Lobby  →  Model avec :
--     SpawnPoints/   → BaseParts (positions de spawn lobby)

local Players           = game:GetService("Players")
local ServerStorage     = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local RoundRunner        = require(script.Parent.RoundRunner)
local GameSettings       = require(script.Parent.GameSettings)
local MatchmakingService = require(script.Parent.MatchmakingService)
local MatchmakingConfig  = require(script.Parent.MatchmakingConfig)
local LeaderboardPodium  = require(script.Parent.LeaderboardPodium)

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
local zoneUpdateEvent    = getOrCreate(lobbyFolder, "ZoneUpdate"); zoneUpdateEvent.Name = "ZoneUpdate" -- statut de file (compteur/countdown) pour le HUD
local playerZoneEvent    = getOrCreate(lobbyFolder, "PlayerZone"); playerZoneEvent.Name = "PlayerZone" -- file actuelle du joueur (nil si aucune)
local requestJoinEvent   = getOrCreate(lobbyFolder, "RequestJoinQueue"); requestJoinEvent.Name = "RequestJoinQueue"
local requestLeaveEvent  = getOrCreate(lobbyFolder, "RequestLeaveQueue"); requestLeaveEvent.Name = "RequestLeaveQueue"
local getGamemodesFunc   = lobbyFolder:FindFirstChild("GetGamemodes") or Instance.new("RemoteFunction")
getGamemodesFunc.Name    = "GetGamemodes"
getGamemodesFunc.Parent  = lobbyFolder

-- ===== Constantes =====
local COUNTDOWN      = 5    -- secondes avant le lancement
local RETURN_DELAY   = 3    -- secondes après round avant retour lobby

-- ===== État =====
local LobbyService = {}

local availableGamemodes = {}
local roundInProgress    = false
local lobbySpawns : { CFrame } = {}

-- queue par gamemode : { players: {[Player]: true}, inCountdown: bool, timeLeft: number }
local queues : { [string]: { players: { [Player]: boolean }, inCountdown: boolean, timeLeft: number } } = {}

-- gamemode dont la file est actuellement rejointe par chaque joueur (nil si aucune)
local playerZone : { [Player]: string? } = {}

-- joueurs actuellement en partie (round en cours) : interdit de rejoindre une nouvelle file.
-- Valeur = un ID de round (pas juste `true`) : `returnToLobby` attend RETURN_DELAY avant de
-- nettoyer, et un joueur peut avoir rejoint UNE AUTRE partie entre-temps (roundInProgress repasse
-- à false dès la fin du round, avant même que returnToLobby ait fini d'attendre) — sans cet ID,
-- le nettoyage tardif de l'ancienne partie effaçait le flag de la nouvelle partie en cours,
-- laissant l'anti-triche du hub reprendre la main sur un joueur pourtant toujours en plein round.
local playersInRound : { [Player]: number } = {}
local roundIdCounter = 0

-- ===== Forward declarations (récursion mutuelle) =====
local checkAndMaybeCountdown
local startRound
local returnToLobby
local removeFromQueues
local joinQueue

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

-- ===== Statut de file (HUD client) =====

local function broadcastQueueStatus(gamemodeName: string)
	local q     = queues[gamemodeName]
	local count = queueCount(gamemodeName)
	local minP  = minPlayers(gamemodeName)

	zoneUpdateEvent:FireAllClients({
		gamemodeName    = gamemodeName,
		count           = count,
		minPlayers      = minP,
		inCountdown     = q and q.inCountdown or false,
		roundInProgress = roundInProgress,
	})
end

-- ===== Queue / countdown =====

removeFromQueues = function(player: Player)
	local current = playerZone[player]
	playerZone[player]       = nil
	playersInRound[player]   = nil
	if current and queues[current] then
		queues[current].players[player] = nil
		broadcastQueueStatus(current)
	end
	playerZoneEvent:FireClient(player, { gamemodeName = nil })
end

-- Fait rejoindre `player` à la file de `gamemodeName` (depuis le bouton "Jouer" côté client).
-- Idempotent si déjà dedans.
joinQueue = function(player: Player, gamemodeName: string)
	if not queues[gamemodeName] then return end
	if playersInRound[player] then return end -- déjà en partie : requête ignorée (anti-triche)
	if MatchmakingConfig.Enabled and MatchmakingService.IsSearching(player) then return end -- déjà en recherche cross-serveur
	if playerZone[player] == gamemodeName then return end

	if playerZone[player] then
		removeFromQueues(player)
	end

	playerZone[player]                   = gamemodeName
	queues[gamemodeName].players[player] = true
	broadcastQueueStatus(gamemodeName)
	playerZoneEvent:FireClient(player, { gamemodeName = gamemodeName })

	local q = queues[gamemodeName]
	if q.inCountdown then
		-- Un nouveau joueur vient de rejoindre pendant le décompte : on repart du cooldown de base.
		q.timeLeft = COUNTDOWN
	end

	checkAndMaybeCountdown(gamemodeName)
end

checkAndMaybeCountdown = function(gamemodeName: string)
	local q = queues[gamemodeName]
	if not q or q.inCountdown or roundInProgress then return end
	if queueCount(gamemodeName) < minPlayers(gamemodeName) then return end

	q.inCountdown = true
	q.timeLeft    = COUNTDOWN
	local gm = getGamemode(gamemodeName)
	if gm then GameSettings.OpenPanel(gm) end
	broadcastQueueStatus(gamemodeName)

	task.spawn(function()
		-- Boucle sur q.timeLeft (pas une variable locale) : joinQueue() peut le remettre à
		-- COUNTDOWN à tout moment si un nouveau joueur rejoint pendant le décompte.
		while q.timeLeft > 0 do
			-- Annuler si pas assez de joueurs
			if queueCount(gamemodeName) < minPlayers(gamemodeName) then
				q.inCountdown = false
				GameSettings.ClosePanel()
				banner("⚠️ " .. gamemodeName .. " — pas assez de joueurs, countdown annulé")
				broadcastQueueStatus(gamemodeName)
				return
			end
			zoneUpdateEvent:FireAllClients({
				gamemodeName    = gamemodeName,
				count           = queueCount(gamemodeName),
				minPlayers      = minPlayers(gamemodeName),
				inCountdown     = true,
				countdown       = q.timeLeft,
				roundInProgress = false,
			})
			task.wait(1)
			q.timeLeft -= 1
		end

		-- Lancement
		if queueCount(gamemodeName) >= minPlayers(gamemodeName) then
			startRound(gamemodeName)
		else
			q.inCountdown = false
			GameSettings.ClosePanel()
			broadcastQueueStatus(gamemodeName)
		end
	end)
end

startRound = function(gamemodeName: string)
	local q = queues[gamemodeName]
	if not q then return end

	q.inCountdown   = false
	roundInProgress = true
	GameSettings.ClosePanel()

	roundIdCounter += 1
	local thisRoundId = roundIdCounter

	-- Collecte les participants
	local players = {}
	for p in q.players do
		if p.Parent then table.insert(players, p) end
	end

	-- Vide la queue et met à jour les zones de ces joueurs
	-- (inRound = true : le client doit garder le bouton "Jouer" caché jusqu'au retour au lobby)
	for p in q.players do
		playerZone[p]      = nil
		playersInRound[p]  = thisRoundId
		playerZoneEvent:FireClient(p, { gamemodeName = nil, inRound = true })
	end
	q.players = {}

	for _, name in queues do
		broadcastQueueStatus(name)
	end

	if #players < minPlayers(gamemodeName) then
		roundInProgress = false
		for _, p in players do
			if playersInRound[p] == thisRoundId then
				playersInRound[p] = nil
			end
			if p.Parent then
				playerZoneEvent:FireClient(p, { gamemodeName = nil, inRound = false })
			end
		end
		return
	end

	local gm       = getGamemode(gamemodeName)
	local settings = GameSettings.GetSettings(gamemodeName, gm.DefaultSettings)
	banner("🎮 " .. gamemodeName .. " — " .. #players .. " joueurs en route !")

	-- Lance le round dans un thread dédié
	task.spawn(function()
		RoundRunner.RunRound(gm, players, settings)
		roundInProgress = false
		returnToLobby(players, thisRoundId)

		-- Réactive les countdowns en attente
		for name in queues do
			broadcastQueueStatus(name)
			checkAndMaybeCountdown(name)
		end
	end)
end

returnToLobby = function(players: { Player }, thisRoundId: number)
	task.wait(RETURN_DELAY)
	banner("🏠 Retour au lobby !")

	for _, p in players do
		if not p.Parent then continue end
		-- Ce joueur a pu rejoindre UNE AUTRE partie pendant les RETURN_DELAY secondes d'attente
		-- (roundInProgress repasse à false dès la fin du round, avant ce délai) : dans ce cas, ni
		-- le flag playersInRound ni le renvoi au lobby (reload perso, téléport) ne doivent
		-- s'appliquer — ce serait casser la partie où il est réellement en train de jouer.
		if playersInRound[p] ~= thisRoundId then continue end

		playersInRound[p] = nil
		playerZoneEvent:FireClient(p, { gamemodeName = nil, inRound = false })
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

-- ===== Anti-triche (hub) : vitesse + vol =====
-- Même principe que l'anti-triche de Clown Survival (voir ClownSurvival.luau ->
-- getMovementState/STATE_MAX_SPEED), en version simplifiée pour le hub : pas de sprint/glissade
-- ici, juste la marche + le saut natifs Roblox. Vise les speed-hacks (vitesse horizontale) ET les
-- fly-hacks basiques (vélocité verticale anormalement soutenue vers le haut, largement au-dessus
-- de ce qu'un saut normal peut produire). Les joueurs déjà en partie sont ignorés : leur propre
-- gamemode a déjà son anti-triche adapté (sprint/glissade/dash autorisés à des vitesses plus hautes).
local HUB_SPEED_TOLERANCE  = 1.35
local HUB_MAX_HORIZONTAL   = 16 * HUB_SPEED_TOLERANCE -- WalkSpeed par défaut du hub (16) + marge
local HUB_MAX_UPWARD_SPEED = 60 -- studs/s : nettement au-dessus d'un saut normal (JumpPower ~50)

local function stepHubAntiCheat()
	for _, player in Players:GetPlayers() do
		if playersInRound[player] then continue end -- géré par l'anti-triche du round lui-même

		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hum or not hrp or hum.PlatformStand then continue end -- PlatformStand : ragdoll/effet légitime en cours

		local velocity = hrp.AssemblyLinearVelocity
		local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
		local corrected = velocity

		if horizontal.Magnitude > HUB_MAX_HORIZONTAL then
			local clampedHorizontal = horizontal.Unit * HUB_MAX_HORIZONTAL
			corrected = Vector3.new(clampedHorizontal.X, corrected.Y, clampedHorizontal.Z)
		end

		if corrected.Y > HUB_MAX_UPWARD_SPEED then
			corrected = Vector3.new(corrected.X, HUB_MAX_UPWARD_SPEED, corrected.Z)
		end

		if corrected ~= velocity then
			hrp.AssemblyLinearVelocity = corrected
			warn(("[Anti-triche hub] Vitesse anormale corrigée pour %s"):format(player.Name))
		end
	end
end
RunService.Heartbeat:Connect(stepHubAntiCheat)

-- ===== API publique =====

function LobbyService.Start(gamemodes)
	availableGamemodes = gamemodes

	-- Initialise les queues
	for _, gm in gamemodes do
		queues[gm.Name] = { players = {}, inCountdown = false, timeLeft = 0 }
	end

	-- File d'attente cross-serveur (voir MatchmakingService.luau) : SUSPENDU pour l'instant, voir
	-- MatchmakingConfig.luau pour la raison et comment reprendre.
	if MatchmakingConfig.Enabled then
		MatchmakingService.Start(gamemodes)
	end

	-- Charge la map lobby si disponible
	local venuesFolder = ServerStorage:FindFirstChild("Venues")
	local lobbyModel   = venuesFolder and venuesFolder:FindFirstChild("Lobby")
	local clonedLobby: Instance? = nil
	if lobbyModel then
		local cloned = lobbyModel:Clone()
		cloned.Name = "_Lobby"
		cloned.Parent = workspace
		clonedLobby = cloned

		-- Spawn points
		local spawnFolder = cloned:FindFirstChild("SpawnPoints")
		if spawnFolder then
			for _, part in spawnFolder:GetChildren() do
				if part:IsA("BasePart") then
					table.insert(lobbySpawns, part.CFrame + Vector3.new(0, 5, 0))
				end
			end
		end
	end

	-- Podium 3D des classements (voir LeaderboardPodium.luau) : Model "LeaderboardPodium" (vraies
	-- Parts Rank1/2/3 + Board) posé à la main directement dans workspace, à côté du hub.
	LeaderboardPodium.Build()

	-- SpawnLocation(s) placées directement dans Workspace : si le level designer en a posé une,
	-- Roblox sait déjà spawner les joueurs dessus nativement — pas besoin (et pas question) de
	-- forcer un CFrame par-dessus, ça casserait le bouton Studio "Tester ici" (spawn à la position
	-- du curseur en Edit mode), qui compte justement sur l'absence d'un script qui replace le
	-- joueur après coup. `lobbySpawns` reste seulement utile pour le retour au lobby après un round
	-- (voir plus haut, EndRound) et pour le cas fallback ci-dessous.
	local usingNativeSpawnLocation = false
	do
		local nativeSpawns : { CFrame } = {}
		for _, inst in workspace:GetDescendants() do
			if inst:IsA("SpawnLocation") then
				table.insert(nativeSpawns, inst.CFrame + Vector3.new(0, 5, 0))
			end
		end
		if #nativeSpawns > 0 then
			lobbySpawns = nativeSpawns
			usingNativeSpawnLocation = true
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
		if not usingNativeSpawnLocation then
			-- Pas de SpawnLocation native : Roblox n'a rien pour placer le joueur tout seul
			-- (SpawnPoints custom ou grille de secours), donc on le fait à la main.
			task.spawn(function()
				local char = player.Character or player.CharacterAdded:Wait()
				local hrp  = char and char:WaitForChild("HumanoidRootPart", 5)
				if hrp and #lobbySpawns > 0 then
					hrp.CFrame = lobbySpawns[math.random(1, #lobbySpawns)]
				end
			end)
		end
		banner("👋 " .. player.Name .. " a rejoint le lobby !")
	end)

	Players.PlayerRemoving:Connect(removeFromQueues)

	-- Bouton "Jouer" client : recherche CROSS-SERVEUR (voir MatchmakingService.luau) quand
	-- activé — sinon (voir MatchmakingConfig.luau, SUSPENDU pour l'instant), retombe sur
	-- l'ancien comportement 100% local, identique à avant l'ajout du matchmaking cross-serveur.
	requestJoinEvent.OnServerEvent:Connect(function(player, gamemodeName)
		if type(gamemodeName) ~= "string" then return end

		if not MatchmakingConfig.Enabled then
			joinQueue(player, gamemodeName)
			return
		end

		if not queues[gamemodeName] then return end
		if playersInRound[player] then return end -- déjà en partie (anti-triche)
		if playerZone[player] then return end -- déjà dans une file locale : pas de double recherche
		if MatchmakingService.IsSearching(player) then return end

		MatchmakingService.Enqueue(player, gamemodeName)
		playerZoneEvent:FireClient(player, { gamemodeName = gamemodeName })
	end)

	-- Annulation de la recherche depuis le client (locale OU cross-serveur)
	requestLeaveEvent.OnServerEvent:Connect(function(player)
		if MatchmakingConfig.Enabled and MatchmakingService.IsSearching(player) then
			MatchmakingService.Dequeue(player)
			playerZoneEvent:FireClient(player, { gamemodeName = nil })
		else
			removeFromQueues(player)
		end
	end)

	-- Fournit la liste des gamemodes (nom, description, min joueurs) pour le menu client
	getGamemodesFunc.OnServerInvoke = function(_player)
		local list = {}
		for _, gm in gamemodes do
			table.insert(list, {
				name        = gm.Name,
				description = gm.Description,
				minPlayers  = gm.MinPlayers,
			})
		end
		return list
	end

	banner("🏠 Lobby ouvert — clique sur JOUER pour choisir un mode !")
	print("[LobbyService] démarré ✅")
end

return LobbyService
