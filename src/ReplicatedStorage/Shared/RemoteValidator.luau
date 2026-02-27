--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HeroData = require(ReplicatedStorage.Shared.HeroData)
local CreepData = require(ReplicatedStorage.Shared.CreepData)
local ItemData = require(ReplicatedStorage.Shared.ItemData)
local UpgradeData = require(ReplicatedStorage.Shared.UpgradeData)
local MedicalData = require(ReplicatedStorage.Shared.MedicalData)
local FamiliarData = require(ReplicatedStorage.Shared.FamiliarData)

local RemoteValidator = {}

local _rateLimits: { [number]: { [string]: number } } = {}

-- Type checks

function RemoteValidator.isString(value: any): boolean
	return type(value) == "string"
end

function RemoteValidator.isNumber(value: any): boolean
	return type(value) == "number"
end

function RemoteValidator.isInteger(value: any): boolean
	return type(value) == "number" and value == math.floor(value)
end

-- Data validation

function RemoteValidator.isValidHeroId(value: any): boolean
	return type(value) == "string" and HeroData[value] ~= nil
end

function RemoteValidator.isValidCreepId(value: any): boolean
	return type(value) == "string" and CreepData[value] ~= nil
end

function RemoteValidator.isValidItemId(value: any): boolean
	return type(value) == "string" and ItemData[value] ~= nil
end

function RemoteValidator.isValidUpgradeId(value: any): boolean
	return type(value) == "string" and UpgradeData[value] ~= nil
end

function RemoteValidator.isValidTeamId(value: any): boolean
	return type(value) == "number" and (value == 1 or value == 2)
end

function RemoteValidator.isValidMedicalId(value: any): boolean
	return type(value) == "string" and MedicalData[value] ~= nil
end

function RemoteValidator.isValidFamiliarId(value: any): boolean
	return type(value) == "string" and FamiliarData[value] ~= nil
end

-- Rate limiting: returns true if allowed, false if throttled

function RemoteValidator.rateLimit(player: Player, action: string, cooldown: number): boolean
	local userId = player.UserId
	local now = os.clock()

	if not _rateLimits[userId] then
		_rateLimits[userId] = {}
	end

	local lastTime = _rateLimits[userId][action]
	if lastTime and (now - lastTime) < cooldown then
		return false
	end

	_rateLimits[userId][action] = now
	return true
end

-- Cleanup on player leave

function RemoteValidator.clearPlayer(player: Player)
	_rateLimits[player.UserId] = nil
end

return RemoteValidator
