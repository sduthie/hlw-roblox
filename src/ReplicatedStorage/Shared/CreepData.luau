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
	},
}

return CreepData
