--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local CreepData = require(ReplicatedStorage.Shared.CreepData)

local CreepService = Knit.CreateService({
	Name = "CreepService",

	Client = {
		CreepSpawned = Knit.CreateSignal(),
		CreepDied = Knit.CreateSignal(),
		CreepReachedBase = Knit.CreateSignal(),
	},
})

CreepService._activeCreeps = {} :: { [number]: any } -- instanceId -> creep data

function CreepService:KnitInit() end

function CreepService:KnitStart() end

function CreepService:SendCreep(player: Player, creepId: string): boolean
	local creepDef = CreepData[creepId]
	if not creepDef then
		return false
	end

	-- Validate player can afford and has the right tier
	local incomeService = Knit.GetService("IncomeService")
	local gold = incomeService:GetGold(player)
	if gold < creepDef.Cost then
		return false
	end

	-- Deduct gold and grant income
	incomeService:SpendGold(player, creepDef.Cost)
	incomeService:AddIncome(player, creepDef.IncomeBonus)

	-- Spawn the wave
	self:_spawnWave(player, creepDef)
	return true
end

function CreepService:_spawnWave(_player: Player, _creepDef: any)
	-- Spawn WAVE_SIZE creeps at intervals along the enemy's lane
	-- Each creep follows the path toward the enemy base ring
	-- TODO: create creep models, attach pathfinding
	-- Will spawn Constants.WAVE_SIZE creeps at intervals
end

function CreepService:_onCreepReachedBase(creepModel: any, targetTeamId: number)
	local gameService = Knit.GetService("GameService")
	gameService:DamageBase(targetTeamId, 1)
	self.Client.CreepReachedBase:FireAll(targetTeamId)

	-- Clean up creep
	if creepModel and creepModel.Parent then
		creepModel:Destroy()
	end
end

function CreepService:_onCreepDied(creepModel: any)
	-- Grant XP to nearby heroes, remove from tracking
	if creepModel and creepModel.Parent then
		creepModel:Destroy()
	end
end

-- Client-callable
function CreepService.Client:SendCreep(player: Player, creepId: string): boolean
	return self.Server:SendCreep(player, creepId)
end

return CreepService
