--!strict

local MedicalData = {}

MedicalData.HealingPotion = {
	Id = "HealingPotion",
	Name = "Healing Potion",
	Description = "Instantly restores 200 HP.",
	Cost = 50,
	Duration = 0, -- instant
	Instant = true,
	HealAmount = 200,
}

MedicalData.RegenElixir = {
	Id = "RegenElixir",
	Name = "Regen Elixir",
	Description = "+5 HP/sec for 60s.",
	Cost = 75,
	Duration = 60,
	BuffStat = "HealthRegen",
	BuffValue = 5,
}

MedicalData.ThornsBrew = {
	Id = "ThornsBrew",
	Name = "Thorns Brew",
	Description = "Reflect 10 damage to attackers for 90s.",
	Cost = 100,
	Duration = 90,
	BuffStat = "Thorns",
	BuffValue = 10,
}

MedicalData.FireWard = {
	Id = "FireWard",
	Name = "Fire Ward",
	Description = "+15 Fire Resist for 120s.",
	Cost = 80,
	Duration = 120,
	BuffStat = "FireResist",
	BuffValue = 15,
}

MedicalData.FrostWard = {
	Id = "FrostWard",
	Name = "Frost Ward",
	Description = "+15 Cold Resist for 120s.",
	Cost = 80,
	Duration = 120,
	BuffStat = "ColdResist",
	BuffValue = 15,
}

MedicalData.ShadowWard = {
	Id = "ShadowWard",
	Name = "Shadow Ward",
	Description = "+15 Shadow Resist for 120s.",
	Cost = 80,
	Duration = 120,
	BuffStat = "ShadowResist",
	BuffValue = 15,
}

MedicalData.ChaosWard = {
	Id = "ChaosWard",
	Name = "Chaos Ward",
	Description = "+15 Chaos Resist for 120s.",
	Cost = 100,
	Duration = 120,
	BuffStat = "ChaosResist",
	BuffValue = 15,
}

MedicalData.BerserkerDraught = {
	Id = "BerserkerDraught",
	Name = "Berserker Draught",
	Description = "+15 ATK for 60s.",
	Cost = 100,
	Duration = 60,
	BuffStat = "AttackDamage",
	BuffValue = 15,
}

MedicalData.IronSkinPotion = {
	Id = "IronSkinPotion",
	Name = "Iron Skin Potion",
	Description = "+8 Armor for 60s.",
	Cost = 80,
	Duration = 60,
	BuffStat = "Armor",
	BuffValue = 8,
}

return MedicalData
