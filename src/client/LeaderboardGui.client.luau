--!nonstrict
-- LeaderboardGui.client.luau — Overlay classement global (Tab pour toggle).

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

local eventsFolder = ReplicatedStorage:WaitForChild("LeaderboardEvents")
local lbEvent      = eventsFolder:WaitForChild("Board")

-- ===== Constantes UI =====
local PANEL_W   = 400
local PANEL_H   = 460
local ROW_H     = 36
local HEADER_H  = 44
local COLOR_BG  = Color3.fromRGB(14, 14, 18)
local COLOR_ROW = Color3.fromRGB(28, 28, 36)
local COLOR_ME  = Color3.fromRGB(210, 160, 10)
local COLOR_TXT = Color3.fromRGB(230, 230, 235)
local COLOR_DIM = Color3.fromRGB(140, 140, 150)
local COLOR_TOP = Color3.fromRGB(255, 210, 30)

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
titleLabel.TextSize           = 17
titleLabel.TextColor3         = COLOR_TOP
titleLabel.TextXAlignment     = Enum.TextXAlignment.Left
titleLabel.Text               = "🏆  CLASSEMENT GLOBAL — GOOFY POINTS"

-- Bouton fermer (X)
local closeBtn = Instance.new("TextButton", titleBar)
closeBtn.Size              = UDim2.new(0, 32, 0, 32)
closeBtn.Position          = UDim2.new(1, -42, 0.5, -16)
closeBtn.BackgroundColor3  = Color3.fromRGB(90, 40, 40)
closeBtn.Font              = Enum.Font.GothamBold
closeBtn.TextSize          = 16
closeBtn.TextColor3        = Color3.fromRGB(255, 200, 200)
closeBtn.Text              = "✕"
closeBtn.AutoButtonColor   = true
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

-- En-tête colonnes
local colHeader = Instance.new("Frame", panel)
colHeader.Size              = UDim2.new(1, -24, 0, 28)
colHeader.Position          = UDim2.new(0, 12, 0, HEADER_H + 6)
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
colLabel(colHeader, "JOUEUR",  0.08, 0.62)
colLabel(colHeader, "GP",      0.70, 0.30, Enum.TextXAlignment.Right)

-- Séparateur
local sep = Instance.new("Frame", panel)
sep.Size              = UDim2.new(1, -24, 0, 1)
sep.Position          = UDim2.new(0, 12, 0, HEADER_H + 36)
sep.BackgroundColor3  = Color3.fromRGB(55, 55, 70)
sep.BorderSizePixel   = 0

-- Conteneur des lignes (liste scrollable)
local rowList = Instance.new("ScrollingFrame", panel)
rowList.Size                     = UDim2.new(1, -24, 1, -(HEADER_H + 42 + 40))
rowList.Position                 = UDim2.new(0, 12, 0, HEADER_H + 42)
rowList.BackgroundTransparency   = 1
rowList.BorderSizePixel          = 0
rowList.ScrollBarThickness       = 4
rowList.ScrollBarImageColor3     = Color3.fromRGB(80, 80, 100)
rowList.CanvasSize               = UDim2.new(0, 0, 0, 0)
rowList.AutomaticCanvasSize      = Enum.AutomaticSize.Y
local rowLayout = Instance.new("UIListLayout", rowList)
rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowLayout.Padding   = UDim.new(0, 4)

-- Placeholder chargement
local placeholderLabel = Instance.new("TextLabel", rowList)
placeholderLabel.Name              = "Placeholder"
placeholderLabel.Size              = UDim2.new(1, 0, 0, 50)
placeholderLabel.BackgroundTransparency = 1
placeholderLabel.Font              = Enum.Font.Gotham
placeholderLabel.TextSize          = 14
placeholderLabel.TextColor3        = COLOR_DIM
placeholderLabel.Text              = "Chargement du classement…"
placeholderLabel.LayoutOrder       = 0

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
toggleBtn.Position         = UDim2.new(0, 14, 0, 74)
toggleBtn.BackgroundColor3 = Color3.fromRGB(40, 36, 20)
toggleBtn.Font             = Enum.Font.GothamBold
toggleBtn.TextSize         = 22
toggleBtn.TextColor3       = COLOR_TOP
toggleBtn.Text             = "🏆"
toggleBtn.AutoButtonColor  = true
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 8)

-- ===== Helpers =====
local function makeRow(entry, order)
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
	nameLbl.Size              = UDim2.new(0.62, 0, 1, 0)
	nameLbl.Position          = UDim2.new(0.08, 0, 0, 0)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font              = isMe and Enum.Font.GothamBold or Enum.Font.Gotham
	nameLbl.TextSize          = 14
	nameLbl.TextColor3        = isMe and COLOR_ME or COLOR_TXT
	nameLbl.TextXAlignment    = Enum.TextXAlignment.Left
	nameLbl.Text              = isMe and ("▶ " .. entry.name) or entry.name

	local scoreLbl = Instance.new("TextLabel", row)
	scoreLbl.Size              = UDim2.new(0.30, -6, 1, 0)
	scoreLbl.Position          = UDim2.new(0.70, 0, 0, 0)
	scoreLbl.BackgroundTransparency = 1
	scoreLbl.Font              = Enum.Font.GothamBold
	scoreLbl.TextSize          = 14
	scoreLbl.TextColor3        = isMe and COLOR_ME or COLOR_TXT
	scoreLbl.TextXAlignment    = Enum.TextXAlignment.Right
	scoreLbl.Text              = tostring(entry.score) .. " GP"

	return row
end

local function rebuildList(entries)
	rowList:ClearAllChildren()
	local newLayout = Instance.new("UIListLayout", rowList)
	newLayout.SortOrder = Enum.SortOrder.LayoutOrder
	newLayout.Padding   = UDim.new(0, 4)

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
		makeRow(entry, entry.rank)
	end
end

-- ===== Toggle =====
local function setVisible(v: boolean)
	panel.Visible = v
end
local function toggle()
	setVisible(not panel.Visible)
end

toggleBtn.MouseButton1Click:Connect(toggle)
closeBtn.MouseButton1Click:Connect(function() setVisible(false) end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Tab then
		toggle()
	end
end)

-- ===== Réception données serveur =====
lbEvent.OnClientEvent:Connect(function(data)
	rebuildList(data.entries or {})
end)
