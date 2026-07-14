--!nonstrict
-- SettingsMenu.client.luau — Panneau de réglages (intermission) côté client.
-- L'hôte voit des boutons +/−, les autres voient uniquement les valeurs.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer

-- Attente des events
local eventsFolder = ReplicatedStorage:WaitForChild("GameSettingsEvents")
local stateEvent   = eventsFolder:WaitForChild("State")
local updateEvent  = eventsFolder:WaitForChild("Update")

-- ===== Construction du GUI =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name            = "SettingsMenuGui"
screenGui.ResetOnSpawn    = false
screenGui.IgnoreGuiInset  = true
screenGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
screenGui.Parent          = localPlayer.PlayerGui

local PANEL_WIDTH = 300
local ROW_H       = 52
local PADDING     = 12

-- Cadre principal (ancré en haut-droit, sous le timer)
local panel = Instance.new("Frame")
panel.Name                    = "Panel"
panel.Size                    = UDim2.new(0, PANEL_WIDTH, 0, 0)
panel.Position                = UDim2.new(1, -PANEL_WIDTH - 16, 0, 74)
panel.BackgroundColor3        = Color3.fromRGB(18, 18, 22)
panel.BackgroundTransparency  = 0.15
panel.BorderSizePixel         = 0
panel.AutomaticSize           = Enum.AutomaticSize.Y
panel.Visible                 = false
panel.Parent                  = screenGui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)

local uiPad = Instance.new("UIPadding", panel)
uiPad.PaddingTop    = UDim.new(0, PADDING)
uiPad.PaddingBottom = UDim.new(0, PADDING)
uiPad.PaddingLeft   = UDim.new(0, PADDING)
uiPad.PaddingRight  = UDim.new(0, PADDING)

local layout = Instance.new("UIListLayout", panel)
layout.SortOrder     = Enum.SortOrder.LayoutOrder
layout.Padding       = UDim.new(0, 8)
layout.FillDirection = Enum.FillDirection.Vertical

-- Titre
local titleLabel = Instance.new("TextLabel", panel)
titleLabel.Name          = "Title"
titleLabel.Size          = UDim2.new(1, 0, 0, 36)
titleLabel.LayoutOrder   = 0
titleLabel.BackgroundTransparency = 1
titleLabel.Font          = Enum.Font.GothamBold
titleLabel.TextSize      = 18
titleLabel.TextColor3    = Color3.fromRGB(255, 255, 255)
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Text          = "PROCHAIN MODE"

-- Tag host
local hostTag = Instance.new("TextLabel", panel)
hostTag.Name             = "HostTag"
hostTag.Size             = UDim2.new(1, 0, 0, 22)
hostTag.LayoutOrder      = 1
hostTag.BackgroundColor3 = Color3.fromRGB(255, 190, 0)
hostTag.BackgroundTransparency = 0
hostTag.Font             = Enum.Font.GothamBold
hostTag.TextSize         = 12
hostTag.TextColor3       = Color3.fromRGB(30, 20, 0)
hostTag.Text             = "★ VOUS ÊTES L'HÔTE — modifiez les réglages"
hostTag.Visible          = false
Instance.new("UICorner", hostTag).CornerRadius = UDim.new(0, 5)

-- Conteneur des lignes de settings (supprimé/recréé à chaque panel open)
local rowsContainer = Instance.new("Frame", panel)
rowsContainer.Name               = "Rows"
rowsContainer.Size               = UDim2.new(1, 0, 0, 0)
rowsContainer.AutomaticSize      = Enum.AutomaticSize.Y
rowsContainer.BackgroundTransparency = 1
rowsContainer.LayoutOrder        = 2
local rowsLayout = Instance.new("UIListLayout", rowsContainer)
rowsLayout.SortOrder   = Enum.SortOrder.LayoutOrder
rowsLayout.Padding     = UDim.new(0, 6)

-- Hint bas
local hintLabel = Instance.new("TextLabel", panel)
hintLabel.Name               = "Hint"
hintLabel.Size               = UDim2.new(1, 0, 0, 18)
hintLabel.LayoutOrder        = 3
hintLabel.BackgroundTransparency = 1
hintLabel.Font               = Enum.Font.Gotham
hintLabel.TextSize           = 11
hintLabel.TextColor3         = Color3.fromRGB(160, 160, 160)
hintLabel.TextXAlignment     = Enum.TextXAlignment.Left
hintLabel.Text               = "Réglages remis à zéro au prochain tour"

-- ===== Helpers UI =====
local function formatValue(value, step)
	if step and step < 1 then
		-- Affiche autant de décimales que le step en a
		local decimals = math.ceil(-math.log10(step))
		return string.format("%." .. decimals .. "f", value)
	end
	return tostring(math.floor(value + 0.5))
end

local function makeRow(entry, currentValue, isHost, order)
	local row = Instance.new("Frame")
	row.Name               = "Row_" .. entry.key
	row.Size               = UDim2.new(1, 0, 0, ROW_H)
	row.BackgroundColor3   = Color3.fromRGB(35, 35, 42)
	row.BackgroundTransparency = 0
	row.LayoutOrder        = order
	row.Parent             = rowsContainer
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 7)

	-- Label
	local lbl = Instance.new("TextLabel", row)
	lbl.Size              = UDim2.new(1, -10, 0, 18)
	lbl.Position          = UDim2.new(0, 10, 0, 6)
	lbl.BackgroundTransparency = 1
	lbl.Font              = Enum.Font.Gotham
	lbl.TextSize          = 12
	lbl.TextColor3        = Color3.fromRGB(200, 200, 210)
	lbl.TextXAlignment    = Enum.TextXAlignment.Left
	lbl.Text              = entry.label

	-- Valeur
	local valLabel = Instance.new("TextLabel", row)
	valLabel.Name          = "Value"
	valLabel.Size          = UDim2.new(0, 80, 0, 22)
	valLabel.Position      = UDim2.new(0.5, -40, 1, -28)
	valLabel.BackgroundTransparency = 1
	valLabel.Font          = Enum.Font.GothamBold
	valLabel.TextSize      = 16
	valLabel.TextColor3    = Color3.fromRGB(255, 255, 255)
	valLabel.TextXAlignment = Enum.TextXAlignment.Center
	valLabel.Text          = formatValue(currentValue, entry.step)

	if isHost then
		local btnStyle = function(btn)
			btn.Size              = UDim2.new(0, 32, 0, 22)
			btn.BackgroundColor3  = Color3.fromRGB(60, 60, 80)
			btn.Font              = Enum.Font.GothamBold
			btn.TextSize          = 18
			btn.TextColor3        = Color3.fromRGB(255, 255, 255)
			btn.AutoButtonColor   = true
			Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
		end

		local minusBtn = Instance.new("TextButton", row)
		minusBtn.Name     = "Minus"
		minusBtn.Position = UDim2.new(0.5, -56, 1, -28)
		minusBtn.Text     = "−"
		btnStyle(minusBtn)
		minusBtn.MouseButton1Click:Connect(function()
			updateEvent:FireServer(entry.key, -(entry.step or 1))
		end)

		local plusBtn = Instance.new("TextButton", row)
		plusBtn.Name     = "Plus"
		plusBtn.Position = UDim2.new(0.5, 24, 1, -28)
		plusBtn.Text     = "+"
		btnStyle(plusBtn)
		plusBtn.MouseButton1Click:Connect(function()
			updateEvent:FireServer(entry.key, entry.step or 1)
		end)
	end

	return row
end

-- ===== Logique principale =====
local function rebuildRows(schema, settings, isHost)
	rowsContainer:ClearAllChildren()
	Instance.new("UIListLayout", rowsContainer).Padding = UDim.new(0, 6)
	for i, entry in schema do
		makeRow(entry, settings[entry.key], isHost, i)
	end
end

local function showPanel(data)
	local isHost = (data.hostId == localPlayer.UserId)
	titleLabel.Text = "🎮 PROCHAIN MODE : " .. string.upper(data.gamemodeName)
	hostTag.Visible = isHost
	rebuildRows(data.schema, data.settings, isHost)
	panel.Visible = true
end

local function hidePanel()
	panel.Visible = false
end

stateEvent.OnClientEvent:Connect(function(data)
	if data.open then
		showPanel(data)
	else
		hidePanel()
	end
end)
