--!nonstrict
-- ClownSurvivalScreamCountdown.client.luau — Compte à rebours "prochain cri" : toutes les
-- SCREAM_INTERVAL secondes (ClownSurvival.luau), tous les survivants encore non touchés crient
-- automatiquement (son positionnel, aide les clowns à les repérer au son). Visible à TOUT LE MONDE
-- (survivants ET clowns) — les clowns en ont besoin pour ajuster leur jeu (s'arrêter de bouger
-- pour mieux écouter où sont les enfants au prochain cri), pas juste les survivants qui vont crier.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local eventsFolder          = ReplicatedStorage:WaitForChild("ClownSurvivalEvents")
local screamCountdownEvent  = eventsFolder:WaitForChild("ScreamCountdown")

-- ===== GUI (coin bas-droit) =====
local gui = Instance.new("ScreenGui")
gui.Name           = "ClownSurvivalScreamCountdownUI"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.Enabled        = false
gui.Parent         = playerGui

local PANEL_W, PANEL_H = 100, 42 -- toujours ~2x plus compact que l'original (176x68), avec le libellé remis

local panel = Instance.new("Frame", gui)
panel.Name                   = "ScreamCountdownPanel"
-- Coin bas-droit, plus bas qu'avant (peut désormais empiéter un peu sur la zone du bouton mobile
-- de frappe, ClownSurvivalInput.client.luau, 120px de haut à y=-160 — à surveiller côté mobile).
panel.AnchorPoint             = Vector2.new(1, 1)
panel.Position                = UDim2.new(1, -14, 1, -130)
panel.Size                    = UDim2.new(0, PANEL_W, 0, PANEL_H)
panel.BackgroundColor3        = Color3.fromRGB(18, 16, 22)
panel.BackgroundTransparency  = 0.12
panel.BorderSizePixel         = 0
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)

-- Agrandit tout le panneau (texte compris) de 20% d'un coup, sans recalculer chaque taille/position
-- à la main — même technique que ButtonHover.luau (UIScale), fiable et centrée.
local panelScale = Instance.new("UIScale", panel)
panelScale.Scale = 1.2

local stroke = Instance.new("UIStroke", panel)
stroke.Thickness    = 1
stroke.Transparency = 0.4
stroke.Color        = Color3.fromRGB(255, 210, 30)

-- Barre d'accent verticale à gauche (même esprit que les toasts de succès)
local accentBar = Instance.new("Frame", panel)
accentBar.Size               = UDim2.new(0, 3, 1, -10)
accentBar.Position           = UDim2.new(0, 4, 0, 5)
accentBar.BackgroundColor3   = Color3.fromRGB(255, 210, 30)
accentBar.BorderSizePixel    = 0
Instance.new("UICorner", accentBar).CornerRadius = UDim.new(0, 2)

-- Icône (pulse en continu pour donner un peu de vie au widget)
local iconLbl = Instance.new("TextLabel", panel)
iconLbl.AnchorPoint             = Vector2.new(0, 0.5)
iconLbl.Position                = UDim2.new(0, 12, 0, 21)
iconLbl.Size                    = UDim2.new(0, 16, 0, 16)
iconLbl.BackgroundTransparency  = 1
iconLbl.Font                    = Enum.Font.GothamBold
iconLbl.TextSize                = 13
iconLbl.Text                    = "🔊"
local iconScale = Instance.new("UIScale", iconLbl)

-- Libellé
local labelLbl = Instance.new("TextLabel", panel)
labelLbl.AnchorPoint             = Vector2.new(0, 0.5)
labelLbl.Position                = UDim2.new(0, 32, 0, 11)
labelLbl.Size                    = UDim2.new(0, 62, 0, 10)
labelLbl.BackgroundTransparency  = 1
labelLbl.Font                    = Enum.Font.GothamBold
labelLbl.TextSize                = 8
labelLbl.TextColor3              = Color3.fromRGB(170, 170, 180)
labelLbl.TextXAlignment          = Enum.TextXAlignment.Left
labelLbl.Text                    = "PROCHAIN CRI"

-- Compte à rebours — TextSize FIXE (pas TextScaled) : un compteur ne doit pas changer de taille de
-- police au fil du temps selon le nombre de chiffres restants.
local textLbl = Instance.new("TextLabel", panel)
textLbl.AnchorPoint             = Vector2.new(0, 0.5)
textLbl.Position                = UDim2.new(0, 32, 0, 22)
textLbl.Size                    = UDim2.new(0, 62, 0, 18)
textLbl.BackgroundTransparency  = 1
textLbl.Font                    = Enum.Font.FredokaOne
textLbl.TextSize                = 15
textLbl.TextColor3              = Color3.fromRGB(255, 210, 30)
textLbl.TextXAlignment          = Enum.TextXAlignment.Left
textLbl.Text                    = ""

-- Barre de progression : se vide au fil du compte à rebours (indice visuel en plus du texte)
local barBg = Instance.new("Frame", panel)
barBg.AnchorPoint          = Vector2.new(0, 1)
barBg.Position              = UDim2.new(0, 10, 1, -4)
barBg.Size                  = UDim2.new(1, -16, 0, 3)
barBg.BackgroundColor3      = Color3.fromRGB(45, 42, 50)
barBg.BorderSizePixel       = 0
Instance.new("UICorner", barBg).CornerRadius = UDim.new(1, 0)

local barFill = Instance.new("Frame", barBg)
barFill.Size               = UDim2.new(1, 0, 1, 0)
barFill.BackgroundColor3   = Color3.fromRGB(255, 210, 30)
barFill.BorderSizePixel    = 0
Instance.new("UICorner", barFill).CornerRadius = UDim.new(1, 0)

local URGENT_THRESHOLD = 3 -- s : couleur d'alerte quand le cri est imminent
local COLOR_NORMAL = Color3.fromRGB(255, 210, 30)
local COLOR_URGENT = Color3.fromRGB(255, 90, 90)

-- ===== Logique =====
local nextScreamAt: number? = nil
local totalDuration = 1
local tickConn: RBXScriptConnection? = nil

local function stepCountdown()
	if not nextScreamAt then return end
	local remaining = math.max(0, nextScreamAt - os.clock())
	local urgent = remaining <= URGENT_THRESHOLD
	local color = urgent and COLOR_URGENT or COLOR_NORMAL

	textLbl.Text              = math.ceil(remaining) .. "s"
	textLbl.TextColor3        = color
	barFill.BackgroundColor3  = color
	accentBar.BackgroundColor3 = color
	stroke.Color              = color

	local fraction = math.clamp(remaining / totalDuration, 0, 1)
	barFill.Size = UDim2.new(fraction, 0, 1, 0)

	-- Petit pulse continu sur l'icône (plus rapide/prononcé quand le cri est imminent)
	local pulseSpeed = urgent and 9 or 4
	local pulseAmount = urgent and 0.18 or 0.1
	iconScale.Scale = 1 + math.sin(os.clock() * pulseSpeed) * pulseAmount
end

-- Reçoit une DURÉE (secondes restantes), pas un timestamp serveur : `os.clock()` n'est pas
-- synchronisé entre machines, donc on calcule l'échéance à partir de NOTRE PROPRE `os.clock()`
-- au moment de la réception, pas celui du serveur. Le serveur envoie toujours l'intervalle COMPLET
-- (jamais un reste partiel), donc cette valeur sert aussi de référence "100%" pour la barre.
local function activate(remainingSeconds: number)
	nextScreamAt  = os.clock() + remainingSeconds
	totalDuration = remainingSeconds
	gui.Enabled   = true
	stepCountdown()
	if not tickConn then
		tickConn = RunService.Heartbeat:Connect(stepCountdown)
	end
end

local function deactivate()
	nextScreamAt = nil
	gui.Enabled  = false
	if tickConn then
		tickConn:Disconnect()
		tickConn = nil
	end
end

screamCountdownEvent.OnClientEvent:Connect(function(remainingSeconds: number?)
	if remainingSeconds then
		activate(remainingSeconds)
	else
		deactivate()
	end
end)
