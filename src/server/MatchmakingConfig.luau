--!nonstrict
-- MatchmakingConfig.luau — Interrupteur unique pour le matchmaking cross-serveur (voir
-- MatchmakingService.luau, le branchement dans LobbyService.luau, et la détection "serveur de
-- match" dans RoundManager.server.luau).
--
-- ⏸️ ACTUELLEMENT SUSPENDU (mis en pause à la demande, 2026) : TeleportService:ReserveServer
-- renvoyait une 403 Forbidden en test Studio (cause probable : "Enable Studio Access to API
-- Services" décoché dans Game Settings > Security, et/ou le fait que le test cross-serveur réel
-- ne peut de toute façon être validé qu'en jeu publié, pas juste dans "Test → Clients and
-- Servers"). Pour ne pas bloquer le travail en cours, on revient au comportement "ancienne
-- version" : le bouton "Jouer" rejoint directement la file LOCALE (même serveur uniquement),
-- exactement comme avant l'ajout du matchmaking cross-serveur.
--
-- Rien n'a été supprimé : MatchmakingService.luau, la détection de serveur de match dans
-- RoundManager.server.luau, et le branchement dans LobbyService.luau sont tous encore en place,
-- juste gardés (`if MatchmakingConfig.Enabled then ...`) derrière ce flag. Pour reprendre :
--   1. Repasser Enabled à true ci-dessous.
--   2. Vérifier "Enable Studio Access to API Services" (Game Settings > Security).
--   3. Tester en jeu PUBLIÉ (pas juste Studio local) avec deux serveurs réels — voir
--      docs/ROADMAP.md, section "Matchmaking cross-serveur", pour le critère de validation exact.
return {
	Enabled = false,
}
