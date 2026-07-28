--!nonstrict
-- ClownSurvivalRedStain.client.luau — "Red stain" façon Dead by Daylight (Clown Survival).
--
-- Deux rôles dans ce seul script :
--  1) Tant que CE joueur est clown (voir "SetActive"), envoie régulièrement la direction de SA
--     caméra au serveur (ClownGaze) pour orienter la lueur rouge projetée devant lui — c'est le
--     serveur qui possède/oriente réellement la Part+SpotLight (voir ClownSurvival.luau), ce
--     script ne fait qu'alimenter la direction.
--  2) Masque localement le "ClownRedStain" qui apparaît sur SON PROPRE personnage : le clown ne
--     doit pas voir son propre indice (repéré par les enfants, pas par lui) — un simple
--     `light.Enabled = false` en local n'affecte que ce qu'affiche ce client, jamais les autres.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local eventsFolder   = ReplicatedStorage:WaitForChild("ClownSurvivalEvents")
local setActiveEvent = eventsFolder:WaitForChild("SetActive")
local clownGazeEvent = eventsFolder:WaitForChild("ClownGaze")

local GAZE_SEND_INTERVAL = 0.1 -- s (10 Hz, largement sous le plafond 20 Hz du serveur)

local isActive = false
local gazeThread: thread? = nil

local function startGazeLoop()
	gazeThread = task.spawn(function()
		while isActive do
			clownGazeEvent:FireServer(camera.CFrame.LookVector)
			task.wait(GAZE_SEND_INTERVAL)
		end
	end)
end

local function stopGazeLoop()
	if gazeThread then
		task.cancel(gazeThread)
		gazeThread = nil
	end
end

setActiveEvent.OnClientEvent:Connect(function(active: boolean)
	isActive = active
	if active then
		startGazeLoop()
	else
		stopGazeLoop()
	end
end)

-- ===== Masquage local du "ClownRedStain" sur son propre personnage =====
local function hideIfRedStain(inst: Instance)
	if inst.Name ~= "ClownRedStain" then return end
	local light = inst:FindFirstChildOfClass("SpotLight")
	if light then light.Enabled = false end
end

local function watchOwnCharacter(char: Model)
	for _, child in char:GetChildren() do
		hideIfRedStain(child)
	end
	char.ChildAdded:Connect(hideIfRedStain)
end

if player.Character then watchOwnCharacter(player.Character) end
player.CharacterAdded:Connect(watchOwnCharacter)
