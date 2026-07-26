--!strict
-- PanelCoordinator.luau — Coordination client-only entre les panneaux HUD plein-centre
-- (Classement global, Profil, Effectifs de la partie...) qui se superposent tous au même endroit
-- à l'écran. Sans ça, ouvrir le Profil pendant que le Classement est déjà affiché empile deux
-- panneaux centrés l'un sur l'autre. Chaque panneau s'enregistre ici : à l'ouverture, il notifie
-- les autres, qui se ferment s'ils étaient ouverts.

local PanelCoordinator = {}

local signal = Instance.new("BindableEvent")

-- À appeler quand CE panneau vient de s'ouvrir : prévient tous les autres panneaux enregistrés
-- (sauf celui qui vient de s'ouvrir) qu'ils doivent se fermer.
function PanelCoordinator.NotifyOpened(id: string)
	signal:Fire(id)
end

-- callback(openedId) est appelé à chaque fois qu'UN panneau (potentiellement un autre) s'ouvre.
-- Charge à l'appelant de comparer `openedId` au sien pour savoir s'il doit se fermer.
function PanelCoordinator.OnPanelOpened(callback: (string) -> ())
	return signal.Event:Connect(callback)
end

return PanelCoordinator
