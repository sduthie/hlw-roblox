--!strict

--[[
	AbilityIcons
	Builds small procedural 2D icons (Frame-based) for each ability type.
	Each icon is a container Frame with 2-6 colored child Frames arranged
	to suggest the ability's effect. Used in the ability bar and hero info UI.

	Icons are lightweight (few Frames each) for performance.
]]

local AbilityIcons = {}

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
-- Icon Builders
--------------------------------------------------------------------------------

--- Heal: Green cross/plus shape (two overlapping rectangles forming a +)
local function buildHeal(container: Frame, size: number)
	local green1 = Color3.fromRGB(50, 200, 80)
	local green2 = Color3.fromRGB(30, 160, 50)

	-- Vertical bar of the cross
	local barW = math.round(size * 0.28)
	local barH = math.round(size * 0.7)
	local barX = math.round((size - barW) / 2)
	local barY = math.round((size - barH) / 2)
	local vBar = makeBlock(container, "VBar", barW, barH, barX, barY, green1, 2)
	addGradient(vBar, green1, green2)

	-- Horizontal bar of the cross
	local hBarW = math.round(size * 0.7)
	local hBarH = math.round(size * 0.28)
	local hBarX = math.round((size - hBarW) / 2)
	local hBarY = math.round((size - hBarH) / 2)
	local hBar = makeBlock(container, "HBar", hBarW, hBarH, hBarX, hBarY, green1, 2)
	addGradient(hBar, green1, green2, 0)
end

--- Damage: Red explosion/burst (red center circle with small radiating squares)
local function buildDamage(container: Frame, size: number)
	local red1 = Color3.fromRGB(220, 50, 40)
	local red2 = Color3.fromRGB(180, 30, 20)

	-- Center circle
	local coreS = math.round(size * 0.36)
	local coreX = math.round((size - coreS) / 2)
	local coreY = math.round((size - coreS) / 2)
	local core = makeBlock(container, "Core", coreS, coreS, coreX, coreY, red1, math.round(coreS / 2))
	addGradient(core, red1, red2)

	-- Radiating squares (4 corners + 4 edges = small burst fragments)
	local fragS = math.round(size * 0.14)
	local center = math.round(size / 2)
	local dist = math.round(size * 0.32)

	-- Top
	makeBlock(container, "Top", fragS, fragS, center - math.round(fragS / 2), center - dist, red2, 1)
	-- Bottom
	makeBlock(container, "Bottom", fragS, fragS, center - math.round(fragS / 2), center + dist - fragS, red2, 1)
	-- Left
	makeBlock(container, "Left", fragS, fragS, center - dist, center - math.round(fragS / 2), red2, 1)
	-- Right
	makeBlock(container, "Right", fragS, fragS, center + dist - fragS, center - math.round(fragS / 2), red2, 1)
end

--- Buff / Passive: Yellow/gold ring with inner glow (circle with smaller circle inside)
local function buildBuff(container: Frame, size: number)
	local gold1 = Color3.fromRGB(255, 215, 60)
	local gold2 = Color3.fromRGB(200, 170, 40)

	-- Outer ring (large circle)
	local outerS = math.round(size * 0.7)
	local outerX = math.round((size - outerS) / 2)
	local outerY = math.round((size - outerS) / 2)
	local outer = makeBlock(container, "Outer", outerS, outerS, outerX, outerY, gold1, math.round(outerS / 2))
	addGradient(outer, gold1, gold2)

	-- Inner cutout (darker circle to create ring effect)
	local innerS = math.round(size * 0.4)
	local innerX = math.round((size - innerS) / 2)
	local innerY = math.round((size - innerS) / 2)
	local inner = makeBlock(container, "Inner", innerS, innerS, innerX, innerY, Color3.fromRGB(255, 245, 180), math.round(innerS / 2))
	inner.BackgroundTransparency = 0.4
end

--- SelfBuff: Blue shield shape (wider at top, pointed at bottom using overlapping rectangles)
local function buildSelfBuff(container: Frame, size: number)
	local blue1 = Color3.fromRGB(60, 140, 220)
	local blue2 = Color3.fromRGB(40, 100, 180)

	-- Top of shield (wide rectangle)
	local topW = math.round(size * 0.6)
	local topH = math.round(size * 0.45)
	local topX = math.round((size - topW) / 2)
	local topY = math.round(size * 0.12)
	local topBlock = makeBlock(container, "ShieldTop", topW, topH, topX, topY, blue1, 3)
	addGradient(topBlock, blue1, blue2)

	-- Middle narrowing (slightly narrower)
	local midW = math.round(size * 0.42)
	local midH = math.round(size * 0.22)
	local midX = math.round((size - midW) / 2)
	local midY = topY + topH - 2
	local midBlock = makeBlock(container, "ShieldMid", midW, midH, midX, midY, blue2, 2)
	addGradient(midBlock, blue1, blue2)

	-- Bottom point (small square)
	local botW = math.round(size * 0.18)
	local botH = math.round(size * 0.18)
	local botX = math.round((size - botW) / 2)
	local botY = midY + midH - 2
	makeBlock(container, "ShieldBot", botW, botH, botX, botY, blue2, 1)

	-- Inner highlight (lighter blue accent)
	local accentW = math.round(size * 0.2)
	local accentH = math.round(size * 0.3)
	local accentX = math.round((size - accentW) / 2)
	local accentY = math.round(size * 0.2)
	local accent = makeBlock(container, "Accent", accentW, accentH, accentX, accentY, Color3.fromRGB(120, 190, 255), 2)
	accent.BackgroundTransparency = 0.4
end

--- Ward: Purple diamond/eye (rotated square with a small circle in center)
local function buildWard(container: Frame, size: number)
	local purple1 = Color3.fromRGB(160, 80, 220)
	local purple2 = Color3.fromRGB(120, 50, 180)

	-- Diamond shape (rotated square using 4 small rectangles arranged as diamond)
	-- Top-left half
	local halfW = math.round(size * 0.32)
	local halfH = math.round(size * 0.32)
	local center = math.round(size / 2)

	-- Upper triangle portion (two blocks forming a diamond)
	local topBlock = makeBlock(container, "DiamondTop", halfW, halfH, center - math.round(halfW / 2), math.round(size * 0.08), purple1, 2)
	addGradient(topBlock, purple1, purple2)

	local botBlock = makeBlock(container, "DiamondBot", halfW, halfH, center - math.round(halfW / 2), math.round(size * 0.58), purple2, 2)
	addGradient(botBlock, purple1, purple2)

	-- Left and right wings to fill out the diamond
	local sideW = math.round(size * 0.22)
	local sideH = math.round(size * 0.28)
	local sideY = math.round((size - sideH) / 2)
	local leftSide = makeBlock(container, "DiamondLeft", sideW, sideH, math.round(size * 0.08), sideY, purple1, 2)
	addGradient(leftSide, purple1, purple2)

	local rightSide = makeBlock(container, "DiamondRight", sideW, sideH, math.round(size * 0.68), sideY, purple1, 2)
	addGradient(rightSide, purple1, purple2)

	-- Center eye (small bright circle)
	local eyeS = math.round(size * 0.18)
	local eyeX = center - math.round(eyeS / 2)
	local eyeY = math.round((size - eyeS) / 2)
	makeBlock(container, "Eye", eyeS, eyeS, eyeX, eyeY, Color3.fromRGB(220, 180, 255), math.round(eyeS / 2))
end

--- Stun: Yellow lightning bolt (3 angled rectangles forming a zigzag)
local function buildStun(container: Frame, size: number)
	local yellow1 = Color3.fromRGB(255, 220, 40)
	local yellow2 = Color3.fromRGB(220, 180, 20)

	local boltW = math.round(size * 0.28)
	local boltH = math.round(size * 0.24)

	-- Top segment (upper-right)
	local seg1 = makeBlock(container, "Bolt1", boltW, boltH, math.round(size * 0.38), math.round(size * 0.08), yellow1, 2)
	addGradient(seg1, yellow1, yellow2, 0)

	-- Middle segment (center-left, overlapping)
	local seg2 = makeBlock(container, "Bolt2", math.round(size * 0.36), boltH, math.round(size * 0.24), math.round(size * 0.28), yellow1, 2)
	addGradient(seg2, yellow1, yellow2, 0)

	-- Bottom segment (lower-right)
	local seg3 = makeBlock(container, "Bolt3", boltW, math.round(size * 0.32), math.round(size * 0.36), math.round(size * 0.48), yellow1, 2)
	addGradient(seg3, yellow1, yellow2, 0)
end

--- Summon: Blue elemental (water drop shape with inner glow)
local function buildSummon(container: Frame, size: number)
	local blue1 = Color3.fromRGB(60, 140, 255)
	local blue2 = Color3.fromRGB(30, 90, 200)

	-- Water drop body (large oval)
	local bodyW = math.round(size * 0.5)
	local bodyH = math.round(size * 0.55)
	local bodyX = math.round((size - bodyW) / 2)
	local bodyY = math.round(size * 0.3)
	local body = makeBlock(container, "Body", bodyW, bodyH, bodyX, bodyY, blue1, math.round(bodyW / 2))
	addGradient(body, blue1, blue2)

	-- Top point (small triangle via narrow block)
	local tipW = math.round(size * 0.2)
	local tipH = math.round(size * 0.25)
	local tipX = math.round((size - tipW) / 2)
	local tipY = math.round(size * 0.12)
	makeBlock(container, "Tip", tipW, tipH, tipX, tipY, blue1, 2)

	-- Inner glow
	local glowS = math.round(size * 0.22)
	local glowX = math.round((size - glowS) / 2)
	local glowY = math.round(size * 0.42)
	local glow = makeBlock(container, "Glow", glowS, glowS, glowX, glowY, Color3.fromRGB(150, 210, 255), math.round(glowS / 2))
	glow.BackgroundTransparency = 0.3
end

--- Unknown / nil: Gray question mark (circle with "?" text label inside)
local function buildUnknown(container: Frame, size: number)
	-- Gray circle background
	local circS = math.round(size * 0.65)
	local circX = math.round((size - circS) / 2)
	local circY = math.round((size - circS) / 2)
	local circ = makeBlock(container, "Circle", circS, circS, circX, circY, Color3.fromRGB(120, 120, 120), math.round(circS / 2))
	addGradient(circ, Color3.fromRGB(140, 140, 140), Color3.fromRGB(90, 90, 90))

	-- "?" text label
	local label = Instance.new("TextLabel")
	label.Name = "QuestionMark"
	label.Size = UDim2.fromOffset(circS, circS)
	label.Position = UDim2.fromOffset(circX, circY)
	label.BackgroundTransparency = 1
	label.Text = "?"
	label.TextColor3 = Color3.fromRGB(220, 220, 220)
	label.TextScaled = true
	label.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
	label.Parent = container
end

--------------------------------------------------------------------------------
-- Builder Dispatch
--------------------------------------------------------------------------------

local builders: { [string]: (container: Frame, size: number) -> () } = {
	Heal = buildHeal,
	Damage = buildDamage,
	Buff = buildBuff,
	Passive = buildBuff, -- Passive abilities reuse the Buff/aura icon
	SelfBuff = buildSelfBuff,
	Ward = buildWard,
	Stun = buildStun,
	Summon = buildSummon,
}

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Build a mini-icon Frame for a given ability type.
--- @param abilityType -- The ability type (e.g. "Heal", "Damage", "Buff", "Passive")
--- @param size        -- Icon size in pixels (default 40)
--- @return Frame      -- A container Frame with child frames forming the icon
function AbilityIcons.build(abilityType: string, size: number?): Frame
	local iconSize = size or 40

	local container = Instance.new("Frame")
	container.Size = UDim2.fromOffset(iconSize, iconSize)
	container.BackgroundTransparency = 1
	container.Name = "AbilityIcon_" .. (abilityType or "Unknown")

	local builder = builders[abilityType]
	if builder then
		builder(container, iconSize)
	else
		buildUnknown(container, iconSize)
	end

	return container
end

return AbilityIcons
