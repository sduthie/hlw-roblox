--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local CreepData = require(ReplicatedStorage.Shared.CreepData)
local ItemData = require(ReplicatedStorage.Shared.ItemData)

local ShopController = Knit.CreateController({
	Name = "ShopController",
})

ShopController._shopOpen = false

function ShopController:KnitInit() end

function ShopController:KnitStart()
	local shopService = Knit.GetService("ShopService")

	shopService.ItemPurchased:Connect(function(itemId: string)
		self:_onItemPurchased(itemId)
	end)
end

function ShopController:BuyCreep(creepId: string)
	local shopService = Knit.GetService("ShopService")
	shopService:BuyCreep(creepId)
end

function ShopController:BuyItem(itemId: string)
	local shopService = Knit.GetService("ShopService")
	shopService:BuyItem(itemId)
end

function ShopController:GetCreepCatalog(): { [string]: any }
	return CreepData
end

function ShopController:GetItemCatalog(): { [string]: any }
	return ItemData
end

function ShopController:ToggleShop()
	self._shopOpen = not self._shopOpen
	-- TODO: show/hide shop UI
end

function ShopController:_onItemPurchased(itemId: string)
	-- TODO: show purchase confirmation in UI
	print("[HLW] Purchased:", itemId)
end

return ShopController
