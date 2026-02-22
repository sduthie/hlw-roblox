--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local BaseService = Knit.CreateService({
	Name = "BaseService",

	Client = {
		BaseDamaged = Knit.CreateSignal(),
		LivesUpdated = Knit.CreateSignal(),
	},
})

function BaseService:KnitInit() end

function BaseService:KnitStart() end

function BaseService:DamageBase(teamId: number, amount: number)
	local gameService = Knit.GetService("GameService")
	local livesBefore = gameService:GetTeamLives(teamId)
	gameService:DamageBase(teamId, amount)
	local livesAfter = gameService:GetTeamLives(teamId)

	if livesBefore ~= livesAfter then
		self.Client.BaseDamaged:FireAll(teamId, amount)
		self.Client.LivesUpdated:FireAll(teamId, livesAfter)
	end
end

function BaseService:GetLives(teamId: number): number
	local gameService = Knit.GetService("GameService")
	return gameService:GetTeamLives(teamId)
end

-- Client-callable
function BaseService.Client:GetLives(_player: Player, teamId: number): number
	return self.Server:GetLives(teamId)
end

return BaseService
