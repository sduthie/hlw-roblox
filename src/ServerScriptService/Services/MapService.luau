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
	gui.StudsOffset = Vector3.new(0, 3, 0)
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

	-- 2. Two nexus structures
	self:_createNexus(mapFolder)

	-- 3. Two gate towers (compact turrets that shoot creeps)
	self:_createGateTowers(mapFolder)

	-- 4. Attack portals only (at top of each lane where enemy creeps spawn)
	self:_createAttackPortals(mapFolder)

	-- 5. Lane waypoint markers (debug visualization)
	if MapConfig.SHOW_WAYPOINT_MARKERS then
		local waypointFolder = Instance.new("Folder")
		waypointFolder.Name = "Waypoints"
		waypointFolder.Parent = mapFolder

		local laneNames = { "AttackTeam1", "AttackTeam2", "DefendTeam1", "DefendTeam2" }
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

	-- 10. Healing wells
	self:_createHealingWells(mapFolder)
end

-- ---------------------------------------------------------------------------
-- Nexus structures
-- ---------------------------------------------------------------------------

function MapService:_createNexus(mapFolder: Folder)
	local nexusFolder = Instance.new("Folder")
	nexusFolder.Name = "Nexuses"
	nexusFolder.Parent = mapFolder

	-- Lane is ~93 studs wide. Nexus footprint should be <=40 studs (under 50%).
	-- Design: tiered castle keep — wide stone base, narrower upper floor, battlements, spire.

	for teamId = 1, Constants.TEAM_COUNT do
		local pos = MapConfig.BASE_POSITIONS[teamId]
		local teamColor = MapConfig.TEAM_COLORS[teamId]
		local lighterColor = Color3.new(
			math.min(1, teamColor.R + 0.25),
			math.min(1, teamColor.G + 0.25),
			math.min(1, teamColor.B + 0.25)
		)
		local darkerColor = Color3.new(teamColor.R * 0.5, teamColor.G * 0.5, teamColor.B * 0.5)
		local stoneColor = Color3.fromRGB(100, 95, 90)
		local darkStone = Color3.fromRGB(70, 65, 60)

		-- Ground level Y = 0. pos.Y = 10, so offset everything from ground.
		local groundY = 0

		-- 1. Stone foundation / base tier (20x4x14, wider footprint)
		local foundation = createPart({
			Name = "Base_Team" .. tostring(teamId),
			Size = Vector3.new(20, 4, 14),
			Position = Vector3.new(pos.X, groundY + 2, pos.Z),
			Color = stoneColor,
			Material = Enum.Material.Cobblestone,
			CanCollide = true,
			Parent = nexusFolder,
		})
		CollectionService:AddTag(foundation, "Base")
		foundation:SetAttribute("TeamId", teamId)

		-- 2. Main keep (14x7x10, sits on top of foundation)
		createPart({
			Name = "NexusKeep_Team" .. tostring(teamId),
			Size = Vector3.new(14, 7, 10),
			Position = Vector3.new(pos.X, groundY + 7.5, pos.Z),
			Color = darkStone,
			Material = Enum.Material.Brick,
			CanCollide = true,
			Parent = nexusFolder,
		})

		-- 3. Team-colored band at keep mid-height
		createPart({
			Name = "NexusBand_Team" .. tostring(teamId),
			Size = Vector3.new(14.2, 0.8, 10.2),
			Position = Vector3.new(pos.X, groundY + 7, pos.Z),
			Color = teamColor,
			Material = Enum.Material.Neon,
			Transparency = 0.3,
			CanCollide = false,
			Parent = nexusFolder,
		})

		-- 4. Four corner turrets on the keep roof (2x3x2 each)
		local turretOffsets = {
			Vector3.new(-6, 0, -4),
			Vector3.new(6, 0, -4),
			Vector3.new(-6, 0, 4),
			Vector3.new(6, 0, 4),
		}
		for i, tOff in turretOffsets do
			createPart({
				Name = "NexusTurret" .. i .. "_Team" .. tostring(teamId),
				Size = Vector3.new(2, 3, 2),
				Position = Vector3.new(pos.X + tOff.X, groundY + 12.5, pos.Z + tOff.Z),
				Color = stoneColor,
				Material = Enum.Material.Cobblestone,
				CanCollide = false,
				Parent = nexusFolder,
			})
		end

		-- 5. Battlement wall segments along keep roof edges (thin crenellations)
		-- Front and back walls
		for _, zOff in { -4.5, 4.5 } do
			for x = -4, 4, 4 do
				createPart({
					Name = "Merlon_Team" .. tostring(teamId),
					Size = Vector3.new(2, 1.5, 0.8),
					Position = Vector3.new(pos.X + x, groundY + 11.75, pos.Z + zOff),
					Color = stoneColor,
					Material = Enum.Material.Cobblestone,
					CanCollide = false,
					Parent = nexusFolder,
				})
			end
		end

		-- 6. Central spire (team-colored glowing crystal)
		local spire = createPart({
			Name = "NexusSpire_Team" .. tostring(teamId),
			Size = Vector3.new(2, 6, 2),
			Position = Vector3.new(pos.X, groundY + 14, pos.Z),
			Color = teamColor,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = nexusFolder,
		})

		-- 7. Wedge cap on spire
		local topCap = Instance.new("WedgePart")
		topCap.Name = "NexusTop_Team" .. tostring(teamId)
		topCap.Size = Vector3.new(2, 3, 2)
		topCap.CFrame = CFrame.new(Vector3.new(pos.X, groundY + 18.5, pos.Z))
		topCap.Color = lighterColor
		topCap.Material = Enum.Material.Neon
		topCap.Anchored = true
		topCap.CanCollide = false
		topCap.TopSurface = Enum.SurfaceType.Smooth
		topCap.BottomSurface = Enum.SurfaceType.Smooth
		topCap.Parent = nexusFolder

		-- 8. Door archway (dark inset on the front face, Z- side)
		createPart({
			Name = "NexusDoor_Team" .. tostring(teamId),
			Size = Vector3.new(3, 4, 0.3),
			Position = Vector3.new(pos.X, groundY + 4, pos.Z - 5.1),
			Color = Color3.fromRGB(20, 20, 25),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Parent = nexusFolder,
		})

		-- 9. Two small window insets on keep sides
		for _, xOff in { -4, 4 } do
			createPart({
				Name = "NexusWindow_Team" .. tostring(teamId),
				Size = Vector3.new(0.3, 2, 1.5),
				Position = Vector3.new(pos.X + xOff, groundY + 8, pos.Z - 5.1),
				Color = Color3.fromRGB(30, 30, 40),
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
				Parent = nexusFolder,
			})
		end

		-- 10. Glow light from spire
		local coreLight = Instance.new("PointLight")
		coreLight.Range = 25
		coreLight.Brightness = 2
		coreLight.Color = teamColor
		coreLight.Parent = spire

		-- 11. "NEXUS" billboard label with health bar
		local gui = Instance.new("BillboardGui")
		gui.Name = "NexusLabel"
		gui.Size = UDim2.fromOffset(140, 50)
		gui.StudsOffset = Vector3.new(0, 6, 0)
		gui.AlwaysOnTop = true
		gui.Parent = foundation

		local label = Instance.new("TextLabel")
		label.Name = "Title"
		label.Size = UDim2.new(1, 0, 0, 22)
		label.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
		label.BackgroundTransparency = 0.35
		label.Text = "NEXUS"
		label.Font = Enum.Font.GothamBold
		label.TextSize = 18
		label.TextColor3 = lighterColor
		label.TextStrokeTransparency = 0.3
		label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		label.Parent = gui

		local labelCorner = Instance.new("UICorner")
		labelCorner.CornerRadius = UDim.new(0, 6)
		labelCorner.Parent = label

		-- Health bar under the label
		local hpBg = Instance.new("Frame")
		hpBg.Name = "NexusHPBackground"
		hpBg.Size = UDim2.new(1, -10, 0, 12)
		hpBg.Position = UDim2.new(0, 5, 0, 25)
		hpBg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
		hpBg.BorderSizePixel = 0
		hpBg.Parent = gui

		local hpBgCorner = Instance.new("UICorner")
		hpBgCorner.CornerRadius = UDim.new(0, 3)
		hpBgCorner.Parent = hpBg

		local hpFill = Instance.new("Frame")
		hpFill.Name = "NexusHPFill"
		hpFill.Size = UDim2.new(1, 0, 1, 0)
		hpFill.BackgroundColor3 = teamColor
		hpFill.BorderSizePixel = 0
		hpFill.Parent = hpBg

		local hpFillCorner = Instance.new("UICorner")
		hpFillCorner.CornerRadius = UDim.new(0, 3)
		hpFillCorner.Parent = hpFill

		local hpLabel = Instance.new("TextLabel")
		hpLabel.Name = "NexusHPLabel"
		hpLabel.Size = UDim2.fromScale(1, 1)
		hpLabel.BackgroundTransparency = 1
		hpLabel.Text = tostring(Constants.BASE_MAX_LIVES) .. " / " .. tostring(Constants.BASE_MAX_LIVES)
		hpLabel.Font = Enum.Font.GothamBold
		hpLabel.TextSize = 9
		hpLabel.TextColor3 = Color3.new(1, 1, 1)
		hpLabel.TextStrokeTransparency = 0.3
		hpLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
		hpLabel.Parent = hpBg
	end
end

-- ---------------------------------------------------------------------------
-- Shop buildings
-- ---------------------------------------------------------------------------

function MapService:_createShopBuildings(mapFolder: Folder)
	local shopFolder = Instance.new("Folder")
	shopFolder.Name = "Shops"
	shopFolder.Parent = mapFolder

	local shopBuildings = MapConfig.SHOP_BUILDINGS
	if not shopBuildings then
		return
	end

	for _, shopDef in shopBuildings do
		for teamId = 1, Constants.TEAM_COUNT do
			local basePos = MapConfig.BASE_POSITIONS[teamId]
			local offset = shopDef.Offsets[teamId]
			if not basePos or not offset then
				continue
			end

			local pos = basePos + offset
			local bodyColor = shopDef.BodyColor
			local roofColor = Color3.new(bodyColor.R * 0.6, bodyColor.G * 0.6, bodyColor.B * 0.6)

			-- Main building body
			local building = createPart({
				Name = shopDef.Type .. "_Shop_Team" .. tostring(teamId),
				Size = Vector3.new(8, 6, 6),
				Position = pos + Vector3.new(0, 3, 0),
				Color = bodyColor,
				Material = Enum.Material.SmoothPlastic,
				CanCollide = true,
				Parent = shopFolder,
			})
			CollectionService:AddTag(building, "Shop")
			building:SetAttribute("TeamId", teamId)
			building:SetAttribute("ShopType", shopDef.Type)

			-- Roof (CanQuery=false so raycasts pass through to the building body)
			local roof = createPart({
				Name = shopDef.Type .. "_Roof_Team" .. tostring(teamId),
				Size = Vector3.new(10, 1, 8),
				Position = pos + Vector3.new(0, 6.5, 0),
				Color = roofColor,
				Material = Enum.Material.Wood,
				CanCollide = false,
				Parent = shopFolder,
			})
			roof.CanQuery = false

			-- Gold trim (CanQuery=false so raycasts pass through)
			local trim = createPart({
				Name = shopDef.Type .. "_Trim_Team" .. tostring(teamId),
				Size = Vector3.new(10, 0.3, 8),
				Position = pos + Vector3.new(0, 6, 0),
				Color = Color3.fromRGB(255, 215, 0),
				Material = Enum.Material.Neon,
				Transparency = 0.4,
				CanCollide = false,
				Parent = shopFolder,
			})
			trim.CanQuery = false

			-- Billboard sign (Active = true so client can attach click handlers)
			local signGui = Instance.new("BillboardGui")
			signGui.Name = "ShopSign"
			signGui.Size = UDim2.fromOffset(140, 36)
			signGui.StudsOffset = Vector3.new(0, 5, 0)
			signGui.AlwaysOnTop = true
			signGui.Active = true
			signGui.Parent = building

			local signLabel = Instance.new("TextLabel")
			signLabel.Size = UDim2.fromScale(1, 1)
			signLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
			signLabel.BackgroundTransparency = 0.3
			signLabel.Text = shopDef.Label
			signLabel.Font = Enum.Font.GothamBold
			signLabel.TextSize = 16
			signLabel.TextColor3 = shopDef.LabelColor
			signLabel.TextStrokeTransparency = 0.3
			signLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
			signLabel.Parent = signGui

			local signCorner = Instance.new("UICorner")
			signCorner.CornerRadius = UDim.new(0, 5)
			signCorner.Parent = signLabel

			-- ProximityPrompt
			local prompt = Instance.new("ProximityPrompt")
			prompt.ObjectText = shopDef.Label
			prompt.ActionText = "Open " .. shopDef.Label
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 12
			prompt.KeyboardKeyCode = Enum.KeyCode.F
			prompt.Parent = building
		end
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

	-- Outer boundary walls (left and right edges)
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

	-- Center divider wall between left and right lanes
	createPart({
		Name = "LaneDivider",
		Size = Vector3.new(wallThickness, wallHeight, wallLength),
		Position = Vector3.new(0, wallHeight / 2, 0),
		Color = Color3.fromRGB(90, 85, 80),
		Material = Enum.Material.Brick,
		CanCollide = true,
		Parent = wallFolder,
	})
end

-- ---------------------------------------------------------------------------
-- Lane path visualization
-- ---------------------------------------------------------------------------

function MapService:_createLanePaths(mapFolder: Folder)
	local laneFolder = Instance.new("Folder")
	laneFolder.Name = "LanePaths"
	laneFolder.Parent = mapFolder

	-- Attack paths: show the main enemy path going down each lane
	-- AttackTeam1 = enemy creeps march down left lane (sent by Team 2, colored red)
	-- AttackTeam2 = enemy creeps march down right lane (sent by Team 1, colored blue)
	local laneConfig = {
		{ lane = "AttackTeam1", teamColor = 2, spawn = MapConfig.ATTACK_SPAWN_POSITIONS[1], transparency = 0.6 },
		{ lane = "AttackTeam2", teamColor = 1, spawn = MapConfig.ATTACK_SPAWN_POSITIONS[2], transparency = 0.6 },
		{ lane = "DefendTeam1", teamColor = 1, spawn = MapConfig.DEFEND_SPAWN_POSITIONS[1], transparency = 0.8 },
		{ lane = "DefendTeam2", teamColor = 2, spawn = MapConfig.DEFEND_SPAWN_POSITIONS[2], transparency = 0.8 },
	}

	for _, cfg in laneConfig do
		local waypoints = MapConfig.LANE_WAYPOINTS[cfg.lane]
		if not waypoints or #waypoints < 2 then
			continue
		end

		local teamColor = MapConfig.TEAM_COLORS[cfg.teamColor]

		-- Draw from spawn to first waypoint
		local allPoints = { cfg.spawn }
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
			strip.Name = cfg.lane .. "_Path" .. tostring(i)
			strip.Size = Vector3.new(2, 0.1, length)
			strip.CFrame = CFrame.lookAt(midpoint, p2)
			strip.Color = teamColor
			strip.Material = Enum.Material.Neon
			strip.Transparency = cfg.transparency
			strip.Anchored = true
			strip.CanCollide = false
			strip.TopSurface = Enum.SurfaceType.Smooth
			strip.BottomSurface = Enum.SurfaceType.Smooth
			strip.Parent = laneFolder
		end
	end
end

-- ---------------------------------------------------------------------------
-- Healing wells
-- ---------------------------------------------------------------------------

function MapService:_createHealingWells(mapFolder: Folder)
	local wellFolder = Instance.new("Folder")
	wellFolder.Name = "HealingWells"
	wellFolder.Parent = mapFolder

	for teamId = 1, Constants.TEAM_COUNT do
		local pos = MapConfig.HEALING_WELL_POSITIONS[teamId]
		local teamColor = MapConfig.TEAM_COLORS[teamId]
		local wellSize = MapConfig.HEALING_WELL_SIZE

		-- Main cylindrical base (team-colored stone basin)
		local base = Instance.new("Part")
		base.Name = "HealingWell_Team" .. tostring(teamId)
		base.Shape = Enum.PartType.Cylinder
		-- Cylinder size: X = length (height when rotated), Y = diameter, Z = diameter
		base.Size = Vector3.new(wellSize.Y, wellSize.X, wellSize.Z)
		base.CFrame = CFrame.new(pos + Vector3.new(0, wellSize.Y / 2, 0))
			* CFrame.Angles(0, 0, math.rad(90))
		base.Color = teamColor
		base.Material = Enum.Material.SmoothPlastic
		base.Transparency = 0.15
		base.Anchored = true
		base.CanCollide = true
		base.TopSurface = Enum.SurfaceType.Smooth
		base.BottomSurface = Enum.SurfaceType.Smooth
		base.Parent = wellFolder

		CollectionService:AddTag(base, "HealingWell")
		base:SetAttribute("TeamId", teamId)

		-- Water surface on top (blue glowing disc)
		local water = Instance.new("Part")
		water.Name = "WellWater_Team" .. tostring(teamId)
		water.Shape = Enum.PartType.Cylinder
		water.Size = Vector3.new(0.3, wellSize.X - 0.5, wellSize.Z - 0.5)
		water.CFrame = CFrame.new(pos + Vector3.new(0, wellSize.Y - 0.15, 0))
			* CFrame.Angles(0, 0, math.rad(90))
		water.Color = Color3.fromRGB(80, 180, 255)
		water.Material = Enum.Material.Neon
		water.Transparency = 0.2
		water.Anchored = true
		water.CanCollide = false
		water.TopSurface = Enum.SurfaceType.Smooth
		water.BottomSurface = Enum.SurfaceType.Smooth
		water.Parent = wellFolder

		-- Glowing pillar of light above the well
		local pillar = Instance.new("Part")
		pillar.Name = "WellGlow_Team" .. tostring(teamId)
		pillar.Shape = Enum.PartType.Cylinder
		pillar.Size = Vector3.new(12, 3, 3)
		pillar.CFrame = CFrame.new(pos + Vector3.new(0, wellSize.Y + 6, 0))
			* CFrame.Angles(0, 0, math.rad(90))
		pillar.Color = Color3.fromRGB(120, 220, 255)
		pillar.Material = Enum.Material.Neon
		pillar.Transparency = 0.75
		pillar.Anchored = true
		pillar.CanCollide = false
		pillar.TopSurface = Enum.SurfaceType.Smooth
		pillar.BottomSurface = Enum.SurfaceType.Smooth
		pillar.Parent = wellFolder

		-- Billboard label
		local gui = Instance.new("BillboardGui")
		gui.Name = "WellLabel"
		gui.Size = UDim2.fromOffset(140, 30)
		gui.StudsOffset = Vector3.new(0, 5, 0)
		gui.AlwaysOnTop = true
		gui.Parent = base

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
		label.BackgroundTransparency = 0.4
		label.Text = "Healing Well"
		label.Font = Enum.Font.GothamBold
		label.TextSize = 18
		label.TextColor3 = Color3.fromRGB(120, 255, 200)
		label.TextStrokeTransparency = 0.4
		label.TextStrokeColor3 = Color3.fromRGB(0, 80, 60)
		label.Parent = gui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = label
	end
end

-- ---------------------------------------------------------------------------
-- Gate towers (compact turrets that shoot enemy creeps)
-- ---------------------------------------------------------------------------

function MapService:_createGateTowers(mapFolder: Folder)
	local gateFolder = Instance.new("Folder")
	gateFolder.Name = "Gates"
	gateFolder.Parent = mapFolder

	for teamId = 1, Constants.TEAM_COUNT do
		local pos = MapConfig.GATE_POSITIONS[teamId]
		local teamColor = MapConfig.TEAM_COLORS[teamId]
		local lighterColor = Color3.new(
			math.min(1, teamColor.R + 0.3),
			math.min(1, teamColor.G + 0.3),
			math.min(1, teamColor.B + 0.3)
		)
		local stoneColor = Color3.fromRGB(110, 105, 100)

		-- 1. Stone base (8x3x8, sits on ground)
		local gatePart = createPart({
			Name = "Gate_Team" .. tostring(teamId),
			Size = Vector3.new(8, 3, 8),
			Position = Vector3.new(pos.X, 1.5, pos.Z),
			Color = stoneColor,
			Material = Enum.Material.Cobblestone,
			CanCollide = true,
			Parent = gateFolder,
		})
		CollectionService:AddTag(gatePart, "Gate")
		gatePart:SetAttribute("TeamId", teamId)
		gatePart:SetAttribute("Health", Constants.GATE_MAX_HP)
		gatePart:SetAttribute("DPS", Constants.GATE_BASE_DPS)

		-- 2. Upper tower (6x5x6)
		createPart({
			Name = "GateTower_Team" .. tostring(teamId),
			Size = Vector3.new(6, 5, 6),
			Position = Vector3.new(pos.X, 5.5, pos.Z),
			Color = Color3.fromRGB(85, 80, 75),
			Material = Enum.Material.Brick,
			CanCollide = true,
			Parent = gateFolder,
		})

		-- 3. Four corner merlons (battlements on top)
		local merlonOffsets = {
			Vector3.new(-2.5, 0, -2.5),
			Vector3.new(2.5, 0, -2.5),
			Vector3.new(-2.5, 0, 2.5),
			Vector3.new(2.5, 0, 2.5),
		}
		for i, mOff in merlonOffsets do
			createPart({
				Name = "GateMerlon" .. i .. "_Team" .. tostring(teamId),
				Size = Vector3.new(1.5, 1.5, 1.5),
				Position = Vector3.new(pos.X + mOff.X, 8.75, pos.Z + mOff.Z),
				Color = stoneColor,
				Material = Enum.Material.Cobblestone,
				CanCollide = false,
				Parent = gateFolder,
			})
		end

		-- 4. Team-colored crystal orb on top (the "weapon")
		local orb = Instance.new("Part")
		orb.Name = "GateOrb_Team" .. tostring(teamId)
		orb.Shape = Enum.PartType.Ball
		orb.Size = Vector3.new(3, 3, 3)
		orb.Position = Vector3.new(pos.X, 10, pos.Z)
		orb.Color = teamColor
		orb.Material = Enum.Material.Neon
		orb.Anchored = true
		orb.CanCollide = false
		orb.TopSurface = Enum.SurfaceType.Smooth
		orb.BottomSurface = Enum.SurfaceType.Smooth
		orb.Parent = gateFolder

		-- Glow from the orb
		local orbLight = Instance.new("PointLight")
		orbLight.Range = 20
		orbLight.Brightness = 1.5
		orbLight.Color = teamColor
		orbLight.Parent = orb

		-- 5. Health bar billboard
		createBillboardHealthGui(gatePart, Constants.GATE_MAX_HP)

		-- 6. "GUARDIAN" label
		local gui = Instance.new("BillboardGui")
		gui.Name = "GateLabel"
		gui.Size = UDim2.fromOffset(100, 24)
		gui.StudsOffset = Vector3.new(0, 4, 0)
		gui.AlwaysOnTop = true
		gui.Parent = gatePart

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
		label.BackgroundTransparency = 0.35
		label.Text = "GUARDIAN"
		label.Font = Enum.Font.GothamBold
		label.TextSize = 14
		label.TextColor3 = lighterColor
		label.TextStrokeTransparency = 0.3
		label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		label.Parent = gui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 5)
		corner.Parent = label
	end
end

-- ---------------------------------------------------------------------------
-- Attack portals only (where enemy creeps spawn at top of each lane)
-- ---------------------------------------------------------------------------

function MapService:_createAttackPortals(mapFolder: Folder)
	local portalFolder = Instance.new("Folder")
	portalFolder.Name = "Portals"
	portalFolder.Parent = mapFolder

	for teamId = 1, Constants.TEAM_COUNT do
		local enemyTeamId = if teamId == 1 then 2 else 1
		local pos = MapConfig.ATTACK_SPAWN_POSITIONS[teamId]
		local portalColor = MapConfig.TEAM_COLORS[enemyTeamId]
		local glowColor = Color3.fromRGB(255, 80, 60)

		-- Ground ring
		local ring = Instance.new("Part")
		ring.Name = "AttackPortal_Team" .. tostring(teamId) .. "_Ring"
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.5, 16, 16)
		ring.CFrame = CFrame.new(pos + Vector3.new(0, 0.3, 0))
			* CFrame.Angles(0, 0, math.rad(90))
		ring.Color = portalColor
		ring.Material = Enum.Material.Neon
		ring.Transparency = 0.3
		ring.Anchored = true
		ring.CanCollide = false
		ring.TopSurface = Enum.SurfaceType.Smooth
		ring.BottomSurface = Enum.SurfaceType.Smooth
		ring.Parent = portalFolder

		-- Inner disc
		local inner = Instance.new("Part")
		inner.Name = "AttackPortal_Team" .. tostring(teamId) .. "_Inner"
		inner.Shape = Enum.PartType.Cylinder
		inner.Size = Vector3.new(0.3, 12, 12)
		inner.CFrame = CFrame.new(pos + Vector3.new(0, 0.35, 0))
			* CFrame.Angles(0, 0, math.rad(90))
		inner.Color = Color3.new(portalColor.R * 0.4, portalColor.G * 0.4, portalColor.B * 0.4)
		inner.Material = Enum.Material.Neon
		inner.Transparency = 0.5
		inner.Anchored = true
		inner.CanCollide = false
		inner.TopSurface = Enum.SurfaceType.Smooth
		inner.BottomSurface = Enum.SurfaceType.Smooth
		inner.Parent = portalFolder

		-- Vertical glow pillar
		local pillar = Instance.new("Part")
		pillar.Name = "AttackPortal_Team" .. tostring(teamId) .. "_Pillar"
		pillar.Shape = Enum.PartType.Cylinder
		pillar.Size = Vector3.new(20, 4, 4)
		pillar.CFrame = CFrame.new(pos + Vector3.new(0, 10, 0))
			* CFrame.Angles(0, 0, math.rad(90))
		pillar.Color = glowColor
		pillar.Material = Enum.Material.Neon
		pillar.Transparency = 0.8
		pillar.Anchored = true
		pillar.CanCollide = false
		pillar.TopSurface = Enum.SurfaceType.Smooth
		pillar.BottomSurface = Enum.SurfaceType.Smooth
		pillar.Parent = portalFolder

		-- Light
		local light = Instance.new("PointLight")
		light.Range = 20
		light.Brightness = 1.5
		light.Color = glowColor
		light.Parent = ring

		-- Label
		local gui = Instance.new("BillboardGui")
		gui.Name = "PortalLabel"
		gui.Size = UDim2.fromOffset(160, 28)
		gui.StudsOffset = Vector3.new(0, 3, 0)
		gui.AlwaysOnTop = true
		gui.Parent = ring

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
		label.BackgroundTransparency = 0.35
		label.Text = "Enemy Portal"
		label.Font = Enum.Font.GothamBold
		label.TextSize = 16
		label.TextColor3 = Color3.fromRGB(255, 100, 80)
		label.TextStrokeTransparency = 0.5
		label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		label.Parent = gui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 5)
		corner.Parent = label
	end
end

-- ---------------------------------------------------------------------------
-- Update nexus health bar when lives change
-- ---------------------------------------------------------------------------

function MapService:UpdateNexusHealth(teamId: number, currentLives: number)
	local mapFolder = workspace:FindFirstChild("Map")
	if not mapFolder then
		return
	end
	local nexusFolder = mapFolder:FindFirstChild("Nexuses")
	if not nexusFolder then
		return
	end

	local basePart = nexusFolder:FindFirstChild("Base_Team" .. tostring(teamId)) :: Part?
	if not basePart then
		return
	end

	local gui = basePart:FindFirstChild("NexusLabel") :: BillboardGui?
	if not gui then
		return
	end

	local hpBg = gui:FindFirstChild("NexusHPBackground") :: Frame?
	if not hpBg then
		return
	end

	local hpFill = hpBg:FindFirstChild("NexusHPFill") :: Frame?
	local hpLabel = hpBg:FindFirstChild("NexusHPLabel") :: TextLabel?

	local maxLives = Constants.BASE_MAX_LIVES
	local pct = math.clamp(currentLives / maxLives, 0, 1)

	if hpFill then
		hpFill.Size = UDim2.new(pct, 0, 1, 0)
		-- Color gradient: team color -> yellow -> red
		if pct > 0.5 then
			-- keep team color
		elseif pct > 0.25 then
			hpFill.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
		else
			hpFill.BackgroundColor3 = Color3.fromRGB(255, 50, 0)
		end
	end

	if hpLabel then
		hpLabel.Text = tostring(math.floor(currentLives)) .. " / " .. tostring(maxLives)
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
