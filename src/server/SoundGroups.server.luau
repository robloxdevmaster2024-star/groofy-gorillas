--!strict
-- SoundGroups.server.luau — Crée les SoundGroups globaux ("Music", "SFX") sous SoundService.
-- Répliqués automatiquement à chaque client (SoundService est un service standard) : le menu
-- Profil (ProfileMenu.client.luau) règle localement leur Volume selon les préférences perso du
-- joueur (settings.musicVolume/sfxVolume), sans rien renvoyer au serveur — c'est purement du
-- rendu audio local, pas une donnée de gameplay à valider.
-- Tous les Sound créés ailleurs dans le jeu doivent être assignés à un de ces deux groupes
-- (sound.SoundGroup = ...) pour que le réglage de volume ait un effet.

local SoundService = game:GetService("SoundService")

local function getOrCreateGroup(name: string): SoundGroup
	local existing = SoundService:FindFirstChild(name)
	if existing and existing:IsA("SoundGroup") then
		return existing
	end
	local group = Instance.new("SoundGroup")
	group.Name   = name
	group.Parent = SoundService
	return group
end

getOrCreateGroup("Music")
getOrCreateGroup("SFX")

print("[SoundGroups] Music/SFX prêts sous SoundService")
