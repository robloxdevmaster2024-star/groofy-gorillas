--!nonstrict
-- Dodgeball.luau — Gamemode brawl de ballons (Goofy Gorillas)

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameStatus = ReplicatedStorage:WaitForChild("GameStatus")

-- ===== RemoteEvents créés dès le chargement du module =====
-- Ainsi le client peut faire WaitForChild sans timeout dès le démarrage du serveur.
local eventsFolder = ReplicatedStorage:FindFirstChild("DodgeballEvents")
if not eventsFolder then
	eventsFolder = Instance.new("Folder")
	eventsFolder.Name = "DodgeballEvents"
	eventsFolder.Parent = ReplicatedStorage
end
local function getOrCreate(parent, name)
	return parent:FindFirstChild(name) or Instance.new("RemoteEvent", parent)
end
local throwEvent  = getOrCreate(eventsFolder, "Throw");  throwEvent.Name  = "Throw"
local activeEvent = getOrCreate(eventsFolder, "Active"); activeEvent.Name = "Active"

-- ===== Métadonnées =====
local Dodgeball = {}

Dodgeball.Name        = "Dodgeball"
Dodgeball.Description = "Lance des ballons sur tes adversaires ! Dernier debout gagne."
Dodgeball.MinPlayers  = 2
Dodgeball.RoundDuration = 120
Dodgeball.DefaultSettings = {
	ballSpeed     = 55,  -- studs/s
	throwCooldown = 1.2, -- s entre deux lancers
	ballLifetime  = 6,   -- s avant disparition de la balle
}
Dodgeball.SettingsSchema = {
	{ key = "ballSpeed",     label = "Vitesse des balles (studs/s)", min = 20,  max = 120, step = 5   },
	{ key = "throwCooldown", label = "Délai entre lancers (s)",      min = 0.3, max = 3.0, step = 0.3 },
	{ key = "ballLifetime",  label = "Durée de vie balle (s)",       min = 2,   max = 15,  step = 1   },
}

-- ===== État du round (remis à zéro à chaque Start) =====
local participants : { [Player]: boolean } = {}
local alive        : { [Player]: boolean } = {}
local lastThrow    : { [Player]: number  } = {}
local balls        : { BasePart }          = {}
local connections  : { RBXScriptConnection } = {}
local running      = false
local settings     = Dodgeball.DefaultSettings

-- ===== Helpers =====
local function getHRP(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") or nil
end

local function applyEliminatedLook(player: Player)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then hum.WalkSpeed = 0; hum.JumpHeight = 0 end
	local hl = Instance.new("Highlight")
	hl.Name = "EliminatedHL"
	hl.FillColor = Color3.fromRGB(80, 80, 80)
	hl.OutlineColor = Color3.fromRGB(140, 140, 140)
	hl.FillTransparency = 0.25
	hl.Parent = char
end

local function removeEliminatedLook(player: Player)
	local char = player.Character
	if not char then return end
	local hl = char:FindFirstChild("EliminatedHL")
	if hl then hl:Destroy() end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then hum.WalkSpeed = 16; hum.JumpHeight = 7.2 end
end

local function eliminatePlayer(player: Player, thrower: Player?)
	if not alive[player] then return end
	alive[player] = nil
	applyEliminatedLook(player)
	local msg = thrower and (thrower.Name .. " a éliminé " .. player.Name .. " ! 💥")
	             or (player.Name .. " est éliminé ! 💥")
	GameStatus:FireAllClients({ kind = "banner", text = msg })
end

local function spawnBall(thrower: Player, direction: Vector3)
	local hrp = getHRP(thrower)
	if not hrp then return end

	local speed = settings.ballSpeed or 55
	local dir   = direction.Unit
	-- Spawn devant le joueur (4 studs) pour éviter la self-collision immédiate
	local spawnPos = hrp.Position + dir * 4 + Vector3.new(0, 0.5, 0)

	local ball = Instance.new("Part")
	ball.Name     = "DodgeballBall"
	ball.Shape    = Enum.PartType.Ball
	ball.Size     = Vector3.new(1.4, 1.4, 1.4)
	ball.BrickColor = BrickColor.new("Bright red")
	ball.Material = Enum.Material.SmoothPlastic
	ball.Elasticity = 0.6
	ball.CFrame   = CFrame.new(spawnPos)
	ball.Parent   = workspace
	ball.AssemblyLinearVelocity = dir * speed

	table.insert(balls, ball)

	-- Délai avant activation du Touched (évite le hit immédiat sur le lanceur)
	task.delay(0.2, function()
		if not (ball and ball.Parent and running) then return end
		local touchConn: RBXScriptConnection
		touchConn = ball.Touched:Connect(function(hit)
			if not running then touchConn:Disconnect() return end
			local player = Players:GetPlayerFromCharacter(hit.Parent)
			if player and player ~= thrower and alive[player] then
				eliminatePlayer(player, thrower)
				touchConn:Disconnect()
				task.defer(function() if ball.Parent then ball:Destroy() end end)
				-- Retire de la liste
				for i, b in balls do
					if b == ball then table.remove(balls, i) break end
				end
			end
		end)
		table.insert(connections, touchConn)
	end)

	-- Durée de vie
	task.delay(settings.ballLifetime or 6, function()
		if ball and ball.Parent then
			ball:Destroy()
			for i, b in balls do
				if b == ball then table.remove(balls, i) break end
			end
		end
	end)
end

-- ===== Cycle de vie =====
function Dodgeball.Start(ctx)
	participants, alive, lastThrow, balls, connections = {}, {}, {}, {}, {}
	running  = true
	settings = ctx.Settings or Dodgeball.DefaultSettings

	for _, player in ctx.Players do
		participants[player] = true
		alive[player]        = true
	end

	-- Active les contrôles côté clients
	activeEvent:FireAllClients(true)

	-- Écoute les lancers clients
	local throwConn = throwEvent.OnServerEvent:Connect(function(player, direction)
		if not running then return end
		if not alive[player] or not participants[player] then return end
		if typeof(direction) ~= "Vector3" then return end

		-- Validation direction (garde-fou anti-cheat NaN/inf)
		local dir = direction.Unit
		if dir ~= dir or dir.Magnitude < 0.9 then return end

		-- Cooldown côté serveur
		local now = tick()
		if lastThrow[player] and (now - lastThrow[player]) < (settings.throwCooldown or 1.2) then return end
		lastThrow[player] = now

		spawnBall(player, dir)
	end)
	table.insert(connections, throwConn)

	GameStatus:FireAllClients({ kind = "banner", text = "🔴 DODGEBALL — visez bien !" })
end

function Dodgeball.CheckWin()
	local alivePlayers = {}
	for player in alive do
		if player.Parent then table.insert(alivePlayers, player) end
	end

	if #alivePlayers <= 1 then
		if #alivePlayers == 1 then
			return alivePlayers, alivePlayers[1].Name .. " est le dernier debout ! 🏆"
		else
			return {}, "Tout le monde est éliminé !"
		end
	end
	return nil, nil
end

function Dodgeball.ResolveTimeout()
	local survivors = {}
	for player in alive do
		if player.Parent then table.insert(survivors, player) end
	end
	return survivors, "Temps écoulé ! " .. #survivors .. " survivant(s) en vie."
end

function Dodgeball.OnPlayerRemoving(player)
	participants[player] = nil
	alive[player]        = nil
	lastThrow[player]    = nil
end

function Dodgeball.Stop()
	running = false

	for _, conn in connections do
		pcall(function() conn:Disconnect() end)
	end
	connections = {}

	for _, ball in balls do
		pcall(function() ball:Destroy() end)
	end
	balls = {}

	for player in participants do
		removeEliminatedLook(player)
	end

	activeEvent:FireAllClients(false)

	participants, alive, lastThrow = {}, {}, {}
end

return Dodgeball
