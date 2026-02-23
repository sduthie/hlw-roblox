--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)

local CameraController = Knit.CreateController({
	Name = "CameraController",
})

CameraController._camera = nil :: Camera?
CameraController._cameraHeight = 60
CameraController._cameraAngle = 70 -- degrees from horizontal
CameraController._panSpeed = 50
CameraController._zoomSpeed = 5
CameraController._minHeight = 30
CameraController._maxHeight = 100
CameraController._isShaking = false

function CameraController:KnitInit()
	self._camera = workspace.CurrentCamera
end

function CameraController:KnitStart()
	self:_setupTopDownCamera()
	self:_bindInputs()
end

function CameraController:_setupTopDownCamera()
	local camera = self._camera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.new(0, self._cameraHeight, 0) * CFrame.Angles(math.rad(-self._cameraAngle), 0, 0)
end

function CameraController:_bindInputs()
	UserInputService.InputChanged:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			self:_onZoom(input.Position.Z)
		end
	end)
end

function CameraController:_onZoom(direction: number)
	self._cameraHeight = math.clamp(self._cameraHeight - direction * self._zoomSpeed, self._minHeight, self._maxHeight)
	self:_updateCameraPosition()
end

function CameraController:_updateCameraPosition()
	local camera = self._camera
	if not camera then
		return
	end
	local currentPos = camera.CFrame.Position
	camera.CFrame = CFrame.new(currentPos.X, self._cameraHeight, currentPos.Z)
		* CFrame.Angles(math.rad(-self._cameraAngle), 0, 0)
end

function CameraController:CenterCamera()
	local camera = self._camera
	if not camera then
		return
	end
	camera.CFrame = CFrame.new(0, self._cameraHeight, 0) * CFrame.Angles(math.rad(-self._cameraAngle), 0, 0)
end

function CameraController:ShakeCamera(intensity: number, duration: number)
	if self._isShaking then
		return
	end

	self._isShaking = true

	task.spawn(function()
		local camera = self._camera
		if not camera then
			self._isShaking = false
			return
		end

		local elapsed = 0
		local rng = Random.new()

		while elapsed < duration do
			local dt = RunService.RenderStepped:Wait()
			elapsed += dt

			local remaining = math.max(0, 1 - elapsed / duration)
			local currentIntensity = intensity * remaining

			local offsetX = (rng:NextNumber() * 2 - 1) * currentIntensity
			local offsetZ = (rng:NextNumber() * 2 - 1) * currentIntensity

			local basePos = camera.CFrame.Position
			camera.CFrame = CFrame.new(basePos.X + offsetX, self._cameraHeight, basePos.Z + offsetZ)
				* CFrame.Angles(math.rad(-self._cameraAngle), 0, 0)
		end

		self:_updateCameraPosition()
		self._isShaking = false
	end)
end

return CameraController
