--!nonstrict
-- AchievementsConfig.luau — Définitions des succès (partagé server/client).

return {
	-- ===== Progression =====
	{ id = "first_gp",      icon = "⭐", name = "Premier point !",        desc = "Gagne ton premier GP." },
	{ id = "gp_100",        icon = "🍌", name = "Gorille en herbe",        desc = "Cumule 100 GP." },
	{ id = "gp_500",        icon = "🦍", name = "Gros singe",              desc = "Cumule 500 GP." },
	{ id = "gp_1000",       icon = "👑", name = "Grand singe",             desc = "Cumule 1 000 GP." },
	{ id = "level_5",       icon = "🎯", name = "Apprenti gorille",        desc = "Atteins le niveau 5." },
	{ id = "level_10",      icon = "🔥", name = "Gorille confirmé",        desc = "Atteins le niveau 10." },
	{ id = "level_20",      icon = "💎", name = "Légende des jungles",     desc = "Atteins le niveau maximum." },

	-- ===== Gameplay =====
	{ id = "first_win",     icon = "🏆", name = "Première victoire",       desc = "Gagne ton premier round." },
	{ id = "win_5",         icon = "🌟", name = "En route vers la gloire", desc = "Gagne 5 rounds." },
	{ id = "win_25",        icon = "🎖️", name = "Champion des gorilles",   desc = "Gagne 25 rounds." },
	{ id = "infector_win",  icon = "🦠", name = "Contaminateur",           desc = "Gagne un round Infector en tant qu'infecteur." },
	{ id = "survivor",      icon = "🛡️", name = "Indestructible",          desc = "Survie un round Infector sans jamais être infecté." },
	{ id = "dodgeball_win", icon = "🔴", name = "As du ballon",            desc = "Gagne un round Dodgeball." },

	-- ===== Easter eggs (cachés jusqu'au déverrouillage) =====
	{ id = "sweat",         icon = "💦", name = "Tu transpires",           desc = "Joue 50 rounds.", hidden = true },
}
