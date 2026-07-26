--!nonstrict
-- LeaderboardService.luau — Classements Goofy Points / Victoires / Meilleure série, chacun en
-- deux périodes : ALL TIME (cumul depuis toujours) et HEBDOMADAIRE (repart à zéro chaque semaine
-- ISO). Un OrderedDataStore distinct par (board x période) ; la période hebdo utilise un nom de
-- store suffixé par le numéro de semaine ISO courant (`WeekId.Current()`) — changer de semaine
-- revient donc simplement à écrire dans un NOUVEAU store vide, sans avoir à "réinitialiser" quoi
-- que ce soit : l'ancien store de la semaine précédente reste intact et consultable tel quel.

local Players           = game:GetService("Players")
local DataStoreService  = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeekId = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeekId"))
local LeaderboardsConfig = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("LeaderboardsConfig")
)

local TOP_COUNT             = 25 -- assez pour que le scroll (molette) ait un intérêt dans l'UI/le podium
local AUTO_REFRESH_INTERVAL = 90 -- secondes (+ refresh manuel après chaque round)

local boardIds = {}
for _, board in LeaderboardsConfig.BOARDS do
	table.insert(boardIds, board.id)
end

-- ===== RemoteEvent (créé au chargement) =====
local eventsFolder = ReplicatedStorage:FindFirstChild("LeaderboardEvents")
if not eventsFolder then
	eventsFolder = Instance.new("Folder")
	eventsFolder.Name = "LeaderboardEvents"
	eventsFolder.Parent = ReplicatedStorage
end
local lbEvent = eventsFolder:FindFirstChild("Board") or Instance.new("RemoteEvent", eventsFolder)
lbEvent.Name = "Board"

-- ===== OrderedDataStores (créés à la demande, mis en cache) =====
local storeCache: { [string]: any } = {}

local function storeNameFor(boardId: string, period: string): string
	if period == "weekly" then
		return "GG_LB_" .. boardId .. "_Weekly_v1_" .. WeekId.Current()
	end
	return "GG_LB_" .. boardId .. "_AllTime_v1"
end

local function getStore(boardId: string, period: string)
	local name = storeNameFor(boardId, period)
	local store = storeCache[name]
	if store == nil then
		local ok, result = pcall(function()
			return DataStoreService:GetOrderedDataStore(name)
		end)
		store = (ok and result) or false -- `false` = échec, mis en cache pour ne pas réessayer en boucle
		storeCache[name] = store
		if not ok then
			warn("[LeaderboardService] OrderedDataStore indisponible (" .. name .. ") :", result)
		end
	end
	return store or nil
end

-- ===== API =====
local LeaderboardService = {}

local refreshListeners: { (payload: any) -> () } = {}

-- Permet à un autre système 100% serveur (ex. le podium 3D du Hub) de se resynchroniser dès
-- qu'un Refresh() a lieu, sans passer par le RemoteEvent client (inutile serveur → serveur).
function LeaderboardService.OnRefresh(callback: (payload: any) -> ())
	table.insert(refreshListeners, callback)
end

local function resolveName(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	if player then return player.Name end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	return (ok and name) or ("User" .. userId)
end

-- Regroupe les écritures : les récompenses d'action (kill, combo, palier de survie...) appellent
-- UpdateScore très fréquemment — sans ça, chaque petit gain de GP déclenchait un SetAsync
-- immédiat, ce qui remplit vite la file de requêtes DataStore avec plusieurs joueurs actifs
-- ("DataStore request was added to queue", repéré en test). Au lieu d'écrire à chaque appel, on
-- retient juste le score le PLUS RÉCENT par (board, période, joueur) et on écrit une seule fois
-- après UPDATE_DEBOUNCE secondes — les appels suivants pendant la fenêtre ne font que mettre à
-- jour la valeur en attente, sans programmer d'écriture supplémentaire.
local UPDATE_DEBOUNCE = 10 -- s
local pendingWrites: { [string]: { score: number } } = {}

-- Persiste le score d'un joueur pour un classement précis (appelé par DataService/RoundRunner).
function LeaderboardService.UpdateScore(boardId: string, period: string, userId: number, score: number)
	if score <= 0 then return end -- OrderedDataStore n'accepte que des valeurs >= 0, et un 0 n'a rien à faire dans un top N

	local key = boardId .. "|" .. period .. "|" .. userId
	local pending = pendingWrites[key]
	if pending then
		pending.score = score -- déjà une écriture programmée : juste rafraîchir la valeur qu'elle enverra
		return
	end

	pendingWrites[key] = { score = score }
	task.delay(UPDATE_DEBOUNCE, function()
		local latest = pendingWrites[key]
		pendingWrites[key] = nil
		if not latest then return end

		local store = getStore(boardId, period)
		if not store then return end
		task.spawn(function()
			pcall(function()
				store:SetAsync(tostring(userId), math.floor(latest.score))
			end)
		end)
	end)
end

-- Force l'écriture immédiate de toutes les valeurs en attente, sans attendre UPDATE_DEBOUNCE.
-- À appeler juste avant un Refresh() où la fraîcheur compte (ex. fin de round) — sans ça, les GP
-- de fin de round pourraient ne s'écrire qu'après le Refresh qui suit, et le classement affiché
-- resterait en retard jusqu'au prochain cycle automatique (90s). N'annule pas les écritures déjà
-- programmées via task.delay : elles se contentent de ne plus rien trouver à écrire (voir `if not
-- latest then return end` dans UpdateScore) quand leur tour arrive.
function LeaderboardService.Flush()
	for key, pending in pendingWrites do
		pendingWrites[key] = nil
		local boardId, period, userIdStr = key:match("^(.-)|(.-)|(.+)$")
		local userId = tonumber(userIdStr)
		if not (boardId and period and userId) then continue end

		local store = getStore(boardId, period)
		if not store then continue end
		task.spawn(function()
			pcall(function()
				store:SetAsync(tostring(userId), math.floor(pending.score))
			end)
		end)
	end
end

-- Récupère le top N résolu (noms) pour un board x période donné. Yields (appel DataStore).
function LeaderboardService.Fetch(boardId: string, period: string, count: number?): { any }
	local store = getStore(boardId, period)
	if not store then return {} end

	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, count or TOP_COUNT)
	end)
	if not ok or not pages then return {} end

	local entries = {}
	for rank, entry in pages:GetCurrentPage() do
		local userId = tonumber(entry.key)
		if userId then
			table.insert(entries, {
				rank   = rank,
				name   = resolveName(userId),
				score  = entry.value,
				userId = userId,
			})
		end
	end
	return entries
end

-- Récupère TOUS les boards x périodes, broadcast aux clients, et notifie les listeners serveur
-- (podium 3D). Un seul aller-retour DataStore par (board x période) — 6 au total actuellement.
function LeaderboardService.Refresh()
	task.spawn(function()
		local boards = {}
		for _, boardId in boardIds do
			boards[boardId] = {
				alltime = LeaderboardService.Fetch(boardId, "alltime"),
				weekly  = LeaderboardService.Fetch(boardId, "weekly"),
			}
		end

		local payload = { boards = boards, weekId = WeekId.Current() }
		lbEvent:FireAllClients(payload)
		for _, callback in refreshListeners do
			task.spawn(callback, payload)
		end
		print("[LeaderboardService] Rafraîchi —", #boardIds, "board(s) x 2 périodes")
	end)
end

-- ===== Cycle automatique =====
task.spawn(function()
	while true do
		task.wait(AUTO_REFRESH_INTERVAL)
		LeaderboardService.Refresh()
	end
end)

-- Refresh à chaque join (délai pour laisser DataService charger + UpdateScore)
Players.PlayerAdded:Connect(function()
	task.wait(5)
	LeaderboardService.Refresh()
end)

print("[LeaderboardService] démarré ✅")
return LeaderboardService
