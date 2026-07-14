--!nonstrict
-- PlayerStats.client.luau — Panneau niveau + Goofy Points + barre de progression.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local DataUpdated  = ReplicatedStorage:WaitForChild("DataUpdated")
local PlayerConfig = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("PlayerConfig")
)
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

-- ===== Construction de l'UI =====

local gui = Instance.new("ScreenGui")
gui.Name         = "GoofyStats"
gui.ResetOnSpawn = false
gui.Parent       = playerGui

-- Conteneur principal (bas gauche)
local panel = Instance.new("Frame")
panel.Name              = "StatsPanel"
panel.AnchorPoint       = Vector2.new(0, 1)
panel.Position          = UDim2.new(0, 16, 1, -16)
panel.Size              = UDim2.new(0, 210, 0, 72)
panel.BackgroundColor3  = Color3.fromRGB(25, 25, 30)
panel.BackgroundTransparency = 0.2
panel.Parent            = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
Instance.new("UIPadding", panel).PaddingLeft = UDim.new(0, 12)

-- Badge de niveau
local lvlLabel = Instance.new("TextLabel")
lvlLabel.Name          = "Level"
lvlLabel.AnchorPoint   = Vector2.new(0, 0)
lvlLabel.Position      = UDim2.new(0, 0, 0, 8)
lvlLabel.Size          = UDim2.new(1, -12, 0, 26)
lvlLabel.BackgroundTransparency = 1
lvlLabel.TextColor3    = Color3.fromRGB(255, 220, 80)
lvlLabel.TextXAlignment = Enum.TextXAlignment.Left
lvlLabel.TextScaled    = true
lvlLabel.Font          = Enum.Font.FredokaOne
lvlLabel.Text          = "Niv. 1"
lvlLabel.Parent        = panel

-- Points
local gpLabel = Instance.new("TextLabel")
gpLabel.Name           = "GP"
gpLabel.AnchorPoint    = Vector2.new(0, 0)
gpLabel.Position       = UDim2.new(0, 0, 0, 34)
gpLabel.Size           = UDim2.new(1, -12, 0, 18)
gpLabel.BackgroundTransparency = 1
gpLabel.TextColor3     = Color3.fromRGB(200, 200, 220)
gpLabel.TextXAlignment = Enum.TextXAlignment.Left
gpLabel.TextScaled     = true
gpLabel.Font           = Enum.Font.FredokaOne
gpLabel.Text           = "0 GP"
gpLabel.Parent         = panel

-- Fond de la barre de progression
local barBg = Instance.new("Frame")
barBg.Name             = "BarBg"
barBg.AnchorPoint      = Vector2.new(0, 1)
barBg.Position         = UDim2.new(0, 0, 1, -8)
barBg.Size             = UDim2.new(1, -12, 0, 8)
barBg.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
barBg.Parent           = panel
Instance.new("UICorner", barBg).CornerRadius = UDim.new(1, 0)

-- Remplissage de la barre
local barFill = Instance.new("Frame")
barFill.Name             = "BarFill"
barFill.Size             = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(120, 220, 100)
barFill.Parent           = barBg
Instance.new("UICorner", barFill).CornerRadius = UDim.new(1, 0)

-- Panneau de level-up (centre écran, caché par défaut)
local levelUpBanner = Instance.new("TextLabel")
levelUpBanner.Name          = "LevelUp"
levelUpBanner.AnchorPoint   = Vector2.new(0.5, 0.5)
levelUpBanner.Position      = UDim2.new(0.5, 0, 0.35, 0)
levelUpBanner.Size          = UDim2.new(0, 340, 0, 60)
levelUpBanner.BackgroundColor3 = Color3.fromRGB(255, 200, 40)
levelUpBanner.BackgroundTransparency = 0.1
levelUpBanner.TextColor3    = Color3.fromRGB(30, 20, 0)
levelUpBanner.TextScaled    = true
levelUpBanner.Font          = Enum.Font.FredokaOne
levelUpBanner.Text          = ""
levelUpBanner.Visible       = false
levelUpBanner.Parent        = gui
Instance.new("UICorner", levelUpBanner).CornerRadius = UDim.new(0, 16)

-- ===== Logique =====

local function getProgress(gp, level)
	local lo = PlayerConfig.LEVEL_THRESHOLDS[level]     or 0
	local hi = PlayerConfig.LEVEL_THRESHOLDS[level + 1] or lo + 1
	if hi <= lo then return 1 end  -- niveau max
	return math.clamp((gp - lo) / (hi - lo), 0, 1)
end

local levelUpToken = 0

local function onDataUpdated(payload)
	if type(payload) ~= "table" then return end

	local gp    = payload.goofyPoints or 0
	local level = payload.level or 1

	lvlLabel.Text = "Niv. " .. level
	gpLabel.Text  = gp .. " GP"

	-- Anime la barre de progression
	local progress = getProgress(gp, level)
	TweenService:Create(barFill, TweenInfo.new(0.6, Enum.EasingStyle.Quad), {
		Size = UDim2.new(progress, 0, 1, 0)
	}):Play()

	-- Notification de montée de niveau
	if payload.leveledUp then
		levelUpToken += 1
		local myToken = levelUpToken
		levelUpBanner.Text    = "⬆ NIVEAU " .. level .. " atteint !"
		levelUpBanner.Visible = true
		levelUpBanner.BackgroundTransparency = 0.1

		-- Fade out après 3s
		task.delay(3, function()
			if myToken ~= levelUpToken then return end
			TweenService:Create(levelUpBanner, TweenInfo.new(0.8), {
				BackgroundTransparency = 1,
				TextTransparency       = 1,
			}):Play()
			task.delay(0.9, function()
				if myToken == levelUpToken then
					levelUpBanner.Visible = false
					levelUpBanner.BackgroundTransparency = 0.1
					levelUpBanner.TextTransparency       = 0
				end
			end)
		end)
	end
end

DataUpdated.OnClientEvent:Connect(onDataUpdated)
