--!strict

--[[
	Shared helper for resolving ability values that scale per ability level.

	Ability fields can be:
	  - A number (constant across all levels)
	  - A table/array (indexed by ability level)

	Usage:
	  local cd = AbilityHelper.getVal(abilityDef, "Cooldown", abilityLevel)
	  local dmg = AbilityHelper.getScaledVal(abilityDef, abilityLevel, heroStats)
]]

local AbilityHelper = {}

--- Get a raw value from an ability definition, resolving arrays by level.
function AbilityHelper.getVal(abilityDef: any, key: string, level: number): number
	local v = abilityDef[key]
	if v == nil then
		return 0
	end
	if type(v) == "table" then
		return v[math.clamp(level, 1, #v)] or 0
	end
	return v
end

--- Get the effective value of an ability (base + stat scaling).
--- `heroStats` should be a table with keys like AttackDamage, MaxHealth, Armor, etc.
function AbilityHelper.getScaledVal(abilityDef: any, level: number, heroStats: { [string]: number }?): number
	local base = AbilityHelper.getVal(abilityDef, "Value", level)

	if abilityDef.ScaleStat and abilityDef.ScalePercent and heroStats then
		local pct = AbilityHelper.getVal(abilityDef, "ScalePercent", level)
		local statVal = heroStats[abilityDef.ScaleStat] or 0
		base += math.floor(statVal * pct / 100)
	end

	return base
end

return AbilityHelper
