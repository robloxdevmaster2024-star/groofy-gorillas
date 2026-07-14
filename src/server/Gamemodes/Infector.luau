--!nonstrict
-- Infector.luau — « Le Clown de nuit » : le clown chasse les enfants à la batte,
-- un coup réussi les propulse (knockback façon Smash Bros) et les transforme en clowns.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting          = game:GetService("Lighting")
local GameStatus = ReplicatedStorage:WaitForChild("GameStatus") -- créé par le RoundManager

-- ===== RemoteEvents créés dès le chargement du module =====
local eventsFolder = ReplicatedStorage:FindFirstChild("InfectorEvents")
if not eventsFolder then
	eventsFolder = Instance.new("Folder")
	eventsFolder.Name = "InfectorEvents"
	eventsFolder.Parent = ReplicatedStorage
end
local function getOrCreate(parent, name)
	return parent:FindFirstChild(name) or Instance.new("RemoteEvent", parent)
end
local swingEvent    = getOrCreate(eventsFolder, "Swing");    swingEvent.Name    = "Swing"
local setActiveEvent = getOrCreate(eventsFolder, "SetActive"); setActiveEvent.Name = "SetActive"

local Infector = {}

-- ===== Métadonnées =====
Infector.Name = "Infector"
Infector.Description = "🤡 Un clown chasse les enfants à la batte, la nuit, dans l'aire de jeu."
Infector.MinPlayers = 2
Infector.RoundDuration = 300 -- 5 minutes
Infector.DefaultSettings = {
	startingInfectors     = 1,   -- nb de clowns au départ
	meleeRange            = 8,   -- portée du swing (studs)
	meleeCooldown         = 1.0, -- s entre deux coups de batte
	knockbackForce        = 90,  -- studs/s, composante horizontale
	knockbackUpward       = 40,  -- studs/s, composante verticale
	knockbackStunDuration = 0.8, -- s pendant lesquelles la victime ne contrôle plus son perso
}
Infector.SettingsSchema = {
	{ key = "startingInfectors", label = "Clowns de départ",        min = 1,   max = 5,  step = 1   },
	{ key = "meleeRange",        label = "Portée de la batte (studs)", min = 4,   max = 15, step = 1   },
	{ key = "meleeCooldown",     label = "Délai entre coups (s)",    min = 0.3, max = 3.0, step = 0.1 },
	{ key = "knockbackForce",    label = "Force du knockback",       min = 30,  max = 200, step = 10  },
}

-- Cône de frappe devant le clown (dot product minimal entre direction visée et direction vers la cible)
local MELEE_CONE_DOT = 0.6 -- ≈ 53°

-- ===== État du round (remis à zéro à chaque Start) =====
local participants: { [Player]: boolean } = {}
local infected: { [Player]: boolean } = {}
local originalInfectors: { [Player]: boolean } = {}  -- infecteurs du départ uniquement
local lastSwing: { [Player]: number } = {}
local connections: { RBXScriptConnection } = {}
local running = false
local settings = Infector.DefaultSettings
local savedLighting: { [string]: any }? = nil

-- ===== Helpers =====
local function getHRP(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") or nil
end

local function applyInfectedLook(player: Player)
	local char = player.Character
	if not char or char:FindFirstChild("InfectedHighlight") then return end
	local hl = Instance.new("Highlight")
	hl.Name = "InfectedHighlight"
	hl.FillColor = Color3.fromRGB(230, 30, 130)   -- rose/rouge criard "clown"
	hl.OutlineColor = Color3.fromRGB(255, 255, 255)
	hl.FillTransparency = 0.4
	hl.Parent = char
end

local function removeInfectedLook(player: Player)
	local char = player.Character
	local hl = char and char:FindFirstChild("InfectedHighlight")
	if hl then hl:Destroy() end
end

local function applyDarkAtmosphere()
	savedLighting = {
		Brightness      = Lighting.Brightness,
		ClockTime       = Lighting.ClockTime,
		Ambient         = Lighting.Ambient,
		OutdoorAmbient  = Lighting.OutdoorAmbient,
		FogColor        = Lighting.FogColor,
		FogStart        = Lighting.FogStart,
		FogEnd          = Lighting.FogEnd,
	}
	Lighting.ClockTime      = 0 -- minuit
	Lighting.Brightness     = 1
	Lighting.Ambient        = Color3.fromRGB(20, 20, 30)
	Lighting.OutdoorAmbient = Color3.fromRGB(15, 15, 25)
	Lighting.FogColor       = Color3.fromRGB(10, 10, 15)
	Lighting.FogStart       = 15
	Lighting.FogEnd         = 90
end

local function restoreAtmosphere()
	if not savedLighting then return end
	for key, value in savedLighting do
		Lighting[key] = value
	end
	savedLighting = nil
end

-- Propulsion façon Smash Bros : vélocité d'impact + arc vertical, contrôle coupé le temps du vol.
local function applyKnockback(player: Player, direction: Vector3)
	local char = player.Character
	local hrp = getHRP(player)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then return end

	local horizontal = direction * (settings.knockbackForce or 90)
	local vertical = Vector3.new(0, settings.knockbackUpward or 40, 0)

	hum.PlatformStand = true
	hrp.AssemblyLinearVelocity = horizontal + vertical

	task.delay(settings.knockbackStunDuration or 0.8, function()
		if hum and hum.Parent then
			hum.PlatformStand = false
		end
	end)
end

local function grantWeapon(player: Player)
	setActiveEvent:FireClient(player, true)
end

local function infectPlayer(player: Player, knockbackDir: Vector3?)
	if infected[player] then return end
	infected[player] = true
	applyInfectedLook(player)
	if knockbackDir then
		applyKnockback(player, knockbackDir)
	end
	grantWeapon(player)
	GameStatus:FireClient(player, { kind = "banner", text = "🤡 Tu es devenu un CLOWN ! Chasse les autres enfants !" })
end

-- Trouve la victime la plus proche dans le cône de frappe devant le clown.
local function findMeleeTarget(attacker: Player, aimDir: Vector3): Player?
	local attackerHRP = getHRP(attacker)
	if not attackerHRP then return nil end

	local range = settings.meleeRange or 8
	local best: Player? = nil
	local bestDist = math.huge

	for target in participants do
		if target ~= attacker and not infected[target] then
			local targetHRP = getHRP(target)
			if targetHRP then
				local offset = targetHRP.Position - attackerHRP.Position
				local dist = offset.Magnitude
				if dist <= range and dist > 0.01 then
					local dot = aimDir:Dot(offset.Unit)
					if dot >= MELEE_CONE_DOT and dist < bestDist then
						best = target
						bestDist = dist
					end
				end
			end
		end
	end

	return best
end

-- ===== Cycle de vie =====
function Infector.Start(ctx)
	participants, infected, originalInfectors, lastSwing, connections = {}, {}, {}, {}, {}
	running = true
	settings = ctx.Settings or Infector.DefaultSettings

	for _, player in ctx.Players do
		participants[player] = true
	end

	applyDarkAtmosphere()

	-- choisit le(s) clown(s) de départ au hasard
	local pool = table.clone(ctx.Players)
	for _ = 1, math.min(settings.startingInfectors or 1, #pool) do
		local chosen = table.remove(pool, math.random(1, #pool))
		if chosen then
			infected[chosen] = true
			originalInfectors[chosen] = true
			applyInfectedLook(chosen)
			grantWeapon(chosen)
			GameStatus:FireClient(chosen, { kind = "banner", text = "🤡 Tu es LE CLOWN ! Chasse les enfants à la batte !" })
		end
	end

	GameStatus:FireAllClients({ kind = "banner", text = "🎪 LE CLOWN DE NUIT — fuyez avant d'être frappé !" })

	-- Écoute les coups de batte des clowns
	local swingConn = swingEvent.OnServerEvent:Connect(function(player, aimDirection)
		if not running then return end
		if not infected[player] or not participants[player] then return end
		if typeof(aimDirection) ~= "Vector3" then return end

		local dir = aimDirection.Unit
		if dir ~= dir or dir.Magnitude < 0.9 then return end -- garde-fou NaN/inf

		local now = tick()
		if lastSwing[player] and (now - lastSwing[player]) < (settings.meleeCooldown or 1.0) then return end
		lastSwing[player] = now

		local target = findMeleeTarget(player, dir)
		if target then
			local attackerHRP = getHRP(player)
			local targetHRP = getHRP(target)
			local knockDir = attackerHRP and targetHRP
				and (targetHRP.Position - attackerHRP.Position).Unit
				or dir
			infectPlayer(target, knockDir)
			GameStatus:FireAllClients({ kind = "banner", text = target.Name .. " a été transformé en clown ! 🤡" })
		end
	end)
	table.insert(connections, swingConn)
end

function Infector.CheckWin()
	local survivors, infectors = {}, {}
	for player in participants do
		if player.Parent then
			table.insert(infected[player] and infectors or survivors, player)
		end
	end
	if #infectors == 0 then return survivors, "Plus d'infecteurs en jeu !" end
	if #survivors == 0 then
		-- Seuls les infecteurs ORIGINAUX gagnent (les contaminés en cours de round ont perdu)
		local winners = {}
		for player in originalInfectors do
			if player.Parent then table.insert(winners, player) end
		end
		return winners, "Tous les survivants ont été infectés !"
	end
	return nil, nil -- le round continue
end

function Infector.ResolveTimeout()
	local survivors = {}
	for player in participants do
		if player.Parent and not infected[player] then
			table.insert(survivors, player)
		end
	end
	return survivors, "Temps écoulé ! Les survivants ont résisté. 🛡️"
end

-- Appelé par le RoundManager avant Stop() pour enrichir le contexte achievements.
function Infector.GetWinnerRoles(winners: { Player })
	local roles = {}
	for _, player in winners do
		roles[player] = originalInfectors[player] and "infector" or "survivor"
	end
	return roles
end

function Infector.OnPlayerRemoving(player)
	participants[player] = nil
	infected[player] = nil
	originalInfectors[player] = nil
	lastSwing[player] = nil
end

function Infector.Stop()
	running = false

	for _, conn in connections do
		pcall(function() conn:Disconnect() end)
	end
	connections = {}

	for player in participants do
		removeInfectedLook(player)
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum.PlatformStand = false end
	end

	setActiveEvent:FireAllClients(false)
	restoreAtmosphere()

	participants, infected, originalInfectors, lastSwing = {}, {}, {}, {}
end

return Infector