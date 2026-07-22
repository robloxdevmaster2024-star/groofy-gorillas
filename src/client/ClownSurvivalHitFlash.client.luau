--!nonstrict
-- ClownSurvivalHitFlash.client.luau — Réaction "je viens d'être touché" à l'écran de la victime :
-- flash blanc bref + lignes de vitesse façon manga qui jaillissent du centre de l'écran.
-- Purement subjectif (visible seulement par la victime) — l'effet visible par tout le monde
-- (particules, étoiles, 💥) est géré côté serveur dans ClownSurvival.luau.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local eventsFolder  = ReplicatedStorage:WaitForChild("ClownSurvivalEvents")
local hitFlashEvent = eventsFolder:WaitForChild("HitFlash")

local gui = Instance.new("ScreenGui")
gui.Name = "ClownSurvivalHitFlashUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50 -- au-dessus du reste du HUD
gui.Parent = playerGui

-- Flash blanc plein écran
local flash = Instance.new("Frame")
flash.Name = "Flash"
flash.Size = UDim2.new(1, 0, 1, 0)
flash.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
flash.BackgroundTransparency = 1
flash.ZIndex = 2
flash.Parent = gui

-- Lignes de vitesse radiales (façon impact manga) : de fines barres qui partent du centre.
local LINE_COUNT = 14
local lines = {}
for i = 1, LINE_COUNT do
	local line = Instance.new("Frame")
	line.Name = "SpeedLine"
	line.AnchorPoint = Vector2.new(0.5, 0)
	line.Position = UDim2.new(0.5, 0, 0.5, 0)
	line.Size = UDim2.new(0, 4, 0, 0)
	line.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	line.BackgroundTransparency = 1
	line.BorderSizePixel = 0
	line.Rotation = (360 / LINE_COUNT) * i
	line.ZIndex = 1
	line.Parent = gui
	table.insert(lines, line)
end

local playing = false

local function playHitFlash()
	if playing then return end
	playing = true

	-- Flash : pop quasi instantané puis fondu.
	flash.BackgroundTransparency = 0.15
	TweenService:Create(flash, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
	}):Play()

	-- Lignes : jaillissent vers l'extérieur en s'étirant puis s'effacent.
	for _, line in lines do
		line.Size = UDim2.new(0, 4, 0, 0)
		line.BackgroundTransparency = 0.1
		TweenService:Create(line, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, 4, 0, math.random(220, 340)),
		}):Play()
		TweenService:Create(line, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
		}):Play()
	end

	task.delay(0.32, function()
		playing = false
	end)
end

hitFlashEvent.OnClientEvent:Connect(playHitFlash)
