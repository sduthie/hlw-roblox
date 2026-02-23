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
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function MapService:KnitInit()
	self:_buildMap()
end

function MapService:KnitStart() end

return MapService
