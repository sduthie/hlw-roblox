--!strict

local Types = require(script.Parent.Types)

local ItemData: { [string]: Types.ItemDef } = {
	------------------------------------------------------------------------
	-- Tier 1: Basic (100-300g) — single stat focus
	------------------------------------------------------------------------
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
	ManaCrystal = {
		Id = "ManaCrystal",
		Name = "Mana Crystal",
		Description = "A glowing crystal that expands mana reserves.",
		Cost = 200,
		Stats = { Mana = 75 },
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

	------------------------------------------------------------------------
	-- Tier 2: Mid-tier (400-800g) — dual stats
	------------------------------------------------------------------------
	CloakOfShadows = {
		Id = "CloakOfShadows",
		Name = "Cloak of Shadows",
		Description = "A dark cloak granting evasion and swiftness.",
		Cost = 450,
		Stats = { Armor = 3, MoveSpeed = 3 },
	},
	BladeMail = {
		Id = "BladeMail",
		Name = "Blade Mail",
		Description = "Returns a portion of damage taken to the attacker.",
		Cost = 500,
		Stats = { Armor = 5, Damage = 8 },
	},
	ArcaneRing = {
		Id = "ArcaneRing",
		Name = "Arcane Ring",
		Description = "Channels arcane energy to reduce cooldowns.",
		Cost = 500,
		Stats = { Mana = 75, CooldownReduction = 5 },
	},
	VampiricMask = {
		Id = "VampiricMask",
		Name = "Vampiric Mask",
		Description = "Drains life force from enemies struck.",
		Cost = 550,
		Stats = { Damage = 12, Health = 100 },
	},
	StaffOfWizardry = {
		Id = "StaffOfWizardry",
		Name = "Staff of Wizardry",
		Description = "Empowers spells, reducing cooldowns.",
		Cost = 600,
		Stats = { Damage = 15, CooldownReduction = 10 },
	},
	WarBoots = {
		Id = "WarBoots",
		Name = "War Boots",
		Description = "Heavy boots forged for battle marches.",
		Cost = 650,
		Stats = { MoveSpeed = 5, Health = 150 },
	},

	------------------------------------------------------------------------
	-- Tier 3: Premium (1000-2000g) — powerful multi-stat
	------------------------------------------------------------------------
	CrownOfKings = {
		Id = "CrownOfKings",
		Name = "Crown of Kings",
		Description = "A regal crown that boosts all stats.",
		Cost = 1000,
		Stats = { Health = 300, Damage = 12, Armor = 4, MoveSpeed = 2 },
	},
	ScepterOfPower = {
		Id = "ScepterOfPower",
		Name = "Scepter of Power",
		Description = "Amplifies all spells with raw arcane might.",
		Cost = 1200,
		Stats = { Damage = 25, CooldownReduction = 15, Mana = 100 },
	},
	TitansPlate = {
		Id = "TitansPlate",
		Name = "Titan's Plate",
		Description = "Armor forged from the bones of ancient titans.",
		Cost = 1500,
		Stats = { Health = 600, Armor = 8 },
	},
	VoidBlade = {
		Id = "VoidBlade",
		Name = "Void Blade",
		Description = "A blade that cuts through dimensions.",
		Cost = 1800,
		Stats = { Damage = 40, MoveSpeed = 5 },
	},
	DivineAegis = {
		Id = "DivineAegis",
		Name = "Divine Aegis",
		Description = "Holy shield blessed by the gods. Grants a damage-absorbing barrier.",
		Cost = 2000,
		Stats = { Health = 400, Armor = 6, CooldownReduction = 10, Shield = 150 },
	},

	------------------------------------------------------------------------
	-- Shield items
	------------------------------------------------------------------------
	MagicBuckler = {
		Id = "MagicBuckler",
		Name = "Magic Buckler",
		Description = "An enchanted shield that absorbs damage. Regenerates after 5s.",
		Cost = 350,
		Stats = { Shield = 80, Armor = 2 },
	},
	AetherBarrier = {
		Id = "AetherBarrier",
		Name = "Aether Barrier",
		Description = "A shimmering barrier of pure energy. Absorbs heavy blows.",
		Cost = 800,
		Stats = { Shield = 200, Health = 100 },
	},
}

return ItemData
