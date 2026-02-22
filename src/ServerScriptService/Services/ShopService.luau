--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local CreepData = require(ReplicatedStorage.Shared.CreepData)
local ItemData = require(ReplicatedStorage.Shared.ItemData)

local ShopService = Knit.CreateService({
	Name = "ShopService",

	Client = {
		ItemPurchased = Knit.CreateSignal(),
	},
})

ShopService._playerItems = {} :: { [number]: { string } } -- UserId -> equipped items

function ShopService:KnitInit() end

function ShopService:KnitStart() end

function ShopService:BuyCreep(player: Player, creepId: string): boolean
	local creepService = Knit.GetService("CreepService")
	return creepService:SendCreep(player, creepId)
end

function ShopService:BuyItem(player: Player, itemId: string): boolean
	local itemDef = ItemData[itemId]
	if not itemDef then
		return false
	end

	local incomeService = Knit.GetService("IncomeService")
	if not incomeService:SpendGold(player, itemDef.Cost) then
		return false
	end

	-- Add item to player inventory
	local userId = player.UserId
	if not self._playerItems[userId] then
		self._playerItems[userId] = {}
	end
	table.insert(self._playerItems[userId], itemId)

	self.Client.ItemPurchased:Fire(player, itemId)
	return true
end

function ShopService:GetPlayerItems(player: Player): { string }
	return self._playerItems[player.UserId] or {}
end

function ShopService:GetAvailableCreeps(_player: Player): { string }
	-- Return creep IDs the player can buy based on their town hall tier
	local available = {}
	-- TODO: check player's town hall tier and filter
	for id, _def in CreepData do
		table.insert(available, id)
	end
	return available
end

-- Client-callable
function ShopService.Client:BuyCreep(player: Player, creepId: string): boolean
	return self.Server:BuyCreep(player, creepId)
end

function ShopService.Client:BuyItem(player: Player, itemId: string): boolean
	return self.Server:BuyItem(player, itemId)
end

function ShopService.Client:GetPlayerItems(player: Player): { string }
	return self.Server:GetPlayerItems(player)
end

function ShopService.Client:GetAvailableCreeps(player: Player): { string }
	return self.Server:GetAvailableCreeps(player)
end

return ShopService
