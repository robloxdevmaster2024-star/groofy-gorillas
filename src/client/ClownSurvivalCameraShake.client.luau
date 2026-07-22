--!nonstrict
-- ClownSurvivalCameraShake.client.luau — Secousse de caméra au moment d'un coup de batte.
-- Le serveur envoie l'intensité (0..~1.5) : plus forte pour l'enfant touché, plus légère pour
-- le clown qui frappe (feedback de contact). S'applique après la mise à jour de la caméra du
-- jeu (Enum.RenderPriority.Camera + 1) pour ne pas être écrasé par le contrôleur de caméra.

local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local eventsFolder     = ReplicatedStorage:WaitForChild("ClownSurvivalEvents")
local cameraShakeEvent = eventsFolder:WaitForChild("CameraShake")

local SHAKE_DURATION           = 0.3 -- s
local SHAKE_POSITION_AMPLITUDE = 0.6 -- studs, à intensité 1
local SHAKE_ROTATION_AMPLITUDE = 2.5 -- degrés, à intensité 1

local shakeTimeLeft  = 0
local shakeMagnitude = 0

local function onShake(intensity: number)
	if typeof(intensity) ~= "number" then return end
	shakeTimeLeft = SHAKE_DURATION
	shakeMagnitude = math.clamp(intensity, 0, 2)
end

cameraShakeEvent.OnClientEvent:Connect(onShake)

RunService:BindToRenderStep("ClownSurvivalCameraShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if shakeTimeLeft <= 0 then return end
	shakeTimeLeft = math.max(0, shakeTimeLeft - dt)

	local camera = workspace.CurrentCamera
	if not camera then return end

	local falloff = shakeTimeLeft / SHAKE_DURATION -- 1 → 0, décroissance linéaire
	local amount = shakeMagnitude * falloff

	local offset = Vector3.new(
		(math.random() * 2 - 1) * SHAKE_POSITION_AMPLITUDE * amount,
		(math.random() * 2 - 1) * SHAKE_POSITION_AMPLITUDE * amount,
		0
	)
	local rotation = CFrame.Angles(
		math.rad((math.random() * 2 - 1) * SHAKE_ROTATION_AMPLITUDE * amount),
		math.rad((math.random() * 2 - 1) * SHAKE_ROTATION_AMPLITUDE * amount),
		math.rad((math.random() * 2 - 1) * SHAKE_ROTATION_AMPLITUDE * amount)
	)

	camera.CFrame = camera.CFrame * CFrame.new(offset) * rotation
end)
