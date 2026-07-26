--!nonstrict
-- ClownSurvivalStatusScreen.client.luau — Écran plein cadre façon "WASTED" (GTA) affiché au
-- joueur LOCAL quand il vient d'être infecté ou éliminé : fondu vers le noir + désaturation de
-- l'écran + gros texte qui apparaît en se resserrant (zoom-out), puis tout disparaît après ~2-3s.
-- Purement cosmétique/local (ColorCorrectionEffect + overlay créés par ce LocalScript, comme le
-- flou d'épuisement de ClownSurvivalSprint.client.luau) : personne d'autre ne le voit.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Lighting          = game:GetService("Lighting")

local player = Players.LocalPlayer

local eventsFolder      = ReplicatedStorage:WaitForChild("ClownSurvivalEvents")
local statusScreenEvent = eventsFolder:WaitForChild("StatusScreen")

local VARIANTS = {
	infected = {
		text  = "INFECTÉ",
		color = Color3.fromRGB(255, 110, 30),
	},
	eliminated = {
		text  = "ÉLIMINÉ",
		color = Color3.fromRGB(210, 40, 40),
	},
}

local HOLD_DURATION = 2.2 -- s avant le fondu de sortie
local FADE_OUT_DURATION = 0.7

-- ===== Construction =====
local gui = Instance.new("ScreenGui")
gui.Name = "ClownSurvivalStatusScreen"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50 -- au-dessus du reste du HUD
gui.Parent = player:WaitForChild("PlayerGui")

local overlay = Instance.new("Frame")
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel = 0
overlay.ZIndex = 1
overlay.Parent = gui

local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0.5, 0.5)
label.Position = UDim2.new(0.5, 0, 0.5, 0)
label.Size = UDim2.new(0, 800, 0, 120)
label.BackgroundTransparency = 1
label.Font = Enum.Font.FredokaOne
label.TextSize = 72 -- taille fixe (pas TextScaled) : le texte change selon la variante mais ne
                    -- doit pas changer de taille pour autant
label.TextColor3 = Color3.new(1, 1, 1)
label.TextStrokeTransparency = 0.3
label.TextStrokeColor3 = Color3.new(0, 0, 0)
label.TextTransparency = 1
label.Text = ""
label.ZIndex = 2
label.Parent = gui

-- Désaturation façon GTA : créé une fois, réutilisé à chaque déclenchement.
local colorCorrection = Instance.new("ColorCorrectionEffect")
colorCorrection.Name = "ClownSurvivalStatusScreenCC"
colorCorrection.Saturation = 0
colorCorrection.Parent = Lighting

local activeToken = 0

local function play(variant: string)
	local def = VARIANTS[variant]
	if not def then return end

	activeToken += 1
	local myToken = activeToken

	label.Text = def.text
	label.TextColor3 = def.color
	label.TextTransparency = 1
	label.Size = UDim2.new(0, 950, 0, 140) -- part plus grand, se resserre à l'entrée (zoom-out)
	overlay.BackgroundTransparency = 1
	colorCorrection.Saturation = 0

	TweenService:Create(overlay, TweenInfo.new(0.35, Enum.EasingStyle.Quad), {
		BackgroundTransparency = 0.45,
	}):Play()
	TweenService:Create(colorCorrection, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
		Saturation = -1,
	}):Play()
	TweenService:Create(label, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		TextTransparency = 0,
		Size = UDim2.new(0, 800, 0, 120),
	}):Play()

	task.delay(HOLD_DURATION, function()
		if myToken ~= activeToken then return end -- un nouveau déclenchement a pris le relais
		TweenService:Create(overlay, TweenInfo.new(FADE_OUT_DURATION), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(colorCorrection, TweenInfo.new(FADE_OUT_DURATION), { Saturation = 0 }):Play()
		TweenService:Create(label, TweenInfo.new(FADE_OUT_DURATION), { TextTransparency = 1 }):Play()
	end)
end

statusScreenEvent.OnClientEvent:Connect(function(variant)
	if typeof(variant) ~= "string" then return end
	play(variant)
end)
