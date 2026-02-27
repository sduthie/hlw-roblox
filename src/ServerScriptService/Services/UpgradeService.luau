--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local UpgradeData = require(ReplicatedStorage.Shared.UpgradeData)
local RemoteValidator = require(ReplicatedStorage.Shared.RemoteValidator)

local UpgradeService = Knit.CreateService({
	Name = "UpgradeService",

	Client = {
		UpgradePurchased = Knit.CreateSignal(),
	},
})

-- UserId -> { upgradeId -> currentLevel }
UpgradeService._playerUpgrades = {} :: { [number]: { [string]: number } }

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function UpgradeService:KnitInit()
	Players.PlayerAdded:Connect(function(player)
		self._playerUpgrades[player.UserId] = {}
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._playerUpgrades[player.UserId] = nil
	end)
end

function UpgradeService:KnitStart() end

--------------------------------------------------------------------------------
-- Server methods (service-to-service)
--------------------------------------------------------------------------------

function UpgradeService:PurchaseUpgrade(player: Player, upgradeId: string): boolean
	local def = UpgradeData[upgradeId]
	if not def then
		return false
	end

	-- Phase check
	local GameService = Knit.GetService("GameService")
	if GameService:GetPhase() ~= Constants.PHASE_PLAYING then
		return false
	end

	local userId = player.UserId
	local upgrades = self._playerUpgrades[userId]
	if not upgrades then
		upgrades = {}
		self._playerUpgrades[userId] = upgrades
	end

	local currentLevel = upgrades[upgradeId] or 0
	if currentLevel >= def.MaxLevel then
		return false
	end

	local nextLevel = currentLevel + 1
	local cost = def.Costs[nextLevel]
	if not cost then
		return false
	end

	-- Deduct gold
	local IncomeService = Knit.GetService("IncomeService")
	if not IncomeService:SpendGold(player, cost) then
		return false
	end

	-- Record upgrade
	upgrades[upgradeId] = nextLevel

	-- Apply effects
	self:_applyUpgradeEffect(player, def, nextLevel)

	-- Notify client
	self.Client.UpgradePurchased:Fire(player, upgradeId, nextLevel)

	return true
end

function UpgradeService:GetUpgradeLevel(player: Player, upgradeId: string): number
	local upgrades = self._playerUpgrades[player.UserId]
	if not upgrades then
		return 0
	end
	return upgrades[upgradeId] or 0
end

function UpgradeService:GetAllUpgrades(player: Player): { [string]: number }
	return self._playerUpgrades[player.UserId] or {}
end

function UpgradeService:ResetPlayer(player: Player)
	self._playerUpgrades[player.UserId] = {}
end

function UpgradeService:ResetAll()
	for _, player in Players:GetPlayers() do
		self._playerUpgrades[player.UserId] = {}
	end
end

--------------------------------------------------------------------------------
-- Apply effects on purchase
--------------------------------------------------------------------------------

function UpgradeService:_applyUpgradeEffect(player: Player, def: any, level: number)
	if def.Category == "Economy" then
		-- Add income bonus
		local bonus = def.IncomeBonus[level]
		if bonus then
			local prevBonus = if level > 1 then def.IncomeBonus[level - 1] else 0
			local incremental = bonus - prevBonus
			local IncomeService = Knit.GetService("IncomeService")
			IncomeService:AddIncome(player, incremental)
		end

	elseif def.Category == "Hero" then
		-- Recompute hero stats (upgrade bonuses are read at compute time)
		local ok, heroCombatService = pcall(function()
			return Knit.GetService("HeroCombatService")
		end)
		if ok and heroCombatService then
			heroCombatService:RecomputeStats(player)
		end
	end
	-- Minion upgrades are applied at creep spawn time (no immediate effect)
end

--------------------------------------------------------------------------------
-- Helpers for other services to query bonuses
--------------------------------------------------------------------------------

function UpgradeService:GetHeroBonusDamage(player: Player): number
	local level = self:GetUpgradeLevel(player, "SharpenedEdge")
	if level == 0 then
		return 0
	end
	local def = UpgradeData.SharpenedEdge
	return def.BonusDamage[level] or 0
end

function UpgradeService:GetHeroBonusArmor(player: Player): number
	local level = self:GetUpgradeLevel(player, "IronPlating")
	if level == 0 then
		return 0
	end
	local def = UpgradeData.IronPlating
	return def.BonusArmor[level] or 0
end

function UpgradeService:GetHeroAttackSpeedPct(player: Player): number
	local level = self:GetUpgradeLevel(player, "SwiftBoots")
	if level == 0 then
		return 0
	end
	local def = UpgradeData.SwiftBoots
	return def.AttackSpeedPct[level] or 0
end

function UpgradeService:GetHeroBonusMana(player: Player): number
	local level = self:GetUpgradeLevel(player, "ArcaneWisdom")
	if level == 0 then
		return 0
	end
	local def = UpgradeData.ArcaneWisdom
	return def.BonusMana[level] or 0
end

function UpgradeService:GetHeroBonusManaRegen(player: Player): number
	local level = self:GetUpgradeLevel(player, "ArcaneWisdom")
	if level == 0 then
		return 0
	end
	local def = UpgradeData.ArcaneWisdom
	return def.BonusManaRegen[level] or 0
end

function UpgradeService:GetCreepHpPct(player: Player): number
	local level = self:GetUpgradeLevel(player, "WarDrums")
	if level == 0 then
		return 0
	end
	local def = UpgradeData.WarDrums
	return def.CreepHpPct[level] or 0
end

function UpgradeService:GetCreepDmgPct(player: Player): number
	local level = self:GetUpgradeLevel(player, "SharpenedBlades")
	if level == 0 then
		return 0
	end
	local def = UpgradeData.SharpenedBlades
	return def.CreepDmgPct[level] or 0
end

function UpgradeService:GetCreepSpeedPct(player: Player): number
	local level = self:GetUpgradeLevel(player, "BattleStandard")
	if level == 0 then
		return 0
	end
	local def = UpgradeData.BattleStandard
	return def.CreepSpeedPct[level] or 0
end

--------------------------------------------------------------------------------
-- Client methods (remote-callable)
--------------------------------------------------------------------------------

function UpgradeService.Client:PurchaseUpgrade(player: Player, upgradeId: string): boolean
	if type(upgradeId) ~= "string" or not UpgradeData[upgradeId] then
		return false
	end
	if not RemoteValidator.rateLimit(player, "UpgradeService:PurchaseUpgrade", 0.5) then
		return false
	end
	return self.Server:PurchaseUpgrade(player, upgradeId)
end

function UpgradeService.Client:GetAllUpgrades(player: Player): { [string]: number }
	if not RemoteValidator.rateLimit(player, "UpgradeService:GetAllUpgrades", 0.1) then
		return self.Server._playerUpgrades[player.UserId] or {}
	end
	return self.Server:GetAllUpgrades(player)
end

function UpgradeService.Client:GetUpgradeLevel(player: Player, upgradeId: string): number
	return self.Server:GetUpgradeLevel(player, upgradeId)
end

return UpgradeService
