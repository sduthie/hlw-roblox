--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local CreepData = require(ReplicatedStorage.Shared.CreepData)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig)
local CreepModels = require(ReplicatedStorage.Shared.CreepModels)
local RemoteValidator = require(ReplicatedStorage.Shared.RemoteValidator)

-- Type alias for the creep instances we track at runtime.
-- Mirrors Types.CreepInstance but declared inline to keep this file self-contained.
type CreepInstance = {
	Id: number,
	CreepId: string,
	OwnerId: number,
	TeamId: number,
	TargetTeamId: number,
	LaneKey: string,
	LaneIndex: number,
	WaypointIndex: number,
	Position: Vector3,
	Health: number,
	MaxHealth: number,
	Model: Model?,
	Hexed: boolean?,
	HexExpires: number?,
	LastAttackTime: number?,
	DamageMultiplier: number?,
	SpeedMultiplier: number?,
	LastHitByPlayer: Player?,
	-- Ability system fields
	LastAbilityTime: number?,
	AuraActive: boolean?,
	StunnedUntil: number?,
	SlowedUntil: number?,
	SlowFactor: number?,
	BuffExpires: number?,
	BuffDamageMultiplier: number?,
	-- AoE DoT tracking (Plague Cloud)
	DoTActive: boolean?,
	DoTExpires: number?,
	DoTDPS: number?,
	DoTRadius: number?,
	-- Charge tracking (Knight)
	ChargeReady: boolean?,
	ChargeDamageMultiplier: number?,
}

--------------------------------------------------------------------------------
-- Service
--------------------------------------------------------------------------------

local CreepService = Knit.CreateService({
	Name = "CreepService",

	Client = {
		CreepSpawned = Knit.CreateSignal(),
		CreepDied = Knit.CreateSignal(),
		CreepReachedBase = Knit.CreateSignal(),
		CreepKillReward = Knit.CreateSignal(),
		CreepAbilityUsed = Knit.CreateSignal(),
	},
})

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

CreepService._nextCreepId = 1 :: number
CreepService._activeCreeps = {} :: { [number]: CreepInstance }
CreepService._creepFolder = nil :: Folder?
CreepService._aiActive = false :: boolean
CreepService._aiStartTime = 0 :: number
CreepService._lastGateFireTime = {} :: { [number]: number } -- teamId -> last fire time

--------------------------------------------------------------------------------
-- Constants (local shortcuts)
--------------------------------------------------------------------------------

local WAVE_SIZE = Constants.WAVE_SIZE
local CREEP_SPAWN_INTERVAL = Constants.CREEP_SPAWN_INTERVAL
local CREEP_UPDATE_RATE = Constants.CREEP_UPDATE_RATE
local WAYPOINT_REACH_DISTANCE = Constants.WAYPOINT_REACH_DISTANCE
local GATE_RANGE = Constants.GATE_RANGE
local GATE_BASE_DPS = Constants.GATE_BASE_DPS
local KILL_BOUNTY_PERCENT = Constants.KILL_BOUNTY_PERCENT
local BLACK_CITADEL_CREEP_HP_BONUS = Constants.BLACK_CITADEL_CREEP_HP_BONUS

-- Creep-vs-creep combat
local CREEP_AGGRO_RANGE = 20
local CREEP_ATTACK_COOLDOWN = 1

-- Creep-vs-hero combat
local CREEP_HERO_AGGRO_RANGE = 25
local CREEP_HERO_ATTACK_COOLDOWN = 1.2
local CREEP_HERO_DAMAGE_MULT = 0.5 -- creeps deal 50% of their damage to heroes
local CREEP_MELEE_STANDOFF = 5 -- min distance from hero (don't stack on top)

-- Separation: creeps push apart when closer than this
local CREEP_SEPARATION_DISTANCE = 4
local CREEP_SEPARATION_STRENGTH = 6 -- studs/sec push speed

-- Gate tower visual fire rate
local GATE_FIRE_INTERVAL = 1.2 -- seconds between visible tower shots

--------------------------------------------------------------------------------
-- Client method
--------------------------------------------------------------------------------

function CreepService.Client:SendCreep(player: Player, creepId: string): boolean
	if not RemoteValidator.isValidCreepId(creepId) then
		return false
	end
	if not RemoteValidator.rateLimit(player, "SendCreep", 0.5) then
		return false
	end
	return self.Server:SendCreep(player, creepId)
end

--------------------------------------------------------------------------------
-- Server method
--------------------------------------------------------------------------------

function CreepService:SendCreep(player: Player, creepId: string): boolean
	-- 1. Resolve team
	local TeamService = Knit.GetService("TeamService")
	local teamId = TeamService:GetTeam(player)
	if not teamId then
		warn("[CreepService] Player", player.Name, "has no team")
		return false
	end

	-- 2. Validate creep definition
	local creepDef = CreepData[creepId]
	if not creepDef then
		warn("[CreepService] Unknown creepId:", creepId)
		return false
	end

	-- 3. Tier gate: player's TownHall tier must be >= creep tier
	local ShopService = Knit.GetService("ShopService")
	local townHallTier: number = ShopService:GetTownHallTier(player)
	if creepDef.Tier > townHallTier then
		return false
	end

	-- 4. Game phase check
	local GameService = Knit.GetService("GameService")
	if GameService:GetPhase() ~= Constants.PHASE_PLAYING then
		return false
	end

	-- 5. Deduct gold (use escalated cost from ShopService)
	local escalatedCost = ShopService:GetCreepCost(player, creepId)
	local IncomeService = Knit.GetService("IncomeService")
	if not IncomeService:SpendGold(player, escalatedCost) then
		return false
	end

	-- 6. Track purchase count for cost escalation
	local userId = player.UserId
	local counts = ShopService._creepPurchaseCounts[userId]
	if not counts then
		counts = {}
		ShopService._creepPurchaseCounts[userId] = counts
	end
	counts[creepId] = (counts[creepId] or 0) + 1

	-- 7. Add income bonus
	IncomeService:AddIncome(player, creepDef.IncomeBonus)

	-- 8. Spawn the wave
	self:_spawnWave(player, creepId, teamId)
	return true
end

--------------------------------------------------------------------------------
-- Wave spawning
--------------------------------------------------------------------------------

function CreepService:_spawnWave(player: Player, creepId: string, teamId: number)
	local targetTeamId = if teamId == 1 then 2 else 1
	local laneKey = "AttackTeam" .. tostring(targetTeamId)

	-- Determine HP bonus from Black Citadel (TownHall tier >= 3)
	local ShopService = Knit.GetService("ShopService")
	local townHallTier: number = ShopService:GetTownHallTier(player)
	local hpMultiplier = 1
	if townHallTier >= 3 then
		hpMultiplier = 1 + BLACK_CITADEL_CREEP_HP_BONUS
	end

	-- Apply minion upgrade bonuses
	local dmgMultiplier = 1
	local speedMultiplier = 1
	local okUpgrade, upgradeService = pcall(function()
		return Knit.GetService("UpgradeService")
	end)
	if okUpgrade and upgradeService then
		local hpPct = upgradeService:GetCreepHpPct(player)
		hpMultiplier = hpMultiplier + (hpPct / 100)

		local dmgPct = upgradeService:GetCreepDmgPct(player)
		dmgMultiplier = 1 + (dmgPct / 100)

		local speedPct = upgradeService:GetCreepSpeedPct(player)
		speedMultiplier = 1 + (speedPct / 100)
	end

	-- Send a single creep per purchase
	local creep = self:_createCreep(creepId, player.UserId, teamId, targetTeamId, laneKey, hpMultiplier)
	creep.DamageMultiplier = dmgMultiplier
	creep.SpeedMultiplier = speedMultiplier
end

--------------------------------------------------------------------------------
-- Creep creation
--------------------------------------------------------------------------------

function CreepService:_createCreep(
	creepId: string,
	ownerId: number,
	teamId: number,
	targetTeamId: number,
	laneKey: string,
	hpMultiplier: number,
	spawnOverride: Vector3?
): CreepInstance
	local creepDef = CreepData[creepId]
	local id = self._nextCreepId
	self._nextCreepId += 1

	local baseHealth = math.floor(creepDef.Health * hpMultiplier)
	-- Use override if provided, otherwise attack spawn at top of target's lane
	local baseSpawn = spawnOverride or MapConfig.ATTACK_SPAWN_POSITIONS[targetTeamId]
	-- Randomize X within ±35 studs so creeps spread across the wide lane
	local xOffset = (math.random() * 70) - 35
	local spawnPosition = Vector3.new(baseSpawn.X + xOffset, baseSpawn.Y, baseSpawn.Z)

	-- Build the model using CreepModels module --------------------------------
	local teamColor = MapConfig.TEAM_COLORS[teamId]
	local model = CreepModels.build(creepId, teamColor, spawnPosition)
	model.Name = "Creep_" .. id

	local part = model.PrimaryPart :: Part

	-- Health bar BillboardGui (attached to Body)
	local bodySize = part.Size
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Size = UDim2.fromOffset(60, 14)
	gui.StudsOffset = Vector3.new(0, bodySize.Y / 2 + 1.5, 0)
	gui.AlwaysOnTop = true
	gui.Parent = part

	-- Name label
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, 0, 0, 6)
	nameLabel.Position = UDim2.new(0, 0, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = creepDef.Name
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = gui

	-- Background frame (black)
	local bgFrame = Instance.new("Frame")
	bgFrame.Name = "Background"
	bgFrame.Size = UDim2.new(1, 0, 0, 8)
	bgFrame.Position = UDim2.new(0, 0, 0, 6)
	bgFrame.BackgroundColor3 = Color3.new(0, 0, 0)
	bgFrame.BorderSizePixel = 0
	bgFrame.Parent = gui

	-- Fill frame (green, scales with health)
	local fillFrame = Instance.new("Frame")
	fillFrame.Name = "Fill"
	fillFrame.Size = UDim2.new(1, 0, 1, 0)
	fillFrame.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
	fillFrame.BorderSizePixel = 0
	fillFrame.Parent = bgFrame

	model.Parent = self._creepFolder

	-- Build instance data -----------------------------------------------------
	local isAura = creepDef.Ability and creepDef.Ability.Type == "Aura"

	local creep: CreepInstance = {
		Id = id,
		CreepId = creepId,
		OwnerId = ownerId,
		TeamId = teamId,
		TargetTeamId = targetTeamId,
		LaneKey = laneKey,
		LaneIndex = 1,
		WaypointIndex = 1,
		Position = spawnPosition,
		Health = baseHealth,
		MaxHealth = baseHealth,
		Model = model,
		-- Ability system defaults
		LastAbilityTime = 0,
		AuraActive = isAura or false,
		StunnedUntil = 0,
		SlowedUntil = 0,
		SlowFactor = 1,
		BuffExpires = 0,
		BuffDamageMultiplier = 1,
		DoTActive = false,
		DoTExpires = 0,
		DoTDPS = 0,
		DoTRadius = 0,
		ChargeReady = false,
		ChargeDamageMultiplier = 1,
	}

	self._activeCreeps[id] = creep

	-- Notify clients
	self.Client.CreepSpawned:FireAll({
		Id = id,
		CreepId = creepId,
		TeamId = teamId,
		Position = spawnPosition,
	})

	return creep
end

--------------------------------------------------------------------------------
-- Health bar update helper
--------------------------------------------------------------------------------

local function _updateHealthBar(creep: CreepInstance)
	local model = creep.Model
	if not model then
		return
	end
	local body = model:FindFirstChild("Body") :: Part?
	if not body then
		return
	end
	local gui = body:FindFirstChild("HealthBar") :: BillboardGui?
	if not gui then
		return
	end
	local bg = gui:FindFirstChild("Background") :: Frame?
	if not bg then
		return
	end
	local fill = bg:FindFirstChild("Fill") :: Frame?
	if not fill then
		return
	end

	local pct = math.clamp(creep.Health / creep.MaxHealth, 0, 1)
	fill.Size = UDim2.new(pct, 0, 1, 0)

	-- Color gradient: green -> yellow -> red
	if pct > 0.5 then
		fill.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
	elseif pct > 0.25 then
		fill.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
	else
		fill.BackgroundColor3 = Color3.fromRGB(255, 50, 0)
	end
end

--------------------------------------------------------------------------------
-- Lane key helper
-- Given a creep we derive the lane key from its routing direction.
--------------------------------------------------------------------------------

local function _getLaneKey(creep: CreepInstance): string
	return creep.LaneKey
end

--------------------------------------------------------------------------------
-- Move entire multi-part model to a new position
--------------------------------------------------------------------------------

local function _moveModel(creep: CreepInstance, newPosition: Vector3)
	local model = creep.Model
	if not model then
		return
	end
	local body = model:FindFirstChild("Body") :: Part?
	if not body then
		return
	end
	local delta = newPosition - body.Position
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			child.CFrame = child.CFrame + delta
		end
	end
end

--------------------------------------------------------------------------------
-- Visual effects: creep attack slash + gate tower projectile
--------------------------------------------------------------------------------

local function _playAttackEffect(attackerPos: Vector3, targetPos: Vector3, color: Color3)
	local dir = targetPos - attackerPos
	local dist = dir.Magnitude
	if dist < 0.5 then
		return
	end

	-- Slash arc near the target (visible neon swipe)
	local slashPos = targetPos + Vector3.new(0, 2, 0) -- raise to body height
	local slash = Instance.new("Part")
	slash.Name = "CreepSlash"
	slash.Size = Vector3.new(2.5, 0.4, 0.15)
	slash.Anchored = true
	slash.CanCollide = false
	slash.Material = Enum.Material.Neon
	slash.Color = color
	slash.Transparency = 0.1
	slash.CFrame = CFrame.lookAt(slashPos, slashPos + dir) * CFrame.Angles(0, 0, math.rad(math.random(-40, 40)))
	slash.Parent = workspace

	-- Quick expand and fade
	task.spawn(function()
		task.wait(0.1)
		if slash.Parent then
			slash.Size = Vector3.new(3.5, 0.6, 0.15)
			slash.Transparency = 0.5
		end
		task.wait(0.15)
		if slash.Parent then
			slash:Destroy()
		end
	end)
end

-- Attack lunge: briefly move the creep model toward its target then snap back
local function _playAttackLunge(creepModel: Model?, targetPos: Vector3)
	if not creepModel then
		return
	end
	local body = creepModel:FindFirstChild("Body") :: BasePart?
	if not body then
		return
	end

	local originalPos = body.Position
	local dir = (targetPos - originalPos)
	dir = Vector3.new(dir.X, 0, dir.Z) -- flatten Y
	local lungeMag = dir.Magnitude
	if lungeMag < 0.5 then
		return
	end
	local lungeOffset = dir.Unit * math.min(lungeMag * 0.3, 2) -- lunge 30% of distance, max 2 studs

	-- Move all parts forward
	task.spawn(function()
		for _, child in creepModel:GetChildren() do
			if child:IsA("BasePart") then
				child.CFrame = child.CFrame + lungeOffset
			end
		end
		task.wait(0.1)
		-- Snap back
		if creepModel.Parent then
			for _, child in creepModel:GetChildren() do
				if child:IsA("BasePart") then
					child.CFrame = child.CFrame - lungeOffset
				end
			end
		end
	end)
end

function CreepService:_fireGateProjectile(gateTeamId: number, targetPos: Vector3)
	local now = os.clock()
	local lastFire = self._lastGateFireTime[gateTeamId] or 0
	if now - lastFire < GATE_FIRE_INTERVAL then
		return
	end
	self._lastGateFireTime[gateTeamId] = now

	local gatePos = MapConfig.GATE_POSITIONS[gateTeamId]
	if not gatePos then
		return
	end

	local orbPos = Vector3.new(gatePos.X, 10, gatePos.Z) -- orb sits at Y=10
	local teamColor = MapConfig.TEAM_COLORS[gateTeamId]

	local projectile = Instance.new("Part")
	projectile.Name = "TowerShot"
	projectile.Shape = Enum.PartType.Ball
	projectile.Size = Vector3.new(1.5, 1.5, 1.5)
	projectile.Position = orbPos
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.Material = Enum.Material.Neon
	projectile.Color = teamColor
	projectile.Transparency = 0.1
	projectile.Parent = workspace

	local light = Instance.new("PointLight")
	light.Range = 8
	light.Brightness = 2
	light.Color = teamColor
	light.Parent = projectile

	-- Animate projectile flight
	task.spawn(function()
		local flightTime = 0.35
		local elapsed = 0
		while elapsed < flightTime do
			local dt = task.wait()
			elapsed += dt
			local alpha = math.min(elapsed / flightTime, 1)
			projectile.Position = orbPos:Lerp(targetPos, alpha)
		end
		-- Impact flash
		projectile.Size = Vector3.new(3, 3, 3)
		projectile.Transparency = 0.5
		task.wait(0.1)
		projectile:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Movement loop (10 Hz)
--------------------------------------------------------------------------------

function CreepService:_computeSeparation(creep: CreepInstance, dt: number): Vector3
	local pushX, pushZ = 0, 0

	for _, other in self._activeCreeps do
		if other.Id == creep.Id then
			continue
		end
		local dx = creep.Position.X - other.Position.X
		local dz = creep.Position.Z - other.Position.Z
		local dist = math.sqrt(dx * dx + dz * dz)
		if dist < CREEP_SEPARATION_DISTANCE and dist > 0.01 then
			-- Stronger push the closer they are
			local factor = (CREEP_SEPARATION_DISTANCE - dist) / CREEP_SEPARATION_DISTANCE
			pushX += (dx / dist) * factor
			pushZ += (dz / dist) * factor
		end
	end

	-- Normalize and scale by strength and dt
	local mag = math.sqrt(pushX * pushX + pushZ * pushZ)
	if mag > 0.01 then
		local scale = CREEP_SEPARATION_STRENGTH * dt / mag
		return Vector3.new(pushX * scale, 0, pushZ * scale)
	end
	return Vector3.zero
end

function CreepService:_findNearestEnemy(creep: CreepInstance): CreepInstance?
	local bestDist = CREEP_AGGRO_RANGE
	local bestTarget: CreepInstance? = nil

	for _, other in self._activeCreeps do
		if other.TeamId == creep.TeamId then
			continue
		end
		local dist = (other.Position - creep.Position).Magnitude
		if dist < bestDist then
			bestDist = dist
			bestTarget = other
		end
	end

	return bestTarget
end

--------------------------------------------------------------------------------
-- Ability system helpers
--------------------------------------------------------------------------------

function CreepService:_findEnemiesInRadius(creep: CreepInstance, radius: number, maxCount: number?): { CreepInstance }
	local results: { CreepInstance } = {}
	local limit = maxCount or 999

	for _, other in self._activeCreeps do
		if other.TeamId == creep.TeamId then
			continue
		end
		if other.Health <= 0 then
			continue
		end
		local dist = (other.Position - creep.Position).Magnitude
		if dist <= radius then
			table.insert(results, other)
			if #results >= limit then
				break
			end
		end
	end

	return results
end

function CreepService:_findAlliesInRadius(creep: CreepInstance, radius: number): { CreepInstance }
	local results: { CreepInstance } = {}

	for _, other in self._activeCreeps do
		if other.TeamId ~= creep.TeamId then
			continue
		end
		if other.Id == creep.Id then
			continue
		end
		if other.Health <= 0 then
			continue
		end
		local dist = (other.Position - creep.Position).Magnitude
		if dist <= radius then
			table.insert(results, other)
		end
	end

	return results
end

--------------------------------------------------------------------------------
-- Find nearest enemy hero (for creep-vs-hero combat)
--------------------------------------------------------------------------------

function CreepService:_findNearestEnemyHero(creep: CreepInstance): (Player?, number)
	local bestDist = CREEP_HERO_AGGRO_RANGE
	local bestPlayer: Player? = nil

	local okTeam, teamService = pcall(function()
		return Knit.GetService("TeamService")
	end)
	if not okTeam or not teamService then
		return nil, 0
	end

	for _, player in Players:GetPlayers() do
		local heroTeamId = teamService:GetTeam(player)
		if not heroTeamId or heroTeamId == creep.TeamId then
			continue
		end

		local character = player.Character
		if not character then
			continue
		end
		local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart then
			continue
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			continue
		end

		local dist = (rootPart.Position - creep.Position).Magnitude
		if dist < bestDist then
			bestDist = dist
			bestPlayer = player
		end
	end

	return bestPlayer, bestDist
end

--------------------------------------------------------------------------------
-- Ability execution
--------------------------------------------------------------------------------

function CreepService:_tryUseAbility(creep: CreepInstance, enemy: CreepInstance, now: number)
	local creepDef = CreepData[creep.CreepId]
	if not creepDef or not creepDef.Ability then
		return
	end

	local ability = creepDef.Ability
	-- Aura type is handled separately (passive, no cooldown)
	if ability.Type == "Aura" then
		return
	end

	local lastUse = creep.LastAbilityTime or 0
	if now - lastUse < ability.Cooldown then
		return
	end

	-- Ability is off cooldown -- execute it
	creep.LastAbilityTime = now

	local targetPos: Vector3 = enemy.Position

	if ability.Type == "Stun" then
		-- Shield Bash: stun the target
		local stunUntil = now + ability.Value
		-- Don't override a longer existing stun
		if (enemy.StunnedUntil or 0) < stunUntil then
			enemy.StunnedUntil = stunUntil
		end

	elseif ability.Type == "BonusDamage" then
		-- Volley: deal bonus damage to primary target + 1 more nearby enemy
		enemy.Health -= ability.Value
		_updateHealthBar(enemy)
		if enemy.Health <= 0 then
			self:_onCreepKilledByCreep(enemy)
		end

		-- Find 1 additional enemy near the primary target
		local secondaryTargets: { CreepInstance } = {}
		for _, other in self._activeCreeps do
			if other.TeamId == creep.TeamId or other.Id == enemy.Id then
				continue
			end
			if other.Health <= 0 then
				continue
			end
			local dist = (other.Position - enemy.Position).Magnitude
			if dist <= ability.Radius then
				table.insert(secondaryTargets, other)
				if #secondaryTargets >= 1 then
					break
				end
			end
		end

		for _, secondary in secondaryTargets do
			secondary.Health -= ability.Value
			_updateHealthBar(secondary)
			if secondary.Health <= 0 then
				self:_onCreepKilledByCreep(secondary)
			end
		end

	elseif ability.Type == "BuffAllies" then
		-- War Cry: buff nearby allies with +damage% for duration
		local allies = self:_findAlliesInRadius(creep, ability.Radius)
		local buffExpires = now + ability.Duration
		local buffMult = 1 + ability.Value

		for _, ally in allies do
			ally.BuffExpires = buffExpires
			ally.BuffDamageMultiplier = buffMult
		end
		-- Also buff self
		creep.BuffExpires = buffExpires
		creep.BuffDamageMultiplier = buffMult

	elseif ability.Type == "Charge" then
		-- Charge: prepare a powered-up next hit (2x damage)
		creep.ChargeReady = true
		creep.ChargeDamageMultiplier = ability.Value

	elseif ability.Type == "Heal" then
		-- Heal Wave: heal nearby allies
		local allies = self:_findAlliesInRadius(creep, ability.Radius)
		for _, ally in allies do
			ally.Health = math.min(ally.Health + ability.Value, ally.MaxHealth)
			_updateHealthBar(ally)
		end
		-- Also heal self
		creep.Health = math.min(creep.Health + ability.Value, creep.MaxHealth)
		_updateHealthBar(creep)

	elseif ability.Type == "Slow" then
		-- Ensnare: slow target
		enemy.SlowedUntil = now + ability.Duration
		enemy.SlowFactor = ability.Value

	elseif ability.Type == "AoEDoT" then
		-- Plague Cloud: activate damage-over-time field around this creep
		creep.DoTActive = true
		creep.DoTExpires = now + ability.Duration
		creep.DoTDPS = ability.Value
		creep.DoTRadius = ability.Radius

	elseif ability.Type == "AoEBurst" then
		-- Frost Breath: instant AoE damage + freeze (stun)
		local enemies = self:_findEnemiesInRadius(creep, ability.Radius)
		local stunUntil = now + ability.Duration

		for _, target in enemies do
			target.Health -= ability.Value
			_updateHealthBar(target)
			if target.Health <= 0 then
				self:_onCreepKilledByCreep(target)
			else
				if (target.StunnedUntil or 0) < stunUntil then
					target.StunnedUntil = stunUntil
				end
			end
		end
	end

	-- Fire VFX signal to all clients
	self.Client.CreepAbilityUsed:FireAll(creep.Id, ability.Name, creep.Position, targetPos)
end

--------------------------------------------------------------------------------
-- Aura tick (Infernal Immolation Aura): passive DPS to nearby enemies
--------------------------------------------------------------------------------

function CreepService:_applyAuraDamage(creep: CreepInstance, dt: number)
	local creepDef = CreepData[creep.CreepId]
	if not creepDef or not creepDef.Ability then
		return
	end
	local ability = creepDef.Ability
	if ability.Type ~= "Aura" then
		return
	end

	local enemies = self:_findEnemiesInRadius(creep, ability.Radius)
	local tickDmg = ability.Value * dt

	for _, target in enemies do
		target.Health -= tickDmg
		_updateHealthBar(target)
		if target.Health <= 0 then
			self:_onCreepKilledByCreep(target)
		end
	end
end

--------------------------------------------------------------------------------
-- AoE DoT tick (Plague Cloud active effect)
--------------------------------------------------------------------------------

function CreepService:_applyDoTDamage(creep: CreepInstance, now: number, dt: number)
	if not creep.DoTActive then
		return
	end
	if now > (creep.DoTExpires or 0) then
		creep.DoTActive = false
		return
	end

	local tickDmg = (creep.DoTDPS or 0) * dt
	if tickDmg <= 0 then
		return
	end

	local enemies = self:_findEnemiesInRadius(creep, creep.DoTRadius or 8)
	for _, target in enemies do
		target.Health -= tickDmg
		_updateHealthBar(target)
		if target.Health <= 0 then
			self:_onCreepKilledByCreep(target)
		end
	end
end

--------------------------------------------------------------------------------
-- Creep-vs-creep kill handler
--------------------------------------------------------------------------------

function CreepService:_onCreepKilledByCreep(creep: CreepInstance)
	-- If a player recently damaged this creep, give them assist/kill credit
	if creep.LastHitByPlayer then
		self:_onCreepKilledByHero(creep, creep.LastHitByPlayer)
		return
	end

	-- Notify clients (no bounty for creep-on-creep kills)
	self.Client.CreepDied:FireAll({
		Id = creep.Id,
		Position = creep.Position,
		CreepId = creep.CreepId,
	})

	self:_destroyCreep(creep.Id)
end

function CreepService:_runMovementLoop()
	local dt = 1 / CREEP_UPDATE_RATE

	while true do
		task.wait(dt)

		local now = os.clock()

		for id, creep in self._activeCreeps do
			local creepDef = CreepData[creep.CreepId]
			if not creepDef then
				continue
			end

			-- Hex stun: skip movement while hexed
			if creep.Hexed and creep.HexExpires then
				if now < creep.HexExpires then
					continue
				else
					creep.Hexed = false
					creep.HexExpires = nil
				end
			end

			local laneKey = _getLaneKey(creep)
			local waypoints = MapConfig.LANE_WAYPOINTS[laneKey]
			if not waypoints then
				continue
			end

			-- Gate damage check --------------------------------------------------
			local gatePos = MapConfig.GATE_POSITIONS[creep.TargetTeamId]
			if gatePos then
				local distToGate = (gatePos - creep.Position).Magnitude
				if distToGate <= GATE_RANGE then
					local gateDPS = GATE_BASE_DPS
					-- Simple armor reduction: effective DPS = max(1, dps - armor*2)
					local effectiveDPS = math.max(1, gateDPS - creepDef.Armor * 2)
					creep.Health -= effectiveDPS * dt
					_updateHealthBar(creep)

					-- Fire tower projectile (throttled visual)
					self:_fireGateProjectile(creep.TargetTeamId, creep.Position)

					if creep.Health <= 0 then
						self:_onCreepKilledByGate(creep)
						continue
					end
				end
			end

			-- Ability system: process passive effects (aura, DoT) ----------------
			if creep.AuraActive then
				self:_applyAuraDamage(creep, dt)
			end
			if creep.DoTActive then
				self:_applyDoTDamage(creep, now, dt)
			end

			-- Expire buff if time is up
			if (creep.BuffExpires or 0) > 0 and now >= (creep.BuffExpires or 0) then
				creep.BuffExpires = 0
				creep.BuffDamageMultiplier = 1
			end

			-- Expire slow if time is up
			if (creep.SlowedUntil or 0) > 0 and now >= (creep.SlowedUntil or 0) then
				creep.SlowedUntil = 0
				creep.SlowFactor = 1
			end

			-- Stun check: skip all combat actions while stunned
			local isStunned = (creep.StunnedUntil or 0) > now
			if isStunned then
				-- Expire stun when time is up (handled next tick)
				-- Still apply separation so stunned creeps don't stack
				local sep = self:_computeSeparation(creep, dt)
				if sep.Magnitude > 0.01 then
					creep.Position = creep.Position + sep
				end
				_moveModel(creep, creep.Position)
				continue
			end

			-- Creep-vs-hero combat -----------------------------------------------
			local heroTarget, heroDist = self:_findNearestEnemyHero(creep)
			if heroTarget then
				local lastAtk = creep.LastAttackTime or 0
				if now - lastAtk >= CREEP_HERO_ATTACK_COOLDOWN then
					creep.LastAttackTime = now

					local dmgMult = (creep.DamageMultiplier or 1) * CREEP_HERO_DAMAGE_MULT
					local variance = Constants.DAMAGE_VARIANCE
					local dmg = (creepDef.Damage or 10) * dmgMult * (1 - variance + math.random() * variance * 2)

					local okCombat, heroCombatService = pcall(function()
						return Knit.GetService("HeroCombatService")
					end)
					if okCombat and heroCombatService then
						heroCombatService:DamageHero(heroTarget, dmg)
					end

					-- Attack slash effect + lunge
					local character = heroTarget.Character
					local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
					if rootPart then
						local attackColor = Color3.fromRGB(255, 80, 60)
						_playAttackEffect(creep.Position, rootPart.Position, attackColor)
						_playAttackLunge(creep.Model, rootPart.Position)
					end
				end

				-- Move toward the hero if not in melee standoff range
				if heroDist > CREEP_MELEE_STANDOFF then
					local character = heroTarget.Character
					local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
					if rootPart then
						local dir = (rootPart.Position - creep.Position).Unit
						local moveDistance = creepDef.MoveSpeed * (creep.SpeedMultiplier or 1) * dt
						creep.Position = creep.Position + dir * moveDistance * 0.5
					end
				end

				local sep = self:_computeSeparation(creep, dt)
				if sep.Magnitude > 0.01 then
					creep.Position = creep.Position + sep
				end
				_moveModel(creep, creep.Position)
				continue
			end

			-- Creep-vs-creep combat ----------------------------------------------
			local enemy = self:_findNearestEnemy(creep)
			if enemy then
				-- Try to use special ability (if off cooldown)
				self:_tryUseAbility(creep, enemy, now)

				local lastAtk = creep.LastAttackTime or 0
				if now - lastAtk >= CREEP_ATTACK_COOLDOWN then
					creep.LastAttackTime = now

					-- Calculate damage with buff and charge multipliers
					local dmgMult = creep.DamageMultiplier or 1
					-- Active buff (War Cry)
					if (creep.BuffExpires or 0) > now then
						dmgMult = dmgMult * (creep.BuffDamageMultiplier or 1)
					end
					-- Charge bonus (Knight: one-time 2x on next hit)
					if creep.ChargeReady then
						dmgMult = dmgMult * (creep.ChargeDamageMultiplier or 1)
						creep.ChargeReady = false
						creep.ChargeDamageMultiplier = 1
					end

					local cVariance = Constants.DAMAGE_VARIANCE
					local dmg = (creepDef.Damage or 10) * dmgMult * (1 - cVariance + math.random() * cVariance * 2)
					enemy.Health -= dmg
					_updateHealthBar(enemy)

					-- Attack slash effect + lunge (team-colored)
					local slashColor = MapConfig.TEAM_COLORS[creep.TeamId] or Color3.new(1, 1, 1)
					_playAttackEffect(creep.Position, enemy.Position, slashColor)
					_playAttackLunge(creep.Model, enemy.Position)

					if enemy.Health <= 0 then
						self:_onCreepKilledByCreep(enemy)
					end
				end
				-- Engaged in combat -- apply separation so creeps spread out
				local sep = self:_computeSeparation(creep, dt)
				if sep.Magnitude > 0.01 then
					creep.Position = creep.Position + sep
				end
				_moveModel(creep, creep.Position)
				continue
			end

			-- Movement -----------------------------------------------------------
			local currentWaypoint = waypoints[creep.WaypointIndex]
			if not currentWaypoint then
				-- No more waypoints; creep reached the base
				self:_onCreepReachedBase(creep)
				continue
			end

			-- Each creep keeps its own X offset; navigate toward waypoint's Z
			local targetPos = Vector3.new(creep.Position.X, currentWaypoint.Y, currentWaypoint.Z)
			local offset = targetPos - creep.Position
			local distToWaypoint = offset.Magnitude

			if distToWaypoint <= WAYPOINT_REACH_DISTANCE then
				-- Advance to next waypoint
				if creep.WaypointIndex < #waypoints then
					creep.WaypointIndex += 1
				else
					-- Final waypoint reached
					self:_onCreepReachedBase(creep)
					continue
				end
			else
				-- Move toward waypoint (primarily along Z, keeping X offset)
				local direction = offset.Unit
				-- Apply slow debuff: SlowFactor < 1 means reduced speed
				local slowMult = 1
				if (creep.SlowedUntil or 0) > now and (creep.SlowFactor or 1) < 1 then
					slowMult = creep.SlowFactor or 1
				end
				local moveDistance = creepDef.MoveSpeed * (creep.SpeedMultiplier or 1) * slowMult * dt
				-- Clamp so we don't overshoot
				if moveDistance > distToWaypoint then
					moveDistance = distToWaypoint
				end
				creep.Position = creep.Position + direction * moveDistance
			end

			-- Separation from nearby creeps while walking
			local sep = self:_computeSeparation(creep, dt)
			if sep.Magnitude > 0.01 then
				creep.Position = creep.Position + sep * 0.5 -- lighter push while moving
			end

			-- Update model position (all parts move together)
			_moveModel(creep, creep.Position)
		end
	end
end

--------------------------------------------------------------------------------
-- Creep reached the enemy base
--------------------------------------------------------------------------------

function CreepService:_onCreepReachedBase(creep: CreepInstance)
	-- Defensive waves (targetTeamId == 0) just despawn at end of their path
	if creep.TargetTeamId == 0 then
		self:_destroyCreep(creep.Id)
		return
	end

	local creepDef = CreepData[creep.CreepId]
	if not creepDef then
		self:_destroyCreep(creep.Id)
		return
	end

	-- Base damage by tier
	local tier = creepDef.Tier
	local baseDamage = Constants.BASE_DAMAGE_BY_TIER[tier] or 1

	-- Damage the target team's base
	local GameService = Knit.GetService("GameService")
	GameService:DamageBase(creep.TargetTeamId, baseDamage)

	-- Record wave result for momentum streak tracking
	GameService:RecordWaveResult(creep.TeamId, 1)

	-- Notify clients
	self.Client.CreepReachedBase:FireAll({
		TargetTeamId = creep.TargetTeamId,
		Position = creep.Position,
	})

	self:_destroyCreep(creep.Id)
end

--------------------------------------------------------------------------------
-- Creep killed by gate
--------------------------------------------------------------------------------

function CreepService:_onCreepKilledByGate(creep: CreepInstance)
	-- If a player recently damaged this creep, give them hero kill credit instead
	if creep.LastHitByPlayer then
		self:_onCreepKilledByHero(creep, creep.LastHitByPlayer)
		return
	end

	local creepDef = CreepData[creep.CreepId]
	if not creepDef then
		self:_destroyCreep(creep.Id)
		return
	end

	-- Calculate bounty
	local bounty = math.floor(creepDef.Cost * KILL_BOUNTY_PERCENT)

	-- Award bounty to defending team players
	local TeamService = Knit.GetService("TeamService")
	local IncomeService = Knit.GetService("IncomeService")
	local defenders = TeamService:GetTeamPlayers(creep.TargetTeamId)
	local teamPlayerCount = #defenders

	if teamPlayerCount > 0 then
		local bountyPerPlayer = math.floor(bounty / teamPlayerCount)
		if bountyPerPlayer > 0 then
			for _, player in defenders do
				IncomeService:AddGold(player, bountyPerPlayer)
			end
		end
	end

	-- Notify clients
	self.Client.CreepDied:FireAll({
		Id = creep.Id,
		Position = creep.Position,
		CreepId = creep.CreepId,
	})

	self:_destroyCreep(creep.Id)
end

--------------------------------------------------------------------------------
-- Public: Get active creeps (for HeroCombatService iteration)
--------------------------------------------------------------------------------

function CreepService:GetActiveCreeps(): { [number]: CreepInstance }
	return self._activeCreeps
end

--------------------------------------------------------------------------------
-- Public: Damage a creep from hero or ability. Returns true if killed.
--------------------------------------------------------------------------------

function CreepService:DamageCreep(creepId: number, amount: number, killerPlayer: Player?): boolean
	local creep = self._activeCreeps[creepId]
	if not creep then
		return false
	end

	creep.Health -= amount
	_updateHealthBar(creep)

	-- Track which player last hit this creep for assist credit
	if killerPlayer then
		creep.LastHitByPlayer = killerPlayer
	end

	if creep.Health <= 0 then
		self:_onCreepKilledByHero(creep, killerPlayer)
		return true
	end
	return false
end

--------------------------------------------------------------------------------
-- Public: Hex (stun) a creep for a duration
--------------------------------------------------------------------------------

function CreepService:HexCreep(creepId: number, duration: number)
	local creep = self._activeCreeps[creepId]
	if not creep then
		return
	end
	creep.Hexed = true
	creep.HexExpires = os.clock() + duration
end

--------------------------------------------------------------------------------
-- Creep killed by hero/ability
--------------------------------------------------------------------------------

function CreepService:_onCreepKilledByHero(creep: CreepInstance, killerPlayer: Player?)
	local creepDef = CreepData[creep.CreepId]

	local bountyGold = 0
	local xpGained = 0

	-- Award XP and bounty gold to killer
	if killerPlayer and creepDef then
		xpGained = Constants.HERO_XP_PER_CREEP_KILL or 30
		local okHero, heroService = pcall(function()
			return Knit.GetService("HeroService")
		end)
		if okHero and heroService then
			heroService:AddXP(killerPlayer, xpGained)
		end

		bountyGold = math.floor(creepDef.Cost * (Constants.HERO_KILL_BOUNTY_PERCENT or 0.25))
		if bountyGold > 0 then
			local okIncome, incomeService = pcall(function()
				return Knit.GetService("IncomeService")
			end)
			if okIncome and incomeService then
				incomeService:AddGold(killerPlayer, bountyGold)
			end
		end
	end

	-- Fire kill reward signal so client shows gold/XP floating text
	if killerPlayer and (bountyGold > 0 or xpGained > 0) then
		self.Client.CreepKillReward:Fire(killerPlayer, creep.Position, bountyGold, xpGained)
	end

	-- Notify clients
	self.Client.CreepDied:FireAll({
		Id = creep.Id,
		Position = creep.Position,
		CreepId = creep.CreepId,
	})

	self:_destroyCreep(creep.Id)
end

--------------------------------------------------------------------------------
-- Destroy a creep
--------------------------------------------------------------------------------

function CreepService:_destroyCreep(creepId: number)
	local creep = self._activeCreeps[creepId]
	if not creep then
		return
	end

	if creep.Model then
		creep.Model:Destroy()
		creep.Model = nil
	end

	self._activeCreeps[creepId] = nil
end

--------------------------------------------------------------------------------
-- AI Attacker — simulates an opponent sending attack creeps
--------------------------------------------------------------------------------

local AI_ATTACK_INTERVAL = 6 -- seconds between AI sends
local AI_SPAWN_DELAY = 0.25

-- Escalation schedule: { maxElapsed, creepId, count }
local AI_ATTACK_ESCALATION = {
	{ 30, "Footman", 1 },
	{ 60, "Footman", 2 },
	{ 90, "Grunt", 1 },
	{ 130, "Grunt", 2 },
	{ 180, "Knight", 1 },
	{ 240, "Knight", 2 },
	-- After 240s → Abomination
}

local function _pickAIAttack(elapsed: number): (string, number)
	for _, entry in AI_ATTACK_ESCALATION do
		if elapsed < entry[1] then
			return entry[2], entry[3]
		end
	end
	return "Abomination", 1
end

function CreepService:StartAIAttacker()
	self._aiActive = true
	self._aiStartTime = os.clock()
	task.spawn(function()
		self:_runAIAttackerLoop()
	end)
end

function CreepService:StopAIAttacker()
	self._aiActive = false
end

function CreepService:_runAIAttackerLoop()
	while self._aiActive do
		task.wait(AI_ATTACK_INTERVAL)
		if not self._aiActive then
			break
		end

		local elapsed = os.clock() - self._aiStartTime
		local creepId, count = _pickAIAttack(elapsed)

		-- Find which teams have human players and attack them
		local TeamService = Knit.GetService("TeamService")
		for targetTeamId = 1, 2 do
			local teamPlayers = TeamService:GetTeamPlayers(targetTeamId)
			if #teamPlayers > 0 then
				-- AI attacks this team's lane (creeps march toward their base)
				local attackerTeamId = if targetTeamId == 1 then 2 else 1
				local laneKey = "AttackTeam" .. tostring(targetTeamId)

				for i = 1, count do
					task.delay((i - 1) * AI_SPAWN_DELAY, function()
						if self._aiActive then
							self:_createCreep(creepId, 0, attackerTeamId, targetTeamId, laneKey, 1)
						end
					end)
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Clear all creeps (used on round reset)
--------------------------------------------------------------------------------

function CreepService:ClearAllCreeps()
	for id, creep in self._activeCreeps do
		if creep.Model then
			creep.Model:Destroy()
			creep.Model = nil
		end
	end

	table.clear(self._activeCreeps)
	self._nextCreepId = 1
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function CreepService:KnitInit()
	local folder = Instance.new("Folder")
	folder.Name = "Creeps"
	folder.Parent = workspace
	self._creepFolder = folder
end

function CreepService:KnitStart()
	task.spawn(function()
		self:_runMovementLoop()
	end)
end

return CreepService
