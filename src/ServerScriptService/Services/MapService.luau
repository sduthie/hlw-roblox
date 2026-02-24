--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig)

local MapService = Knit.CreateService({
	Name = "MapService",
	Client = {},
})

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function createPart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	for key, value in props do
		if key == "Parent" then
			continue -- set Parent last
		end
		(part :: any)[key] = value
	end

	if props.Parent then
		part.Parent = props.Parent
	end

	return part
end

local function createBillboardHealthGui(parent: Part, maxHP: number): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthDisplay"
	gui.Size = UDim2.new(0, 120, 0, 40)
	gui.StudsOffset = Vector3.new(0, 7, 0)
	gui.AlwaysOnTop = true
	gui.Parent = parent

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.new(1, 0, 0.5, 0)
	background.Position = UDim2.new(0, 0, 0.25, 0)
	background.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	background.BorderSizePixel = 0
	background.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = background

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(0, 200, 80)
	fill.BorderSizePixel = 0
	fill.Parent = background

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = fill

	local label = Instance.new("TextLabel")
	label.Name = "HPLabel"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = tostring(maxHP) .. " / " .. tostring(maxHP)
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = background

	return gui
end

-- ---------------------------------------------------------------------------
-- Map building
-- ---------------------------------------------------------------------------

function MapService:_buildMap()
	-- Clean up any existing map folder
	local existingMap = workspace:FindFirstChild("Map")
	if existingMap then
		existingMap:Destroy()
	end

	local mapFolder = Instance.new("Folder")
	mapFolder.Name = "Map"
	mapFolder.Parent = workspace

	-- 1. Ground plane
	createPart({
		Name = "Ground",
		Size = MapConfig.GROUND_SIZE,
		Position = MapConfig.GROUND_POSITION,
		Color = Color3.fromRGB(76, 153, 76), -- Forest green
		Material = Enum.Material.Grass,
		CanCollide = true,
		Parent = mapFolder,
	})

	-- 2. Two base structures
	for teamId = 1, Constants.TEAM_COUNT do
		local basePart = createPart({
			Name = "Base_Team" .. tostring(teamId),
			Size = MapConfig.BASE_SIZE,
			Position = MapConfig.BASE_POSITIONS[teamId],
			Color = MapConfig.TEAM_COLORS[teamId],
			Material = Enum.Material.SmoothPlastic,
			CanCollide = true,
			Parent = mapFolder,
		})
		CollectionService:AddTag(basePart, "Base")
		basePart:SetAttribute("TeamId", teamId)
	end

	-- 3. Two gates
	for teamId = 1, Constants.TEAM_COUNT do
		local teamColor = MapConfig.TEAM_COLORS[teamId]
		-- Lighter version of team color for gate
		local lighterColor =
			Color3.new(math.min(1, teamColor.R + 0.3), math.min(1, teamColor.G + 0.3), math.min(1, teamColor.B + 0.3))

		local gatePart = createPart({
			Name = "Gate_Team" .. tostring(teamId),
			Size = MapConfig.GATE_SIZE,
			Position = MapConfig.GATE_POSITIONS[teamId],
			Color = lighterColor,
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.3,
			CanCollide = true,
			Parent = mapFolder,
		})
		CollectionService:AddTag(gatePart, "Gate")
		gatePart:SetAttribute("TeamId", teamId)
		gatePart:SetAttribute("Health", Constants.GATE_MAX_HP)
		gatePart:SetAttribute("DPS", Constants.GATE_BASE_DPS)

		-- Add BillboardGui health display
		createBillboardHealthGui(gatePart, Constants.GATE_MAX_HP)
	end

	-- 4. Creep spawn markers
	for teamId = 1, Constants.TEAM_COUNT do
		createPart({
			Name = "CreepSpawn_Team" .. tostring(teamId),
			Size = Vector3.new(4, 1, 4),
			Position = MapConfig.SPAWN_POSITIONS[teamId],
			Color = MapConfig.TEAM_COLORS[teamId],
			Transparency = 0.5,
			CanCollide = false,
			Parent = mapFolder,
		})
	end

	-- 5. Lane waypoint markers (debug visualization)
	if MapConfig.SHOW_WAYPOINT_MARKERS then
		local waypointFolder = Instance.new("Folder")
		waypointFolder.Name = "Waypoints"
		waypointFolder.Parent = mapFolder

		local laneNames = { "ToTeam2", "ToTeam1" }
		for _, laneName in laneNames do
			local waypoints = MapConfig.LANE_WAYPOINTS[laneName]
			if waypoints then
				for i, position in waypoints do
					local marker = Instance.new("Part")
					marker.Name = laneName .. "_WP" .. tostring(i)
					marker.Shape = Enum.PartType.Ball
					marker.Size = MapConfig.WAYPOINT_MARKER_SIZE
					marker.Position = position
					marker.Anchored = true
					marker.CanCollide = false
					marker.Transparency = MapConfig.WAYPOINT_MARKER_TRANSPARENCY
					marker.Material = Enum.Material.Neon
					marker.Color = Color3.fromRGB(255, 255, 255)
					marker.TopSurface = Enum.SurfaceType.Smooth
					marker.BottomSurface = Enum.SurfaceType.Smooth
					marker.Parent = waypointFolder
				end
			end
		end
	end

	-- 6. Hero spawn markers
	for teamId = 1, Constants.TEAM_COUNT do
		createPart({
			Name = "HeroSpawn_Team" .. tostring(teamId),
			Size = Vector3.new(4, 1, 4),
			Position = MapConfig.HERO_POSITIONS[teamId],
			Color = MapConfig.TEAM_COLORS[teamId],
			Transparency = 1,
			CanCollide = false,
			Parent = mapFolder,
		})
	end

	-- 7. Shop buildings
	self:_createShopBuildings(mapFolder)

	-- 8. Lane boundary walls
	self:_createLaneWalls(mapFolder)

	-- 9. Lane path visualization
	self:_createLanePaths(mapFolder)
end

-- ---------------------------------------------------------------------------
-- Shop buildings
-- ---------------------------------------------------------------------------

function MapService:_createShopBuildings(mapFolder: Folder)
	local shopFolder = Instance.new("Folder")
	shopFolder.Name = "Shops"
	shopFolder.Parent = mapFolder

	for teamId = 1, Constants.TEAM_COUNT do
		local pos = MapConfig.SHOP_POSITIONS[teamId]
		local teamColor = MapConfig.TEAM_COLORS[teamId]

		-- Main building body
		local building = createPart({
			Name = "Shop_Team" .. tostring(teamId),
			Size = Vector3.new(10, 8, 8),
			Position = pos + Vector3.new(0, 4, 0),
			Color = teamColor,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = true,
			Parent = shopFolder,
		})
		CollectionService:AddTag(building, "Shop")
		building:SetAttribute("TeamId", teamId)

		-- Roof (wider, darker)
		local darkerColor = Color3.new(
			teamColor.R * 0.6,
			teamColor.G * 0.6,
			teamColor.B * 0.6
		)
		createPart({
			Name = "Roof_Team" .. tostring(teamId),
			Size = Vector3.new(12, 1.5, 10),
			Position = pos + Vector3.new(0, 8.75, 0),
			Color = darkerColor,
			Material = Enum.Material.Wood,
			CanCollide = false,
			Parent = shopFolder,
		})

		-- Counter (front ledge)
		createPart({
			Name = "Counter_Team" .. tostring(teamId),
			Size = Vector3.new(8, 1, 2),
			Position = pos + Vector3.new(0, 2, 5),
			Color = Color3.fromRGB(139, 90, 43),
			Material = Enum.Material.Wood,
			CanCollide = true,
			Parent = shopFolder,
		})

		-- Gold accent trim along roof edge
		createPart({
			Name = "Trim_Team" .. tostring(teamId),
			Size = Vector3.new(12, 0.4, 10),
			Position = pos + Vector3.new(0, 8, 0),
			Color = Color3.fromRGB(255, 215, 0),
			Material = Enum.Material.Neon,
			Transparency = 0.4,
			CanCollide = false,
			Parent = shopFolder,
		})

		-- Billboard sign with "SHOP" text
		local signGui = Instance.new("BillboardGui")
		signGui.Name = "ShopSign"
		signGui.Size = UDim2.fromOffset(120, 40)
		signGui.StudsOffset = Vector3.new(0, 6, 0)
		signGui.AlwaysOnTop = true
		signGui.Parent = building

		local signLabel = Instance.new("TextLabel")
		signLabel.Size = UDim2.fromScale(1, 1)
		signLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
		signLabel.BackgroundTransparency = 0.3
		signLabel.Text = "SHOP"
		signLabel.Font = Enum.Font.GothamBold
		signLabel.TextSize = 28
		signLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
		signLabel.TextStrokeTransparency = 0.3
		signLabel.TextStrokeColor3 = Color3.fromRGB(100, 80, 0)
		signLabel.Parent = signGui

		local signCorner = Instance.new("UICorner")
		signCorner.CornerRadius = UDim.new(0, 6)
		signCorner.Parent = signLabel

		-- ProximityPrompt for interaction
		local prompt = Instance.new("ProximityPrompt")
		prompt.ObjectText = "Shop"
		prompt.ActionText = "Open Shop"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 14
		prompt.KeyboardKeyCode = Enum.KeyCode.F
		prompt.Parent = building
	end
end

-- ---------------------------------------------------------------------------
-- Lane boundary walls
-- ---------------------------------------------------------------------------

function MapService:_createLaneWalls(mapFolder: Folder)
	local wallFolder = Instance.new("Folder")
	wallFolder.Name = "LaneWalls"
	wallFolder.Parent = mapFolder

	local halfWidth = MapConfig.LANE_HALF_WIDTH
	local wallHeight = MapConfig.LANE_WALL_HEIGHT
	local wallThickness = MapConfig.LANE_WALL_THICKNESS

	-- Walls run along the Z-axis for the full ground length
	local groundZ = MapConfig.GROUND_SIZE.Z
	local wallLength = groundZ - 20 -- slightly shorter than ground

	for _, xPos in { -halfWidth, halfWidth } do
		createPart({
			Name = "LaneWall_X" .. tostring(xPos),
			Size = Vector3.new(wallThickness, wallHeight, wallLength),
			Position = Vector3.new(xPos, wallHeight / 2, 0),
			Color = Color3.fromRGB(120, 110, 100),
			Material = Enum.Material.Brick,
			CanCollide = true,
			Parent = wallFolder,
		})
	end
end

-- ---------------------------------------------------------------------------
-- Lane path visualization
-- ---------------------------------------------------------------------------

function MapService:_createLanePaths(mapFolder: Folder)
	local laneFolder = Instance.new("Folder")
	laneFolder.Name = "LanePaths"
	laneFolder.Parent = mapFolder

	local laneTeamMap = {
		ToTeam2 = 1, -- Team 1's creeps walk this path (colored blue)
		ToTeam1 = 2, -- Team 2's creeps walk this path (colored red)
	}

	for laneName, teamId in laneTeamMap do
		local waypoints = MapConfig.LANE_WAYPOINTS[laneName]
		if not waypoints or #waypoints < 2 then
			continue
		end

		local teamColor = MapConfig.TEAM_COLORS[teamId]

		-- Also draw from spawn to first waypoint
		local spawnPos = MapConfig.SPAWN_POSITIONS[teamId]
		local allPoints = { spawnPos }
		for _, wp in waypoints do
			table.insert(allPoints, wp)
		end

		for i = 1, #allPoints - 1 do
			local p1 = Vector3.new(allPoints[i].X, 0.1, allPoints[i].Z)
			local p2 = Vector3.new(allPoints[i + 1].X, 0.1, allPoints[i + 1].Z)

			local midpoint = (p1 + p2) / 2
			local length = (p2 - p1).Magnitude

			if length < 0.1 then
				continue
			end

			local strip = Instance.new("Part")
			strip.Name = laneName .. "_Path" .. tostring(i)
			-- Size: length along the Z (forward) axis via lookAt, 2 studs wide, 0.1 tall
			strip.Size = Vector3.new(2, 0.1, length)
			strip.CFrame = CFrame.lookAt(midpoint, p2)
			strip.Color = teamColor
			strip.Material = Enum.Material.Neon
			strip.Transparency = 0.6
			strip.Anchored = true
			strip.CanCollide = false
			strip.TopSurface = Enum.SurfaceType.Smooth
			strip.BottomSurface = Enum.SurfaceType.Smooth
			strip.Parent = laneFolder
		end
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function MapService:KnitInit()
	self:_buildMap()
end

function MapService:KnitStart() end

return MapService
