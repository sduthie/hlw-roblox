--!strict

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local HeroData = require(ReplicatedStorage.Shared.HeroData)

local AbilityBarController = Knit.CreateController({
	Name = "AbilityBarController",
})

AbilityBarController._screenGui = nil :: ScreenGui?
AbilityBarController._barFrame = nil :: Frame?
AbilityBarController._healthBar = nil :: Frame?
AbilityBarController._healthFill = nil :: Frame?
AbilityBarController._healthLabel = nil :: TextLabel?
AbilityBarController._manaBar = nil :: Frame?
AbilityBarController._manaFill = nil :: Frame?
AbilityBarController._manaLabel = nil :: TextLabel?
AbilityBarController._slots = {} :: { Frame }
AbilityBarController._cooldownOverlays = {} :: { Frame }
AbilityBarController._slotLabels = {} :: { TextLabel }
AbilityBarController._lockedOverlays = {} :: { Frame }
AbilityBarController._heroId = nil :: string?
AbilityBarController._heroLevel = 1 :: number

local HOTKEYS = { "Q", "W", "E", "R" }
local SLOT_SIZE = 60
local SLOT_GAP = 6
local BAR_WIDTH = SLOT_SIZE * 4 + SLOT_GAP * 3
local HEALTH_BAR_WIDTH = 200
local HEALTH_BAR_HEIGHT = 12

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function AbilityBarController:KnitInit()
	-- Disabled: ability bar merged into SkillBarController
end

function AbilityBarController:KnitStart()
	-- Disabled: ability bar merged into SkillBarController
end

--------------------------------------------------------------------------------
-- UI Construction
--------------------------------------------------------------------------------

function AbilityBarController:_createUI()
	local player = Players.LocalPlayer
	if not player then
		return
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "HLW_AbilityBar"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = player.PlayerGui
	self._screenGui = screenGui

	-- Container for bars + ability slots, bottom-center
	local container = Instance.new("Frame")
	container.Name = "AbilityContainer"
	container.Size = UDim2.new(0, BAR_WIDTH, 0, SLOT_SIZE + HEALTH_BAR_HEIGHT * 2 + 20)
	container.Position = UDim2.new(0.5, 0, 1, -10)
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.BackgroundTransparency = 1
	container.Parent = screenGui
	self._barFrame = container

	-- Health bar
	local healthBarBg = Instance.new("Frame")
	healthBarBg.Name = "HealthBarBg"
	healthBarBg.Size = UDim2.new(0, HEALTH_BAR_WIDTH, 0, HEALTH_BAR_HEIGHT)
	healthBarBg.Position = UDim2.new(0.5, 0, 0, 0)
	healthBarBg.AnchorPoint = Vector2.new(0.5, 0)
	healthBarBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	healthBarBg.BorderSizePixel = 0
	healthBarBg.Parent = container
	self._healthBar = healthBarBg

	local healthCorner = Instance.new("UICorner")
	healthCorner.CornerRadius = UDim.new(0, 4)
	healthCorner.Parent = healthBarBg

	local healthFill = Instance.new("Frame")
	healthFill.Name = "Fill"
	healthFill.Size = UDim2.new(1, 0, 1, 0)
	healthFill.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
	healthFill.BorderSizePixel = 0
	healthFill.Parent = healthBarBg
	self._healthFill = healthFill

	local healthFillCorner = Instance.new("UICorner")
	healthFillCorner.CornerRadius = UDim.new(0, 4)
	healthFillCorner.Parent = healthFill

	local healthLabel = Instance.new("TextLabel")
	healthLabel.Name = "HealthText"
	healthLabel.Size = UDim2.new(1, 0, 1, 0)
	healthLabel.BackgroundTransparency = 1
	healthLabel.Text = ""
	healthLabel.TextColor3 = Color3.new(1, 1, 1)
	healthLabel.TextScaled = true
	healthLabel.Font = Enum.Font.GothamBold
	healthLabel.ZIndex = 2
	healthLabel.Parent = healthBarBg
	self._healthLabel = healthLabel

	-- Mana bar
	local manaBarBg = Instance.new("Frame")
	manaBarBg.Name = "ManaBarBg"
	manaBarBg.Size = UDim2.new(0, HEALTH_BAR_WIDTH, 0, HEALTH_BAR_HEIGHT)
	manaBarBg.Position = UDim2.new(0.5, 0, 0, HEALTH_BAR_HEIGHT + 4)
	manaBarBg.AnchorPoint = Vector2.new(0.5, 0)
	manaBarBg.BackgroundColor3 = Color3.fromRGB(30, 30, 50)
	manaBarBg.BorderSizePixel = 0
	manaBarBg.Parent = container
	self._manaBar = manaBarBg

	local manaCorner = Instance.new("UICorner")
	manaCorner.CornerRadius = UDim.new(0, 4)
	manaCorner.Parent = manaBarBg

	local manaFill = Instance.new("Frame")
	manaFill.Name = "Fill"
	manaFill.Size = UDim2.new(1, 0, 1, 0)
	manaFill.BackgroundColor3 = Color3.fromRGB(50, 100, 230)
	manaFill.BorderSizePixel = 0
	manaFill.Parent = manaBarBg
	self._manaFill = manaFill

	local manaFillCorner = Instance.new("UICorner")
	manaFillCorner.CornerRadius = UDim.new(0, 4)
	manaFillCorner.Parent = manaFill

	local manaLabel = Instance.new("TextLabel")
	manaLabel.Name = "ManaText"
	manaLabel.Size = UDim2.new(1, 0, 1, 0)
	manaLabel.BackgroundTransparency = 1
	manaLabel.Text = ""
	manaLabel.TextColor3 = Color3.new(1, 1, 1)
	manaLabel.TextScaled = true
	manaLabel.Font = Enum.Font.GothamBold
	manaLabel.ZIndex = 2
	manaLabel.Parent = manaBarBg
	self._manaLabel = manaLabel

	-- Ability slots
	local slotsYOffset = HEALTH_BAR_HEIGHT * 2 + 12
	for i = 1, 4 do
		local xPos = (i - 1) * (SLOT_SIZE + SLOT_GAP)

		local slot = Instance.new("Frame")
		slot.Name = "Slot" .. i
		slot.Size = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE)
		slot.Position = UDim2.new(0, xPos, 0, slotsYOffset)
		slot.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
		slot.BorderSizePixel = 0
		slot.Parent = container

		local slotCorner = Instance.new("UICorner")
		slotCorner.CornerRadius = UDim.new(0, 6)
		slotCorner.Parent = slot

		-- Ability name label
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "AbilityName"
		nameLabel.Size = UDim2.new(1, -4, 0.6, 0)
		nameLabel.Position = UDim2.new(0, 2, 0, 2)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = ""
		nameLabel.TextColor3 = Color3.new(1, 1, 1)
		nameLabel.TextScaled = true
		nameLabel.TextWrapped = true
		nameLabel.Font = Enum.Font.GothamMedium
		nameLabel.ZIndex = 2
		nameLabel.Parent = slot
		self._slotLabels[i] = nameLabel

		-- Hotkey label
		local hotkeyLabel = Instance.new("TextLabel")
		hotkeyLabel.Name = "Hotkey"
		hotkeyLabel.Size = UDim2.new(0, 20, 0, 16)
		hotkeyLabel.Position = UDim2.new(1, -22, 1, -18)
		hotkeyLabel.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
		hotkeyLabel.BackgroundTransparency = 0.3
		hotkeyLabel.Text = HOTKEYS[i]
		hotkeyLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
		hotkeyLabel.TextScaled = true
		hotkeyLabel.Font = Enum.Font.GothamBold
		hotkeyLabel.ZIndex = 3
		hotkeyLabel.Parent = slot

		local hotkeyCorner = Instance.new("UICorner")
		hotkeyCorner.CornerRadius = UDim.new(0, 3)
		hotkeyCorner.Parent = hotkeyLabel

		-- Cooldown overlay (full slot size, clips from top to bottom)
		local cdOverlay = Instance.new("Frame")
		cdOverlay.Name = "CooldownOverlay"
		cdOverlay.Size = UDim2.new(1, 0, 0, 0) -- starts invisible (0 height)
		cdOverlay.Position = UDim2.new(0, 0, 0, 0)
		cdOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
		cdOverlay.BackgroundTransparency = 0.5
		cdOverlay.BorderSizePixel = 0
		cdOverlay.ZIndex = 4
		cdOverlay.Parent = slot

		local cdCorner = Instance.new("UICorner")
		cdCorner.CornerRadius = UDim.new(0, 6)
		cdCorner.Parent = cdOverlay

		self._cooldownOverlays[i] = cdOverlay

		-- Locked overlay
		local lockedOverlay = Instance.new("Frame")
		lockedOverlay.Name = "LockedOverlay"
		lockedOverlay.Size = UDim2.new(1, 0, 1, 0)
		lockedOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
		lockedOverlay.BackgroundTransparency = 0.7
		lockedOverlay.BorderSizePixel = 0
		lockedOverlay.ZIndex = 5
		lockedOverlay.Visible = true
		lockedOverlay.Parent = slot

		local lockedCorner = Instance.new("UICorner")
		lockedCorner.CornerRadius = UDim.new(0, 6)
		lockedCorner.Parent = lockedOverlay

		local lockLabel = Instance.new("TextLabel")
		lockLabel.Name = "LockLabel"
		lockLabel.Size = UDim2.new(1, 0, 1, 0)
		lockLabel.BackgroundTransparency = 1
		lockLabel.Text = "Locked"
		lockLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
		lockLabel.TextScaled = true
		lockLabel.Font = Enum.Font.GothamBold
		lockLabel.ZIndex = 6
		lockLabel.Parent = lockedOverlay

		self._lockedOverlays[i] = lockedOverlay
		self._slots[i] = slot
	end

	-- Start hidden
	container.Visible = false
end

--------------------------------------------------------------------------------
-- Phase visibility
--------------------------------------------------------------------------------

function AbilityBarController:_onPhaseChanged(phase: string)
	local container = self._barFrame
	if not container then
		return
	end
	container.Visible = (phase == Constants.PHASE_PLAYING)
end

--------------------------------------------------------------------------------
-- Slot updates
--------------------------------------------------------------------------------

function AbilityBarController:_updateSlots()
	local heroId = self._heroId
	if not heroId then
		return
	end

	local heroDef = HeroData[heroId]
	if not heroDef then
		return
	end

	for i = 1, 4 do
		local ability = heroDef.Abilities[i]
		local nameLabel = self._slotLabels[i]
		local lockedOverlay = self._lockedOverlays[i]

		if not ability then
			if nameLabel then
				nameLabel.Text = ""
			end
			if lockedOverlay then
				lockedOverlay.Visible = true
			end
			continue
		end

		if nameLabel then
			nameLabel.Text = ability.Name
		end

		-- Check if locked (level too low or unimplemented)
		local isLocked = (self._heroLevel < ability.UnlockLevel) or (ability.Type == nil)
		local isPassive = ability.IsPassive == true
		if lockedOverlay then
			lockedOverlay.Visible = isLocked

			-- Show "Passive" label for passive abilities instead of "Locked"
			local lockLabel = lockedOverlay:FindFirstChild("LockLabel") :: TextLabel?
			if lockLabel then
				if isPassive and not isLocked then
					lockedOverlay.Visible = false
				end
				if isLocked and ability.Type == nil then
					lockLabel.Text = "N/A"
				elseif isLocked then
					lockLabel.Text = "Lv " .. ability.UnlockLevel
				end
			end
		end

		-- Passive abilities get a different background
		local slot = self._slots[i]
		if slot and isPassive and ability.Type then
			slot.BackgroundColor3 = Color3.fromRGB(25, 40, 25) -- greenish tint
		end
	end
end

--------------------------------------------------------------------------------
-- Cooldown animation
--------------------------------------------------------------------------------

function AbilityBarController:_startCooldownAnimation(slotIndex: number, cooldown: number)
	local overlay = self._cooldownOverlays[slotIndex]
	if not overlay then
		return
	end

	-- Start with full overlay (top-to-bottom reveal as cooldown ticks)
	overlay.Size = UDim2.new(1, 0, 1, 0)

	local tweenInfo = TweenInfo.new(cooldown, Enum.EasingStyle.Linear)
	local tween = TweenService:Create(overlay, tweenInfo, {
		Size = UDim2.new(1, 0, 0, 0),
	})
	tween:Play()
end

--------------------------------------------------------------------------------
-- Health / Mana bar updates
--------------------------------------------------------------------------------

function AbilityBarController:_updateHealthBar(health: number, maxHealth: number)
	local fill = self._healthFill
	local label = self._healthLabel
	if not fill or not label then
		return
	end

	local pct = math.clamp(health / maxHealth, 0, 1)
	fill.Size = UDim2.new(pct, 0, 1, 0)
	label.Text = math.floor(health) .. " / " .. maxHealth

	-- Color gradient
	if pct > 0.5 then
		fill.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
	elseif pct > 0.25 then
		fill.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
	else
		fill.BackgroundColor3 = Color3.fromRGB(255, 50, 0)
	end
end

function AbilityBarController:_updateManaBar(mana: number, maxMana: number)
	local fill = self._manaFill
	local label = self._manaLabel
	if not fill or not label then
		return
	end

	local pct = math.clamp(mana / maxMana, 0, 1)
	fill.Size = UDim2.new(pct, 0, 1, 0)
	label.Text = math.floor(mana) .. " / " .. maxMana
end

return AbilityBarController
