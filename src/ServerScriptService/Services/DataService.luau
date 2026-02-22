--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local Knit = require(ReplicatedStorage.Packages.Knit)

local DataService = Knit.CreateService({
	Name = "DataService",

	Client = {},
})

local DATA_STORE_NAME = "HLW_PlayerData_v1"
local DATA_TEMPLATE = {
	Wins = 0,
	Losses = 0,
	GamesPlayed = 0,
	FavoriteHero = "",
	TotalCreepsSent = 0,
	TotalGoldEarned = 0,
}

DataService._store = nil :: any
DataService._playerData = {} :: { [number]: { [string]: any } }

function DataService:KnitInit()
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(DATA_STORE_NAME)
	end)
	if ok then
		self._store = store
	else
		warn("[HLW] Failed to get DataStore:", store)
	end
end

function DataService:KnitStart()
	Players.PlayerAdded:Connect(function(player)
		self:_loadData(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:_saveData(player)
		self._playerData[player.UserId] = nil
	end)

	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			self:_saveData(player)
		end
	end)
end

function DataService:GetData(player: Player): { [string]: any }
	return self._playerData[player.UserId] or table.clone(DATA_TEMPLATE)
end

function DataService:SetValue(player: Player, key: string, value: any)
	local data = self._playerData[player.UserId]
	if data then
		data[key] = value
	end
end

function DataService:IncrementValue(player: Player, key: string, amount: number)
	local data = self._playerData[player.UserId]
	if data and type(data[key]) == "number" then
		data[key] += amount
	end
end

function DataService:_loadData(player: Player)
	if not self._store then
		self._playerData[player.UserId] = table.clone(DATA_TEMPLATE)
		return
	end

	local ok, data = pcall(function()
		return self._store:GetAsync("Player_" .. player.UserId)
	end)

	if ok and data then
		-- Merge with template to handle new fields
		local merged = table.clone(DATA_TEMPLATE)
		for k, v in data do
			merged[k] = v
		end
		self._playerData[player.UserId] = merged
	else
		self._playerData[player.UserId] = table.clone(DATA_TEMPLATE)
		if not ok then
			warn("[HLW] Failed to load data for", player.Name, ":", data)
		end
	end
end

function DataService:_saveData(player: Player)
	local data = self._playerData[player.UserId]
	if not data or not self._store then
		return
	end

	local ok, err = pcall(function()
		self._store:SetAsync("Player_" .. player.UserId, data)
	end)

	if not ok then
		warn("[HLW] Failed to save data for", player.Name, ":", err)
	end
end

return DataService
