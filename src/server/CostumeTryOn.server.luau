--!strict
-- CostumeTryOn.server.luau — TEST : ProximityPrompt sur le mannequin "ClownCostume"
-- (Workspace, posé sur la Part "Costume de clown") permettant à un joueur d'essayer son
-- apparence (Shirt/Pants/Accessory clonés depuis le mannequin sur son personnage).
--
-- Script autonome (auto-exécuté par Roblox comme tous les *.server.luau du dossier), pas de
-- dépendance au RoundManager : le mannequin est une Part physique du hub, indépendante des rounds.

local mannequin = workspace:WaitForChild("ClownCostume")

-- Le mannequin importé (asset Creator Store) imbrique tout son rig sous un sous-Model nommé
-- d'après son créateur (ex. ClownCostume.Infinitizing.HumanoidRootPart) plutôt qu'à la racine —
-- recherche récursive nécessaire, FindFirstChild seul ne suffit pas.
local promptPart = mannequin:FindFirstChild("HumanoidRootPart", true) :: BasePart?
if not promptPart then
	warn("[CostumeTryOn] HumanoidRootPart introuvable sur ClownCostume, prompt non créé.")
	return
end

local function findFirstDescendantOfClass(root: Instance, className: string): Instance?
	for _, inst in root:GetDescendants() do
		if inst:IsA(className) then
			return inst
		end
	end
	return nil
end

local prompt = Instance.new("ProximityPrompt")
prompt.Name                 = "TryOnPrompt"
prompt.ActionText           = "Essayer"
prompt.ObjectText           = "Costume de clown"
prompt.HoldDuration         = 0.5
prompt.MaxActivationDistance = 8
prompt.RequiresLineOfSight  = false
prompt.Parent               = promptPart

-- Remplace le Shirt/Pants/Accessory du joueur par ceux du mannequin (clonés, l'original du
-- mannequin ne doit jamais être déplacé/détruit — c'est aussi la pièce d'exposition).
local function equipCostume(player: Player)
	local char = player.Character
	if not char then return end

	local shirt     = findFirstDescendantOfClass(mannequin, "Shirt")
	local pants     = findFirstDescendantOfClass(mannequin, "Pants")
	local accessory = findFirstDescendantOfClass(mannequin, "Accessory")

	if shirt then
		local existing = char:FindFirstChildOfClass("Shirt")
		if existing then existing:Destroy() end
		shirt:Clone().Parent = char
	end

	if pants then
		local existing = char:FindFirstChildOfClass("Pants")
		if existing then existing:Destroy() end
		pants:Clone().Parent = char
	end

	if accessory then
		local existing = char:FindFirstChild(accessory.Name)
		if existing and existing:IsA("Accessory") then existing:Destroy() end
		accessory:Clone().Parent = char
	end
end

prompt.Triggered:Connect(equipCostume)
