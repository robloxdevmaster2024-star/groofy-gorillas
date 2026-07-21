--!nonstrict
-- DataService.luau — Persistance joueur : Goofy Points, niveaux, cosmétiques.
-- API : GetProfile(player), AddGoofyPoints(player, n), GetLevel(player)

local Players        = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerConfig = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("PlayerConfig")
)

-- ===== Config =====

local STORE_KEY    = "GoofyGorillas_v1"
local SAVE_INTERVAL = 60  -- auto-save toutes les N secondes

local TEMPLATE = {
	goofyPoints    = 0,
	level          = 1,
	ownedCosmetics = {},
	equipped       = {},
	achievements   = {},
	bestTimes      = {},
}

-- ===== Init DataStore =====

local store
do
	local ok, err = pcall(function()
		store = DataStoreService:GetDataStore(STORE_KEY)
	end)
	if not ok then
		warn("[DataService] DataStore indisponible (mode offline ?) :", err)
	end
end

-- RemoteEvent : le serveur notifie les clients de leurs données
local DataUpdated = Instance.new("RemoteEvent")
DataUpdated.Name  = "DataUpdated"
DataUpdated.Parent = ReplicatedStorage

-- ===== Helpers =====

local profiles   = {}   -- [userId] → data table
local saveLocks  = {}   -- [userId] → bool (évite les saves concurrentes)

local function deepCopy(t)
	local copy = {}
	for k, v in t do
		copy[k] = type(v) == "table" and deepCopy(v) or v
	end
	return copy
end

local function reconcile(data, template)
	for k, v in template do
		if data[k] == nil then
			data[k] = type(v) == "table" and deepCopy(v) or v
		elseif type(v) == "table" and type(data[k]) == "table" then
			reconcile(data[k], v)
		end
	end
end

local function computeLevel(points)
	for lvl = PlayerConfig.MAX_LEVEL, 1, -1 do
		if PlayerConfig.LEVEL_THRESHOLDS[lvl] and points >= PlayerConfig.LEVEL_THRESHOLDS[lvl] then
			return lvl
		end
	end
	return 1
end

-- ===== DataStore I/O =====

local function loadData(userId)
	if not store then return deepCopy(TEMPLATE) end
	local key = "u_" .. userId
	local data
	for attempt = 1, 3 do
		local ok, result = pcall(function() return store:GetAsync(key) end)
		if ok then
			data = result
			break
		end
		warn("[DataService] GetAsync tentative", attempt, "échouée :", result)
		task.wait(2)
	end
	if type(data) ~= "table" then data = deepCopy(TEMPLATE) end
	reconcile(data, TEMPLATE)
	return data
end

local function saveData(userId, data)
	if not store or saveLocks[userId] then return end
	saveLocks[userId] = true
	local key = "u_" .. userId
	for attempt = 1, 3 do
		local ok, err = pcall(function() store:SetAsync(key, data) end)
		if ok then break end
		if attempt == 3 then
			warn("[DataService] Échec sauvegarde userId", userId, ":", err)
		end
		task.wait(2)
	end
	saveLocks[userId] = false
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
	return profiles[player.UserId]
end

function DataService.GetLevel(player)
	local d = profiles[player.UserId]
	return d and d.level or 1
end

function DataService.GetNextThreshold(player)
	local d = profiles[player.UserId]
	if not d then return nil end
	return PlayerConfig.LEVEL_THRESHOLDS[d.level + 1]
end

function DataService.AddGoofyPoints(player, amount)
	local data = profiles[player.UserId]
	if not data then return end

	data.goofyPoints = math.max(0, data.goofyPoints + amount)

	local newLevel  = computeLevel(data.goofyPoints)
	local leveledUp = newLevel > data.level
	data.level      = newLevel

	syncLeaderstats(player, data)

	DataUpdated:FireClient(player, {
		goofyPoints    = data.goofyPoints,
		level          = data.level,
		leveledUp      = leveledUp,
	})
end

-- ===== Cycle de vie des joueurs =====

local function onPlayerAdded(player)
	local data = loadData(player.UserId)
	profiles[player.UserId] = data
	syncLeaderstats(player, data)
	DataUpdated:FireClient(player, {
		goofyPoints = data.goofyPoints,
		level       = data.level,
		leveledUp   = false,
	})
	print("[DataService]", player.Name, "chargé — Lvl", data.level, "| GP", data.goofyPoints)
end

local function onPlayerRemoving(player)
	local data = profiles[player.UserId]
	if data then
		saveData(player.UserId, data)
		profiles[player.UserId] = nil
	end
	saveLocks[player.UserId] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Rattraper les joueurs déjà là (test Studio en solo)
for _, p in Players:GetPlayers() do
	task.spawn(onPlayerAdded, p)
end

-- Auto-save périodique
task.spawn(function()
	while true do
		task.wait(SAVE_INTERVAL)
		for userId, data in profiles do
			local p = Players:GetPlayerByUserId(userId)
			if p then task.spawn(saveData, userId, data) end
		end
	end
end)

-- Sauvegarde forcée à la fermeture du serveur
game:BindToClose(function()
	for userId, data in profiles do
		saveData(userId, data)
	end
end)

print("[DataService] démarré ✅")
return DataService
