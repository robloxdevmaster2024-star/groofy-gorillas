--!nonstrict
-- PlayerConfig.luau — Courbe de niveaux et récompenses (source de vérité).

return {
	-- XP total requis pour atteindre chaque niveau (indice = numéro de niveau)
	LEVEL_THRESHOLDS = {
		[1]  = 0,
		[2]  = 100,
		[3]  = 250,
		[4]  = 500,
		[5]  = 850,
		[6]  = 1300,
		[7]  = 1900,
		[8]  = 2700,
		[9]  = 3700,
		[10] = 5000,
		[11] = 6600,
		[12] = 8500,
		[13] = 10800,
		[14] = 13500,
		[15] = 16700,
		[16] = 20500,
		[17] = 25000,
		[18] = 30200,
		[19] = 36200,
		[20] = 43000,
	},
	MAX_LEVEL = 20,

	-- Goofy Points attribués en fin de round
	POINTS = {
		WINNER      = 50,  -- gagnant du round
		PARTICIPANT = 15,  -- tous les autres (participation)

		-- Récompenses d'ACTION pendant la partie (Clown Survival) : données pour un événement
		-- précis qui vient de se produire, pas pour le résultat final du round. Restent dues même
		-- si la victoire finale est "vidée" (voir RoundRunner.MIN_MEANINGFUL_ROUND_DURATION) —
		-- ce sont de vraies actions jouées, pas un bonus de victoire.
		KILL          = 5,  -- clown : chaque coup réussi (contamination ou élimination)
		FIRST_BLOOD   = 10, -- clown : bonus pour la toute première contamination/élimination du round
		NEVER_TOUCHED = 15, -- survivant : bonus si jamais contaminé/éliminé de tout le round
		COMBO_MILESTONES = { [2] = 5, [3] = 10, [5] = 20 }, -- clown : bonus une fois par palier, par round
		-- survivant : paliers de temps de survie (s écoulées depuis le début du round), symétrique
		-- aux paliers de combo du clown. Donné à TOUS les survivants encore non-touchés à cet
		-- instant précis : toutes les 30s, 5 GP sur la 1ère moitié du round (0-90s), 10 GP sur la
		-- 2ᵉ moitié (90-180s).
		SURVIVAL_MILESTONES = { [30] = 5, [60] = 5, [90] = 5, [120] = 10, [150] = 10, [180] = 10 },
	},
}
