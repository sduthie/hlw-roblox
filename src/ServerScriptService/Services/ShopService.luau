--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local CreepData = require(ReplicatedStorage.Shared.CreepData)
local ItemData = require(ReplicatedStorage.Shared.ItemData)
local MedicalData = require(ReplicatedStorage.Shared.MedicalData)
local FamiliarData = require(ReplicatedStorage.Shared.FamiliarData)
local RemoteValidator = require(ReplicatedStorage.Shared.RemoteValidator)

local ShopService = Knit.CreateService({
	Name = "ShopService",

	Client = {
		ItemPurchased = Knit.CreateSignal(),
		TownHallUpgraded = Knit.CreateSignal(),
		MedicalPurchased = Knit.CreateSignal(),
		FamiliarPurchased = Knit.CreateSignal(),
	},
})

ShopService._playerItems = {} :: { [number]: { string } } -- UserId -> equipped item ids
ShopService._townHallTier = {} :: { [number]: number } -- UserId -> tier (1-3)
ShopService._playerFamiliars = {} :: { [number]: string? } -- UserId -> familiar id (one per player)
ShopService._creepPurchaseCounts = {} :: { [number]: { [string]: number } } -- UserId -> creepId -> times bought

-- Cost escalation: each purchase of the same creep type increases cost by 10%
local CREEP_COST_ESCALATION = 0.10

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function ShopService:KnitInit()
	Players.PlayerAdded:Connect(function(player)
		local userId = player.UserId
		self._playerItems[userId] = {}
		self._townHallTier[userId] = 1
		self._playerFamiliars[userId] = nil
		self._creepPurchaseCounts[userId] = {}
	end)

	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		self._playerItems[userId] = nil
		self._townHallTier[userId] = nil
		self._playerFamiliars[userId] = nil
		self._creepPurchaseCounts[userId] = nil
	end)
end

function ShopService:KnitStart() end

--------------------------------------------------------------------------------
-- Server methods (service-to-service)
--------------------------------------------------------------------------------

function ShopService:GetCreepCost(player: Player, creepId: string): number
	local creepDef = CreepData[creepId]
	if not creepDef then
		return 0
	end
	local userId = player.UserId
	local counts = self._creepPurchaseCounts[userId]
	local timesBought = if counts then (counts[creepId] or 0) else 0
	return math.ceil(creepDef.Cost * (1 + CREEP_COST_ESCALATION * timesBought))
end

function ShopService:BuyCreep(player: Player, creepId: string): boolean
	local CreepService = Knit.GetService("CreepService")
	return CreepService:SendCreep(player, creepId)
end

function ShopService:BuyItem(player: Player, itemId: string): boolean
	local itemDef = ItemData[itemId]
	if not itemDef then
		return false
	end

	-- Enforce maximum item limit
	local userId = player.UserId
	local items = self._playerItems[userId]
	if not items then
		items = {}
		self._playerItems[userId] = items
	end
	if #items >= Constants.MAX_ITEMS_PER_PLAYER then
		return false
	end

	-- Deduct gold (SpendGold already checks phase)
	local IncomeService = Knit.GetService("IncomeService")
	if not IncomeService:SpendGold(player, itemDef.Cost) then
		return false
	end

	table.insert(items, itemId)
	self.Client.ItemPurchased:Fire(player, itemId)
	return true
end

function ShopService:GetPlayerItems(player: Player): { string }
	return self._playerItems[player.UserId] or {}
end

function ShopService:GetAvailableCreeps(player: Player): { string }
	local tier = self._townHallTier[player.UserId] or 1
	local available: { string } = {}
	for id, def in CreepData do
		if def.Tier <= tier then
			table.insert(available, id)
		end
	end
	return available
end

function ShopService:GetTownHallTier(player: Player): number
	return self._townHallTier[player.UserId] or 1
end

function ShopService:UpgradeTownHall(player: Player): boolean
	local userId = player.UserId
	local currentTier = self._townHallTier[userId] or 1
	local maxTier = #Constants.TOWN_HALL_TIERS

	-- Already at max tier
	if currentTier >= maxTier then
		return false
	end

	local nextTier = currentTier + 1
	local cost = Constants.TOWN_HALL_UPGRADE_COST[nextTier]
	if not cost then
		return false
	end

	-- Deduct gold (SpendGold already checks phase)
	local IncomeService = Knit.GetService("IncomeService")
	if not IncomeService:SpendGold(player, cost) then
		return false
	end

	self._townHallTier[userId] = nextTier
	self.Client.TownHallUpgraded:Fire(player, nextTier)
	return true
end

function ShopService:BuyMedical(player: Player, medicalId: string): boolean
	local def = MedicalData[medicalId]
	if not def then
		return false
	end

	-- Deduct gold
	local IncomeService = Knit.GetService("IncomeService")
	if not IncomeService:SpendGold(player, def.Cost) then
		return false
	end

	local ok, heroCombatService = pcall(function()
		return Knit.GetService("HeroCombatService")
	end)
	if not ok or not heroCombatService then
		return false
	end

	if def.Instant then
		-- Instant heal
		heroCombatService:HealHero(player, def.HealAmount)
	else
		-- Apply buff
		heroCombatService:ApplyBuff(player, def.Name, def.BuffStat, def.BuffValue, def.Duration)
	end

	self.Client.MedicalPurchased:Fire(player, medicalId)
	return true
end

function ShopService:BuyFamiliar(player: Player, familiarId: string): boolean
	local def = FamiliarData[familiarId]
	if not def then
		return false
	end

	-- Premium familiars are not yet supported
	if def.IsPremium then
		return false
	end

	-- Deduct gold
	local IncomeService = Knit.GetService("IncomeService")
	if not IncomeService:SpendGold(player, def.Cost) then
		return false
	end

	-- Set familiar (one per player, replaces previous)
	local userId = player.UserId
	self._playerFamiliars[userId] = familiarId

	-- Recompute hero stats to include familiar bonuses
	local ok, heroCombatService = pcall(function()
		return Knit.GetService("HeroCombatService")
	end)
	if ok and heroCombatService then
		heroCombatService:RecomputeStats(player)
	end

	self.Client.FamiliarPurchased:Fire(player, familiarId)
	return true
end

function ShopService:GetPlayerFamiliar(player: Player): string?
	return self._playerFamiliars[player.UserId]
end

function ShopService:ResetAll()
	for _, player in Players:GetPlayers() do
		local userId = player.UserId
		self._playerItems[userId] = {}
		self._townHallTier[userId] = 1
		self._playerFamiliars[userId] = nil
		self._creepPurchaseCounts[userId] = {}
	end
end

--------------------------------------------------------------------------------
-- Client methods (remote-callable)
--------------------------------------------------------------------------------

function ShopService.Client:BuyCreep(player: Player, creepId: string): boolean
	if not RemoteValidator.isValidCreepId(creepId) then
		return false
	end
	if not RemoteValidator.rateLimit(player, "ShopService:BuyCreep", 0.5) then
		return false
	end
	return self.Server:BuyCreep(player, creepId)
end

function ShopService.Client:BuyItem(player: Player, itemId: string): boolean
	if not RemoteValidator.isValidItemId(itemId) then
		return false
	end
	if not RemoteValidator.rateLimit(player, "ShopService:BuyItem", 0.5) then
		return false
	end
	return self.Server:BuyItem(player, itemId)
end

function ShopService.Client:GetPlayerItems(player: Player): { string }
	if not RemoteValidator.rateLimit(player, "ShopService:GetPlayerItems", 0.1) then
		return self.Server._playerItems[player.UserId] or {}
	end
	return self.Server:GetPlayerItems(player)
end

function ShopService.Client:GetAvailableCreeps(player: Player): { string }
	if not RemoteValidator.rateLimit(player, "ShopService:GetAvailableCreeps", 0.1) then
		return self.Server:GetAvailableCreeps(player)
	end
	return self.Server:GetAvailableCreeps(player)
end

function ShopService.Client:GetCreepCost(player: Player, creepId: string): number
	return self.Server:GetCreepCost(player, creepId)
end

function ShopService.Client:GetAllCreepCosts(player: Player): { [string]: number }
	local costs = {}
	local counts = self.Server._creepPurchaseCounts[player.UserId] or {}
	for id, def in CreepData do
		local timesBought = counts[id] or 0
		costs[id] = math.ceil(def.Cost * (1 + CREEP_COST_ESCALATION * timesBought))
	end
	return costs
end

function ShopService.Client:GetTownHallTier(player: Player): number
	return self.Server:GetTownHallTier(player)
end

function ShopService.Client:UpgradeTownHall(player: Player): boolean
	if not RemoteValidator.rateLimit(player, "ShopService:UpgradeTownHall", 1.0) then
		return false
	end
	return self.Server:UpgradeTownHall(player)
end

function ShopService.Client:BuyMedical(player: Player, medicalId: string): boolean
	if not RemoteValidator.isValidMedicalId(medicalId) then
		return false
	end
	if not RemoteValidator.rateLimit(player, "ShopService:BuyMedical", 0.5) then
		return false
	end
	return self.Server:BuyMedical(player, medicalId)
end

function ShopService.Client:BuyFamiliar(player: Player, familiarId: string): boolean
	if not RemoteValidator.isValidFamiliarId(familiarId) then
		return false
	end
	if not RemoteValidator.rateLimit(player, "ShopService:BuyFamiliar", 1.0) then
		return false
	end
	return self.Server:BuyFamiliar(player, familiarId)
end

function ShopService.Client:GetPlayerFamiliar(player: Player): string?
	if not RemoteValidator.rateLimit(player, "ShopService:GetPlayerFamiliar", 0.1) then
		return self.Server._playerFamiliars[player.UserId]
	end
	return self.Server:GetPlayerFamiliar(player)
end

return ShopService
