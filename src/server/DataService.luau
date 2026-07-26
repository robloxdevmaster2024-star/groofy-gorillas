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
local WeekId             = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeekId"))
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
		gamesPlayed     = 0,
		gamesWon        = 0,
		winStreaks      = {}, -- [gamemodeName] = streak de victoires consécutives en cours
		bestStreaks     = {}, -- [gamemodeName] = meilleur streak jamais atteint
		clownWins       = 0,  -- Clown Survival : victoires en tant que clown
		survivorWins    = 0,  -- Clown Survival : victoires en tant qu'enfant
		totalClownKills = 0,  -- Clown Survival : coups réussis (contamination OU élimination) en tant que clown, tous rounds confondus
		-- Compteurs de la semaine ISO en cours (voir shared/WeekId.luau), pour les classements
		-- hebdomadaires. Remis à zéro paresseusement (DataService.EnsureCurrentWeek) dès que
		-- `weekId` ne correspond plus à la semaine ISO courante — pas de tâche planifiée à part.
		weekly = {
			weekId     = "",
			gp         = 0,
			wins       = 0,
			bestStreak = 0,
		},
	},
	settings = {
		musicVolume = 0.5,
		sfxVolume   = 0.5,
	},
}

local playerStore = ProfileStoreModule.New(STORE_KEY, TEMPLATE)

-- RemoteEvent : le serveur notifie les clients de leurs données
local DataUpdated = Instance.new("RemoteEvent")
DataUpdated.Name  = "DataUpdated"
DataUpdated.Parent = ReplicatedStorage

-- RemoteFunction : le client récupère un instantané complet de son profil (menu Profil)
local GetProfileSnapshot = Instance.new("RemoteFunction")
GetProfileSnapshot.Name   = "GetProfileSnapshot"
GetProfileSnapshot.Parent = ReplicatedStorage

-- RemoteEvent : le client pousse un changement de préférence perso (volume musique/SFX)
local UpdatePlayerSettings = Instance.new("RemoteEvent")
UpdatePlayerSettings.Name   = "UpdatePlayerSettings"
UpdatePlayerSettings.Parent = ReplicatedStorage

local VALID_SETTINGS_KEYS = { musicVolume = true, sfxVolume = true }

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

-- Reset paresseux des compteurs hebdomadaires si la semaine ISO a changé depuis la dernière
-- action de ce joueur (voir shared/WeekId.luau). Retourne la table `weekly` à jour, prête à être
-- lue/mutée directement par l'appelant (même pattern que `profile.stats` ailleurs dans le code :
-- RoundRunner mute déjà `profile.stats` sans passer par un setter dédié).
function DataService.EnsureCurrentWeek(player)
	local profile = profiles[player]
	if not profile then return nil end
	local weekly = profile.Data.stats.weekly
	local currentWeek = WeekId.Current()
	if weekly.weekId ~= currentWeek then
		weekly.weekId     = currentWeek
		weekly.gp         = 0
		weekly.wins       = 0
		weekly.bestStreak = 0
	end
	return weekly
end

function DataService.GetNextThreshold(player)
	local profile = profiles[player]
	if not profile then return nil end
	return PlayerConfig.LEVEL_THRESHOLDS[profile.Data.level + 1]
end

-- Instantané "sûr" (pas la table brute du profil) pour le menu Profil client : niveau/xp, stats,
-- succès débloqués (juste les ids, la description vit déjà dans AchievementsConfig côté client),
-- réglages perso. Volontairement pas de cosmétiques (système pas encore décidé, voir ROADMAP).
function DataService.GetProfileSnapshot(player)
	local profile = profiles[player]
	if not profile then return nil end
	local data = profile.Data

	local unlockedAchievements = {}
	for id, unlocked in data.achievements do
		if unlocked then table.insert(unlockedAchievements, id) end
	end

	return {
		goofyPoints       = data.goofyPoints,
		level             = data.level,
		currentThreshold  = PlayerConfig.LEVEL_THRESHOLDS[data.level] or 0,
		nextThreshold     = PlayerConfig.LEVEL_THRESHOLDS[data.level + 1], -- nil si niveau max
		gamesPlayed       = data.stats.gamesPlayed,
		gamesWon          = data.stats.gamesWon,
		winStreaks        = data.stats.winStreaks,
		bestStreaks       = data.stats.bestStreaks,
		clownWins         = data.stats.clownWins,
		survivorWins      = data.stats.survivorWins,
		totalClownKills   = data.stats.totalClownKills,
		unlockedAchievements = unlockedAchievements,
		settings          = data.settings,
	}
end

GetProfileSnapshot.OnServerInvoke = function(player)
	return DataService.GetProfileSnapshot(player)
end

UpdatePlayerSettings.OnServerEvent:Connect(function(player, key, value)
	if type(key) ~= "string" or not VALID_SETTINGS_KEYS[key] then return end
	if type(value) ~= "number" then return end

	local profile = profiles[player]
	if not profile then return end

	profile.Data.settings[key] = math.clamp(value, 0, 1)
end)

function DataService.AddGoofyPoints(player, amount)
	local profile = profiles[player]
	if not profile then return end
	local data = profile.Data

	data.goofyPoints = math.max(0, data.goofyPoints + amount)

	local newLevel  = computeLevel(data.goofyPoints)
	local leveledUp = newLevel > data.level
	data.level      = newLevel

	syncLeaderstats(player, data)
	LeaderboardService.UpdateScore("gp", "alltime", player.UserId, data.goofyPoints)

	local weekly = DataService.EnsureCurrentWeek(player)
	if weekly then
		weekly.gp = math.max(0, weekly.gp + amount)
		LeaderboardService.UpdateScore("gp", "weekly", player.UserId, weekly.gp)
	end

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

	-- Resynchronise tous les classements au chargement (pas seulement GP) : couvre le cas où le
	-- joueur revient après un changement de semaine ISO pendant qu'il était déconnecté (le
	-- prochain gain/victoire l'aurait fait de toute façon, mais autant ne pas attendre).
	local stats = profile.Data.stats
	LeaderboardService.UpdateScore("gp", "alltime", player.UserId, profile.Data.goofyPoints)
	LeaderboardService.UpdateScore("wins", "alltime", player.UserId, stats.gamesWon)
	local bestStreakOverall = 0
	for _, streak in stats.bestStreaks do
		bestStreakOverall = math.max(bestStreakOverall, streak)
	end
	LeaderboardService.UpdateScore("streak", "alltime", player.UserId, bestStreakOverall)

	local weekly = DataService.EnsureCurrentWeek(player)
	if weekly then
		LeaderboardService.UpdateScore("gp", "weekly", player.UserId, weekly.gp)
		LeaderboardService.UpdateScore("wins", "weekly", player.UserId, weekly.wins)
		LeaderboardService.UpdateScore("streak", "weekly", player.UserId, weekly.bestStreak)
	end

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
