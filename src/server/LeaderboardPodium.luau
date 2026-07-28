--!nonstrict
-- LeaderboardPodium.luau — Podium 3D dans le Hub : 3 plateformes (or/argent/bronze) affichant en
-- direct le top 3 du classement sélectionné, + un panneau (SurfaceGui) avec les mêmes onglets
-- période x board que LeaderboardGui.client.luau (ALL TIME/HEBDO x GP/Victoires/Meilleure série)
-- et une liste scrollable (molette native, aucun code requis) allant jusqu'au top 25.
--
-- 100% serveur : un TextButton posé dans un SurfaceGui du monde 3D (contrairement à un ScreenGui)
-- déclenche déjà MouseButton1Click côté serveur — pas besoin de RemoteEvent pour piloter les
-- onglets. L'affichage est VOLONTAIREMENT partagé entre tous les joueurs (un seul état d'onglet
-- pour tout le monde à un instant donné) : c'est un objet physique unique du monde, façon borne
-- d'arcade, pas une UI par joueur.
--
-- Convention Studio : un Model nommé "LeaderboardPodium" posé directement dans le Workspace (à
-- côté du reste du hub — contrairement aux Venues de gamemodes, le Lobby n'est construit qu'une
-- fois au démarrage du serveur et n'est jamais rechargé, donc pas besoin de le stocker en template
-- dans ServerStorage), contenant de VRAIES Parts placées à la main :
--   Rank1, Rank2, Rank3  → les 3 socles (le script lit directement leur CFrame/Size existants,
--                          rien n'est recréé — les redimensionner/déplacer dans Studio suffit)
--   Board                → le panneau (le SurfaceGui s'affiche sur sa face -Z/"Front" — orienter
--                          la Part en conséquence)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")

local LeaderboardsConfig = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("LeaderboardsConfig")
)
local LeaderboardService = require(script.Parent.LeaderboardService)
local WeekId              = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeekId"))

local PLATFORM_COLORS  = {
	Color3.fromRGB(255, 210, 40),  -- or
	Color3.fromRGB(200, 200, 210), -- argent
	Color3.fromRGB(205, 130, 60),  -- bronze
}

-- Grossissement x3 : le panneau physique (voir "Board" dans Studio) a été construit 3x plus grand
-- en studs, mais le CANVAS pixel (donc toute la mise en page ci-dessous, définie en pixels fixes)
-- reste identique en divisant PixelsPerStud par le même facteur — chaque pixel couvre juste 3x plus
-- d'espace physique, donc tout (texte, onglets, lignes) grossit proportionnellement sans rien
-- retoucher au layout.
local BOARD_SCALE       = 3
local PIXELS_PER_STUD   = 50 / BOARD_SCALE
local TAB_ROW_H_PX      = 42
local ROW_H_PX          = 30

local COLOR_BG      = Color3.fromRGB(14, 14, 18)
local COLOR_TXT     = Color3.fromRGB(230, 230, 235)
local COLOR_DIM     = Color3.fromRGB(150, 150, 160)
local COLOR_TOP     = Color3.fromRGB(255, 210, 30)
local COLOR_TAB_OFF = Color3.fromRGB(30, 30, 38)
local COLOR_TAB_ON  = Color3.fromRGB(70, 55, 12)

local AVATAR_ROTATE_SPEED = math.rad(30) -- rad/s, rotation lente façon vitrine de boutique

local LeaderboardPodium = {}

-- Cherche les vraies Parts placées à la main dans Studio (voir convention en tête de fichier).
-- Retourne nil si le Model ou une des 4 Parts manque.
local function findPhysicalPodium(): { ranks: { BasePart }, board: BasePart }?
	local podiumModel = workspace:FindFirstChild("LeaderboardPodium", true)
	if not podiumModel then return nil end

	local ranks = {}
	for i = 1, 3 do
		local part = podiumModel:FindFirstChild("Rank" .. i)
		if not (part and part:IsA("BasePart")) then return nil end
		ranks[i] = part
	end

	local board = podiumModel:FindFirstChild("Board")
	if not (board and board:IsA("BasePart")) then return nil end

	return { ranks = ranks, board = board }
end

-- Ajoute le BillboardGui (nom + score) sur un socle déjà existant (physique ou généré) — ne touche
-- ni à sa taille ni à sa position : la hauteur du label se cale sur part.Size.Y actuel, donc un
-- socle redimensionné à la main dans Studio garde un label bien placé sans toucher au code.
local function attachRankBillboard(part: BasePart, colorIndex: number)
	-- Au-dessus de la tête de l'avatar affiché sur ce socle (voir placeAvatarOnSlot) plutôt
	-- que juste au-dessus du socle lui-même, sinon le nom/score flotterait dans le torse.
	local billboard = Instance.new("BillboardGui")
	billboard.Name        = "RankLabel"
	billboard.Size        = UDim2.new(0, 150, 0, 60)
	billboard.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 7.2, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent      = part

	local nameLbl = Instance.new("TextLabel", billboard)
	nameLbl.Name               = "NameLbl"
	nameLbl.Size               = UDim2.new(1, 0, 0.55, 0)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font               = Enum.Font.FredokaOne
	nameLbl.TextSize           = 18
	nameLbl.TextColor3         = Color3.new(1, 1, 1)
	nameLbl.TextStrokeTransparency = 0.3
	nameLbl.Text               = "—"

	local scoreLbl = Instance.new("TextLabel", billboard)
	scoreLbl.Name               = "ScoreLbl"
	scoreLbl.Size               = UDim2.new(1, 0, 0.45, 0)
	scoreLbl.Position           = UDim2.new(0, 0, 0.55, 0)
	scoreLbl.BackgroundTransparency = 1
	scoreLbl.Font               = Enum.Font.GothamBold
	scoreLbl.TextSize           = 14
	scoreLbl.TextColor3         = PLATFORM_COLORS[colorIndex]
	scoreLbl.TextStrokeTransparency = 0.5
	scoreLbl.Text               = ""

	return { name = nameLbl, score = scoreLbl }
end

local function attachBillboards(parts: { BasePart })
	local billboards = {}
	for i, part in parts do
		billboards[i] = attachRankBillboard(part, i)
	end
	return billboards
end

-- ===== Avatars affichés sur les socles (top 3 en direct) =====
-- Construits à partir du userId (pas du Player en ligne : le top 3 peut très bien être hors ligne
-- ou sur un autre serveur) via l'API officielle Players:CreateHumanoidModelFromDescription, mis en
-- cache indéfiniment par userId (une requête réseau par joueur affiché, pas une par render()).

local avatarCache: { [number]: Model | false } = {} -- false = échec définitif (avatar indispo), pour ne pas refetch en boucle

local function getOrBuildAvatar(userId: number): Model?
	local cached = avatarCache[userId]
	if cached ~= nil then
		return cached or nil
	end

	-- Les comptes simulés de "Test → Clients and Servers" en Studio ont des UserId négatifs
	-- (ex. -1, -2...) qui n'existent pas côté service Avatar réel : GetHumanoidDescriptionFromUserId
	-- échoue systématiquement pour eux, ce n'est pas un bug — juste une limite du test local. En
	-- jeu publié (vrais UserId positifs), ça fonctionne normalement. On évite juste le warn/pcall
	-- inutile pour ce cas prévisible.
	if userId <= 0 then
		avatarCache[userId] = false
		return nil
	end

	local ok, desc = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(userId)
	end)
	if not ok then
		warn("[LeaderboardPodium] Avatar indisponible pour userId", userId, ":", desc)
		avatarCache[userId] = false
		return nil
	end

	local ok2, avatarModel = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok2 or not avatarModel then
		avatarCache[userId] = false
		return nil
	end

	-- Simple présentoir statique : pas de script de personnage (mouvement, animation d'input...),
	-- juste anchoré en place, non solide pour que les joueurs puissent passer au travers.
	for _, inst in avatarModel:GetDescendants() do
		if inst:IsA("BasePart") then
			inst.Anchored   = true
			inst.CanCollide = false
		elseif inst:IsA("Script") then
			inst:Destroy()
		end
	end
	avatarModel.Name = "Avatar_" .. userId

	avatarCache[userId] = avatarModel
	return avatarModel
end

-- Pose le modèle debout sur le socle, pieds au contact de la surface, même orientation que le socle.
local function placeAvatarOnPlatform(avatarModel: Model, platformPart: BasePart, parentModel: Model)
	local _, boundsSize = avatarModel:GetBoundingBox()
	local topSurfaceY = platformPart.Position.Y + platformPart.Size.Y / 2
	local targetCFrame = CFrame.new(platformPart.Position.X, topSurfaceY + boundsSize.Y / 2, platformPart.Position.Z)
		* platformPart.CFrame.Rotation
	avatarModel:PivotTo(targetCFrame)
	avatarModel.Parent = parentModel
end

local function makeTabButton(parent: Instance, text: string, widthScale: number, textSize: number, onClick: () -> ())
	local btn = Instance.new("TextButton")
	btn.Size              = UDim2.new(widthScale, -4, 1, 0)
	btn.BackgroundColor3  = COLOR_TAB_OFF
	btn.Font              = Enum.Font.GothamBold
	btn.TextSize          = textSize
	btn.TextColor3        = COLOR_DIM
	btn.TextTruncate      = Enum.TextTruncate.AtEnd -- filet de sécurité si un futur libellé reste trop long malgré tabLabel
	btn.Text              = text
	btn.AutoButtonColor   = true
	btn.Parent            = parent
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
	btn.MouseButton1Click:Connect(onClick)
	return btn
end

-- Construit le SurfaceGui (onglets + liste) sur le panneau physique "Board" — la taille du canvas
-- (PixelsPerStud) suit automatiquement le Size réel de la Part.
local function attachBoardGui(boardPart: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Name           = "Board"
	gui.Face           = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.SizingMode     = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud  = PIXELS_PER_STUD
	gui.Parent         = boardPart

	local root = Instance.new("Frame", gui)
	root.Size               = UDim2.new(1, 0, 1, 0)
	root.BackgroundColor3   = COLOR_BG
	root.BorderSizePixel    = 0

	local titleLbl = Instance.new("TextLabel", root)
	titleLbl.Size               = UDim2.new(1, -20, 0, 34)
	titleLbl.Position           = UDim2.new(0, 10, 0, 6)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Font               = Enum.Font.GothamBold
	titleLbl.TextSize           = 22
	titleLbl.TextColor3         = COLOR_TOP
	titleLbl.TextXAlignment     = Enum.TextXAlignment.Left
	titleLbl.Text                = "🏆 CLASSEMENTS"

	local periodRow = Instance.new("Frame", root)
	periodRow.Size               = UDim2.new(1, -20, 0, TAB_ROW_H_PX)
	periodRow.Position           = UDim2.new(0, 10, 0, 44)
	periodRow.BackgroundTransparency = 1
	local periodLayout = Instance.new("UIListLayout", periodRow)
	periodLayout.FillDirection = Enum.FillDirection.Horizontal
	periodLayout.Padding       = UDim.new(0, 8)

	local boardRow = Instance.new("Frame", root)
	boardRow.Size               = UDim2.new(1, -20, 0, TAB_ROW_H_PX)
	boardRow.Position           = UDim2.new(0, 10, 0, 44 + TAB_ROW_H_PX + 8)
	boardRow.BackgroundTransparency = 1
	local boardLayout = Instance.new("UIListLayout", boardRow)
	boardLayout.FillDirection = Enum.FillDirection.Horizontal
	boardLayout.Padding       = UDim.new(0, 8)

	local listTop = 44 + (TAB_ROW_H_PX + 8) * 2

	local weekLbl = Instance.new("TextLabel", root)
	weekLbl.Size               = UDim2.new(1, -20, 0, 22)
	weekLbl.Position           = UDim2.new(0, 10, 0, listTop)
	weekLbl.BackgroundTransparency = 1
	weekLbl.Font               = Enum.Font.Gotham
	weekLbl.TextSize           = 16
	weekLbl.TextColor3         = COLOR_DIM
	weekLbl.TextXAlignment     = Enum.TextXAlignment.Left
	weekLbl.Text               = ""
	weekLbl.Visible            = false

	local rowList = Instance.new("ScrollingFrame", root)
	rowList.Size                 = UDim2.new(1, -20, 1, -(listTop + 30))
	rowList.Position             = UDim2.new(0, 10, 0, listTop + 26)
	rowList.BackgroundTransparency = 1
	rowList.BorderSizePixel      = 0
	rowList.ScrollBarThickness   = 8
	rowList.ScrollBarImageColor3 = Color3.fromRGB(90, 90, 110)
	rowList.CanvasSize           = UDim2.new(0, 0, 0, 0)
	rowList.AutomaticCanvasSize  = Enum.AutomaticSize.Y
	local rowLayout = Instance.new("UIListLayout", rowList)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Padding   = UDim.new(0, 4)

	return {
		titleLbl  = titleLbl,
		weekLbl   = weekLbl,
		rowList   = rowList,
		periodRow = periodRow,
		boardRow  = boardRow,
	}
end

local function makeRow(parent: Instance, entry, order: number, board)
	local row = Instance.new("Frame", parent)
	row.Size               = UDim2.new(1, 0, 0, ROW_H_PX)
	row.BackgroundColor3   = Color3.fromRGB(28, 28, 36)
	row.BackgroundTransparency = 0.1
	row.BorderSizePixel    = 0
	row.LayoutOrder        = order
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

	local medals = { "🥇", "🥈", "🥉" }
	local rankLbl = Instance.new("TextLabel", row)
	rankLbl.Size               = UDim2.new(0.1, 0, 1, 0)
	rankLbl.BackgroundTransparency = 1
	rankLbl.Font               = Enum.Font.GothamBold
	rankLbl.TextSize           = 16
	rankLbl.TextColor3         = COLOR_TXT
	rankLbl.TextXAlignment     = Enum.TextXAlignment.Center
	rankLbl.Text               = medals[entry.rank] or ("#" .. entry.rank)

	local nameLbl = Instance.new("TextLabel", row)
	nameLbl.Size               = UDim2.new(0.55, 0, 1, 0)
	nameLbl.Position           = UDim2.new(0.1, 0, 0, 0)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font               = Enum.Font.Gotham
	nameLbl.TextSize           = 16
	nameLbl.TextColor3         = COLOR_TXT
	nameLbl.TextXAlignment     = Enum.TextXAlignment.Left
	nameLbl.Text               = entry.name

	local scoreLbl = Instance.new("TextLabel", row)
	scoreLbl.Size               = UDim2.new(0.35, -6, 1, 0)
	scoreLbl.Position           = UDim2.new(0.65, 0, 0, 0)
	scoreLbl.BackgroundTransparency = 1
	scoreLbl.Font               = Enum.Font.GothamBold
	scoreLbl.TextSize           = 16
	scoreLbl.TextColor3         = COLOR_TXT
	scoreLbl.TextXAlignment     = Enum.TextXAlignment.Right
	scoreLbl.Text               = LeaderboardsConfig.FormatScore(board, entry.score)
end

function LeaderboardPodium.Build()
	local physical = findPhysicalPodium()
	if not physical then
		warn("[LeaderboardPodium] Model 'LeaderboardPodium' (Rank1/2/3 + Board) introuvable dans workspace — podium non construit.")
		return nil
	end

	local platformParts = physical.ranks
	local billboards     = attachBillboards(platformParts)
	local ui              = attachBoardGui(physical.board)
	local model            = physical.board.Parent :: Model -- le Model "LeaderboardPodium" déjà dans le monde

	local boardsById = {}
	for _, board in LeaderboardsConfig.BOARDS do
		boardsById[board.id] = board
	end

	local state = { period = "alltime", board = "gp" }
	local cachedPayload = { boards = {}, weekId = WeekId.Current() }

	-- userId actuellement affiché sur chaque socle, pour ne (re)construire un avatar que quand le
	-- classement affiché change réellement de top 3 (pas à chaque render() redondant).
	local slotUserId: { number? } = { nil, nil, nil }

	local function updateSlotAvatar(i: number, entry)
		local newUserId = entry and entry.userId or nil
		if slotUserId[i] == newUserId then return end

		-- Retire l'avatar précédemment affiché sur ce socle (reste en cache, juste détaché).
		local prevUserId = slotUserId[i]
		local prevModel = prevUserId and avatarCache[prevUserId]
		if prevModel and prevModel ~= false then
			prevModel.Parent = nil
		end

		slotUserId[i] = newUserId
		if not newUserId then return end

		task.spawn(function()
			local avatarModel = getOrBuildAvatar(newUserId)
			if not avatarModel then return end
			if slotUserId[i] ~= newUserId then return end -- le classement a re-changé entre-temps, annule
			placeAvatarOnPlatform(avatarModel, platformParts[i], model)
		end)
	end

	local function render()
		local board = boardsById[state.board]
		local entries = cachedPayload.boards[state.board]
		entries = entries and entries[state.period] or {}

		ui.titleLbl.Text = board.icon .. " " .. board.labelUpper
			.. (state.period == "weekly" and " — HEBDO" or " — ALL TIME")
		ui.weekLbl.Visible = state.period == "weekly"
		ui.weekLbl.Text     = "Semaine " .. cachedPayload.weekId

		for i = 1, 3 do
			local entry = entries[i]
			billboards[i].name.Text  = entry and entry.name or "—"
			billboards[i].score.Text = entry and LeaderboardsConfig.FormatScore(board, entry.score) or ""
			updateSlotAvatar(i, entry)
		end

		ui.rowList:ClearAllChildren()
		local layout = Instance.new("UIListLayout", ui.rowList)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding   = UDim.new(0, 4)

		if #entries == 0 then
			local lbl = Instance.new("TextLabel", ui.rowList)
			lbl.Size               = UDim2.new(1, 0, 0, 40)
			lbl.BackgroundTransparency = 1
			lbl.Font               = Enum.Font.Gotham
			lbl.TextSize           = 16
			lbl.TextColor3         = COLOR_DIM
			lbl.Text               = "Aucun score enregistré pour l'instant."
			return
		end

		for _, entry in entries do
			makeRow(ui.rowList, entry, entry.rank, board)
		end
	end

	local periodButtons = {}
	for _, period in LeaderboardsConfig.PERIODS do
		periodButtons[period.id] = makeTabButton(ui.periodRow, period.label, 1 / #LeaderboardsConfig.PERIODS, 20, function()
			state.period = period.id
			for id, b in periodButtons do
				b.BackgroundColor3 = (id == period.id) and COLOR_TAB_ON or COLOR_TAB_OFF
				b.TextColor3       = (id == period.id) and COLOR_TOP or COLOR_DIM
			end
			render()
		end)
	end
	periodButtons[state.period].BackgroundColor3 = COLOR_TAB_ON
	periodButtons[state.period].TextColor3       = COLOR_TOP

	local boardButtons = {}
	for _, board in LeaderboardsConfig.BOARDS do
		-- tabLabel (court) plutôt que label (ex. "Victoires clown") : avec 4 boards sur la même
		-- rangée, le libellé long dépassait de son bouton (texte tronqué/qui sort du cadre).
		boardButtons[board.id] = makeTabButton(ui.boardRow, board.icon .. " " .. board.tabLabel, 1 / #LeaderboardsConfig.BOARDS, 17, function()
			state.board = board.id
			for id, b in boardButtons do
				b.BackgroundColor3 = (id == board.id) and COLOR_TAB_ON or COLOR_TAB_OFF
				b.TextColor3       = (id == board.id) and COLOR_TOP or COLOR_DIM
			end
			render()
		end)
	end
	boardButtons[state.board].BackgroundColor3 = COLOR_TAB_ON
	boardButtons[state.board].TextColor3       = COLOR_TOP

	LeaderboardService.OnRefresh(function(payload)
		cachedPayload = payload
		render()
	end)

	-- Premier remplissage immédiat (sans attendre le prochain cycle auto de 90s) : lecture directe,
	-- 100% serveur → serveur, pas besoin du RemoteEvent client.
	task.spawn(function()
		local boards = {}
		for id in boardsById do
			boards[id] = {
				alltime = LeaderboardService.Fetch(id, "alltime"),
				weekly  = LeaderboardService.Fetch(id, "weekly"),
			}
		end
		cachedPayload = { boards = boards, weekId = WeekId.Current() }
		render()
	end)

	render()

	-- Rotation lente des avatars affichés (façon vitrine de boutique) : tourne chaque modèle
	-- actuellement sur un socle autour de son propre pivot, indépendamment du choix d'onglet.
	RunService.Heartbeat:Connect(function(dt)
		local spin = CFrame.Angles(0, AVATAR_ROTATE_SPEED * dt, 0)
		for i = 1, 3 do
			local userId = slotUserId[i]
			local avatarModel = userId and avatarCache[userId]
			if avatarModel and avatarModel ~= false and avatarModel.Parent then
				avatarModel:PivotTo(avatarModel:GetPivot() * spin)
			end
		end
	end)

	print("[LeaderboardPodium] construit ✅")
	return model
end

return LeaderboardPodium
