--!nonstrict
-- LeaderboardGui.client.luau — Overlay classements (Tab pour toggle).
-- Deux dimensions de sélection : période (ALL TIME / HEBDO) x board (GP / Victoires / Meilleure
-- série), pilotées par shared/Config/LeaderboardsConfig.luau. Le serveur envoie TOUT le payload
-- (les 3 boards x 2 périodes) à chaque Refresh ; changer d'onglet ne fait que re-rendre depuis le
-- cache local, aucun aller-retour serveur nécessaire.

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

local eventsFolder = ReplicatedStorage:WaitForChild("LeaderboardEvents")
local lbEvent      = eventsFolder:WaitForChild("Board")

local LeaderboardsConfig = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("LeaderboardsConfig")
)
local UISound = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("UISound"))
local ButtonHover = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("ButtonHover"))
local PanelCoordinator = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("PanelCoordinator")
)
local PANEL_ID = "leaderboard"

-- ===== Constantes UI =====
local PANEL_W    = 400
local PANEL_H    = 520
local ROW_H      = 34
local HEADER_H   = 44
local TABS_H     = 30 -- hauteur d'une rangée d'onglets
local COLOR_BG   = Color3.fromRGB(14, 14, 18)
local COLOR_ROW  = Color3.fromRGB(28, 28, 36)
local COLOR_ME   = Color3.fromRGB(210, 160, 10)
local COLOR_TXT  = Color3.fromRGB(230, 230, 235)
local COLOR_DIM  = Color3.fromRGB(140, 140, 150)
local COLOR_TOP  = Color3.fromRGB(255, 210, 30)
local COLOR_TAB_OFF = Color3.fromRGB(26, 26, 34)
local COLOR_TAB_ON  = Color3.fromRGB(60, 48, 10)

-- ===== Construction du GUI =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "LeaderboardGui"
screenGui.ResetOnSpawn   = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent         = localPlayer.PlayerGui

-- Panneau centré
local panel = Instance.new("Frame", screenGui)
panel.Name                   = "Panel"
panel.Size                   = UDim2.new(0, PANEL_W, 0, PANEL_H)
panel.Position               = UDim2.new(0.5, -PANEL_W / 2, 0.5, -PANEL_H / 2)
panel.BackgroundColor3       = COLOR_BG
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel        = 0
panel.Visible                = false
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)

-- Titre
local titleBar = Instance.new("Frame", panel)
titleBar.Size               = UDim2.new(1, 0, 0, HEADER_H)
titleBar.BackgroundColor3   = Color3.fromRGB(30, 28, 22)
titleBar.BorderSizePixel    = 0
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)
-- surcharge coin bas pour avoir des coins carrés en bas
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
titleLabel.TextSize           = 15
titleLabel.TextColor3         = COLOR_TOP
titleLabel.TextXAlignment     = Enum.TextXAlignment.Left
titleLabel.TextTruncate       = Enum.TextTruncate.AtEnd
titleLabel.Text               = "🏆  CLASSEMENT"

-- Bouton fermer (X)
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

-- ===== Onglets : période (ALL TIME / HEBDO) =====
local periodRow = Instance.new("Frame", panel)
periodRow.Size               = UDim2.new(1, -24, 0, TABS_H)
periodRow.Position           = UDim2.new(0, 12, 0, HEADER_H + 6)
periodRow.BackgroundTransparency = 1
local periodLayout = Instance.new("UIListLayout", periodRow)
periodLayout.FillDirection = Enum.FillDirection.Horizontal
periodLayout.Padding       = UDim.new(0, 6)
periodLayout.SortOrder     = Enum.SortOrder.LayoutOrder

-- ===== Onglets : board (GP / Victoires / Meilleure série) =====
local boardRow = Instance.new("Frame", panel)
boardRow.Size               = UDim2.new(1, -24, 0, TABS_H)
boardRow.Position           = UDim2.new(0, 12, 0, HEADER_H + 6 + TABS_H + 6)
boardRow.BackgroundTransparency = 1
local boardLayout = Instance.new("UIListLayout", boardRow)
boardLayout.FillDirection = Enum.FillDirection.Horizontal
boardLayout.Padding       = UDim.new(0, 6)
boardLayout.SortOrder     = Enum.SortOrder.LayoutOrder

local TABS_TOP = HEADER_H + 6 + (TABS_H + 6) * 2 -- bas de la 2ᵉ rangée d'onglets

-- Sous-titre (numéro de semaine, visible seulement en HEBDO)
local weekLabel = Instance.new("TextLabel", panel)
weekLabel.Size               = UDim2.new(1, -24, 0, 16)
weekLabel.Position           = UDim2.new(0, 12, 0, TABS_TOP)
weekLabel.BackgroundTransparency = 1
weekLabel.Font               = Enum.Font.Gotham
weekLabel.TextSize           = 11
weekLabel.TextColor3         = COLOR_DIM
weekLabel.TextXAlignment     = Enum.TextXAlignment.Left
weekLabel.Text               = ""
weekLabel.Visible            = false

local LIST_TOP = TABS_TOP + 18

-- En-tête colonnes
local colHeader = Instance.new("Frame", panel)
colHeader.Size              = UDim2.new(1, -24, 0, 22)
colHeader.Position           = UDim2.new(0, 12, 0, LIST_TOP)
colHeader.BackgroundTransparency = 1

local function colLabel(parent, text, xPct, wPct, align)
	local l = Instance.new("TextLabel", parent)
	l.Size               = UDim2.new(wPct, 0, 1, 0)
	l.Position           = UDim2.new(xPct, 0, 0, 0)
	l.BackgroundTransparency = 1
	l.Font               = Enum.Font.GothamBold
	l.TextSize           = 12
	l.TextColor3         = COLOR_DIM
	l.TextXAlignment     = align or Enum.TextXAlignment.Left
	l.Text               = text
	return l
end
colLabel(colHeader, "#",       0,    0.08)
colLabel(colHeader, "JOUEUR",  0.08, 0.52)
local scoreHeaderLabel = colLabel(colHeader, "GP", 0.60, 0.40, Enum.TextXAlignment.Right)

-- Séparateur
local sep = Instance.new("Frame", panel)
sep.Size              = UDim2.new(1, -24, 0, 1)
sep.Position          = UDim2.new(0, 12, 0, LIST_TOP + 26)
sep.BackgroundColor3  = Color3.fromRGB(55, 55, 70)
sep.BorderSizePixel   = 0

-- Conteneur des lignes (liste scrollable — molette native, aucun code requis)
local rowList = Instance.new("ScrollingFrame", panel)
rowList.Size                     = UDim2.new(1, -24, 1, -(LIST_TOP + 32 + 40))
rowList.Position                 = UDim2.new(0, 12, 0, LIST_TOP + 32)
rowList.BackgroundTransparency   = 1
rowList.BorderSizePixel          = 0
rowList.ScrollBarThickness       = 4
rowList.ScrollBarImageColor3     = Color3.fromRGB(80, 80, 100)
rowList.CanvasSize               = UDim2.new(0, 0, 0, 0)
rowList.AutomaticCanvasSize      = Enum.AutomaticSize.Y
local rowLayout = Instance.new("UIListLayout", rowList)
rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowLayout.Padding   = UDim.new(0, 4)

-- Hint bas
local hintLabel = Instance.new("TextLabel", panel)
hintLabel.Size               = UDim2.new(1, -24, 0, 30)
hintLabel.Position           = UDim2.new(0, 12, 1, -36)
hintLabel.BackgroundTransparency = 1
hintLabel.Font               = Enum.Font.Gotham
hintLabel.TextSize           = 12
hintLabel.TextColor3         = COLOR_DIM
hintLabel.TextXAlignment     = Enum.TextXAlignment.Center
hintLabel.Text               = "Tab  •  fermer"

-- ===== Bouton de toggle (toujours visible) =====
local toggleBtn = Instance.new("TextButton", screenGui)
toggleBtn.Name             = "ToggleBtn"
toggleBtn.Size             = UDim2.new(0, 42, 0, 42)
-- Décalé à droite du bouton "👤 Profil" (ProfileMenu.client.luau, à 0,14,0,74) pour ne pas se superposer.
toggleBtn.Position         = UDim2.new(0, 64, 0, 74)
toggleBtn.BackgroundColor3 = Color3.fromRGB(40, 36, 20)
toggleBtn.Font             = Enum.Font.GothamBold
toggleBtn.TextSize         = 22
toggleBtn.TextColor3       = COLOR_TOP
toggleBtn.Text             = "🏆"
toggleBtn.AutoButtonColor  = true
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 8)
ButtonHover.Apply(toggleBtn)

-- ===== État =====
local selectedPeriod = "alltime"
local selectedBoard  = "gp"
local latestPayload  = { boards = {}, weekId = "" }

local boardsById = {}
for _, board in LeaderboardsConfig.BOARDS do
	boardsById[board.id] = board
end

-- ===== Helpers =====
local function makeRow(entry, order, board)
	local isMe = (entry.userId == localPlayer.UserId)

	local row = Instance.new("Frame", rowList)
	row.Name               = "Row" .. order
	row.Size               = UDim2.new(1, 0, 0, ROW_H)
	row.BackgroundColor3   = isMe and Color3.fromRGB(60, 48, 10) or COLOR_ROW
	row.BackgroundTransparency = isMe and 0 or 0.1
	row.BorderSizePixel    = 0
	row.LayoutOrder        = order
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 7)

	-- Médaille top 3
	local medals = { "🥇", "🥈", "🥉" }
	local rankStr = medals[entry.rank] or ("#" .. entry.rank)

	local rankLbl = Instance.new("TextLabel", row)
	rankLbl.Size               = UDim2.new(0.08, 0, 1, 0)
	rankLbl.BackgroundTransparency = 1
	rankLbl.Font               = Enum.Font.GothamBold
	rankLbl.TextSize           = 14
	rankLbl.TextColor3         = isMe and COLOR_ME or COLOR_TXT
	rankLbl.TextXAlignment     = Enum.TextXAlignment.Center
	rankLbl.Text               = rankStr

	local nameLbl = Instance.new("TextLabel", row)
	nameLbl.Size              = UDim2.new(0.52, 0, 1, 0)
	nameLbl.Position          = UDim2.new(0.08, 0, 0, 0)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font              = isMe and Enum.Font.GothamBold or Enum.Font.Gotham
	nameLbl.TextSize          = 14
	nameLbl.TextColor3        = isMe and COLOR_ME or COLOR_TXT
	nameLbl.TextXAlignment    = Enum.TextXAlignment.Left
	nameLbl.Text              = isMe and ("▶ " .. entry.name) or entry.name

	local scoreLbl = Instance.new("TextLabel", row)
	scoreLbl.Size              = UDim2.new(0.40, -6, 1, 0)
	scoreLbl.Position          = UDim2.new(0.60, 0, 0, 0)
	scoreLbl.BackgroundTransparency = 1
	scoreLbl.Font              = Enum.Font.GothamBold
	scoreLbl.TextSize          = 14
	scoreLbl.TextColor3        = isMe and COLOR_ME or COLOR_TXT
	scoreLbl.TextXAlignment    = Enum.TextXAlignment.Right
	scoreLbl.Text              = LeaderboardsConfig.FormatScore(board, entry.score)

	return row
end

local function rebuildList()
	rowList:ClearAllChildren()
	local newLayout = Instance.new("UIListLayout", rowList)
	newLayout.SortOrder = Enum.SortOrder.LayoutOrder
	newLayout.Padding   = UDim.new(0, 4)

	local board = boardsById[selectedBoard]
	local entries = latestPayload.boards[selectedBoard]
	entries = entries and entries[selectedPeriod] or {}

	titleLabel.Text = board.icon .. "  CLASSEMENT — " .. board.labelUpper
		.. (selectedPeriod == "weekly" and " (HEBDO)" or " (ALL TIME)")
	scoreHeaderLabel.Text = board.unitUpper

	weekLabel.Visible = selectedPeriod == "weekly"
	weekLabel.Text     = "Semaine " .. latestPayload.weekId

	if #entries == 0 then
		local lbl = Instance.new("TextLabel", rowList)
		lbl.Size               = UDim2.new(1, 0, 0, 50)
		lbl.BackgroundTransparency = 1
		lbl.Font               = Enum.Font.Gotham
		lbl.TextSize           = 14
		lbl.TextColor3         = COLOR_DIM
		lbl.Text               = "Aucun score enregistré pour l'instant."
		lbl.LayoutOrder        = 0
		return
	end

	for _, entry in entries do
		makeRow(entry, entry.rank, board)
	end
end

-- ===== Construction des boutons d'onglets (data-driven, LeaderboardsConfig) =====
local function makeTabButton(parent, text, widthScale, onClick)
	local btn = Instance.new("TextButton", parent)
	btn.Size              = UDim2.new(widthScale, -4, 1, 0)
	btn.BackgroundColor3  = COLOR_TAB_OFF
	btn.Font              = Enum.Font.GothamBold
	btn.TextSize           = 13
	btn.TextColor3        = COLOR_DIM
	btn.Text              = text
	btn.AutoButtonColor   = true
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 7)
	ButtonHover.Apply(btn, 0.96) -- effet plus discret que les gros boutons (onglets déjà petits)
	btn.MouseButton1Click:Connect(onClick)
	return btn
end

local periodButtons = {}
for _, period in LeaderboardsConfig.PERIODS do
	local btn = makeTabButton(periodRow, period.label, 1 / #LeaderboardsConfig.PERIODS, function()
		selectedPeriod = period.id
		rebuildList()
		for id, b in periodButtons do
			b.BackgroundColor3 = (id == period.id) and COLOR_TAB_ON or COLOR_TAB_OFF
			b.TextColor3       = (id == period.id) and COLOR_TOP or COLOR_DIM
		end
	end)
	periodButtons[period.id] = btn
end
periodButtons[selectedPeriod].BackgroundColor3 = COLOR_TAB_ON
periodButtons[selectedPeriod].TextColor3       = COLOR_TOP

local boardButtons = {}
for _, board in LeaderboardsConfig.BOARDS do
	local btn = makeTabButton(boardRow, board.icon .. " " .. board.label, 1 / #LeaderboardsConfig.BOARDS, function()
		selectedBoard = board.id
		rebuildList()
		for id, b in boardButtons do
			b.BackgroundColor3 = (id == board.id) and COLOR_TAB_ON or COLOR_TAB_OFF
			b.TextColor3       = (id == board.id) and COLOR_TOP or COLOR_DIM
		end
	end)
	boardButtons[board.id] = btn
end
boardButtons[selectedBoard].BackgroundColor3 = COLOR_TAB_ON
boardButtons[selectedBoard].TextColor3       = COLOR_TOP

-- ===== Toggle =====
local function setVisible(v: boolean)
	panel.Visible = v
	if v then
		PanelCoordinator.NotifyOpened(PANEL_ID) -- joue aussi le son d'ouverture, voir PanelCoordinator.luau
	else
		UISound.PlayClick()
	end
end
local function toggle()
	setVisible(not panel.Visible)
end

toggleBtn.MouseButton1Click:Connect(toggle)
closeBtn.MouseButton1Click:Connect(function() setVisible(false) end)

-- Un AUTRE panneau (Profil, Effectifs de la partie...) vient de s'ouvrir : le nôtre se ferme s'il
-- était affiché, pour ne pas empiler deux panneaux centrés l'un sur l'autre.
PanelCoordinator.OnPanelOpened(function(openedId)
	if openedId ~= PANEL_ID and panel.Visible then
		panel.Visible = false
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Tab then
		toggle()
	end
end)

-- ===== Réception données serveur =====
lbEvent.OnClientEvent:Connect(function(data)
	latestPayload = data or { boards = {}, weekId = "" }
	rebuildList()
end)
