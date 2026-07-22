--!nonstrict
-- LobbyHud.client.luau — Indicateur de zone et file d'attente (lobby).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer

local lobbyFolder      = ReplicatedStorage:WaitForChild("LobbyEvents")
local zoneUpdateEvent  = lobbyFolder:WaitForChild("ZoneUpdate")
local playerZoneEvent  = lobbyFolder:WaitForChild("PlayerZone")

-- ===== État local =====
local currentZone    : string? = nil
local zoneData       : { [string]: any } = {}  -- dernière update par gamemode

-- ===== GUI =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "LobbyHudGui"
screenGui.ResetOnSpawn   = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent         = localPlayer.PlayerGui

-- Panneau bas-centre, visible seulement en zone
local panel = Instance.new("Frame", screenGui)
panel.Name                   = "ZonePanel"
panel.Size                   = UDim2.new(0, 320, 0, 70)
panel.Position               = UDim2.new(0.5, -160, 1, 10)  -- commence hors écran
panel.BackgroundColor3       = Color3.fromRGB(14, 12, 20)
panel.BackgroundTransparency = 0.12
panel.BorderSizePixel        = 0
panel.Visible                = true
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)

-- Barre de couleur gauche (couleur du mode)
local colorBar = Instance.new("Frame", panel)
colorBar.Name            = "ColorBar"
colorBar.Size            = UDim2.new(0, 5, 1, -16)
colorBar.Position        = UDim2.new(0, 8, 0, 8)
colorBar.BackgroundColor3 = Color3.fromRGB(150, 150, 200)
colorBar.BorderSizePixel = 0
Instance.new("UICorner", colorBar).CornerRadius = UDim.new(0, 3)

local ZONE_COLORS = {
	["Clown Survival"] = Color3.fromRGB(220, 50,  50),
	Dodgeball          = Color3.fromRGB(50,  100, 220),
}

-- Nom de la zone
local zoneNameLabel = Instance.new("TextLabel", panel)
zoneNameLabel.Name               = "ZoneName"
zoneNameLabel.Size               = UDim2.new(1, -60, 0, 22)
zoneNameLabel.Position           = UDim2.new(0, 20, 0, 10)
zoneNameLabel.BackgroundTransparency = 1
zoneNameLabel.Font               = Enum.Font.GothamBold
zoneNameLabel.TextSize           = 15
zoneNameLabel.TextColor3         = Color3.fromRGB(240, 240, 245)
zoneNameLabel.TextXAlignment     = Enum.TextXAlignment.Left
zoneNameLabel.Text               = ""

-- Barre de progression joueurs
local progressBg = Instance.new("Frame", panel)
progressBg.Name            = "ProgressBg"
progressBg.Size            = UDim2.new(1, -26, 0, 6)
progressBg.Position        = UDim2.new(0, 20, 0, 36)
progressBg.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
progressBg.BorderSizePixel = 0
Instance.new("UICorner", progressBg).CornerRadius = UDim.new(0, 3)

local progressFill = Instance.new("Frame", progressBg)
progressFill.Name            = "Fill"
progressFill.Size            = UDim2.new(0, 0, 1, 0)
progressFill.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
progressFill.BorderSizePixel = 0
Instance.new("UICorner", progressFill).CornerRadius = UDim.new(0, 3)

-- Texte statut
local statusLabel = Instance.new("TextLabel", panel)
statusLabel.Name               = "Status"
statusLabel.Size               = UDim2.new(1, -26, 0, 18)
statusLabel.Position           = UDim2.new(0, 20, 0, 46)
statusLabel.BackgroundTransparency = 1
statusLabel.Font               = Enum.Font.Gotham
statusLabel.TextSize           = 12
statusLabel.TextColor3         = Color3.fromRGB(160, 160, 170)
statusLabel.TextXAlignment     = Enum.TextXAlignment.Left
statusLabel.Text               = ""

-- Compteur joueurs (coin droit)
local countLabel = Instance.new("TextLabel", panel)
countLabel.Name               = "Count"
countLabel.Size               = UDim2.new(0, 50, 1, 0)
countLabel.Position           = UDim2.new(1, -58, 0, 0)
countLabel.BackgroundTransparency = 1
countLabel.Font               = Enum.Font.GothamBold
countLabel.TextSize           = 20
countLabel.TextColor3         = Color3.fromRGB(255, 255, 255)
countLabel.TextXAlignment     = Enum.TextXAlignment.Center
countLabel.Text               = ""

-- ===== Animations =====
local SLIDE_IN  = UDim2.new(0.5, -160, 1, -86)
local SLIDE_OUT = UDim2.new(0.5, -160, 1, 10)

local function showPanel()
	TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = SLIDE_IN,
	}):Play()
end

local function hidePanel()
	TweenService:Create(panel, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
		Position = SLIDE_OUT,
	}):Play()
end

-- ===== Mise à jour du panneau =====
local function refreshPanel()
	if not currentZone then
		hidePanel()
		return
	end

	local data = zoneData[currentZone]
	if not data then return end

	showPanel()

	-- Couleur
	local color = ZONE_COLORS[currentZone] or Color3.fromRGB(150, 150, 200)
	colorBar.BackgroundColor3 = color
	progressFill.BackgroundColor3 = color

	-- Nom
	zoneNameLabel.Text = "🎮  " .. currentZone:upper()

	-- Compteur
	local count = data.count or 0
	local minP  = data.minPlayers or 2
	countLabel.Text = count .. "/" .. minP

	-- Barre de progression
	local pct = math.clamp(count / math.max(minP, 1), 0, 1)
	TweenService:Create(progressFill, TweenInfo.new(0.2), {
		Size = UDim2.new(pct, 0, 1, 0),
	}):Play()

	-- Statut
	if data.roundInProgress then
		statusLabel.Text      = "⏳ Une partie est en cours…"
		statusLabel.TextColor3 = Color3.fromRGB(200, 150, 50)
	elseif data.inCountdown then
		local t = data.countdown or 0
		statusLabel.Text       = "🚀 Départ dans " .. t .. "s — reste en zone !"
		statusLabel.TextColor3 = Color3.fromRGB(80, 220, 80)
	elseif count >= minP then
		statusLabel.Text       = "🟢 Assez de joueurs — décompte imminent…"
		statusLabel.TextColor3 = Color3.fromRGB(80, 220, 80)
	else
		statusLabel.Text       = "En attente de " .. (minP - count) .. " joueur(s) de plus…"
		statusLabel.TextColor3 = Color3.fromRGB(160, 160, 170)
	end
end

-- ===== Réception des events =====
playerZoneEvent.OnClientEvent:Connect(function(data)
	currentZone = data.gamemodeName  -- nil si hors zone
	refreshPanel()
end)

zoneUpdateEvent.OnClientEvent:Connect(function(data)
	zoneData[data.gamemodeName] = data
	-- Rafraîchit seulement si c'est la zone du joueur
	if data.gamemodeName == currentZone then
		refreshPanel()
	end
end)
