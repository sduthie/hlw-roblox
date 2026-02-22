--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)

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

function IncomeService:KnitInit() end

function IncomeService:KnitStart()
	Players.PlayerAdded:Connect(function(player)
		self._gold[player.UserId] = Constants.STARTING_GOLD
		self._income[player.UserId] = Constants.STARTING_INCOME
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._gold[player.UserId] = nil
		self._income[player.UserId] = nil
	end)

	-- Start income loop
	task.spawn(function()
		self:_incomeLoop()
	end)
end

function IncomeService:GetGold(player: Player): number
	return self._gold[player.UserId] or 0
end

function IncomeService:GetIncome(player: Player): number
	return self._income[player.UserId] or 0
end

function IncomeService:SpendGold(player: Player, amount: number): boolean
	local current = self._gold[player.UserId] or 0
	if current < amount then
		return false
	end

	self._gold[player.UserId] = current - amount
	self.Client.GoldChanged:Fire(player, self._gold[player.UserId])
	return true
end

function IncomeService:AddGold(player: Player, amount: number)
	self._gold[player.UserId] = (self._gold[player.UserId] or 0) + amount
	self.Client.GoldChanged:Fire(player, self._gold[player.UserId])
end

function IncomeService:AddIncome(player: Player, amount: number)
	self._income[player.UserId] = (self._income[player.UserId] or 0) + amount
	self.Client.IncomeChanged:Fire(player, self._income[player.UserId])
end

function IncomeService:_incomeLoop()
	while true do
		task.wait(Constants.INCOME_INTERVAL)

		local gameService = Knit.GetService("GameService")
		if gameService:GetPhase() ~= Constants.PHASE_PLAYING then
			continue
		end

		for _, player in Players:GetPlayers() do
			local income = self._income[player.UserId] or 0
			self:AddGold(player, income)
			self.Client.IncomeTick:Fire(player, income)
		end
	end
end

-- Client-callable
function IncomeService.Client:GetGold(player: Player): number
	return self.Server:GetGold(player)
end

function IncomeService.Client:GetIncome(player: Player): number
	return self.Server:GetIncome(player)
end

return IncomeService
