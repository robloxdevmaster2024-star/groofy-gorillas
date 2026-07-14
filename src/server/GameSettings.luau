--!nonstrict
-- GameSettings.luau — Surcharge des DefaultSettings par le host avant chaque round.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ===== RemoteEvents (créés au chargement) =====
local eventsFolder = ReplicatedStorage:FindFirstChild("GameSettingsEvents")
if not eventsFolder then
	eventsFolder = Instance.new("Folder")
	eventsFolder.Name = "GameSettingsEvents"
	eventsFolder.Parent = ReplicatedStorage
end
local function getOrCreate(parent, name)
	return parent:FindFirstChild(name) or Instance.new("RemoteEvent", parent)
end
local stateEvent  = getOrCreate(eventsFolder, "State");  stateEvent.Name  = "State"
local updateEvent = getOrCreate(eventsFolder, "Update"); updateEvent.Name = "Update"

-- ===== État =====
local GameSettings = {}

local overrides : { [string]: { [string]: any } } = {}  -- par nom de gamemode
local currentGamemode = nil  -- gamemode en cours d'édition (pendant l'intermission)
local hostPlayer: Player? = nil

-- ===== Host = premier joueur (par ordre d'arrivée) =====
local function refreshHost()
	local players = Players:GetPlayers()
	hostPlayer = players[1] or nil
end

Players.PlayerAdded:Connect(refreshHost)
Players.PlayerRemoving:Connect(function()
	task.defer(function()
		refreshHost()
		-- Si le panel est ouvert, re-diffuse avec le nouveau host
		if currentGamemode then
			GameSettings._broadcast()
		end
	end)
end)

-- ===== API publique =====

-- Retourne les settings du gamemode avec les overrides appliqués.
function GameSettings.GetSettings(gamemodeName: string, defaultSettings: { [string]: any })
	local result = {}
	for k, v in defaultSettings do result[k] = v end
	local ovr = overrides[gamemodeName]
	if ovr then
		for k, v in ovr do result[k] = v end
	end
	return result
end

-- Ouvre le panneau en début d'intermission.
function GameSettings.OpenPanel(gamemode)
	currentGamemode = gamemode
	GameSettings._broadcast()
end

-- Ferme le panneau (début du round).
function GameSettings.ClosePanel()
	currentGamemode = nil
	stateEvent:FireAllClients({ open = false })
end

-- ===== Interne =====
function GameSettings._broadcast()
	if not currentGamemode then return end
	local settings = GameSettings.GetSettings(currentGamemode.Name, currentGamemode.DefaultSettings)
	stateEvent:FireAllClients({
		open         = true,
		gamemodeName = currentGamemode.Name,
		schema       = currentGamemode.SettingsSchema or {},
		settings     = settings,
		hostId       = hostPlayer and hostPlayer.UserId or 0,
	})
end

-- Écoute les modifications du host
updateEvent.OnServerEvent:Connect(function(player, key, delta)
	if player ~= hostPlayer then return end
	if not currentGamemode then return end

	local schema = currentGamemode.SettingsSchema
	if not schema then return end

	-- Cherche l'entrée correspondante dans le schéma
	local entry
	for _, e in schema do
		if e.key == key then entry = e break end
	end
	if not entry then return end

	-- Lit la valeur actuelle (override ou défaut)
	if not overrides[currentGamemode.Name] then
		overrides[currentGamemode.Name] = {}
	end
	local current = overrides[currentGamemode.Name][key]
	if current == nil then current = currentGamemode.DefaultSettings[key] end
	current = current + delta

	-- Clamp + arrondi step
	current = math.clamp(current, entry.min, entry.max)
	if entry.step and entry.step > 0 then
		current = math.round(current / entry.step) * entry.step
		-- Correction flottant (ex: 0.30000000001)
		local precision = math.ceil(-math.log10(entry.step))
		if precision > 0 then
			current = math.floor(current * 10^precision + 0.5) / 10^precision
		end
	end

	overrides[currentGamemode.Name][key] = current
	GameSettings._broadcast()
end)

return GameSettings
