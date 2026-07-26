--!strict
-- LeaderboardsConfig.luau — Liste data-driven des classements disponibles (source de vérité
-- unique pour id/libellé/unité/icône), consommée par LeaderboardService (serveur, noms des
-- OrderedDataStore), LeaderboardGui.client.luau (onglets du panneau) et LeaderboardPodium.luau
-- (onglets du board 3D dans le Hub). Ajouter un classement = ajouter une entrée ici, rien
-- d'autre à dupliquer côté libellés.

export type BoardDef = {
	id: string,            -- utilisé tel quel dans le nom du OrderedDataStore (voir LeaderboardService)
	label: string,         -- titre affiché dans les onglets/en-têtes
	labelUpper: string,    -- même chose en MAJUSCULES, écrit à la main (voir unitUpper)
	unit: string,          -- suffixe pluriel (ex. "7 victoires") — aussi utilisé tel quel pour l'en-tête de colonne
	unitSingular: string,  -- suffixe singulier, utilisé quand le score vaut exactement 1 (ex. "1 victoire")
	unitUpper: string,     -- pluriel en MAJUSCULES, écrit à la main : `string.upper` (Luau, ASCII only) casse les accents ("D'AFFILéE" au lieu de "D'AFFILÉE", "SéRIE" au lieu de "SÉRIE")
	icon: string,
}

local BOARDS: { BoardDef } = {
	{ id = "gp",     label = "Goofy Points",    labelUpper = "GOOFY POINTS",    unit = "GP",                   unitSingular = "GP",                  unitUpper = "GP",                   icon = "🏆" },
	{ id = "wins",   label = "Victoires",       labelUpper = "VICTOIRES",       unit = "victoires",            unitSingular = "victoire",             unitUpper = "VICTOIRES",            icon = "🥊" },
	{ id = "streak", label = "Meilleure série", labelUpper = "MEILLEURE SÉRIE", unit = "victoires d'affilées", unitSingular = "victoire d'affilée",   unitUpper = "VICTOIRES D'AFFILÉES", icon = "🔥" },
}

export type PeriodDef = {
	id: "alltime" | "weekly",
	label: string,
}

local PERIODS: { PeriodDef } = {
	{ id = "alltime", label = "ALL TIME" },
	{ id = "weekly",  label = "HEBDO" },
}

-- Accord singulier/pluriel : "1 victoire" mais "2 victoires" / "1 victoire d'affilée" mais
-- "5 victoires d'affilées". GP n'a pas de forme différente (déjà une abréviation invariable).
local function FormatScore(board: BoardDef, score: number): string
	local unit = (score == 1) and board.unitSingular or board.unit
	return tostring(score) .. " " .. unit
end

return {
	BOARDS       = BOARDS,
	PERIODS      = PERIODS,
	FormatScore  = FormatScore,
}
