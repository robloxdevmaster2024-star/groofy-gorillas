--!nonstrict
-- AchievementService.luau — Déverrouillage et diffusion des succès.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- RemoteEvent (créé au chargement)
local eventsFolder = ReplicatedStorage:FindFirstChild("AchievementEvents")
if not eventsFolder then
	eventsFolder = Instance.new("Folder")
	eventsFolder.Name = "AchievementEvents"
	eventsFolder.Parent = ReplicatedStorage
end
local unlockEvent = eventsFolder:FindFirstChild("Unlock") or Instance.new("RemoteEvent", eventsFolder)
unlockEvent.Name = "Unlock"

local AchievementService = {}

-- ===== Conditions par trigger =====
-- check(profile, data?) → bool
-- Appelées uniquement si le succès n'est pas encore débloqué.

local CONDITIONS: { [string]: { { id: string, check: (any, any?) -> boolean } } } = {

	gp_change = {
		{ id = "first_gp",  check = function(p) return p.goofyPoints >= 1    end },
		{ id = "gp_100",    check = function(p) return p.goofyPoints >= 100   end },
		{ id = "gp_500",    check = function(p) return p.goofyPoints >= 500   end },
		{ id = "gp_1000",   check = function(p) return p.goofyPoints >= 1000  end },
		{ id = "level_5",   check = function(p) return p.level >= 5           end },
		{ id = "level_10",  check = function(p) return p.level >= 10          end },
		{ id = "level_20",  check = function(p) return p.level >= 20          end },
	},

	round_win = {
		{ id = "first_win",     check = function(p, d) return true end },
		{ id = "win_5",         check = function(p, d) return p.stats.gamesWon >= 5  end },
		{ id = "win_25",        check = function(p, d) return p.stats.gamesWon >= 25 end },
		{ id = "infector_win",  check = function(p, d) return d.gamemode == "Infector" and d.role == "infector" end },
		{ id = "survivor",      check = function(p, d) return d.gamemode == "Infector" and d.role == "survivor" end },
		{ id = "dodgeball_win", check = function(p, d) return d.gamemode == "Dodgeball" end },
	},

	round_played = {
		{ id = "sweat", check = function(p, d) return p.stats.gamesPlayed >= 50 end },
	},
}

-- ===== API =====

-- Déverrouille un succès et notifie le client.
function AchievementService.Unlock(player: Player, profile, id: string)
	if profile.achievements[id] then return end  -- déjà obtenu
	profile.achievements[id] = true
	unlockEvent:FireClient(player, id)
	print("[AchievementService]", player.Name, "→", id)
end

-- Vérifie les conditions pour un trigger donné et déverrouille au besoin.
-- profile  : table renvoyé par DataService.GetProfile(player) — modifié en place
-- trigger  : "gp_change" | "round_win" | "round_played"
-- data     : contexte optionnel (ex. { gamemode = "Dodgeball", role = "winner" })
function AchievementService.Check(player: Player, profile, trigger: string, data)
	if not profile then return end
	local list = CONDITIONS[trigger]
	if not list then return end
	for _, entry in list do
		if not profile.achievements[entry.id] then
			local ok, result = pcall(entry.check, profile, data)
			if ok and result then
				AchievementService.Unlock(player, profile, entry.id)
			end
		end
	end
end

print("[AchievementService] démarré ✅")
return AchievementService
