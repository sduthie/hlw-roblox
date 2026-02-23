--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local CreepData = require(ReplicatedStorage.Shared.CreepData)
local ItemData = require(ReplicatedStorage.Shared.ItemData)
local RemoteValidator = require(ReplicatedStorage.Shared.RemoteValidator)

local ShopService = Knit.CreateService({
	Name = "ShopService",

	Client = {
		ItemPurchased = Knit.CreateSignal(),
		TownHallUpgraded = Knit.CreateSignal(),
	},
})

ShopService._playerItems = {} :: { [number]: { string } } -- UserId -> equipped item ids
ShopService._townHallTier = {} :: { [number]: number } -- UserId -> tier (1-3)

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function ShopService:KnitInit()
	Players.PlayerAdded:Connect(function(player)
		local userId = player.UserId
		self._playerItems[userId] = {}
		self._townHallTier[userId] = 1
	end)

	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		self._playerItems[userId] = nil
		self._townHallTier[userId] = nil
	end)
end

function ShopService:KnitStart() end

--------------------------------------------------------------------------------
-- Server methods (service-to-service)
--------------------------------------------------------------------------------

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

function ShopService:ResetAll()
	for _, player in Players:GetPlayers() do
		local userId = player.UserId
		self._playerItems[userId] = {}
		self._townHallTier[userId] = 1
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

function ShopService.Client:UpgradeTownHall(player: Player): boolean
	if not RemoteValidator.rateLimit(player, "ShopService:UpgradeTownHall", 1.0) then
		return false
	end
	return self.Server:UpgradeTownHall(player)
end

return ShopService
