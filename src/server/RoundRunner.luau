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

local RoundRunner = {}

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

	local ctx = {
		Players      = players,
		Settings     = settings,
		Map          = map,
		SpawnCFrames = spawnCFrames,
	}

	local leaveConn = Players.PlayerRemoving:Connect(function(p)
		gamemode.OnPlayerRemoving(p)
	end)

	-- Boucle principale
	gamemode.Start(ctx)
	local winners, reason
	for elapsed = 1, gamemode.RoundDuration do
		task.wait(1)
		timerText("⏱️ " .. (gamemode.RoundDuration - elapsed) .. "s")
		winners, reason = gamemode.CheckWin()
		if winners then break end
	end
	if not winners then
		winners, reason = gamemode.ResolveTimeout()
	end

	-- Métadonnées avant Stop() (certains modes effacent leur état dans Stop)
	local winnerRoles = gamemode.GetWinnerRoles and gamemode.GetWinnerRoles(winners) or {}
	local winnerSet   = {}
	for _, w in winners do winnerSet[w] = true end

	gamemode.Stop()
	leaveConn:Disconnect()

	local names = {}
	for _, w in winners do table.insert(names, w.Name) end
	banner("🏆 " .. (reason or "Fin du round") .. " — " ..
		(#names > 0 and table.concat(names, ", ") or "Personne"))

	-- GP + stats + achievements
	for _, p in players do
		if not p.Parent then continue end
		local profile = DataService.GetProfile(p)
		if not profile then continue end

		profile.stats.gamesPlayed += 1
		if winnerSet[p] then profile.stats.gamesWon += 1 end

		local pts = winnerSet[p] and PlayerConfig.POINTS.WINNER or PlayerConfig.POINTS.PARTICIPANT
		DataService.AddGoofyPoints(p, pts)

		if winnerSet[p] then
			AchievementService.Check(p, profile, "round_win", {
				gamemode = gamemode.Name,
				role     = winnerRoles[p] or "winner",
			})
		end
		AchievementService.Check(p, profile, "round_played", { gamemode = gamemode.Name })
	end

	task.spawn(LeaderboardService.Refresh)

	task.wait(5)
	MapManager.Unload(map)
	timerText("")
end

return RoundRunner
