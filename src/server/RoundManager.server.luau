--!nonstrict
-- RoundManager.server.luau — Orchestration des parties.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService  = require(script.Parent.DataService)
local MapManager   = require(script.Parent.MapManager)
local PlayerConfig = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("PlayerConfig")
)

-- Crée le RemoteEvent de statut s'il n'existe pas
local GameStatus = ReplicatedStorage:FindFirstChild("GameStatus")
if not GameStatus then
	GameStatus = Instance.new("RemoteEvent")
	GameStatus.Name = "GameStatus"
	GameStatus.Parent = ReplicatedStorage
end

-- Charge les gamemodes (dossier voisin)
local GamemodesFolder = script.Parent:FindFirstChild("Gamemodes")
assert(GamemodesFolder, "❌ Dossier 'Gamemodes' introuvable sous Server. Vérifie src/server/Gamemodes/")
local AVAILABLE_GAMEMODES = {
	require(GamemodesFolder.Infector),
	-- ajoute ici les prochains modes
}

local CONFIG = {
	MIN_PLAYERS = 2,     -- mets 1 pour tester seul, 2 pour un vrai test
	INTERMISSION = 10,
	ROUND_END_PAUSE = 6,
}

-- ===== Helpers =====
local function banner(text)
	GameStatus:FireAllClients({ kind = "banner", text = text })
	print("[RoundManager]", text)
end
local function timer(text)
	GameStatus:FireAllClients({ kind = "timer", text = text })
end
local function waitForCharacter(player)
	local char = player.Character or player.CharacterAdded:Wait()
	char:WaitForChild("HumanoidRootPart", 5)
end

-- ===== Boucle principale =====
task.spawn(function()
	while true do
		-- 1) Attente de joueurs
		while #Players:GetPlayers() < CONFIG.MIN_PLAYERS do
			banner("En attente de joueurs… (" .. #Players:GetPlayers() .. "/" .. CONFIG.MIN_PLAYERS .. ")")
			task.wait(2)
		end

		-- 2) Intermission
		local cancelled = false
		for t = CONFIG.INTERMISSION, 1, -1 do
			banner("Prochaine partie dans " .. t .. "s")
			task.wait(1)
			if #Players:GetPlayers() < CONFIG.MIN_PLAYERS then cancelled = true break end
		end
		if cancelled then continue end

		-- 3) Préparation
		local gamemode     = AVAILABLE_GAMEMODES[math.random(1, #AVAILABLE_GAMEMODES)]
		local participants = Players:GetPlayers()

		-- Charge les personnages et la map
		for _, p in participants do p:LoadCharacter() end
		local map, spawnCFrames = MapManager.LoadRandom(#participants)

		-- Attend chaque personnage puis le téléporte à son spawn
		for i, p in participants do
			waitForCharacter(p)
			local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp.CFrame = spawnCFrames[((i - 1) % #spawnCFrames) + 1]
			end
		end

		banner("▶️ " .. gamemode.Name .. " commence !")
		task.wait(1.5)

		local ctx = {
			Players      = participants,
			Settings     = gamemode.DefaultSettings,
			Map          = map,
			SpawnCFrames = spawnCFrames,
		}

		-- relaie les départs au gamemode pendant le round
		local leaveConn = Players.PlayerRemoving:Connect(function(p)
			gamemode.OnPlayerRemoving(p)
		end)

		-- 4) Round
		gamemode.Start(ctx)
		local winners, reason
		for elapsed = 1, gamemode.RoundDuration do
			task.wait(1)
			timer("⏱️ " .. (gamemode.RoundDuration - elapsed) .. "s")
			winners, reason = gamemode.CheckWin()
			if winners then break end
		end
		if not winners then
			winners, reason = gamemode.ResolveTimeout() -- temps écoulé
		end

		-- 5) Fin
		gamemode.Stop()
		leaveConn:Disconnect()

		local names = {}
		for _, w in winners do table.insert(names, w.Name) end
		banner("🏆 " .. (reason or "Fin du round") .. " — " .. (#names > 0 and table.concat(names, ", ") or "Personne"))

		-- Attribution des Goofy Points
		local winnerSet = {}
		for _, w in winners do winnerSet[w] = true end

		for _, p in participants do
			if p.Parent then  -- encore en jeu
				local pts = winnerSet[p] and PlayerConfig.POINTS.WINNER or PlayerConfig.POINTS.PARTICIPANT
				DataService.AddGoofyPoints(p, pts)
			end
		end

		task.wait(CONFIG.ROUND_END_PAUSE)
		MapManager.Unload(map)
	end
end)

print("[RoundManager] démarré ✅")