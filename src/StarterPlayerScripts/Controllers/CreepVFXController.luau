--!strict
--------------------------------------------------------------------------------
-- CreepVFXController
-- Client-side visual effects for creep abilities. Listens for the
-- CreepAbilityUsed signal from CreepService and spawns lightweight Part-based
-- effects animated with TweenService.
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Packages.Knit)

local CreepVFXController = Knit.CreateController({ Name = "CreepVFXController" })

--------------------------------------------------------------------------------
-- Shared VFX folder (created once, cleaned up on leave)
--------------------------------------------------------------------------------

local vfxFolder: Folder = nil :: any

local function _getFolder(): Folder
	if vfxFolder and vfxFolder.Parent then
		return vfxFolder
	end
	local folder = Instance.new("Folder")
	folder.Name = "CreepVFX"
	folder.Parent = workspace
	vfxFolder = folder
	return folder
end

--------------------------------------------------------------------------------
-- Helper: create a basic anchored neon part
--------------------------------------------------------------------------------

local function _makePart(shape: Enum.PartType, size: Vector3, color: Color3, transparency: number): Part
	local part = Instance.new("Part")
	part.Shape = shape
	part.Size = size
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency
	part.Parent = _getFolder()
	return part
end

--------------------------------------------------------------------------------
-- Helper: tween a part and destroy it when done
--------------------------------------------------------------------------------

local function _tweenAndDestroy(part: Part, duration: number, goals: { [string]: any })
	local tween = TweenService:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goals)
	tween:Play()
	tween.Completed:Connect(function()
		part:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Effect: Shield Bash (Footman)
-- Expanding yellow ring around target position
--------------------------------------------------------------------------------

function CreepVFXController:_shieldBashEffect(position: Vector3)
	local ring = _makePart(Enum.PartType.Cylinder, Vector3.new(0.2, 2, 2), Color3.fromRGB(255, 220, 50), 0.3)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))

	_tweenAndDestroy(ring, 0.5, {
		Size = Vector3.new(0.2, 6, 6),
		Transparency = 1,
	})
end

--------------------------------------------------------------------------------
-- Effect: Volley (Rifleman)
-- Two small red projectile parts fly from caster toward target
--------------------------------------------------------------------------------

function CreepVFXController:_volleyEffect(position: Vector3, targetPosition: Vector3)
	local dir = targetPosition - position
	if dir.Magnitude < 0.1 then
		return
	end

	for i = 1, 2 do
		local offset = Vector3.new((i - 1.5) * 1.5, 0.5, 0)
		local startPos = position + offset
		local projectile = _makePart(Enum.PartType.Ball, Vector3.new(0.6, 0.6, 0.6), Color3.fromRGB(220, 50, 30), 0)
		projectile.CFrame = CFrame.new(startPos)

		_tweenAndDestroy(projectile, 0.35, {
			CFrame = CFrame.new(targetPosition + Vector3.new((i - 1.5) * 1, 0.5, 0)),
			Transparency = 1,
			Size = Vector3.new(0.3, 0.3, 0.3),
		})
	end
end

--------------------------------------------------------------------------------
-- Effect: War Cry (Grunt)
-- Expanding orange ring (cylinder) centered on caster
--------------------------------------------------------------------------------

function CreepVFXController:_warCryEffect(position: Vector3)
	local ring = _makePart(Enum.PartType.Cylinder, Vector3.new(0.3, 3, 3), Color3.fromRGB(255, 160, 30), 0.2)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))

	_tweenAndDestroy(ring, 0.8, {
		Size = Vector3.new(0.3, 24, 24),
		Transparency = 1,
	})

	-- Inner pulse ring (slightly delayed, smaller)
	task.delay(0.1, function()
		local inner = _makePart(Enum.PartType.Cylinder, Vector3.new(0.2, 2, 2), Color3.fromRGB(255, 200, 80), 0.4)
		inner.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))

		_tweenAndDestroy(inner, 0.6, {
			Size = Vector3.new(0.2, 18, 18),
			Transparency = 1,
		})
	end)
end

--------------------------------------------------------------------------------
-- Effect: Charge (Knight)
-- Blue trail from caster toward target
--------------------------------------------------------------------------------

function CreepVFXController:_chargeEffect(position: Vector3, targetPosition: Vector3)
	local dir = targetPosition - position
	if dir.Magnitude < 0.1 then
		return
	end

	local midPoint = position + dir * 0.5
	local trailLength = math.min(dir.Magnitude, 8)

	local trail = _makePart(Enum.PartType.Block, Vector3.new(0.5, 0.5, trailLength), Color3.fromRGB(60, 140, 255), 0.2)
	trail.CFrame = CFrame.lookAt(midPoint, targetPosition)

	_tweenAndDestroy(trail, 0.4, {
		Size = Vector3.new(0.1, 0.1, trailLength * 0.5),
		Transparency = 1,
	})

	-- Impact flash at target
	task.delay(0.15, function()
		local flash = _makePart(Enum.PartType.Ball, Vector3.new(1.5, 1.5, 1.5), Color3.fromRGB(100, 180, 255), 0)
		flash.CFrame = CFrame.new(targetPosition)

		_tweenAndDestroy(flash, 0.3, {
			Size = Vector3.new(3, 3, 3),
			Transparency = 1,
		})
	end)
end

--------------------------------------------------------------------------------
-- Effect: Heal Wave (Priest)
-- Green sparkle particles rising around caster position
--------------------------------------------------------------------------------

function CreepVFXController:_healWaveEffect(position: Vector3)
	-- Central green ring expanding outward
	local ring = _makePart(Enum.PartType.Cylinder, Vector3.new(0.2, 2, 2), Color3.fromRGB(50, 220, 80), 0.2)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))

	_tweenAndDestroy(ring, 0.7, {
		Size = Vector3.new(0.2, 20, 20),
		Transparency = 1,
	})

	-- Sparkle particles rising upward
	for i = 1, 3 do
		task.delay((i - 1) * 0.1, function()
			local angle = math.rad(i * 120)
			local offsetX = math.cos(angle) * 2
			local offsetZ = math.sin(angle) * 2
			local sparkle = _makePart(Enum.PartType.Ball, Vector3.new(0.5, 0.5, 0.5), Color3.fromRGB(80, 255, 120), 0)
			sparkle.CFrame = CFrame.new(position + Vector3.new(offsetX, 0, offsetZ))

			_tweenAndDestroy(sparkle, 0.6, {
				CFrame = CFrame.new(position + Vector3.new(offsetX, 4, offsetZ)),
				Size = Vector3.new(0.15, 0.15, 0.15),
				Transparency = 1,
			})
		end)
	end
end

--------------------------------------------------------------------------------
-- Effect: Ensnare (Raider)
-- Brown flat square (net) appears on target, then fades
--------------------------------------------------------------------------------

function CreepVFXController:_ensnareEffect(position: Vector3, targetPosition: Vector3)
	local netPos = targetPosition
	local net = _makePart(Enum.PartType.Block, Vector3.new(3, 0.1, 3), Color3.fromRGB(140, 100, 50), 0.2)
	net.CFrame = CFrame.new(netPos + Vector3.new(0, 0.2, 0))

	-- Cross-hatch lines using a second flat part rotated 45 degrees
	local cross = _makePart(Enum.PartType.Block, Vector3.new(3, 0.1, 3), Color3.fromRGB(120, 80, 30), 0.3)
	cross.CFrame = CFrame.new(netPos + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, math.rad(45), 0)

	_tweenAndDestroy(net, 2.5, {
		Transparency = 1,
		Size = Vector3.new(2.5, 0.05, 2.5),
	})

	_tweenAndDestroy(cross, 2.5, {
		Transparency = 1,
		Size = Vector3.new(2.5, 0.05, 2.5),
	})
end

--------------------------------------------------------------------------------
-- Effect: Plague Cloud (Abomination)
-- Green semi-transparent sphere that grows, lingers, and fades over 5s
--------------------------------------------------------------------------------

function CreepVFXController:_plagueCloudEffect(position: Vector3)
	local cloud = _makePart(Enum.PartType.Ball, Vector3.new(2, 2, 2), Color3.fromRGB(80, 180, 30), 0.6)
	cloud.CFrame = CFrame.new(position)
	cloud.Material = Enum.Material.SmoothPlastic

	-- Phase 1: grow over 0.5s
	local growTween = TweenService:Create(cloud, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(16, 10, 16),
		Transparency = 0.7,
	})
	growTween:Play()

	-- Phase 2: linger and slowly pulse for the duration, then fade out
	growTween.Completed:Connect(function()
		-- Subtle pulse
		local pulseTween = TweenService:Create(cloud, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 1, true), {
			Size = Vector3.new(17, 11, 17),
			Transparency = 0.65,
		})
		pulseTween:Play()

		-- After pulse completes, fade out
		pulseTween.Completed:Connect(function()
			_tweenAndDestroy(cloud, 1.5, {
				Size = Vector3.new(12, 6, 12),
				Transparency = 1,
			})
		end)
	end)
end

--------------------------------------------------------------------------------
-- Effect: Frost Breath (Frost Wyrm)
-- Cyan cone expanding forward, then fading
--------------------------------------------------------------------------------

function CreepVFXController:_frostBreathEffect(position: Vector3, targetPosition: Vector3)
	local dir = targetPosition - position
	if dir.Magnitude < 0.1 then
		dir = Vector3.new(0, 0, -1)
	end

	local midPoint = position + dir.Unit * 4

	-- Main frost cone (elongated block scaled to look like a cone/wedge)
	local cone = _makePart(Enum.PartType.Block, Vector3.new(2, 2, 3), Color3.fromRGB(100, 220, 255), 0.2)
	cone.CFrame = CFrame.lookAt(position + dir.Unit * 1.5, targetPosition)

	-- Secondary wider frost area
	local wide = _makePart(Enum.PartType.Block, Vector3.new(6, 1.5, 4), Color3.fromRGB(150, 240, 255), 0.4)
	wide.CFrame = CFrame.lookAt(midPoint, targetPosition)

	-- Expand and fade
	_tweenAndDestroy(cone, 0.6, {
		Size = Vector3.new(8, 4, 10),
		CFrame = CFrame.lookAt(midPoint + dir.Unit * 2, targetPosition + dir.Unit * 6),
		Transparency = 1,
	})

	_tweenAndDestroy(wide, 0.7, {
		Size = Vector3.new(14, 3, 8),
		Transparency = 1,
	})

	-- Ice crystal particles
	for i = 1, 3 do
		task.delay(i * 0.08, function()
			local spread = Vector3.new((math.random() - 0.5) * 6, math.random() * 2, (math.random() - 0.5) * 4)
			local crystal = _makePart(Enum.PartType.Block, Vector3.new(0.4, 0.8, 0.4), Color3.fromRGB(180, 240, 255), 0)
			crystal.CFrame = CFrame.new(midPoint + spread) * CFrame.Angles(math.random() * math.pi, math.random() * math.pi, 0)

			_tweenAndDestroy(crystal, 0.5, {
				CFrame = crystal.CFrame + Vector3.new(0, 2, 0),
				Transparency = 1,
				Size = Vector3.new(0.1, 0.2, 0.1),
			})
		end)
	end
end

--------------------------------------------------------------------------------
-- Effect: Immolation Aura (Infernal)
-- Persistent orange/red glow ring attached to the Infernal model.
-- We track active aura parts by creepId so we don't duplicate.
--------------------------------------------------------------------------------

CreepVFXController._auraEffects = {} :: { [number]: Part }

function CreepVFXController:_immolationAuraEffect(creepId: number, position: Vector3)
	-- Only create once per creep
	if self._auraEffects[creepId] and self._auraEffects[creepId].Parent then
		return
	end

	-- Find the creep model in workspace
	local creepFolder = workspace:FindFirstChild("Creeps")
	local model: Model? = nil
	if creepFolder then
		model = creepFolder:FindFirstChild("Creep_" .. tostring(creepId)) :: Model?
	end

	local ring = _makePart(Enum.PartType.Cylinder, Vector3.new(0.3, 12, 12), Color3.fromRGB(255, 100, 20), 0.5)
	ring.Material = Enum.Material.Neon
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))

	-- If we found the model, weld the ring to it so it follows
	if model then
		local body = model:FindFirstChild("Body") :: Part?
		if body then
			ring.Anchored = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = body
			weld.Part1 = ring
			weld.Parent = ring
			ring.CFrame = body.CFrame * CFrame.Angles(0, 0, math.rad(90))
		end
	end

	self._auraEffects[creepId] = ring

	-- Animate a continuous subtle pulse
	task.spawn(function()
		while ring and ring.Parent do
			local pulseUp = TweenService:Create(ring, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Transparency = 0.35,
				Color = Color3.fromRGB(255, 140, 40),
			})
			pulseUp:Play()
			pulseUp.Completed:Wait()

			if not ring or not ring.Parent then
				break
			end

			local pulseDown = TweenService:Create(ring, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Transparency = 0.6,
				Color = Color3.fromRGB(255, 80, 10),
			})
			pulseDown:Play()
			pulseDown.Completed:Wait()
		end
	end)
end

--------------------------------------------------------------------------------
-- Effect dispatcher
--------------------------------------------------------------------------------

function CreepVFXController:_playEffect(creepId: number, abilityName: string, position: Vector3, targetPosition: Vector3?)
	local target = targetPosition or position

	if abilityName == "Shield Bash" then
		self:_shieldBashEffect(target)

	elseif abilityName == "Volley" then
		self:_volleyEffect(position, target)

	elseif abilityName == "War Cry" then
		self:_warCryEffect(position)

	elseif abilityName == "Charge" then
		self:_chargeEffect(position, target)

	elseif abilityName == "Heal Wave" then
		self:_healWaveEffect(position)

	elseif abilityName == "Ensnare" then
		self:_ensnareEffect(position, target)

	elseif abilityName == "Plague Cloud" then
		self:_plagueCloudEffect(position)

	elseif abilityName == "Frost Breath" then
		self:_frostBreathEffect(position, target)

	elseif abilityName == "Immolation Aura" then
		self:_immolationAuraEffect(creepId, position)
	end
end

--------------------------------------------------------------------------------
-- Cleanup aura effects when creeps die
--------------------------------------------------------------------------------

function CreepVFXController:_onCreepDied(data: { Id: number })
	local auraRing = self._auraEffects[data.Id]
	if auraRing then
		-- Fade out the aura ring gracefully
		if auraRing.Parent then
			_tweenAndDestroy(auraRing, 0.4, { Transparency = 1 })
		end
		self._auraEffects[data.Id] = nil
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function CreepVFXController:KnitInit()
	-- Nothing to initialize
end

function CreepVFXController:KnitStart()
	local CreepService = Knit.GetService("CreepService")

	-- Listen for ability VFX events
	CreepService.CreepAbilityUsed:Connect(function(creepId: number, abilityName: string, position: Vector3, targetPosition: Vector3?)
		self:_playEffect(creepId, abilityName, position, targetPosition)
	end)

	-- Listen for creep deaths to clean up persistent effects (aura rings)
	CreepService.CreepDied:Connect(function(data: { Id: number })
		self:_onCreepDied(data)
	end)

	-- Fire Immolation Aura VFX for Infernals that already exist on join
	-- (in case client joins mid-game and Infernals are already spawned)
	CreepService.CreepSpawned:Connect(function(data: { Id: number, CreepId: string, Position: Vector3 })
		if data.CreepId == "Infernal" then
			-- Small delay to let the model replicate
			task.delay(0.5, function()
				self:_immolationAuraEffect(data.Id, data.Position)
			end)
		end
	end)
end

return CreepVFXController
