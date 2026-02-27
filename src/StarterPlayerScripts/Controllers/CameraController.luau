--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig)

local CameraController = Knit.CreateController({
	Name = "CameraController",
})

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

CameraController._camera = nil :: Camera?
CameraController._cameraHeight = 60
CameraController._cameraAngle = 70 -- degrees from horizontal (70 = mostly top-down)
CameraController._cameraTarget = Vector3.new(0, 0, 0) -- ground-level point the camera hovers above

-- Zoom
CameraController._zoomSpeed = 5
CameraController._minHeight = 30
CameraController._maxHeight = 100

-- Pan (edge + arrow keys)
CameraController._panSpeed = 60 -- studs/sec
CameraController._edgePanThreshold = 20 -- pixels from screen edge

-- Arrow key tracking
CameraController._arrowUp = false :: boolean
CameraController._arrowDown = false :: boolean
CameraController._arrowLeft = false :: boolean
CameraController._arrowRight = false :: boolean

-- Middle-mouse drag
CameraController._middleDragging = false :: boolean
CameraController._lastMousePos = nil :: Vector2?
CameraController._dragScale = 0.5

-- Space = hold to follow hero
CameraController._spaceHeld = false :: boolean

-- Camera bounds (will be narrowed to team lane once team is known)
CameraController._boundsMinX = -MapConfig.GROUND_SIZE.X / 2
CameraController._boundsMaxX = MapConfig.GROUND_SIZE.X / 2
CameraController._boundsHalfZ = MapConfig.GROUND_SIZE.Z / 2
CameraController._teamId = nil :: number?

-- Intro cinematic
CameraController._introActive = false :: boolean

-- Shake
CameraController._isShaking = false :: boolean
CameraController._shakeOffset = Vector3.zero

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function CameraController:KnitInit()
	self._camera = workspace.CurrentCamera
end

function CameraController:KnitStart()
	self:_setupCamera()
	self:_bindInputs()

	-- Fetch team and set lane-locked camera bounds, then play intro
	task.defer(function()
		local ok, TeamService = pcall(function()
			return Knit.GetService("TeamService")
		end)
		if ok and TeamService then
			local teamId = TeamService:GetTeam()
			if teamId then
				self._teamId = teamId
				local halfWidth = MapConfig.LANE_HALF_WIDTH
				if teamId == 1 then
					self._boundsMinX = -(halfWidth + 15)
					self._boundsMaxX = 10
				else
					self._boundsMinX = -10
					self._boundsMaxX = halfWidth + 15
				end
			end
		end
		self:_playIntro()
	end)

	RunService:BindToRenderStep("RTSCamera", Enum.RenderPriority.Camera.Value, function(dt)
		self:_updateCamera(dt)
	end)
end

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

function CameraController:_setupCamera()
	local camera = self._camera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
end

--------------------------------------------------------------------------------
-- Input Bindings
--------------------------------------------------------------------------------

function CameraController:_bindInputs()
	-- Mouse wheel zoom
	UserInputService.InputChanged:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			self:_onZoom(input.Position.Z)
		end
	end)

	-- Key press
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end

		-- Arrow keys
		if input.KeyCode == Enum.KeyCode.Up then
			self._arrowUp = true
		end
		if input.KeyCode == Enum.KeyCode.Down then
			self._arrowDown = true
		end
		if input.KeyCode == Enum.KeyCode.Left then
			self._arrowLeft = true
		end
		if input.KeyCode == Enum.KeyCode.Right then
			self._arrowRight = true
		end

		-- Space = hold to follow hero
		if input.KeyCode == Enum.KeyCode.Space then
			self._spaceHeld = true
			self:CenterOnHero()
		end

		-- Middle mouse drag
		if input.UserInputType == Enum.UserInputType.MouseButton3 then
			self._middleDragging = true
			self._lastMousePos = UserInputService:GetMouseLocation()
		end
	end)

	-- Key release
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Up then
			self._arrowUp = false
		end
		if input.KeyCode == Enum.KeyCode.Down then
			self._arrowDown = false
		end
		if input.KeyCode == Enum.KeyCode.Left then
			self._arrowLeft = false
		end
		if input.KeyCode == Enum.KeyCode.Right then
			self._arrowRight = false
		end

		if input.KeyCode == Enum.KeyCode.Space then
			self._spaceHeld = false
		end

		if input.UserInputType == Enum.UserInputType.MouseButton3 then
			self._middleDragging = false
			self._lastMousePos = nil
		end
	end)
end

--------------------------------------------------------------------------------
-- Zoom
--------------------------------------------------------------------------------

function CameraController:_onZoom(direction: number)
	self._cameraHeight = math.clamp(
		self._cameraHeight - direction * self._zoomSpeed,
		self._minHeight,
		self._maxHeight
	)
end

--------------------------------------------------------------------------------
-- Camera Update (runs every render frame)
--------------------------------------------------------------------------------

function CameraController:_updateCamera(dt: number)
	local camera = self._camera
	if not camera then
		return
	end

	-- Ensure camera stays scriptable (Roblox can reset this)
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	-- Skip normal update during intro cinematic
	if self._introActive then
		return
	end

	-- Space held = continuously follow hero, skip all panning
	if self._spaceHeld then
		local player = Players.LocalPlayer
		if player and player.Character then
			local rootPart = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if rootPart then
				self._cameraTarget = Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z)
			end
		end

		-- Still apply bounds and position camera
		self._cameraTarget = Vector3.new(
			math.clamp(self._cameraTarget.X, self._boundsMinX, self._boundsMaxX),
			0,
			math.clamp(self._cameraTarget.Z, -self._boundsHalfZ, self._boundsHalfZ)
		)

		local target = self._cameraTarget
		camera.CFrame = CFrame.new(
			target.X + self._shakeOffset.X,
			self._cameraHeight,
			target.Z + self._shakeOffset.Z
		) * CFrame.Angles(math.rad(-self._cameraAngle), 0, 0)
		return
	end

	local panX, panZ = 0, 0

	-- 1. Edge panning (check mouse position relative to screen edges)
	local mouse = UserInputService:GetMouseLocation()
	local viewportSize = camera.ViewportSize
	local threshold = self._edgePanThreshold

	if mouse.X <= threshold then
		panX -= 1
	end
	if mouse.X >= viewportSize.X - threshold then
		panX += 1
	end
	if mouse.Y <= threshold then
		panZ -= 1
	end
	if mouse.Y >= viewportSize.Y - threshold then
		panZ += 1
	end

	-- 2. Arrow key panning
	if self._arrowLeft then
		panX -= 1
	end
	if self._arrowRight then
		panX += 1
	end
	if self._arrowUp then
		panZ -= 1
	end
	if self._arrowDown then
		panZ += 1
	end

	-- Apply keyboard/edge pan
	if panX ~= 0 or panZ ~= 0 then
		-- Scale pan speed by zoom level (faster when zoomed out)
		local zoomFactor = self._cameraHeight / 60
		local speed = self._panSpeed * dt * zoomFactor
		self._cameraTarget += Vector3.new(panX * speed, 0, panZ * speed)
	end

	-- 3. Middle-mouse drag pan
	if self._middleDragging then
		local currentMouse = UserInputService:GetMouseLocation()
		if self._lastMousePos then
			local delta = currentMouse - self._lastMousePos
			local zoomFactor = self._cameraHeight / 60
			self._cameraTarget += Vector3.new(
				-delta.X * self._dragScale * zoomFactor,
				0,
				-delta.Y * self._dragScale * zoomFactor
			)
		end
		self._lastMousePos = currentMouse
	end

	-- 4. Clamp to lane bounds (team-locked X, full Z)
	self._cameraTarget = Vector3.new(
		math.clamp(self._cameraTarget.X, self._boundsMinX, self._boundsMaxX),
		0,
		math.clamp(self._cameraTarget.Z, -self._boundsHalfZ, self._boundsHalfZ)
	)

	-- 5. Apply camera CFrame (position above target, angled down)
	local target = self._cameraTarget
	camera.CFrame = CFrame.new(
		target.X + self._shakeOffset.X,
		self._cameraHeight,
		target.Z + self._shakeOffset.Z
	) * CFrame.Angles(math.rad(-self._cameraAngle), 0, 0)
end

--------------------------------------------------------------------------------
-- Intro cinematic: sweep from nexus up to hero
--------------------------------------------------------------------------------

function CameraController:_playIntro()
	local camera = self._camera
	if not camera then
		self:CenterOnHero()
		return
	end

	self._introActive = true

	local teamId = self._teamId or 1
	local basePos = MapConfig.BASE_POSITIONS[teamId]
	if not basePos then
		self._introActive = false
		self:CenterOnHero()
		return
	end

	local player = Players.LocalPlayer

	-- Helper: get hero ground position (re-checked each frame)
	local function getHeroTarget(): Vector3
		if player and player.Character then
			local rootPart = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if rootPart then
				return Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z)
			end
		end
		-- Fallback to hero spawn area
		local heroPos = MapConfig.HERO_POSITIONS[teamId]
		if heroPos then
			return Vector3.new(heroPos.X, 0, heroPos.Z)
		end
		return Vector3.new(basePos.X, 0, basePos.Z - 50)
	end

	-- Helper: apply camera frame
	local function applyCam(target: Vector3, height: number, angle: number)
		camera.CFrame = CFrame.new(target.X, height, target.Z)
			* CFrame.Angles(math.rad(-angle), 0, 0)
	end

	-- Phase 1: Full map overview → zoom into citadel
	-- Start high above map center, nearly top-down
	local overviewTarget = Vector3.new(0, 0, 0)
	local overviewHeight = 200
	local overviewAngle = 85

	-- End at the citadel (base), closer and more dramatic
	local citadelTarget = Vector3.new(basePos.X, 0, basePos.Z)
	local citadelHeight = 30
	local citadelAngle = 55

	local phase1Duration = 2.5
	local elapsed = 0

	while elapsed < phase1Duration do
		local dt = RunService.RenderStepped:Wait()
		elapsed += dt

		local t = math.clamp(elapsed / phase1Duration, 0, 1)
		local smooth = t * t * (3 - 2 * t)

		local target = overviewTarget:Lerp(citadelTarget, smooth)
		local height = overviewHeight + (citadelHeight - overviewHeight) * smooth
		local angle = overviewAngle + (citadelAngle - overviewAngle) * smooth
		applyCam(target, height, angle)
	end

	-- Brief hold on citadel
	local holdDuration = 0.6
	elapsed = 0
	while elapsed < holdDuration do
		elapsed += RunService.RenderStepped:Wait()
		applyCam(citadelTarget, citadelHeight, citadelAngle)
	end

	-- Phase 2: Sweep from citadel to hero at normal camera settings
	local heroTarget = getHeroTarget()
	local endHeight = self._cameraHeight
	local endAngle = self._cameraAngle

	local phase2Duration = 2.0
	elapsed = 0

	while elapsed < phase2Duration do
		local dt = RunService.RenderStepped:Wait()
		elapsed += dt

		local t = math.clamp(elapsed / phase2Duration, 0, 1)
		local smooth = t * t * (3 - 2 * t)

		-- Re-check hero position (character might load during intro)
		heroTarget = getHeroTarget()

		local target = citadelTarget:Lerp(heroTarget, smooth)
		local height = citadelHeight + (endHeight - citadelHeight) * smooth
		local angle = citadelAngle + (endAngle - citadelAngle) * smooth
		applyCam(target, height, angle)
	end

	-- Set final state
	self._cameraTarget = heroTarget
	self._introActive = false
end

--------------------------------------------------------------------------------
-- Public: center camera on hero character
--------------------------------------------------------------------------------

function CameraController:CenterOnHero()
	local player = Players.LocalPlayer
	if not player then
		return
	end

	local character = player.Character
	if character then
		local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rootPart then
			self._cameraTarget = Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z)
			return
		end
	end

	-- Fallback: team's lane near the base area
	local laneX = 0
	if self._teamId == 1 then
		laneX = MapConfig.LEFT_LANE_X
	elseif self._teamId == 2 then
		laneX = MapConfig.RIGHT_LANE_X
	end
	self._cameraTarget = Vector3.new(laneX, 0, 80)
end

function CameraController:CenterCamera()
	self._cameraTarget = Vector3.new(0, 0, 0)
end

--------------------------------------------------------------------------------
-- Shake (screen impact effect)
--------------------------------------------------------------------------------

function CameraController:ShakeCamera(intensity: number, duration: number)
	if self._isShaking then
		return
	end

	self._isShaking = true

	task.spawn(function()
		local elapsed = 0
		local rng = Random.new()

		while elapsed < duration do
			local dt = RunService.RenderStepped:Wait()
			elapsed += dt

			local remaining = math.max(0, 1 - elapsed / duration)
			local currentIntensity = intensity * remaining

			self._shakeOffset = Vector3.new(
				(rng:NextNumber() * 2 - 1) * currentIntensity,
				0,
				(rng:NextNumber() * 2 - 1) * currentIntensity
			)
		end

		self._shakeOffset = Vector3.zero
		self._isShaking = false
	end)
end

return CameraController
