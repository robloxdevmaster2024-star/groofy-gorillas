--!nonstrict
-- RoundManager.server.luau — Point d'entrée serveur.
-- Crée GameStatus puis démarre soit le Hub (LobbyService), soit directement un round si ce
-- serveur est un serveur de MATCH réservé par le matchmaking cross-serveur (voir
-- MatchmakingService.luau + docs/ROADMAP.md "Architecture serveur" — une seule Place, des
-- serveurs réservés à la volée plutôt que deux Places séparées).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService   = game:GetService("TeleportService")

local MatchmakingConfig = require(script.Parent.MatchmakingConfig)

-- GameStatus doit exister avant que les clients se connectent
if not ReplicatedStorage:FindFirstChild("GameStatus") then
	local e = Instance.new("RemoteEvent")
	e.Name   = "GameStatus"
	e.Parent = ReplicatedStorage
end

-- Gamemodes disponibles (ajouter ici les prochains modes)
local GamemodesFolder = script.Parent:FindFirstChild("Gamemodes")
assert(GamemodesFolder, "❌ Dossier 'Gamemodes' introuvable.")
local AVAILABLE_GAMEMODES = {
	require(GamemodesFolder.ClownSurvival),
	require(GamemodesFolder.Dodgeball),
}

local function getGamemode(name: string)
	for _, gm in AVAILABLE_GAMEMODES do
		if gm.Name == name then return gm end
	end
	return nil
end

-- Seuls les serveurs RÉSERVÉS (PrivateServerId non vide — VIP server OU réservé via
-- TeleportService:ReserveServer) peuvent être des serveurs de match : on ne veut PAS bloquer le
-- démarrage d'un serveur Hub public normal en attendant un premier joueur (LobbyService doit
-- s'initialiser tout de suite pour ne rater aucun PlayerAdded). Un serveur réservé démarre lui
-- VIDE de toute façon, donc attendre son premier joueur pour lire ses données de téléportation
-- ne retarde rien d'anormal.
local function readMatchTeleportData(): { gamemodeName: string }?
	if game.PrivateServerId == "" then
		return nil -- serveur public normal : jamais un serveur de match
	end

	local player = Players:GetPlayers()[1]
	if not player then
		player = Players.PlayerAdded:Wait()
	end

	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	local teleportData = ok and joinData and joinData.TeleportData
	if typeof(teleportData) == "table" and teleportData.isMatchServer then
		return teleportData :: any
	end
	return nil
end

-- Matchmaking cross-serveur SUSPENDU pour l'instant (voir MatchmakingConfig.luau) : on saute la
-- détection "serveur de match" et on démarre toujours le Hub normal, comme avant son ajout.
local matchData = MatchmakingConfig.Enabled and readMatchTeleportData() or nil

if matchData and matchData.gamemodeName then
	-- ===== Mode MATCH : démarre directement le round avec les joueurs qui arrivent =====
	local RoundRunner  = require(script.Parent.RoundRunner)
	local GameSettings = require(script.Parent.GameSettings)
	local gamemode = getGamemode(matchData.gamemodeName)

	if not gamemode then
		warn("[RoundManager] Serveur de match réservé pour un gamemode inconnu : " .. tostring(matchData.gamemodeName))
	else
		task.spawn(function()
			-- Petite fenêtre de grâce : les joueurs matchés arrivent de PLUSIEURS serveurs Hub
			-- différents (chacun téléporté indépendamment par son propre serveur d'origine, voir
			-- MatchmakingService.luau), donc pas tous à la même frame.
			task.wait(5)

			local players = Players:GetPlayers()
			if #players < (gamemode.MinPlayers or 2) then
				-- Pas assez arrivés (ex. certains ont quitté avant leur téléportation) : on laisse
				-- ce serveur réservé se vider naturellement plutôt que de lancer un round cassé.
				warn("[RoundManager] Pas assez de joueurs arrivés sur le serveur de match, round annulé.")
				return
			end

			local settings = GameSettings.GetSettings(gamemode.Name, gamemode.DefaultSettings)
			RoundRunner.RunRound(gamemode, players, settings)

			-- Fin de partie sur un serveur réservé : pas de Hub ici, on renvoie tout le monde
			-- vers un serveur public normal de la même Place.
			local remaining = Players:GetPlayers()
			if #remaining > 0 then
				pcall(function()
					TeleportService:TeleportAsync(game.PlaceId, remaining)
				end)
			end
		end)
	end
else
	-- ===== Mode HUB normal =====
	require(script.Parent.LobbyService).Start(AVAILABLE_GAMEMODES)
end
