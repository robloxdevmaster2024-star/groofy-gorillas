--!strict
-- UISound.luau — Sons d'interface (clics, ouverture de panneau, notification), routés via le
-- SoundGroup "SFX" (voir server/SoundGroups.server.luau) pour respecter le réglage de volume perso
-- du joueur (menu Profil, onglet Réglages).
--
-- ⚠️ IDs PLACEHOLDER : `rbxassetid://0` ne joue aucun son (silencieux, ne lève pas d'erreur) tant
-- qu'un vrai asset n'a pas été choisi — remplacer les 3 valeurs de SOUND_IDS ci-dessous suffit à
-- activer tous les sons de ce module d'un coup, rien d'autre à toucher. Même pattern que le rire du
-- taunt / le whoosh du dash ailleurs dans le projet (voir docs/ROADMAP.md) : le code est prêt,
-- l'asset audio est hors scope code.

local SoundService = game:GetService("SoundService")

local sfxGroup = SoundService:WaitForChild("SFX")

local SOUND_IDS = {
	click  = "rbxassetid://0", -- clic de bouton générique (onglets, Rejouer/Fermer, Jouer...)
	open   = "rbxassetid://0", -- ouverture d'un panneau centré (Classement/Profil/Effectifs/fin de partie)
	notify = "rbxassetid://0", -- pop-in d'une notification (succès débloqué, niveau atteint)
}

local function play(soundId: string, volume: number)
	if soundId == "rbxassetid://0" then return end -- placeholder non renseigné : rien à jouer

	local sound = Instance.new("Sound")
	sound.SoundId    = soundId
	sound.Volume     = volume
	sound.SoundGroup = sfxGroup
	sound.Parent     = SoundService -- son 2D (pas de position dans le monde), pas besoin de personnage
	sound.Ended:Once(function() sound:Destroy() end)
	sound:Play()
	task.delay(3, function()
		if sound.Parent then sound:Destroy() end
	end)
end

local UISound = {}

function UISound.PlayClick()
	play(SOUND_IDS.click, 0.5)
end

function UISound.PlayOpen()
	play(SOUND_IDS.open, 0.4)
end

function UISound.PlayNotify()
	play(SOUND_IDS.notify, 0.6)
end

return UISound
