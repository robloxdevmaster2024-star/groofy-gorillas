--!nonstrict
-- EndScreen.client.luau — Écran de fin de partie : classement des participants (gagnants en
-- tête, triés par GP gagnés CE round), récompense mise en avant, bouton "Rejouer" (relance la
-- recherche pour le MÊME gamemode sans repasser par le menu). Reçoit RoundEndSummary (serveur,
-- voir RoundRunner.luau), diffusé uniquement aux participants du round qui vient de se terminer.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer

local RoundEndSummary = ReplicatedStorage:WaitForChild("RoundEndSummary")
local lobbyFolder      = ReplicatedStorage:WaitForChild("LobbyEvents")
local requestJoinEvent = lobbyFolder:WaitForChild("RequestJoinQueue")

local PanelCoordinator = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("PanelCoordinator")
)
local UISound = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("UISound"))
local ButtonHover = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("ButtonHover"))
local PANEL_ID = "endscreen"

local AUTO_DISMISS_DELAY = 10 -- s : le serveur renvoie au lobby ~8s après la fin du round (voir RoundRunner/LobbyService.RETURN_DELAY)

-- Badge "camp gagnant" (quel camp a gagné, ex. Clown Survival, voir summary.winningRole côté
-- serveur), affiché EN PLUS du titre personnel (VICTOIRE/DÉFAITE du point de vue du joueur local,
-- voir show()) — les deux infos sont différentes et toutes les deux utiles : un survivant qui perd
-- individuellement (éliminé tôt) veut quand même savoir si son camp a fini par gagner. Les
-- gamemodes sans rôle (ex. Dodgeball) n'affichent pas ce badge.
local ROLE_BADGE = {
	clown    = { text = "🤡 Victoire des Clowns",  color = Color3.fromRGB(200, 60, 70) },
	survivor = { text = "🧒 Victoire des Enfants", color = Color3.fromRGB(60, 150, 190) },
}

-- Sections du classement, même regroupement/ordre que le panneau "Effectifs de la partie" en
-- direct (ClownSurvivalRoster.client.luau) : Clowns → Enfants → Éliminés. N'apparaît que si le
-- gamemode expose un `role` par participant (Clown Survival) ; sinon liste plate classique.
local ROLE_SECTIONS = {
	{ role = "clown",      header = "🤡 CLOWNS" },
	{ role = "survivor",   header = "🧒 ENFANTS" },
	{ role = "eliminated", header = "💀 ÉLIMINÉS" },
}

local COLOR_BG      = Color3.fromRGB(14, 14, 18)
local COLOR_PANEL   = Color3.fromRGB(22, 22, 28)
local COLOR_ROW     = Color3.fromRGB(30, 30, 38)
local COLOR_TXT     = Color3.fromRGB(230, 230, 235)
local COLOR_DIM     = Color3.fromRGB(150, 150, 160)
local COLOR_TOP     = Color3.fromRGB(255, 210, 30)
local COLOR_ME      = Color3.fromRGB(210, 160, 10)
local COLOR_GP      = Color3.fromRGB(120, 220, 100)
local COLOR_WIN     = Color3.fromRGB(255, 210, 30)
local COLOR_LOSE    = Color3.fromRGB(200, 90, 90)
local COLOR_VOID    = Color3.fromRGB(180, 180, 190)

-- ===== GUI =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "EndScreenGui"
screenGui.ResetOnSpawn   = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder   = 20 -- au-dessus des autres panneaux (classement, profil...)
screenGui.Parent         = localPlayer.PlayerGui

local backdrop = Instance.new("Frame", screenGui)
backdrop.Size               = UDim2.new(1, 0, 1, 0)
backdrop.BackgroundColor3   = Color3.new(0, 0, 0)
backdrop.BackgroundTransparency = 1
backdrop.BorderSizePixel    = 0
backdrop.Visible            = false

local PANEL_W, PANEL_H = 420, 520
local panel = Instance.new("Frame", backdrop)
panel.AnchorPoint       = Vector2.new(0.5, 0.5)
panel.Size               = UDim2.new(0, PANEL_W, 0, PANEL_H)
-- Vrai centre (0.5, 0.5), comme tous les autres panneaux centrés (LeaderboardGui, ProfileMenu,
-- ClownSurvivalRoster) : un centrage biaisé vers le haut (0.44 initialement) combiné à la hauteur
-- de CE panneau (520px, le plus haut du jeu) le collait visuellement en haut de l'écran, surtout
-- sur les petites résolutions/fenêtres de test Studio.
panel.Position           = UDim2.new(0.5, 0, 0.5, 40) -- démarre légèrement plus bas, remonte au fade-in
panel.BackgroundColor3   = COLOR_PANEL
panel.BackgroundTransparency = 1
panel.BorderSizePixel    = 0
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 16)

-- Titre PERSONNEL (point de vue du joueur local) : "ai-je gagné ou perdu, moi" — la question la
-- plus immédiate. Le badge ci-dessous répond à la question complémentaire "qui a gagné la manche".
local titleLbl = Instance.new("TextLabel", panel)
titleLbl.Size               = UDim2.new(1, -24, 0, 38)
titleLbl.Position           = UDim2.new(0, 12, 0, 14)
titleLbl.BackgroundTransparency = 1
titleLbl.Font               = Enum.Font.FredokaOne
titleLbl.TextSize           = 28
titleLbl.TextColor3         = COLOR_WIN
titleLbl.Text               = ""
titleLbl.TextTransparency   = 1

-- Badge camp gagnant (voir ROLE_BADGE) : pastille colorée, bien visible, sous le titre personnel.
-- Masqué (Visible=false) pour les gamemodes sans notion de camp (ex. Dodgeball).
local campBadge = Instance.new("TextLabel", panel)
campBadge.AnchorPoint       = Vector2.new(0.5, 0)
campBadge.Size               = UDim2.new(0, 240, 0, 28)
campBadge.Position           = UDim2.new(0.5, 0, 0, 54)
campBadge.BackgroundColor3   = Color3.fromRGB(255, 255, 255)
campBadge.BackgroundTransparency = 1
campBadge.Font               = Enum.Font.GothamBold
campBadge.TextSize           = 15
campBadge.TextColor3         = Color3.new(1, 1, 1)
campBadge.TextTransparency   = 1
campBadge.Text               = ""
campBadge.Visible            = false
Instance.new("UICorner", campBadge).CornerRadius = UDim.new(1, 0)

local subtitleLbl = Instance.new("TextLabel", panel)
subtitleLbl.Size               = UDim2.new(1, -24, 0, 18)
subtitleLbl.Position           = UDim2.new(0, 12, 0, 92)
subtitleLbl.BackgroundTransparency = 1
subtitleLbl.Font               = Enum.Font.Gotham
subtitleLbl.TextSize           = 12
subtitleLbl.TextColor3         = COLOR_DIM
subtitleLbl.Text               = ""
subtitleLbl.TextTransparency   = 1

local rowList = Instance.new("ScrollingFrame", panel)
rowList.Size                 = UDim2.new(1, -24, 0, PANEL_H - 196)
rowList.Position             = UDim2.new(0, 12, 0, 118)
rowList.BackgroundTransparency = 1
rowList.BorderSizePixel      = 0
rowList.ScrollBarThickness   = 4
rowList.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 100)
rowList.CanvasSize           = UDim2.new(0, 0, 0, 0)
rowList.AutomaticCanvasSize  = Enum.AutomaticSize.Y
local rowLayout = Instance.new("UIListLayout", rowList)
rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowLayout.Padding   = UDim.new(0, 4)

local replayBtn = Instance.new("TextButton", panel)
replayBtn.AnchorPoint       = Vector2.new(0, 1)
replayBtn.Size               = UDim2.new(0.62, -6, 0, 46)
replayBtn.Position           = UDim2.new(0, 12, 1, -14)
replayBtn.BackgroundColor3   = Color3.fromRGB(80, 200, 90)
replayBtn.Font               = Enum.Font.GothamBold
replayBtn.TextSize           = 17
replayBtn.TextColor3         = Color3.new(1, 1, 1)
replayBtn.Text               = "🔄 REJOUER"
replayBtn.AutoButtonColor    = true
Instance.new("UICorner", replayBtn).CornerRadius = UDim.new(0, 10)
ButtonHover.Apply(replayBtn)

local closeBtn = Instance.new("TextButton", panel)
closeBtn.AnchorPoint       = Vector2.new(1, 1)
closeBtn.Size               = UDim2.new(0.34, -6, 0, 46)
closeBtn.Position           = UDim2.new(1, -12, 1, -14)
closeBtn.BackgroundColor3   = Color3.fromRGB(60, 60, 70)
closeBtn.Font               = Enum.Font.GothamBold
closeBtn.TextSize           = 15
closeBtn.TextColor3         = COLOR_TXT
closeBtn.Text               = "X Fermer"
closeBtn.AutoButtonColor    = true
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 10)
ButtonHover.Apply(closeBtn)

-- ===== État =====
local currentGamemodeName: string? = nil
local dismissToken = 0

-- `rankNumber` : nil quand regroupé par section (Clowns/Enfants/Éliminés) — un médaillon "🥇" sur
-- une ligne du groupe "Éliminés" n'aurait aucun sens ; le classement global par rang ne s'affiche
-- que pour les gamemodes SANS rôle (liste plate, ex. Dodgeball).
local function makeRow(parent: Instance, entry, layoutOrder: number, rankNumber: number?)
	local isMe = entry.userId == localPlayer.UserId

	local row = Instance.new("Frame", parent)
	row.Size               = UDim2.new(1, 0, 0, 40)
	row.BackgroundColor3   = isMe and Color3.fromRGB(60, 48, 10) or COLOR_ROW
	row.BackgroundTransparency = isMe and 0 or 0.15
	row.BorderSizePixel    = 0
	row.LayoutOrder        = layoutOrder
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
	local rowPadding = Instance.new("UIPadding", row)
	rowPadding.PaddingLeft  = UDim.new(0, 12)
	rowPadding.PaddingRight = UDim.new(0, 10)

	local nameLbl = Instance.new("TextLabel", row)
	nameLbl.Size              = UDim2.new(rankNumber and 0.48 or 0.58, 0, 1, 0)
	nameLbl.Position          = UDim2.new(rankNumber and 0.1 or 0, 0, 0, 0)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font              = isMe and Enum.Font.GothamBold or Enum.Font.Gotham
	nameLbl.TextSize          = 14
	nameLbl.TextColor3        = isMe and COLOR_ME or COLOR_TXT
	nameLbl.TextXAlignment    = Enum.TextXAlignment.Left
	nameLbl.TextTruncate      = Enum.TextTruncate.AtEnd
	nameLbl.Text              = (isMe and "▶ " or "") .. entry.name

	if rankNumber then
		local medals = { "🥇", "🥈", "🥉" }
		local rankLbl = Instance.new("TextLabel", row)
		rankLbl.Size               = UDim2.new(0.1, 0, 1, 0)
		rankLbl.BackgroundTransparency = 1
		rankLbl.Font               = Enum.Font.GothamBold
		rankLbl.TextSize           = 15
		rankLbl.TextColor3         = isMe and COLOR_ME or COLOR_TXT
		rankLbl.TextXAlignment     = Enum.TextXAlignment.Center
		rankLbl.Text               = medals[rankNumber] or ("#" .. rankNumber)
	end

	if entry.isWinner then
		local trophy = Instance.new("TextLabel", row)
		trophy.Size               = UDim2.new(0.14, 0, 1, 0)
		trophy.Position           = UDim2.new(0.58, 0, 0, 0)
		trophy.BackgroundTransparency = 1
		trophy.Font               = Enum.Font.GothamBold
		trophy.TextSize           = 16
		trophy.Text               = "🏆"
	end

	local gpLbl = Instance.new("TextLabel", row)
	gpLbl.Size               = UDim2.new(0.30, -10, 1, 0)
	gpLbl.Position           = UDim2.new(0.70, 0, 0, 0)
	gpLbl.BackgroundTransparency = 1
	gpLbl.Font               = Enum.Font.GothamBold
	gpLbl.TextSize           = 15
	gpLbl.TextColor3         = COLOR_GP
	gpLbl.TextXAlignment     = Enum.TextXAlignment.Right
	gpLbl.Text               = "+" .. entry.gpEarned .. " GP"
end

local function makeSectionHeader(parent: Instance, text: string, layoutOrder: number)
	local header = Instance.new("TextLabel", parent)
	header.Size               = UDim2.new(1, -12, 0, 24)
	header.Position           = UDim2.new(0, 12, 0, 0)
	header.LayoutOrder        = layoutOrder
	header.BackgroundTransparency = 1
	header.Font               = Enum.Font.GothamBold
	header.TextSize           = 13
	header.TextColor3         = COLOR_DIM
	header.TextXAlignment     = Enum.TextXAlignment.Left
	header.Text               = text
end

local function hide()
	dismissToken += 1
	local tweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(backdrop, tweenInfo, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(panel, tweenInfo, { BackgroundTransparency = 1, Position = UDim2.new(0.5, 0, 0.5, 40) }):Play()
	TweenService:Create(titleLbl, tweenInfo, { TextTransparency = 1 }):Play()
	TweenService:Create(subtitleLbl, tweenInfo, { TextTransparency = 1 }):Play()
	if campBadge.Visible then
		TweenService:Create(campBadge, tweenInfo, { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
	end
	task.delay(0.35, function()
		if not backdrop.Visible then return end
		backdrop.Visible = false
	end)
end

local function show(summary)
	currentGamemodeName = summary.gamemodeName

	local myEntry = nil
	for _, entry in summary.results do
		if entry.userId == localPlayer.UserId then
			myEntry = entry
			break
		end
	end

	-- Titre PERSONNEL : ai-je gagné ou perdu, moi (indépendant du camp gagnant — un survivant
	-- éliminé tôt a personnellement PERDU même si son camp finit par gagner la manche).
	if summary.voided then
		titleLbl.Text     = "⏱️ PARTIE ANNULÉE"
		titleLbl.TextColor3 = COLOR_VOID
	elseif myEntry and myEntry.isWinner then
		titleLbl.Text     = "🎉 TU AS GAGNÉ !"
		titleLbl.TextColor3 = COLOR_WIN
	elseif myEntry then
		titleLbl.Text     = "💀 TU AS PERDU !"
		titleLbl.TextColor3 = COLOR_LOSE
	else
		titleLbl.Text     = "FIN DE LA PARTIE"
		titleLbl.TextColor3 = COLOR_TXT
	end
	subtitleLbl.Text = summary.reason or ""

	-- Badge camp gagnant : question complémentaire "qui a gagné la manche", affichée EN PLUS du
	-- titre personnel (voir ROLE_BADGE). Masqué si round vidé ou gamemode sans notion de camp.
	local badgeInfo = (not summary.voided) and summary.winningRole and ROLE_BADGE[summary.winningRole]
	if badgeInfo then
		campBadge.Text            = badgeInfo.text
		campBadge.BackgroundColor3 = badgeInfo.color
		campBadge.Visible         = true
	else
		campBadge.Visible = false
	end

	rowList:ClearAllChildren()
	local layout = Instance.new("UIListLayout", rowList)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding   = UDim.new(0, 4)

	local hasRoleInfo = false
	for _, entry in summary.results do
		if entry.role then hasRoleInfo = true; break end
	end

	if hasRoleInfo then
		-- Regroupé par section (Clowns/Enfants/Éliminés), même ordre que le panneau "Effectifs de
		-- la partie" en direct — pas de médaillon de rang (n'aurait pas de sens dans "Éliminés").
		local layoutOrder = 0
		for _, section in ROLE_SECTIONS do
			local entriesInSection = {}
			for _, entry in summary.results do
				if entry.role == section.role then table.insert(entriesInSection, entry) end
			end
			if #entriesInSection > 0 then
				layoutOrder += 1
				makeSectionHeader(rowList, section.header, layoutOrder)
				for _, entry in entriesInSection do
					layoutOrder += 1
					makeRow(rowList, entry, layoutOrder, nil)
				end
			end
		end
	else
		-- Pas de notion de rôle/camp pour ce gamemode (ex. Dodgeball) : liste plate classique,
		-- classement par rang (médaillons top 3).
		for i, entry in summary.results do
			makeRow(rowList, entry, i, i)
		end
	end

	backdrop.Visible = true
	PanelCoordinator.NotifyOpened(PANEL_ID)

	local tweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(backdrop, tweenInfo, { BackgroundTransparency = 0.35 }):Play()
	TweenService:Create(panel, tweenInfo, { BackgroundTransparency = 0.05, Position = UDim2.new(0.5, 0, 0.5, 0) }):Play()
	TweenService:Create(titleLbl, tweenInfo, { TextTransparency = 0 }):Play()
	TweenService:Create(subtitleLbl, tweenInfo, { TextTransparency = 0 }):Play()
	if campBadge.Visible then
		TweenService:Create(campBadge, tweenInfo, { BackgroundTransparency = 0.1, TextTransparency = 0 }):Play()
	end

	dismissToken += 1
	local myToken = dismissToken
	task.delay(AUTO_DISMISS_DELAY, function()
		if myToken == dismissToken then
			hide()
		end
	end)
end

replayBtn.MouseButton1Click:Connect(function()
	UISound.PlayClick()
	if currentGamemodeName then
		requestJoinEvent:FireServer(currentGamemodeName)
	end
	hide()
end)
closeBtn.MouseButton1Click:Connect(function()
	UISound.PlayClick()
	hide()
end)

-- Un AUTRE panneau centré vient de s'ouvrir (Profil, Classement...) : on se ferme pour ne pas
-- empiler deux panneaux centrés l'un sur l'autre.
PanelCoordinator.OnPanelOpened(function(openedId)
	if openedId ~= PANEL_ID and backdrop.Visible then
		hide()
	end
end)

RoundEndSummary.OnClientEvent:Connect(show)
