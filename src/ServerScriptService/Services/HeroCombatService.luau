--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local HeroData = require(ReplicatedStorage.Shared.HeroData)
local HeroStats = require(ReplicatedStorage.Shared.HeroStats)

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

type CombatState = {
	MaxHealth: number,
	Health: number,
	Mana: number,
	MaxMana: number,
	AttackDamage: number,
	Armor: number,
	MoveSpeed: number,
	CooldownReduction: number,
	AttackRange: number,
	AttackCooldown: number,
	LastAttackTime: number,
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

--------------------------------------------------------------------------------
-- Public methods (service-to-service)
--------------------------------------------------------------------------------

function HeroCombatService:StartCombat()
	self._combatActive = true

	for _, player in Players:GetPlayers() do
		self:_initPlayerState(player)
	end

	task.spawn(function()
		self:_runCombatLoop()
	end)
end

function HeroCombatService:StopCombat()
	self._combatActive = false
	table.clear(self._combatState)
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
	if ok and shopService and shopService.GetItems then
		items = shopService:GetItems(player) or {}
	end

	local stats = HeroStats.compute(heroId, level, items)

	-- Proportionally scale health
	local healthPct = state.Health / state.MaxHealth
	state.MaxHealth = stats.MaxHealth
	state.Health = math.floor(stats.MaxHealth * healthPct)

	-- Scale mana similarly
	local manaPct = state.Mana / state.MaxMana
	state.MaxMana = stats.MaxMana
	state.Mana = math.floor(stats.MaxMana * manaPct)

	state.AttackDamage = stats.AttackDamage
	state.Armor = stats.Armor
	state.MoveSpeed = stats.MoveSpeed
	state.CooldownReduction = stats.CooldownReduction

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
		AttackDamage = state.AttackDamage,
		Armor = state.Armor,
	})
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
end

function HeroCombatService:DamageHero(player: Player, amount: number)
	local state = self._combatState[player.UserId]
	if not state or state.Invulnerable then
		return
	end
	state.Health = math.max(0, state.Health - amount)

	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = state.Health
		end
	end

	self.Client.HeroHealthChanged:Fire(player, state.Health, state.MaxHealth)
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
	if ok and shopService and shopService.GetItems then
		items = shopService:GetItems(player) or {}
	end

	local stats = HeroStats.compute(heroId, level, items)

	local state: CombatState = {
		MaxHealth = stats.MaxHealth,
		Health = stats.MaxHealth,
		Mana = stats.MaxMana,
		MaxMana = stats.MaxMana,
		AttackDamage = stats.AttackDamage,
		Armor = stats.Armor,
		MoveSpeed = stats.MoveSpeed,
		CooldownReduction = stats.CooldownReduction,
		AttackRange = Constants.HERO_ATTACK_RANGE,
		AttackCooldown = Constants.HERO_ATTACK_RATE,
		LastAttackTime = 0,
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

			-- Check attack cooldown
			if now - state.LastAttackTime < state.AttackCooldown then
				continue
			end

			-- Find nearest enemy creep in range
			local CreepService = Knit.GetService("CreepService")
			local activeCreeps = CreepService:GetActiveCreeps()
			local nearestCreep = nil
			local nearestDist = math.huge

			for _, creep in activeCreeps do
				-- Enemy creeps are ones targeting the hero's team
				if creep.TargetTeamId ~= heroTeamId then
					continue
				end
				local dist = (creep.Position - heroPos).Magnitude
				if dist <= state.AttackRange and dist < nearestDist then
					nearestDist = dist
					nearestCreep = creep
				end
			end

			if not nearestCreep then
				continue
			end

			-- Attack!
			state.LastAttackTime = now
			local damage = state.AttackDamage

			-- Check Blademaster crit passive
			local HeroService = Knit.GetService("HeroService")
			local heroId = HeroService:GetHeroId(player)
			if heroId == "Blademaster" then
				local level = HeroService:GetLevel(player)
				local heroDef = HeroData[heroId]
				if heroDef then
					for _, ability in heroDef.Abilities do
						if ability.Name == "Critical Strike" and ability.IsPassive and ability.UnlockLevel <= level then
							local critChance = (ability.Value or 25) / 100
							if math.random() < critChance then
								damage *= 2
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

			-- Apply damage to creep
			local killed = CreepService:DamageCreep(nearestCreep.Id, damage, player)

			-- Fire signal for client floating damage
			self.Client.HeroAttacked:FireAll(userId, nearestCreep.Id, damage, nearestCreep.Position, killed)
		end
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function HeroCombatService:KnitInit() end

function HeroCombatService:KnitStart() end

return HeroCombatService
