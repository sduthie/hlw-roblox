--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)

local GameService = Knit.CreateService({
	Name = "GameService",

	Client = {
		PhaseChanged = Knit.CreateSignal(),
		TimerSync = Knit.CreateSignal(),
		GameOver = Knit.CreateSignal(),
	},
})

GameService._phase = Constants.PHASE_LOBBY
GameService._timer = 0
GameService._teamLives = {} :: { [number]: number }

function GameService:KnitInit()
	self._teamLives[1] = Constants.BASE_MAX_LIVES
	self._teamLives[2] = Constants.BASE_MAX_LIVES
end

function GameService:KnitStart()
	Players.PlayerAdded:Connect(function(player)
		self:_onPlayerAdded(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:_onPlayerRemoving(player)
	end)
end

function GameService:GetPhase(): string
	return self._phase
end

function GameService:SetPhase(phase: string)
	self._phase = phase
	self.Client.PhaseChanged:FireAll(phase)
end

function GameService:GetTeamLives(teamId: number): number
	return self._teamLives[teamId] or 0
end

function GameService:DamageBase(teamId: number, amount: number)
	local lives = self._teamLives[teamId]
	if not lives then
		return
	end

	self._teamLives[teamId] = math.max(0, lives - amount)

	if self._teamLives[teamId] <= 0 then
		self:_endGame(teamId)
	end
end

function GameService:_endGame(losingTeamId: number)
	local winningTeamId = if losingTeamId == 1 then 2 else 1
	self:SetPhase(Constants.PHASE_GAME_OVER)
	self.Client.GameOver:FireAll(winningTeamId)
end

function GameService:_onPlayerAdded(_player: Player)
	-- Assign team, initialize player state
end

function GameService:_onPlayerRemoving(_player: Player)
	-- Clean up player state
end

-- Client-callable
function GameService.Client:GetPhase(): string
	return self.Server:GetPhase()
end

function GameService.Client:GetTeamLives(_player: Player, teamId: number): number
	return self.Server:GetTeamLives(teamId)
end

return GameService
