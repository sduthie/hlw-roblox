--!strict

export type HeroId = string
export type CreepId = string
export type ItemId = string
export type TeamId = number

export type GearPieceDef = {
	Name: string,
	PartType: string, -- "Block" | "Ball" | "Cylinder" | "Wedge"
	Size: Vector3,
	Offset: CFrame,
	Color: Color3,
	Material: Enum.Material,
	Transparency: number?,
	AttachTo: string?, -- body part name to weld to (default: HumanoidRootPart)
}

export type WeaponToolDef = {
	Name: string,
	HandleSize: Vector3,
	HandleColor: Color3,
	HandleMaterial: Enum.Material,
	BladeSize: Vector3?,
	BladeColor: Color3?,
	BladeMaterial: Enum.Material?,
	BladeOffset: CFrame?,
	GripPos: Vector3?,
}

export type HeroAppearanceDef = {
	BodyColors: {
		HeadColor3: Color3,
		TorsoColor3: Color3,
		LeftArmColor3: Color3,
		RightArmColor3: Color3,
		LeftLegColor3: Color3,
		RightLegColor3: Color3,
	},
	GearPieces: { GearPieceDef },
	WeaponTool: WeaponToolDef?,
}

export type HeroDef = {
	Id: HeroId,
	Name: string,
	Description: string,
	BaseHealth: number,
	BaseDamage: number,
	BaseArmor: number,
	MoveSpeed: number,
	Abilities: { AbilityDef },
	Appearance: HeroAppearanceDef?,
}

export type AbilityDef = {
	Name: string,
	Description: string,
	Cooldown: number,
	ManaCost: number,
	UnlockLevel: number,
	-- Combat effect fields (nil = unimplemented ability)
	Type: string?, -- "Damage"|"Heal"|"Buff"|"SelfBuff"|"Ward"|"Stun"
	IsPassive: boolean?,
	Range: number?,
	Radius: number?,
	Value: number?,
	Duration: number?,
	DamagePerTick: number?,
	TickInterval: number?,
}

export type BuffInstance = {
	Name: string,
	StatKey: string,
	Value: number,
	ExpiresAt: number,
}

export type HeroCombatState = {
	MaxHealth: number,
	Mana: number,
	MaxMana: number,
	AttackDamage: number,
	Armor: number,
	MoveSpeed: number,
	CooldownReduction: number,
	AttackRange: number,
	AttackCooldown: number,
	LastAttackTime: number,
	Buffs: { BuffInstance },
}

export type CreepDef = {
	Id: CreepId,
	Name: string,
	Tier: number,
	Cost: number,
	IncomeBonus: number,
	Health: number,
	Damage: number,
	Armor: number,
	MoveSpeed: number,
}

export type ItemDef = {
	Id: ItemId,
	Name: string,
	Description: string,
	Cost: number,
	Stats: { [string]: number },
}

export type PlayerState = {
	Gold: number,
	Income: number,
	TownHallTier: number,
	HeroId: HeroId?,
	HeroLevel: number,
	HeroXP: number,
	Items: { ItemId },
	TeamId: TeamId,
}

export type GameState = {
	Phase: string,
	Timer: number,
	TeamLives: { [TeamId]: number },
	Players: { [number]: PlayerState }, -- keyed by Player.UserId
}

export type CreepInstance = {
	Id: number,
	CreepId: CreepId,
	OwnerId: number, -- Player.UserId who sent this creep
	TeamId: TeamId,
	TargetTeamId: TeamId,
	LaneIndex: number,
	WaypointIndex: number,
	Position: Vector3,
	Health: number,
	MaxHealth: number,
	Model: Model?,
}

export type SaveData = {
	Wins: number,
	Losses: number,
	GamesPlayed: number,
	FavoriteHero: string,
	TotalCreepsSent: number,
	TotalGoldEarned: number,
	_sessionLock: string?,
	_saveVersion: number,
}

return nil
