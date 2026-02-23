--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local RemoteValidator = require(ReplicatedStorage.Shared.RemoteValidator)

local DataService = Knit.CreateService({
	Name = "DataService",

	Client = {},
})

-- Constants -------------------------------------------------------------------

local DATA_STORE_NAME = "HLW_PlayerData_v1"
local AUTO_SAVE_INTERVAL = 90
local MAX_RETRY_ATTEMPTS = 3
local BIND_TO_CLOSE_TIMEOUT = 25

local DATA_TEMPLATE = {
	Wins = 0,
	Losses = 0,
	GamesPlayed = 0,
	FavoriteHero = "",
	TotalCreepsSent = 0,
	TotalGoldEarned = 0,
}

-- Private state ---------------------------------------------------------------

DataService._store = nil :: any
DataService._playerData = {} :: { [number]: { [string]: any } }
DataService._sessionLocks = {} :: { [number]: string }
DataService._dataLoaded = {} :: { [number]: boolean }
DataService._isStudio = false :: boolean

-- Helpers ---------------------------------------------------------------------

local function getDataStoreKey(player: Player): string
	return "Player_" .. player.UserId
end

local function mergeWithTemplate(saved: { [string]: any }?): { [string]: any }
	local merged = table.clone(DATA_TEMPLATE)
	if saved then
		for key, value in saved do
			merged[key] = value
		end
	end
	return merged
end

local function retryWithBackoff<T>(label: string, maxAttempts: number, callback: () -> T): (boolean, T | string)
	for attempt = 1, maxAttempts do
		local ok, result = pcall(callback)
		if ok then
			return true, result :: any
		end

		local errorMessage = tostring(result)
		warn(string.format("[DataService] %s failed (attempt %d/%d): %s", label, attempt, maxAttempts, errorMessage))

		if attempt < maxAttempts then
			local delay = math.pow(2, attempt)
			task.wait(delay)
		end
	end

	return false, string.format("[DataService] %s failed after %d attempts", label, maxAttempts)
end

-- Data loading ----------------------------------------------------------------

function DataService:_loadData(player: Player)
	local userId = player.UserId

	if self._isStudio then
		self._playerData[userId] = mergeWithTemplate(nil)
		self._dataLoaded[userId] = true
		print("[DataService] Studio mode - loaded mock data for", player.Name)
		return
	end

	if not self._store then
		warn("[DataService] No DataStore available, using template for", player.Name)
		self._playerData[userId] = mergeWithTemplate(nil)
		self._dataLoaded[userId] = true
		return
	end

	local sessionGuid = HttpService:GenerateGUID(false)
	local dsKey = getDataStoreKey(player)

	local ok, result = retryWithBackoff("LoadData:" .. player.Name, MAX_RETRY_ATTEMPTS, function()
		return self._store:UpdateAsync(dsKey, function(currentData: { [string]: any }?)
			-- Check for existing session lock
			if currentData and currentData._sessionLock and currentData._sessionLock ~= "" then
				warn(
					string.format(
						"[DataService] Session lock detected for %s (lock: %s). Overriding with new session.",
						player.Name,
						tostring(currentData._sessionLock)
					)
				)
			end

			local merged = mergeWithTemplate(currentData)
			merged._sessionLock = sessionGuid
			merged._saveVersion = if currentData and currentData._saveVersion then currentData._saveVersion + 1 else 1
			return merged
		end)
	end)

	-- Player may have left during the async load
	if not player:IsDescendantOf(Players) then
		-- Player left before load finished; clean up the session lock if we claimed one
		if ok and self._store then
			task.spawn(function()
				self:_clearSessionLock(userId, dsKey, sessionGuid)
			end)
		end
		return
	end

	if ok and result then
		local data = result :: { [string]: any }
		self._playerData[userId] = data
		self._sessionLocks[userId] = sessionGuid
		self._dataLoaded[userId] = true
		print(string.format("[DataService] Loaded data for %s (version %s)", player.Name, tostring(data._saveVersion)))
	else
		warn("[DataService] Using template data for", player.Name, "-", tostring(result))
		self._playerData[userId] = mergeWithTemplate(nil)
		self._sessionLocks[userId] = sessionGuid
		self._dataLoaded[userId] = true
	end
end

-- Data saving -----------------------------------------------------------------

function DataService:_saveData(player: Player)
	local userId = player.UserId
	local data = self._playerData[userId]

	if not data or not self._dataLoaded[userId] then
		return
	end

	if self._isStudio then
		print("[DataService] Studio mode - skipped save for", player.Name)
		return
	end

	if not self._store then
		return
	end

	local sessionGuid = self._sessionLocks[userId]
	if not sessionGuid then
		warn("[DataService] No session lock for", player.Name, "- skipping save")
		return
	end

	local dsKey = getDataStoreKey(player)

	local ok, err = retryWithBackoff("SaveData:" .. player.Name, MAX_RETRY_ATTEMPTS, function()
		self._store:UpdateAsync(dsKey, function(currentData: { [string]: any }?)
			-- Verify session lock ownership
			if currentData and currentData._sessionLock ~= sessionGuid then
				warn(
					string.format(
						"[DataService] Session lock mismatch for %s. Expected %s, got %s. Aborting save.",
						player.Name,
						sessionGuid,
						tostring(currentData._sessionLock)
					)
				)
				return nil -- Returning nil cancels the UpdateAsync write
			end

			-- Clone the player's current data for the write
			local saveData = table.clone(data)
			saveData._sessionLock = sessionGuid
			saveData._saveVersion = if currentData and currentData._saveVersion then currentData._saveVersion + 1 else 1
			return saveData
		end)
	end)

	if not ok then
		warn("[DataService] Final save failure for", player.Name, "-", tostring(err))
	end
end

-- Session lock cleanup --------------------------------------------------------

function DataService:_clearSessionLock(userId: number, dsKey: string, expectedGuid: string)
	if self._isStudio or not self._store then
		return
	end

	local ok, err = pcall(function()
		self._store:UpdateAsync(dsKey, function(currentData: { [string]: any }?)
			if not currentData then
				return nil
			end

			if currentData._sessionLock == expectedGuid then
				currentData._sessionLock = ""
				return currentData
			end

			-- Another server has already claimed this data; do not modify
			return nil
		end)
	end)

	if not ok then
		warn("[DataService] Failed to clear session lock for userId", userId, "-", tostring(err))
	end
end

-- Player removal --------------------------------------------------------------

function DataService:_onPlayerRemoving(player: Player)
	local userId = player.UserId
	local sessionGuid = self._sessionLocks[userId]

	-- Save data
	self:_saveData(player)

	-- Clear session lock in DataStore
	if sessionGuid and self._store and not self._isStudio then
		local dsKey = getDataStoreKey(player)
		self:_clearSessionLock(userId, dsKey, sessionGuid)
	end

	-- Clean up local state
	self._playerData[userId] = nil
	self._sessionLocks[userId] = nil
	self._dataLoaded[userId] = nil

	-- Clean up rate limits
	RemoteValidator.clearPlayer(player)
end

-- Auto-save loop --------------------------------------------------------------

function DataService:_startAutoSaveLoop()
	task.spawn(function()
		while true do
			task.wait(AUTO_SAVE_INTERVAL)

			for _, player in Players:GetPlayers() do
				local userId = player.UserId
				if self._dataLoaded[userId] then
					task.spawn(function()
						self:_saveData(player)
					end)
				end
			end
		end
	end)
end

-- BindToClose -----------------------------------------------------------------

function DataService:_bindToClose()
	game:BindToClose(function()
		local activePlayers = Players:GetPlayers()
		if #activePlayers == 0 then
			return
		end

		local saveCount = 0
		local totalPlayers = 0

		for _, player in activePlayers do
			if self._dataLoaded[player.UserId] then
				totalPlayers += 1
			end
		end

		if totalPlayers == 0 then
			return
		end

		print(string.format("[DataService] BindToClose: saving %d players...", totalPlayers))

		for _, player in activePlayers do
			local userId = player.UserId
			if self._dataLoaded[userId] then
				task.spawn(function()
					self:_saveData(player)

					-- Clear session lock after save
					local sessionGuid = self._sessionLocks[userId]
					if sessionGuid and self._store and not self._isStudio then
						local dsKey = getDataStoreKey(player)
						self:_clearSessionLock(userId, dsKey, sessionGuid)
					end

					-- Clean up local state
					self._playerData[userId] = nil
					self._sessionLocks[userId] = nil
					self._dataLoaded[userId] = nil

					saveCount += 1
				end)
			end
		end

		-- Wait for all saves to complete, with timeout
		local elapsed = 0
		local pollInterval = 0.1
		while saveCount < totalPlayers and elapsed < BIND_TO_CLOSE_TIMEOUT do
			task.wait(pollInterval)
			elapsed += pollInterval
		end

		if saveCount < totalPlayers then
			warn(
				string.format(
					"[DataService] BindToClose timed out: saved %d/%d players in %.1fs",
					saveCount,
					totalPlayers,
					elapsed
				)
			)
		else
			print(string.format("[DataService] BindToClose complete: saved %d players in %.1fs", saveCount, elapsed))
		end
	end)
end

-- Knit lifecycle --------------------------------------------------------------

function DataService:KnitInit()
	self._isStudio = RunService:IsStudio()

	if self._isStudio then
		print("[DataService] Studio mode - using mock data")
		return
	end

	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(DATA_STORE_NAME)
	end)

	if ok then
		self._store = store
	else
		warn("[DataService] Failed to get DataStore:", tostring(store))
	end
end

function DataService:KnitStart()
	Players.PlayerAdded:Connect(function(player)
		self:_loadData(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:_onPlayerRemoving(player)
	end)

	-- Load data for any players already in the game (in case of late Knit startup)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:_loadData(player)
		end)
	end

	self:_startAutoSaveLoop()
	self:_bindToClose()
end

-- Public API ------------------------------------------------------------------

function DataService:GetData(player: Player): { [string]: any }?
	local data = self._playerData[player.UserId]
	if not data then
		return nil
	end
	return data
end

function DataService:SetValue(player: Player, key: string, value: any)
	local data = self._playerData[player.UserId]
	if not data then
		warn("[DataService] SetValue called before data loaded for", player.Name)
		return
	end

	if DATA_TEMPLATE[key] == nil and key ~= "_sessionLock" and key ~= "_saveVersion" then
		warn("[DataService] SetValue called with unknown key:", key)
		return
	end

	data[key] = value
end

function DataService:IncrementValue(player: Player, key: string, amount: number)
	local data = self._playerData[player.UserId]
	if not data then
		warn("[DataService] IncrementValue called before data loaded for", player.Name)
		return
	end

	if type(data[key]) ~= "number" then
		warn("[DataService] IncrementValue called on non-number key:", key)
		return
	end

	data[key] += amount
end

function DataService:SavePlayer(player: Player)
	self:_saveData(player)
end

return DataService
