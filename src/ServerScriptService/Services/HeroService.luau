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
		SkillPointsChanged = Knit.CreateSignal(),
		AbilityLeveledUp = Knit.CreateSignal(),
	},
})

HeroService._playerHeroes = {} :: { [number]: string } -- UserId -> HeroId
HeroService._playerLevels = {} :: { [number]: number }
HeroService._playerXP = {} :: { [number]: number }
HeroService._heroModels = {} :: { [number]: Model } -- UserId -> visual Model in workspace

-- Skill point system
HeroService._skillPoints = {} :: { [number]: number } -- UserId -> unspent points
HeroService._abilityLevels = {} :: { [number]: { number } } -- UserId -> {slot1, slot2, slot3, slot4}
HeroService._attributeBonusLevels = {} :: { [number]: number } -- UserId -> attribute bonus level

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function HeroService:KnitInit()
	Players.PlayerAdded:Connect(function(player)
		local userId = player.UserId
		self._playerHeroes[userId] = nil
		self._playerLevels[userId] = 1
		self._playerXP[userId] = 0
		self._skillPoints[userId] = 1 -- start with 1 point at level 1
		self._abilityLevels[userId] = { 0, 0, 0, 0 }
		self._attributeBonusLevels[userId] = 0
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
		self._skillPoints[userId] = nil
		self._abilityLevels[userId] = nil
		self._attributeBonusLevels[userId] = nil
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
	self._skillPoints[userId] = 1
	self._abilityLevels[userId] = { 0, 0, 0, 0 }
	self._attributeBonusLevels[userId] = 0
	self.Client.HeroSelected:FireAll(userId, heroId)
	self.Client.SkillPointsChanged:Fire(player, self._skillPoints[userId])

	-- Tag the character with HeroId for client-side detection (ranged VFX, etc.)
	if player.Character then
		player.Character:SetAttribute("HeroId", heroId)
	end

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

		-- Award 1 skill point per level
		self._skillPoints[userId] = (self._skillPoints[userId] or 0) + 1

		self.Client.HeroLevelUp:Fire(player, currentLevel)
		self.Client.SkillPointsChanged:Fire(player, self._skillPoints[userId])
	end

	self._playerXP[userId] = currentXP
	self._playerLevels[userId] = currentLevel

	-- On level-up, recompute stats, re-apply passives, update overhead
	if didLevelUp then
		local okCombat, heroCombatService = pcall(function()
			return Knit.GetService("HeroCombatService")
		end)
		if okCombat and heroCombatService then
			heroCombatService:RecomputeStats(player)
			heroCombatService:UpdateOverheadLevel(player, currentLevel)
		end

		local okAbility, abilityService = pcall(function()
			return Knit.GetService("AbilityService")
		end)
		if okAbility and abilityService then
			abilityService:ApplyPassives(player)
		end
	end
end

--------------------------------------------------------------------------------
-- Skill Point System
--------------------------------------------------------------------------------

function HeroService:LevelUpAbility(player: Player, slotIndex: number): boolean
	local userId = player.UserId
	local heroId = self._playerHeroes[userId]
	if not heroId then
		return false
	end

	-- Must have skill points
	local points = self._skillPoints[userId] or 0
	if points <= 0 then
		return false
	end

	local heroLevel = self._playerLevels[userId] or 1

	-- Slot 5 = Attribute Bonus (special)
	if slotIndex == 5 then
		self._attributeBonusLevels[userId] = (self._attributeBonusLevels[userId] or 0) + 1
		self._skillPoints[userId] = points - 1

		-- Recompute stats with attribute bonus
		local okCombat, heroCombatService = pcall(function()
			return Knit.GetService("HeroCombatService")
		end)
		if okCombat and heroCombatService then
			heroCombatService:RecomputeStats(player)
		end

		self.Client.AbilityLeveledUp:Fire(player, slotIndex, self._attributeBonusLevels[userId])
		self.Client.SkillPointsChanged:Fire(player, self._skillPoints[userId])
		return true
	end

	-- Slots 1-4: regular abilities
	if slotIndex < 1 or slotIndex > 4 then
		return false
	end

	local heroDef = HeroData[heroId]
	if not heroDef then
		return false
	end

	local abilityDef = heroDef.Abilities[slotIndex]
	if not abilityDef then
		return false
	end

	local maxLevel = abilityDef.MaxLevel or 5
	local requiredHeroLevel = abilityDef.RequiredHeroLevel or 1
	local levels = self._abilityLevels[userId]
	if not levels then
		return false
	end

	local currentAbilityLevel = levels[slotIndex] or 0

	-- Check max level
	if currentAbilityLevel >= maxLevel then
		return false
	end

	-- Check hero level requirement
	if heroLevel < requiredHeroLevel then
		return false
	end

	-- Level up the ability
	levels[slotIndex] = currentAbilityLevel + 1
	self._skillPoints[userId] = points - 1

	-- Recompute stats and re-apply passives
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

	self.Client.AbilityLeveledUp:Fire(player, slotIndex, levels[slotIndex])
	self.Client.SkillPointsChanged:Fire(player, self._skillPoints[userId])
	return true
end

function HeroService:GetAbilityLevel(player: Player, slotIndex: number): number
	local userId = player.UserId
	if slotIndex == 5 then
		return self._attributeBonusLevels[userId] or 0
	end
	local levels = self._abilityLevels[userId]
	if not levels then
		return 0
	end
	return levels[slotIndex] or 0
end

function HeroService:GetAllAbilityLevels(player: Player): { number }
	local userId = player.UserId
	local levels = self._abilityLevels[userId] or { 0, 0, 0, 0 }
	return { levels[1], levels[2], levels[3], levels[4], self._attributeBonusLevels[userId] or 0 }
end

function HeroService:GetSkillPoints(player: Player): number
	return self._skillPoints[player.UserId] or 0
end

function HeroService:GetAttributeBonusLevel(player: Player): number
	return self._attributeBonusLevels[player.UserId] or 0
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
			self._skillPoints[userId] = 1
			self._abilityLevels[userId] = { 0, 0, 0, 0 }
			self._attributeBonusLevels[userId] = 0
			self.Client.HeroSelected:FireAll(userId, heroId)

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

			if self._heroModels[userId] then
				self._heroModels[userId]:Destroy()
				self._heroModels[userId] = nil
			end

			local offset = Vector3.new(0, 0, (playerIndex - 1) * 6)
			local position = basePosition + offset

			local model = Instance.new("Model")
			model.Name = "Hero_" .. player.Name

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
	local ok, appearanceService = pcall(function()
		return Knit.GetService("HeroAppearanceService")
	end)
	if ok and appearanceService then
		for _, player in Players:GetPlayers() do
			appearanceService:ClearAppearance(player)
		end
	end

	for userId, model in self._heroModels do
		if model then
			model:Destroy()
		end
		self._heroModels[userId] = nil
	end
	table.clear(self._heroModels)

	for _, player in Players:GetPlayers() do
		local userId = player.UserId
		self._playerHeroes[userId] = nil
		self._playerLevels[userId] = 1
		self._playerXP[userId] = 0
		self._skillPoints[userId] = 1
		self._abilityLevels[userId] = { 0, 0, 0, 0 }
		self._attributeBonusLevels[userId] = 0
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
	return self.Server._playerHeroes[player.UserId]
end

function HeroService.Client:GetLevel(player: Player): number
	return self.Server._playerLevels[player.UserId] or 1
end

function HeroService.Client:LevelUpAbility(player: Player, slotIndex: number): boolean
	if type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > 5 then
		return false
	end
	if not RemoteValidator.rateLimit(player, "LevelUpAbility", 0.3) then
		return false
	end
	return self.Server:LevelUpAbility(player, slotIndex)
end

function HeroService.Client:GetSkillPoints(player: Player): number
	return self.Server:GetSkillPoints(player)
end

function HeroService.Client:GetAllAbilityLevels(player: Player): { number }
	return self.Server:GetAllAbilityLevels(player)
end

return HeroService
