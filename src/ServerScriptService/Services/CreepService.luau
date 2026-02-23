--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local CreepData = require(ReplicatedStorage.Shared.CreepData)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig)
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
	},
})

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

CreepService._nextCreepId = 1 :: number
CreepService._activeCreeps = {} :: { [number]: CreepInstance }
CreepService._creepFolder = nil :: Folder?

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

	for i = 1, WAVE_SIZE do
		task.delay((i - 1) * CREEP_SPAWN_INTERVAL, function()
			self:_createCreep(creepId, player.UserId, teamId, targetTeamId, laneKey, hpMultiplier)
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
	local spawnPosition = MapConfig.SPAWN_POSITIONS[teamId]

	-- Build the model ---------------------------------------------------------
	local model = Instance.new("Model")
	model.Name = "Creep_" .. id

	-- Body part
	local part = Instance.new("Part")
	part.Name = "Body"
	part.Size = Vector3.new(3, 3, 3)
	part.Color = MapConfig.TEAM_COLORS[teamId]
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CFrame = CFrame.new(spawnPosition)
	part.Parent = model
	model.PrimaryPart = part

	-- Health bar BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Size = UDim2.fromOffset(60, 14)
	gui.StudsOffset = Vector3.new(0, 2.5, 0)
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
-- Movement loop (10 Hz)
--------------------------------------------------------------------------------

function CreepService:_runMovementLoop()
	local dt = 1 / CREEP_UPDATE_RATE

	while true do
		task.wait(dt)

		for id, creep in self._activeCreeps do
			local creepDef = CreepData[creep.CreepId]
			if not creepDef then
				continue
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

			-- Movement -----------------------------------------------------------
			local currentWaypoint = waypoints[creep.WaypointIndex]
			if not currentWaypoint then
				-- No more waypoints; creep reached the base
				self:_onCreepReachedBase(creep)
				continue
			end

			local offset = currentWaypoint - creep.Position
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
				-- Move toward waypoint
				local direction = offset.Unit
				local moveDistance = creepDef.MoveSpeed * dt
				-- Clamp so we don't overshoot
				if moveDistance > distToWaypoint then
					moveDistance = distToWaypoint
				end
				creep.Position = creep.Position + direction * moveDistance
			end

			-- Update model CFrame
			local model = creep.Model
			if model then
				local body = model:FindFirstChild("Body") :: Part?
				if body then
					body.CFrame = CFrame.new(creep.Position)
				end
			end
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
