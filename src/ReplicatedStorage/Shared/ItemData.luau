--!strict

local Types = require(script.Parent.Types)

local ItemData: { [string]: Types.ItemDef } = {
	-- Basic items
	IronSword = {
		Id = "IronSword",
		Name = "Iron Sword",
		Description = "A sturdy blade that increases attack damage.",
		Cost = 150,
		Stats = { Damage = 10 },
	},
	ChainMail = {
		Id = "ChainMail",
		Name = "Chain Mail",
		Description = "Protective mail armor.",
		Cost = 200,
		Stats = { Armor = 3 },
	},
	BootsOfSpeed = {
		Id = "BootsOfSpeed",
		Name = "Boots of Speed",
		Description = "Increases hero movement speed.",
		Cost = 250,
		Stats = { MoveSpeed = 4 },
	},
	HealthStone = {
		Id = "HealthStone",
		Name = "Health Stone",
		Description = "A gem that bolsters vitality.",
		Cost = 300,
		Stats = { Health = 200 },
	},

	-- Advanced items
	BladeMail = {
		Id = "BladeMail",
		Name = "Blade Mail",
		Description = "Returns a portion of damage taken to the attacker.",
		Cost = 500,
		Stats = { Armor = 5, Damage = 8 },
	},
	StaffOfWizardry = {
		Id = "StaffOfWizardry",
		Name = "Staff of Wizardry",
		Description = "Empowers spells, reducing cooldowns.",
		Cost = 600,
		Stats = { Damage = 15, CooldownReduction = 10 },
	},
	CrownOfKings = {
		Id = "CrownOfKings",
		Name = "Crown of Kings",
		Description = "A regal crown that boosts all stats.",
		Cost = 1000,
		Stats = { Health = 300, Damage = 12, Armor = 4, MoveSpeed = 2 },
	},
}

return ItemData
