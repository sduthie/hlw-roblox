--!strict

local MapConfig = {}

-- Map dimensions (wide X for two lanes, long Z for the march)
MapConfig.GROUND_SIZE = Vector3.new(380, 8, 300)
MapConfig.GROUND_POSITION = Vector3.new(0, -4, 0)

-- Lane centers
-- Team 1 (blue) owns the LEFT lane, Team 2 (red) owns the RIGHT lane
-- Each lane is ~90 studs wide (wall to divider)
MapConfig.LEFT_LANE_X = -47
MapConfig.RIGHT_LANE_X = 47

-- Both bases sit at the BOTTOM (positive Z) of their own lane.
-- Your hero defends here; enemy purchased creeps march DOWN toward it.
MapConfig.BASE_POSITIONS = {
	[1] = Vector3.new(-47, 10, 130), -- Team 1 base (bottom-left)
	[2] = Vector3.new(47, 10, 130), -- Team 2 base (bottom-right)
}

MapConfig.BASE_SIZE = Vector3.new(20, 20, 14)

-- Gates sit just in front of each base (defending it)
MapConfig.GATE_POSITIONS = {
	[1] = Vector3.new(-47, 5, 115), -- Team 1 gate (bottom-left)
	[2] = Vector3.new(47, 5, 115), -- Team 2 gate (bottom-right)
}

-- Gate spans one lane width
MapConfig.GATE_SIZE = Vector3.new(80, 10, 4)

-- Attack spawn: where PURCHASED creeps appear (top of the enemy's lane, march DOWN)
-- Keyed by the TARGET team being attacked
MapConfig.ATTACK_SPAWN_POSITIONS = {
	[1] = Vector3.new(-47, 2, -105), -- Creeps attacking Team 1 spawn at top of left lane
	[2] = Vector3.new(47, 2, -105), -- Creeps attacking Team 2 spawn at top of right lane
}

-- Defense spawn: where AI DEFENSIVE waves appear (bottom of own lane, march UP)
-- Keyed by the DEFENDING team
MapConfig.DEFEND_SPAWN_POSITIONS = {
	[1] = Vector3.new(-47, 2, 105), -- Team 1 defense spawns at bottom of left lane
	[2] = Vector3.new(47, 2, 105), -- Team 2 defense spawns at bottom of right lane
}

-- Hero spawn positions — 5 per team spread across the lane width
-- Used for initial character spawn and respawn
MapConfig.HERO_SPAWN_POINTS = {
	[1] = {
		Vector3.new(-75, 2, 80),
		Vector3.new(-61, 2, 80),
		Vector3.new(-47, 2, 80),
		Vector3.new(-33, 2, 80),
		Vector3.new(-19, 2, 80),
	},
	[2] = {
		Vector3.new(19, 2, 80),
		Vector3.new(33, 2, 80),
		Vector3.new(47, 2, 80),
		Vector3.new(61, 2, 80),
		Vector3.new(75, 2, 80),
	},
}

-- Legacy single hero position (used for fallback / hero models)
MapConfig.HERO_POSITIONS = {
	[1] = Vector3.new(-47, 2, 80),
	[2] = Vector3.new(47, 2, 80),
}

-- Lane waypoints
-- Attack paths march TOP->BOTTOM (negative Z -> positive Z) toward the target base
-- Defense paths march BOTTOM->TOP (positive Z -> negative Z) to intercept attackers
MapConfig.LANE_WAYPOINTS = {
	-- Purchased creeps attacking Team 1 (down left lane)
	AttackTeam1 = {
		Vector3.new(-47, 2, -80),
		Vector3.new(-47, 2, -40),
		Vector3.new(-47, 2, 0),
		Vector3.new(-47, 2, 40),
		Vector3.new(-47, 2, 80),
		Vector3.new(-47, 2, 115), -- ends at Team 1 gate
	},
	-- Purchased creeps attacking Team 2 (down right lane)
	AttackTeam2 = {
		Vector3.new(47, 2, -80),
		Vector3.new(47, 2, -40),
		Vector3.new(47, 2, 0),
		Vector3.new(47, 2, 40),
		Vector3.new(47, 2, 80),
		Vector3.new(47, 2, 115), -- ends at Team 2 gate
	},
	-- Team 1's auto-defense (up left lane from base area)
	DefendTeam1 = {
		Vector3.new(-47, 2, 80),
		Vector3.new(-47, 2, 40),
		Vector3.new(-47, 2, 0),
		Vector3.new(-47, 2, -40),
		Vector3.new(-47, 2, -80),
	},
	-- Team 2's auto-defense (up right lane from base area)
	DefendTeam2 = {
		Vector3.new(47, 2, 80),
		Vector3.new(47, 2, 40),
		Vector3.new(47, 2, 0),
		Vector3.new(47, 2, -40),
		Vector3.new(47, 2, -80),
	},
}

MapConfig.WAYPOINT_REACH_DISTANCE = 3

-- Team colors
MapConfig.TEAM_COLORS = {
	[1] = Color3.fromRGB(50, 100, 200), -- Blue
	[2] = Color3.fromRGB(200, 50, 50), -- Red
}

-- Shop building positions (legacy single shop, kept for backward compatibility)
MapConfig.SHOP_POSITIONS = {
	[1] = Vector3.new(-100, 2, 120), -- Team 1 shop (far left of base)
	[2] = Vector3.new(100, 2, 120), -- Team 2 shop (far right of base)
}

-- Multiple shop buildings behind each team's nexus
-- Each shop type has a position offset from the base position
MapConfig.SHOP_BUILDINGS = {
	{
		Type = "Gear",
		Label = "ARMORY",
		LabelColor = Color3.fromRGB(200, 180, 60),
		BodyColor = Color3.fromRGB(120, 100, 40),
		Offsets = {
			[1] = Vector3.new(-30, 0, 18),
			[2] = Vector3.new(-30, 0, 18),
		},
	},
	{
		Type = "Medical",
		Label = "APOTHECARY",
		LabelColor = Color3.fromRGB(80, 200, 120),
		BodyColor = Color3.fromRGB(40, 100, 60),
		Offsets = {
			[1] = Vector3.new(-15, 0, 22),
			[2] = Vector3.new(-15, 0, 22),
		},
	},
	{
		Type = "Familiar",
		Label = "MENAGERIE",
		LabelColor = Color3.fromRGB(180, 100, 220),
		BodyColor = Color3.fromRGB(80, 40, 110),
		Offsets = {
			[1] = Vector3.new(0, 0, 24),
			[2] = Vector3.new(0, 0, 24),
		},
	},
	{
		Type = "Upgrades",
		Label = "FORGE",
		LabelColor = Color3.fromRGB(200, 120, 60),
		BodyColor = Color3.fromRGB(100, 60, 30),
		Offsets = {
			[1] = Vector3.new(15, 0, 22),
			[2] = Vector3.new(15, 0, 22),
		},
	},
	{
		Type = "Creeps",
		Label = "BARRACKS",
		LabelColor = Color3.fromRGB(200, 60, 60),
		BodyColor = Color3.fromRGB(100, 40, 40),
		Offsets = {
			[1] = Vector3.new(30, 0, 18),
			[2] = Vector3.new(30, 0, 18),
		},
	},
}

-- Lane boundaries
-- Each lane is ~90 studs wide (wall at edge, divider at center)
MapConfig.LANE_HALF_WIDTH = 93
MapConfig.LANE_WALL_HEIGHT = 4
MapConfig.LANE_WALL_THICKNESS = 2

-- Healing wells
-- Behind the base/nexus (higher Z = further back)
MapConfig.HEALING_WELL_POSITIONS = {
	[1] = Vector3.new(-47, 2, 140),
	[2] = Vector3.new(47, 2, 140),
}
MapConfig.HEALING_WELL_RADIUS = 15
MapConfig.HEALING_WELL_HPS = 40 -- health per second
MapConfig.HEALING_WELL_MPS = 15 -- mana per second
MapConfig.HEALING_WELL_SIZE = Vector3.new(8, 3, 8)

-- Debug visualization
MapConfig.SHOW_WAYPOINT_MARKERS = true
MapConfig.WAYPOINT_MARKER_SIZE = Vector3.new(2, 2, 2)
MapConfig.WAYPOINT_MARKER_TRANSPARENCY = 0.6

return MapConfig
