--!nonstrict
-- Infector.luau — Premier gamemode de Goofy Gorillas.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameStatus = ReplicatedStorage:WaitForChild("GameStatus") -- créé par le RoundManager

local Infector = {}

-- ===== Métadonnées =====
Infector.Name = "Infector"
Infector.Description = "Fuyez l'infecteur ! Touché = contaminé."
Infector.MinPlayers = 2
Infector.RoundDuration = 90
Infector.DefaultSettings = {
	startingInfectors = 1, -- nb d'infecteurs au départ
	tagDistance = 6,       -- distance de contamination (studs)
}

-- ===== État du round (remis à zéro à chaque Start) =====
local participants: { [Player]: boolean } = {}
local infected: { [Player]: boolean } = {}
local originalInfectors: { [Player]: boolean } = {}  -- infecteurs du départ uniquement
local running = false
local settings = Infector.DefaultSettings

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
	hl.FillColor = Color3.fromRGB(200, 40, 40)
	hl.OutlineColor = Color3.fromRGB(255, 120, 120)
	hl.FillTransparency = 0.5
	hl.Parent = char
end

local function removeInfectedLook(player: Player)
	local char = player.Character
	local hl = char and char:FindFirstChild("InfectedHighlight")
	if hl then hl:Destroy() end
end

local function infectPlayer(player: Player)
	if infected[player] then return end
	infected[player] = true
	applyInfectedLook(player)
	GameStatus:FireClient(player, { kind = "banner", text = "🦠 Tu es INFECTÉ ! Contamine les autres !" })
end

-- ===== Cycle de vie =====
function Infector.Start(ctx)
	participants, infected, originalInfectors, running = {}, {}, {}, true
	settings = ctx.Settings or Infector.DefaultSettings

	for _, player in ctx.Players do
		participants[player] = true
	end

	-- choisit le(s) infecteur(s) de départ au hasard
	local pool = table.clone(ctx.Players)
	for _ = 1, math.min(settings.startingInfectors or 1, #pool) do
		local chosen = table.remove(pool, math.random(1, #pool))
		if chosen then
			infectPlayer(chosen)
			originalInfectors[chosen] = true
		end
	end

	GameStatus:FireAllClients({ kind = "banner", text = "🦍 INFECTOR — fuyez l'infecteur !" })

	-- Boucle de contamination par proximité
	task.spawn(function()
		local tagDistance = settings.tagDistance or 6
		while running do
			-- snapshots (on ne modifie pas une table en l'itérant)
			local infectedList, survivorList = {}, {}
			for p in infected do table.insert(infectedList, p) end
			for p in participants do
				if not infected[p] then table.insert(survivorList, p) end
			end

			for _, infP in infectedList do
				local infHRP = getHRP(infP)
				if infHRP then
					for _, survP in survivorList do
						if not infected[survP] then
							local survHRP = getHRP(survP)
							if survHRP and (infHRP.Position - survHRP.Position).Magnitude <= tagDistance then
								infectPlayer(survP)
								GameStatus:FireAllClients({ kind = "banner", text = survP.Name .. " a été infecté ! 🦠" })
							end
						end
					end
				end
			end
			task.wait(0.25)
		end
	end)
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

function Infector.OnPlayerRemoving(player)
	participants[player] = nil
	infected[player] = nil
	originalInfectors[player] = nil
end

function Infector.Stop()
	running = false
	for player in participants do removeInfectedLook(player) end
	participants, infected, originalInfectors = {}, {}, {}
end

return Infector