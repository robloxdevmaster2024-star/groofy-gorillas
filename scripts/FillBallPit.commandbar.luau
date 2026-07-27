-- FillBallPit.commandbar.luau
--
-- SCRIPT DE STUDIO (Command Bar), PAS un script Rojo / pas synchronisé en jeu.
-- À coller dans Studio : View > Command Bar, puis Entrée pour exécuter.
--
-- Vide "BOULES" (les balles dupliquées à la main) et regénère une grille de balles
-- en plusieurs étages pour remplir tout le volume intérieur de "Piscine à balle".
-- Les balles sont détachées (non-ancrées) avec des propriétés physiques légères
-- et glissantes, comme de vraies balles en plastique : quand un joueur saute dedans,
-- elles doivent être poussées et partir un peu dans tous les sens au lieu de rester figées.
--
-- Réglages à ajuster en haut du script puis ré-exécuter autant de fois que nécessaire
-- (le script vide BOULES à chaque fois, donc pas de doublons/accumulation).

local Workspace = game:GetService("Workspace")

-- ===== Réglages =====
local LAYERS            = 4     -- nombre d'étages de balles empilés
local WALL_MARGIN       = 0.5   -- studs de marge par rapport aux bords intérieurs de la piscine
local EDGE_INSET_RINGS  = 1     -- nombre de rangées de bord à ne pas générer (évite que la balle du contour clippe dans la piscine)
local SPACING_MULT      = 1.05  -- espacement horizontal entre centres de balles (x diamètre) ; <1 = balles qui se chevauchent légèrement
local LAYER_HEIGHT_MULT = 0.88  -- hauteur entre étages (x diamètre) ; <1 = les balles s'imbriquent comme un vrai tas
local JITTER            = 0.15  -- décalage horizontal aléatoire max par balle (studs), pour un look naturel
local RANDOM_ROTATION   = true  -- oriente chaque balle aléatoirement (plus naturel si la balle n'est pas parfaitement sphérique)

-- Physique "vraie piscine à balles" : légères, glissantes, un peu rebondissantes.
local BALL_DENSITY    = 0.15 -- très léger (plastique creux) → facilement poussé/écarté par un joueur
local BALL_FRICTION   = 0.15 -- faible → les balles glissent les unes sur les autres au lieu de se figer
local BALL_ELASTICITY = 0.4  -- un peu de rebond, sans exagérer

-- Perf : simuler des milliers de balles non-ancrées fait très fortement lag le jeu.
-- Seuls les étages du haut (ceux qu'un joueur touche vraiment en sautant dedans) sont
-- physiques ; les étages du dessous restent ancrés (statiques, quasi gratuits en perf)
-- tout en gardant le remplissage visuel complet de la piscine.
local PHYSICS_TOP_LAYERS = 2 -- nombre d'étages du haut avec vraie physique (augmente si le lag redevient acceptable, diminue sinon)

-- Palette "piscine à balles" classique (plastique brillant, couleurs primaires/vives)
local BALL_COLORS = {
	Color3.fromRGB(220, 30, 30),   -- rouge
	Color3.fromRGB(255, 140, 0),   -- orange
	Color3.fromRGB(255, 210, 0),   -- jaune
	Color3.fromRGB(40, 167, 69),   -- vert
	Color3.fromRGB(0, 110, 220),   -- bleu
	Color3.fromRGB(150, 60, 180),  -- violet
	Color3.fromRGB(255, 105, 180), -- rose
}
local BALL_MATERIAL = Enum.Material.SmoothPlastic -- plastique lisse et brillant

-- ===== Récupération des objets =====
local pool = Workspace:FindFirstChild("Piscine à balle")
assert(pool, "Introuvable dans Workspace : 'Piscine à balle'")
assert(pool:IsA("Model"), "'Piscine à balle' doit être un Model (bords + fond)")

local boulesFolder = Workspace:FindFirstChild("BOULES")
assert(boulesFolder, "Introuvable dans Workspace : 'BOULES'")

-- Le gabarit de balle = la première balle trouvée dans BOULES (BasePart ou Model)
local template = nil
for _, child in boulesFolder:GetChildren() do
	if child:IsA("BasePart") or child:IsA("Model") then
		template = child
		break
	end
end
assert(template ~= nil, "Aucune balle-gabarit trouvée dans BOULES (attendu : au moins 1 BasePart/Model)")
template = template:Clone() -- on garde une copie de côté, l'original sera détruit avec le reste

-- Taille approximative d'une balle (BasePart ou Model), sans ternaire pour laisser le type se préciser
local function getApproxSize(inst)
	if inst:IsA("BasePart") then
		return inst.Size
	elseif inst:IsA("Model") then
		return inst:GetExtentsSize()
	end
	error("Gabarit de balle invalide : doit être un BasePart ou un Model")
end

-- Configure une balle : couleur aléatoire toujours, mais physique (non-ancrée + propriétés
-- de plastique léger/glissant) seulement si `physical` est vrai. Sinon elle reste ancrée
-- (statique, quasi gratuite en perf) tout en gardant le même look.
local function setupBall(inst, rng, physical)
	local color = BALL_COLORS[rng:NextInteger(1, #BALL_COLORS)]

	local function apply(part)
		part.Anchored = not physical
		part.CanCollide = true
		part.Color = color
		part.Material = BALL_MATERIAL
		if physical then
			part.CustomPhysicalProperties = PhysicalProperties.new(
				BALL_DENSITY,
				BALL_FRICTION,
				BALL_ELASTICITY
			)
		end
	end

	if inst:IsA("BasePart") then
		apply(inst)
	elseif inst:IsA("Model") then
		for _, desc in inst:GetDescendants() do
			if desc:IsA("BasePart") then
				apply(desc)
			end
		end
	end
end

local ballDiameter
do
	local templateSize = getApproxSize(template)
	ballDiameter = math.max(templateSize.X, templateSize.Y, templateSize.Z)
end

-- ===== Volume intérieur de la piscine =====
local poolCFrame, poolSize = pool:GetBoundingBox()

local innerHalfX = poolSize.X / 2 - WALL_MARGIN - ballDiameter / 2
local innerHalfZ = poolSize.Z / 2 - WALL_MARGIN - ballDiameter / 2
assert(innerHalfX > 0 and innerHalfZ > 0, "Piscine trop petite pour la taille de balle / marge donnée")

local bottomY = -poolSize.Y / 2 + WALL_MARGIN + ballDiameter / 2

local spacing     = ballDiameter * SPACING_MULT
local layerHeight = ballDiameter * LAYER_HEIGHT_MULT

local countX = math.max(1, math.floor((innerHalfX * 2) / spacing) + 1)
local countZ = math.max(1, math.floor((innerHalfZ * 2) / spacing) + 1)

-- ===== Vidage de BOULES =====
boulesFolder:ClearAllChildren()

-- ===== Génération de la grille (empilement en étages) =====
local rng = Random.new()
local placed = 0

for layer = 0, LAYERS - 1 do
	-- Décalage en quinconce à chaque étage (comme un empilement de sphères réel)
	local stagger = (layer % 2 == 1) and (spacing / 2) or 0
	-- Seuls les derniers étages (le dessus) sont physiques ; le reste est ancré (perf).
	local physical = layer >= LAYERS - PHYSICS_TOP_LAYERS

	-- On saute les rangées de bord (EDGE_INSET_RINGS) pour ne pas générer la ligne de balles
	-- de contour qui clippe dans les parois de la piscine.
	local minIx = math.min(EDGE_INSET_RINGS, math.floor((countX - 1) / 2))
	local maxIx = countX - 1 - minIx
	local minIz = math.min(EDGE_INSET_RINGS, math.floor((countZ - 1) / 2))
	local maxIz = countZ - 1 - minIz

	for ix = minIx, maxIx do
		for iz = minIz, maxIz do
			local localX = -innerHalfX + ix * spacing + stagger
			local localZ = -innerHalfZ + iz * spacing + stagger
			if math.abs(localX) <= innerHalfX and math.abs(localZ) <= innerHalfZ then
				local jitterX = (rng:NextNumber() * 2 - 1) * JITTER
				local jitterZ = (rng:NextNumber() * 2 - 1) * JITTER
				local localY  = bottomY + layer * layerHeight

				local rotation = CFrame.new()
				if RANDOM_ROTATION then
					rotation = CFrame.Angles(
						rng:NextNumber() * math.pi * 2,
						rng:NextNumber() * math.pi * 2,
						rng:NextNumber() * math.pi * 2
					)
				end

				local worldCFrame = poolCFrame
					* CFrame.new(localX + jitterX, localY, localZ + jitterZ)
					* rotation

				local ball = template:Clone()
				ball.Parent = boulesFolder -- parenté avant les propriétés physiques/CFrame (évite le warning "not parented to Workspace")
				setupBall(ball, rng, physical)
				if ball:IsA("BasePart") then
					ball.CFrame = worldCFrame
				else
					ball:PivotTo(worldCFrame)
				end
				placed += 1
			end
		end
	end
end

template:Destroy()

print(("[FillBallPit] %d balles physiques générées sur %d étage(s) dans BOULES."):format(placed, LAYERS))
