--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local HeroData = require(ReplicatedStorage.Shared.HeroData)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig)
local RemoteValidator = require(ReplicatedStorage.Shared.RemoteValidator)

local HeroService = Knit.CreateService({
	Name = "HeroService",

	Client = {
		HeroSelected = Knit.CreateSignal(),
		HeroLevelUp = Knit.CreateSignal(),
	},
})

HeroService._playerHeroes = {} :: { [number]: string } -- UserId -> HeroId
HeroService._playerLevels = {} :: { [number]: number }
HeroService._playerXP = {} :: { [number]: number }
HeroService._heroModels = {} :: { [number]: Model } -- UserId -> visual Model in workspace

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function HeroService:KnitInit()
	Players.PlayerAdded:Connect(function(player)
		local userId = player.UserId
		self._playerHeroes[userId] = nil
		self._playerLevels[userId] = 1
		self._playerXP[userId] = 0
	end)

	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		-- Destroy hero model if present
		local model = self._heroModels[userId]
		if model then
			model:Destroy()
			self._heroModels[userId] = nil
		end
		self._playerHeroes[userId] = nil
		self._playerLevels[userId] = nil
		self._playerXP[userId] = nil
	end)
end

function HeroService:KnitStart() end

--------------------------------------------------------------------------------
-- Server methods (service-to-service)
--------------------------------------------------------------------------------

function HeroService:SelectHero(player: Player, heroId: string): boolean
	if not HeroData[heroId] then
		return false
	end

	local GameService = Knit.GetService("GameService")
	if GameService:GetPhase() ~= Constants.PHASE_HERO_SELECT then
		return false
	end

	local userId = player.UserId
	self._playerHeroes[userId] = heroId
	self._playerLevels[userId] = 1
	self._playerXP[userId] = 0
	self.Client.HeroSelected:FireAll(userId, heroId)

	-- Apply hero appearance to the player's character
	local ok, appearanceService = pcall(function()
		return Knit.GetService("HeroAppearanceService")
	end)
	if ok and appearanceService then
		appearanceService:ApplyHeroAppearance(player, heroId)
	end

	return true
end

function HeroService:AddXP(player: Player, amount: number)
	local userId = player.UserId
	local currentXP = (self._playerXP[userId] or 0) + amount
	local currentLevel = self._playerLevels[userId] or 1
	local didLevelUp = false

	while currentLevel < Constants.HERO_MAX_LEVEL do
		local xpNeeded = Constants.HERO_XP_PER_LEVEL[currentLevel]
		if not xpNeeded or currentXP < xpNeeded then
			break
		end
		currentXP -= xpNeeded
		currentLevel += 1
		didLevelUp = true
		self.Client.HeroLevelUp:Fire(player, currentLevel)
	end

	self._playerXP[userId] = currentXP
	self._playerLevels[userId] = currentLevel

	-- On level-up, recompute stats and re-apply passives
	if didLevelUp then
		local okCombat, heroCombatService = pcall(function()
			return Knit.GetService("HeroCombatService")
		end)
		if okCombat and heroCombatService then
			heroCombatService:RecomputeStats(player)
		end

		local okAbility, abilityService = pcall(function()
			return Knit.GetService("AbilityService")
		end)
		if okAbility and abilityService then
			abilityService:ApplyPassives(player)
		end
	end
end

function HeroService:GetHeroId(player: Player): string?
	return self._playerHeroes[player.UserId]
end

function HeroService:GetLevel(player: Player): number
	return self._playerLevels[player.UserId] or 1
end

--------------------------------------------------------------------------------
-- AssignDefaults: auto-pick heroes for players who did not choose one
--------------------------------------------------------------------------------

function HeroService:AssignDefaults()
	-- Build a flat list of hero ids for random assignment
	local heroIds: { string } = {}
	for id, _ in HeroData do
		table.insert(heroIds, id)
	end

	if #heroIds == 0 then
		warn("[HeroService] No heroes defined in HeroData")
		return
	end

	local ok, appearanceService = pcall(function()
		return Knit.GetService("HeroAppearanceService")
	end)

	for _, player in Players:GetPlayers() do
		local userId = player.UserId
		if self._playerHeroes[userId] == nil then
			local randomIndex = math.random(1, #heroIds)
			local heroId = heroIds[randomIndex]
			self._playerHeroes[userId] = heroId
			self._playerLevels[userId] = 1
			self._playerXP[userId] = 0
			self.Client.HeroSelected:FireAll(userId, heroId)

			-- Apply appearance for auto-assigned heroes
			if ok and appearanceService then
				appearanceService:ApplyHeroAppearance(player, heroId)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- SpawnHeroModels: create visual hero representations on the map
--------------------------------------------------------------------------------

function HeroService:SpawnHeroModels()
	local TeamService = Knit.GetService("TeamService")

	-- Group players by team for index-based offset positioning
	local teamPlayers: { [number]: { Player } } = { [1] = {}, [2] = {} }
	for _, player in Players:GetPlayers() do
		local teamId = TeamService:GetTeam(player)
		if teamId and teamPlayers[teamId] then
			table.insert(teamPlayers[teamId], player)
		end
	end

	for teamId, players in teamPlayers do
		local basePosition = MapConfig.HERO_POSITIONS[teamId]
		if not basePosition then
			continue
		end

		local teamColor = MapConfig.TEAM_COLORS[teamId] or Color3.new(1, 1, 1)

		for playerIndex, player in players do
			local userId = player.UserId
			local heroId = self._playerHeroes[userId]
			if not heroId then
				continue
			end

			local heroDef = HeroData[heroId]
			if not heroDef then
				continue
			end

			-- Destroy any existing model for this player
			if self._heroModels[userId] then
				self._heroModels[userId]:Destroy()
				self._heroModels[userId] = nil
			end

			-- Offset each player along the Z axis so they don't overlap
			local offset = Vector3.new(0, 0, (playerIndex - 1) * 6)
			local position = basePosition + offset

			-- Create the model
			local model = Instance.new("Model")
			model.Name = "Hero_" .. player.Name

			-- Colored body part (4x6x4)
			local part = Instance.new("Part")
			part.Name = "Body"
			part.Size = Vector3.new(4, 6, 4)
			part.Color = teamColor
			part.Material = Enum.Material.SmoothPlastic
			part.Anchored = true
			part.CanCollide = false
			part.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
			part.Parent = model
			model.PrimaryPart = part

			-- BillboardGui with player name + hero name
			local gui = Instance.new("BillboardGui")
			gui.Name = "HeroLabel"
			gui.Size = UDim2.fromOffset(120, 40)
			gui.StudsOffset = Vector3.new(0, 4, 0)
			gui.AlwaysOnTop = true
			gui.Parent = part

			local playerLabel = Instance.new("TextLabel")
			playerLabel.Name = "PlayerName"
			playerLabel.Size = UDim2.new(1, 0, 0.5, 0)
			playerLabel.Position = UDim2.new(0, 0, 0, 0)
			playerLabel.BackgroundTransparency = 1
			playerLabel.Text = player.Name
			playerLabel.TextColor3 = Color3.new(1, 1, 1)
			playerLabel.TextStrokeTransparency = 0.5
			playerLabel.TextScaled = true
			playerLabel.Font = Enum.Font.GothamBold
			playerLabel.Parent = gui

			local heroLabel = Instance.new("TextLabel")
			heroLabel.Name = "HeroName"
			heroLabel.Size = UDim2.new(1, 0, 0.5, 0)
			heroLabel.Position = UDim2.new(0, 0, 0.5, 0)
			heroLabel.BackgroundTransparency = 1
			heroLabel.Text = heroDef.Name
			heroLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
			heroLabel.TextStrokeTransparency = 0.5
			heroLabel.TextScaled = true
			heroLabel.Font = Enum.Font.GothamMedium
			heroLabel.Parent = gui

			model.Parent = workspace

			self._heroModels[userId] = model
		end
	end
end

--------------------------------------------------------------------------------
-- CleanupAll: destroy all hero models and reset all player state
--------------------------------------------------------------------------------

function HeroService:CleanupAll()
	-- Clear hero appearances for all players
	local ok, appearanceService = pcall(function()
		return Knit.GetService("HeroAppearanceService")
	end)
	if ok and appearanceService then
		for _, player in Players:GetPlayers() do
			appearanceService:ClearAppearance(player)
		end
	end

	-- Destroy all hero models
	for userId, model in self._heroModels do
		if model then
			model:Destroy()
		end
		self._heroModels[userId] = nil
	end
	table.clear(self._heroModels)

	-- Reset all player hero state
	for _, player in Players:GetPlayers() do
		local userId = player.UserId
		self._playerHeroes[userId] = nil
		self._playerLevels[userId] = 1
		self._playerXP[userId] = 0
	end
end

--------------------------------------------------------------------------------
-- Client methods (remote-callable)
--------------------------------------------------------------------------------

function HeroService.Client:SelectHero(player: Player, heroId: string): boolean
	if not RemoteValidator.isValidHeroId(heroId) then
		return false
	end
	if not RemoteValidator.rateLimit(player, "HeroService:SelectHero", 1.0) then
		return false
	end
	return self.Server:SelectHero(player, heroId)
end

function HeroService.Client:GetHeroId(player: Player): string?
	if not RemoteValidator.rateLimit(player, "HeroService:GetHeroId", 0.1) then
		return self.Server._playerHeroes[player.UserId]
	end
	return self.Server:GetHeroId(player)
end

function HeroService.Client:GetLevel(player: Player): number
	if not RemoteValidator.rateLimit(player, "HeroService:GetLevel", 0.1) then
		return self.Server._playerLevels[player.UserId] or 1
	end
	return self.Server:GetLevel(player)
end

return HeroService
