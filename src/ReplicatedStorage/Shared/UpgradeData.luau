--!strict

local UpgradeData = {}

--------------------------------------------------------------------------------
-- Economy Buildings — passive income bonuses
--------------------------------------------------------------------------------

UpgradeData.GoldMine = {
	Id = "GoldMine",
	Name = "Gold Mine",
	Category = "Economy",
	Description = "+income per tick",
	MaxLevel = 5,
	Costs = { 75, 200, 450, 800, 1400 },
	IncomeBonus = { 3, 8, 16, 28, 45 },
}

UpgradeData.LumberMill = {
	Id = "LumberMill",
	Name = "Lumber Mill",
	Category = "Economy",
	Description = "+income per tick",
	MaxLevel = 5,
	Costs = { 100, 250, 550, 1000, 1800 },
	IncomeBonus = { 4, 10, 20, 35, 55 },
}

UpgradeData.Marketplace = {
	Id = "Marketplace",
	Name = "Marketplace",
	Category = "Economy",
	Description = "+income per tick",
	MaxLevel = 3,
	Costs = { 300, 900, 2500 },
	IncomeBonus = { 8, 22, 50 },
}

--------------------------------------------------------------------------------
-- Hero Upgrades — improve your hero's combat stats
--------------------------------------------------------------------------------

UpgradeData.SharpenedEdge = {
	Id = "SharpenedEdge",
	Name = "Sharpened Edge",
	Category = "Hero",
	Description = "+ATK damage",
	MaxLevel = 5,
	Costs = { 100, 200, 400, 700, 1100 },
	BonusDamage = { 5, 12, 22, 35, 50 },
}

UpgradeData.IronPlating = {
	Id = "IronPlating",
	Name = "Iron Plating",
	Category = "Hero",
	Description = "+Armor",
	MaxLevel = 5,
	Costs = { 100, 200, 400, 700, 1100 },
	BonusArmor = { 2, 5, 10, 16, 25 },
}

UpgradeData.SwiftBoots = {
	Id = "SwiftBoots",
	Name = "Swift Boots",
	Category = "Hero",
	Description = "Faster attacks",
	MaxLevel = 3,
	Costs = { 150, 400, 900 },
	AttackSpeedPct = { 10, 25, 40 }, -- reduces attack cooldown by %
}

UpgradeData.ArcaneWisdom = {
	Id = "ArcaneWisdom",
	Name = "Arcane Wisdom",
	Category = "Hero",
	Description = "+Max Mana & Regen",
	MaxLevel = 3,
	Costs = { 120, 350, 800 },
	BonusMana = { 25, 60, 120 },
	BonusManaRegen = { 0.5, 1.5, 3 },
}

--------------------------------------------------------------------------------
-- Minion Upgrades — buff all creeps you send
--------------------------------------------------------------------------------

UpgradeData.WarDrums = {
	Id = "WarDrums",
	Name = "War Drums",
	Category = "Minion",
	Description = "+HP for your creeps",
	MaxLevel = 5,
	Costs = { 100, 250, 500, 900, 1500 },
	CreepHpPct = { 10, 25, 45, 70, 100 },
}

UpgradeData.SharpenedBlades = {
	Id = "SharpenedBlades",
	Name = "Sharpened Blades",
	Category = "Minion",
	Description = "+DMG for your creeps",
	MaxLevel = 5,
	Costs = { 100, 250, 500, 900, 1500 },
	CreepDmgPct = { 10, 25, 45, 70, 100 },
}

UpgradeData.BattleStandard = {
	Id = "BattleStandard",
	Name = "Battle Standard",
	Category = "Minion",
	Description = "+Speed for your creeps",
	MaxLevel = 3,
	Costs = { 150, 400, 900 },
	CreepSpeedPct = { 10, 20, 35 },
}

return UpgradeData
