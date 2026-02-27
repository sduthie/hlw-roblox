--!strict

local FamiliarData = {}

FamiliarData.BabyDragon = {
	Id = "BabyDragon",
	Name = "Baby Dragon",
	Description = "A tiny dragon companion. +10 ATK.",
	Cost = 500,
	IsPremium = false,
	Stats = { Damage = 10 },
}

FamiliarData.SpiritWolf = {
	Id = "SpiritWolf",
	Name = "Spirit Wolf",
	Description = "A spectral wolf. +3 MoveSpeed.",
	Cost = 400,
	IsPremium = false,
	Stats = { MoveSpeed = 3 },
}

FamiliarData.StoneGolem = {
	Id = "StoneGolem",
	Name = "Stone Golem",
	Description = "A sturdy golem. +300 HP, +4 Armor.",
	Cost = 600,
	IsPremium = false,
	Stats = { Health = 300, Armor = 4 },
}

FamiliarData.ArcaneFairy = {
	Id = "ArcaneFairy",
	Name = "Arcane Fairy",
	Description = "A magical fairy. +100 Mana, +10% CDR.",
	Cost = 500,
	IsPremium = false,
	Stats = { Mana = 100, CooldownReduction = 10 },
}

FamiliarData.PhoenixHatchling = {
	Id = "PhoenixHatchling",
	Name = "Phoenix Hatchling",
	Description = "Premium: +15 ATK, +200 HP, +5 all resists.",
	Cost = 0,
	IsPremium = true,
	RobuxCost = 199,
	Stats = { Damage = 15, Health = 200, FireResist = 5, ColdResist = 5, ShadowResist = 5, ChaosResist = 5 },
}

FamiliarData.VoidSerpent = {
	Id = "VoidSerpent",
	Name = "Void Serpent",
	Description = "Premium: +25 ATK, +5 MoveSpeed.",
	Cost = 0,
	IsPremium = true,
	RobuxCost = 299,
	Stats = { Damage = 25, MoveSpeed = 5 },
}

FamiliarData.ResurrectionPotion = {
	Id = "ResurrectionPotion",
	Name = "Resurrection Potion",
	Description = "Premium: Instantly revive when dead!",
	Cost = 0,
	IsPremium = true,
	RobuxCost = 49,
	IsConsumable = true,
	Stats = {},
}

return FamiliarData
