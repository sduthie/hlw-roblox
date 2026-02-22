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

return Constants
