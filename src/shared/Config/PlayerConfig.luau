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
	},
}
