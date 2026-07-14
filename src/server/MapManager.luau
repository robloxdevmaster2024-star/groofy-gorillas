--!nonstrict
-- MapManager.luau — Chargement/déchargement des venues par round.
--
-- Convention maps (créées dans Studio sous ServerStorage.Venues) :
--   Model "MonNom"/
--     SpawnPoints/   ← Folder contenant des BaseParts (positions de spawn)
--     ... géométrie ...
--
-- Si aucune venue n'existe, les joueurs spawn sur une grille circulaire (baseplate).

local ServerStorage = game:GetService("ServerStorage")
local Workspace     = game:GetService("Workspace")

local MapManager = {}

-- Grille circulaire de secours (baseplate sans map)
local function defaultSpawnCFrames(count)
	local spawns = {}
	local n = math.max(count, 8)
	for i = 0, n - 1 do
		local angle = (i / n) * math.pi * 2
		table.insert(spawns, CFrame.new(math.cos(angle) * 24, 5, math.sin(angle) * 24))
	end
	return spawns
end

-- Lit le dossier SpawnPoints d'une map et retourne la liste de CFrames (au-dessus des parts)
local function extractSpawnCFrames(mapInstance)
	local folder = mapInstance and mapInstance:FindFirstChild("SpawnPoints")
	if not folder then return {} end
	local result = {}
	for _, part in folder:GetChildren() do
		if part:IsA("BasePart") then
			table.insert(result, part.CFrame + Vector3.new(0, 4, 0))
		end
	end
	return result
end

-- Mélange en place (Fisher-Yates)
local function shuffle(t)
	for i = #t, 2, -1 do
		local j = math.random(1, i)
		t[i], t[j] = t[j], t[i]
	end
	return t
end

-- Charge une venue aléatoire dans le Workspace.
-- Retourne (mapInstance ou nil, spawnCFrames mélangés)
function MapManager.LoadRandom(playerCount)
	local venuesFolder = ServerStorage:FindFirstChild("Venues")
	local venues       = venuesFolder and venuesFolder:GetChildren() or {}

	local map
	local spawnCFrames = {}

	if #venues > 0 then
		local template = venues[math.random(1, #venues)]
		map            = template:Clone()
		map.Name       = "_ActiveVenue"
		map.Parent     = Workspace
		spawnCFrames   = extractSpawnCFrames(map)
		print("[MapManager] Venue chargée :", template.Name)
	end

	if #spawnCFrames == 0 then
		spawnCFrames = defaultSpawnCFrames(playerCount or 8)
	end

	return map, shuffle(spawnCFrames)
end

-- Détruit la venue active.
function MapManager.Unload(map)
	if map and map.Parent then
		map:Destroy()
		print("[MapManager] Venue déchargée.")
	end
end

return MapManager
