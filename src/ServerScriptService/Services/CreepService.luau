--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

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
local CREEP_AGGRO_RANGE = 8
local CREEP_ATTACK_COOLDOWN = 1

-- Separation: creeps push apart when closer than this
local CREEP_SEPARATION_DISTANCE = 4
local CREEP_SEPARATION_STRENGTH = 6 -- studs/sec push speed

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

	-- 5. Deduct gold
	local IncomeService = Knit.GetService("IncomeService")
	if not IncomeService:SpendGold(player, creepDef.Cost) then
		return false
	end

	-- 6. Add income bonus
	IncomeService:AddIncome(player, creepDef.IncomeBonus)

	-- 7. Spawn the wave
	self:_spawnWave(player, creepId, teamId)
	return true
end

--------------------------------------------------------------------------------
-- Wave spawning
--------------------------------------------------------------------------------

function CreepService:_spawnWave(player: Player, creepId: string, teamId: number)
	local targetTeamId = if teamId == 1 then 2 else 1
	local laneKey = if targetTeamId == 2 then "ToTeam2" else "ToTeam1"

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

	for i = 1, WAVE_SIZE do
		task.delay((i - 1) * CREEP_SPAWN_INTERVAL, function()
			local creep = self:_createCreep(creepId, player.UserId, teamId, targetTeamId, laneKey, hpMultiplier)
			creep.DamageMultiplier = dmgMultiplier
			creep.SpeedMultiplier = speedMultiplier
		end)
	end
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
	hpMultiplier: number
): CreepInstance
	local creepDef = CreepData[creepId]
	local id = self._nextCreepId
	self._nextCreepId += 1

	local baseHealth = math.floor(creepDef.Health * hpMultiplier)
	local baseSpawn = MapConfig.SPAWN_POSITIONS[teamId]
	-- Randomize X within ±12 studs so creeps spread across the lane width
	local xOffset = (math.random() * 24) - 12
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
	local creep: CreepInstance = {
		Id = id,
		CreepId = creepId,
		OwnerId = ownerId,
		TeamId = teamId,
		TargetTeamId = targetTeamId,
		LaneIndex = 1,
		WaypointIndex = 1,
		Position = spawnPosition,
		Health = baseHealth,
		MaxHealth = baseHealth,
		Model = model,
	}

	-- Store lane waypoints key on the instance for quick lookup.
	-- We use LaneIndex as a lookup alias; the actual waypoints array is resolved in the movement loop.
	-- (LaneIndex is currently unused beyond being part of the type; we keep it at 1.)

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
	return if creep.TargetTeamId == 2 then "ToTeam2" else "ToTeam1"
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

					if creep.Health <= 0 then
						self:_onCreepKilledByGate(creep)
						continue
					end
				end
			end

			-- Creep-vs-creep combat ----------------------------------------------
			local enemy = self:_findNearestEnemy(creep)
			if enemy then
				local lastAtk = creep.LastAttackTime or 0
				if now - lastAtk >= CREEP_ATTACK_COOLDOWN then
					creep.LastAttackTime = now
					local dmg = (creepDef.Damage or 10) * (creep.DamageMultiplier or 1)
					enemy.Health -= dmg
					_updateHealthBar(enemy)

					if enemy.Health <= 0 then
						self:_onCreepKilledByCreep(enemy)
					end
				end
				-- Engaged in combat — apply separation so creeps spread out
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
				local moveDistance = creepDef.MoveSpeed * (creep.SpeedMultiplier or 1) * dt
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
-- AI Wave System — spawns creeps for teams with no human players
--------------------------------------------------------------------------------

local AI_WAVE_INTERVAL = 12
local AI_WAVE_SIZE = 4
local AI_SPAWN_DELAY = 0.4

-- Escalation schedule: { maxElapsed, creepId }
local AI_ESCALATION = {
	{ 60, "Footman" },
	{ 120, "Grunt" },
	{ 240, "Knight" },
	-- After 240s → Abomination (fallback)
}

local function _pickAICreep(elapsed: number): string
	for _, entry in AI_ESCALATION do
		if elapsed < entry[1] then
			return entry[2]
		end
	end
	return "Abomination"
end

function CreepService:StartAIWaves()
	self._aiActive = true
	self._aiStartTime = os.clock()
	task.spawn(function()
		self:_runAIWaveLoop()
	end)
end

function CreepService:StopAIWaves()
	self._aiActive = false
end

function CreepService:_runAIWaveLoop()
	while self._aiActive do
		task.wait(AI_WAVE_INTERVAL)
		if not self._aiActive then
			break
		end

		local elapsed = os.clock() - self._aiStartTime
		local creepId = _pickAICreep(elapsed)

		-- Spawn AI waves for BOTH teams so creeps clash in the lane
		for teamId = 1, 2 do
			local targetTeamId = if teamId == 1 then 2 else 1
			local laneKey = if targetTeamId == 2 then "ToTeam2" else "ToTeam1"

			for i = 1, AI_WAVE_SIZE do
				task.delay((i - 1) * AI_SPAWN_DELAY, function()
					if self._aiActive then
						self:_createCreep(creepId, 0, teamId, targetTeamId, laneKey, 1)
					end
				end)
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
