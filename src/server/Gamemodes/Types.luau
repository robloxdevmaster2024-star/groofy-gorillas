--!nonstrict
-- Types.luau — Contrat commun à tous les gamemodes de Goofy Gorillas.

export type GamemodeContext = {
	Players: { Player },           -- les joueurs participant à CE round
	Settings: { [string]: any },   -- réglages (défauts + overrides plus tard)
	Map: Instance?,                -- la venue clonée dans Workspace (nil = baseplate)
	SpawnCFrames: { CFrame },      -- points de spawn mélangés (toujours >= 1)
}

export type Gamemode = {
	-- Métadonnées
	Name: string,
	Description: string,
	MinPlayers: number,
	RoundDuration: number,         -- durée max du round (secondes)
	DefaultSettings: { [string]: any },

	-- Cycle de vie (appelé par le RoundManager)
	Start: (ctx: GamemodeContext) -> (),
	CheckWin: () -> ({ Player }?, string?),   -- (gagnants, raison) si fin anticipée, sinon nil
	ResolveTimeout: () -> ({ Player }, string), -- qui gagne quand le temps est écoulé
	OnPlayerRemoving: (player: Player) -> (),
	Stop: () -> (),
}

return {}