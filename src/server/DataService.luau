--!nonstrict
-- DataService.luau — Persistance joueur : Goofy Points, niveaux, cosmétiques.
-- API : GetProfile(player), AddGoofyPoints(player, n), GetLevel(player)
--
-- Basé sur ProfileStore (src/server/ProfileStore.luau, vendored depuis
-- https://github.com/MadStudioRoblox/ProfileStore, licence MIT) plutôt que DataStoreService brut :
--   - Session-lock : un même profil ne peut être actif que sur UN SEUL serveur à la fois.
--     `StartSessionAsync` gère lui-même les reconnexions rapides (retry automatique pendant
--     jusqu'à 120s si le profil est encore verrouillé ailleurs) avant d'abandonner.
--   - Anti-perte : sauvegardes périodiques + sauvegarde de fermeture (`game:BindToClose`) gérées
--     EN INTERNE par ProfileStore — pas besoin de dupliquer cette logique ici.
--   - Retries : `GetAsync`/`SetAsync` internes à ProfileStore sont déjà entourés de pcall/retry.
-- Notre travail ici se limite donc à bien UTILISER l'API (StartSessionAsync/EndSession/Reconcile),
-- pas à réimplémenter la fiabilité nous-mêmes.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileStoreModule = require(script.Parent.ProfileStore)

local PlayerConfig = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("PlayerConfig")
)
local LeaderboardService = require(script.Parent.LeaderboardService)
local AchievementService = require(script.Parent.AchievementService)

-- ===== Config =====

local STORE_KEY = "GoofyGorillas_v2" -- v2 : passage à ProfileStore, format différent de l'ancien DataStore brut (v1)

local TEMPLATE = {
	goofyPoints    = 0,
	level          = 1,
	ownedCosmetics = {},
	equipped       = {},
	achievements   = {},
	bestTimes      = {},
	stats = {
		gamesPlayed = 0,
		gamesWon    = 0,
	},
}

local playerStore = ProfileStoreModule.New(STORE_KEY, TEMPLATE)

-- RemoteEvent : le serveur notifie les clients de leurs données
local DataUpdated = Instance.new("RemoteEvent")
DataUpdated.Name  = "DataUpdated"
DataUpdated.Parent = ReplicatedStorage

-- ===== État =====

local profiles: { [Player]: any } = {} -- [Player] → Profile ProfileStore (Profile.Data = la table de jeu)

-- `OnSessionEnd` se déclenche aussi bien quand un AUTRE serveur vole la session que quand NOUS
-- appelons nous-mêmes `profile:EndSession()` (déconnexion normale, voir onPlayerRemoving) — sans
-- distinction, un joueur qui quitte normalement se ferait quand même kick inutilement.
local voluntaryEnding: { [Player]: boolean } = {}

local function computeLevel(points)
	for lvl = PlayerConfig.MAX_LEVEL, 1, -1 do
		if PlayerConfig.LEVEL_THRESHOLDS[lvl] and points >= PlayerConfig.LEVEL_THRESHOLDS[lvl] then
			return lvl
		end
	end
	return 1
end

-- ===== Leaderstats =====

local function syncLeaderstats(player, data)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = player
	end

	local function ensureInt(name, value)
		local val = ls:FindFirstChild(name)
		if not val then
			val = Instance.new("IntValue")
			val.Name = name
			val.Parent = ls
		end
		val.Value = value
	end

	ensureInt("GP",  data.goofyPoints)
	ensureInt("Lvl", data.level)
end

-- ===== API publique =====

local DataService = {}

function DataService.GetProfile(player)
	local profile = profiles[player]
	return profile and profile.Data
end

function DataService.GetLevel(player)
	local profile = profiles[player]
	return profile and profile.Data.level or 1
end

function DataService.GetNextThreshold(player)
	local profile = profiles[player]
	if not profile then return nil end
	return PlayerConfig.LEVEL_THRESHOLDS[profile.Data.level + 1]
end

function DataService.AddGoofyPoints(player, amount)
	local profile = profiles[player]
	if not profile then return end
	local data = profile.Data

	data.goofyPoints = math.max(0, data.goofyPoints + amount)

	local newLevel  = computeLevel(data.goofyPoints)
	local leveledUp = newLevel > data.level
	data.level      = newLevel

	syncLeaderstats(player, data)
	LeaderboardService.UpdateScore(player.UserId, data.goofyPoints)
	AchievementService.Check(player, data, "gp_change")

	DataUpdated:FireClient(player, {
		goofyPoints = data.goofyPoints,
		level       = data.level,
		leveledUp   = leveledUp,
	})
end

-- ===== Cycle de vie des joueurs =====

local function onPlayerAdded(player: Player)
	-- StartSessionAsync gère lui-même les reconnexions rapides : si ce profil est encore
	-- verrouillé par un autre serveur, il RETENTE automatiquement (jusqu'à ~120s) avant
	-- d'abandonner (retourne nil) — pas besoin de boucle de retry manuelle ici.
	local profile = playerStore:StartSessionAsync(tostring(player.UserId), {
		Cancel = function()
			return player.Parent ~= Players -- le joueur est parti avant la fin du chargement
		end,
	})

	if not profile then
		-- Verrouillé ailleurs après tous les essais internes, ou le joueur est parti entre-temps.
		if player.Parent == Players then
			player:Kick("Impossible de charger tes données pour le moment (déjà en cours de chargement ailleurs). Réessaie dans un instant.")
		end
		return
	end

	profile:AddUserId(player.UserId) -- association GDPR
	profile:Reconcile() -- comble les champs manquants depuis TEMPLATE (nouveaux champs ajoutés après coup)

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		local wasVoluntary = voluntaryEnding[player]
		voluntaryEnding[player] = nil
		if wasVoluntary then return end -- déconnexion normale (onPlayerRemoving) : rien à faire de plus

		-- Un autre serveur a volé la session (ou celle-ci a expiré) : ce joueur n'a plus de
		-- profil actif ici, impossible de continuer à jouer en toute sécurité sur CE serveur.
		if player.Parent == Players then
			player:Kick("Tes données ont été chargées par un autre serveur. Reconnecte-toi.")
		end
	end)

	if player.Parent ~= Players then
		-- Le joueur est parti PENDANT le chargement (StartSessionAsync a pu prendre du temps en
		-- cas de conflit de session) : libère immédiatement, sinon la session resterait verrouillée
		-- pour rien jusqu'à expiration.
		profile:EndSession()
		return
	end

	profiles[player] = profile
	syncLeaderstats(player, profile.Data)
	LeaderboardService.UpdateScore(player.UserId, profile.Data.goofyPoints)
	DataUpdated:FireClient(player, {
		goofyPoints = profile.Data.goofyPoints,
		level       = profile.Data.level,
		leveledUp   = false,
	})
	print("[DataService]", player.Name, "chargé — Lvl", profile.Data.level, "| GP", profile.Data.goofyPoints)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile then
		voluntaryEnding[player] = true
		profile:EndSession() -- déclenche la sauvegarde finale (ProfileStore s'en charge)
		profiles[player] = nil
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Rattraper les joueurs déjà là (test Studio en solo)
for _, p in Players:GetPlayers() do
	task.spawn(onPlayerAdded, p)
end

-- Pas d'auto-save ni de BindToClose ici : ProfileStore gère déjà tout ça en interne pour chaque
-- profil actif (voir l'en-tête de ProfileStore.luau).

print("[DataService] démarré ✅ (ProfileStore)")
return DataService
