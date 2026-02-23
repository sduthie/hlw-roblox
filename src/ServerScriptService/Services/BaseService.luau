--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local RemoteValidator = require(ReplicatedStorage.Shared.RemoteValidator)

local BaseService = Knit.CreateService({
	Name = "BaseService",

	Client = {
		BaseDamaged = Knit.CreateSignal(),
		LivesUpdated = Knit.CreateSignal(),
	},
})

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function BaseService:KnitInit() end

function BaseService:KnitStart()
	Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			local GameService = Knit.GetService("GameService")
			for teamId = 1, 2 do
				local lives = GameService:GetTeamLives(teamId)
				self.Client.LivesUpdated:Fire(player, teamId, lives)
			end
		end)
	end)
end

--------------------------------------------------------------------------------
-- Server methods
--------------------------------------------------------------------------------

function BaseService:DamageBase(teamId: number, amount: number, _creepTier: number?)
	local GameService = Knit.GetService("GameService")
	local livesBefore = GameService:GetTeamLives(teamId)
	GameService:DamageBase(teamId, amount)
	local livesAfter = GameService:GetTeamLives(teamId)

	if livesBefore ~= livesAfter then
		self.Client.BaseDamaged:FireAll(teamId, amount)
		self.Client.LivesUpdated:FireAll(teamId, livesAfter)
	end
end

function BaseService:GetLives(teamId: number): number
	local GameService = Knit.GetService("GameService")
	return GameService:GetTeamLives(teamId)
end

--------------------------------------------------------------------------------
-- Client-callable
--------------------------------------------------------------------------------

function BaseService.Client:GetLives(player: Player, teamId: number): number
	if not RemoteValidator.rateLimit(player, "GetLives", 0.1) then
		return self.Server:GetLives(teamId)
	end
	return self.Server:GetLives(teamId)
end

return BaseService
