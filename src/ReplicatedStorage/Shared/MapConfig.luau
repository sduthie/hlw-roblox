--!strict

local MapConfig = {}

-- Map dimensions
MapConfig.GROUND_SIZE = Vector3.new(300, 1, 160)
MapConfig.GROUND_POSITION = Vector3.new(0, -0.5, 0)

-- Base positions (center of base structure)
MapConfig.BASE_POSITIONS = {
	[1] = Vector3.new(-130, 10, 0), -- Team 1 (blue)
	[2] = Vector3.new(130, 10, 0), -- Team 2 (red)
}

MapConfig.BASE_SIZE = Vector3.new(20, 20, 10)

-- Gate positions (in front of each base, enemy creeps must pass through)
MapConfig.GATE_POSITIONS = {
	[1] = Vector3.new(-115, 5, 0),
	[2] = Vector3.new(115, 5, 0),
}

MapConfig.GATE_SIZE = Vector3.new(4, 10, 16)

-- Creep spawn positions (where creeps appear before walking to enemy base)
MapConfig.SPAWN_POSITIONS = {
	[1] = Vector3.new(-110, 2, 0), -- Team 1 creeps spawn here
	[2] = Vector3.new(110, 2, 0), -- Team 2 creeps spawn here
}

-- Hero spawn positions (static visual placement)
MapConfig.HERO_POSITIONS = {
	[1] = Vector3.new(-120, 2, 20),
	[2] = Vector3.new(120, 2, 20),
}

-- Lane waypoints: creeps follow these sequentially toward enemy base
-- ToTeam2 = path for Team 1's creeps heading toward Team 2's base
-- ToTeam1 = path for Team 2's creeps heading toward Team 1's base
MapConfig.LANE_WAYPOINTS = {
	ToTeam2 = {
		Vector3.new(-80, 2, 8),
		Vector3.new(-40, 2, 12),
		Vector3.new(0, 2, 10),
		Vector3.new(40, 2, 12),
		Vector3.new(80, 2, 8),
		Vector3.new(115, 2, 0), -- ends at Team 2 gate
	},
	ToTeam1 = {
		Vector3.new(80, 2, -8),
		Vector3.new(40, 2, -12),
		Vector3.new(0, 2, -10),
		Vector3.new(-40, 2, -12),
		Vector3.new(-80, 2, -8),
		Vector3.new(-115, 2, 0), -- ends at Team 1 gate
	},
}

MapConfig.WAYPOINT_REACH_DISTANCE = 3

-- Team colors
MapConfig.TEAM_COLORS = {
	[1] = Color3.fromRGB(50, 100, 200), -- Blue
	[2] = Color3.fromRGB(200, 50, 50), -- Red
}

-- Debug visualization
MapConfig.SHOW_WAYPOINT_MARKERS = true
MapConfig.WAYPOINT_MARKER_SIZE = Vector3.new(2, 2, 2)
MapConfig.WAYPOINT_MARKER_TRANSPARENCY = 0.6

return MapConfig
