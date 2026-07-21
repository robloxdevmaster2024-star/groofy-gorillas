--!nonstrict
-- PlayButton.client.luau — Bouton "JOUER" bas-centre : ouvre un menu de
-- sélection de gamemode puis lance la recherche de serveur (file d'attente),
-- sans avoir besoin de marcher physiquement sur une zone.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

local lobbyFolder       = ReplicatedStorage:WaitForChild("LobbyEvents")
local playerZoneEvent   = lobbyFolder:WaitForChild("PlayerZone")
local requestJoinEvent  = lobbyFolder:WaitForChild("RequestJoinQueue")
local requestLeaveEvent = lobbyFolder:WaitForChild("RequestLeaveQueue")
local getGamemodesFunc  = lobbyFolder:WaitForChild("GetGamemodes")

-- ===== État local =====
local searching   = false -- true dès qu'on a rejoint une file (via bouton ou zone)
local menuOpen    = false
local gamemodes   : { { name: string, description: string, minPlayers: number } } = {}

local ZONE_COLORS = {
	Infector  = Color3.fromRGB(220, 50,  50),
	Dodgeball = Color3.fromRGB(50,  100, 220),
}
local DEFAULT_COLOR = Color3.fromRGB(120, 90, 200)

-- ===== GUI =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "PlayButtonGui"
screenGui.ResetOnSpawn   = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent         = localPlayer.PlayerGui

-- Bouton principal "JOUER"
local playButton = Instance.new("TextButton")
playButton.Name                   = "PlayButton"
playButton.Size                   = UDim2.new(0, 220, 0, 56)
playButton.Position               = UDim2.new(0.5, -110, 1, -96)
playButton.AnchorPoint             = Vector2.new(0, 0)
playButton.BackgroundColor3       = Color3.fromRGB(80, 200, 90)
playButton.AutoButtonColor        = true
playButton.Font                   = Enum.Font.GothamBold
playButton.TextSize               = 22
playButton.TextColor3             = Color3.fromRGB(255, 255, 255)
playButton.Text                   = "▶  JOUER"
playButton.BorderSizePixel        = 0
playButton.ZIndex                 = 10
playButton.Parent                 = screenGui
Instance.new("UICorner", playButton).CornerRadius = UDim.new(0, 14)

local buttonStroke = Instance.new("UIStroke", playButton)
buttonStroke.Color     = Color3.fromRGB(255, 255, 255)
buttonStroke.Thickness = 1.5
buttonStroke.Transparency = 0.6

-- ===== Menu de sélection de gamemode =====
local menu = Instance.new("Frame")
menu.Name                   = "GamemodeMenu"
menu.Size                   = UDim2.new(0, 260, 0, 0)
menu.AutomaticSize          = Enum.AutomaticSize.Y
menu.Position               = UDim2.new(0.5, -130, 1, -96 - 12)
menu.AnchorPoint            = Vector2.new(0, 1)
menu.BackgroundColor3       = Color3.fromRGB(16, 14, 22)
menu.BackgroundTransparency = 0.08
menu.BorderSizePixel        = 0
menu.Visible                = false
menu.ZIndex                 = 10
menu.Parent                 = screenGui
Instance.new("UICorner", menu).CornerRadius = UDim.new(0, 12)

local menuList = Instance.new("UIListLayout", menu)
menuList.Padding    = UDim.new(0, 6)
menuList.SortOrder  = Enum.SortOrder.LayoutOrder

local menuPadding = Instance.new("UIPadding", menu)
menuPadding.PaddingTop    = UDim.new(0, 10)
menuPadding.PaddingBottom = UDim.new(0, 10)
menuPadding.PaddingLeft   = UDim.new(0, 10)
menuPadding.PaddingRight  = UDim.new(0, 10)

local menuTitle = Instance.new("TextLabel", menu)
menuTitle.Size               = UDim2.new(1, 0, 0, 24)
menuTitle.BackgroundTransparency = 1
menuTitle.Font               = Enum.Font.GothamBold
menuTitle.TextSize           = 15
menuTitle.TextColor3         = Color3.fromRGB(230, 230, 235)
menuTitle.Text               = "CHOISIS UN MODE"
menuTitle.LayoutOrder        = 0

local function clearGamemodeButtons()
	for _, child in menu:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

-- ===== Recherche en cours (overlay + annulation) =====
local searchingFrame = Instance.new("Frame")
searchingFrame.Name                   = "SearchingFrame"
searchingFrame.Size                   = UDim2.new(0, 220, 0, 56)
searchingFrame.Position               = UDim2.new(0.5, -110, 1, -96)
searchingFrame.BackgroundColor3       = Color3.fromRGB(40, 38, 48)
searchingFrame.BorderSizePixel        = 0
searchingFrame.Visible                = false
searchingFrame.ZIndex                 = 10
searchingFrame.Parent                 = screenGui
Instance.new("UICorner", searchingFrame).CornerRadius = UDim.new(0, 14)

local searchingLabel = Instance.new("TextLabel", searchingFrame)
searchingLabel.Size               = UDim2.new(1, -40, 1, 0)
searchingLabel.Position           = UDim2.new(0, 12, 0, 0)
searchingLabel.BackgroundTransparency = 1
searchingLabel.Font               = Enum.Font.GothamBold
searchingLabel.TextSize           = 15
searchingLabel.TextColor3         = Color3.fromRGB(230, 230, 235)
searchingLabel.TextXAlignment     = Enum.TextXAlignment.Left
searchingLabel.Text               = "🔎 Recherche…"

local cancelButton = Instance.new("TextButton")
cancelButton.Name               = "Cancel"
cancelButton.Size               = UDim2.new(0, 34, 0, 34)
cancelButton.Position           = UDim2.new(1, -44, 0.5, -17)
cancelButton.BackgroundColor3   = Color3.fromRGB(200, 60, 60)
cancelButton.Font               = Enum.Font.GothamBold
cancelButton.TextSize           = 18
cancelButton.TextColor3         = Color3.fromRGB(255, 255, 255)
cancelButton.Text               = "✕"
cancelButton.BorderSizePixel    = 0
cancelButton.ZIndex             = 11
cancelButton.Parent             = searchingFrame
Instance.new("UICorner", cancelButton).CornerRadius = UDim.new(0, 10)

-- ===== Comportement =====
local function setSearching(isSearching: boolean)
	searching = isSearching
	playButton.Visible     = not isSearching
	searchingFrame.Visible = isSearching
	if isSearching then
		menu.Visible = false
		menuOpen = false
	end
end

local function closeMenu()
	menuOpen     = false
	menu.Visible = false
end

local function openMenu()
	if searching then return end

	-- (Re)construit la liste à partir des données serveur les plus récentes
	clearGamemodeButtons()
	for i, gm in gamemodes do
		local btn = Instance.new("TextButton")
		btn.Name               = gm.name
		btn.Size               = UDim2.new(1, 0, 0, 46)
		btn.BackgroundColor3   = ZONE_COLORS[gm.name] or DEFAULT_COLOR
		btn.Font               = Enum.Font.GothamBold
		btn.TextSize           = 15
		btn.TextColor3         = Color3.fromRGB(255, 255, 255)
		btn.Text               = gm.name:upper() .. "  (" .. gm.minPlayers .. "+ joueurs)"
		btn.BorderSizePixel    = 0
		btn.LayoutOrder        = i
		btn.ZIndex             = 10
		btn.Parent             = menu
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)

		btn.MouseButton1Click:Connect(function()
			requestJoinEvent:FireServer(gm.name)
			closeMenu()
		end)
	end

	menu.Visible = true
	menuOpen     = true
end

playButton.MouseButton1Click:Connect(function()
	if menuOpen then
		closeMenu()
	else
		-- Rafraîchit la liste des gamemodes à chaque ouverture (au cas où)
		local ok, result = pcall(function()
			return getGamemodesFunc:InvokeServer()
		end)
		if ok and result then
			gamemodes = result
		end
		openMenu()
	end
end)

cancelButton.MouseButton1Click:Connect(function()
	requestLeaveEvent:FireServer()
end)

-- ===== Synchronisation avec l'état serveur (zone / file) =====
playerZoneEvent.OnClientEvent:Connect(function(data)
	setSearching(data.gamemodeName ~= nil)
end)

-- Chargement initial de la liste des gamemodes (asynchrone, ne bloque pas l'affichage du bouton)
task.spawn(function()
	local ok, result = pcall(function()
		return getGamemodesFunc:InvokeServer()
	end)
	if ok and result then
		gamemodes = result
	end
end)
