--!strict

export type HeroId = string
export type CreepId = string
export type ItemId = string
export type TeamId = number

export type HeroDef = {
	Id: HeroId,
	Name: string,
	Description: string,
	BaseHealth: number,
	BaseDamage: number,
	BaseArmor: number,
	MoveSpeed: number,
	Abilities: { AbilityDef },
}

export type AbilityDef = {
	Name: string,
	Description: string,
	Cooldown: number,
	ManaCost: number,
	UnlockLevel: number,
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
