--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local HeroData = require(ReplicatedStorage.Shared.HeroData)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig)
local RemoteValidator = require(ReplicatedStorage.Shared.RemoteValidator)

--------------------------------------------------------------------------------
-- Service
--------------------------------------------------------------------------------

local AbilityService = Knit.CreateService({
	Name = "AbilityService",

	Client = {
		AbilityCast = Knit.CreateSignal(),
		AbilityCooldownStarted = Knit.CreateSignal(),
		AbilityUnlocked = Knit.CreateSignal(),
	},
})

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

AbilityService._cooldowns = {} :: { [number]: { [number]: number } } -- UserId -> {slotIndex -> expiry timestamp}
AbilityService._passiveApplied = {} :: { [number]: { [number]: boolean } } -- UserId -> {slotIndex -> applied}

--------------------------------------------------------------------------------
-- Client method
--------------------------------------------------------------------------------

function AbilityService.Client:CastAbility(player: Player, slotIndex: number): boolean
	if type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > 4 then
		return false
	end
	if not RemoteValidator.rateLimit(player, "CastAbility", 0.3) then
		return false
	end
	return self.Server:CastAbility(player, slotIndex)
end

--------------------------------------------------------------------------------
-- Server methods
--------------------------------------------------------------------------------

function AbilityService:CastAbility(player: Player, slotIndex: number): boolean
	-- Phase check
	local GameService = Knit.GetService("GameService")
	if GameService:GetPhase() ~= Constants.PHASE_PLAYING then
		return false
	end

	-- Get hero
	local HeroService = Knit.GetService("HeroService")
	local heroId = HeroService:GetHeroId(player)
	if not heroId then
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

	-- Check if ability is implemented
	if not abilityDef.Type then
		return false
	end

	-- Check if passive (can't be cast)
	if abilityDef.IsPassive then
		return false
	end

	-- Level check
	local level = HeroService:GetLevel(player)
	if level < abilityDef.UnlockLevel then
		return false
	end

	-- Cooldown check
	local userId = player.UserId
	local cooldowns = self._cooldowns[userId]
	if cooldowns then
		local expiry = cooldowns[slotIndex]
		if expiry and os.clock() < expiry then
			return false
		end
	end

	-- Mana check
	local HeroCombatService = Knit.GetService("HeroCombatService")
	if abilityDef.ManaCost > 0 then
		if not HeroCombatService:SpendMana(player, abilityDef.ManaCost) then
			return false
		end
	end

	-- Apply cooldown (with CDR)
	local state = HeroCombatService:GetCombatState(player)
	local cdr = if state then state.CooldownReduction else 0
	local effectiveCooldown = abilityDef.Cooldown * (1 - cdr / 100)
	if effectiveCooldown > 0 then
		if not self._cooldowns[userId] then
			self._cooldowns[userId] = {}
		end
		self._cooldowns[userId][slotIndex] = os.clock() + effectiveCooldown
		self.Client.AbilityCooldownStarted:Fire(player, slotIndex, effectiveCooldown)
	end

	-- Execute the ability
	self:_executeAbility(player, abilityDef)

	-- Fire cast signal
	self.Client.AbilityCast:FireAll(userId, slotIndex, abilityDef.Name)

	return true
end

function AbilityService:_executeAbility(player: Player, abilityDef: any)
	local abilityType = abilityDef.Type
	local HeroCombatService = Knit.GetService("HeroCombatService")

	if abilityType == "Damage" then
		self:_executeDamage(player, abilityDef)
	elseif abilityType == "Heal" then
		self:_executeHeal(player, abilityDef)
	elseif abilityType == "SelfBuff" then
		self:_executeSelfBuff(player, abilityDef, HeroCombatService)
	elseif abilityType == "Stun" then
		self:_executeStun(player, abilityDef)
	elseif abilityType == "Ward" then
		self:_executeWard(player, abilityDef)
	end
end

--------------------------------------------------------------------------------
-- Ability type executors
--------------------------------------------------------------------------------

function AbilityService:_executeDamage(player: Player, abilityDef: any)
	local character = player.Character
	if not character then
		return
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end
	local heroPos = rootPart.Position

	local CreepService = Knit.GetService("CreepService")
	local okTeam, teamService = pcall(function()
		return Knit.GetService("TeamService")
	end)
	if not okTeam then
		return
	end
	local heroTeamId = teamService:GetTeam(player)

	if abilityDef.DamagePerTick and abilityDef.Duration then
		-- DoT AoE (Blizzard, Bladestorm)
		local radius = abilityDef.Radius or 10
		local dpt = abilityDef.DamagePerTick
		local interval = abilityDef.TickInterval or 1
		local duration = abilityDef.Duration

		task.spawn(function()
			local elapsed = 0
			while elapsed < duration do
				task.wait(interval)
				elapsed += interval

				-- Re-get position for abilities that follow hero (Bladestorm)
				local charNow = player.Character
				if not charNow then
					break
				end
				local rootNow = charNow:FindFirstChild("HumanoidRootPart") :: BasePart?
				if not rootNow then
					break
				end
				local pos = rootNow.Position

				local activeCreeps = CreepService:GetActiveCreeps()
				for _, creep in activeCreeps do
					if creep.TargetTeamId ~= heroTeamId then
						continue
					end
					local dist = (creep.Position - pos).Magnitude
					if dist <= radius then
						CreepService:DamageCreep(creep.Id, dpt, player)
					end
				end
			end
		end)
	elseif abilityDef.Value then
		-- Single target damage (Death Coil)
		local range = abilityDef.Range or Constants.HERO_ATTACK_RANGE
		local activeCreeps = CreepService:GetActiveCreeps()
		local nearestCreep = nil
		local nearestDist = math.huge

		for _, creep in activeCreeps do
			if creep.TargetTeamId ~= heroTeamId then
				continue
			end
			local dist = (creep.Position - heroPos).Magnitude
			if dist <= range and dist < nearestDist then
				nearestDist = dist
				nearestCreep = creep
			end
		end

		if nearestCreep then
			CreepService:DamageCreep(nearestCreep.Id, abilityDef.Value, player)
		end
	end
end

function AbilityService:_executeHeal(player: Player, abilityDef: any)
	local HeroCombatService = Knit.GetService("HeroCombatService")

	-- Death Pact special: costs 150hp first
	if abilityDef.Name == "Death Pact" then
		HeroCombatService:DamageHero(player, 150)
	end

	HeroCombatService:HealHero(player, abilityDef.Value or 0)
end

function AbilityService:_executeSelfBuff(player: Player, abilityDef: any, heroCombatService: any)
	local duration = abilityDef.Duration or 5

	if abilityDef.Name == "Divine Shield" then
		heroCombatService:SetInvulnerable(player, true)
		task.delay(duration, function()
			heroCombatService:SetInvulnerable(player, false)
		end)
	elseif abilityDef.Name == "Wind Walk" then
		-- Speed buff + 2x next attack damage + transparency
		local speedBonus = abilityDef.Value or 8
		heroCombatService:ApplyBuff(player, "WindWalk", "MoveSpeed", speedBonus, duration)
		heroCombatService:SetWindWalk(player, true, 2)
		task.delay(duration, function()
			-- If still active after duration, deactivate
			local state = heroCombatService:GetCombatState(player)
			if state and state.WindWalkActive then
				heroCombatService:SetWindWalk(player, false)
			end
		end)
	end
end

function AbilityService:_executeStun(player: Player, abilityDef: any)
	-- Hex: stun nearest enemy creep
	local character = player.Character
	if not character then
		return
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end
	local heroPos = rootPart.Position

	local okTeam, teamService = pcall(function()
		return Knit.GetService("TeamService")
	end)
	if not okTeam then
		return
	end
	local heroTeamId = teamService:GetTeam(player)

	local CreepService = Knit.GetService("CreepService")
	local range = abilityDef.Range or 20
	local activeCreeps = CreepService:GetActiveCreeps()
	local nearestCreep = nil
	local nearestDist = math.huge

	for _, creep in activeCreeps do
		if creep.TargetTeamId ~= heroTeamId then
			continue
		end
		local dist = (creep.Position - heroPos).Magnitude
		if dist <= range and dist < nearestDist then
			nearestDist = dist
			nearestCreep = creep
		end
	end

	if nearestCreep then
		local duration = abilityDef.Duration or 4
		CreepService:HexCreep(nearestCreep.Id, duration)
	end
end

function AbilityService:_executeWard(player: Player, abilityDef: any)
	-- Serpent Ward: create a neon part that damages nearby enemy creeps
	local character = player.Character
	if not character then
		return
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end
	local wardPos = rootPart.Position + Vector3.new(0, 0, 3) -- slightly offset

	local okTeam, teamService = pcall(function()
		return Knit.GetService("TeamService")
	end)
	if not okTeam then
		return
	end
	local heroTeamId = teamService:GetTeam(player)

	-- Create visual ward
	local ward = Instance.new("Part")
	ward.Name = "SerpentWard"
	ward.Shape = Enum.PartType.Cylinder
	ward.Size = Vector3.new(4, 1.5, 1.5)
	ward.CFrame = CFrame.new(wardPos) * CFrame.Angles(0, 0, math.rad(90))
	ward.Color = Color3.fromRGB(0, 200, 80)
	ward.Material = Enum.Material.Neon
	ward.Anchored = true
	ward.CanCollide = false
	ward.Parent = workspace

	local dpt = abilityDef.DamagePerTick or 20
	local interval = abilityDef.TickInterval or 1
	local radius = abilityDef.Radius or 10
	local duration = abilityDef.Duration or 15

	local CreepService = Knit.GetService("CreepService")

	task.spawn(function()
		local elapsed = 0
		while elapsed < duration do
			task.wait(interval)
			elapsed += interval

			local activeCreeps = CreepService:GetActiveCreeps()
			for _, creep in activeCreeps do
				if creep.TargetTeamId ~= heroTeamId then
					continue
				end
				local dist = (creep.Position - wardPos).Magnitude
				if dist <= radius then
					CreepService:DamageCreep(creep.Id, dpt, player)
				end
			end
		end

		ward:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Passive abilities
--------------------------------------------------------------------------------

function AbilityService:ApplyPassives(player: Player)
	local HeroService = Knit.GetService("HeroService")
	local heroId = HeroService:GetHeroId(player)
	if not heroId then
		return
	end

	local heroDef = HeroData[heroId]
	if not heroDef then
		return
	end

	local HeroCombatService = Knit.GetService("HeroCombatService")
	local level = HeroService:GetLevel(player)
	local userId = player.UserId

	if not self._passiveApplied[userId] then
		self._passiveApplied[userId] = {}
	end

	for slotIndex, ability in heroDef.Abilities do
		if not ability.IsPassive or not ability.Type then
			continue
		end
		if level < ability.UnlockLevel then
			continue
		end
		if self._passiveApplied[userId][slotIndex] then
			continue
		end

		-- Apply permanent buff (very long duration)
		if ability.Name == "Devotion Aura" then
			HeroCombatService:ApplyBuff(player, "DevotionAura", "Armor", ability.Value or 5, 999999)
		elseif ability.Name == "Brilliance Aura" then
			HeroCombatService:ApplyBuff(player, "BrillianceAura", "ManaRegen", ability.Value or 2, 999999)
		elseif ability.Name == "Unholy Aura" then
			HeroCombatService:ApplyBuff(player, "UnholyAura", "MoveSpeed", ability.Value or 4, 999999)
		end
		-- Critical Strike is handled in the combat loop (checked per-attack)

		self._passiveApplied[userId][slotIndex] = true
		self.Client.AbilityUnlocked:Fire(player, slotIndex)
	end
end

function AbilityService:ResetPlayer(player: Player)
	local userId = player.UserId
	self._cooldowns[userId] = nil
	self._passiveApplied[userId] = nil
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function AbilityService:KnitInit() end

function AbilityService:KnitStart() end

return AbilityService
