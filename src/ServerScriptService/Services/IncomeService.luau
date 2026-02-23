--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local RemoteValidator = require(ReplicatedStorage.Shared.RemoteValidator)

local IncomeService = Knit.CreateService({
	Name = "IncomeService",

	Client = {
		GoldChanged = Knit.CreateSignal(),
		IncomeChanged = Knit.CreateSignal(),
		IncomeTick = Knit.CreateSignal(),
	},
})

IncomeService._gold = {} :: { [number]: number } -- UserId -> gold
IncomeService._income = {} :: { [number]: number } -- UserId -> income per tick

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function IncomeService:KnitInit()
	Players.PlayerAdded:Connect(function(player)
		self._gold[player.UserId] = Constants.STARTING_GOLD
		self._income[player.UserId] = Constants.STARTING_INCOME
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._gold[player.UserId] = nil
		self._income[player.UserId] = nil
	end)
end

function IncomeService:KnitStart()
	task.spawn(function()
		self:_incomeLoop()
	end)
end

--------------------------------------------------------------------------------
-- Income loop
--------------------------------------------------------------------------------

function IncomeService:_incomeLoop()
	while true do
		task.wait(Constants.INCOME_INTERVAL)

		local GameService = Knit.GetService("GameService")
		if GameService:GetPhase() ~= Constants.PHASE_PLAYING then
			continue
		end

		for _, player in Players:GetPlayers() do
			local income = self._income[player.UserId] or 0
			self:AddGold(player, income)
			self.Client.IncomeTick:Fire(player, income)
		end
	end
end

--------------------------------------------------------------------------------
-- Server methods (service-to-service)
--------------------------------------------------------------------------------

function IncomeService:GetGold(player: Player): number
	return self._gold[player.UserId] or 0
end

function IncomeService:GetIncome(player: Player): number
	return self._income[player.UserId] or 0
end

function IncomeService:SpendGold(player: Player, amount: number): boolean
	-- Only allow spending during the Playing phase
	local GameService = Knit.GetService("GameService")
	if GameService:GetPhase() ~= Constants.PHASE_PLAYING then
		return false
	end

	local userId = player.UserId
	local current = self._gold[userId] or 0
	if current < amount then
		return false
	end

	self._gold[userId] = current - amount
	self.Client.GoldChanged:Fire(player, self._gold[userId])
	return true
end

function IncomeService:AddGold(player: Player, amount: number)
	local userId = player.UserId
	self._gold[userId] = (self._gold[userId] or 0) + amount
	self.Client.GoldChanged:Fire(player, self._gold[userId])
end

function IncomeService:AddIncome(player: Player, amount: number)
	local userId = player.UserId
	self._income[userId] = (self._income[userId] or 0) + amount
	self.Client.IncomeChanged:Fire(player, self._income[userId])
end

function IncomeService:ResetPlayer(player: Player)
	local userId = player.UserId
	self._gold[userId] = Constants.STARTING_GOLD
	self._income[userId] = Constants.STARTING_INCOME
	self.Client.GoldChanged:Fire(player, self._gold[userId])
	self.Client.IncomeChanged:Fire(player, self._income[userId])
end

--------------------------------------------------------------------------------
-- Client methods (remote-callable)
--------------------------------------------------------------------------------

function IncomeService.Client:GetGold(player: Player): number
	if not RemoteValidator.rateLimit(player, "IncomeService:GetGold", 0.1) then
		return self.Server._gold[player.UserId] or 0
	end
	return self.Server:GetGold(player)
end

function IncomeService.Client:GetIncome(player: Player): number
	if not RemoteValidator.rateLimit(player, "IncomeService:GetIncome", 0.1) then
		return self.Server._income[player.UserId] or 0
	end
	return self.Server:GetIncome(player)
end

return IncomeService
