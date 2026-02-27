--!strict

--[[
	CreepIcons
	Builds small procedural 2D icons (Frame-based) for each creep type.
	Each icon is a container Frame with 2-4 colored child Frames arranged
	to suggest the creep's silhouette. Used in the creep bar and shop UI.

	Icons are lightweight (few Frames each) for performance.
]]

local CreepIcons = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Create a child Frame with common properties.
local function makeBlock(
	parent: Frame,
	name: string,
	sizeX: number,
	sizeY: number,
	posX: number,
	posY: number,
	color: Color3,
	cornerRadius: number?
): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.fromOffset(sizeX, sizeY)
	frame.Position = UDim2.fromOffset(posX, posY)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Parent = parent

	if cornerRadius and cornerRadius > 0 then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, cornerRadius)
		corner.Parent = frame
	end

	return frame
end

--- Add a UIGradient to a frame.
local function addGradient(frame: Frame, colorFrom: Color3, colorTo: Color3, rotation: number?)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(colorFrom, colorTo)
	gradient.Rotation = rotation or 90
	gradient.Parent = frame
end

--------------------------------------------------------------------------------
-- Tier 1 Builders
--------------------------------------------------------------------------------

--- Footman: Silver body + blue shield on left + white sword on right
local function buildFootman(container: Frame, size: number)
	-- Body (silver torso)
	local bodyW = math.round(size * 0.35)
	local bodyH = math.round(size * 0.5)
	local bodyX = math.round((size - bodyW) / 2)
	local bodyY = math.round(size * 0.15)
	local body = makeBlock(container, "Body", bodyW, bodyH, bodyX, bodyY, Color3.fromRGB(180, 185, 195), 2)
	addGradient(body, Color3.fromRGB(200, 205, 215), Color3.fromRGB(150, 155, 165))

	-- Head (silver helmet)
	local headS = math.round(size * 0.22)
	local headX = math.round((size - headS) / 2)
	makeBlock(container, "Head", headS, headS, headX, math.round(size * 0.02), Color3.fromRGB(163, 162, 165), math.round(headS / 2))

	-- Shield (blue rectangle, left side)
	local shieldW = math.round(size * 0.18)
	local shieldH = math.round(size * 0.42)
	local shieldX = bodyX - shieldW + 1
	local shieldY = math.round(size * 0.18)
	makeBlock(container, "Shield", shieldW, shieldH, shieldX, shieldY, Color3.fromRGB(60, 100, 180), 2)

	-- Sword (thin white line, right side)
	local swordW = math.round(math.max(size * 0.06, 2))
	local swordH = math.round(size * 0.5)
	local swordX = bodyX + bodyW
	local swordY = math.round(size * 0.08)
	makeBlock(container, "Sword", swordW, swordH, swordX, swordY, Color3.fromRGB(240, 240, 255), 1)

	-- Legs
	local legW = math.round(size * 0.12)
	local legH = math.round(size * 0.28)
	local legY = bodyY + bodyH
	makeBlock(container, "LeftLeg", legW, legH, bodyX + 1, legY, Color3.fromRGB(92, 64, 51), 1)
	makeBlock(container, "RightLeg", legW, legH, bodyX + bodyW - legW - 1, legY, Color3.fromRGB(92, 64, 51), 1)
end

--- Rifleman: Brown hooded body + dark gray rifle barrel extending right
local function buildRifleman(container: Frame, size: number)
	-- Body (brown cloak)
	local bodyW = math.round(size * 0.38)
	local bodyH = math.round(size * 0.45)
	local bodyX = math.round(size * 0.18)
	local bodyY = math.round(size * 0.2)
	local body = makeBlock(container, "Body", bodyW, bodyH, bodyX, bodyY, Color3.fromRGB(120, 90, 50), 2)
	addGradient(body, Color3.fromRGB(140, 105, 60), Color3.fromRGB(95, 70, 40))

	-- Hood (wider brown block on top)
	local hoodW = math.round(size * 0.42)
	local hoodH = math.round(size * 0.22)
	local hoodX = math.round(size * 0.16)
	makeBlock(container, "Hood", hoodW, hoodH, hoodX, math.round(size * 0.04), Color3.fromRGB(100, 75, 40), 3)

	-- Face (small skin-colored square under hood)
	local faceS = math.round(size * 0.15)
	local faceX = math.round(size * 0.26)
	makeBlock(container, "Face", faceS, faceS, faceX, math.round(size * 0.16), Color3.fromRGB(255, 204, 153), 2)

	-- Rifle barrel (dark gray, extending right)
	local barrelW = math.round(size * 0.4)
	local barrelH = math.round(math.max(size * 0.08, 2))
	local barrelX = bodyX + bodyW - 2
	local barrelY = math.round(size * 0.38)
	makeBlock(container, "Rifle", barrelW, barrelH, barrelX, barrelY, Color3.fromRGB(61, 61, 61), 1)

	-- Legs (short, dwarf proportions)
	local legW = math.round(size * 0.12)
	local legH = math.round(size * 0.22)
	local legY = bodyY + bodyH
	makeBlock(container, "LeftLeg", legW, legH, bodyX + 2, legY, Color3.fromRGB(92, 64, 51), 1)
	makeBlock(container, "RightLeg", legW, legH, bodyX + bodyW - legW - 2, legY, Color3.fromRGB(92, 64, 51), 1)
end

--- Grunt: Wide green body + brown shoulder pads + dark axe
local function buildGrunt(container: Frame, size: number)
	-- Body (wide green, stocky)
	local bodyW = math.round(size * 0.5)
	local bodyH = math.round(size * 0.45)
	local bodyX = math.round((size - bodyW) / 2)
	local bodyY = math.round(size * 0.2)
	local body = makeBlock(container, "Body", bodyW, bodyH, bodyX, bodyY, Color3.fromRGB(75, 120, 50), 2)
	addGradient(body, Color3.fromRGB(90, 140, 60), Color3.fromRGB(60, 95, 40))

	-- Head (green, broad)
	local headW = math.round(size * 0.28)
	local headH = math.round(size * 0.22)
	local headX = math.round((size - headW) / 2)
	makeBlock(container, "Head", headW, headH, headX, math.round(size * 0.03), Color3.fromRGB(85, 130, 55), 2)

	-- Left shoulder pad (brown)
	local padW = math.round(size * 0.18)
	local padH = math.round(size * 0.14)
	makeBlock(container, "LeftPad", padW, padH, bodyX - padW + 3, math.round(size * 0.2), Color3.fromRGB(120, 85, 45), 2)

	-- Right shoulder pad (brown)
	makeBlock(container, "RightPad", padW, padH, bodyX + bodyW - 3, math.round(size * 0.2), Color3.fromRGB(120, 85, 45), 2)

	-- Axe handle + blade (right side)
	local handleW = math.round(math.max(size * 0.06, 2))
	local handleH = math.round(size * 0.5)
	local handleX = bodyX + bodyW + padW - 4
	makeBlock(container, "AxeHandle", handleW, handleH, handleX, math.round(size * 0.1), Color3.fromRGB(61, 61, 61), 1)

	-- Axe blade (wider block at top of handle)
	local bladeW = math.round(size * 0.14)
	local bladeH = math.round(size * 0.18)
	makeBlock(container, "AxeBlade", bladeW, bladeH, handleX + handleW, math.round(size * 0.1), Color3.fromRGB(80, 80, 85), 1)

	-- Legs
	local legW = math.round(size * 0.14)
	local legH = math.round(size * 0.24)
	local legY = bodyY + bodyH
	makeBlock(container, "LeftLeg", legW, legH, bodyX + 2, legY, Color3.fromRGB(75, 100, 45), 1)
	makeBlock(container, "RightLeg", legW, legH, bodyX + bodyW - legW - 2, legY, Color3.fromRGB(75, 100, 45), 1)
end

--------------------------------------------------------------------------------
-- Tier 2 Builders
--------------------------------------------------------------------------------

--- Knight: Gold rider on top of a brown horse block
local function buildKnight(container: Frame, size: number)
	-- Horse body (brown horizontal block)
	local horseW = math.round(size * 0.7)
	local horseH = math.round(size * 0.28)
	local horseX = math.round((size - horseW) / 2)
	local horseY = math.round(size * 0.5)
	local horse = makeBlock(container, "Horse", horseW, horseH, horseX, horseY, Color3.fromRGB(139, 105, 20), 3)
	addGradient(horse, Color3.fromRGB(160, 120, 30), Color3.fromRGB(110, 80, 15))

	-- Horse legs (front and back pairs)
	local legW = math.round(size * 0.1)
	local legH = math.round(size * 0.2)
	local legY = horseY + horseH
	makeBlock(container, "FrontLegs", legW, legH, horseX + 2, legY, Color3.fromRGB(110, 80, 15), 1)
	makeBlock(container, "BackLegs", legW, legH, horseX + horseW - legW - 2, legY, Color3.fromRGB(110, 80, 15), 1)

	-- Rider torso (gold/team colored, on top of horse)
	local riderW = math.round(size * 0.28)
	local riderH = math.round(size * 0.3)
	local riderX = math.round((size - riderW) / 2)
	local riderY = horseY - riderH + 2
	local rider = makeBlock(container, "Rider", riderW, riderH, riderX, riderY, Color3.fromRGB(200, 170, 50), 2)
	addGradient(rider, Color3.fromRGB(220, 190, 60), Color3.fromRGB(170, 140, 30))

	-- Rider head (lighter gold helmet)
	local headS = math.round(size * 0.18)
	local headX = math.round((size - headS) / 2)
	makeBlock(container, "Head", headS, headS, headX, riderY - headS + 2, Color3.fromRGB(230, 210, 80), math.round(headS / 2))

	-- Sword (white neon line, right side of rider)
	local swordW = math.round(math.max(size * 0.06, 2))
	local swordH = math.round(size * 0.38)
	makeBlock(container, "Sword", swordW, swordH, riderX + riderW + 1, math.round(size * 0.05), Color3.fromRGB(255, 255, 240), 1)
end

--- Priest: White tall robe + gold orb circle on top
local function buildPriest(container: Frame, size: number)
	-- Robe body (white, tall)
	local robeW = math.round(size * 0.32)
	local robeH = math.round(size * 0.5)
	local robeX = math.round((size - robeW) / 2)
	local robeY = math.round(size * 0.22)
	local robe = makeBlock(container, "Robe", robeW, robeH, robeX, robeY, Color3.fromRGB(235, 230, 220), 2)
	addGradient(robe, Color3.fromRGB(245, 240, 230), Color3.fromRGB(215, 210, 200))

	-- Robe skirt (wider at bottom, A-line)
	local skirtW = math.round(size * 0.45)
	local skirtH = math.round(size * 0.22)
	local skirtX = math.round((size - skirtW) / 2)
	makeBlock(container, "Skirt", skirtW, skirtH, skirtX, robeY + robeH - 2, Color3.fromRGB(235, 230, 220), 2)

	-- Head (pale skin circle)
	local headS = math.round(size * 0.2)
	local headX = math.round((size - headS) / 2)
	makeBlock(container, "Head", headS, headS, headX, math.round(size * 0.08), Color3.fromRGB(255, 224, 196), math.round(headS / 2))

	-- Gold hair on top
	local hairW = math.round(size * 0.22)
	local hairH = math.round(size * 0.08)
	local hairX = math.round((size - hairW) / 2)
	makeBlock(container, "Hair", hairW, hairH, hairX, math.round(size * 0.04), Color3.fromRGB(240, 210, 100), 2)

	-- Staff (thin line right side)
	local staffW = math.round(math.max(size * 0.05, 2))
	local staffH = math.round(size * 0.7)
	local staffX = robeX + robeW + math.round(size * 0.05)
	makeBlock(container, "Staff", staffW, staffH, staffX, math.round(size * 0.12), Color3.fromRGB(196, 168, 130), 1)

	-- Gold orb at top of staff
	local orbS = math.round(size * 0.16)
	local orbX = staffX - math.round(orbS * 0.25)
	makeBlock(container, "Orb", orbS, orbS, orbX, math.round(size * 0.02), Color3.fromRGB(255, 240, 120), math.round(orbS / 2))
end

--- Raider: Dark gray wolf block + rider on top + blade
local function buildRaider(container: Frame, size: number)
	-- Wolf body (dark gray horizontal block)
	local wolfW = math.round(size * 0.65)
	local wolfH = math.round(size * 0.26)
	local wolfX = math.round((size - wolfW) / 2)
	local wolfY = math.round(size * 0.5)
	local wolf = makeBlock(container, "Wolf", wolfW, wolfH, wolfX, wolfY, Color3.fromRGB(74, 74, 74), 3)
	addGradient(wolf, Color3.fromRGB(90, 90, 90), Color3.fromRGB(55, 55, 55))

	-- Wolf head (block at front-left)
	local whW = math.round(size * 0.18)
	local whH = math.round(size * 0.16)
	makeBlock(container, "WolfHead", whW, whH, wolfX - 2, wolfY - 4, Color3.fromRGB(80, 80, 80), 2)

	-- Wolf ears (two small blocks)
	local earS = math.round(size * 0.08)
	makeBlock(container, "LeftEar", earS, earS, wolfX - 2, wolfY - 4 - earS + 1, Color3.fromRGB(90, 90, 90), 1)
	makeBlock(container, "RightEar", earS, earS, wolfX + whW - earS - 2, wolfY - 4 - earS + 1, Color3.fromRGB(90, 90, 90), 1)

	-- Wolf legs
	local legW = math.round(size * 0.08)
	local legH = math.round(size * 0.2)
	local legY = wolfY + wolfH
	makeBlock(container, "FrontLegs", legW, legH, wolfX + 3, legY, Color3.fromRGB(60, 60, 60), 1)
	makeBlock(container, "BackLegs", legW, legH, wolfX + wolfW - legW - 3, legY, Color3.fromRGB(60, 60, 60), 1)

	-- Orc rider (team colored, on wolf)
	local riderW = math.round(size * 0.24)
	local riderH = math.round(size * 0.28)
	local riderX = math.round((size - riderW) / 2) + 2
	local riderY = wolfY - riderH + 3
	makeBlock(container, "Rider", riderW, riderH, riderX, riderY, Color3.fromRGB(85, 130, 55), 2)

	-- Rider head
	local headS = math.round(size * 0.16)
	makeBlock(container, "RiderHead", headS, headS, riderX + math.round((riderW - headS) / 2), riderY - headS + 2, Color3.fromRGB(95, 140, 65), 2)

	-- Warblade (angled, right side)
	local bladeW = math.round(math.max(size * 0.06, 2))
	local bladeH = math.round(size * 0.35)
	makeBlock(container, "Blade", bladeW, bladeH, riderX + riderW + 2, math.round(size * 0.08), Color3.fromRGB(85, 85, 85), 1)
end

--------------------------------------------------------------------------------
-- Tier 3 Builders
--------------------------------------------------------------------------------

--- Abomination: Large sickly green circle with dark red slash marks
local function buildAbomination(container: Frame, size: number)
	-- Large green blob (circle)
	local blobS = math.round(size * 0.7)
	local blobX = math.round((size - blobS) / 2)
	local blobY = math.round(size * 0.08)
	local blob = makeBlock(container, "Blob", blobS, blobS, blobX, blobY, Color3.fromRGB(120, 140, 70), math.round(blobS / 2))
	addGradient(blob, Color3.fromRGB(135, 155, 80), Color3.fromRGB(95, 115, 55))

	-- Belly gash (dark crimson horizontal slash)
	local gashW = math.round(size * 0.35)
	local gashH = math.round(math.max(size * 0.08, 2))
	local gashX = math.round((size - gashW) / 2)
	makeBlock(container, "Gash", gashW, gashH, gashX, math.round(size * 0.45), Color3.fromRGB(123, 30, 30), 1)

	-- Off-center head (small lighter green circle)
	local headS = math.round(size * 0.2)
	makeBlock(container, "Head", headS, headS, math.round(size * 0.52), math.round(size * 0.02), Color3.fromRGB(145, 165, 90), math.round(headS / 2))

	-- Left arm (angled block)
	local armW = math.round(size * 0.15)
	local armH = math.round(size * 0.3)
	makeBlock(container, "LeftArm", armW, armH, blobX - armW + 3, math.round(size * 0.35), Color3.fromRGB(95, 115, 55), 2)

	-- Right arm
	makeBlock(container, "RightArm", armW, armH, blobX + blobS - 3, math.round(size * 0.3), Color3.fromRGB(95, 115, 55), 2)

	-- Cleaver (small dark block at end of right arm)
	local cleavW = math.round(size * 0.12)
	local cleavH = math.round(size * 0.08)
	makeBlock(container, "Cleaver", cleavW, cleavH, blobX + blobS - 3 + armW - 2, math.round(size * 0.55), Color3.fromRGB(61, 61, 61), 1)
end

--- FrostWyrm: Cyan/ice blue elongated body + white wing triangles
local function buildFrostWyrm(container: Frame, size: number)
	-- Elongated body (horizontal cyan block)
	local bodyW = math.round(size * 0.7)
	local bodyH = math.round(size * 0.22)
	local bodyX = math.round((size - bodyW) / 2)
	local bodyY = math.round(size * 0.4)
	local body = makeBlock(container, "Body", bodyW, bodyH, bodyX, bodyY, Color3.fromRGB(100, 180, 220), 3)
	addGradient(body, Color3.fromRGB(120, 200, 240), Color3.fromRGB(70, 150, 190))

	-- Skull (lighter cyan/bone block at front-left)
	local skullW = math.round(size * 0.2)
	local skullH = math.round(size * 0.16)
	makeBlock(container, "Skull", skullW, skullH, bodyX - skullW + 4, bodyY - 2, Color3.fromRGB(200, 220, 245), 2)

	-- Cyan eye glow (tiny bright block on skull)
	local eyeS = math.round(math.max(size * 0.08, 3))
	makeBlock(container, "Eye", eyeS, eyeS, bodyX - skullW + 6, bodyY, Color3.fromRGB(0, 255, 255), math.round(eyeS / 2))

	-- Left wing (tall thin block extending up-left)
	local wingW = math.round(size * 0.2)
	local wingH = math.round(size * 0.35)
	local wingY = bodyY - wingH + 3
	local leftWing = makeBlock(container, "LeftWing", wingW, wingH, math.round(size * 0.2), wingY, Color3.fromRGB(160, 196, 232), 2)
	leftWing.BackgroundTransparency = 0.3
	addGradient(leftWing, Color3.fromRGB(180, 210, 240), Color3.fromRGB(130, 175, 215), 135)

	-- Right wing (mirror)
	local rightWing = makeBlock(container, "RightWing", wingW, wingH, math.round(size * 0.55), wingY, Color3.fromRGB(160, 196, 232), 2)
	rightWing.BackgroundTransparency = 0.3
	addGradient(rightWing, Color3.fromRGB(180, 210, 240), Color3.fromRGB(130, 175, 215), 45)

	-- Tail (tapered block extending right from body)
	local tailW = math.round(size * 0.22)
	local tailH = math.round(math.max(size * 0.1, 3))
	makeBlock(container, "Tail", tailW, tailH, bodyX + bodyW - 2, bodyY + math.round(bodyH * 0.4), Color3.fromRGB(130, 200, 230), 2)
end

--- Infernal: Dark charcoal body + green neon accents (eyes/joints)
local function buildInfernal(container: Frame, size: number)
	-- Torso (large dark charcoal block)
	local bodyW = math.round(size * 0.42)
	local bodyH = math.round(size * 0.42)
	local bodyX = math.round((size - bodyW) / 2)
	local bodyY = math.round(size * 0.2)
	local body = makeBlock(container, "Body", bodyW, bodyH, bodyX, bodyY, Color3.fromRGB(50, 45, 45), 2)
	addGradient(body, Color3.fromRGB(65, 58, 58), Color3.fromRGB(38, 35, 35))

	-- Head (dark stone block above torso)
	local headS = math.round(size * 0.22)
	local headX = math.round((size - headS) / 2)
	makeBlock(container, "Head", headS, headS, headX, math.round(size * 0.02), Color3.fromRGB(55, 50, 50), 2)

	-- Green face glow (neon green rectangle on head)
	local glowW = math.round(size * 0.16)
	local glowH = math.round(math.max(size * 0.08, 2))
	local glowX = math.round((size - glowW) / 2)
	makeBlock(container, "FaceGlow", glowW, glowH, glowX, math.round(size * 0.08), Color3.fromRGB(0, 255, 68), 1)

	-- Horn (small dark wedge on top of head)
	local hornW = math.round(size * 0.1)
	local hornH = math.round(size * 0.12)
	local hornX = math.round((size - hornW) / 2)
	makeBlock(container, "Horn", hornW, hornH, hornX, 0, Color3.fromRGB(50, 45, 45), 1)

	-- Left arm (thick dark block)
	local armW = math.round(size * 0.16)
	local armH = math.round(size * 0.38)
	makeBlock(container, "LeftArm", armW, armH, bodyX - armW + 1, math.round(size * 0.28), Color3.fromRGB(50, 45, 45), 2)

	-- Right arm
	makeBlock(container, "RightArm", armW, armH, bodyX + bodyW - 1, math.round(size * 0.28), Color3.fromRGB(50, 45, 45), 2)

	-- Left shoulder flame (green neon)
	local flameS = math.round(size * 0.1)
	makeBlock(container, "LeftFlame", flameS, flameS, bodyX - math.round(flameS * 0.5), math.round(size * 0.2), Color3.fromRGB(68, 255, 34), math.round(flameS / 2))

	-- Right shoulder flame (green neon)
	makeBlock(container, "RightFlame", flameS, flameS, bodyX + bodyW - math.round(flameS * 0.5), math.round(size * 0.2), Color3.fromRGB(68, 255, 34), math.round(flameS / 2))

	-- Legs
	local legW = math.round(size * 0.14)
	local legH = math.round(size * 0.24)
	local legY = bodyY + bodyH
	makeBlock(container, "LeftLeg", legW, legH, bodyX + 1, legY, Color3.fromRGB(45, 40, 40), 1)
	makeBlock(container, "RightLeg", legW, legH, bodyX + bodyW - legW - 1, legY, Color3.fromRGB(45, 40, 40), 1)
end

--------------------------------------------------------------------------------
-- Builder Dispatch
--------------------------------------------------------------------------------

local builders: { [string]: (container: Frame, size: number) -> () } = {
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

--- Build a mini-icon Frame for a given creep type.
--- @param creepId -- The creep identifier (e.g. "Footman", "Knight", "FrostWyrm")
--- @param size    -- Icon size in pixels (default 40)
--- @return Frame  -- A container Frame with child frames forming the icon
function CreepIcons.build(creepId: string, size: number?): Frame
	local iconSize = size or 40

	local container = Instance.new("Frame")
	container.Size = UDim2.fromOffset(iconSize, iconSize)
	container.BackgroundTransparency = 1
	container.Name = "CreepIcon_" .. creepId

	local builder = builders[creepId]
	if builder then
		builder(container, iconSize)
	else
		-- Fallback: simple colored square
		local sq = Instance.new("Frame")
		sq.Size = UDim2.fromScale(0.6, 0.6)
		sq.Position = UDim2.fromScale(0.2, 0.2)
		sq.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
		sq.BorderSizePixel = 0
		sq.Parent = container

		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 4)
		c.Parent = sq
	end

	return container
end

return CreepIcons
