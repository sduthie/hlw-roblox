--!strict

local Types = require(script.Parent.Types)

local CreepData: { [string]: Types.CreepDef } = {
	-- Tier 1: Town Hall
	Footman = {
		Id = "Footman",
		Name = "Footman",
		Tier = 1,
		Cost = 15,
		IncomeBonus = 1,
		Health = 100,
		Damage = 10,
		Armor = 1,
		MoveSpeed = 14,
		Ability = {
			Name = "Shield Bash",
			Type = "Stun",
			Cooldown = 8,
			Value = 1.5, -- stun duration in seconds
			Radius = 0,
			Duration = 0,
		},
	},
	Rifleman = {
		Id = "Rifleman",
		Name = "Rifleman",
		Tier = 1,
		Cost = 25,
		IncomeBonus = 3,
		Health = 80,
		Damage = 18,
		Armor = 0,
		MoveSpeed = 14,
		Ability = {
			Name = "Volley",
			Type = "BonusDamage",
			Cooldown = 6,
			Value = 18, -- extra damage dealt to each secondary target
			Radius = 10, -- search radius for secondary targets
			Duration = 0,
		},
	},
	Grunt = {
		Id = "Grunt",
		Name = "Grunt",
		Tier = 1,
		Cost = 30,
		IncomeBonus = 2,
		Health = 150,
		Damage = 12,
		Armor = 2,
		MoveSpeed = 12,
		Ability = {
			Name = "War Cry",
			Type = "BuffAllies",
			Cooldown = 12,
			Value = 0.3, -- +30% damage multiplier
			Radius = 12,
			Duration = 4,
		},
	},

	-- Tier 2: Stronghold
	Knight = {
		Id = "Knight",
		Name = "Knight",
		Tier = 2,
		Cost = 80,
		IncomeBonus = 5,
		Health = 350,
		Damage = 28,
		Armor = 4,
		MoveSpeed = 16,
		Ability = {
			Name = "Charge",
			Type = "Charge",
			Cooldown = 10,
			Value = 2, -- next hit deals 2x damage
			Radius = 0,
			Duration = 0,
		},
	},
	Priest = {
		Id = "Priest",
		Name = "Priest",
		Tier = 2,
		Cost = 60,
		IncomeBonus = 4,
		Health = 180,
		Damage = 15,
		Armor = 1,
		MoveSpeed = 14,
		Ability = {
			Name = "Heal Wave",
			Type = "Heal",
			Cooldown = 8,
			Value = 40, -- HP healed per ally
			Radius = 12,
			Duration = 0,
		},
	},
	Raider = {
		Id = "Raider",
		Name = "Raider",
		Tier = 2,
		Cost = 100,
		IncomeBonus = 6,
		Health = 400,
		Damage = 22,
		Armor = 3,
		MoveSpeed = 18,
		Ability = {
			Name = "Ensnare",
			Type = "Slow",
			Cooldown = 10,
			Value = 0.5, -- 50% slow factor
			Radius = 0,
			Duration = 3,
		},
	},

	-- Tier 3: Black Citadel
	Abomination = {
		Id = "Abomination",
		Name = "Abomination",
		Tier = 3,
		Cost = 250,
		IncomeBonus = 15,
		Health = 1200,
		Damage = 45,
		Armor = 3,
		MoveSpeed = 10,
		Ability = {
			Name = "Plague Cloud",
			Type = "AoEDoT",
			Cooldown = 15,
			Value = 15, -- DPS to enemies in radius
			Radius = 8,
			Duration = 5,
		},
	},
	FrostWyrm = {
		Id = "FrostWyrm",
		Name = "Frost Wyrm",
		Tier = 3,
		Cost = 400,
		IncomeBonus = 25,
		Health = 800,
		Damage = 70,
		Armor = 2,
		MoveSpeed = 14,
		Ability = {
			Name = "Frost Breath",
			Type = "AoEBurst",
			Cooldown = 12,
			Value = 80, -- burst damage
			Radius = 10,
			Duration = 2, -- freeze (stun) duration
		},
	},
	Infernal = {
		Id = "Infernal",
		Name = "Infernal",
		Tier = 3,
		Cost = 500,
		IncomeBonus = 30,
		Health = 1500,
		Damage = 55,
		Armor = 6,
		MoveSpeed = 12,
		Ability = {
			Name = "Immolation Aura",
			Type = "Aura",
			Cooldown = 0, -- always active, no cooldown
			Value = 10, -- DPS to nearby enemies
			Radius = 6,
			Duration = 0, -- permanent
		},
	},
}

return CreepData
