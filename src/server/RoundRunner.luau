--!nonstrict
-- RoundRunner.luau — Exécute un round complet (map → gameplay → récompenses).
-- Appelé par LobbyService. Yields jusqu'à la fin du round.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService        = require(script.Parent.DataService)
local MapManager         = require(script.Parent.MapManager)
local LeaderboardService = require(script.Parent.LeaderboardService)
local AchievementService = require(script.Parent.AchievementService)
local PlayerConfig       = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("PlayerConfig")
)

local GameStatus = ReplicatedStorage:WaitForChild("GameStatus")

-- RemoteEvent : résumé de fin de round (classement + GP gagnés + rejouer), voir EndScreen.client.luau.
-- Diffusé uniquement aux PARTICIPANTS du round (pas à tout le serveur/lobby).
local RoundEndSummary = ReplicatedStorage:FindFirstChild("RoundEndSummary")
if not RoundEndSummary then
	RoundEndSummary = Instance.new("RemoteEvent")
	RoundEndSummary.Name   = "RoundEndSummary"
	RoundEndSummary.Parent = ReplicatedStorage
end

local RoundRunner = {}

-- ===== Victoires "vidées" (rounds avortés par déconnexions en cascade) =====
-- Une victoire ne doit compter comme une VRAIE victoire (bonus GP vainqueur, gamesWon, série de
-- victoires, succès "round_win") que si la partie a réellement eu lieu. Sans ça, un round qui se
-- termine en quelques secondes parce que la moitié des joueurs a quitté produirait un "gagnant"
-- qui n'a en pratique rien accompli. On ne pénalise PAS les victoires rapides mais légitimes
-- (personne n'est parti) : les deux conditions doivent être réunies.
local MIN_MEANINGFUL_ROUND_DURATION = 20 -- s : en dessous, une fin de round est "précoce"
local VOID_DISCONNECT_RATIO = 0.5 -- + de la moitié des participants du round partis

local function banner(text)
	GameStatus:FireAllClients({ kind = "banner", text = text })
	print("[RoundRunner]", text)
end

local function timerText(text)
	GameStatus:FireAllClients({ kind = "timer", text = text })
end

local function waitForCharacter(player: Player)
	local char = player.Character or player.CharacterAdded:Wait()
	char:WaitForChild("HumanoidRootPart", 5)
	return char
end

-- Exécute un round complet. Yields jusqu'à la fin.
-- gamemode : module conforme au contrat Gamemode
-- players  : participants (liste)
-- settings : settings avec overrides appliqués
function RoundRunner.RunRound(gamemode, players: { Player }, settings)
	-- Charge/reset les personnages
	for _, p in players do
		pcall(function() p:LoadCharacter() end)
	end

	-- Map
	local map, spawnCFrames = MapManager.LoadRandom(#players)

	-- Attend chaque personnage et téléporte
	for i, p in players do
		pcall(function()
			local char = waitForCharacter(p)
			local hrp  = char:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp.CFrame = spawnCFrames[((i - 1) % #spawnCFrames) + 1]
			end
		end)
	end

	banner("▶️ " .. gamemode.Name .. " commence !")
	task.wait(1.5)

	-- Total des GP gagnés PENDANT ce round précis (actions + bonus de fin), pour l'écran de fin de
	-- partie (voir EndScreen.client.luau) — distinct du total cumulé (lifetime) du profil.
	local roundGPEarned: { [Player]: number } = {}
	local function award(player: Player, amount: number)
		DataService.AddGoofyPoints(player, amount)
		roundGPEarned[player] = (roundGPEarned[player] or 0) + amount
	end

	-- Récompenses d'ACTION (voir PlayerConfig.POINTS.KILL/FIRST_BLOOD/etc.) : accordées EN DIRECT
	-- pendant le round via ce callback injecté dans le ctx, plutôt qu'accumulées et distribuées à
	-- la fin comme les stats/streaks. Deux raisons : le joueur voit sa barre de GP progresser tout
	-- de suite (`DataService.AddGoofyPoints` déclenche déjà `DataUpdated`), et ça reste
	-- naturellement dû même si la victoire finale du round est vidée plus tard (rien à recalculer
	-- après coup). Le gamemode reste décorrélé de DataService/ProfileStore : il ne voit que cette
	-- fonction, pas la persistance elle-même.
	local function awardActionGP(player: Player, amount: number)
		if not player.Parent then return end
		local profile = DataService.GetProfile(player)
		if not profile then return end
		award(player, amount)
	end

	local ctx = {
		Players      = players,
		Settings     = settings,
		Map          = map,
		SpawnCFrames = spawnCFrames,
		AwardActionGP = awardActionGP,
	}

	local leaveConn = Players.PlayerRemoving:Connect(function(p)
		gamemode.OnPlayerRemoving(p)
	end)

	-- Boucle principale
	local loopStartTime = os.clock()
	gamemode.Start(ctx)
	-- Affichage immédiat (durée pleine) : sans ça, le timer restait invisible pendant le premier
	-- task.wait(1) de la boucle ci-dessous, alors que gamemode.Start() vient déjà d'activer les
	-- autres boutons du round (Taunt, Roster, compte à rebours du cri...) — décalage visible d'~1s
	-- entre le timer et le reste du HUD au lancement d'une partie.
	timerText("⏱️ " .. gamemode.RoundDuration .. "s")
	local winners, reason
	local endedEarlyAt: number? = nil
	-- Chrono affiché basé sur le temps RÉEL écoulé (os.clock()), pas sur un simple comptage
	-- d'itérations : task.wait(1) ne garantit jamais exactement 1s (léger dépassement à chaque
	-- appel selon la charge serveur), et ces dépassements s'accumulaient au fil de la boucle —
	-- le chrono affiché dérivait de plusieurs secondes en fin de round par rapport au temps réel
	-- (et donc par rapport aux récompenses de survie de ClownSurvival.luau, elles basées sur
	-- os.clock() en continu, donc déjà précises).
	for _ = 1, gamemode.RoundDuration do
		task.wait(1)
		local trueElapsed = math.min(gamemode.RoundDuration, math.floor(os.clock() - loopStartTime))
		timerText("⏱️ " .. (gamemode.RoundDuration - trueElapsed) .. "s")
		winners, reason = gamemode.CheckWin()
		if winners then
			endedEarlyAt = trueElapsed
			break
		end
		if trueElapsed >= gamemode.RoundDuration then break end
	end
	if not winners then
		winners, reason = gamemode.ResolveTimeout()
	end

	-- Métadonnées avant Stop() (certains modes effacent leur état dans Stop)
	local winnerRoles = gamemode.GetWinnerRoles and gamemode.GetWinnerRoles(winners) or {}
	local killCounts  = gamemode.GetKillCounts and gamemode.GetKillCounts() or {}
	-- Statut ACTUEL de TOUS les participants (pas juste les gagnants) — pour l'écran de fin de
	-- partie (regroupement par section, voir EndScreen.client.luau). Distinct de winnerRoles : voir
	-- le commentaire de GetParticipantRoles() dans ClownSurvival.luau.
	local participantRoles = gamemode.GetParticipantRoles and gamemode.GetParticipantRoles() or {}
	local winnerSet   = {}
	for _, w in winners do winnerSet[w] = true end

	-- Bonus "jamais touché" (survivant qui a fini le round sans jamais être contaminé/éliminé) :
	-- une action réelle du round, pas un bonus de victoire — reste due même si la victoire finale
	-- est vidée (voir plus bas).
	local neverTouchedSet = {}
	if gamemode.GetNeverTouchedSurvivors then
		for _, p in gamemode.GetNeverTouchedSurvivors() do
			neverTouchedSet[p] = true
		end
	end

	-- Une fin précoce (avant ResolveTimeout, donc via CheckWin) ET beaucoup de départs = victoire
	-- vidée. Un ResolveTimeout n'est jamais vidé : la partie est allée à son terme normal.
	local stillConnected = 0
	for _, p in players do
		if p.Parent then stillConnected += 1 end
	end
	local disconnectRatio = #players > 0 and (#players - stillConnected) / #players or 0
	local voidedVictory = endedEarlyAt ~= nil
		and endedEarlyAt < MIN_MEANINGFUL_ROUND_DURATION
		and disconnectRatio > VOID_DISCONNECT_RATIO

	gamemode.Stop()
	leaveConn:Disconnect()

	-- Pas de liste de noms dans le bandeau : avec beaucoup de gagnants (ex. toute l'équipe
	-- survivante), le message devenait bien trop long. Le `reason` suffit à dire qui a gagné
	-- (camp clown/survivant), sans lister chaque joueur individuellement.
	if voidedVictory then
		banner("⏱️ Partie écourtée par des déconnexions — victoire non comptabilisée.")
	else
		banner("🏆 " .. (reason or "Fin du round") .. (#winners == 0 and " — Personne n'a gagné" or ""))
	end

	-- GP + stats + achievements
	for _, p in players do
		if not p.Parent then continue end
		local profile = DataService.GetProfile(p)
		if not profile then continue end

		profile.stats.gamesPlayed += 1

		-- Coups réussis en tant que clown (Clown Survival) : une action pendant la partie, pas une
		-- récompense de victoire — reste due même si la victoire elle-même est vidée (voir plus bas).
		local kills = killCounts[p] or 0
		if kills > 0 then
			profile.stats.totalClownKills = (profile.stats.totalClownKills or 0) + kills
		end

		-- Victoire vidée (voir MIN_MEANINGFUL_ROUND_DURATION/VOID_DISCONNECT_RATIO) : personne
		-- n'est traité comme vainqueur pour les stats/récompenses de victoire, mais la
		-- participation (GP, gamesPlayed, succès "round_played") reste due à ceux qui sont
		-- restés jusqu'au bout — ce n'est pas de leur faute si la partie s'est vidée.
		local isRealWin = winnerSet[p] and not voidedVictory

		if isRealWin then
			profile.stats.gamesWon += 1
			local role = winnerRoles[p]
			if role == "clown" then
				profile.stats.clownWins = (profile.stats.clownWins or 0) + 1
			elseif role == "survivor" then
				profile.stats.survivorWins = (profile.stats.survivorWins or 0) + 1
			end

			LeaderboardService.UpdateScore("wins", "alltime", p.UserId, profile.stats.gamesWon)
			local weeklyWin = DataService.EnsureCurrentWeek(p)
			if weeklyWin then
				weeklyWin.wins += 1
				LeaderboardService.UpdateScore("wins", "weekly", p.UserId, weeklyWin.wins)
			end
		end

		-- Win streak par gamemode : victoires consécutives sur CE mode précis, remise à 0 dès
		-- qu'un round de ce mode est perdu. bestStreaks garde le record jamais atteint. Gelée
		-- (ni incrémentée ni remise à 0) si la victoire est vidée : ce round ne compte pas.
		if not voidedVictory then
			local streak = isRealWin and (profile.stats.winStreaks[gamemode.Name] or 0) + 1 or 0
			profile.stats.winStreaks[gamemode.Name] = streak
			if streak > (profile.stats.bestStreaks[gamemode.Name] or 0) then
				profile.stats.bestStreaks[gamemode.Name] = streak
			end

			-- Classement "Meilleure série" : un seul nombre par joueur, le record tous gamemodes
			-- confondus (le framework reste générique — un futur 2ᵉ mode avec streaks y contribue
			-- pareil, sans rien à changer ici).
			local bestOverall = 0
			for _, best in profile.stats.bestStreaks do
				bestOverall = math.max(bestOverall, best)
			end
			LeaderboardService.UpdateScore("streak", "alltime", p.UserId, bestOverall)

			local weeklyStreak = DataService.EnsureCurrentWeek(p)
			if weeklyStreak and streak > weeklyStreak.bestStreak then
				weeklyStreak.bestStreak = streak
			end
			if weeklyStreak then
				LeaderboardService.UpdateScore("streak", "weekly", p.UserId, weeklyStreak.bestStreak)
			end
		end

		local pts = isRealWin and PlayerConfig.POINTS.WINNER or PlayerConfig.POINTS.PARTICIPANT
		award(p, pts)

		if neverTouchedSet[p] then
			award(p, PlayerConfig.POINTS.NEVER_TOUCHED)
		end

		if isRealWin then
			AchievementService.Check(p, profile, "round_win", {
				gamemode = gamemode.Name,
				role     = winnerRoles[p] or "winner",
			})
		end
		AchievementService.Check(p, profile, "round_played", { gamemode = gamemode.Name })
	end

	-- Résumé de fin de round pour l'écran client (voir EndScreen.client.luau) : classement des
	-- PARTICIPANTS (pas tout le serveur), gagnants en tête puis triés par GP gagnés CE round.
	do
		local results = {}
		for _, p in players do
			if not p.Parent then continue end
			table.insert(results, {
				userId   = p.UserId,
				name     = p.Name,
				isWinner = (winnerSet[p] == true) and not voidedVictory,
				-- Statut ACTUEL (clown/survivor/eliminated si le gamemode l'expose, ex. Clown
				-- Survival) en priorité, sinon repli sur le rôle "de gagnant" (autres gamemodes).
				role     = participantRoles[p] or winnerRoles[p],
				gpEarned = roundGPEarned[p] or 0,
			})
		end
		table.sort(results, function(a, b)
			if a.isWinner ~= b.isWinner then return a.isWinner end
			if a.gpEarned ~= b.gpEarned then return a.gpEarned > b.gpEarned end
			return a.name < b.name
		end)

		-- Rôle du camp GAGNANT (ex. "clown"/"survivor" pour Clown Survival) pour que le titre de
		-- l'écran de fin puisse préciser "VICTOIRE DES CLOWNS"/"VICTOIRE DES ENFANTS" plutôt qu'un
		-- générique "VICTOIRE". nil si round vidé ou si le gamemode n'a pas de notion de rôle/camp.
		local winningRole = nil
		if not voidedVictory then
			for _, w in winners do
				-- participantRoles (statut ACTUEL) en priorité sur winnerRoles ici : winnerRoles
				-- rétrograde volontairement les clowns infectés en cours de round à "survivor" pour
				-- les stats/achievements (voir GetWinnerRoles), mais pour le TITRE de l'écran on
				-- veut décrire objectivement quel camp a gagné la manche, pas l'éligibilité aux stats.
				winningRole = participantRoles[w] or winnerRoles[w]
				if winningRole then break end
			end
		end

		local summary = {
			gamemodeName = gamemode.Name,
			reason       = reason,
			voided       = voidedVictory,
			winningRole  = winningRole,
			results      = results,
		}
		for _, p in players do
			if p.Parent then
				RoundEndSummary:FireClient(p, summary)
			end
		end
	end

	LeaderboardService.Flush() -- écrit tout de suite les GP de fin de round (regroupés en temps normal, voir UpdateScore), sinon le Refresh juste après lirait des valeurs pas encore écrites
	task.spawn(LeaderboardService.Refresh)

	task.wait(5)
	MapManager.Unload(map)
	timerText("")
end

return RoundRunner
