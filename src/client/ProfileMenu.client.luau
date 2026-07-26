--!nonstrict
-- ProfileMenu.client.luau — Bouton "Profil" (haut-gauche) → panneau à onglets :
-- Profil (niveau/XP/GP/victoires/streaks), Succès (débloqués), Cosmétiques (placeholder,
-- système pas encore décidé, voir ROADMAP), Réglages (volume musique/SFX perso).
--
-- La plupart des données viennent de DataService.GetProfileSnapshot (RemoteFunction), rafraîchi
-- à l'ouverture du panneau. Niveau/GP/XP en revanche restent à jour EN DIRECT tant que le
-- panneau est ouvert, sans polling : on écoute juste `DataUpdated` (déjà diffusé par
-- DataService à chaque gain de GP pour animer le HUD) et on ne retouche l'affichage que si ce
-- panneau est actuellement visible — zéro appel réseau ni boucle supplémentaire.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")

local localPlayer = Players.LocalPlayer

local GetProfileSnapshot   = ReplicatedStorage:WaitForChild("GetProfileSnapshot")
local UpdatePlayerSettings = ReplicatedStorage:WaitForChild("UpdatePlayerSettings")
local DataUpdated          = ReplicatedStorage:WaitForChild("DataUpdated")
local AchievementsConfig   = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("AchievementsConfig")
)
local PlayerConfig = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("PlayerConfig")
)
local PanelCoordinator = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("PanelCoordinator")
)
local PANEL_ID = "profile"

local musicGroup = SoundService:WaitForChild("Music")
local sfxGroup   = SoundService:WaitForChild("SFX")

-- ===== Constantes UI (même palette que LeaderboardGui.client.luau) =====
local PANEL_W   = 440
local PANEL_H   = 480
local HEADER_H  = 44
local TABS_H    = 36
local COLOR_BG  = Color3.fromRGB(14, 14, 18)
local COLOR_ROW = Color3.fromRGB(28, 28, 36)
local COLOR_TXT = Color3.fromRGB(230, 230, 235)
local COLOR_DIM = Color3.fromRGB(140, 140, 150)
local COLOR_TOP = Color3.fromRGB(255, 210, 30)
local COLOR_TAB_ACTIVE   = Color3.fromRGB(60, 55, 30)
local COLOR_TAB_INACTIVE = Color3.fromRGB(24, 24, 30)

local ACHIEVEMENT_BY_ID = {}
for _, entry in AchievementsConfig do
	ACHIEVEMENT_BY_ID[entry.id] = entry
end

-- ===== Construction du GUI =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "ProfileMenuGui"
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

-- Titre
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
titleLabel.Text               = "👤  PROFIL"

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

-- Barre d'onglets
local tabsBar = Instance.new("Frame", panel)
tabsBar.Name              = "Tabs"
tabsBar.Size              = UDim2.new(1, -24, 0, TABS_H)
tabsBar.Position          = UDim2.new(0, 12, 0, HEADER_H + 8)
tabsBar.BackgroundTransparency = 1
local tabsLayout = Instance.new("UIListLayout", tabsBar)
tabsLayout.FillDirection = Enum.FillDirection.Horizontal
tabsLayout.Padding       = UDim.new(0, 6)
tabsLayout.SortOrder     = Enum.SortOrder.LayoutOrder

-- Conteneur des pages (une par onglet)
local pagesContainer = Instance.new("Frame", panel)
pagesContainer.Name              = "Pages"
pagesContainer.Size              = UDim2.new(1, -24, 1, -(HEADER_H + TABS_H + 20))
pagesContainer.Position          = UDim2.new(0, 12, 0, HEADER_H + TABS_H + 12)
pagesContainer.BackgroundTransparency = 1

-- ===== Bouton de toggle (toujours visible) =====
-- Pas en haut-gauche (0,14,0,14) : ce coin est caché par les icônes natives du menu Roblox
-- (paramètres/liste des joueurs) sur certaines résolutions/plateformes. Placé à la place du
-- bouton "🏆 Classement global" (LeaderboardGui.client.luau), qui a été décalé à droite (0,64,0,74).
local toggleBtn = Instance.new("TextButton", screenGui)
toggleBtn.Name             = "ToggleBtn"
toggleBtn.Size             = UDim2.new(0, 42, 0, 42)
toggleBtn.Position         = UDim2.new(0, 14, 0, 74)
toggleBtn.BackgroundColor3 = Color3.fromRGB(40, 36, 20)
toggleBtn.Font             = Enum.Font.GothamBold
toggleBtn.TextSize         = 22
toggleBtn.TextColor3       = COLOR_TOP
toggleBtn.Text             = "👤"
toggleBtn.AutoButtonColor  = true
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 8)

-- ===== Helpers génériques =====
local function makePage(name)
	local page = Instance.new("ScrollingFrame", pagesContainer)
	page.Name                   = name
	page.Size                   = UDim2.new(1, 0, 1, 0)
	page.BackgroundTransparency = 1
	page.BorderSizePixel        = 0
	page.ScrollBarThickness     = 4
	page.ScrollBarImageColor3   = Color3.fromRGB(80, 80, 100)
	page.CanvasSize             = UDim2.new(0, 0, 0, 0)
	page.AutomaticCanvasSize    = Enum.AutomaticSize.Y
	page.Visible                = false
	local layout = Instance.new("UIListLayout", page)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding   = UDim.new(0, 8)
	return page
end

local function placeholderLabel(parent, text, order)
	local lbl = Instance.new("TextLabel", parent)
	lbl.Size               = UDim2.new(1, 0, 0, 50)
	lbl.BackgroundTransparency = 1
	lbl.Font               = Enum.Font.Gotham
	lbl.TextSize           = 14
	lbl.TextColor3         = COLOR_DIM
	lbl.TextWrapped        = true
	lbl.Text               = text
	lbl.LayoutOrder        = order or 0
	return lbl
end

-- ===== Onglet "Profil" =====
local profilePage = makePage("Profil")

local function statRow(parent, order)
	local row = Instance.new("Frame", parent)
	row.Name        = "Row"
	row.Size        = UDim2.new(1, 0, 0, 44)
	row.BackgroundColor3 = COLOR_ROW
	row.BackgroundTransparency = 0.1
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 7)

	local lbl = Instance.new("TextLabel", row)
	lbl.Size               = UDim2.new(0.55, 0, 1, 0)
	lbl.Position            = UDim2.new(0, 12, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Font               = Enum.Font.Gotham
	lbl.TextSize           = 14
	lbl.TextColor3         = COLOR_DIM
	lbl.TextXAlignment     = Enum.TextXAlignment.Left

	local val = Instance.new("TextLabel", row)
	val.Size               = UDim2.new(0.4, -12, 1, 0)
	val.Position            = UDim2.new(0.6, 0, 0, 0)
	val.BackgroundTransparency = 1
	val.Font               = Enum.Font.GothamBold
	val.TextSize           = 16
	val.TextColor3         = COLOR_TXT
	val.TextXAlignment     = Enum.TextXAlignment.Right

	return row, lbl, val
end

local _, levelLbl, levelVal = statRow(profilePage, 1)
levelLbl.Text = "Niveau"

-- Barre XP (sous la ligne niveau)
local xpBarBg = Instance.new("Frame", profilePage)
xpBarBg.Name              = "XpBar"
xpBarBg.Size              = UDim2.new(1, 0, 0, 10)
xpBarBg.BackgroundColor3  = Color3.fromRGB(50, 50, 60)
xpBarBg.BorderSizePixel   = 0
xpBarBg.LayoutOrder       = 2
Instance.new("UICorner", xpBarBg).CornerRadius = UDim.new(1, 0)
local xpBarFill = Instance.new("Frame", xpBarBg)
xpBarFill.Size             = UDim2.new(0, 0, 1, 0)
xpBarFill.BackgroundColor3 = Color3.fromRGB(120, 220, 100)
xpBarFill.BorderSizePixel  = 0
Instance.new("UICorner", xpBarFill).CornerRadius = UDim.new(1, 0)
local xpLabel = Instance.new("TextLabel", profilePage)
xpLabel.Size               = UDim2.new(1, 0, 0, 18)
xpLabel.BackgroundTransparency = 1
xpLabel.Font               = Enum.Font.Gotham
xpLabel.TextSize           = 12
xpLabel.TextColor3         = COLOR_DIM
xpLabel.TextXAlignment     = Enum.TextXAlignment.Left
xpLabel.LayoutOrder        = 3

local _, gpLbl, gpVal = statRow(profilePage, 4)
gpLbl.Text = "Goofy Points"

local _, winsLbl, winsVal = statRow(profilePage, 5)
winsLbl.Text = "Victoires (total)"

local _, playedLbl, playedVal = statRow(profilePage, 6)
playedLbl.Text = "Parties jouées"

-- ===== Sections par gamemode (titre du mode + détails propres à ce mode) =====
-- Un bloc par gamemode déjà joué. Clown Survival a des détails dédiés (rôles, éliminations,
-- série) ; tout autre mode retombe sur un résumé générique (série de victoires) tant qu'il n'a
-- pas ses propres stats persistées — quand un nouveau mode sera ajouté avec ses propres stats
-- (ex. futures stats Dodgeball), lui donner le même traitement : un titre (nom du mode) suivi de
-- ses lignes de détail, sur ce même modèle.
local modesSection = Instance.new("Frame", profilePage)
modesSection.Name              = "ModesSection"
modesSection.Size              = UDim2.new(1, 0, 0, 0)
modesSection.AutomaticSize     = Enum.AutomaticSize.Y
modesSection.BackgroundTransparency = 1
modesSection.LayoutOrder       = 7
local modesLayout = Instance.new("UIListLayout", modesSection)
modesLayout.SortOrder = Enum.SortOrder.LayoutOrder
modesLayout.Padding   = UDim.new(0, 8)

local function modeTitle(parent, text, order)
	local lbl = Instance.new("TextLabel", parent)
	lbl.Size               = UDim2.new(1, 0, 0, 22)
	lbl.BackgroundTransparency = 1
	lbl.Font               = Enum.Font.GothamBold
	lbl.TextSize           = 13
	lbl.TextColor3         = COLOR_TOP
	lbl.TextXAlignment     = Enum.TextXAlignment.Left
	lbl.LayoutOrder        = order
	lbl.Text               = string.upper(text)
	return lbl
end

local function streakRow(parent, order, winStreaks, bestStreaks, gamemodeName)
	local _, lbl, val = statRow(parent, order)
	lbl.Text = "Série de victoires"
	val.Text = string.format("%d actuelle · %d record", winStreaks[gamemodeName] or 0, bestStreaks[gamemodeName] or 0)
	val.TextSize = 13
end

local function rebuildModesSection(snapshot)
	modesSection:ClearAllChildren()
	local newLayout = Instance.new("UIListLayout", modesSection)
	newLayout.SortOrder = Enum.SortOrder.LayoutOrder
	newLayout.Padding   = UDim.new(0, 8)

	local winStreaks  = snapshot.winStreaks or {}
	local bestStreaks = snapshot.bestStreaks or {}

	local names = {}
	for name in bestStreaks do table.insert(names, name) end
	table.sort(names)

	if #names == 0 then
		placeholderLabel(modesSection, "Aucune partie jouée pour l'instant.", 0)
		return
	end

	local order = 0
	for _, name in names do
		order += 1
		modeTitle(modesSection, name, order)

		if name == "Clown Survival" then
			order += 1
			local _, l1, v1 = statRow(modesSection, order)
			l1.Text = "Victoire en tant que clown"
			v1.Text = tostring(snapshot.clownWins or 0)

			order += 1
			local _, l2, v2 = statRow(modesSection, order)
			l2.Text = "Victoire en tant qu'enfant"
			v2.Text = tostring(snapshot.survivorWins or 0)

			order += 1
			local _, l3, v3 = statRow(modesSection, order)
			l3.Text = "Éliminations"
			v3.Text = tostring(snapshot.totalClownKills or 0)

			order += 1
			streakRow(modesSection, order, winStreaks, bestStreaks, name)
		else
			order += 1
			streakRow(modesSection, order, winStreaks, bestStreaks, name)
		end
	end
end

-- ===== Onglet "Succès" =====
local achievementsPage = makePage("Succès")

local function rebuildAchievements(unlockedIds)
	achievementsPage:ClearAllChildren()
	local layout = Instance.new("UIListLayout", achievementsPage)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding   = UDim.new(0, 6)

	if #unlockedIds == 0 then
		placeholderLabel(achievementsPage, "Aucun succès débloqué pour l'instant — fonce sur les rounds !", 0)
		return
	end

	for i, id in unlockedIds do
		local entry = ACHIEVEMENT_BY_ID[id]
		if entry then
			local row = Instance.new("Frame", achievementsPage)
			row.Size              = UDim2.new(1, 0, 0, 52)
			row.BackgroundColor3  = COLOR_ROW
			row.BackgroundTransparency = 0.1
			row.BorderSizePixel   = 0
			row.LayoutOrder       = i
			Instance.new("UICorner", row).CornerRadius = UDim.new(0, 7)

			local icon = Instance.new("TextLabel", row)
			icon.Size               = UDim2.new(0, 44, 1, 0)
			icon.BackgroundTransparency = 1
			icon.Font               = Enum.Font.GothamBold
			icon.TextSize           = 24
			icon.Text               = entry.icon or "🏅"

			local name = Instance.new("TextLabel", row)
			name.Size               = UDim2.new(1, -56, 0, 24)
			name.Position           = UDim2.new(0, 48, 0, 4)
			name.BackgroundTransparency = 1
			name.Font               = Enum.Font.GothamBold
			name.TextSize           = 14
			name.TextColor3         = COLOR_TOP
			name.TextXAlignment     = Enum.TextXAlignment.Left
			name.Text               = entry.name

			local desc = Instance.new("TextLabel", row)
			desc.Size               = UDim2.new(1, -56, 0, 20)
			desc.Position           = UDim2.new(0, 48, 0, 26)
			desc.BackgroundTransparency = 1
			desc.Font               = Enum.Font.Gotham
			desc.TextSize           = 12
			desc.TextColor3         = COLOR_DIM
			desc.TextXAlignment     = Enum.TextXAlignment.Left
			desc.Text               = entry.desc
		end
	end
end

-- ===== Onglet "Cosmétiques" (placeholder — système pas encore décidé, voir ROADMAP) =====
local cosmeticsPage = makePage("Cosmétiques")
placeholderLabel(
	cosmeticsPage,
	"🚧 Bientôt disponible !\n\nLe système de cosmétiques (boutique, équipement) n'est pas encore en place — reviens plus tard.",
	0
)

-- ===== Onglet "Réglages" =====
local settingsPage = makePage("Réglages")

local SETTINGS_SCHEMA = {
	{ key = "musicVolume", label = "Volume musique", group = musicGroup },
	{ key = "sfxVolume",   label = "Volume effets sonores", group = sfxGroup },
}
local VOLUME_STEP = 0.1

local settingsValueLabels = {}

local function makeSettingRow(entry, order)
	local row = Instance.new("Frame", settingsPage)
	row.Size              = UDim2.new(1, 0, 0, 56)
	row.BackgroundColor3  = COLOR_ROW
	row.BackgroundTransparency = 0.1
	row.BorderSizePixel   = 0
	row.LayoutOrder       = order
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 7)

	local lbl = Instance.new("TextLabel", row)
	lbl.Size               = UDim2.new(1, -20, 0, 20)
	lbl.Position            = UDim2.new(0, 12, 0, 6)
	lbl.BackgroundTransparency = 1
	lbl.Font               = Enum.Font.Gotham
	lbl.TextSize           = 13
	lbl.TextColor3         = COLOR_DIM
	lbl.TextXAlignment     = Enum.TextXAlignment.Left
	lbl.Text               = entry.label

	local valLabel = Instance.new("TextLabel", row)
	valLabel.Size          = UDim2.new(0, 80, 0, 24)
	valLabel.Position      = UDim2.new(0.5, -40, 1, -30)
	valLabel.BackgroundTransparency = 1
	valLabel.Font          = Enum.Font.GothamBold
	valLabel.TextSize      = 16
	valLabel.TextColor3    = COLOR_TXT
	valLabel.TextXAlignment = Enum.TextXAlignment.Center
	settingsValueLabels[entry.key] = valLabel

	local function btnStyle(btn)
		btn.Size              = UDim2.new(0, 32, 0, 24)
		btn.BackgroundColor3  = Color3.fromRGB(60, 60, 80)
		btn.Font              = Enum.Font.GothamBold
		btn.TextSize          = 18
		btn.TextColor3        = Color3.fromRGB(255, 255, 255)
		btn.AutoButtonColor   = true
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
	end

	local function applyDelta(delta)
		local current = entry.group.Volume
		local newValue = math.clamp(current + delta, 0, 1)
		entry.group.Volume = newValue
		valLabel.Text = string.format("%d%%", math.floor(newValue * 100 + 0.5))
		UpdatePlayerSettings:FireServer(entry.key, newValue)
	end

	local minusBtn = Instance.new("TextButton", row)
	minusBtn.Position = UDim2.new(0.5, -56, 1, -30)
	minusBtn.Text     = "-"
	btnStyle(minusBtn)
	minusBtn.MouseButton1Click:Connect(function() applyDelta(-VOLUME_STEP) end)

	local plusBtn = Instance.new("TextButton", row)
	plusBtn.Position = UDim2.new(0.5, 24, 1, -30)
	plusBtn.Text     = "+"
	btnStyle(plusBtn)
	plusBtn.MouseButton1Click:Connect(function() applyDelta(VOLUME_STEP) end)
end

for i, entry in SETTINGS_SCHEMA do
	makeSettingRow(entry, i)
end

local function applySettingsToUI(settings)
	for _, entry in SETTINGS_SCHEMA do
		local value = (settings and settings[entry.key]) or 0.5
		entry.group.Volume = value
		local lbl = settingsValueLabels[entry.key]
		if lbl then
			lbl.Text = string.format("%d%%", math.floor(value * 100 + 0.5))
		end
	end
end

-- ===== Onglets : bascule =====
local pages = {
	["Profil"]      = profilePage,
	["Succès"]      = achievementsPage,
	["Cosmétiques"] = cosmeticsPage,
	["Réglages"]    = settingsPage,
}
local tabButtons = {}

local function selectTab(name)
	for pageName, page in pages do
		page.Visible = (pageName == name)
	end
	for tabName, btn in tabButtons do
		btn.BackgroundColor3 = (tabName == name) and COLOR_TAB_ACTIVE or COLOR_TAB_INACTIVE
		btn.TextColor3       = (tabName == name) and COLOR_TOP or COLOR_DIM
	end
end

for _, name in { "Profil", "Succès", "Cosmétiques", "Réglages" } do
	local btn = Instance.new("TextButton", tabsBar)
	btn.Name              = name
	btn.Size              = UDim2.new(0, 96, 1, 0)
	btn.BackgroundColor3  = COLOR_TAB_INACTIVE
	btn.Font              = Enum.Font.GothamBold
	btn.TextSize          = 13
	btn.TextColor3        = COLOR_DIM
	btn.Text              = name
	btn.AutoButtonColor   = true
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
	btn.MouseButton1Click:Connect(function() selectTab(name) end)
	tabButtons[name] = btn
end

-- ===== Chargement des données =====

-- Niveau/GP/barre XP : seuils calculés côté client via PlayerConfig (partagé, déjà utilisé par
-- PlayerStats.client.luau pour le HUD) plutôt que renvoyés par le serveur, pour pouvoir se
-- rafraîchir sur un simple événement `DataUpdated` (goofyPoints/level) sans réinvoquer
-- GetProfileSnapshot à chaque gain de GP.
local function applyLevelGP(goofyPoints: number, level: number)
	levelVal.Text = tostring(level)
	gpVal.Text    = tostring(goofyPoints) .. " GP"

	local lo = PlayerConfig.LEVEL_THRESHOLDS[level] or 0
	local hi = PlayerConfig.LEVEL_THRESHOLDS[level + 1]
	if hi and hi > lo then
		local progress = math.clamp((goofyPoints - lo) / (hi - lo), 0, 1)
		xpBarFill.Size = UDim2.new(progress, 0, 1, 0)
		xpLabel.Text   = string.format("%d / %d XP jusqu'au niveau suivant", goofyPoints - lo, hi - lo)
	else
		xpBarFill.Size = UDim2.new(1, 0, 1, 0)
		xpLabel.Text   = "Niveau maximum atteint"
	end
end

-- Écoute EN CONTINU (pas seulement à l'ouverture) : ne fait rien tant que le panneau n'est pas
-- affiché, donc coût nul le reste du temps — juste une mise à jour de texte quand un gain de GP
-- arrive vraiment pendant que le panneau est ouvert.
DataUpdated.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or not panel.Visible then return end
	applyLevelGP(payload.goofyPoints or 0, payload.level or 1)
end)

local function refresh()
	local ok, snapshot = pcall(function()
		return GetProfileSnapshot:InvokeServer()
	end)
	if not ok or not snapshot then return end

	applyLevelGP(snapshot.goofyPoints, snapshot.level)
	winsVal.Text  = tostring(snapshot.gamesWon)
	playedVal.Text = tostring(snapshot.gamesPlayed)

	rebuildModesSection(snapshot)
	rebuildAchievements(snapshot.unlockedAchievements or {})
	applySettingsToUI(snapshot.settings)
end

-- ===== Toggle panneau =====
local function setVisible(v: boolean)
	panel.Visible = v
	if v then
		-- Notifier AVANT refresh() : refresh() invoque une RemoteFunction (aller-retour réseau
		-- bloquant) pour récupérer le snapshot du profil — si on notifiait après, les autres
		-- panneaux mettraient ce délai réseau à se fermer au lieu de disparaître instantanément.
		PanelCoordinator.NotifyOpened(PANEL_ID)
		refresh()
	end
end
toggleBtn.MouseButton1Click:Connect(function() setVisible(not panel.Visible) end)
closeBtn.MouseButton1Click:Connect(function() setVisible(false) end)

-- Un AUTRE panneau (Classement, Effectifs de la partie...) vient de s'ouvrir : le nôtre se ferme
-- s'il était affiché, pour ne pas empiler deux panneaux centrés l'un sur l'autre.
PanelCoordinator.OnPanelOpened(function(openedId)
	if openedId ~= PANEL_ID and panel.Visible then
		panel.Visible = false
	end
end)

selectTab("Profil")

-- ===== Applique le volume sauvegardé dès la connexion (pas besoin d'ouvrir le panneau) =====
task.spawn(function()
	for _ = 1, 20 do -- ProfileStore peut prendre quelques secondes à charger (session-lock, retries)
		local ok, snapshot = pcall(function()
			return GetProfileSnapshot:InvokeServer()
		end)
		if ok and snapshot then
			applySettingsToUI(snapshot.settings)
			return
		end
		task.wait(1)
	end
end)
