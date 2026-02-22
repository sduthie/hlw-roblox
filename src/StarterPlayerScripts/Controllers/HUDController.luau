--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Util = require(ReplicatedStorage.Shared.Util)

local HUDController = Knit.CreateController({
	Name = "HUDController",
})

HUDController._gold = 0
HUDController._income = 0
HUDController._teamLives = { [1] = 100, [2] = 100 }

function HUDController:KnitInit() end

function HUDController:KnitStart()
	local incomeService = Knit.GetService("IncomeService")
	local gameService = Knit.GetService("GameService")

	incomeService.GoldChanged:Connect(function(gold: number)
		self._gold = gold
		self:_updateGoldDisplay()
	end)

	incomeService.IncomeChanged:Connect(function(income: number)
		self._income = income
		self:_updateIncomeDisplay()
	end)

	incomeService.IncomeTick:Connect(function(amount: number)
		self:_showIncomeTick(amount)
	end)

	gameService.PhaseChanged:Connect(function(phase: string)
		self:_onPhaseChanged(phase)
	end)

	gameService.TimerSync:Connect(function(timer: number)
		self:_updateTimer(timer)
	end)

	gameService.GameOver:Connect(function(winningTeamId: number)
		self:_showGameOver(winningTeamId)
	end)

	-- Fetch initial values
	self._gold = incomeService:GetGold()
	self._income = incomeService:GetIncome()
end

function HUDController:_updateGoldDisplay()
	-- TODO: update gold UI label
	_ = Util.formatGold(self._gold)
end

function HUDController:_updateIncomeDisplay()
	-- TODO: update income UI label
end

function HUDController:_showIncomeTick(_amount: number)
	-- TODO: show floating "+X gold" text
end

function HUDController:_onPhaseChanged(_phase: string)
	-- TODO: update phase-dependent UI elements
end

function HUDController:_updateTimer(_seconds: number)
	-- TODO: update timer display
end

function HUDController:_showGameOver(_winningTeamId: number)
	-- TODO: show game over screen
end

return HUDController
