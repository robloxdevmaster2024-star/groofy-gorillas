--!nonstrict
-- AchievementToast.client.luau — Pop-up de succès débloqué (bas-droit).

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

-- Charge le config pour résoudre id → { icon, name, desc }
local AchievementsConfig = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("AchievementsConfig")
)

local eventsFolder  = ReplicatedStorage:WaitForChild("AchievementEvents")
local unlockEvent   = eventsFolder:WaitForChild("Unlock")

-- ===== Index config par id =====
local DEFS = {}
for _, def in AchievementsConfig do
	DEFS[def.id] = def
end

-- ===== GUI =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "AchievementToastGui"
screenGui.ResetOnSpawn   = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent         = localPlayer.PlayerGui

-- Pile des toasts (max 3 simultanés, empilés de bas en haut)
local TOAST_W    = 300
local TOAST_H    = 80
local TOAST_GAP  = 10
local MARGIN_R   = 18
local MARGIN_B   = 90   -- au-dessus du bouton mobile Dodgeball éventuel
local ANIM_IN    = 0.35
local ANIM_OUT   = 0.5
local HOLD_TIME  = 4.0

local activeToasts: { Frame } = {}

local function removeToast(toast: Frame)
	for i, t in activeToasts do
		if t == toast then table.remove(activeToasts, i) break end
	end
	-- Reposition des toasts restants
	for j, t in activeToasts do
		local targetY = -(TOAST_H + TOAST_GAP) * j
		TweenService:Create(t, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
			Position = UDim2.new(1, -(TOAST_W + MARGIN_R), 1, -MARGIN_B + targetY),
		}):Play()
	end
end

local function spawnToast(def)
	-- Décale les toasts existants vers le haut
	for j, t in activeToasts do
		local targetY = -(TOAST_H + TOAST_GAP) * (j + 1)
		TweenService:Create(t, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
			Position = UDim2.new(1, -(TOAST_W + MARGIN_R), 1, -MARGIN_B + targetY),
		}):Play()
	end

	-- Crée le toast
	local toast = Instance.new("Frame", screenGui)
	toast.Size                   = UDim2.new(0, TOAST_W, 0, TOAST_H)
	toast.Position               = UDim2.new(1, MARGIN_R, 1, -MARGIN_B)  -- hors écran à droite
	toast.BackgroundColor3       = Color3.fromRGB(20, 18, 12)
	toast.BackgroundTransparency = 0.05
	toast.BorderSizePixel        = 0
	Instance.new("UICorner", toast).CornerRadius = UDim.new(0, 10)

	-- Barre gauche colorée
	local bar = Instance.new("Frame", toast)
	bar.Size             = UDim2.new(0, 4, 1, -16)
	bar.Position         = UDim2.new(0, 8, 0, 8)
	bar.BackgroundColor3 = Color3.fromRGB(255, 200, 30)
	bar.BorderSizePixel  = 0
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 2)

	-- Icône
	local iconLbl = Instance.new("TextLabel", toast)
	iconLbl.Size               = UDim2.new(0, 36, 0, 36)
	iconLbl.Position           = UDim2.new(0, 18, 0.5, -18)
	iconLbl.BackgroundTransparency = 1
	iconLbl.Font               = Enum.Font.GothamBold
	iconLbl.TextSize           = 24
	iconLbl.TextColor3         = Color3.fromRGB(255, 255, 255)
	iconLbl.Text               = def.icon or "🏅"

	-- Titre "SUCCÈS DÉBLOQUÉ"
	local headerLbl = Instance.new("TextLabel", toast)
	headerLbl.Size             = UDim2.new(1, -70, 0, 18)
	headerLbl.Position         = UDim2.new(0, 62, 0, 10)
	headerLbl.BackgroundTransparency = 1
	headerLbl.Font             = Enum.Font.GothamBold
	headerLbl.TextSize         = 11
	headerLbl.TextColor3       = Color3.fromRGB(255, 200, 30)
	headerLbl.TextXAlignment   = Enum.TextXAlignment.Left
	headerLbl.Text             = "✦ SUCCÈS DÉBLOQUÉ"

	-- Nom
	local nameLbl = Instance.new("TextLabel", toast)
	nameLbl.Size              = UDim2.new(1, -70, 0, 20)
	nameLbl.Position          = UDim2.new(0, 62, 0, 28)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font              = Enum.Font.GothamBold
	nameLbl.TextSize          = 15
	nameLbl.TextColor3        = Color3.fromRGB(240, 240, 245)
	nameLbl.TextXAlignment    = Enum.TextXAlignment.Left
	nameLbl.Text              = def.name or def.id

	-- Description
	local descLbl = Instance.new("TextLabel", toast)
	descLbl.Size              = UDim2.new(1, -70, 0, 16)
	descLbl.Position          = UDim2.new(0, 62, 0, 50)
	descLbl.BackgroundTransparency = 1
	descLbl.Font              = Enum.Font.Gotham
	descLbl.TextSize          = 11
	descLbl.TextColor3        = Color3.fromRGB(160, 160, 170)
	descLbl.TextXAlignment    = Enum.TextXAlignment.Left
	descLbl.Text              = def.desc or ""

	table.insert(activeToasts, 1, toast)

	-- Animation entrée (slide depuis la droite)
	local targetPos = UDim2.new(1, -(TOAST_W + MARGIN_R), 1, -MARGIN_B - (TOAST_H + TOAST_GAP))
	TweenService:Create(toast, TweenInfo.new(ANIM_IN, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = targetPos,
	}):Play()

	-- Sortie après délai
	task.delay(HOLD_TIME, function()
		if not toast.Parent then return end
		local exitTween = TweenService:Create(toast, TweenInfo.new(ANIM_OUT, Enum.EasingStyle.Quad), {
			Position = UDim2.new(1, MARGIN_R, 1, targetPos.Y.Offset),
			BackgroundTransparency = 1,
		})
		exitTween.Completed:Connect(function()
			removeToast(toast)
			toast:Destroy()
		end)
		exitTween:Play()
	end)
end

-- ===== Réception =====
unlockEvent.OnClientEvent:Connect(function(achievementId: string)
	local def = DEFS[achievementId]
	if not def then
		def = { id = achievementId, icon = "🏅", name = achievementId, desc = "" }
	end
	spawnToast(def)
end)
