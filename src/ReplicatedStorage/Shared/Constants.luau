--!strict

local Constants = {}

-- Teams
Constants.TEAM_COUNT = 2
Constants.MAX_PLAYERS_PER_TEAM = 4

-- Base
Constants.BASE_MAX_LIVES = 100

-- Income
Constants.INCOME_INTERVAL = 17 -- seconds between income ticks
Constants.STARTING_GOLD = 250
Constants.STARTING_INCOME = 10
Constants.INCOME_PER_CREEP_COST = 1 -- income gained per gold spent on creeps

-- Hero
Constants.HERO_MAX_LEVEL = 25
Constants.HERO_XP_PER_LEVEL = {
	100,
	120,
	150,
	190,
	240,
	300,
	370,
	450,
	540,
	640,
	750,
	870,
	1000,
	1140,
	1290,
	1450,
	1620,
	1800,
	1990,
	2190,
	2400,
	2620,
	2850,
	3090,
	3340,
}
Constants.HERO_ABILITY_UNLOCK_LEVELS = { 1, 3, 5, 10 } -- levels at which abilities unlock
Constants.HERO_PICK_TIME = 30 -- seconds for hero selection

-- Creep Tiers (unlocked by town hall level)
Constants.TOWN_HALL_TIERS = {
	"TownHall", -- tier 1: basic creeps
	"Stronghold", -- tier 2: mid-tier creeps
	"BlackCitadel", -- tier 3: elite creeps
}
Constants.TOWN_HALL_UPGRADE_COST = { 0, 1500, 5000 }

-- Game Phases
Constants.PHASE_LOBBY = "Lobby"
Constants.PHASE_HERO_SELECT = "HeroSelect"
Constants.PHASE_PLAYING = "Playing"
Constants.PHASE_GAME_OVER = "GameOver"

-- Timers
Constants.LOBBY_COUNTDOWN = 10 -- seconds after minimum players joined
Constants.GAME_OVER_DISPLAY_TIME = 10

-- Pathing
Constants.CREEP_SPAWN_INTERVAL = 1.5 -- seconds between individual creeps in a wave
Constants.WAVE_SIZE = 4 -- number of creeps per send

-- Shop
Constants.SHOP_CATEGORIES = { "Creeps", "Items", "Upgrades" }

-- Balance: Base Gate
Constants.GATE_BASE_DPS = 25
Constants.GATE_RANGE = 40
Constants.GATE_MAX_HP = 500

-- Balance: Tiered Base Damage (per creep reaching base, indexed by tier)
Constants.BASE_DAMAGE_BY_TIER = { 1, 3, 7 }

-- Balance: Kill Bounty (defending team earns % of creep cost when their gate/hero kills a creep)
Constants.KILL_BOUNTY_PERCENT = 0.25

-- Balance: Momentum Streaks (consecutive waves with at least 1 survivor)
Constants.STREAK_THRESHOLD_1 = 3 -- +1 bonus damage per creep
Constants.STREAK_BONUS_1 = 1
Constants.STREAK_THRESHOLD_2 = 5 -- +2 bonus damage per creep
Constants.STREAK_BONUS_2 = 2

-- Balance: TownHall Passives
Constants.STRONGHOLD_GATE_BONUS_DPS = 10 -- T2: your gate gains +10 DPS
Constants.BLACK_CITADEL_CREEP_HP_BONUS = 0.20 -- T3: your creeps gain +20% HP

-- Creep Movement
Constants.WAYPOINT_REACH_DISTANCE = 3
Constants.CREEP_UPDATE_RATE = 10 -- server updates per second

-- Items
Constants.MAX_ITEMS_PER_PLAYER = 6

-- Hero Combat
Constants.HERO_ATTACK_RANGE = 12
Constants.HERO_ATTACK_RATE = 1.0 -- seconds between auto-attacks
Constants.HERO_COMBAT_UPDATE_RATE = 10 -- Hz, match creep loop

-- Hero XP & Bounty
Constants.HERO_XP_PER_CREEP_KILL = 30
Constants.HERO_KILL_BOUNTY_PERCENT = 0.25

-- Level Scaling
Constants.HP_PER_LEVEL = 20
Constants.DAMAGE_PER_LEVEL = 2
Constants.ARMOR_PER_LEVEL = 0.5

-- Mana
Constants.BASE_MANA = 100
Constants.MANA_REGEN = 1 -- per second
Constants.MANA_PER_LEVEL = 10

return Constants
