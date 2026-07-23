--!nonstrict
-- ClownSurvivalBhop.client.luau — Bunny hop (tout le monde, comme le sprint) pendant le round
-- Clown Survival. Envoie un signal serveur à chaque VRAI ré-appui de la touche de saut (front
-- montant), PAS à chaque frame où elle est maintenue : Roby fait sauter automatiquement le
-- personnage tant qu'on garde Espace enfoncé dès qu'il retouche le sol, donc se fier à l'état du
-- personnage laisserait bhop-per en boucle sans aucun timing. Toute la logique de fenêtre/bonus/
-- plafond est arbitrée côté serveur (voir ClownSurvival.luau) — ce script ne fait qu'envoyer
-- l'intention.
--
-- Limite connue : sur mobile, le bouton de saut est celui par défaut de Roblox (CoreGui), qu'on ne
-- peut pas intercepter proprement en front montant sans le remplacer entièrement — cette
-- protection anti-"maintenir pour spam" ne s'applique donc pour l'instant qu'au clavier PC.

local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local eventsFolder         = ReplicatedStorage:WaitForChild("ClownSurvivalEvents")
local sprintAvailableEvent = eventsFolder:WaitForChild("SprintAvailable") -- réutilisé : même fenêtre que le sprint
local bhopJumpEvent        = eventsFolder:WaitForChild("BhopJumpPressed")

local inputConn: RBXScriptConnection? = nil

local function activate()
	if inputConn then return end
	inputConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.Space then
			bhopJumpEvent:FireServer()
		end
	end)
end

local function deactivate()
	if inputConn then
		inputConn:Disconnect()
		inputConn = nil
	end
end

sprintAvailableEvent.OnClientEvent:Connect(function(active: boolean)
	if active then
		activate()
	else
		deactivate()
	end
end)
