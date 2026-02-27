--!strict

--[[
	CreepModels
	Builds distinctive WC3-accurate multi-part 3D models for each creep type.
	Models are made entirely from Roblox primitive Parts (no external meshes).
	Health bars are added separately — this module only handles geometry.

	Each builder stays at or under 8 parts for performance.

	Tier 1: Footman (7), Rifleman (6), Grunt (7)
	Tier 2: Knight (6, mounted), Priest (7), Raider (6, mounted)
	Tier 3: Abomination (8 + PointLight), FrostWyrm (8 + PointLight), Infernal (8 + PointLight)
]]

local CreepModels = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Lighten a Color3 by a factor (0..1). factor=0.3 means 30% toward white.
local function lighten(color: Color3, factor: number): Color3
	return Color3.new(
		color.R + (1 - color.R) * factor,
		color.G + (1 - color.G) * factor,
		color.B + (1 - color.B) * factor
	)
end

--- Darken a Color3 by a factor (0..1). factor=0.3 means 30% toward black.
local function darken(color: Color3, factor: number): Color3
	return Color3.new(
		color.R * (1 - factor),
		color.G * (1 - factor),
		color.B * (1 - factor)
	)
end

--- Create a Part with common defaults and parent it to a model.
local function makePart(
	model: Model,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	if shape then
		part.Shape = shape
	end

	part.Parent = model
	return part
end

--- Create a WedgePart with common defaults and parent it to a model.
local function makeWedge(
	model: Model,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material
): WedgePart
	local wedge = Instance.new("WedgePart")
	wedge.Name = name
	wedge.Size = size
	wedge.CFrame = cframe
	wedge.Color = color
	wedge.Material = material
	wedge.Anchored = true
	wedge.CanCollide = false
	wedge.TopSurface = Enum.SurfaceType.Smooth
	wedge.BottomSurface = Enum.SurfaceType.Smooth
	wedge.Parent = model
	return wedge
end

--- Create a new Model container with standard naming.
local function makeModel(): Model
	local model = Instance.new("Model")
	model.Name = "CreepModel"
	return model
end

--------------------------------------------------------------------------------
-- Tier 1 Builders
--------------------------------------------------------------------------------

--- Footman: human infantry with kite shield and sword. SmoothPlastic, 7 parts.
--- Signature feature: tall kite shield on left side.
local function buildFootman(teamColor: Color3, pos: Vector3): Model
	local model = makeModel()
	local mat = Enum.Material.SmoothPlastic
	local legColor = Color3.fromRGB(92, 64, 51)

	-- Body (torso) — PrimaryPart
	local body = makePart(model, "Body", Vector3.new(2.5, 3, 2), CFrame.new(pos), teamColor, mat)
	model.PrimaryPart = body

	-- Head — medium stone gray
	local headColor = Color3.fromRGB(163, 162, 165) -- Medium stone grey
	makePart(model, "Head", Vector3.new(1.2, 1.2, 1.2), CFrame.new(pos + Vector3.new(0, 2.1, 0)), headColor, mat)

	-- Helmet peak wedge on top of head
	local helmetCF = CFrame.new(pos + Vector3.new(0, 2.9, 0))
	makeWedge(model, "Helmet", Vector3.new(0.8, 0.6, 0.8), helmetCF, headColor, mat)

	-- Kite Shield on left side — tall tapered block, slightly darker team color
	local shieldColor = darken(teamColor, 0.15)
	makePart(
		model, "Shield", Vector3.new(0.3, 2.5, 1.6),
		CFrame.new(pos + Vector3.new(-1.4, 0, 0)),
		shieldColor, mat
	)

	-- Sword on right side — thin silver blade extending upward
	makePart(
		model, "Sword", Vector3.new(0.2, 2.5, 0.2),
		CFrame.new(pos + Vector3.new(1.35, 1.25, 0)),
		Color3.new(1, 1, 1), Enum.Material.Metal
	)

	-- Left leg
	makePart(model, "LeftLeg", Vector3.new(0.6, 1.5, 0.6), CFrame.new(pos + Vector3.new(-0.6, -2.25, 0)), legColor, mat)

	-- Right leg
	makePart(model, "RightLeg", Vector3.new(0.6, 1.5, 0.6), CFrame.new(pos + Vector3.new(0.6, -2.25, 0)), legColor, mat)

	return model -- 7 parts
end

--- Rifleman: dwarven ranged unit with hood and long rifle. Wood material, 6 parts.
--- Signature feature: long rifle barrel extending forward.
local function buildRifleman(teamColor: Color3, pos: Vector3): Model
	local model = makeModel()
	local mat = Enum.Material.Wood
	local legColor = Color3.fromRGB(92, 64, 51)
	local skinColor = Color3.fromRGB(255, 204, 153)

	-- Body (dwarf proportions: wider, shorter) — PrimaryPart
	local body = makePart(model, "Body", Vector3.new(2.2, 2.8, 2), CFrame.new(pos), teamColor, mat)
	model.PrimaryPart = body

	-- Hood/cloak block on top of body
	local hoodColor = darken(teamColor, 0.15)
	makePart(model, "Hood", Vector3.new(2.4, 1.0, 2.2), CFrame.new(pos + Vector3.new(0, 1.9, 0)), hoodColor, mat)

	-- Small face under the hood
	makePart(model, "Face", Vector3.new(1.0, 0.8, 1.0), CFrame.new(pos + Vector3.new(0, 1.8, -0.65)), skinColor, Enum.Material.SmoothPlastic)

	-- Beard wedge hanging below face
	local beardColor = Color3.fromRGB(220, 210, 195)
	local beardCF = CFrame.new(pos + Vector3.new(0, 1.15, -0.65)) * CFrame.Angles(math.rad(180), 0, 0)
	makeWedge(model, "Beard", Vector3.new(1.0, 1.0, 0.6), beardCF, beardColor, mat)

	-- Long rifle barrel extending forward (-Z) — the key identifying feature
	local barrelColor = Color3.fromRGB(61, 61, 61)
	makePart(
		model, "Rifle", Vector3.new(0.35, 0.35, 4.5),
		CFrame.new(pos + Vector3.new(0.5, 0.3, -3.25)),
		barrelColor, Enum.Material.Metal
	)

	-- Two stubby legs
	makePart(model, "LeftLeg", Vector3.new(0.6, 1.2, 0.6), CFrame.new(pos + Vector3.new(-0.5, -2.0, 0)), legColor, mat)
	makePart(model, "RightLeg", Vector3.new(0.6, 1.2, 0.6), CFrame.new(pos + Vector3.new(0.5, -2.0, 0)), legColor, mat)

	return model -- 7 parts (within budget)
end

--- Grunt: orc infantry with spiked pauldrons and battle axe. Slate material, 7 parts.
--- Signature features: shoulder pauldrons and large battle axe.
local function buildGrunt(teamColor: Color3, pos: Vector3): Model
	local model = makeModel()
	local mat = Enum.Material.Slate
	local pauldronColor = Color3.fromRGB(92, 64, 51)
	local axeColor = Color3.fromRGB(61, 61, 61)

	-- Body (wide, stocky) — PrimaryPart
	local body = makePart(model, "Body", Vector3.new(3.2, 3.5, 2.5), CFrame.new(pos), teamColor, mat)
	model.PrimaryPart = body

	-- Broad head — orc green tint: mix team color toward green
	local headColor = lighten(teamColor, 0.1)
	makePart(model, "Head", Vector3.new(1.5, 1.3, 1.5), CFrame.new(pos + Vector3.new(0, 2.4, 0)), headColor, mat)

	-- Left shoulder pauldron (Metal material for contrast, includes implied spike)
	makePart(
		model, "LeftPauldron", Vector3.new(1.4, 0.8, 1.4),
		CFrame.new(pos + Vector3.new(-1.6, 2.0, 0)),
		pauldronColor, Enum.Material.Metal
	)

	-- Left pauldron spike — bone white wedge pointing up
	local spikeColor = Color3.fromRGB(232, 220, 200)
	local leftSpikeCF = CFrame.new(pos + Vector3.new(-1.6, 2.8, 0))
	makeWedge(model, "LeftSpike", Vector3.new(0.3, 0.8, 0.3), leftSpikeCF, spikeColor, Enum.Material.SmoothPlastic)

	-- Right shoulder pauldron
	makePart(
		model, "RightPauldron", Vector3.new(1.4, 0.8, 1.4),
		CFrame.new(pos + Vector3.new(1.6, 2.0, 0)),
		pauldronColor, Enum.Material.Metal
	)

	-- Battle Axe handle on right side — thin tall shaft
	makePart(
		model, "AxeHandle", Vector3.new(0.3, 3.5, 0.3),
		CFrame.new(pos + Vector3.new(2.2, 0.25, 0)),
		axeColor, Enum.Material.Metal
	)

	-- Axe blade wedge at top of handle — wide thin blade
	local bladeCF = CFrame.new(pos + Vector3.new(3.0, 2.0, 0)) * CFrame.Angles(0, 0, math.rad(90))
	makeWedge(model, "AxeBlade", Vector3.new(1.8, 1.2, 0.25), bladeCF, axeColor, Enum.Material.Metal)

	return model -- 7 parts
end

--------------------------------------------------------------------------------
-- Tier 2 Builders
--------------------------------------------------------------------------------

--- Knight: armored human mounted on horse. Metal rider, SmoothPlastic horse. 6 parts.
--- Rider body is PrimaryPart. Neon sword for enchanted glow.
local function buildKnight(teamColor: Color3, pos: Vector3): Model
	local model = makeModel()
	local horseBrown = Color3.fromRGB(139, 105, 20)
	local horseLegColor = darken(horseBrown, 0.2)

	-- Horse body — horizontal block
	makePart(
		model, "HorseBody", Vector3.new(2.5, 2.5, 5.0),
		CFrame.new(pos + Vector3.new(0, -1.5, 0)),
		horseBrown, Enum.Material.SmoothPlastic
	)

	-- Horse front legs (combined pair)
	makePart(
		model, "HorseFrontLegs", Vector3.new(1.0, 2.0, 0.5),
		CFrame.new(pos + Vector3.new(0, -3.5, -1.8)),
		horseLegColor, Enum.Material.SmoothPlastic
	)

	-- Horse back legs (combined pair)
	makePart(
		model, "HorseBackLegs", Vector3.new(1.0, 2.0, 0.5),
		CFrame.new(pos + Vector3.new(0, -3.5, 1.8)),
		horseLegColor, Enum.Material.SmoothPlastic
	)

	-- Rider torso on top of horse — team colored Metal — PrimaryPart
	local body = makePart(
		model, "Body", Vector3.new(1.8, 2.5, 1.5),
		CFrame.new(pos),
		teamColor, Enum.Material.Metal
	)
	model.PrimaryPart = body

	-- Rider head — lightened team color to suggest circlet/helm
	local headColor = lighten(teamColor, 0.2)
	makePart(
		model, "RiderHead", Vector3.new(1.0, 1.0, 1.0),
		CFrame.new(pos + Vector3.new(0, 1.75, 0)),
		headColor, Enum.Material.Metal
	)

	-- Sword extending upward from right — white Neon enchanted blade
	makePart(
		model, "Sword", Vector3.new(0.25, 3.0, 0.25),
		CFrame.new(pos + Vector3.new(1.1, 1.5, 0)),
		Color3.new(1, 1, 1), Enum.Material.Neon
	)

	return model -- 6 parts
end

--- Priest: elven healer in white robes with staff and glowing orb. Fabric body, 7 parts.
--- Signature feature: Neon gold orb at top of staff.
local function buildPriest(teamColor: Color3, pos: Vector3): Model
	local model = makeModel()
	local robeWhite = Color3.fromRGB(245, 240, 230)
	local skinColor = Color3.fromRGB(255, 224, 196)
	local goldHair = Color3.fromRGB(240, 210, 100)
	local staffWood = Color3.fromRGB(196, 168, 130)
	local orbGold = Color3.fromRGB(255, 253, 224)

	-- Robe body (upper, PrimaryPart) — white Fabric
	local body = makePart(
		model, "Body", Vector3.new(1.5, 4, 1.5),
		CFrame.new(pos),
		robeWhite, Enum.Material.Fabric
	)
	model.PrimaryPart = body

	-- Robe skirt — wider block at the bottom for A-line silhouette
	makePart(
		model, "Skirt", Vector3.new(2.2, 1.5, 2.2),
		CFrame.new(pos + Vector3.new(0, -2.75, 0)),
		robeWhite, Enum.Material.Fabric
	)

	-- Head — pale skin Ball
	makePart(
		model, "Head", Vector3.new(1.2, 1.2, 1.2),
		CFrame.new(pos + Vector3.new(0, 2.6, 0)),
		skinColor, Enum.Material.SmoothPlastic,
		Enum.PartType.Ball
	)

	-- Gold hair on top of head
	makePart(
		model, "Hair", Vector3.new(1.2, 0.4, 1.0),
		CFrame.new(pos + Vector3.new(0, 3.3, 0)),
		goldHair, Enum.Material.SmoothPlastic
	)

	-- Staff — thin tall wood rod beside body
	makePart(
		model, "Staff", Vector3.new(0.25, 5.5, 0.25),
		CFrame.new(pos + Vector3.new(1.1, 0.75, 0)),
		staffWood, Enum.Material.Wood
	)

	-- Staff orb — Neon gold Ball at top of staff — the visual anchor
	makePart(
		model, "StaffOrb", Vector3.new(0.8, 0.8, 0.8),
		CFrame.new(pos + Vector3.new(1.1, 3.9, 0)),
		orbGold, Enum.Material.Neon,
		Enum.PartType.Ball
	)

	-- Pointed ear (left, small wedge angled out)
	local earCF = CFrame.new(pos + Vector3.new(-0.7, 2.7, 0)) * CFrame.Angles(0, 0, math.rad(30))
	makeWedge(model, "Ear", Vector3.new(0.3, 0.3, 0.5), earCF, skinColor, Enum.Material.SmoothPlastic)

	return model -- 7 parts
end

--- Raider: orc on wolf mount with warblade. DiamondPlate rider, SmoothPlastic wolf. 7 parts.
--- Signature feature: dark wolf mount and raised warblade.
local function buildRaider(teamColor: Color3, pos: Vector3): Model
	local model = makeModel()
	local wolfGray = Color3.fromRGB(74, 74, 74)
	local wolfLightGray = lighten(wolfGray, 0.15)
	local bladeColor = Color3.fromRGB(85, 85, 85)

	-- Wolf body — horizontal dark gray block
	makePart(
		model, "WolfBody", Vector3.new(2.0, 2.0, 4.0),
		CFrame.new(pos + Vector3.new(0, -1.5, 0)),
		wolfGray, Enum.Material.SmoothPlastic
	)

	-- Wolf head — block at front
	makePart(
		model, "WolfHead", Vector3.new(1.2, 1.0, 1.8),
		CFrame.new(pos + Vector3.new(0, -1.2, -2.5)),
		wolfGray, Enum.Material.SmoothPlastic
	)

	-- Wolf tail — small wedge at rear, angled up
	local tailCF = CFrame.new(pos + Vector3.new(0, -0.8, 2.5)) * CFrame.Angles(math.rad(-30), math.rad(180), 0)
	makeWedge(model, "WolfTail", Vector3.new(0.6, 0.8, 1.2), tailCF, wolfLightGray, Enum.Material.SmoothPlastic)

	-- Wolf ear wedges (two small upward wedges on wolf head)
	local leftEarCF = CFrame.new(pos + Vector3.new(-0.4, -0.4, -3.0)) * CFrame.Angles(math.rad(-20), 0, 0)
	makeWedge(model, "LeftEar", Vector3.new(0.3, 0.6, 0.3), leftEarCF, wolfLightGray, Enum.Material.SmoothPlastic)

	local rightEarCF = CFrame.new(pos + Vector3.new(0.4, -0.4, -3.0)) * CFrame.Angles(math.rad(-20), 0, 0)
	makeWedge(model, "RightEar", Vector3.new(0.3, 0.6, 0.3), rightEarCF, wolfLightGray, Enum.Material.SmoothPlastic)

	-- Orc rider body on wolf — team colored DiamondPlate — PrimaryPart
	local body = makePart(
		model, "Body", Vector3.new(1.8, 2.0, 1.5),
		CFrame.new(pos),
		teamColor, Enum.Material.DiamondPlate
	)
	model.PrimaryPart = body

	-- Warblade — angled thin block raised above rider, dark metal
	local bladeCF = CFrame.new(pos + Vector3.new(1.2, 1.8, 0)) * CFrame.Angles(0, 0, math.rad(-15))
	makePart(
		model, "Warblade", Vector3.new(0.3, 2.8, 0.8),
		bladeCF,
		bladeColor, Enum.Material.Metal
	)

	return model -- 7 parts
end

--------------------------------------------------------------------------------
-- Tier 3 Builders
--------------------------------------------------------------------------------

--- Abomination: undead monstrosity — massive sickly green ball with belly gash,
--- off-center head, three asymmetric arms with cleavers. Granite material, 8 parts + PointLight.
local function buildAbomination(teamColor: Color3, pos: Vector3): Model
	local model = makeModel()
	local mat = Enum.Material.Granite
	local sicklyGreen = Color3.fromRGB(120, 140, 70)
	local darkCrimson = Color3.fromRGB(123, 30, 30)
	local armColor = darken(sicklyGreen, 0.2)
	local cleaverColor = Color3.fromRGB(61, 61, 61)
	local headColor = lighten(sicklyGreen, 0.15)

	-- Large ball body — PrimaryPart
	local body = makePart(
		model, "Body", Vector3.new(5.5, 6.0, 5.5),
		CFrame.new(pos),
		sicklyGreen, mat, Enum.PartType.Ball
	)
	model.PrimaryPart = body

	-- PointLight for Tier 3 ground glow
	local glow = Instance.new("PointLight")
	glow.Range = 8
	glow.Brightness = 1
	glow.Color = Color3.fromRGB(120, 140, 70)
	glow.Parent = body

	-- Belly gash — thin dark crimson block on front
	makePart(
		model, "BellyGash", Vector3.new(2.0, 1.5, 0.3),
		CFrame.new(pos + Vector3.new(0, -0.5, -2.6)),
		darkCrimson, Enum.Material.SmoothPlastic
	)

	-- Small off-center head on top
	makePart(
		model, "Head", Vector3.new(1.2, 1.0, 1.2),
		CFrame.new(pos + Vector3.new(0.5, 3.2, 0)),
		headColor, mat
	)

	-- Arm 1: front-right, angled outward
	local arm1CF = CFrame.new(pos + Vector3.new(2.2, -0.5, -1.5)) * CFrame.Angles(math.rad(20), 0, math.rad(-35))
	makePart(model, "Arm1", Vector3.new(1.2, 2.5, 1.2), arm1CF, armColor, mat)

	-- Arm 2: front-left, angled outward
	local arm2CF = CFrame.new(pos + Vector3.new(-2.2, -0.5, -1.5)) * CFrame.Angles(math.rad(20), 0, math.rad(35))
	makePart(model, "Arm2", Vector3.new(1.2, 2.5, 1.2), arm2CF, armColor, mat)

	-- Arm 3: back-center, angled backward
	local arm3CF = CFrame.new(pos + Vector3.new(0, -0.5, 2.5)) * CFrame.Angles(math.rad(-25), 0, 0)
	makePart(model, "Arm3", Vector3.new(1.2, 2.5, 1.2), arm3CF, armColor, mat)

	-- Cleaver on Arm 1 tip
	local cleaver1CF = CFrame.new(pos + Vector3.new(3.2, -2.0, -2.2)) * CFrame.Angles(math.rad(20), 0, math.rad(-35))
	makePart(model, "Cleaver1", Vector3.new(1.2, 0.8, 0.2), cleaver1CF, cleaverColor, Enum.Material.Metal)

	-- Cleaver on Arm 2 tip
	local cleaver2CF = CFrame.new(pos + Vector3.new(-3.2, -2.0, -2.2)) * CFrame.Angles(math.rad(20), 0, math.rad(35))
	makePart(model, "Cleaver2", Vector3.new(1.2, 0.8, 0.2), cleaver2CF, cleaverColor, Enum.Material.Metal)

	return model -- 8 parts + PointLight
end

--- FrostWyrm: undead ice dragon — long Ice body, bone skull with glowing cyan eyes,
--- translucent wings, and tail. Ice material, 8 parts + PointLight.
--- Signature feature: menacing cyan Neon eye glow.
local function buildFrostWyrm(teamColor: Color3, pos: Vector3): Model
	local model = makeModel()
	local mat = Enum.Material.Ice
	local boneWhite = Color3.fromRGB(200, 220, 245)
	local cyanGlow = Color3.fromRGB(0, 255, 255)
	local iceWing = Color3.fromRGB(160, 196, 232)

	-- Long horizontal body — PrimaryPart
	local body = makePart(
		model, "Body", Vector3.new(3, 3, 6),
		CFrame.new(pos),
		teamColor, mat
	)
	model.PrimaryPart = body

	-- PointLight for Tier 3 ground glow
	local glow = Instance.new("PointLight")
	glow.Range = 10
	glow.Brightness = 1
	glow.Color = cyanGlow
	glow.Parent = body

	-- Skull at front — bone white with blue tint
	makePart(
		model, "Skull", Vector3.new(1.5, 1.5, 2.5),
		CFrame.new(pos + Vector3.new(0, 0.5, -4.0)),
		boneWhite, mat
	)

	-- Horn wedge — single wider piece centered on skull, angling backward
	local hornCF = CFrame.new(pos + Vector3.new(0, 1.6, -3.5)) * CFrame.Angles(math.rad(25), 0, 0)
	makeWedge(model, "Horn", Vector3.new(1.0, 0.5, 1.5), hornCF, boneWhite, mat)

	-- Left eye glow — bright cyan Neon Ball
	makePart(
		model, "LeftEye", Vector3.new(0.4, 0.4, 0.4),
		CFrame.new(pos + Vector3.new(-0.4, 0.6, -5.0)),
		cyanGlow, Enum.Material.Neon,
		Enum.PartType.Ball
	)

	-- Right eye glow — bright cyan Neon Ball
	makePart(
		model, "RightEye", Vector3.new(0.4, 0.4, 0.4),
		CFrame.new(pos + Vector3.new(0.4, 0.6, -5.0)),
		cyanGlow, Enum.Material.Neon,
		Enum.PartType.Ball
	)

	-- Left wing — thin translucent Ice, angled outward
	local leftWingCF = CFrame.new(pos + Vector3.new(-2.8, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(20))
	local leftWing = makePart(model, "LeftWing", Vector3.new(0.2, 2.5, 4), leftWingCF, iceWing, mat)
	leftWing.Transparency = 0.3

	-- Right wing — mirror of left
	local rightWingCF = CFrame.new(pos + Vector3.new(2.8, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(-20))
	local rightWing = makePart(model, "RightWing", Vector3.new(0.2, 2.5, 4), rightWingCF, iceWing, mat)
	rightWing.Transparency = 0.3

	-- Tail — tapered block extending backward from body
	makePart(
		model, "Tail", Vector3.new(0.8, 0.8, 3),
		CFrame.new(pos + Vector3.new(0, -0.5, 4.5)),
		lighten(teamColor, 0.2), mat
	)

	return model -- 8 parts + PointLight
end

--- Infernal: demonic golem — dark stone body with GREEN flame accents (not orange).
--- Slate material with Neon green joint flames. 8 parts + PointLight.
--- Signature feature: green Neon face glow and shoulder joint flames.
local function buildInfernal(teamColor: Color3, pos: Vector3): Model
	local model = makeModel()
	local darkStone = Color3.fromRGB(50, 45, 45)
	local mat = Enum.Material.Slate
	local greenFlame = Color3.fromRGB(0, 255, 68)
	local greenFlame2 = Color3.fromRGB(68, 255, 34)

	-- Torso — large dark charcoal Slate body — PrimaryPart
	local body = makePart(
		model, "Body", Vector3.new(4.5, 5.0, 3.5),
		CFrame.new(pos),
		darkStone, mat
	)
	model.PrimaryPart = body

	-- PointLight for Tier 3 green ground glow
	local glow = Instance.new("PointLight")
	glow.Range = 10
	glow.Brightness = 1
	glow.Color = greenFlame
	glow.Parent = body

	-- Head — dark stone block with slight gap above torso
	makePart(
		model, "Head", Vector3.new(1.8, 1.8, 1.8),
		CFrame.new(pos + Vector3.new(0, 3.7, 0)),
		darkStone, mat
	)

	-- Face glow — thin Neon green block on front of head
	makePart(
		model, "FaceGlow", Vector3.new(1.2, 0.8, 0.2),
		CFrame.new(pos + Vector3.new(0, 3.7, -0.9)),
		greenFlame, Enum.Material.Neon
	)

	-- Left arm — thick dark stone block extending down
	makePart(
		model, "LeftArm", Vector3.new(1.5, 3.5, 1.5),
		CFrame.new(pos + Vector3.new(-3.0, -0.5, 0)),
		darkStone, mat
	)

	-- Right arm — thick dark stone block extending down
	makePart(
		model, "RightArm", Vector3.new(1.5, 3.5, 1.5),
		CFrame.new(pos + Vector3.new(3.0, -0.5, 0)),
		darkStone, mat
	)

	-- Left shoulder flame — small Neon green block at shoulder gap
	makePart(
		model, "LeftFlame", Vector3.new(0.8, 0.8, 0.8),
		CFrame.new(pos + Vector3.new(-2.1, 2.0, 0)),
		greenFlame2, Enum.Material.Neon
	)

	-- Right shoulder flame — small Neon green block at shoulder gap
	makePart(
		model, "RightFlame", Vector3.new(0.8, 0.8, 0.8),
		CFrame.new(pos + Vector3.new(2.1, 2.0, 0)),
		greenFlame2, Enum.Material.Neon
	)

	-- Horn — dark stone wedge angling backward from head
	local hornCF = CFrame.new(pos + Vector3.new(0, 5.0, 0.5)) * CFrame.Angles(math.rad(-20), 0, 0)
	makeWedge(model, "Horn", Vector3.new(0.6, 1.2, 0.6), hornCF, darkStone, mat)

	return model -- 8 parts + PointLight
end

--------------------------------------------------------------------------------
-- Builder Dispatch
--------------------------------------------------------------------------------

local builders: { [string]: (teamColor: Color3, pos: Vector3) -> Model } = {
	Footman = buildFootman,
	Rifleman = buildRifleman,
	Grunt = buildGrunt,
	Knight = buildKnight,
	Priest = buildPriest,
	Raider = buildRaider,
	Abomination = buildAbomination,
	FrostWyrm = buildFrostWyrm,
	Infernal = buildInfernal,
}

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Build a 3D model for the given creep type.
--- @param creepId   -- The creep identifier (e.g. "Footman", "Knight", "FrostWyrm")
--- @param teamColor -- Color3 applied to the main body part
--- @param spawnPosition -- World position for the body center
--- @return Model with PrimaryPart set to the "Body" part
function CreepModels.build(creepId: string, teamColor: Color3, spawnPosition: Vector3): Model
	local builder = builders[creepId]
	if not builder then
		warn("[CreepModels] Unknown creepId: " .. creepId .. ". Falling back to Footman.")
		builder = buildFootman
	end

	return builder(teamColor, spawnPosition)
end

return CreepModels
