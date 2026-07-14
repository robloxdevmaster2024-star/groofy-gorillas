--!nonstrict
-- RoundManager.server.luau — Point d'entrée serveur.
-- Crée GameStatus puis délègue tout à LobbyService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
	require(GamemodesFolder.Infector),
	require(GamemodesFolder.Dodgeball),
}

-- Lance le lobby
require(script.Parent.LobbyService).Start(AVAILABLE_GAMEMODES)
