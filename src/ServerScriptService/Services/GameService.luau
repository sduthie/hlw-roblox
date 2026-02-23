--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local GamePhases = require(ReplicatedStorage.Shared.GamePhases)
local RemoteValidator = require(ReplicatedStorage.Shared.RemoteValidator)

local GameService = Knit.CreateService({
	Name = "GameService",

	Client = {
		PhaseChanged = Knit.CreateSignal(),
		TimerSync = Knit.CreateSignal(),
		GameOver = Knit.CreateSignal(),
		LivesUpdated = Knit.CreateSignal(),
	},
})

GameService._phase = Constants.PHASE_LOBBY :: string
GameService._timer = 0 :: number
GameService._teamLives = {} :: { [number]: number }
GameService._winningTeam = nil :: number?
GameService._lobbyCountdownActive = false :: boolean
GameService._streaks = {} :: { [number]: number }

-- ---------------------------------------------------------------------------
-- Client methods (remote-callable)
-- ---------------------------------------------------------------------------

function GameService.Client:GetPhase(player: Player): string
	if not RemoteValidator.rateLimit(player, "GetPhase", 0.1) then
		return self.Server._phase
	end
	return self.Server._phase
end

function GameService.Client:GetTeamLives(player: Player): { [number]: number }
	if not RemoteValidator.rateLimit(player, "GetTeamLives", 0.1) then
		return self.Server._teamLives
	end
	return self.Server._teamLives
end

-- ---------------------------------------------------------------------------
-- Server methods (service-to-service)
-- ---------------------------------------------------------------------------

function GameService:GetPhase(): string
	return self._phase
end

function GameService:GetTeamLives(): { [number]: number }
	return self._teamLives
end

function GameService:SetPhase(newPhase: string)
	local oldPhase = self._phase
	if oldPhase == newPhase then
		return
	end

	if not GamePhases.canTransition(oldPhase, newPhase) then
		warn("[HLW] Invalid phase transition:", oldPhase, "->", newPhase)
		return
	end

	self:_exitPhase(oldPhase)
	self._phase = newPhase
	self:_enterPhase(newPhase)

	self.Client.PhaseChanged:FireAll(newPhase, self._timer)
end

function GameService:DamageBase(targetTeamId: number, amount: number, creepTier: number?, attackingTeamId: number?)
	local lives = self._teamLives[targetTeamId]
	if not lives or lives <= 0 then
		return
	end

	if self._phase ~= Constants.PHASE_PLAYING then
		return
	end

	-- Apply streak bonus if an attacking team is provided
	local totalDamage = amount
	if attackingTeamId then
		local bonus = self:GetStreakBonus(attackingTeamId)
		totalDamage = amount + bonus
	end

	self._teamLives[targetTeamId] = math.max(0, lives - totalDamage)

	-- Fire LivesUpdated to all clients
	self.Client.LivesUpdated:FireAll(self._teamLives)

	-- Fire BaseDamaged via BaseService
	local ok, baseService = pcall(function()
		return Knit.GetService("BaseService")
	end)
	if ok and baseService then
		baseService.Client.BaseDamaged:FireAll(targetTeamId, totalDamage)
	end

	-- Check for game over
	if self._teamLives[targetTeamId] <= 0 then
		local winningTeamId = if targetTeamId == 1 then 2 else 1
		self._winningTeam = winningTeamId
		self.Client.GameOver:FireAll(winningTeamId)
		self:SetPhase(Constants.PHASE_GAME_OVER)
	end
end

function GameService:RecordWaveResult(attackingTeamId: number, survivorCount: number): number
	if survivorCount > 0 then
		self._streaks[attackingTeamId] = (self._streaks[attackingTeamId] or 0) + 1
	else
		self._streaks[attackingTeamId] = 0
	end
	return self:GetStreakBonus(attackingTeamId)
end

function GameService:GetStreakBonus(attackingTeamId: number): number
	local streak = self._streaks[attackingTeamId] or 0
	if streak >= Constants.STREAK_THRESHOLD_2 then
		return Constants.STREAK_BONUS_2
	elseif streak >= Constants.STREAK_THRESHOLD_1 then
		return Constants.STREAK_BONUS_1
	end
	return 0
end

-- ---------------------------------------------------------------------------
-- Phase hooks
-- ---------------------------------------------------------------------------

function GameService:_enterPhase(phase: string)
	if phase == Constants.PHASE_LOBBY then
		self._lobbyCountdownActive = false
		self._timer = 0
	elseif phase == Constants.PHASE_HERO_SELECT then
		self._timer = Constants.HERO_PICK_TIME
	elseif phase == Constants.PHASE_PLAYING then
		self:_startGame()
	elseif phase == Constants.PHASE_GAME_OVER then
		self._timer = Constants.GAME_OVER_DISPLAY_TIME
	end
end

function GameService:_exitPhase(phase: string)
	if phase == Constants.PHASE_HERO_SELECT then
		-- Assign default heroes for players who didn't pick
		local ok, heroService = pcall(function()
			return Knit.GetService("HeroService")
		end)
		if ok and heroService and heroService.AssignDefaults then
			heroService:AssignDefaults()
		end
	elseif phase == Constants.PHASE_GAME_OVER then
		-- Record stats via DataService
		self:_recordEndOfGameStats()
		self:_resetGame()
	end
end

-- ---------------------------------------------------------------------------
-- Game lifecycle
-- ---------------------------------------------------------------------------

function GameService:_startGame()
	-- Reset lives to max
	self._teamLives[1] = Constants.BASE_MAX_LIVES
	self._teamLives[2] = Constants.BASE_MAX_LIVES

	-- Reset streaks
	self._streaks[1] = 0
	self._streaks[2] = 0

	-- Reset winning team
	self._winningTeam = nil

	-- Reset timer (no fixed duration for PLAYING)
	self._timer = 0

	-- Notify all clients of fresh lives
	self.Client.LivesUpdated:FireAll(self._teamLives)

	-- Start hero combat
	local okCombat, heroCombatService = pcall(function()
		return Knit.GetService("HeroCombatService")
	end)
	if okCombat and heroCombatService then
		heroCombatService:StartCombat()
	end

	-- Apply passive abilities for all players
	local okAbility, abilityService = pcall(function()
		return Knit.GetService("AbilityService")
	end)
	if okAbility and abilityService then
		for _, player in Players:GetPlayers() do
			abilityService:ApplyPassives(player)
		end
	end
end

function GameService:_resetGame()
	-- 1. Clear all creeps
	local okCreep, creepService = pcall(function()
		return Knit.GetService("CreepService")
	end)
	if okCreep and creepService and creepService.ClearAllCreeps then
		creepService:ClearAllCreeps()
	end

	-- 2. Clean up all heroes
	local okHero, heroService = pcall(function()
		return Knit.GetService("HeroService")
	end)
	if okHero and heroService and heroService.CleanupAll then
		heroService:CleanupAll()
	end

	-- 3. Reset income for each player
	local okIncome, incomeService = pcall(function()
		return Knit.GetService("IncomeService")
	end)
	if okIncome and incomeService and incomeService.ResetPlayer then
		for _, player in Players:GetPlayers() do
			incomeService:ResetPlayer(player)
		end
	end

	-- 4. Stop combat
	local okCombat, heroCombatService = pcall(function()
		return Knit.GetService("HeroCombatService")
	end)
	if okCombat and heroCombatService then
		heroCombatService:StopCombat()
	end

	-- 5. Reset abilities
	local okAbility, abilityService = pcall(function()
		return Knit.GetService("AbilityService")
	end)
	if okAbility and abilityService then
		for _, player in Players:GetPlayers() do
			abilityService:ResetPlayer(player)
		end
	end

	-- 6. Reset shop state
	local okShop, shopService = pcall(function()
		return Knit.GetService("ShopService")
	end)
	if okShop and shopService and shopService.ResetAll then
		shopService:ResetAll()
	end

	-- 5. Reset internal state
	self._teamLives[1] = Constants.BASE_MAX_LIVES
	self._teamLives[2] = Constants.BASE_MAX_LIVES
	self._streaks[1] = 0
	self._streaks[2] = 0
	self._winningTeam = nil
	self._lobbyCountdownActive = false
	self._timer = 0
end

function GameService:_recordEndOfGameStats()
	local okData, dataService = pcall(function()
		return Knit.GetService("DataService")
	end)
	if not okData or not dataService then
		warn("[HLW] DataService not available for end-of-game stats")
		return
	end

	local okTeam, teamService = pcall(function()
		return Knit.GetService("TeamService")
	end)
	if not okTeam or not teamService then
		return
	end

	for _, player in Players:GetPlayers() do
		dataService:IncrementValue(player, "GamesPlayed", 1)

		local teamId = teamService:GetTeam(player)
		if teamId and self._winningTeam then
			if teamId == self._winningTeam then
				dataService:IncrementValue(player, "Wins", 1)
			else
				dataService:IncrementValue(player, "Losses", 1)
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Game loop (timer tick)
-- ---------------------------------------------------------------------------

function GameService:_tickPhase()
	local config = GamePhases.getConfig(self._phase)
	if not config then
		return
	end

	if self._phase == Constants.PHASE_LOBBY then
		-- Lobby countdown logic
		if self._lobbyCountdownActive then
			-- Check if player count dropped below minimum
			local playerCount = #Players:GetPlayers()
			if playerCount < config.MinPlayers then
				self._lobbyCountdownActive = false
				self._timer = 0
				self.Client.TimerSync:FireAll(self._phase, self._timer)
				return
			end

			self._timer -= 1
			if self._timer <= 0 then
				self._lobbyCountdownActive = false
				self:SetPhase(config.NextPhase)
				return
			end
		end
	elseif config.AutoTransition and config.Duration > 0 then
		-- Ticking phases: HERO_SELECT, GAME_OVER
		self._timer -= 1
		if self._timer <= 0 then
			self:SetPhase(config.NextPhase)
			return
		end
	end

	-- Fire timer sync to all clients each tick
	self.Client.TimerSync:FireAll(self._phase, self._timer)
end

-- ---------------------------------------------------------------------------
-- Player connection handlers
-- ---------------------------------------------------------------------------

function GameService:_onPlayerAdded(player: Player)
	-- 1. Assign team via TeamService
	local okTeam, teamService = pcall(function()
		return Knit.GetService("TeamService")
	end)
	if okTeam and teamService then
		teamService:_assignTeam(player)
	end

	-- 2. Fire current phase + timer to the joining player
	self.Client.PhaseChanged:Fire(player, self._phase, self._timer)

	-- 3. Fire current lives to the joining player
	self.Client.LivesUpdated:Fire(player, self._teamLives)

	-- 4. If in lobby and enough players, start countdown
	if self._phase == Constants.PHASE_LOBBY and not self._lobbyCountdownActive then
		local config = GamePhases.getConfig(Constants.PHASE_LOBBY)
		if config then
			local playerCount = #Players:GetPlayers()
			if playerCount >= config.MinPlayers then
				self._lobbyCountdownActive = true
				self._timer = Constants.LOBBY_COUNTDOWN
			end
		end
	end
end

function GameService:_onPlayerRemoving(player: Player)
	-- Clean up rate limiter for this player
	RemoteValidator.clearPlayer(player)

	if self._phase == Constants.PHASE_PLAYING then
		-- Check if a team now has 0 players -> auto-end game
		local okTeam, teamService = pcall(function()
			return Knit.GetService("TeamService")
		end)
		if okTeam and teamService then
			local teamId = teamService:GetTeam(player)
			if teamId then
				-- Count remaining players on that team (excluding the leaving player)
				local teamPlayers = teamService:GetTeamPlayers(teamId)
				local remainingCount = 0
				for _, teamPlayer in teamPlayers do
					if teamPlayer ~= player then
						remainingCount += 1
					end
				end

				if remainingCount == 0 then
					-- Other team wins
					local winningTeamId = if teamId == 1 then 2 else 1
					self._winningTeam = winningTeamId
					self.Client.GameOver:FireAll(winningTeamId)
					self:SetPhase(Constants.PHASE_GAME_OVER)
				end
			end
		end
	elseif self._phase == Constants.PHASE_LOBBY and self._lobbyCountdownActive then
		-- Check if players dropped below minimum
		local config = GamePhases.getConfig(Constants.PHASE_LOBBY)
		if config then
			-- Subtract 1 because the leaving player is still in GetPlayers() during PlayerRemoving
			local playerCount = #Players:GetPlayers() - 1
			if playerCount < config.MinPlayers then
				self._lobbyCountdownActive = false
				self._timer = 0
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function GameService:KnitInit()
	-- Set initial state
	self._phase = Constants.PHASE_LOBBY
	self._timer = 0
	self._teamLives[1] = Constants.BASE_MAX_LIVES
	self._teamLives[2] = Constants.BASE_MAX_LIVES
	self._streaks[1] = 0
	self._streaks[2] = 0
	self._winningTeam = nil
	self._lobbyCountdownActive = false

	-- Connect player events
	Players.PlayerAdded:Connect(function(player)
		self:_onPlayerAdded(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:_onPlayerRemoving(player)
	end)
end

function GameService:KnitStart()
	-- Launch game loop
	task.spawn(function()
		while true do
			task.wait(1)
			self:_tickPhase()
		end
	end)
end

return GameService
