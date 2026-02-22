--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
	-- Position camera above the map center looking down
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

return CameraController
