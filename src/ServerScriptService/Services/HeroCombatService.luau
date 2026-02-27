--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local HeroData = require(ReplicatedStorage.Shared.HeroData)
local HeroStats = require(ReplicatedStorage.Shared.HeroStats)
local AbilityHelper = require(ReplicatedStorage.Shared.AbilityHelper)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig)

--------------------------------------------------------------------------------
-- Service
--------------------------------------------------------------------------------

local HeroCombatService = Knit.CreateService({
	Name = "HeroCombatService",

	Client = {
		HeroAttacked = Knit.CreateSignal(),
		CombatStateChanged = Knit.CreateSignal(),
		ManaChanged = Knit.CreateSignal(),
		HeroHealthChanged = Knit.CreateSignal(),
	},
})

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

-- Armor reduction formula: reduction% = armor / (armor + ARMOR_CONSTANT), capped at 75%
local ARMOR_CONSTANT = 30
local ARMOR_CAP = 0.75

-- Shield regen delay: seconds of no damage before shield starts regenerating
local SHIELD_REGEN_DELAY = 5
local SHIELD_REGEN_RATE = 10 -- shield points per second

type CombatState = {
	MaxHealth: number,
	Health: number,
	Mana: number,
	MaxMana: number,
	Shield: number,
	MaxShield: number,
	AttackDamage: number,
	Armor: number,
	MoveSpeed: number,
	CooldownReduction: number,
	AttackRange: number,
	AttackCooldown: number,
	LastAttackTime: number,
	LastDamagedTime: number,
	Buffs: { BuffEntry },
	Invulnerable: boolean,
	WindWalkActive: boolean,
	WindWalkBonusDamage: number,
}

type BuffEntry = {
	Name: string,
	StatKey: string,
	Value: number,
	ExpiresAt: number,
}

HeroCombatService._combatState = {} :: { [number]: CombatState } -- UserId -> state
HeroCombatService._combatActive = false :: boolean
HeroCombatService._attackTargets = {} :: { [number]: number } -- UserId -> targeted creep Id (0 = none)
HeroCombatService._overheadGuis = {} :: { [number]: BillboardGui } -- UserId -> overhead BillboardGui

--------------------------------------------------------------------------------
-- Public methods (service-to-service)
--------------------------------------------------------------------------------

function HeroCombatService:StartCombat()
	self._combatActive = true

	for _, player in Players:GetPlayers() do
		self:_initPlayerState(player)
		-- If init failed (no hero yet), retry after a short delay
		if not self._combatState[player.UserId] then
			task.delay(1, function()
				if self._combatActive and not self._combatState[player.UserId] then
					self:_initPlayerState(player)
				end
			end)
		end
	end

	-- Re-create overhead UI on respawn
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function()
			task.wait(0.5) -- Wait for Head to replicate
			if self._combatActive then
				local state = self._combatState[player.UserId]
				if state then
					self:_createOverheadUI(player, state)
					local HeroService = Knit.GetService("HeroService")
					self:UpdateOverheadLevel(player, HeroService:GetLevel(player))
				end
			end
		end)
	end

	task.spawn(function()
		self:_runCombatLoop()
	end)
end

function HeroCombatService:StopCombat()
	self._combatActive = false
	table.clear(self._combatState)
	table.clear(self._attackTargets)
end

function HeroCombatService:RecomputeStats(player: Player)
	local userId = player.UserId
	local state = self._combatState[userId]
	if not state then
		return
	end

	local HeroService = Knit.GetService("HeroService")
	local heroId = HeroService:GetHeroId(player)
	if not heroId then
		return
	end

	local level = HeroService:GetLevel(player)

	-- Get player items
	local items = {}
	local ok, shopService = pcall(function()
		return Knit.GetService("ShopService")
	end)
	if ok and shopService and shopService.GetPlayerItems then
		items = shopService:GetPlayerItems(player) or {}
	end

	local stats = HeroStats.compute(heroId, level, items)

	-- Apply upgrade bonuses
	local bonusDamage = 0
	local bonusArmor = 0
	local attackSpeedPct = 0
	local bonusMana = 0
	local okUpgrade, upgradeService = pcall(function()
		return Knit.GetService("UpgradeService")
	end)
	if okUpgrade and upgradeService then
		bonusDamage = upgradeService:GetHeroBonusDamage(player)
		bonusArmor = upgradeService:GetHeroBonusArmor(player)
		attackSpeedPct = upgradeService:GetHeroAttackSpeedPct(player)
		bonusMana = upgradeService:GetHeroBonusMana(player)
	end

	-- Attribute Bonus from skill points
	local attrLevel = HeroService:GetAttributeBonusLevel(player)
	if attrLevel > 0 then
		bonusDamage += attrLevel * Constants.ATTRIBUTE_BONUS_DAMAGE
		bonusArmor += attrLevel * Constants.ATTRIBUTE_BONUS_ARMOR
		stats.MaxHealth += attrLevel * Constants.ATTRIBUTE_BONUS_HP
	end

	-- Proportionally scale health
	local healthPct = state.Health / state.MaxHealth
	state.MaxHealth = stats.MaxHealth
	state.Health = math.floor(stats.MaxHealth * healthPct)

	-- Scale mana similarly
	local manaPct = state.Mana / state.MaxMana
	state.MaxMana = stats.MaxMana + bonusMana
	state.Mana = math.floor(state.MaxMana * manaPct)

	state.AttackDamage = stats.AttackDamage + bonusDamage
	state.Armor = stats.Armor + bonusArmor
	state.MoveSpeed = stats.MoveSpeed
	state.CooldownReduction = stats.CooldownReduction
	state.AttackCooldown = Constants.HERO_ATTACK_RATE * (1 - attackSpeedPct / 100)

	-- Recalculate shield max from items
	local newMaxShield = 0
	for _, item in items do
		if item.Stats and item.Stats.Shield then
			newMaxShield += item.Stats.Shield
		end
	end
	if newMaxShield ~= state.MaxShield then
		local shieldPct = if state.MaxShield > 0 then state.Shield / state.MaxShield else 1
		state.MaxShield = newMaxShield
		state.Shield = math.floor(newMaxShield * shieldPct)
	end

	-- Update humanoid if present
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.MaxHealth = state.MaxHealth
			humanoid.Health = state.Health
		end
	end

	self.Client.CombatStateChanged:Fire(player, {
		MaxHealth = state.MaxHealth,
		Health = state.Health,
		MaxMana = state.MaxMana,
		Mana = state.Mana,
		Shield = state.Shield,
		MaxShield = state.MaxShield,
		AttackDamage = state.AttackDamage,
		Armor = state.Armor,
		MoveSpeed = state.MoveSpeed,
		AttackRange = state.AttackRange,
		AttackCooldown = state.AttackCooldown,
		ManaRegen = self:GetEffectiveStat(player, "ManaRegen"),
		Buffs = state.Buffs,
	})

	self:_updateOverheadHealth(player)
	self:_updateOverheadMana(player)
end

function HeroCombatService:GetMana(player: Player): number
	local state = self._combatState[player.UserId]
	return if state then state.Mana else 0
end

function HeroCombatService:SpendMana(player: Player, amount: number): boolean
	local state = self._combatState[player.UserId]
	if not state then
		return false
	end
	if state.Mana < amount then
		return false
	end
	state.Mana -= amount
	self.Client.ManaChanged:Fire(player, state.Mana, state.MaxMana)
	self:_updateOverheadMana(player)
	return true
end

function HeroCombatService:GetHealth(player: Player): number
	local state = self._combatState[player.UserId]
	return if state then state.Health else 0
end

function HeroCombatService:HealHero(player: Player, amount: number)
	local state = self._combatState[player.UserId]
	if not state then
		return
	end
	state.Health = math.min(state.Health + amount, state.MaxHealth)

	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = state.Health
		end
	end

	self.Client.HeroHealthChanged:Fire(player, state.Health, state.MaxHealth)
	self:_updateOverheadHealth(player)
end

function HeroCombatService:DamageHero(player: Player, amount: number)
	local state = self._combatState[player.UserId]
	if not state or state.Invulnerable then
		return
	end

	-- Apply armor reduction (diminishing returns, capped at 75%)
	local armor = self:GetEffectiveStat(player, "Armor")
	local reduction = math.min(armor / (armor + ARMOR_CONSTANT), ARMOR_CAP)
	local mitigated = amount * (1 - reduction)

	-- Track last damage time for shield regen
	state.LastDamagedTime = os.clock()

	-- Shield absorbs damage first
	if state.Shield > 0 then
		if state.Shield >= mitigated then
			state.Shield -= mitigated
			mitigated = 0
		else
			mitigated -= state.Shield
			state.Shield = 0
		end
	end

	-- Remaining damage hits health
	state.Health = math.max(0, state.Health - mitigated)

	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = state.Health
		end
	end

	self.Client.HeroHealthChanged:Fire(player, state.Health, state.MaxHealth)
	self:_updateOverheadHealth(player)
end

function HeroCombatService:ApplyBuff(player: Player, name: string, statKey: string, value: number, duration: number)
	local state = self._combatState[player.UserId]
	if not state then
		return
	end

	table.insert(state.Buffs, {
		Name = name,
		StatKey = statKey,
		Value = value,
		ExpiresAt = os.clock() + duration,
	})
end

function HeroCombatService:SetInvulnerable(player: Player, invuln: boolean)
	local state = self._combatState[player.UserId]
	if state then
		state.Invulnerable = invuln
	end
end

function HeroCombatService:SetWindWalk(player: Player, active: boolean, bonusDamageMultiplier: number?)
	local state = self._combatState[player.UserId]
	if state then
		state.WindWalkActive = active
		state.WindWalkBonusDamage = if active then (bonusDamageMultiplier or 2) else 0

		-- Apply transparency to character
		local character = player.Character
		if character then
			for _, part in character:GetDescendants() do
				if part:IsA("BasePart") then
					part.Transparency = if active then 0.6 else 0
				end
			end
		end
	end
end

function HeroCombatService:GetEffectiveStat(player: Player, statKey: string): number
	local state = self._combatState[player.UserId]
	if not state then
		return 0
	end

	local base = 0
	if statKey == "AttackDamage" then
		base = state.AttackDamage
	elseif statKey == "Armor" then
		base = state.Armor
	elseif statKey == "MoveSpeed" then
		base = state.MoveSpeed
	elseif statKey == "MaxHealth" then
		base = state.MaxHealth
	elseif statKey == "ManaRegen" then
		base = Constants.MANA_REGEN
		local okUpgrade, upgradeService = pcall(function()
			return Knit.GetService("UpgradeService")
		end)
		if okUpgrade and upgradeService then
			base += upgradeService:GetHeroBonusManaRegen(player)
		end
	end

	-- Add active buffs
	local now = os.clock()
	for _, buff in state.Buffs do
		if buff.ExpiresAt > now and buff.StatKey == statKey then
			base += buff.Value
		end
	end

	return base
end

function HeroCombatService:GetCombatState(player: Player): CombatState?
	return self._combatState[player.UserId]
end

--------------------------------------------------------------------------------
-- Overhead UI (HP / Mana / Level above hero head)
--------------------------------------------------------------------------------

function HeroCombatService:_createOverheadUI(player: Player, state: CombatState)
	local character = player.Character
	if not character then
		return
	end
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end

	-- Hide default Roblox health bar
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end

	-- Remove old GUI if exists
	local old = head:FindFirstChild("HeroOverhead")
	if old then
		old:Destroy()
	end

	-- Get team color
	local teamColor = Color3.new(1, 1, 1)
	local okTeam, teamService = pcall(function()
		return Knit.GetService("TeamService")
	end)
	if okTeam and teamService then
		local teamId = teamService:GetTeam(player)
		if teamId then
			teamColor = MapConfig.TEAM_COLORS[teamId] or teamColor
		end
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "HeroOverhead"
	gui.Size = UDim2.fromOffset(130, 44)
	gui.StudsOffset = Vector3.new(0, 2.2, 0)
	gui.AlwaysOnTop = true
	gui.Parent = head

	-- Row 1: Level badge + Player name
	local levelBadge = Instance.new("TextLabel")
	levelBadge.Name = "Level"
	levelBadge.Size = UDim2.fromOffset(22, 14)
	levelBadge.Position = UDim2.fromOffset(0, 0)
	levelBadge.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	levelBadge.BackgroundTransparency = 0.2
	levelBadge.BorderSizePixel = 0
	levelBadge.Text = "1"
	levelBadge.Font = Enum.Font.GothamBold
	levelBadge.TextSize = 10
	levelBadge.TextColor3 = Color3.fromRGB(255, 215, 80)
	levelBadge.ZIndex = 2
	levelBadge.Parent = gui

	local lvlCorner = Instance.new("UICorner")
	lvlCorner.CornerRadius = UDim.new(0, 3)
	lvlCorner.Parent = levelBadge

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "PlayerName"
	nameLabel.Size = UDim2.new(1, -24, 0, 14)
	nameLabel.Position = UDim2.fromOffset(24, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = player.DisplayName
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 11
	nameLabel.TextColor3 = teamColor
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextStrokeTransparency = 0.5
	nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	nameLabel.Parent = gui

	-- Row 2: HP bar
	local hpBg = Instance.new("Frame")
	hpBg.Name = "HPBackground"
	hpBg.Size = UDim2.new(1, 0, 0, 12)
	hpBg.Position = UDim2.fromOffset(0, 16)
	hpBg.BackgroundColor3 = Color3.fromRGB(30, 0, 0)
	hpBg.BorderSizePixel = 0
	hpBg.Parent = gui

	local hpCorner = Instance.new("UICorner")
	hpCorner.CornerRadius = UDim.new(0, 2)
	hpCorner.Parent = hpBg

	local hpFill = Instance.new("Frame")
	hpFill.Name = "HPFill"
	hpFill.Size = UDim2.new(1, 0, 1, 0)
	hpFill.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
	hpFill.BorderSizePixel = 0
	hpFill.Parent = hpBg

	local hpFillCorner = Instance.new("UICorner")
	hpFillCorner.CornerRadius = UDim.new(0, 2)
	hpFillCorner.Parent = hpFill

	local hpText = Instance.new("TextLabel")
	hpText.Name = "HPText"
	hpText.Size = UDim2.new(1, 0, 1, 0)
	hpText.BackgroundTransparency = 1
	hpText.Text = tostring(math.floor(state.Health)) .. "/" .. tostring(math.floor(state.MaxHealth))
	hpText.Font = Enum.Font.GothamBold
	hpText.TextSize = 8
	hpText.TextColor3 = Color3.new(1, 1, 1)
	hpText.TextStrokeTransparency = 0.3
	hpText.TextStrokeColor3 = Color3.new(0, 0, 0)
	hpText.ZIndex = 2
	hpText.Parent = hpBg

	-- Row 3: Mana bar
	local manaBg = Instance.new("Frame")
	manaBg.Name = "ManaBackground"
	manaBg.Size = UDim2.new(1, 0, 0, 7)
	manaBg.Position = UDim2.fromOffset(0, 30)
	manaBg.BackgroundColor3 = Color3.fromRGB(0, 0, 30)
	manaBg.BorderSizePixel = 0
	manaBg.Parent = gui

	local manaCorner = Instance.new("UICorner")
	manaCorner.CornerRadius = UDim.new(0, 2)
	manaCorner.Parent = manaBg

	local manaFill = Instance.new("Frame")
	manaFill.Name = "ManaFill"
	manaFill.Size = UDim2.new(1, 0, 1, 0)
	manaFill.BackgroundColor3 = Color3.fromRGB(50, 100, 255)
	manaFill.BorderSizePixel = 0
	manaFill.Parent = manaBg

	local manaFillCorner = Instance.new("UICorner")
	manaFillCorner.CornerRadius = UDim.new(0, 2)
	manaFillCorner.Parent = manaFill

	self._overheadGuis[player.UserId] = gui
end

function HeroCombatService:_updateOverheadHealth(player: Player)
	local state = self._combatState[player.UserId]
	local gui = self._overheadGuis[player.UserId]
	if not state or not gui or not gui.Parent then
		return
	end

	local hpBg = gui:FindFirstChild("HPBackground") :: Frame?
	if not hpBg then
		return
	end
	local hpFill = hpBg:FindFirstChild("HPFill") :: Frame?
	local hpText = hpBg:FindFirstChild("HPText") :: TextLabel?

	local pct = math.clamp(state.Health / state.MaxHealth, 0, 1)

	if hpFill then
		hpFill.Size = UDim2.new(pct, 0, 1, 0)
		if pct > 0.5 then
			hpFill.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
		elseif pct > 0.25 then
			hpFill.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
		else
			hpFill.BackgroundColor3 = Color3.fromRGB(255, 50, 0)
		end
	end

	if hpText then
		hpText.Text = tostring(math.floor(state.Health)) .. "/" .. tostring(math.floor(state.MaxHealth))
	end
end

function HeroCombatService:_updateOverheadMana(player: Player)
	local state = self._combatState[player.UserId]
	local gui = self._overheadGuis[player.UserId]
	if not state or not gui or not gui.Parent then
		return
	end

	local manaBg = gui:FindFirstChild("ManaBackground") :: Frame?
	if not manaBg then
		return
	end
	local manaFill = manaBg:FindFirstChild("ManaFill") :: Frame?

	if manaFill then
		local pct = math.clamp(state.Mana / state.MaxMana, 0, 1)
		manaFill.Size = UDim2.new(pct, 0, 1, 0)
	end
end

function HeroCombatService:UpdateOverheadLevel(player: Player, level: number)
	local gui = self._overheadGuis[player.UserId]
	if not gui or not gui.Parent then
		return
	end

	local levelBadge = gui:FindFirstChild("Level") :: TextLabel?
	if levelBadge then
		levelBadge.Text = tostring(level)
	end
end

--------------------------------------------------------------------------------
-- Init player combat state
--------------------------------------------------------------------------------

function HeroCombatService:_initPlayerState(player: Player)
	local HeroService = Knit.GetService("HeroService")
	local heroId = HeroService:GetHeroId(player)
	if not heroId then
		return
	end

	local level = HeroService:GetLevel(player)
	local items = {}
	local ok, shopService = pcall(function()
		return Knit.GetService("ShopService")
	end)
	if ok and shopService and shopService.GetPlayerItems then
		items = shopService:GetPlayerItems(player) or {}
	end

	local stats = HeroStats.compute(heroId, level, items)

	-- Apply upgrade bonuses
	local bonusDamage = 0
	local bonusArmor = 0
	local attackSpeedPct = 0
	local bonusMana = 0
	local okUpgrade, upgradeService = pcall(function()
		return Knit.GetService("UpgradeService")
	end)
	if okUpgrade and upgradeService then
		bonusDamage = upgradeService:GetHeroBonusDamage(player)
		bonusArmor = upgradeService:GetHeroBonusArmor(player)
		attackSpeedPct = upgradeService:GetHeroAttackSpeedPct(player)
		bonusMana = upgradeService:GetHeroBonusMana(player)
	end

	-- Attribute Bonus from skill points
	local attrLevel = HeroService:GetAttributeBonusLevel(player)
	if attrLevel > 0 then
		bonusDamage += attrLevel * Constants.ATTRIBUTE_BONUS_DAMAGE
		bonusArmor += attrLevel * Constants.ATTRIBUTE_BONUS_ARMOR
		stats.MaxHealth += attrLevel * Constants.ATTRIBUTE_BONUS_HP
	end

	-- Compute shield from items (items may have a Shield stat)
	local maxShield = 0
	for _, item in items do
		if item.Stats and item.Stats.Shield then
			maxShield += item.Stats.Shield
		end
	end

	local state: CombatState = {
		MaxHealth = stats.MaxHealth,
		Health = stats.MaxHealth,
		Mana = stats.MaxMana + bonusMana,
		MaxMana = stats.MaxMana + bonusMana,
		Shield = maxShield,
		MaxShield = maxShield,
		AttackDamage = stats.AttackDamage + bonusDamage,
		Armor = stats.Armor + bonusArmor,
		MoveSpeed = stats.MoveSpeed,
		CooldownReduction = stats.CooldownReduction,
		AttackRange = if HeroData[heroId] and HeroData[heroId].AttackRange then HeroData[heroId].AttackRange else Constants.HERO_ATTACK_RANGE,
		AttackCooldown = Constants.HERO_ATTACK_RATE * (1 - attackSpeedPct / 100),
		LastAttackTime = 0,
		LastDamagedTime = 0,
		Buffs = {},
		Invulnerable = false,
		WindWalkActive = false,
		WindWalkBonusDamage = 0,
	}

	self._combatState[player.UserId] = state

	-- Set humanoid health
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.MaxHealth = state.MaxHealth
			humanoid.Health = state.MaxHealth
		end
	end

	self.Client.HeroHealthChanged:Fire(player, state.Health, state.MaxHealth)
	self.Client.ManaChanged:Fire(player, state.Mana, state.MaxMana)

	-- Create overhead UI (HP/Mana/Level above head)
	self:_createOverheadUI(player, state)

	-- Set initial level
	local heroLevel = HeroService:GetLevel(player)
	self:UpdateOverheadLevel(player, heroLevel)

	-- Fire initial combat state so client stats panel appears immediately
	self.Client.CombatStateChanged:Fire(player, {
		MaxHealth = state.MaxHealth,
		Health = state.Health,
		MaxMana = state.MaxMana,
		Mana = state.Mana,
		Shield = state.Shield,
		MaxShield = state.MaxShield,
		AttackDamage = state.AttackDamage,
		Armor = state.Armor,
		MoveSpeed = state.MoveSpeed,
		AttackRange = state.AttackRange,
		AttackCooldown = state.AttackCooldown,
		ManaRegen = self:GetEffectiveStat(player, "ManaRegen"),
		Buffs = state.Buffs,
	})
end

--------------------------------------------------------------------------------
-- Combat loop (10 Hz)
--------------------------------------------------------------------------------

function HeroCombatService:_runCombatLoop()
	local dt = 1 / Constants.HERO_COMBAT_UPDATE_RATE

	while self._combatActive do
		task.wait(dt)

		if not self._combatActive then
			break
		end

		local now = os.clock()

		for _, player in Players:GetPlayers() do
			local userId = player.UserId
			local state = self._combatState[userId]
			if not state then
				continue
			end

			-- Mana regen
			local manaRegen = self:GetEffectiveStat(player, "ManaRegen")
			if state.Mana < state.MaxMana then
				state.Mana = math.min(state.MaxMana, state.Mana + manaRegen * dt)
				-- Only fire signal every ~1 second to avoid spam
				if math.floor(now) ~= math.floor(now - dt) then
					self.Client.ManaChanged:Fire(player, state.Mana, state.MaxMana)
					self:_updateOverheadMana(player)
				end
			end

			-- Shield regen (after no damage taken for SHIELD_REGEN_DELAY seconds)
			if state.MaxShield > 0 and state.Shield < state.MaxShield then
				local timeSinceDamage = now - (state.LastDamagedTime or 0)
				if timeSinceDamage >= SHIELD_REGEN_DELAY then
					state.Shield = math.min(state.MaxShield, state.Shield + SHIELD_REGEN_RATE * dt)
				end
			end

			-- Expire buffs
			for i = #state.Buffs, 1, -1 do
				if state.Buffs[i].ExpiresAt <= now then
					table.remove(state.Buffs, i)
				end
			end

			-- Get hero position
			local character = player.Character
			if not character then
				continue
			end
			local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not rootPart then
				continue
			end
			local heroPos = rootPart.Position

			-- Get team
			local okTeam, teamService = pcall(function()
				return Knit.GetService("TeamService")
			end)
			if not okTeam then
				continue
			end
			local heroTeamId = teamService:GetTeam(player)
			if not heroTeamId then
				continue
			end

			-- Healing well: passively heal HP and mana near team's well
			local wellPos = MapConfig.HEALING_WELL_POSITIONS[heroTeamId]
			if wellPos then
				local distToWell = (heroPos - wellPos).Magnitude
				if distToWell <= MapConfig.HEALING_WELL_RADIUS then
					if state.Health < state.MaxHealth then
						self:HealHero(player, MapConfig.HEALING_WELL_HPS * dt)
					end
					if state.Mana < state.MaxMana then
						state.Mana = math.min(state.MaxMana, state.Mana + MapConfig.HEALING_WELL_MPS * dt)
					end
				end
			end

			-- Check attack cooldown
			if now - state.LastAttackTime < state.AttackCooldown then
				continue
			end

			-- Find attack target: use player's selected target if valid, otherwise idle
			local CreepService = Knit.GetService("CreepService")
			local targetCreepId = self._attackTargets[userId] or 0
			local nearestCreep = nil

			if targetCreepId > 0 then
				local activeCreeps = CreepService:GetActiveCreeps()
				local targetCreep = activeCreeps[targetCreepId]
				if targetCreep and targetCreep.TeamId ~= heroTeamId then
					local dist = (targetCreep.Position - heroPos).Magnitude
					if dist <= state.AttackRange then
						nearestCreep = targetCreep
					end
				else
					-- Target is dead or invalid — clear it
					self._attackTargets[userId] = 0
				end
			end

			if not nearestCreep then
				continue
			end

			-- Attack!
			state.LastAttackTime = now
			-- Roll damage within ±DAMAGE_VARIANCE range
			local variance = Constants.DAMAGE_VARIANCE
			local damage = state.AttackDamage * (1 - variance + math.random() * variance * 2)

			-- Check Blademaster crit passive (uses ability level, not hero level)
			local HeroService = Knit.GetService("HeroService")
			local heroId = HeroService:GetHeroId(player)
			if heroId == "Blademaster" then
				local heroDef = HeroData[heroId]
				if heroDef then
					for slotIdx, ability in heroDef.Abilities do
						if ability.Name == "Critical Strike" and ability.IsPassive then
							local critLevel = HeroService:GetAbilityLevel(player, slotIdx)
							if critLevel > 0 then
								local critChance = AbilityHelper.getVal(ability, "Value", critLevel) / 100
								if math.random() < critChance then
									damage *= 2
								end
							end
							break
						end
					end
				end
			end

			-- Wind Walk bonus
			if state.WindWalkActive then
				damage *= state.WindWalkBonusDamage
				self:SetWindWalk(player, false)
			end

			-- Apply damage to creep (kill rewards handled by CreepService)
			local killed = CreepService:DamageCreep(nearestCreep.Id, damage, player)

			-- Fire signal for client floating damage + attack visual
			self.Client.HeroAttacked:FireAll(userId, nearestCreep.Id, damage, nearestCreep.Position, killed)

			-- Clear target if killed
			if killed then
				self._attackTargets[userId] = 0
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Attack targeting
--------------------------------------------------------------------------------

function HeroCombatService:SetAttackTarget(player: Player, creepId: number)
	self._attackTargets[player.UserId] = creepId
end

function HeroCombatService.Client:SetTarget(player: Player, creepId: number)
	if type(creepId) ~= "number" then
		return
	end
	self.Server:SetAttackTarget(player, creepId)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function HeroCombatService:KnitInit() end

function HeroCombatService:KnitStart() end

return HeroCombatService
