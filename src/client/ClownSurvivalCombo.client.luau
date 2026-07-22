--!nonstrict
-- ClownSurvivalCombo.client.luau — Compteur de combo affiché au clown qui enchaîne les coups.
-- But : boucle de récompense visuelle qui monte en flèche (couleur + taille) pour donner envie
-- de re-frapper vite. Le compteur (et son reset après COMBO_RESET_WINDOW sans coup) est calculé
-- côté serveur — ce script ne fait qu'afficher/animer la valeur reçue.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local eventsFolder    = ReplicatedStorage:WaitForChild("ClownSurvivalEvents")
local comboUpdateEvent = eventsFolder:WaitForChild("ComboUpdate")

local FADE_DELAY = 1.6 -- s sans nouveau coup avant que le texte s'efface

local gui = Instance.new("ScreenGui")
gui.Name = "ClownSurvivalComboUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.Parent = playerGui

local label = Instance.new("TextLabel")
label.Name = "ComboLabel"
label.AnchorPoint = Vector2.new(0.5, 0)
label.Position = UDim2.new(0.5, 0, 0.16, 0)
label.Size = UDim2.new(0, 260, 0, 60)
label.BackgroundTransparency = 1
label.Font = Enum.Font.FredokaOne
label.TextScaled = true
label.TextStrokeTransparency = 0.3
label.TextStrokeColor3 = Color3.fromRGB(30, 15, 40)
label.Text = ""
label.Parent = gui

-- Couleur + échelle qui montent avec le combo (palette qui "chauffe" : blanc → jaune → orange → rouge).
local function colorForCombo(n: number): Color3
	if n >= 8 then return Color3.fromRGB(255, 60, 60) end
	if n >= 5 then return Color3.fromRGB(255, 140, 40) end
	if n >= 3 then return Color3.fromRGB(255, 220, 60) end
	return Color3.fromRGB(255, 255, 255)
end

local fadeToken = 0

local function onCombo(count: number)
	if typeof(count) ~= "number" then return end

	gui.Enabled = true
	label.TextColor3 = colorForCombo(count)
	label.Text = (count > 1) and ("COMBO x" .. count .. " !") or "TOUCHÉ !"

	-- "Pop" : légère surtaille qui grossit avec le combo, puis retour à la normale.
	local punchScale = 1 + math.min(count, 10) * 0.03
	label.Size = UDim2.new(0, 260 * punchScale * 1.15, 0, 60 * punchScale * 1.15)
	TweenService:Create(
		label,
		TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, 260 * punchScale, 0, 60 * punchScale) }
	):Play()

	fadeToken += 1
	local myToken = fadeToken
	task.delay(FADE_DELAY, function()
		if myToken == fadeToken then
			gui.Enabled = false
		end
	end)
end

comboUpdateEvent.OnClientEvent:Connect(onCombo)
