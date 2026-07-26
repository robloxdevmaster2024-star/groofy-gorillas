--!nonstrict
-- ClownSurvivalRoster.client.luau — Bouton "📋" (haut-droite) → panneau "Effectifs de la partie"
-- listant, en direct, les Clowns / Enfants / Éliminés du round Clown Survival en cours.
--
-- Pas d'info cachée ici : l'identité des clowns est déjà visible de tous via le Highlight rouge
-- (ClownSurvival.luau) — ce panneau ne fait que consolider ça en liste avec les noms, plutôt que
-- d'obliger chacun à repérer les joueurs à l'œil. Visible uniquement pour les participants du
-- round (RosterVisible, voir ClownSurvival.luau), pas pour les joueurs restés au lobby.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

local eventsFolder      = ReplicatedStorage:WaitForChild("ClownSurvivalEvents")
local rosterVisibleEvent = eventsFolder:WaitForChild("RosterVisible")
local rosterUpdateEvent  = eventsFolder:WaitForChild("RosterUpdate")

local PanelCoordinator = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("PanelCoordinator")
)
local UISound = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("UISound"))
local ButtonHover = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("ButtonHover"))
local PANEL_ID = "roster"

-- ===== Constantes UI (même palette que LeaderboardGui/ProfileMenu) =====
local PANEL_W   = 380
local PANEL_H   = 420
local HEADER_H  = 44
local COLOR_BG  = Color3.fromRGB(14, 14, 18)
local COLOR_ROW = Color3.fromRGB(28, 28, 36)
local COLOR_TXT = Color3.fromRGB(230, 230, 235)
local COLOR_DIM = Color3.fromRGB(140, 140, 150)
local COLOR_TOP = Color3.fromRGB(255, 210, 30)

local SECTIONS = {
	{ key = "clowns",     title = "🤡 CLOWNS",   color = Color3.fromRGB(255, 90, 90) },
	{ key = "children",   title = "🧒 ENFANTS",  color = Color3.fromRGB(120, 220, 140) },
	{ key = "eliminated", title = "💀 ÉLIMINÉS", color = Color3.fromRGB(150, 150, 160) },
}

-- ===== Construction du GUI =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "ClownSurvivalRosterGui"
screenGui.ResetOnSpawn   = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent         = localPlayer:WaitForChild("PlayerGui")

local panel = Instance.new("Frame", screenGui)
panel.Name                   = "Panel"
panel.Size                   = UDim2.new(0, PANEL_W, 0, PANEL_H)
panel.Position               = UDim2.new(0.5, -PANEL_W / 2, 0.5, -PANEL_H / 2)
panel.BackgroundColor3       = COLOR_BG
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel        = 0
panel.Visible                = false
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)

local titleBar = Instance.new("Frame", panel)
titleBar.Size             = UDim2.new(1, 0, 0, HEADER_H)
titleBar.BackgroundColor3 = Color3.fromRGB(30, 28, 22)
titleBar.BorderSizePixel  = 0
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)
local titleBotCover = Instance.new("Frame", titleBar)
titleBotCover.Size             = UDim2.new(1, 0, 0, 12)
titleBotCover.Position         = UDim2.new(0, 0, 1, -12)
titleBotCover.BackgroundColor3 = Color3.fromRGB(30, 28, 22)
titleBotCover.BorderSizePixel  = 0

local titleLabel = Instance.new("TextLabel", titleBar)
titleLabel.Size               = UDim2.new(1, -50, 1, 0)
titleLabel.Position           = UDim2.new(0, 14, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Font               = Enum.Font.GothamBold
titleLabel.TextSize           = 17
titleLabel.TextColor3         = COLOR_TOP
titleLabel.TextXAlignment     = Enum.TextXAlignment.Left
titleLabel.Text               = "🎪  EFFECTIFS DE LA PARTIE"

local closeBtn = Instance.new("TextButton", titleBar)
closeBtn.Size              = UDim2.new(0, 32, 0, 32)
closeBtn.Position          = UDim2.new(1, -42, 0.5, -16)
closeBtn.BackgroundColor3  = Color3.fromRGB(90, 40, 40)
closeBtn.Font              = Enum.Font.GothamBold
closeBtn.TextSize          = 16
closeBtn.TextColor3        = Color3.fromRGB(255, 200, 200)
closeBtn.Text              = "X"
closeBtn.AutoButtonColor   = true
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
ButtonHover.Apply(closeBtn)

-- Conteneur des 3 sections, empilées verticalement
local sectionsContainer = Instance.new("Frame", panel)
sectionsContainer.Size              = UDim2.new(1, -24, 1, -(HEADER_H + 20))
sectionsContainer.Position          = UDim2.new(0, 12, 0, HEADER_H + 12)
sectionsContainer.BackgroundTransparency = 1
local sectionsLayout = Instance.new("UIListLayout", sectionsContainer)
sectionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
sectionsLayout.Padding   = UDim.new(0, 8)

local sectionLists = {}

for i, section in SECTIONS do
	local block = Instance.new("Frame", sectionsContainer)
	block.Name              = section.key
	block.Size               = UDim2.new(1, 0, 0, 0)
	block.AutomaticSize      = Enum.AutomaticSize.Y
	block.BackgroundTransparency = 1
	block.LayoutOrder        = i
	local blockLayout = Instance.new("UIListLayout", block)
	blockLayout.SortOrder = Enum.SortOrder.LayoutOrder
	blockLayout.Padding   = UDim.new(0, 4)

	local header = Instance.new("TextLabel", block)
	header.Size               = UDim2.new(1, 0, 0, 22)
	header.BackgroundTransparency = 1
	header.Font               = Enum.Font.GothamBold
	header.TextSize           = 13
	header.TextColor3         = section.color
	header.TextXAlignment     = Enum.TextXAlignment.Left
	header.LayoutOrder        = 0
	header.Text               = section.title .. " (0)"

	local namesLabel = Instance.new("TextLabel", block)
	namesLabel.Size               = UDim2.new(1, 0, 0, 0)
	namesLabel.AutomaticSize      = Enum.AutomaticSize.Y
	namesLabel.BackgroundTransparency = 1
	namesLabel.Font               = Enum.Font.Gotham
	namesLabel.TextSize           = 14
	namesLabel.TextColor3         = COLOR_TXT
	namesLabel.TextXAlignment     = Enum.TextXAlignment.Left
	namesLabel.TextWrapped        = true
	namesLabel.LayoutOrder        = 1
	namesLabel.Text               = "—"

	sectionLists[section.key] = { header = header, names = namesLabel, title = section.title }
end

-- ===== Bouton de toggle (tout en haut à droite) =====
local toggleBtn = Instance.new("TextButton", screenGui)
toggleBtn.Name             = "ToggleBtn"
toggleBtn.Size             = UDim2.new(0, 42, 0, 42)
toggleBtn.AnchorPoint      = Vector2.new(1, 0)
toggleBtn.Position         = UDim2.new(1, -16, 0, 8)
toggleBtn.BackgroundColor3 = Color3.fromRGB(40, 36, 20)
toggleBtn.Font             = Enum.Font.GothamBold
toggleBtn.TextSize         = 22
toggleBtn.TextColor3       = COLOR_TOP
toggleBtn.Text             = "📋"
toggleBtn.AutoButtonColor  = true
toggleBtn.Visible          = false -- affiché seulement pendant un round Clown Survival (RosterVisible)
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 8)
ButtonHover.Apply(toggleBtn)

-- ===== Logique =====
local function setVisible(v: boolean)
	panel.Visible = v
	if v then
		PanelCoordinator.NotifyOpened(PANEL_ID) -- joue aussi le son d'ouverture, voir PanelCoordinator.luau
	else
		UISound.PlayClick()
	end
end
toggleBtn.MouseButton1Click:Connect(function() setVisible(not panel.Visible) end)
closeBtn.MouseButton1Click:Connect(function() setVisible(false) end)

-- Un AUTRE panneau (Classement, Profil...) vient de s'ouvrir : le nôtre se ferme s'il était
-- affiché, pour ne pas empiler deux panneaux centrés l'un sur l'autre.
PanelCoordinator.OnPanelOpened(function(openedId)
	if openedId ~= PANEL_ID and panel.Visible then
		panel.Visible = false
	end
end)

rosterVisibleEvent.OnClientEvent:Connect(function(active: boolean)
	toggleBtn.Visible = active == true
	if not active then
		setVisible(false)
	end
end)

rosterUpdateEvent.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	for _, section in SECTIONS do
		local ui = sectionLists[section.key]
		local list = payload[section.key] or {}
		ui.header.Text = string.format("%s (%d)", ui.title, #list)
		ui.names.Text  = #list > 0 and table.concat(list, ", ") or "—"
	end
end)
