--!nonstrict
-- MatchmakingService.luau — File d'attente CROSS-SERVEUR (MemoryStoreService) : rassemble des
-- joueurs venant de PLUSIEURS serveurs Hub différents pour un même gamemode, dans un seul
-- serveur réservé de la MÊME Place (voir docs/ROADMAP.md "Architecture serveur" — décision de ne
-- pas séparer Hub/Match en deux Places distinctes).
--
-- Principe en 3 étapes :
--  1. ENQUEUE — chaque serveur Hub ajoute l'UserId du joueur à une MemoryStoreQueue partagée
--     (une par gamemode) quand il clique "Jouer".
--  2. COORDINATION — TOUS les serveurs Hub font tourner la MÊME boucle de coordination ; c'est
--     sans danger : `ReadAsync(minPlayers, true, 0)` (allOrNothing) est atomique côté
--     MemoryStoreService — un seul serveur peut "gagner" un lot exact de minPlayers joueurs à la
--     fois, les autres reçoivent un lot vide et retenteront au prochain tour. Le serveur qui
--     gagne un lot réserve un serveur (TeleportService:ReserveServer) et écrit une "affectation"
--     par joueur matché dans une MemoryStoreSortedMap partagée.
--  3. DEQUEUE — un joueur ne peut être téléporté QUE depuis le serveur où il se trouve
--     PHYSIQUEMENT (TeleportService ne permet pas de téléporter un joueur distant). Donc chaque
--     serveur Hub surveille, pour SES PROPRES joueurs en recherche, si une affectation est
--     apparue à leur nom — et si oui, exécute lui-même le TeleportAsync vers le serveur réservé.
--     C'est ce qui permet à des joueurs de serveurs différents de se retrouver dans la même
--     partie : chacun est téléporté par SON serveur d'origine, vers le même accessCode partagé.

local Players            = game:GetService("Players")
local TeleportService    = game:GetService("TeleportService")
local MemoryStoreService = game:GetService("MemoryStoreService")

local MatchmakingService = {}

-- ===== Config =====
local QUEUE_INVISIBILITY_TIMEOUT = 30  -- s : durée pendant laquelle un lot lu reste cachÉ aux autres serveurs, le temps d'être traité
local QUEUE_ITEM_EXPIRATION      = 300 -- s : abandon auto si la queue est trop calme pour compléter un lot (5 min)
local ASSIGNMENT_TTL             = 60  -- s : durée de vie d'une affectation non réclamée (auto-nettoyage)
local COORDINATOR_INTERVAL       = 3   -- s entre deux tentatives de "gagner" un lot, par gamemode
local ASSIGNMENT_POLL_INTERVAL   = 2   -- s entre deux vérifications "ai-je été matché ?"

local assignmentsMap = MemoryStoreService:GetSortedMap("ClownGorillasMatchAssignments")

-- Joueurs actuellement en recherche cross-serveur SUR CE serveur (gamemodeName par joueur).
local searching: { [Player]: string } = {}

local function getQueue(gamemodeName: string)
	return MemoryStoreService:GetQueue("ClownGorillasQueue_" .. gamemodeName, QUEUE_INVISIBILITY_TIMEOUT)
end

-- ===== API publique (appelée par LobbyService) =====

function MatchmakingService.Enqueue(player: Player, gamemodeName: string)
	if searching[player] then return end
	searching[player] = gamemodeName

	local queue = getQueue(gamemodeName)
	local ok, err = pcall(function()
		queue:AddAsync(player.UserId, QUEUE_ITEM_EXPIRATION)
	end)
	if not ok then
		warn("[Matchmaking] AddAsync échoué pour " .. player.Name .. " : " .. tostring(err))
		searching[player] = nil
	end
end

function MatchmakingService.Dequeue(player: Player)
	-- Une MemoryStoreQueue ne permet pas de retirer un item précis par valeur (ce n'est pas une
	-- map) : on laisse simplement l'entrée expirer (QUEUE_ITEM_EXPIRATION) si jamais elle est lue
	-- plus tard par un coordinateur, le joueur ne sera juste plus là pour réclamer son
	-- affectation, qui expirera à son tour (ASSIGNMENT_TTL) sans dégât.
	searching[player] = nil
end

function MatchmakingService.IsSearching(player: Player): boolean
	return searching[player] ~= nil
end

-- ===== Coordinateur : tourne sur CHAQUE serveur Hub, sans danger (voir en-tête) =====
local function runCoordinatorFor(gamemodeName: string, minPlayers: number)
	local queue = getQueue(gamemodeName)

	local ok, items, id = pcall(function()
		return queue:ReadAsync(minPlayers, true, 0)
	end)
	if not ok or not items or #items == 0 then return end

	local reserveOk, accessCode = pcall(function()
		return TeleportService:ReserveServer(game.PlaceId)
	end)
	if not reserveOk then
		warn("[Matchmaking] ReserveServer échoué pour " .. gamemodeName .. " : " .. tostring(accessCode))
		-- On NE retire PAS le lot de la queue : il redeviendra visible après le timeout
		-- d'invisibilité et un autre serveur retentera sa chance.
		return
	end

	for _, userId in items do
		pcall(function()
			assignmentsMap:SetAsync(tostring(userId), {
				accessCode   = accessCode,
				gamemodeName = gamemodeName,
			}, ASSIGNMENT_TTL)
		end)
	end

	-- Le lot est traité (affectations écrites) : on peut le retirer définitivement de la queue.
	pcall(function()
		queue:RemoveAsync(id)
	end)

	print(string.format(
		"[Matchmaking] Lot de %d joueur(s) réservé pour %s (accessCode=%s)",
		#items, gamemodeName, tostring(accessCode)
	))
end

-- ===== Poll des affectations : chaque serveur surveille SES PROPRES joueurs en recherche =====
local function pollAssignmentFor(player: Player)
	local gamemodeName = searching[player]
	if not gamemodeName then return end

	local ok, assignment = pcall(function()
		return assignmentsMap:GetAsync(tostring(player.UserId))
	end)
	if not ok or not assignment then return end

	searching[player] = nil
	pcall(function()
		assignmentsMap:RemoveAsync(tostring(player.UserId))
	end)

	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = assignment.accessCode
	options:SetTeleportData({ isMatchServer = true, gamemodeName = assignment.gamemodeName })

	local teleportOk, teleportErr = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, { player }, options)
	end)
	if not teleportOk then
		warn("[Matchmaking] Téléportation échouée pour " .. player.Name .. " : " .. tostring(teleportErr))
	end
end

-- ===== Démarrage =====
function MatchmakingService.Start(gamemodes: { any })
	for _, gm in gamemodes do
		local gamemodeName = gm.Name
		local minPlayers   = gm.MinPlayers or 2
		task.spawn(function()
			while true do
				task.wait(COORDINATOR_INTERVAL)
				runCoordinatorFor(gamemodeName, minPlayers)
			end
		end)
	end

	task.spawn(function()
		while true do
			task.wait(ASSIGNMENT_POLL_INTERVAL)
			for player in searching do
				pollAssignmentFor(player)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		searching[player] = nil
	end)
end

return MatchmakingService
