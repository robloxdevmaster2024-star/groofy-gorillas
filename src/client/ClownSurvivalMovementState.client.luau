--!nonstrict
-- ClownSurvivalMovementState.client.luau — Machine à états de déplacement (idle/run/slide/prone/
-- air/dash) pendant le round Clown Survival.
--
-- Le serveur reste seul juge (calcul + validation anti speed-hack, voir getMovementState et
-- STATE_MAX_SPEED dans ClownSurvival.luau) : ce script ne fait qu'afficher/exposer l'état
-- CONFIRMÉ (MovementStateChanged), pour des transitions propres côté client plutôt que de
-- deviner l'état localement à partir de plusieurs scripts indépendants (sprint/glissade/couché).
--
-- Expose `_G.ClownSurvivalMovementState` (état courant, en lecture) pour que d'éventuels futurs
-- scripts (animations, HUD) puissent s'y accrocher sans devoir réécouter l'event eux-mêmes.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local eventsFolder        = ReplicatedStorage:WaitForChild("ClownSurvivalEvents")
local movementStateEvent  = eventsFolder:WaitForChild("MovementStateChanged")
local sprintAvailableEvent = eventsFolder:WaitForChild("SprintAvailable") -- dispo pendant tout round Clown Survival

_G.ClownSurvivalMovementState = "idle"

-- Petit indicateur de debug (coin haut-gauche, discret) pour visualiser les transitions d'état
-- en jeu. Purement indicatif ; à retirer facilement (ce bloc UI) si non désiré en prod.
local gui = Instance.new("ScreenGui")
gui.Name = "ClownSurvivalMovementStateDebug"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0, 0)
label.Position = UDim2.new(0, 12, 0, 12)
label.Size = UDim2.new(0, 130, 0, 26)
label.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
label.BackgroundTransparency = 0.35
label.TextColor3 = Color3.fromRGB(230, 230, 235)
label.Font = Enum.Font.GothamBold
label.TextScaled = true
label.Text = "idle"
label.Parent = gui
Instance.new("UICorner", label).CornerRadius = UDim.new(0, 6)

movementStateEvent.OnClientEvent:Connect(function(state: string)
	if typeof(state) ~= "string" then return end
	if state == _G.ClownSurvivalMovementState then return end
	_G.ClownSurvivalMovementState = state
	label.Text = state
end)

sprintAvailableEvent.OnClientEvent:Connect(function(active: boolean)
	gui.Enabled = active
end)
