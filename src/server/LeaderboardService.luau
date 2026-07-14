--!nonstrict
-- LeaderboardService.luau — Classement global Goofy Points (OrderedDataStore).

local Players          = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TOP_COUNT            = 10
local AUTO_REFRESH_INTERVAL = 90  -- secondes (+ refresh manuel après chaque round)

-- ===== OrderedDataStore =====
local lbStore
do
	local ok, err = pcall(function()
		lbStore = DataStoreService:GetOrderedDataStore("GoofyPoints_Global_v1")
	end)
	if not ok then
		warn("[LeaderboardService] OrderedDataStore indisponible :", err)
	end
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

-- ===== API =====
local LeaderboardService = {}

local function resolveName(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	if player then return player.Name end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	return (ok and name) or ("User" .. userId)
end

-- Persiste le score d'un joueur dans le classement (appelé par DataService).
function LeaderboardService.UpdateScore(userId: number, points: number)
	if not lbStore or points <= 0 then return end
	task.spawn(function()
		pcall(function()
			lbStore:SetAsync(tostring(userId), math.floor(points))
		end)
	end)
end

-- Récupère le top N, résout les noms, et broadcast à tous les clients.
function LeaderboardService.Refresh()
	if not lbStore then return end
	task.spawn(function()
		local ok, pages = pcall(function()
			return lbStore:GetSortedAsync(false, TOP_COUNT)
		end)
		if not ok or not pages then return end

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

		lbEvent:FireAllClients({ entries = entries })
		print("[LeaderboardService] Rafraîchi —", #entries, "entrée(s)")
	end)
end

-- ===== Cycle automatique =====
task.spawn(function()
	while true do
		task.wait(AUTO_REFRESH_INTERVAL)
		LeaderboardService.Refresh()
	end
end)

-- Refresh à chaque join (délai pour laisser DataService charger + updateScore)
Players.PlayerAdded:Connect(function()
	task.wait(5)
	LeaderboardService.Refresh()
end)

print("[LeaderboardService] démarré ✅")
return LeaderboardService
