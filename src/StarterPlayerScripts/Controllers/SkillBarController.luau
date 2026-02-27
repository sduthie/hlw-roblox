--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Knit = require(ReplicatedStorage.Packages.Knit)
local HeroData = require(ReplicatedStorage.Shared.HeroData)
local Constants = require(ReplicatedStorage.Shared.Constants)
local AbilityHelper = require(ReplicatedStorage.Shared.AbilityHelper)
local AbilityIcons = require(ReplicatedStorage.Shared.AbilityIcons)

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local SkillBarController = Knit.CreateController({
	Name = "SkillBarController",
})

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

SkillBarController._screenGui = nil :: ScreenGui?
SkillBarController._barFrame = nil :: Frame?
SkillBarController._abilitySlots = {} :: { Frame } -- 4 ability slots
SkillBarController._statSlot = nil :: Frame? -- attribute bonus slot
SkillBarController._cooldownOverlays = {} :: { Frame } -- cooldown overlays for slots 1-4
SkillBarController._pointsLabel = nil :: TextLabel?
SkillBarController._levelLabel = nil :: TextLabel?
SkillBarController._tooltipFrame = nil :: Frame?
SkillBarController._levelUpLabel = nil :: TextLabel?
SkillBarController._skillPoints = 0 :: number
SkillBarController._heroLevel = 1 :: number
SkillBarController._abilityLevels = { 0, 0, 0, 0, 0 } :: { number }
SkillBarController._heroId = nil :: string?
SkillBarController._respawnOverlay = nil :: Frame?
SkillBarController._respawnCounterId = 0 :: number
SkillBarController._attackMoveMode = false :: boolean
SkillBarController._targetIndicator = nil :: Highlight?
SkillBarController._groundTargetSlot = 0 :: number -- slot being ground-targeted (0 = none)
SkillBarController._groundTargetCircle = nil :: Part? -- targeting reticle on ground
SkillBarController._petActive = false :: boolean -- whether summoned pet is alive
SkillBarController._wKeyDownTime = 0 :: number -- os.clock() when W was pressed (for hold detection)
SkillBarController._wHoldHandled = false :: boolean -- whether the 2s hold was already processed

--------------------------------------------------------------------------------
-- Colors
--------------------------------------------------------------------------------

local COLOR_BG = Color3.fromRGB(25, 25, 30)
local COLOR_SLOT = Color3.fromRGB(40, 40, 50)
local COLOR_SLOT_LEARNED = Color3.fromRGB(50, 55, 70)
local COLOR_PLUS = Color3.fromRGB(255, 200, 40)
local COLOR_PLUS_BG = Color3.fromRGB(60, 50, 20)
local COLOR_KEY = Color3.fromRGB(200, 200, 200)
local COLOR_NAME = Color3.fromRGB(180, 180, 190)
local COLOR_LEVEL = Color3.fromRGB(100, 200, 255)
local COLOR_POINTS = Color3.fromRGB(255, 215, 80)
local COLOR_UNLEARNABLE = Color3.fromRGB(100, 100, 100)
local COLOR_STAT_ACCENT = Color3.fromRGB(180, 140, 255)
local COLOR_LEVELUP = Color3.fromRGB(255, 215, 80)
local COLOR_TOOLTIP_BG = Color3.fromRGB(20, 20, 25)
local COLOR_TOOLTIP_TEXT = Color3.fromRGB(220, 220, 220)
local COLOR_TOOLTIP_TITLE = Color3.fromRGB(255, 255, 255)

local SLOT_SIZE = 70
local SLOT_GAP = 6
local KEY_LABELS = { "Q", "W", "E", "R", "T" }

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function SkillBarController:KnitInit()
	-- Disable default Roblox backpack/toolbar so it doesn't overlap our skill bar
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
	self:_createUI()
end

function SkillBarController:KnitStart()
	local HeroService = Knit.GetService("HeroService")

	-- Listen for hero selection to populate ability names
	HeroService.HeroSelected:Connect(function(userId: number, heroId: string)
		local player = Players.LocalPlayer
		if player and userId == player.UserId then
			self._heroId = heroId
			self:_refreshSlots()
		end
	end)

	-- Listen for skill point changes
	HeroService.SkillPointsChanged:Connect(function(points: number)
		self._skillPoints = points
		self:_refreshSlots()
	end)

	-- Listen for ability level changes
	HeroService.AbilityLeveledUp:Connect(function(slotIndex: number, newLevel: number)
		self._abilityLevels[slotIndex] = newLevel
		self:_refreshSlots()
	end)

	-- Listen for hero level ups
	HeroService.HeroLevelUp:Connect(function(newLevel: number)
		self._heroLevel = newLevel
		self:_updateLevelDisplay()
		self:_showLevelUpNotification(newLevel)
	end)

	-- Ability casting + leveling hotkeys
	local ABILITY_KEYS = {
		[Enum.KeyCode.Q] = 1,
		[Enum.KeyCode.W] = 2,
		[Enum.KeyCode.E] = 3,
		[Enum.KeyCode.R] = 4,
		[Enum.KeyCode.T] = 5,
	}
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		local slotIndex = ABILITY_KEYS[input.KeyCode]

		-- Ctrl + key = level up ability (allow even if gameProcessed for Ctrl combos)
		if slotIndex then
			local ctrlHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
			if ctrlHeld then
				self:_onPlusClicked(slotIndex)
				return
			end
		end

		if gameProcessed then
			return
		end

		-- Q/W/E/R = cast ability (slot 1-4 only)
		if slotIndex and slotIndex <= 4 then
			self:_castAbility(slotIndex)
			return
		end

		-- A key = enter attack-move mode
		if input.KeyCode == Enum.KeyCode.A then
			self._attackMoveMode = true
			return
		end

		-- Escape = cancel attack-move mode and ground targeting
		if input.KeyCode == Enum.KeyCode.Escape then
			self._attackMoveMode = false
			if self._groundTargetSlot > 0 then
				self:_cancelGroundTarget()
			end
		end

		-- Left mouse click
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			-- Ground targeting mode: confirm cast at mouse position
			if self._groundTargetSlot > 0 then
				self:_confirmGroundTarget()
				return
			end
			-- Attack-move mode: target nearest creep
			if self._attackMoveMode then
				self._attackMoveMode = false
				self:_attackMoveClick()
			end
		end
	end)

	-- Also handle right-click to target (always, no attack-move needed)
	-- Right-click also cancels ground targeting mode
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			if self._groundTargetSlot > 0 then
				self:_cancelGroundTarget()
			else
				self:_attackMoveClick()
			end
		end
	end)

	-- Ability cooldown and cast signals
	local AbilityService = Knit.GetService("AbilityService")

	AbilityService.AbilityCooldownStarted:Connect(function(slotIndex: number, cooldown: number)
		self:_startCooldownAnimation(slotIndex, cooldown)
	end)

	AbilityService.AbilityCast:Connect(function(userId: number, slotIndex: number, abilityName: string, targetPosition: Vector3?)
		self:_onAbilityCast(userId, slotIndex, abilityName, targetPosition)
	end)

	-- Pet lifecycle signals
	AbilityService.PetSpawned:Connect(function()
		self._petActive = true
	end)
	AbilityService.PetDied:Connect(function()
		self._petActive = false
	end)

	-- Ranged attack VFX (hero auto-attacks + elemental attacks)
	local HeroCombatService = Knit.GetService("HeroCombatService")
	HeroCombatService.HeroAttacked:Connect(function(userId: number, _creepId: number, damage: number, targetPos: Vector3, _killed: boolean)
		self:_onHeroAutoAttack(userId, targetPos, damage)
	end)
	AbilityService.ElementalAttack:Connect(function(fromPos: Vector3, toPos: Vector3)
		self:_vfxRangedProjectile(fromPos, toPos, Color3.fromRGB(60, 140, 255), 0.8)
	end)

	-- Death timer display
	task.defer(function()
		local ok, DeathTimerService = pcall(function()
			return Knit.GetService("DeathTimerService")
		end)
		if ok and DeathTimerService then
			DeathTimerService.RespawnTimerStarted:Connect(function(remainingTime: number)
				self:_showRespawnTimer(remainingTime)
			end)
			DeathTimerService.RespawnComplete:Connect(function()
				-- Force hide respawn overlay when actually respawned
				if self._respawnOverlay then
					self._respawnOverlay.Visible = false
				end
			end)
		end
	end)

	-- Fetch initial state
	task.defer(function()
		local heroId = HeroService:GetHeroId()
		if heroId then
			self._heroId = heroId
		end
		local points = HeroService:GetSkillPoints()
		if points then
			self._skillPoints = points
		end
		local levels = HeroService:GetAllAbilityLevels()
		if levels then
			self._abilityLevels = levels
		end
		local heroLevel = HeroService:GetLevel()
		if heroLevel then
			self._heroLevel = heroLevel
		end
		self:_refreshSlots()
		self:_updateLevelDisplay()
	end)
end

--------------------------------------------------------------------------------
-- UI Creation
--------------------------------------------------------------------------------

function SkillBarController:_createUI()
	local player = Players.LocalPlayer
	if not player then
		return
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "HLW_SkillBar"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = player.PlayerGui
	self._screenGui = screenGui

	-- Container at bottom center
	local totalWidth = SLOT_SIZE * 5 + SLOT_GAP * 4 + 16
	local barFrame = Instance.new("Frame")
	barFrame.Name = "SkillBar"
	barFrame.Size = UDim2.new(0, totalWidth, 0, SLOT_SIZE + 40)
	barFrame.Position = UDim2.new(0.5, -totalWidth / 2, 1, -(SLOT_SIZE + 48))
	barFrame.BackgroundColor3 = COLOR_BG
	barFrame.BackgroundTransparency = 0.15
	barFrame.BorderSizePixel = 0
	barFrame.Parent = screenGui
	self._barFrame = barFrame

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 8)
	barCorner.Parent = barFrame

	-- Hero level display (left of skill points)
	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "HeroLevel"
	levelLabel.Size = UDim2.new(0, 60, 0, 20)
	levelLabel.Position = UDim2.new(0, 8, 0, 2)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text = "Lv 1"
	levelLabel.Font = Enum.Font.GothamBold
	levelLabel.TextSize = 14
	levelLabel.TextColor3 = COLOR_LEVEL
	levelLabel.TextXAlignment = Enum.TextXAlignment.Left
	levelLabel.Parent = barFrame
	self._levelLabel = levelLabel

	-- Skill points label at top (right-aligned)
	local pointsLabel = Instance.new("TextLabel")
	pointsLabel.Name = "SkillPoints"
	pointsLabel.Size = UDim2.new(1, -70, 0, 20)
	pointsLabel.Position = UDim2.new(0, 70, 0, 2)
	pointsLabel.BackgroundTransparency = 1
	pointsLabel.Text = ""
	pointsLabel.Font = Enum.Font.GothamBold
	pointsLabel.TextSize = 13
	pointsLabel.TextColor3 = COLOR_POINTS
	pointsLabel.TextXAlignment = Enum.TextXAlignment.Right
	pointsLabel.Parent = barFrame
	self._pointsLabel = pointsLabel

	-- Create 5 slots (4 abilities + 1 attribute bonus)
	for i = 1, 5 do
		local xPos = 8 + (i - 1) * (SLOT_SIZE + SLOT_GAP)
		local slot = self:_createSlot(i, xPos)
		slot.Parent = barFrame
		if i <= 4 then
			self._abilitySlots[i] = slot
		else
			self._statSlot = slot
		end
	end

	-- Tooltip frame (hidden, positioned above hovered slot)
	self:_createTooltip(screenGui)

	-- Level-up notification label (centered above skill bar)
	local levelUpLabel = Instance.new("TextLabel")
	levelUpLabel.Name = "LevelUpNotification"
	levelUpLabel.Size = UDim2.new(0, 300, 0, 50)
	levelUpLabel.Position = UDim2.new(0.5, 0, 1, -(SLOT_SIZE + 110))
	levelUpLabel.AnchorPoint = Vector2.new(0.5, 1)
	levelUpLabel.BackgroundTransparency = 1
	levelUpLabel.Text = ""
	levelUpLabel.Font = Enum.Font.GothamBold
	levelUpLabel.TextSize = 28
	levelUpLabel.TextColor3 = COLOR_LEVELUP
	levelUpLabel.TextStrokeTransparency = 0.3
	levelUpLabel.TextStrokeColor3 = Color3.fromRGB(100, 80, 0)
	levelUpLabel.TextTransparency = 1
	levelUpLabel.ZIndex = 10
	levelUpLabel.Parent = screenGui
	self._levelUpLabel = levelUpLabel
end

function SkillBarController:_createSlot(index: number, xPos: number): Frame
	local slot = Instance.new("Frame")
	slot.Name = "Slot_" .. tostring(index)
	slot.Size = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE)
	slot.Position = UDim2.new(0, xPos, 0, 24)
	slot.BackgroundColor3 = COLOR_SLOT
	slot.BorderSizePixel = 0

	local slotCorner = Instance.new("UICorner")
	slotCorner.CornerRadius = UDim.new(0, 6)
	slotCorner.Parent = slot

	-- Key label (Q/W/E/R/T)
	local keyLabel = Instance.new("TextLabel")
	keyLabel.Name = "Key"
	keyLabel.Size = UDim2.new(0, 20, 0, 14)
	keyLabel.Position = UDim2.new(0, 3, 0, 2)
	keyLabel.BackgroundTransparency = 1
	keyLabel.Text = KEY_LABELS[index] or ""
	keyLabel.Font = Enum.Font.GothamBold
	keyLabel.TextSize = 11
	keyLabel.TextColor3 = COLOR_KEY
	keyLabel.TextXAlignment = Enum.TextXAlignment.Left
	keyLabel.Parent = slot

	-- Ability name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "AbilityName"
	nameLabel.Size = UDim2.new(1, -6, 0, 22)
	nameLabel.Position = UDim2.new(0, 3, 0, 16)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = ""
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 9
	nameLabel.TextColor3 = COLOR_NAME
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextWrapped = true
	nameLabel.Parent = slot

	-- Level indicator
	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "Level"
	levelLabel.Size = UDim2.new(1, -6, 0, 14)
	levelLabel.Position = UDim2.new(0, 3, 1, -16)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text = ""
	levelLabel.Font = Enum.Font.GothamMedium
	levelLabel.TextSize = 11
	levelLabel.TextColor3 = COLOR_LEVEL
	levelLabel.TextXAlignment = Enum.TextXAlignment.Left
	levelLabel.Parent = slot

	-- "+" button (hidden by default, ZIndex=3 to sit above HoverZone)
	local plusBtn = Instance.new("TextButton")
	plusBtn.Name = "PlusButton"
	plusBtn.Size = UDim2.new(0, 22, 0, 22)
	plusBtn.Position = UDim2.new(1, -24, 0, 2)
	plusBtn.BackgroundColor3 = COLOR_PLUS_BG
	plusBtn.BorderSizePixel = 0
	plusBtn.Text = "+"
	plusBtn.Font = Enum.Font.GothamBold
	plusBtn.TextSize = 16
	plusBtn.TextColor3 = COLOR_PLUS
	plusBtn.Visible = false
	plusBtn.AutoButtonColor = true
	plusBtn.ZIndex = 3
	plusBtn.Parent = slot

	local plusCorner = Instance.new("UICorner")
	plusCorner.CornerRadius = UDim.new(0, 4)
	plusCorner.Parent = plusBtn

	plusBtn.Activated:Connect(function()
		self:_onPlusClicked(index)
	end)

	-- Ability icon (centered in slot, behind labels)
	local iconContainer = Instance.new("Frame")
	iconContainer.Name = "AbilityIcon"
	iconContainer.Size = UDim2.fromOffset(28, 28)
	iconContainer.Position = UDim2.new(0.5, -14, 0, 18)
	iconContainer.BackgroundTransparency = 1
	iconContainer.ZIndex = 1
	iconContainer.Parent = slot

	-- Level pips container (underneath the slot)
	local pipContainer = Instance.new("Frame")
	pipContainer.Name = "LevelPips"
	pipContainer.Size = UDim2.new(1, 0, 0, 8)
	pipContainer.Position = UDim2.new(0, 0, 1, 2)
	pipContainer.BackgroundTransparency = 1
	pipContainer.Parent = slot

	local pipLayout = Instance.new("UIListLayout")
	pipLayout.FillDirection = Enum.FillDirection.Horizontal
	pipLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	pipLayout.Padding = UDim.new(0, 2)
	pipLayout.Parent = pipContainer

	-- Cooldown overlay (ability slots 1-4 only)
	-- Grey bar that shrinks top-to-bottom as cooldown expires
	if index <= 4 then
		local cdContainer = Instance.new("Frame")
		cdContainer.Name = "CooldownOverlay"
		cdContainer.Size = UDim2.fromScale(1, 1)
		cdContainer.BackgroundTransparency = 1
		cdContainer.BorderSizePixel = 0
		cdContainer.ClipsDescendants = true
		cdContainer.ZIndex = 4
		cdContainer.Visible = false
		cdContainer.Parent = slot

		-- Grey fill that shrinks from bottom (revealing ability from bottom up)
		local fill = Instance.new("Frame")
		fill.Name = "CooldownFill"
		fill.Size = UDim2.fromScale(1, 1)
		fill.Position = UDim2.fromScale(0, 0)
		fill.BackgroundColor3 = Color3.new(0, 0, 0)
		fill.BackgroundTransparency = 0.45
		fill.BorderSizePixel = 0
		fill.ZIndex = 4
		fill.Parent = cdContainer

		-- Countdown text (centered)
		local cdLabel = Instance.new("TextLabel")
		cdLabel.Name = "CDText"
		cdLabel.Size = UDim2.fromScale(1, 1)
		cdLabel.BackgroundTransparency = 1
		cdLabel.Text = ""
		cdLabel.Font = Enum.Font.GothamBold
		cdLabel.TextSize = 16
		cdLabel.TextColor3 = Color3.new(1, 1, 1)
		cdLabel.TextStrokeTransparency = 0.3
		cdLabel.ZIndex = 5
		cdLabel.Parent = cdContainer

		self._cooldownOverlays[index] = cdContainer
	end

	-- Hover detection for tooltip (invisible button overlay)
	local hoverBtn = Instance.new("TextButton")
	hoverBtn.Name = "HoverZone"
	hoverBtn.Size = UDim2.fromScale(1, 1)
	hoverBtn.BackgroundTransparency = 1
	hoverBtn.Text = ""
	hoverBtn.ZIndex = 2
	hoverBtn.Parent = slot

	hoverBtn.MouseEnter:Connect(function()
		self:_showTooltip(index, slot)
	end)
	hoverBtn.MouseLeave:Connect(function()
		self:_hideTooltip()
	end)

	return slot
end

--------------------------------------------------------------------------------
-- Tooltip
--------------------------------------------------------------------------------

function SkillBarController:_createTooltip(parent: ScreenGui)
	local tooltip = Instance.new("Frame")
	tooltip.Name = "SkillTooltip"
	tooltip.Size = UDim2.new(0, 220, 0, 100)
	tooltip.BackgroundColor3 = COLOR_TOOLTIP_BG
	tooltip.BackgroundTransparency = 0.08
	tooltip.BorderSizePixel = 0
	tooltip.Visible = false
	tooltip.ZIndex = 20
	tooltip.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = tooltip

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(80, 80, 90)
	stroke.Thickness = 1
	stroke.Parent = tooltip

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -12, 0, 20)
	title.Position = UDim2.new(0, 6, 0, 6)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 14
	title.TextColor3 = COLOR_TOOLTIP_TITLE
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextWrapped = true
	title.ZIndex = 21
	title.Parent = tooltip

	-- Description
	local desc = Instance.new("TextLabel")
	desc.Name = "Description"
	desc.Size = UDim2.new(1, -12, 0, 40)
	desc.Position = UDim2.new(0, 6, 0, 28)
	desc.BackgroundTransparency = 1
	desc.Font = Enum.Font.Gotham
	desc.TextSize = 12
	desc.TextColor3 = COLOR_TOOLTIP_TEXT
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.TextWrapped = true
	desc.ZIndex = 21
	desc.Parent = tooltip

	-- Stats line (cooldown, mana, etc.)
	local stats = Instance.new("TextLabel")
	stats.Name = "Stats"
	stats.Size = UDim2.new(1, -12, 0, 28)
	stats.Position = UDim2.new(0, 6, 0, 68)
	stats.BackgroundTransparency = 1
	stats.Font = Enum.Font.GothamMedium
	stats.TextSize = 11
	stats.TextColor3 = COLOR_LEVEL
	stats.TextXAlignment = Enum.TextXAlignment.Left
	stats.TextYAlignment = Enum.TextYAlignment.Top
	stats.TextWrapped = true
	stats.ZIndex = 21
	stats.Parent = tooltip

	self._tooltipFrame = tooltip
end

function SkillBarController:_showTooltip(slotIndex: number, slot: Frame)
	local tooltip = self._tooltipFrame
	if not tooltip then
		return
	end

	local heroDef = if self._heroId then HeroData[self._heroId] else nil
	local title = tooltip:FindFirstChild("Title") :: TextLabel?
	local desc = tooltip:FindFirstChild("Description") :: TextLabel?
	local stats = tooltip:FindFirstChild("Stats") :: TextLabel?

	if not title or not desc or not stats then
		return
	end

	-- Slot 5 = attribute bonus
	if slotIndex == 5 then
		local attrLevel = self._abilityLevels[5] or 0
		title.Text = "Attribute Bonus"
		desc.Text = "Each level grants +" .. Constants.ATTRIBUTE_BONUS_HP .. " HP, +"
			.. Constants.ATTRIBUTE_BONUS_DAMAGE .. " ATK, +"
			.. Constants.ATTRIBUTE_BONUS_ARMOR .. " Armor."
		stats.Text = "Current: Lv " .. attrLevel .. " (no max)  |  Ctrl+T to level"
	elseif heroDef and heroDef.Abilities[slotIndex] then
		local abilityDef = heroDef.Abilities[slotIndex]
		local abilityLevel = self._abilityLevels[slotIndex] or 0
		title.Text = abilityDef.Name or "???"
		desc.Text = abilityDef.Description or ""

		-- Build stats line
		local statsText = {}
		if abilityDef.IsPassive then
			table.insert(statsText, "Passive")
		else
			-- Cooldown
			local cd = abilityDef.Cooldown
			if type(cd) == "table" then
				local lvl = math.max(1, abilityLevel)
				table.insert(statsText, "CD: " .. (cd[lvl] or cd[1]) .. "s")
			elseif type(cd) == "number" and cd > 0 then
				table.insert(statsText, "CD: " .. cd .. "s")
			end
			-- Mana
			local mana = abilityDef.ManaCost
			if type(mana) == "table" then
				local lvl = math.max(1, abilityLevel)
				table.insert(statsText, "Mana: " .. (mana[lvl] or mana[1]))
			elseif type(mana) == "number" and mana > 0 then
				table.insert(statsText, "Mana: " .. mana)
			end
		end
		if abilityDef.RequiredHeroLevel and abilityDef.RequiredHeroLevel > 1 then
			table.insert(statsText, "Req Lv " .. abilityDef.RequiredHeroLevel)
		end
		table.insert(statsText, KEY_LABELS[slotIndex] .. " to cast")
		table.insert(statsText, "Ctrl+" .. KEY_LABELS[slotIndex] .. " to level")
		stats.Text = table.concat(statsText, "  |  ")
	else
		title.Text = KEY_LABELS[slotIndex] or ""
		desc.Text = "No ability"
		stats.Text = ""
	end

	-- Position tooltip above the slot
	local absPos = slot.AbsolutePosition
	tooltip.Position = UDim2.fromOffset(absPos.X - 10, absPos.Y - tooltip.Size.Y.Offset - 8)
	tooltip.Visible = true
end

function SkillBarController:_hideTooltip()
	if self._tooltipFrame then
		self._tooltipFrame.Visible = false
	end
end

--------------------------------------------------------------------------------
-- Hero Level Display
--------------------------------------------------------------------------------

function SkillBarController:_updateLevelDisplay()
	if self._levelLabel then
		self._levelLabel.Text = "Lv " .. self._heroLevel
	end
end

--------------------------------------------------------------------------------
-- Level-Up Sound
--------------------------------------------------------------------------------

function SkillBarController:_playLevelUpSound()
	-- Use a Roblox built-in achievement sound
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://6042053626" -- bright achievement chime
	sound.Volume = 0.6
	sound.PlaybackSpeed = 1.0
	sound.Parent = SoundService
	sound:Play()

	-- Clean up after playing
	sound.Ended:Once(function()
		sound:Destroy()
	end)

	-- Second tone slightly delayed for the classic "ding-ding" feel
	task.delay(0.15, function()
		local sound2 = Instance.new("Sound")
		sound2.SoundId = "rbxassetid://6042053626"
		sound2.Volume = 0.4
		sound2.PlaybackSpeed = 1.2 -- slightly higher pitch
		sound2.Parent = SoundService
		sound2:Play()
		sound2.Ended:Once(function()
			sound2:Destroy()
		end)
	end)
end

--------------------------------------------------------------------------------
-- Level-Up Notification
--------------------------------------------------------------------------------

function SkillBarController:_showLevelUpNotification(newLevel: number)
	self:_playLevelUpSound()

	local label = self._levelUpLabel
	if not label then
		return
	end

	label.Text = "LEVEL UP! (" .. newLevel .. ") +1 Skill Point"
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0.3

	-- Flash and fade out
	local fadeInfo = TweenInfo.new(2.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeTween = TweenService:Create(label, fadeInfo, {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})

	-- Slight upward drift
	local startY = label.Position.Y.Offset
	label.Position = UDim2.new(0.5, 0, 1, startY)

	local driftTween = TweenService:Create(label, fadeInfo, {
		Position = UDim2.new(0.5, 0, 1, startY - 30),
	})

	fadeTween:Play()
	driftTween:Play()

	fadeTween.Completed:Connect(function()
		label.Position = UDim2.new(0.5, 0, 1, startY)
	end)
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

function SkillBarController:_refreshSlots()
	local heroDef = if self._heroId then HeroData[self._heroId] else nil

	-- Update points label
	if self._pointsLabel then
		if self._skillPoints > 0 then
			self._pointsLabel.Text = self._skillPoints .. " Skill Point" .. (if self._skillPoints > 1 then "s" else "")
		else
			self._pointsLabel.Text = ""
		end
	end

	-- Update 4 ability slots
	for i = 1, 4 do
		local slot = self._abilitySlots[i]
		if not slot then
			continue
		end

		local abilityDef = if heroDef then heroDef.Abilities[i] else nil
		local abilityLevel = self._abilityLevels[i] or 0

		local nameLabel = slot:FindFirstChild("AbilityName") :: TextLabel?
		local levelLabel = slot:FindFirstChild("Level") :: TextLabel?
		local plusBtn = slot:FindFirstChild("PlusButton") :: TextButton?

		if nameLabel then
			nameLabel.Text = if abilityDef then abilityDef.Name else ""
		end

		if levelLabel then
			if abilityDef and abilityLevel > 0 then
				local maxLvl = abilityDef.MaxLevel or 5
				levelLabel.Text = "Lv " .. abilityLevel .. "/" .. maxLvl
				levelLabel.TextColor3 = if abilityLevel >= maxLvl then Color3.fromRGB(100, 255, 100) else COLOR_LEVEL
			elseif abilityDef then
				levelLabel.Text = "Not learned"
				levelLabel.TextColor3 = COLOR_UNLEARNABLE
			else
				levelLabel.Text = ""
			end
		end

		-- Show "+" if can level
		if plusBtn and abilityDef then
			local maxLvl = abilityDef.MaxLevel or 5
			local canLevel = self._skillPoints > 0 and abilityLevel < maxLvl
			plusBtn.Visible = canLevel
		elseif plusBtn then
			plusBtn.Visible = false
		end

		-- Update ability icon
		local iconContainer = slot:FindFirstChild("AbilityIcon")
		if iconContainer then
			-- Clear old icon children
			for _, child in iconContainer:GetChildren() do
				child:Destroy()
			end

			if abilityDef then
				local iconType = if abilityDef.IsPassive then "Buff" else (abilityDef.Type or nil)
				local icon = AbilityIcons.build(iconType, 28)
				icon.Parent = iconContainer
			end
		end

		-- Slot color
		slot.BackgroundColor3 = if abilityLevel > 0 then COLOR_SLOT_LEARNED else COLOR_SLOT

		-- Level pips
		local maxLvl = if abilityDef then (abilityDef.MaxLevel or 5) else 5
		self:_updateLevelPips(slot, abilityLevel, maxLvl)
	end

	-- Update stat slot (attribute bonus)
	local statSlot = self._statSlot
	if statSlot then
		local attrLevel = self._abilityLevels[5] or 0

		local nameLabel = statSlot:FindFirstChild("AbilityName") :: TextLabel?
		local levelLabel = statSlot:FindFirstChild("Level") :: TextLabel?
		local plusBtn = statSlot:FindFirstChild("PlusButton") :: TextButton?

		if nameLabel then
			nameLabel.Text = "Stats"
			nameLabel.TextColor3 = COLOR_STAT_ACCENT
		end

		if levelLabel then
			if attrLevel > 0 then
				levelLabel.Text = "Lv " .. attrLevel
				levelLabel.TextColor3 = COLOR_STAT_ACCENT
			else
				levelLabel.Text = "+HP/ATK/ARM"
				levelLabel.TextColor3 = COLOR_UNLEARNABLE
			end
		end

		if plusBtn then
			plusBtn.Visible = self._skillPoints > 0
		end

		-- Update stat slot icon
		local statIconContainer = statSlot:FindFirstChild("AbilityIcon")
		if statIconContainer then
			for _, child in statIconContainer:GetChildren() do
				child:Destroy()
			end
			local icon = AbilityIcons.build("Buff", 28)
			icon.Parent = statIconContainer
		end

		statSlot.BackgroundColor3 = if attrLevel > 0 then COLOR_SLOT_LEARNED else COLOR_SLOT

		-- Level pips (attribute bonus has no max, show badge)
		self:_updateLevelPips(statSlot, attrLevel, 0)
	end
end

--------------------------------------------------------------------------------
-- Level Pips (visual dots below each slot showing ability level)
--------------------------------------------------------------------------------

function SkillBarController:_updateLevelPips(slot: Frame, currentLevel: number, maxLevel: number)
	local pipContainer = slot:FindFirstChild("LevelPips") :: Frame?
	if not pipContainer then
		return
	end

	-- Clear old pips (keep UIListLayout)
	for _, child in pipContainer:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	-- For attribute bonus (no max), show a number badge instead of pips
	if maxLevel <= 0 then
		if currentLevel > 0 then
			local badge = Instance.new("Frame")
			badge.Name = "LevelBadge"
			badge.Size = UDim2.new(0, 20, 0, 8)
			badge.BackgroundColor3 = COLOR_STAT_ACCENT
			badge.BorderSizePixel = 0
			badge.Parent = pipContainer

			local badgeCorner = Instance.new("UICorner")
			badgeCorner.CornerRadius = UDim.new(0, 3)
			badgeCorner.Parent = badge

			local badgeText = Instance.new("TextLabel")
			badgeText.Size = UDim2.fromScale(1, 1)
			badgeText.BackgroundTransparency = 1
			badgeText.Text = tostring(currentLevel)
			badgeText.Font = Enum.Font.GothamBold
			badgeText.TextSize = 7
			badgeText.TextColor3 = Color3.new(1, 1, 1)
			badgeText.Parent = badge
		end
		return
	end

	-- Create pips for each level slot
	local pipSize = math.min(10, math.floor((SLOT_SIZE - 4) / maxLevel) - 2)
	pipSize = math.max(4, pipSize)

	for i = 1, maxLevel do
		local pip = Instance.new("Frame")
		pip.Name = "Pip_" .. tostring(i)
		pip.Size = UDim2.fromOffset(pipSize, 6)
		pip.BorderSizePixel = 0
		pip.Parent = pipContainer

		local pipCorner = Instance.new("UICorner")
		pipCorner.CornerRadius = UDim.new(0, 2)
		pipCorner.Parent = pip

		if i <= currentLevel then
			pip.BackgroundColor3 = Color3.fromRGB(80, 200, 255) -- filled = bright blue
		else
			pip.BackgroundColor3 = Color3.fromRGB(50, 50, 60) -- empty = dark
		end
	end
end

--------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------

function SkillBarController:_onPlusClicked(slotIndex: number)
	local HeroService = Knit.GetService("HeroService")
	HeroService:LevelUpAbility(slotIndex)
end

--------------------------------------------------------------------------------
-- Respawn Timer
--------------------------------------------------------------------------------

function SkillBarController:_showRespawnTimer(duration: number)
	-- Create overlay if needed
	if not self._respawnOverlay then
		local overlay = Instance.new("Frame")
		overlay.Name = "RespawnOverlay"
		overlay.Size = UDim2.new(0, 260, 0, 80)
		overlay.Position = UDim2.new(0.5, 0, 0.4, 0)
		overlay.AnchorPoint = Vector2.new(0.5, 0.5)
		overlay.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
		overlay.BackgroundTransparency = 0.2
		overlay.BorderSizePixel = 0
		overlay.ZIndex = 30
		overlay.Parent = self._screenGui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = overlay

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.Size = UDim2.new(1, 0, 0, 24)
		title.Position = UDim2.new(0, 0, 0, 8)
		title.BackgroundTransparency = 1
		title.Text = "DEFEATED"
		title.Font = Enum.Font.GothamBold
		title.TextSize = 18
		title.TextColor3 = Color3.fromRGB(255, 80, 80)
		title.ZIndex = 31
		title.Parent = overlay

		local countdown = Instance.new("TextLabel")
		countdown.Name = "Countdown"
		countdown.Size = UDim2.new(1, 0, 0, 30)
		countdown.Position = UDim2.new(0, 0, 0, 36)
		countdown.BackgroundTransparency = 1
		countdown.Text = ""
		countdown.Font = Enum.Font.GothamBold
		countdown.TextSize = 24
		countdown.TextColor3 = Color3.fromRGB(255, 255, 255)
		countdown.ZIndex = 31
		countdown.Parent = overlay

		self._respawnOverlay = overlay
	end

	self._respawnOverlay.Visible = true

	-- Cancel any existing countdown by incrementing counter
	self._respawnCounterId += 1
	local myCounterId = self._respawnCounterId

	-- Countdown loop
	task.spawn(function()
		local remaining = math.ceil(duration)
		while remaining > 0 do
			-- Check if this countdown is still the active one
			if self._respawnCounterId ~= myCounterId then
				return
			end
			local countdown = self._respawnOverlay and self._respawnOverlay:FindFirstChild("Countdown") :: TextLabel?
			if countdown then
				countdown.Text = "Respawning in " .. remaining .. "s"
			end
			task.wait(1)
			remaining -= 1
		end
		-- Only hide if this countdown is still the active one
		if self._respawnCounterId == myCounterId and self._respawnOverlay then
			self._respawnOverlay.Visible = false
		end
	end)
end

--------------------------------------------------------------------------------
-- Ability Casting
--------------------------------------------------------------------------------

function SkillBarController:_castAbility(slotIndex: number)
	-- Slot 2 (W) pet control: if pet is active, command it instead of re-summoning
	if slotIndex == 2 and self._petActive then
		self:_handlePetWPress()
		return
	end

	-- Check if this ability is ground-targetable
	local heroDef = if self._heroId then HeroData[self._heroId] else nil
	if heroDef then
		local abilityDef = heroDef.Abilities[slotIndex]
		if abilityDef and abilityDef.TargetType == "Ground" then
			-- Enter ground targeting mode
			self:_startGroundTarget(slotIndex)
			return
		end
	end

	local AbilityService = Knit.GetService("AbilityService")
	AbilityService:CastAbility(slotIndex)
end

--------------------------------------------------------------------------------
-- Cooldown Animation
--------------------------------------------------------------------------------

function SkillBarController:_startCooldownAnimation(slotIndex: number, cooldown: number)
	local cdContainer = self._cooldownOverlays[slotIndex]
	if not cdContainer then
		return
	end

	local fill = cdContainer:FindFirstChild("CooldownFill") :: Frame?
	if not fill then
		return
	end

	-- Reset fill to full coverage and show
	fill.Size = UDim2.fromScale(1, 1)
	fill.Position = UDim2.fromScale(0, 0)
	cdContainer.Visible = true

	-- Tween the fill: shrink height from 1 → 0 (reveals from bottom up)
	local tweenInfo = TweenInfo.new(cooldown, Enum.EasingStyle.Linear)
	local tween = TweenService:Create(fill, tweenInfo, { Size = UDim2.fromScale(1, 0) })
	tween:Play()

	tween.Completed:Connect(function()
		cdContainer.Visible = false
		fill.Size = UDim2.fromScale(1, 1)
	end)

	-- Update countdown text
	local cdLabel = cdContainer:FindFirstChild("CDText") :: TextLabel?
	if cdLabel then
		task.spawn(function()
			local remaining = cooldown
			while remaining > 0.1 do
				cdLabel.Text = string.format("%.0f", remaining)
				task.wait(0.5)
				remaining -= 0.5
			end
			cdLabel.Text = ""
		end)
	end
end

--------------------------------------------------------------------------------
-- Attack-Move Targeting
--------------------------------------------------------------------------------

function SkillBarController:_attackMoveClick()
	local player = Players.LocalPlayer
	if not player then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local mouse = player:GetMouse()
	local hitPos = mouse.Hit and mouse.Hit.Position

	-- Also check if mouse hit a creep model directly
	local hitTarget = mouse.Target
	local creepModel = nil

	if hitTarget then
		-- Walk up the parent tree to find a creep model
		local current = hitTarget
		while current and current ~= workspace do
			if current.Name:match("^Creep_") then
				creepModel = current
				break
			end
			current = current.Parent :: Instance
		end
	end

	-- If clicked directly on a creep model, target it
	if creepModel then
		local idStr = creepModel.Name:match("^Creep_(%d+)$")
		if idStr then
			local creepId = tonumber(idStr)
			if creepId then
				self:_setTarget(creepId, creepModel)
				return
			end
		end
	end

	-- Otherwise find nearest creep to click position
	if hitPos then
		local creepsFolder = workspace:FindFirstChild("Creeps")
		if not creepsFolder then
			return
		end

		local bestDist = 30 -- max click-to-target distance
		local bestModel = nil
		local bestId = 0

		for _, model in creepsFolder:GetChildren() do
			if not model:IsA("Model") then
				continue
			end
			local idStr = model.Name:match("^Creep_(%d+)$")
			if not idStr then
				continue
			end
			local body = model:FindFirstChild("Body") :: BasePart?
			if not body then
				continue
			end
			local dist = (body.Position - hitPos).Magnitude
			if dist < bestDist then
				bestDist = dist
				bestModel = model
				bestId = tonumber(idStr) or 0
			end
		end

		if bestModel and bestId > 0 then
			self:_setTarget(bestId, bestModel)
		end
	end
end

function SkillBarController:_setTarget(creepId: number, model: Instance)
	local HeroCombatService = Knit.GetService("HeroCombatService")
	HeroCombatService:SetTarget(creepId)

	-- Visual indicator: highlight the targeted creep
	if self._targetIndicator then
		self._targetIndicator:Destroy()
		self._targetIndicator = nil
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "TargetHighlight"
	highlight.FillColor = Color3.fromRGB(255, 50, 50)
	highlight.FillTransparency = 0.7
	highlight.OutlineColor = Color3.fromRGB(255, 0, 0)
	highlight.OutlineTransparency = 0.3
	highlight.Parent = model
	self._targetIndicator = highlight

	-- Auto-remove when model is destroyed or after 10s
	Debris:AddItem(highlight, 10)
end

--------------------------------------------------------------------------------
-- Ground Targeting (for Blizzard and other ground-targeted abilities)
--------------------------------------------------------------------------------

function SkillBarController:_startGroundTarget(slotIndex: number)
	-- Cancel any existing ground target
	self:_cancelGroundTarget()

	self._groundTargetSlot = slotIndex

	-- Create targeting circle on the ground
	local circle = Instance.new("Part")
	circle.Name = "GroundTargetCircle"
	circle.Shape = Enum.PartType.Cylinder
	circle.Size = Vector3.new(0.2, 30, 30) -- 15 radius = 30 diameter
	circle.Anchored = true
	circle.CanCollide = false
	circle.Material = Enum.Material.Neon
	circle.Color = Color3.fromRGB(100, 180, 255)
	circle.Transparency = 0.6
	circle.CFrame = CFrame.new(0, -100, 0) * CFrame.Angles(0, 0, math.rad(90))
	circle.Parent = workspace
	self._groundTargetCircle = circle

	-- Inner ring for visual depth
	local innerRing = Instance.new("Part")
	innerRing.Name = "InnerRing"
	innerRing.Shape = Enum.PartType.Cylinder
	innerRing.Size = Vector3.new(0.25, 28, 28)
	innerRing.Anchored = true
	innerRing.CanCollide = false
	innerRing.Material = Enum.Material.ForceField
	innerRing.Color = Color3.fromRGB(150, 210, 255)
	innerRing.Transparency = 0.7
	innerRing.CFrame = circle.CFrame
	innerRing.Parent = workspace
	Debris:AddItem(innerRing, 30)

	-- Update circle position on RenderStep
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if self._groundTargetSlot <= 0 then
			if connection then
				connection:Disconnect()
			end
			return
		end

		local player = Players.LocalPlayer
		if not player then
			return
		end
		local mouse = player:GetMouse()
		local hitPos = mouse.Hit and mouse.Hit.Position
		if hitPos then
			local groundY = 0.15
			circle.CFrame = CFrame.new(hitPos.X, groundY, hitPos.Z) * CFrame.Angles(0, 0, math.rad(90))
			innerRing.CFrame = CFrame.new(hitPos.X, groundY + 0.05, hitPos.Z) * CFrame.Angles(0, 0, math.rad(90))
		end
	end)
end

function SkillBarController:_confirmGroundTarget()
	local slotIndex = self._groundTargetSlot
	if slotIndex <= 0 then
		return
	end

	local player = Players.LocalPlayer
	if not player then
		return
	end
	local mouse = player:GetMouse()
	local hitPos = mouse.Hit and mouse.Hit.Position

	self:_cancelGroundTarget()

	if hitPos then
		local AbilityService = Knit.GetService("AbilityService")
		AbilityService:CastAbility(slotIndex, hitPos)
	end
end

function SkillBarController:_cancelGroundTarget()
	self._groundTargetSlot = 0
	if self._groundTargetCircle then
		-- Also destroy the inner ring sibling
		local innerRing = workspace:FindFirstChild("InnerRing")
		if innerRing then
			innerRing:Destroy()
		end
		self._groundTargetCircle:Destroy()
		self._groundTargetCircle = nil
	end
end

function SkillBarController:_onAbilityCast(userId: number, _slotIndex: number, abilityName: string, targetPosition: Vector3?)
	-- Find the caster's character
	local caster = nil
	for _, player in Players:GetPlayers() do
		if player.UserId == userId then
			caster = player
			break
		end
	end
	if not caster or not caster.Character then
		return
	end

	local rootPart = caster.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end
	local heroPos = rootPart.Position

	if abilityName == "Blizzard" then
		local center = if targetPosition then targetPosition else heroPos
		self:_vfxBlizzard(center)
	elseif abilityName == "Summon Elemental" then
		self:_vfxSummonElemental(heroPos)
	elseif abilityName == "Bladestorm" then
		self:_vfxBladestorm(heroPos, caster.Character)
	elseif abilityName == "Death Coil" then
		self:_vfxDeathCoil(heroPos)
	elseif abilityName == "Holy Light" or abilityName == "Healing Wave" then
		self:_vfxHeal(heroPos, abilityName == "Holy Light")
	elseif abilityName == "Divine Shield" then
		self:_vfxDivineShield(caster.Character)
	elseif abilityName == "Wind Walk" then
		self:_vfxWindWalk(heroPos)
	elseif abilityName == "Hex" then
		self:_vfxHex(heroPos)
	elseif abilityName == "Death Pact" then
		self:_vfxDeathPact(heroPos)
	end
end

-- Blizzard: D2-inspired ice storm with ground circle and pronounced icicles
function SkillBarController:_vfxBlizzard(center: Vector3)
	task.spawn(function()
		local duration = 4
		local elapsed = 0
		local radius = 15

		-- Pre-cast ground circle (icy AoE indicator)
		local groundCircle = Instance.new("Part")
		groundCircle.Name = "BlizzardCircle"
		groundCircle.Shape = Enum.PartType.Cylinder
		groundCircle.Size = Vector3.new(0.15, radius * 2, radius * 2)
		groundCircle.CFrame = CFrame.new(center.X, 0.1, center.Z) * CFrame.Angles(0, 0, math.rad(90))
		groundCircle.Anchored = true
		groundCircle.CanCollide = false
		groundCircle.Material = Enum.Material.Ice
		groundCircle.Color = Color3.fromRGB(120, 180, 255)
		groundCircle.Transparency = 0.65
		groundCircle.Parent = workspace

		-- Inner pulsing ring
		local innerCircle = Instance.new("Part")
		innerCircle.Name = "BlizzardInner"
		innerCircle.Shape = Enum.PartType.Cylinder
		innerCircle.Size = Vector3.new(0.18, radius * 1.4, radius * 1.4)
		innerCircle.CFrame = CFrame.new(center.X, 0.12, center.Z) * CFrame.Angles(0, 0, math.rad(90))
		innerCircle.Anchored = true
		innerCircle.CanCollide = false
		innerCircle.Material = Enum.Material.ForceField
		innerCircle.Color = Color3.fromRGB(160, 210, 255)
		innerCircle.Transparency = 0.75
		innerCircle.Parent = workspace

		-- Fog/mist at ground level
		local mist = Instance.new("Part")
		mist.Name = "BlizzardMist"
		mist.Shape = Enum.PartType.Cylinder
		mist.Size = Vector3.new(2, radius * 2.2, radius * 2.2)
		mist.CFrame = CFrame.new(center.X, 1, center.Z) * CFrame.Angles(0, 0, math.rad(90))
		mist.Anchored = true
		mist.CanCollide = false
		mist.Material = Enum.Material.ForceField
		mist.Color = Color3.fromRGB(200, 230, 255)
		mist.Transparency = 0.85
		mist.Parent = workspace

		while elapsed < duration do
			-- Spawn 4-6 pronounced ice shards per tick
			for _ = 1, math.random(4, 6) do
				-- Spawn within the circle area
				local angle = math.random() * math.pi * 2
				local dist = math.sqrt(math.random()) * radius -- sqrt for uniform distribution
				local rx = math.cos(angle) * dist
				local rz = math.sin(angle) * dist
				local startPos = center + Vector3.new(rx, 30 + math.random() * 15, rz)
				local endPos = center + Vector3.new(rx, 0, rz)

				-- Large icicle shard
				local shardHeight = 2.0 + math.random() * 2.0
				local shardWidth = 0.5 + math.random() * 0.3
				local shard = Instance.new("Part")
				shard.Name = "IceShard"
				shard.Size = Vector3.new(shardWidth, shardHeight, shardWidth)
				shard.Anchored = true
				shard.CanCollide = false
				shard.Material = Enum.Material.Ice
				-- Vary ice color from white to blue
				local blueShift = math.random(0, 80)
				shard.Color = Color3.fromRGB(170 - blueShift, 210 - blueShift / 2, 255)
				shard.Transparency = 0.15
				shard.CFrame = CFrame.new(startPos) * CFrame.Angles(
					math.rad(math.random(-25, 25)),
					math.rad(math.random(0, 360)),
					math.rad(math.random(-25, 25))
				)
				shard.Parent = workspace

				-- Animate falling fast
				task.spawn(function()
					local fallTime = 0.2 + math.random() * 0.15
					local t = 0
					while t < fallTime do
						local dt = task.wait()
						t += dt
						local alpha = math.min(t / fallTime, 1)
						-- Accelerate downward
						local eased = alpha * alpha
						shard.CFrame = CFrame.new(startPos:Lerp(endPos, eased)) * CFrame.Angles(
							shard.CFrame:ToEulerAnglesXYZ()
						)
					end

					-- Impact: icicle sticks in ground briefly then fades
					shard.Position = endPos + Vector3.new(0, shardHeight * 0.3, 0)
					shard.Size = Vector3.new(shardWidth * 1.3, shardHeight * 0.6, shardWidth * 1.3)
					shard.Material = Enum.Material.Ice
					shard.Color = Color3.fromRGB(200, 235, 255)

					-- Impact frost burst
					local frost = Instance.new("Part")
					frost.Name = "FrostBurst"
					frost.Shape = Enum.PartType.Cylinder
					frost.Size = Vector3.new(0.1, 1, 1)
					frost.CFrame = CFrame.new(endPos.X, 0.05, endPos.Z) * CFrame.Angles(0, 0, math.rad(90))
					frost.Anchored = true
					frost.CanCollide = false
					frost.Material = Enum.Material.Ice
					frost.Color = Color3.fromRGB(210, 240, 255)
					frost.Transparency = 0.4
					frost.Parent = workspace

					-- Expand frost ring
					local expandInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
					local expandTween = TweenService:Create(frost, expandInfo, {
						Size = Vector3.new(0.1, 3.5, 3.5),
						Transparency = 1,
					})
					expandTween:Play()
					Debris:AddItem(frost, 0.4)

					-- Fade out icicle
					task.wait(0.4 + math.random() * 0.3)
					if shard.Parent then
						local fadeInfo = TweenInfo.new(0.3)
						TweenService:Create(shard, fadeInfo, { Transparency = 1 }):Play()
						Debris:AddItem(shard, 0.35)
					end
				end)
			end
			elapsed += 0.2
			task.wait(0.2)
		end

		-- Fade out ground effects
		local fadeInfo = TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(groundCircle, fadeInfo, { Transparency = 1 }):Play()
		TweenService:Create(innerCircle, fadeInfo, { Transparency = 1 }):Play()
		TweenService:Create(mist, fadeInfo, { Transparency = 1 }):Play()
		Debris:AddItem(groundCircle, 1.1)
		Debris:AddItem(innerCircle, 1.1)
		Debris:AddItem(mist, 1.1)
	end)
end

-- Bladestorm: spinning slash lines around hero
function SkillBarController:_vfxBladestorm(center: Vector3, character: Model)
	task.spawn(function()
		local duration = 5
		local elapsed = 0

		while elapsed < duration do
			local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not rootPart then
				break
			end
			local pos = rootPart.Position

			for i = 0, 3 do
				local angle = math.rad(90 * i + elapsed * 360)
				local offset = Vector3.new(math.cos(angle) * 5, 1, math.sin(angle) * 5)
				local slashPos = pos + offset

				local slash = Instance.new("Part")
				slash.Name = "BladestormSlash"
				slash.Size = Vector3.new(3, 0.2, 0.6)
				slash.Anchored = true
				slash.CanCollide = false
				slash.Material = Enum.Material.Neon
				slash.Color = Color3.fromRGB(255, 100, 40)
				slash.Transparency = 0.3
				slash.CFrame = CFrame.lookAt(slashPos, pos) * CFrame.Angles(0, 0, math.rad(math.random(-30, 30)))
				slash.Parent = workspace
				Debris:AddItem(slash, 0.15)
			end

			elapsed += 0.1
			task.wait(0.1)
		end
	end)
end

-- Death Coil: green projectile toward nearest enemy
function SkillBarController:_vfxDeathCoil(heroPos: Vector3)
	-- Find nearest creep model for target direction
	local creepsFolder = workspace:FindFirstChild("Creeps")
	local targetPos = heroPos + Vector3.new(0, 0, 10)

	if creepsFolder then
		local bestDist = 25
		for _, model in creepsFolder:GetChildren() do
			if not model:IsA("Model") then
				continue
			end
			local body = model:FindFirstChild("Body") :: BasePart?
			if body then
				local dist = (body.Position - heroPos).Magnitude
				if dist < bestDist then
					bestDist = dist
					targetPos = body.Position
				end
			end
		end
	end

	local projectile = Instance.new("Part")
	projectile.Name = "DeathCoilBolt"
	projectile.Shape = Enum.PartType.Ball
	projectile.Size = Vector3.new(1.5, 1.5, 1.5)
	projectile.Position = heroPos + Vector3.new(0, 2, 0)
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.Material = Enum.Material.Neon
	projectile.Color = Color3.fromRGB(0, 255, 80)
	projectile.Transparency = 0.1
	projectile.Parent = workspace

	local light = Instance.new("PointLight")
	light.Range = 8
	light.Brightness = 2
	light.Color = Color3.fromRGB(0, 255, 80)
	light.Parent = projectile

	task.spawn(function()
		local startPos = heroPos + Vector3.new(0, 2, 0)
		local flightTime = 0.3
		local t = 0
		while t < flightTime do
			local dt = task.wait()
			t += dt
			projectile.Position = startPos:Lerp(targetPos + Vector3.new(0, 2, 0), math.min(t / flightTime, 1))
		end
		-- Impact flash
		projectile.Size = Vector3.new(3, 3, 3)
		projectile.Transparency = 0.5
		task.wait(0.1)
		projectile:Destroy()
	end)
end

-- Holy Light / Healing Wave: golden or green glow
function SkillBarController:_vfxHeal(heroPos: Vector3, isHoly: boolean)
	local color = if isHoly then Color3.fromRGB(255, 215, 80) else Color3.fromRGB(0, 220, 100)
	local ringCount = 3

	for i = 1, ringCount do
		task.delay(i * 0.15, function()
			local ring = Instance.new("Part")
			ring.Name = "HealRing"
			ring.Shape = Enum.PartType.Cylinder
			ring.Size = Vector3.new(0.2, 2, 2)
			ring.CFrame = CFrame.new(heroPos + Vector3.new(0, 0.5 + i, 0)) * CFrame.Angles(0, 0, math.rad(90))
			ring.Anchored = true
			ring.CanCollide = false
			ring.Material = Enum.Material.Neon
			ring.Color = color
			ring.Transparency = 0.3
			ring.Parent = workspace

			-- Expand and fade
			task.spawn(function()
				local t = 0
				while t < 0.6 do
					local dt = task.wait()
					t += dt
					local scale = 2 + t * 10
					ring.Size = Vector3.new(0.2, scale, scale)
					ring.Transparency = 0.3 + t * 1.2
				end
				ring:Destroy()
			end)
		end)
	end
end

-- Divine Shield: golden bubble
function SkillBarController:_vfxDivineShield(character: Model)
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end

	local bubble = Instance.new("Part")
	bubble.Name = "DivineShieldBubble"
	bubble.Shape = Enum.PartType.Ball
	bubble.Size = Vector3.new(8, 8, 8)
	bubble.Position = rootPart.Position
	bubble.Anchored = true
	bubble.CanCollide = false
	bubble.Material = Enum.Material.ForceField
	bubble.Color = Color3.fromRGB(255, 215, 80)
	bubble.Transparency = 0.6
	bubble.Parent = workspace

	local light = Instance.new("PointLight")
	light.Range = 12
	light.Brightness = 1
	light.Color = Color3.fromRGB(255, 215, 80)
	light.Parent = bubble

	-- Follow the hero and fade after duration
	task.spawn(function()
		local elapsed = 0
		while elapsed < 8 and bubble.Parent do
			local rp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if rp then
				bubble.Position = rp.Position
			else
				break
			end
			elapsed += task.wait()
		end
		if bubble.Parent then
			bubble:Destroy()
		end
	end)
end

-- Wind Walk: shimmer burst
function SkillBarController:_vfxWindWalk(heroPos: Vector3)
	for _ = 1, 8 do
		local particle = Instance.new("Part")
		particle.Name = "WindParticle"
		particle.Size = Vector3.new(0.5, 0.5, 0.5)
		particle.Position = heroPos + Vector3.new(
			(math.random() - 0.5) * 4,
			math.random() * 3,
			(math.random() - 0.5) * 4
		)
		particle.Anchored = true
		particle.CanCollide = false
		particle.Material = Enum.Material.Neon
		particle.Color = Color3.fromRGB(180, 220, 255)
		particle.Transparency = 0.3
		particle.Parent = workspace
		Debris:AddItem(particle, 0.4)
	end
end

-- Hex: purple bolt toward nearest enemy
function SkillBarController:_vfxHex(heroPos: Vector3)
	local creepsFolder = workspace:FindFirstChild("Creeps")
	local targetPos = heroPos + Vector3.new(0, 0, 10)

	if creepsFolder then
		local bestDist = 25
		for _, model in creepsFolder:GetChildren() do
			if not model:IsA("Model") then
				continue
			end
			local body = model:FindFirstChild("Body") :: BasePart?
			if body then
				local dist = (body.Position - heroPos).Magnitude
				if dist < bestDist then
					bestDist = dist
					targetPos = body.Position
				end
			end
		end
	end

	local bolt = Instance.new("Part")
	bolt.Name = "HexBolt"
	bolt.Shape = Enum.PartType.Ball
	bolt.Size = Vector3.new(1, 1, 1)
	bolt.Position = heroPos + Vector3.new(0, 2, 0)
	bolt.Anchored = true
	bolt.CanCollide = false
	bolt.Material = Enum.Material.Neon
	bolt.Color = Color3.fromRGB(150, 50, 255)
	bolt.Transparency = 0.1
	bolt.Parent = workspace

	task.spawn(function()
		local startPos = heroPos + Vector3.new(0, 2, 0)
		local flightTime = 0.25
		local t = 0
		while t < flightTime do
			local dt = task.wait()
			t += dt
			bolt.Position = startPos:Lerp(targetPos + Vector3.new(0, 1, 0), math.min(t / flightTime, 1))
		end
		-- Impact: purple burst
		bolt.Size = Vector3.new(4, 4, 4)
		bolt.Transparency = 0.4
		bolt.Color = Color3.fromRGB(200, 100, 255)
		task.wait(0.2)
		bolt:Destroy()
	end)
end

-- Death Pact: dark red pulse
function SkillBarController:_vfxDeathPact(heroPos: Vector3)
	local pulse = Instance.new("Part")
	pulse.Name = "DeathPactPulse"
	pulse.Shape = Enum.PartType.Ball
	pulse.Size = Vector3.new(2, 2, 2)
	pulse.Position = heroPos
	pulse.Anchored = true
	pulse.CanCollide = false
	pulse.Material = Enum.Material.Neon
	pulse.Color = Color3.fromRGB(180, 0, 0)
	pulse.Transparency = 0.3
	pulse.Parent = workspace

	task.spawn(function()
		local t = 0
		while t < 0.5 do
			local dt = task.wait()
			t += dt
			local scale = 2 + t * 12
			pulse.Size = Vector3.new(scale, scale, scale)
			pulse.Transparency = 0.3 + t * 1.4
		end
		pulse:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Pet Control (W key for Summon Elemental)
--------------------------------------------------------------------------------

function SkillBarController:_handlePetWPress()
	self._wKeyDownTime = os.clock()
	self._wHoldHandled = false

	-- Start a coroutine to detect 2-second hold
	task.spawn(function()
		while UserInputService:IsKeyDown(Enum.KeyCode.W) do
			if os.clock() - self._wKeyDownTime >= 2 then
				-- Held for 2 seconds: pet hold at mouse position
				self._wHoldHandled = true
				self:_petHoldCommand()
				return
			end
			task.wait(0.05)
		end

		-- Key released before 2 seconds: quick command
		if not self._wHoldHandled then
			self:_petQuickCommand()
		end
	end)
end

function SkillBarController:_petQuickCommand()
	-- If hero has a current attack target, retarget pet to it
	local player = Players.LocalPlayer
	if not player then
		return
	end

	-- Check if we clicked on a creep (use mouse target)
	local mouse = player:GetMouse()
	local hitTarget = mouse.Target
	local creepId = 0

	if hitTarget then
		local current = hitTarget
		while current and current ~= workspace do
			local idStr = current.Name:match("^Creep_(%d+)$")
			if idStr then
				creepId = tonumber(idStr) or 0
				break
			end
			current = current.Parent :: Instance
		end
	end

	local AbilityService = Knit.GetService("AbilityService")
	if creepId > 0 then
		-- Retarget pet to this creep
		AbilityService:PetCommand("retarget", creepId)
	else
		-- Move pet to mouse position
		local hitPos = mouse.Hit and mouse.Hit.Position
		if hitPos then
			AbilityService:PetCommand("move", hitPos)
		end
	end
end

function SkillBarController:_petHoldCommand()
	local player = Players.LocalPlayer
	if not player then
		return
	end
	local mouse = player:GetMouse()
	local hitPos = mouse.Hit and mouse.Hit.Position
	if hitPos then
		local AbilityService = Knit.GetService("AbilityService")
		AbilityService:PetCommand("hold", hitPos)
	end
end

--------------------------------------------------------------------------------
-- Ranged Auto-Attack VFX
--------------------------------------------------------------------------------

function SkillBarController:_onHeroAutoAttack(userId: number, targetPos: Vector3, _damage: number)
	-- Only show projectile for ranged heroes (Archmage)
	local caster = nil
	for _, player in Players:GetPlayers() do
		if player.UserId == userId then
			caster = player
			break
		end
	end
	if not caster or not caster.Character then
		return
	end

	-- Check if this hero is ranged
	local ok, HeroService = pcall(function()
		return Knit.GetService("HeroService")
	end)
	if not ok then
		return
	end

	-- Use the hero's character to determine heroId from attribute
	local heroId = caster.Character:GetAttribute("HeroId")
	if not heroId then
		-- Try service call for local player only
		local localPlayer = Players.LocalPlayer
		if caster == localPlayer then
			heroId = self._heroId
		end
	end

	if heroId ~= "Archmage" then
		return
	end

	local rootPart = caster.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end

	self:_vfxRangedProjectile(
		rootPart.Position + Vector3.new(0, 2, 0),
		targetPos + Vector3.new(0, 1, 0),
		Color3.fromRGB(100, 180, 255),
		1.0
	)
end

function SkillBarController:_vfxRangedProjectile(fromPos: Vector3, toPos: Vector3, color: Color3, size: number)
	local projectile = Instance.new("Part")
	projectile.Name = "RangedBolt"
	projectile.Shape = Enum.PartType.Ball
	projectile.Size = Vector3.new(size, size, size)
	projectile.Position = fromPos
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.Material = Enum.Material.Neon
	projectile.Color = color
	projectile.Transparency = 0.1
	projectile.Parent = workspace

	local light = Instance.new("PointLight")
	light.Range = 6
	light.Brightness = 1.5
	light.Color = color
	light.Parent = projectile

	task.spawn(function()
		local dist = (toPos - fromPos).Magnitude
		local flightTime = math.clamp(dist / 80, 0.1, 0.4)
		local t = 0
		while t < flightTime do
			local dt = task.wait()
			t += dt
			projectile.Position = fromPos:Lerp(toPos, math.min(t / flightTime, 1))
		end
		-- Small impact flash
		projectile.Size = Vector3.new(size * 1.5, size * 1.5, size * 1.5)
		projectile.Transparency = 0.6
		task.wait(0.05)
		projectile:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Ability VFX (client-side visual effects for all abilities)
--------------------------------------------------------------------------------

-- Summon Elemental: water burst at hero's feet
function SkillBarController:_vfxSummonElemental(heroPos: Vector3)
	-- Summoning circle
	local circle = Instance.new("Part")
	circle.Name = "SummonCircle"
	circle.Shape = Enum.PartType.Cylinder
	circle.Size = Vector3.new(0.1, 1, 1)
	circle.CFrame = CFrame.new(heroPos.X, 0.1, heroPos.Z) * CFrame.Angles(0, 0, math.rad(90))
	circle.Anchored = true
	circle.CanCollide = false
	circle.Material = Enum.Material.Neon
	circle.Color = Color3.fromRGB(60, 140, 255)
	circle.Transparency = 0.3
	circle.Parent = workspace

	-- Expand circle
	local expandInfo = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(circle, expandInfo, {
		Size = Vector3.new(0.1, 8, 8),
		Transparency = 0.7,
	}):Play()

	-- Water splash particles
	task.delay(0.3, function()
		for _ = 1, 8 do
			local splash = Instance.new("Part")
			splash.Name = "WaterSplash"
			splash.Shape = Enum.PartType.Ball
			splash.Size = Vector3.new(0.8, 0.8, 0.8)
			splash.Position = heroPos + Vector3.new(math.random(-2, 2), 0, math.random(-2, 2))
			splash.Anchored = true
			splash.CanCollide = false
			splash.Material = Enum.Material.Glass
			splash.Color = Color3.fromRGB(60, 140, 255)
			splash.Transparency = 0.3
			splash.Parent = workspace

			local riseInfo = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(splash, riseInfo, {
				Position = splash.Position + Vector3.new(0, 4 + math.random() * 3, 0),
				Transparency = 1,
				Size = Vector3.new(0.3, 0.3, 0.3),
			}):Play()
			Debris:AddItem(splash, 0.7)
		end
	end)

	Debris:AddItem(circle, 1.5)
end

return SkillBarController
