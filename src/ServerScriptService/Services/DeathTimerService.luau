--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig)
local RemoteValidator = require(ReplicatedStorage.Shared.RemoteValidator)

local DeathTimerService = Knit.CreateService({
	Name = "DeathTimerService",

	Client = {
		RespawnTimerStarted = Knit.CreateSignal(),
		RespawnComplete = Knit.CreateSignal(),
	},
})

DeathTimerService._deathCounts = {} :: { [number]: number } -- UserId -> death count this game
DeathTimerService._respawnTimers = {} :: { [number]: number } -- UserId -> when they can respawn (os.clock timestamp)
DeathTimerService._characterConnections = {} :: { [number]: RBXScriptConnection? } -- UserId -> Humanoid.Died connection

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function DeathTimerService:KnitInit()
	Players.PlayerAdded:Connect(function(player)
		local userId = player.UserId
		self._deathCounts[userId] = 0
		self._respawnTimers[userId] = nil

		-- Connect to CharacterAdded to track deaths
		player.CharacterAdded:Connect(function(character)
			self:_connectCharacterDeath(player, character)
		end)

		-- Handle existing character (if already spawned)
		if player.Character then
			self:_connectCharacterDeath(player, player.Character)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		self._deathCounts[userId] = nil
		self._respawnTimers[userId] = nil

		-- Disconnect any existing Humanoid.Died connection
		local conn = self._characterConnections[userId]
		if conn then
			conn:Disconnect()
			self._characterConnections[userId] = nil
		end
	end)
end

function DeathTimerService:KnitStart() end

--------------------------------------------------------------------------------
-- Character death detection
--------------------------------------------------------------------------------

function DeathTimerService:_connectCharacterDeath(player: Player, character: Model)
	local userId = player.UserId

	-- Disconnect previous connection if any
	local oldConn = self._characterConnections[userId]
	if oldConn then
		oldConn:Disconnect()
		self._characterConnections[userId] = nil
	end

	-- Wait for humanoid
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	end

	if not humanoid then
		return
	end

	self._characterConnections[userId] = humanoid.Died:Connect(function()
		-- Only process deaths during PHASE_PLAYING
		local okGame, gameService = pcall(function()
			return Knit.GetService("GameService")
		end)
		if not okGame or not gameService then
			return
		end

		if gameService:GetPhase() ~= Constants.PHASE_PLAYING then
			return
		end

		self:OnHeroDied(player)
	end)
end

--------------------------------------------------------------------------------
-- Server methods (service-to-service)
--------------------------------------------------------------------------------

function DeathTimerService:OnHeroDied(player: Player)
	local userId = player.UserId

	-- Increment death count
	local deaths = (self._deathCounts[userId] or 0) + 1
	self._deathCounts[userId] = deaths

	-- Calculate respawn time: min(BASE + PER_DEATH * deaths, MAX)
	local respawnTime = math.min(
		Constants.DEATH_TIMER_BASE + Constants.DEATH_TIMER_PER_DEATH * deaths,
		Constants.DEATH_TIMER_MAX
	)

	-- Set respawn timestamp
	self._respawnTimers[userId] = os.clock() + respawnTime

	-- Fire RespawnTimerStarted to client
	self.Client.RespawnTimerStarted:Fire(player, respawnTime)

	-- Spawn a task to respawn after delay
	task.delay(respawnTime, function()
		-- Verify the player is still in the game and still dead (timer not cleared by resurrection)
		if not player.Parent then
			return
		end
		if not self._respawnTimers[userId] then
			return
		end

		self:_respawnPlayer(player)
	end)
end

function DeathTimerService:UseResurrectionPotion(player: Player): boolean
	local userId = player.UserId

	-- Check if player is dead (has active respawn timer)
	if not self._respawnTimers[userId] then
		return false
	end

	-- Immediately respawn them and reset timer
	self._respawnTimers[userId] = nil
	self:_respawnPlayer(player)
	return true
end

function DeathTimerService:GetDeathCount(player: Player): number
	return self._deathCounts[player.UserId] or 0
end

function DeathTimerService:ResetAll()
	for _, player in Players:GetPlayers() do
		local userId = player.UserId
		self._deathCounts[userId] = 0
		self._respawnTimers[userId] = nil
	end
end

--------------------------------------------------------------------------------
-- Respawn logic
--------------------------------------------------------------------------------

function DeathTimerService:_respawnPlayer(player: Player)
	local userId = player.UserId

	-- Clear respawn timer
	self._respawnTimers[userId] = nil

	-- Reload the character
	player:LoadCharacter()

	-- Wait briefly for character to load
	task.delay(0.5, function()
		if not player.Parent then
			return
		end

		-- Teleport to team spawn position
		local okTeam, teamService = pcall(function()
			return Knit.GetService("TeamService")
		end)
		if okTeam and teamService then
			local teamId = teamService:GetTeam(player)
			if teamId then
				local spawnPos = MapConfig.HERO_POSITIONS[teamId]
				if spawnPos and player.Character then
					local rootPart = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
					if rootPart then
						rootPart.CFrame = CFrame.new(spawnPos + Vector3.new(0, 3, 0))
					end
				end
			end
		end

		-- Restore full health via HeroCombatService
		local okCombat, heroCombatService = pcall(function()
			return Knit.GetService("HeroCombatService")
		end)
		if okCombat and heroCombatService then
			-- Re-init combat state for this player after respawn
			if heroCombatService._initPlayerState then
				heroCombatService:_initPlayerState(player)
			end
		end

		-- Fire RespawnComplete to client
		self.Client.RespawnComplete:Fire(player)
	end)
end

--------------------------------------------------------------------------------
-- Client methods (remote-callable)
--------------------------------------------------------------------------------

function DeathTimerService.Client:GetDeathCount(player: Player): number
	if not RemoteValidator.rateLimit(player, "DeathTimerService:GetDeathCount", 0.1) then
		return self.Server._deathCounts[player.UserId] or 0
	end
	return self.Server:GetDeathCount(player)
end

function DeathTimerService.Client:UseResurrectionPotion(player: Player): boolean
	if not RemoteValidator.rateLimit(player, "DeathTimerService:UseResurrectionPotion", 1.0) then
		return false
	end
	return self.Server:UseResurrectionPotion(player)
end

return DeathTimerService
