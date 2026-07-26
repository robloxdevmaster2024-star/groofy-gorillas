--!strict
-- ButtonHover.luau — Effet de survol (léger rétrécissement) sur les boutons cliquables de l'UI :
-- retour visuel standard "je suis sous ma souris", très utilisé dans les jeux. PC uniquement en
-- pratique — MouseEnter/MouseLeave ne se déclenchent pas au toucher sur mobile (pas de souris à
-- survoler), donc rien à gérer côté tactile, le comportement par défaut convient déjà.
--
-- Implémenté via un `UIScale` enfant plutôt qu'en tweenant directement `Size`/`Position` du
-- bouton (1ʳᵉ version, remplacée) — deux problèmes que `UIScale` résout d'un coup :
--   1. Le bouton ET tout son contenu (texte compris, même à `TextSize` fixe) doivent rétrécir
--      ensemble : `UIScale` s'applique à tout le sous-arbre, texte inclus, sans rien tweener à la
--      main par propriété.
--   2. Un bouton géré par un `UIListLayout` (onglets, menu de sélection de gamemode...) ne
--      rétrécissait PAS de façon centrée : modifier `Size` déclenche un recalcul du layout, qui
--      réécrase la `Position` selon ses propres règles d'alignement (pas le centre). `UIScale` ne
--      change pas `Size`/`Position` (juste le rendu), donc le layout ne le voit jamais et ne
--      interfère plus — le rétrécissement reste centré sur le bouton, dans une liste ou non.
--
-- ⚠️ Client uniquement (ScreenGui). Ne PAS appliquer à des boutons dans un SurfaceGui/BillboardGui
-- posé dans le monde 3D et créé côté SERVEUR (ex. LeaderboardPodium.luau) : l'Instance y est
-- PARTAGÉE entre tous les joueurs qui la voient — un survol tweené depuis un script serveur
-- rétrécirait le bouton pour TOUT LE MONDE dès qu'UN SEUL joueur passe la souris dessus.

local TweenService = game:GetService("TweenService")

local SHRINK_FACTOR = 0.94
local TWEEN_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local ButtonHover = {}

-- Applique l'effet à UN bouton. `shrinkFactor` optionnel (défaut SHRINK_FACTOR) pour un effet plus
-- ou moins prononcé selon le bouton.
function ButtonHover.Apply(button: GuiButton, shrinkFactor: number?)
	local factor = shrinkFactor or SHRINK_FACTOR

	-- `AutoButtonColor` (activé par défaut sur tout GuiButton) assombrit/éclaircit le fond
	-- INSTANTANÉMENT au survol, sans easing — en conflit avec notre tween fluide en `UIScale` :
	-- au moment de quitter le bouton, la couleur revient d'un coup pendant que la taille est encore
	-- en train de retrécir/regrossir en douceur, ce qui se voit comme un petit "saut". Désactivé
	-- ici : notre propre effet de survol remplace déjà ce retour visuel.
	button.AutoButtonColor = false

	local scale = button:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = button
	end

	button.MouseEnter:Connect(function()
		TweenService:Create(scale, TWEEN_INFO, { Scale = factor }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, TWEEN_INFO, { Scale = 1 }):Play()
	end)
end

return ButtonHover
