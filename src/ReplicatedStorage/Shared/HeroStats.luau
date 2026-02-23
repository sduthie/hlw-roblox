--!strict

local Constants = require(script.Parent.Constants)
local HeroData = require(script.Parent.HeroData)
local ItemData = require(script.Parent.ItemData)

local HeroStats = {}

export type EffectiveStats = {
	MaxHealth: number,
	AttackDamage: number,
	Armor: number,
	MoveSpeed: number,
	CooldownReduction: number,
	MaxMana: number,
	ManaRegen: number,
}

function HeroStats.compute(heroId: string, level: number, itemIds: { string }): EffectiveStats
	local heroDef = HeroData[heroId]
	if not heroDef then
		-- Fallback defaults
		return {
			MaxHealth = 500,
			AttackDamage = 20,
			Armor = 0,
			MoveSpeed = 16,
			CooldownReduction = 0,
			MaxMana = Constants.BASE_MANA,
			ManaRegen = Constants.MANA_REGEN,
		}
	end

	local levelsGained = level - 1

	local maxHealth = heroDef.BaseHealth + levelsGained * Constants.HP_PER_LEVEL
	local attackDamage = heroDef.BaseDamage + levelsGained * Constants.DAMAGE_PER_LEVEL
	local armor = heroDef.BaseArmor + levelsGained * Constants.ARMOR_PER_LEVEL
	local moveSpeed = heroDef.MoveSpeed
	local cooldownReduction = 0
	local maxMana = Constants.BASE_MANA + levelsGained * Constants.MANA_PER_LEVEL
	local manaRegen = Constants.MANA_REGEN

	-- Stack item bonuses
	for _, itemId in itemIds do
		local itemDef = ItemData[itemId]
		if not itemDef then
			continue
		end
		local stats = itemDef.Stats
		if stats.Health then
			maxHealth += stats.Health
		end
		if stats.Damage then
			attackDamage += stats.Damage
		end
		if stats.Armor then
			armor += stats.Armor
		end
		if stats.MoveSpeed then
			moveSpeed += stats.MoveSpeed
		end
		if stats.CooldownReduction then
			cooldownReduction += stats.CooldownReduction
		end
	end

	-- Cap CDR at 40%
	cooldownReduction = math.min(cooldownReduction, 40)
	-- Round armor to 1 decimal
	armor = math.floor(armor * 10 + 0.5) / 10

	return {
		MaxHealth = maxHealth,
		AttackDamage = attackDamage,
		Armor = armor,
		MoveSpeed = moveSpeed,
		CooldownReduction = cooldownReduction,
		MaxMana = maxMana,
		ManaRegen = manaRegen,
	}
end

return HeroStats
