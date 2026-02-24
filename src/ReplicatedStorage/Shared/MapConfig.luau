--!strict

local MapConfig = {}

-- Map dimensions (wide X for the lane, long Z for the march)
MapConfig.GROUND_SIZE = Vector3.new(160, 1, 300)
MapConfig.GROUND_POSITION = Vector3.new(0, -0.5, 0)

-- Base positions (center of base structure)
-- Team 1 (blue) at top (negative Z), Team 2 (red) at bottom (positive Z)
MapConfig.BASE_POSITIONS = {
	[1] = Vector3.new(0, 10, -130), -- Team 1 (blue)
	[2] = Vector3.new(0, 10, 130), -- Team 2 (red)
}

MapConfig.BASE_SIZE = Vector3.new(20, 20, 10)

-- Gate positions (in front of each base, enemy creeps must pass through)
MapConfig.GATE_POSITIONS = {
	[1] = Vector3.new(0, 5, -115),
	[2] = Vector3.new(0, 5, 115),
}

-- Wide gate spanning the lane (wide X, tall Y, thin Z)
MapConfig.GATE_SIZE = Vector3.new(40, 10, 4)

-- Creep spawn positions (where creeps appear before walking to enemy base)
MapConfig.SPAWN_POSITIONS = {
	[1] = Vector3.new(0, 2, -105), -- Team 1 creeps spawn here
	[2] = Vector3.new(0, 2, 105), -- Team 2 creeps spawn here
}

-- Hero spawn positions (off to the side, near base)
MapConfig.HERO_POSITIONS = {
	[1] = Vector3.new(40, 2, -120),
	[2] = Vector3.new(-40, 2, 120),
}

-- Lane waypoints: creeps follow these sequentially toward enemy base
-- Vertical lane: creeps march along the Z-axis
-- ToTeam2 = path for Team 1's creeps heading toward Team 2's base (top to bottom)
-- ToTeam1 = path for Team 2's creeps heading toward Team 1's base (bottom to top)
MapConfig.LANE_WAYPOINTS = {
	ToTeam2 = {
		Vector3.new(0, 2, -80),
		Vector3.new(0, 2, -40),
		Vector3.new(0, 2, 0),
		Vector3.new(0, 2, 40),
		Vector3.new(0, 2, 80),
		Vector3.new(0, 2, 115), -- ends at Team 2 gate
	},
	ToTeam1 = {
		Vector3.new(0, 2, 80),
		Vector3.new(0, 2, 40),
		Vector3.new(0, 2, 0),
		Vector3.new(0, 2, -40),
		Vector3.new(0, 2, -80),
		Vector3.new(0, 2, -115), -- ends at Team 1 gate
	},
}

MapConfig.WAYPOINT_REACH_DISTANCE = 3

-- Team colors
MapConfig.TEAM_COLORS = {
	[1] = Color3.fromRGB(50, 100, 200), -- Blue
	[2] = Color3.fromRGB(200, 50, 50), -- Red
}

-- Shop building positions (off-lane, near each team's base)
MapConfig.SHOP_POSITIONS = {
	[1] = Vector3.new(-40, 2, -120), -- Team 1 shop (left side)
	[2] = Vector3.new(40, 2, 120), -- Team 2 shop (right side)
}

-- Lane boundaries (walls on each side)
MapConfig.LANE_HALF_WIDTH = 30
MapConfig.LANE_WALL_HEIGHT = 4
MapConfig.LANE_WALL_THICKNESS = 2

-- Debug visualization
MapConfig.SHOW_WAYPOINT_MARKERS = true
MapConfig.WAYPOINT_MARKER_SIZE = Vector3.new(2, 2, 2)
MapConfig.WAYPOINT_MARKER_TRANSPARENCY = 0.6

return MapConfig
