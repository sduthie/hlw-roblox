--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local HeroData = require(ReplicatedStorage.Shared.HeroData)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig)
local RemoteValidator = require(ReplicatedStorage.Shared.RemoteValidator)
local AbilityHelper = require(ReplicatedStorage.Shared.AbilityHelper)

--------------------------------------------------------------------------------
-- Service
--------------------------------------------------------------------------------

local AbilityService = Knit.CreateService({
	Name = "AbilityService",

	Client = {
		AbilityCast = Knit.CreateSignal(),
		AbilityCooldownStarted = Knit.CreateSignal(),
		AbilityUnlocked = Knit.CreateSignal(),
		PetSpawned = Knit.CreateSignal(),
		PetDied = Knit.CreateSignal(),
		ElementalAttack = Knit.CreateSignal(),
	},
})

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

AbilityService._cooldowns = {} :: { [number]: { [number]: number } }
AbilityService._passiveApplied = {} :: { [number]: { [string]: boolean } } -- UserId -> {abilityName_level -> applied}
AbilityService._activePets = {} :: { [number]: any } -- UserId -> pet state table

--------------------------------------------------------------------------------
-- Client method
--------------------------------------------------------------------------------

function AbilityService.Client:CastAbility(player: Player, slotIndex: number, targetPosition: Vector3?): boolean
	if type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > 4 then
		return false
	end
	if not RemoteValidator.rateLimit(player, "CastAbility", 0.3) then
		return false
	end
	-- Validate targetPosition if provided
	if targetPosition ~= nil and typeof(targetPosition) ~= "Vector3" then
		return false
	end
	return self.Server:CastAbility(player, slotIndex, targetPosition)
end

function AbilityService.Client:PetCommand(player: Player, command: string, data: any?)
	if type(command) ~= "string" then
		return
	end
	if not RemoteValidator.rateLimit(player, "PetCommand", 0.2) then
		return
	end
	self.Server:HandlePetCommand(player, command, data)
end

--------------------------------------------------------------------------------
-- Server methods
--------------------------------------------------------------------------------

function AbilityService:CastAbility(player: Player, slotIndex: number, targetPosition: Vector3?): boolean
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

	-- Check ability level (must be learned)
	local abilityLevel = HeroService:GetAbilityLevel(player, slotIndex)
	if abilityLevel <= 0 then
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

	-- Mana check (use level-scaled mana cost)
	local HeroCombatService = Knit.GetService("HeroCombatService")
	local manaCost = AbilityHelper.getVal(abilityDef, "ManaCost", abilityLevel)
	if manaCost > 0 then
		if not HeroCombatService:SpendMana(player, manaCost) then
			return false
		end
	end

	-- Apply cooldown (with CDR)
	local state = HeroCombatService:GetCombatState(player)
	local cdr = if state then state.CooldownReduction else 0
	local baseCooldown = AbilityHelper.getVal(abilityDef, "Cooldown", abilityLevel)
	local effectiveCooldown = baseCooldown * (1 - cdr / 100)
	if effectiveCooldown > 0 then
		if not self._cooldowns[userId] then
			self._cooldowns[userId] = {}
		end
		self._cooldowns[userId][slotIndex] = os.clock() + effectiveCooldown
		self.Client.AbilityCooldownStarted:Fire(player, slotIndex, effectiveCooldown)
	end

	-- Validate ground-targeted position (range check)
	local validatedTarget = targetPosition
	if abilityDef.TargetType == "Ground" and validatedTarget then
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rootPart then
			local dist = (validatedTarget - rootPart.Position).Magnitude
			local maxRange = AbilityHelper.getVal(abilityDef, "Range", abilityLevel)
			if maxRange <= 0 then maxRange = 50 end
			if dist > maxRange + 5 then -- small grace margin
				validatedTarget = rootPart.Position + (validatedTarget - rootPart.Position).Unit * maxRange
			end
		end
	end

	-- Execute the ability with level scaling
	self:_executeAbility(player, abilityDef, abilityLevel, validatedTarget)

	-- Fire cast signal (include target position for VFX)
	self.Client.AbilityCast:FireAll(userId, slotIndex, abilityDef.Name, validatedTarget)

	return true
end

function AbilityService:_executeAbility(player: Player, abilityDef: any, abilityLevel: number, targetPosition: Vector3?)
	local abilityType = abilityDef.Type
	local HeroCombatService = Knit.GetService("HeroCombatService")

	if abilityType == "Damage" then
		self:_executeDamage(player, abilityDef, abilityLevel, targetPosition)
	elseif abilityType == "Heal" then
		self:_executeHeal(player, abilityDef, abilityLevel)
	elseif abilityType == "SelfBuff" then
		self:_executeSelfBuff(player, abilityDef, abilityLevel, HeroCombatService)
	elseif abilityType == "Stun" then
		self:_executeStun(player, abilityDef, abilityLevel)
	elseif abilityType == "Ward" then
		self:_executeWard(player, abilityDef, abilityLevel)
	elseif abilityType == "Summon" then
		self:_executeSummon(player, abilityDef, abilityLevel)
	end
end

--------------------------------------------------------------------------------
-- Helper: get hero stats for scaling
--------------------------------------------------------------------------------

local function _getHeroStats(player: Player): { [string]: number }?
	local ok, heroCombatService = pcall(function()
		return Knit.GetService("HeroCombatService")
	end)
	if not ok then
		return nil
	end
	local state = heroCombatService:GetCombatState(player)
	if not state then
		return nil
	end
	return {
		AttackDamage = state.AttackDamage,
		MaxHealth = state.MaxHealth,
		Armor = state.Armor,
		MoveSpeed = state.MoveSpeed,
	}
end

--------------------------------------------------------------------------------
-- Ability type executors
--------------------------------------------------------------------------------

function AbilityService:_executeDamage(player: Player, abilityDef: any, abilityLevel: number, targetPosition: Vector3?)
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

	local dpt = AbilityHelper.getVal(abilityDef, "DamagePerTick", abilityLevel)

	if dpt > 0 and AbilityHelper.getVal(abilityDef, "Duration", abilityLevel) > 0 then
		-- DoT AoE (Blizzard, Bladestorm) with stat scaling
		local heroStats = _getHeroStats(player)
		local scaledBonus = 0
		if abilityDef.ScaleStat and abilityDef.ScalePercent and heroStats then
			local pct = AbilityHelper.getVal(abilityDef, "ScalePercent", abilityLevel)
			local statVal = heroStats[abilityDef.ScaleStat] or 0
			scaledBonus = math.floor(statVal * pct / 100)
		end
		local totalDPT = dpt + scaledBonus

		local radius = AbilityHelper.getVal(abilityDef, "Radius", abilityLevel)
		if radius <= 0 then
			radius = 10
		end
		local interval = AbilityHelper.getVal(abilityDef, "TickInterval", abilityLevel)
		if interval <= 0 then
			interval = 1
		end
		local duration = AbilityHelper.getVal(abilityDef, "Duration", abilityLevel)

		-- Ground-targeted abilities use the target position; others follow the hero
		local isGroundTargeted = abilityDef.TargetType == "Ground" and targetPosition ~= nil
		local fixedCenter = if isGroundTargeted then targetPosition else nil

		-- Blizzard-specific slow/freeze: slow all creeps, freeze chance at lv3+
		local isBlizzard = abilityDef.Name == "Blizzard"
		local slowFactor = if isBlizzard then 0.5 else 1 -- 50% speed reduction
		local freezeChance = 0
		if isBlizzard and abilityLevel >= 3 then
			-- Level 3: 20%, Level 4: 35%, Level 5: 50%
			local freezeTable = { [3] = 0.20, [4] = 0.35, [5] = 0.50 }
			freezeChance = freezeTable[abilityLevel] or 0
		end

		task.spawn(function()
			local elapsed = 0
			while elapsed < duration do
				task.wait(interval)
				elapsed += interval

				-- Ground-targeted: use fixed center; otherwise follow hero
				local pos = fixedCenter
				if not pos then
					local charNow = player.Character
					if not charNow then
						break
					end
					local rootNow = charNow:FindFirstChild("HumanoidRootPart") :: BasePart?
					if not rootNow then
						break
					end
					pos = rootNow.Position
				end

				local activeCreeps = CreepService:GetActiveCreeps()
				for _, creep in activeCreeps do
					if creep.TeamId == heroTeamId then
						continue
					end
					local dist = (creep.Position - pos).Magnitude
					if dist <= radius then
						CreepService:DamageCreep(creep.Id, totalDPT, player)

						-- Blizzard slow/freeze effects
						if isBlizzard then
							-- Apply slow for the tick interval + extra
							creep.SlowedUntil = os.clock() + interval + 0.5
							creep.SlowFactor = slowFactor

							-- Freeze chance (stun) at level 3+
							if freezeChance > 0 and math.random() < freezeChance then
								local freezeDuration = 1.5
								local stunUntil = os.clock() + freezeDuration
								if (creep.StunnedUntil or 0) < stunUntil then
									creep.StunnedUntil = stunUntil
								end
							end
						end
					end
				end
			end
		end)
	elseif AbilityHelper.getVal(abilityDef, "Value", abilityLevel) > 0 then
		-- Single target damage (Death Coil) with stat scaling
		local heroStats = _getHeroStats(player)
		local dmg = AbilityHelper.getScaledVal(abilityDef, abilityLevel, heroStats)

		local range = AbilityHelper.getVal(abilityDef, "Range", abilityLevel)
		if range <= 0 then
			range = Constants.HERO_ATTACK_RANGE
		end

		local activeCreeps = CreepService:GetActiveCreeps()
		local nearestCreep = nil
		local nearestDist = math.huge

		for _, creep in activeCreeps do
			if creep.TeamId == heroTeamId then
				continue
			end
			local dist = (creep.Position - heroPos).Magnitude
			if dist <= range and dist < nearestDist then
				nearestDist = dist
				nearestCreep = creep
			end
		end

		if nearestCreep then
			CreepService:DamageCreep(nearestCreep.Id, dmg, player)
		end
	end
end

function AbilityService:_executeHeal(player: Player, abilityDef: any, abilityLevel: number)
	local HeroCombatService = Knit.GetService("HeroCombatService")

	-- Death Pact special: costs 150hp first
	if abilityDef.Name == "Death Pact" then
		HeroCombatService:DamageHero(player, 150)
	end

	local heroStats = _getHeroStats(player)
	local healAmount = AbilityHelper.getScaledVal(abilityDef, abilityLevel, heroStats)
	HeroCombatService:HealHero(player, healAmount)
end

function AbilityService:_executeSelfBuff(player: Player, abilityDef: any, abilityLevel: number, heroCombatService: any)
	local duration = AbilityHelper.getVal(abilityDef, "Duration", abilityLevel)
	if duration <= 0 then
		duration = 5
	end

	if abilityDef.Name == "Divine Shield" then
		heroCombatService:SetInvulnerable(player, true)
		task.delay(duration, function()
			heroCombatService:SetInvulnerable(player, false)
		end)
	elseif abilityDef.Name == "Wind Walk" then
		local speedBonus = AbilityHelper.getVal(abilityDef, "Value", abilityLevel)
		if speedBonus <= 0 then
			speedBonus = 8
		end
		heroCombatService:ApplyBuff(player, "WindWalk", "MoveSpeed", speedBonus, duration)
		heroCombatService:SetWindWalk(player, true, 2)
		task.delay(duration, function()
			local state = heroCombatService:GetCombatState(player)
			if state and state.WindWalkActive then
				heroCombatService:SetWindWalk(player, false)
			end
		end)
	end
end

function AbilityService:_executeStun(player: Player, abilityDef: any, abilityLevel: number)
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
	local range = AbilityHelper.getVal(abilityDef, "Range", abilityLevel)
	if range <= 0 then
		range = 20
	end

	local activeCreeps = CreepService:GetActiveCreeps()
	local nearestCreep = nil
	local nearestDist = math.huge

	for _, creep in activeCreeps do
		if creep.TeamId == heroTeamId then
			continue
		end
		local dist = (creep.Position - heroPos).Magnitude
		if dist <= range and dist < nearestDist then
			nearestDist = dist
			nearestCreep = creep
		end
	end

	if nearestCreep then
		local duration = AbilityHelper.getVal(abilityDef, "Duration", abilityLevel)
		if duration <= 0 then
			duration = 4
		end
		CreepService:HexCreep(nearestCreep.Id, duration)
	end
end

function AbilityService:_executeWard(player: Player, abilityDef: any, abilityLevel: number)
	local character = player.Character
	if not character then
		return
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end
	local wardPos = rootPart.Position + Vector3.new(0, 0, 3)

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

	-- Stat-scaled damage
	local heroStats = _getHeroStats(player)
	local baseDPT = AbilityHelper.getVal(abilityDef, "DamagePerTick", abilityLevel)
	local scaledBonus = 0
	if abilityDef.ScaleStat and abilityDef.ScalePercent and heroStats then
		local pct = AbilityHelper.getVal(abilityDef, "ScalePercent", abilityLevel)
		local statVal = heroStats[abilityDef.ScaleStat] or 0
		scaledBonus = math.floor(statVal * pct / 100)
	end
	local totalDPT = baseDPT + scaledBonus

	local interval = AbilityHelper.getVal(abilityDef, "TickInterval", abilityLevel)
	if interval <= 0 then
		interval = 1
	end
	local radius = AbilityHelper.getVal(abilityDef, "Radius", abilityLevel)
	if radius <= 0 then
		radius = 10
	end
	local duration = AbilityHelper.getVal(abilityDef, "Duration", abilityLevel)

	local CreepService = Knit.GetService("CreepService")

	task.spawn(function()
		local elapsed = 0
		while elapsed < duration do
			task.wait(interval)
			elapsed += interval

			local activeCreeps = CreepService:GetActiveCreeps()
			for _, creep in activeCreeps do
				if creep.TeamId == heroTeamId then
					continue
				end
				local dist = (creep.Position - wardPos).Magnitude
				if dist <= radius then
					CreepService:DamageCreep(creep.Id, totalDPT, player)
				end
			end
		end

		ward:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Pet commands (retarget, move, hold position)
--------------------------------------------------------------------------------

function AbilityService:HandlePetCommand(player: Player, command: string, data: any?)
	local userId = player.UserId
	local pet = self._activePets[userId]
	if not pet then
		return
	end

	if command == "retarget" and type(data) == "number" then
		pet.TargetCreepId = data
		pet.MoveTarget = nil
		pet.HoldPosition = nil
	elseif command == "move" and typeof(data) == "Vector3" then
		pet.MoveTarget = data
		pet.TargetCreepId = 0
		pet.HoldPosition = nil
	elseif command == "hold" and typeof(data) == "Vector3" then
		pet.HoldPosition = data
		pet.MoveTarget = nil
		pet.TargetCreepId = 0
	end
end

--------------------------------------------------------------------------------
-- Summon: spawn a temporary allied creep near the hero
--------------------------------------------------------------------------------

function AbilityService:_executeSummon(player: Player, abilityDef: any, abilityLevel: number)
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
	if not heroTeamId then
		return
	end

	-- Destroy existing pet if any
	local userId = player.UserId
	local oldPet = self._activePets[userId]
	if oldPet and oldPet.Model and oldPet.Model.Parent then
		oldPet.Model:Destroy()
	end
	self._activePets[userId] = nil

	-- Stat-scaled damage
	local heroStats = _getHeroStats(player)
	local baseDmg = AbilityHelper.getVal(abilityDef, "Damage", abilityLevel)
	local scaledBonus = 0
	if abilityDef.ScaleStat and abilityDef.ScalePercent and heroStats then
		local pct = AbilityHelper.getVal(abilityDef, "ScalePercent", abilityLevel)
		local statVal = heroStats[abilityDef.ScaleStat] or 0
		scaledBonus = math.floor(statVal * pct / 100)
	end
	local totalDmg = baseDmg + scaledBonus
	local elementalHP = AbilityHelper.getVal(abilityDef, "Value", abilityLevel)
	local duration = AbilityHelper.getVal(abilityDef, "Duration", abilityLevel)
	if duration <= 0 then
		duration = 30
	end

	-- Spawn the elemental as a visual model near the hero
	local spawnPos = heroPos + Vector3.new(math.random(-3, 3), 0, math.random(-3, 3))
	local model = Instance.new("Model")
	model.Name = "WaterElemental_" .. userId .. "_" .. tostring(os.clock())

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Block
	body.Size = Vector3.new(2.5, 4, 2.5)
	body.Position = spawnPos + Vector3.new(0, 2, 0)
	body.Anchored = true
	body.CanCollide = false
	body.Material = Enum.Material.Glass
	body.Color = Color3.fromRGB(60, 140, 255)
	body.Transparency = 0.3
	body.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(2, 2, 2)
	head.Position = spawnPos + Vector3.new(0, 5, 0)
	head.Anchored = true
	head.CanCollide = false
	head.Material = Enum.Material.Glass
	head.Color = Color3.fromRGB(80, 160, 255)
	head.Transparency = 0.3
	head.Parent = model

	-- Glow
	local light = Instance.new("PointLight")
	light.Range = 10
	light.Brightness = 1
	light.Color = Color3.fromRGB(60, 140, 255)
	light.Parent = body

	model.PrimaryPart = body
	model.Parent = workspace

	-- Health bar
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealthBar"
	billboard.Size = UDim2.new(0, 50, 0, 6)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.Adornee = head
	billboard.AlwaysOnTop = true
	billboard.Parent = model

	local hpBg = Instance.new("Frame")
	hpBg.Size = UDim2.fromScale(1, 1)
	hpBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	hpBg.BorderSizePixel = 0
	hpBg.Parent = billboard

	local hpFill = Instance.new("Frame")
	hpFill.Name = "Fill"
	hpFill.Size = UDim2.fromScale(1, 1)
	hpFill.BackgroundColor3 = Color3.fromRGB(60, 180, 255)
	hpFill.BorderSizePixel = 0
	hpFill.Parent = hpBg

	-- Get hero's current attack target so pet starts attacking it
	local HeroCombatService = Knit.GetService("HeroCombatService")
	local initialTarget = HeroCombatService._attackTargets[userId] or 0

	-- Store pet state
	local petState = {
		Model = model,
		Body = body,
		Head = head,
		HP = elementalHP,
		MaxHP = elementalHP,
		HPFill = hpFill,
		TeamId = heroTeamId,
		Damage = totalDmg,
		Duration = duration,
		SpawnTime = os.clock(),
		TargetCreepId = initialTarget,
		MoveTarget = nil :: Vector3?,
		HoldPosition = nil :: Vector3?,
		LastAttackTime = 0,
		Owner = player,
	}
	self._activePets[userId] = petState

	-- Notify client that pet spawned
	self.Client.PetSpawned:Fire(player)

	-- Elemental combat loop
	local CreepService = Knit.GetService("CreepService")

	task.spawn(function()
		local attackCooldown = 1.2
		local attackRange = 10
		local moveSpeed = 12

		while (os.clock() - petState.SpawnTime) < petState.Duration and petState.HP > 0 do
			local dt = task.wait(0.1)
			local currentPos = body.Position
			local now = os.clock()

			-- Hold position mode: stay at position, attack enemies in range
			if petState.HoldPosition then
				local holdPos = petState.HoldPosition
				local distToHold = (currentPos - Vector3.new(holdPos.X, currentPos.Y, holdPos.Z)).Magnitude
				if distToHold > 1 then
					local dir = (Vector3.new(holdPos.X, currentPos.Y, holdPos.Z) - currentPos).Unit
					local newPos = currentPos + dir * moveSpeed * dt
					body.Position = newPos
					head.Position = newPos + Vector3.new(0, 3, 0)
				end

				-- Attack nearest enemy in range while holding
				local activeCreeps = CreepService:GetActiveCreeps()
				local nearestInRange = nil
				local nearestDist = math.huge
				for _, creep in activeCreeps do
					if creep.TeamId == heroTeamId then
						continue
					end
					local dist = (creep.Position - body.Position).Magnitude
					if dist <= attackRange and dist < nearestDist then
						nearestDist = dist
						nearestInRange = creep
					end
				end
				if nearestInRange and now - petState.LastAttackTime >= attackCooldown then
					petState.LastAttackTime = now
					local petKilled = CreepService:DamageCreep(nearestInRange.Id, petState.Damage, player)
					self.Client.ElementalAttack:FireAll(body.Position, nearestInRange.Position, petState.Damage, petKilled)
				end

			-- Move-to mode: walk to target position, then resume auto-targeting
			elseif petState.MoveTarget then
				local moveTarget = petState.MoveTarget
				local distToTarget = (currentPos - Vector3.new(moveTarget.X, currentPos.Y, moveTarget.Z)).Magnitude
				if distToTarget > 2 then
					local dir = (Vector3.new(moveTarget.X, currentPos.Y, moveTarget.Z) - currentPos).Unit
					local newPos = currentPos + dir * moveSpeed * dt
					body.Position = newPos
					head.Position = newPos + Vector3.new(0, 3, 0)
				else
					-- Arrived, clear move target
					petState.MoveTarget = nil
				end

			-- Targeted attack mode: chase and attack a specific creep
			elseif petState.TargetCreepId > 0 then
				local activeCreeps = CreepService:GetActiveCreeps()
				local targetCreep = activeCreeps[petState.TargetCreepId]
				if targetCreep and targetCreep.TeamId ~= heroTeamId then
					local dist = (targetCreep.Position - currentPos).Magnitude
					if dist <= attackRange then
						if now - petState.LastAttackTime >= attackCooldown then
							petState.LastAttackTime = now
							local petKilled2 = CreepService:DamageCreep(targetCreep.Id, petState.Damage, player)
							self.Client.ElementalAttack:FireAll(body.Position, targetCreep.Position, petState.Damage, petKilled2)
						end
					else
						local dir = (targetCreep.Position - currentPos).Unit
						local newPos = currentPos + dir * moveSpeed * dt
						body.Position = newPos
						head.Position = newPos + Vector3.new(0, 3, 0)
					end
				else
					-- Target dead or invalid, fall back to auto
					petState.TargetCreepId = 0
				end

			-- Default: find and attack nearest enemy creep
			else
				local activeCreeps = CreepService:GetActiveCreeps()
				local nearestCreep = nil
				local nearestDist = math.huge
				for _, creep in activeCreeps do
					if creep.TeamId == heroTeamId then
						continue
					end
					local dist = (creep.Position - currentPos).Magnitude
					if dist < nearestDist then
						nearestDist = dist
						nearestCreep = creep
					end
				end

				if nearestCreep then
					if nearestDist <= attackRange then
						if now - petState.LastAttackTime >= attackCooldown then
							petState.LastAttackTime = now
							local petKilled3 = CreepService:DamageCreep(nearestCreep.Id, petState.Damage, player)
							self.Client.ElementalAttack:FireAll(body.Position, nearestCreep.Position, petState.Damage, petKilled3)
						end
					else
						local dir = (nearestCreep.Position - currentPos).Unit
						local newPos = currentPos + dir * moveSpeed * dt
						body.Position = newPos
						head.Position = newPos + Vector3.new(0, 3, 0)
					end
				end
			end

			-- Update HP bar
			petState.HPFill.Size = UDim2.fromScale(math.max(0, petState.HP / petState.MaxHP), 1)
		end

		-- Destroy elemental
		model:Destroy()
		if self._activePets[userId] == petState then
			self._activePets[userId] = nil
		end
		self.Client.PetDied:Fire(player)
	end)
end

--------------------------------------------------------------------------------
-- Passive abilities (re-apply when ability is leveled up)
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
	local userId = player.UserId

	if not self._passiveApplied[userId] then
		self._passiveApplied[userId] = {}
	end

	for slotIndex, ability in heroDef.Abilities do
		if not ability.IsPassive or not ability.Type then
			continue
		end

		local abilityLevel = HeroService:GetAbilityLevel(player, slotIndex)
		if abilityLevel <= 0 then
			continue
		end

		-- Track by ability name + level so we re-apply when leveled
		local trackKey = ability.Name .. "_" .. tostring(abilityLevel)
		if self._passiveApplied[userId][trackKey] then
			continue
		end

		local value = AbilityHelper.getVal(ability, "Value", abilityLevel)

		-- Remove previous level's buff first
		for prevLevel = 1, abilityLevel - 1 do
			local prevKey = ability.Name .. "_" .. tostring(prevLevel)
			self._passiveApplied[userId][prevKey] = nil
		end

		-- Apply permanent buff
		if ability.Name == "Devotion Aura" then
			HeroCombatService:ApplyBuff(player, "DevotionAura", "Armor", value, 999999)
		elseif ability.Name == "Brilliance Aura" then
			HeroCombatService:ApplyBuff(player, "BrillianceAura", "ManaRegen", value, 999999)
		elseif ability.Name == "Unholy Aura" then
			HeroCombatService:ApplyBuff(player, "UnholyAura", "MoveSpeed", value, 999999)
		end

		self._passiveApplied[userId][trackKey] = true
		self.Client.AbilityUnlocked:Fire(player, slotIndex)
	end
end

function AbilityService:ResetPlayer(player: Player)
	local userId = player.UserId
	self._cooldowns[userId] = nil
	self._passiveApplied[userId] = nil

	-- Destroy active pet
	local pet = self._activePets[userId]
	if pet and pet.Model and pet.Model.Parent then
		pet.Model:Destroy()
	end
	self._activePets[userId] = nil
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function AbilityService:KnitInit() end

function AbilityService:KnitStart() end

return AbilityService
