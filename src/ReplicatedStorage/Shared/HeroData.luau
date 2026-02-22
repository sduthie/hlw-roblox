--!strict

local Types = require(script.Parent.Types)

local HeroData: { [string]: Types.HeroDef } = {
	Paladin = {
		Id = "Paladin",
		Name = "Paladin",
		Description = "A holy warrior who heals allies and smites foes.",
		BaseHealth = 800,
		BaseDamage = 35,
		BaseArmor = 5,
		MoveSpeed = 16,
		Abilities = {
			{
				Name = "Holy Light",
				Description = "Heals a friendly unit or damages undead.",
				Cooldown = 8,
				ManaCost = 65,
				UnlockLevel = 1,
			},
			{
				Name = "Divine Shield",
				Description = "Becomes invulnerable for a short duration.",
				Cooldown = 30,
				ManaCost = 0,
				UnlockLevel = 3,
			},
			{
				Name = "Devotion Aura",
				Description = "Increases armor of nearby friendly units.",
				Cooldown = 0,
				ManaCost = 0,
				UnlockLevel = 5,
			},
			{
				Name = "Resurrection",
				Description = "Revives nearby fallen creeps to fight again.",
				Cooldown = 120,
				ManaCost = 200,
				UnlockLevel = 10,
			},
		},
	},

	Archmage = {
		Id = "Archmage",
		Name = "Archmage",
		Description = "A master of arcane magic with powerful AoE spells.",
		BaseHealth = 550,
		BaseDamage = 45,
		BaseArmor = 2,
		MoveSpeed = 16,
		Abilities = {
			{
				Name = "Blizzard",
				Description = "Calls down waves of ice dealing AoE damage.",
				Cooldown = 10,
				ManaCost = 75,
				UnlockLevel = 1,
			},
			{
				Name = "Summon Elemental",
				Description = "Summons a water elemental to fight.",
				Cooldown = 60,
				ManaCost = 125,
				UnlockLevel = 3,
			},
			{
				Name = "Brilliance Aura",
				Description = "Increases mana regeneration of nearby allies.",
				Cooldown = 0,
				ManaCost = 0,
				UnlockLevel = 5,
			},
			{
				Name = "Mass Teleport",
				Description = "Teleports hero and nearby units to target location.",
				Cooldown = 90,
				ManaCost = 100,
				UnlockLevel = 10,
			},
		},
	},

	DeathKnight = {
		Id = "DeathKnight",
		Name = "Death Knight",
		Description = "A dark warrior who drains life and raises the dead.",
		BaseHealth = 750,
		BaseDamage = 40,
		BaseArmor = 4,
		MoveSpeed = 16,
		Abilities = {
			{
				Name = "Death Coil",
				Description = "Deals damage to a living unit or heals undead.",
				Cooldown = 6,
				ManaCost = 75,
				UnlockLevel = 1,
			},
			{
				Name = "Unholy Aura",
				Description = "Increases movement speed and life regeneration.",
				Cooldown = 0,
				ManaCost = 0,
				UnlockLevel = 3,
			},
			{
				Name = "Death Pact",
				Description = "Sacrifices a friendly unit to heal the Death Knight.",
				Cooldown = 45,
				ManaCost = 50,
				UnlockLevel = 5,
			},
			{
				Name = "Animate Dead",
				Description = "Raises corpses to fight as skeletons.",
				Cooldown = 120,
				ManaCost = 175,
				UnlockLevel = 10,
			},
		},
	},

	ShadowHunter = {
		Id = "ShadowHunter",
		Name = "Shadow Hunter",
		Description = "A cunning troll who hexes enemies and heals allies.",
		BaseHealth = 650,
		BaseDamage = 38,
		BaseArmor = 3,
		MoveSpeed = 18,
		Abilities = {
			{
				Name = "Healing Wave",
				Description = "Bouncing heal that heals multiple friendly units.",
				Cooldown = 8,
				ManaCost = 90,
				UnlockLevel = 1,
			},
			{
				Name = "Hex",
				Description = "Transforms an enemy into a critter, disabling them.",
				Cooldown = 15,
				ManaCost = 70,
				UnlockLevel = 3,
			},
			{
				Name = "Serpent Ward",
				Description = "Places a ward that attacks nearby enemies.",
				Cooldown = 12,
				ManaCost = 50,
				UnlockLevel = 5,
			},
			{
				Name = "Big Bad Voodoo",
				Description = "Makes all nearby friendly units invulnerable.",
				Cooldown = 150,
				ManaCost = 200,
				UnlockLevel = 10,
			},
		},
	},

	Blademaster = {
		Id = "Blademaster",
		Name = "Blademaster",
		Description = "A swift swordsman with critical strikes and illusions.",
		BaseHealth = 700,
		BaseDamage = 50,
		BaseArmor = 3,
		MoveSpeed = 20,
		Abilities = {
			{
				Name = "Wind Walk",
				Description = "Become invisible and move faster. Next attack deals bonus damage.",
				Cooldown = 10,
				ManaCost = 75,
				UnlockLevel = 1,
			},
			{
				Name = "Mirror Image",
				Description = "Creates illusions to confuse enemies.",
				Cooldown = 20,
				ManaCost = 80,
				UnlockLevel = 3,
			},
			{
				Name = "Critical Strike",
				Description = "Passive chance to deal double damage.",
				Cooldown = 0,
				ManaCost = 0,
				UnlockLevel = 5,
			},
			{
				Name = "Bladestorm",
				Description = "Spins dealing massive AoE damage, immune to magic.",
				Cooldown = 120,
				ManaCost = 150,
				UnlockLevel = 10,
			},
		},
	},
}

return HeroData
