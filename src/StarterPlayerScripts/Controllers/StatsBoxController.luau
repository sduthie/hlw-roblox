--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local HeroData = require(ReplicatedStorage.Shared.HeroData)
local Constants = require(ReplicatedStorage.Shared.Constants)

local StatsBoxController = Knit.CreateController({
	Name = "StatsBoxController",
})

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

StatsBoxController._screenGui = nil :: ScreenGui?
StatsBoxController._statsFrame = nil :: Frame?
StatsBoxController._heroId = nil :: string?
StatsBoxController._heroLevel = 1 :: number
StatsBoxController._currentHP = 0 :: number
StatsBoxController._maxHP = 0 :: number
StatsBoxController._currentMana = 0 :: number
StatsBoxController._maxMana = 0 :: number
StatsBoxController._attackDamage = 0 :: number
StatsBoxController._armor = 0 :: number

-- Label references
StatsBoxController._heroNameLabel = nil :: TextLabel?
StatsBoxController._levelLabel = nil :: TextLabel?
StatsBoxController._strLabel = nil :: TextLabel?
StatsBoxController._agiLabel = nil :: TextLabel?
StatsBoxController._staLabel = nil :: TextLabel?
StatsBoxController._intLabel = nil :: TextLabel?
StatsBoxController._hpLabel = nil :: TextLabel?
StatsBoxController._manaLabel = nil :: TextLabel?
StatsBoxController._atkLabel = nil :: TextLabel?
StatsBoxController._armorLabel = nil :: TextLabel?
StatsBoxController._critLabel = nil :: TextLabel?
StatsBoxController._dodgeLabel = nil :: TextLabel?
StatsBoxController._blockLabel = nil :: TextLabel?

--------------------------------------------------------------------------------
-- Colors
--------------------------------------------------------------------------------

local COLOR_BG = Color3.fromRGB(20, 20, 25)
local COLOR_HEADER = Color3.fromRGB(255, 255, 255)
local COLOR_LEVEL = Color3.fromRGB(100, 200, 255)
local COLOR_SECTION = Color3.fromRGB(160, 160, 170)
local COLOR_STR = Color3.fromRGB(220, 80, 60)
local COLOR_AGI = Color3.fromRGB(80, 220, 80)
local COLOR_STA = Color3.fromRGB(200, 160, 60)
local COLOR_INT = Color3.fromRGB(80, 140, 255)
local COLOR_STAT = Color3.fromRGB(200, 200, 210)
local COLOR_DERIVED = Color3.fromRGB(180, 180, 190)
local COLOR_DIVIDER = Color3.fromRGB(60, 60, 70)

local PANEL_WIDTH = 170
local PANEL_HEIGHT = 280

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function StatsBoxController:KnitInit()
	self:_createUI()
end

function StatsBoxController:KnitStart()
	local HeroService = Knit.GetService("HeroService")
	local HeroCombatService = Knit.GetService("HeroCombatService")
	local GameService = Knit.GetService("GameService")

	-- Show/hide based on phase
	GameService.PhaseChanged:Connect(function(phase: string, _timer: number)
		self:_onPhaseChanged(phase)
	end)

	-- Hero selection: get hero name and base attributes
	HeroService.HeroSelected:Connect(function(userId: number, heroId: string)
		local player = Players.LocalPlayer
		if player and userId == player.UserId then
			self._heroId = heroId
			self._heroLevel = 1
			self:_refreshAttributes()
			self:_refreshHeroName()
		end
	end)

	-- Level up: recalculate attributes
	HeroService.HeroLevelUp:Connect(function(newLevel: number)
		self._heroLevel = newLevel
		self:_refreshAttributes()
		self:_refreshLevelDisplay()
	end)

	-- Combat state changed: update HP, Mana, ATK, Armor
	HeroCombatService.CombatStateChanged:Connect(function(state: any)
		if type(state) == "table" then
			self._maxHP = state.MaxHealth or self._maxHP
			self._currentHP = state.Health or self._currentHP
			self._maxMana = state.MaxMana or self._maxMana
			self._currentMana = state.Mana or self._currentMana
			self._attackDamage = state.AttackDamage or self._attackDamage
			self._armor = state.Armor or self._armor
			self:_refreshCombatStats()
		end
	end)

	-- Health changed
	HeroCombatService.HeroHealthChanged:Connect(function(currentHP: number, maxHP: number)
		self._currentHP = currentHP
		self._maxHP = maxHP
		self:_refreshCombatStats()
	end)

	-- Mana changed
	HeroCombatService.ManaChanged:Connect(function(currentMana: number, maxMana: number)
		self._currentMana = currentMana
		self._maxMana = maxMana
		self:_refreshCombatStats()
	end)

	-- Fetch initial state
	task.defer(function()
		local heroId = HeroService:GetHeroId()
		if heroId then
			self._heroId = heroId
		end
		local heroLevel = HeroService:GetLevel()
		if heroLevel then
			self._heroLevel = heroLevel
		end
		self:_refreshHeroName()
		self:_refreshAttributes()
		self:_refreshLevelDisplay()
	end)
end

--------------------------------------------------------------------------------
-- Phase visibility
--------------------------------------------------------------------------------

function StatsBoxController:_onPhaseChanged(phase: string)
	local frame = self._statsFrame
	if not frame then
		return
	end

	frame.Visible = (phase == Constants.PHASE_PLAYING)
end

--------------------------------------------------------------------------------
-- UI Creation
--------------------------------------------------------------------------------

function StatsBoxController:_createUI()
	local player = Players.LocalPlayer
	if not player then
		return
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "HLW_StatsBox"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = player.PlayerGui
	self._screenGui = screenGui

	-- Main stats frame
	local statsFrame = Instance.new("Frame")
	statsFrame.Name = "StatsBox"
	statsFrame.Size = UDim2.new(0, PANEL_WIDTH, 0, PANEL_HEIGHT)
	statsFrame.Position = UDim2.new(0, 10, 0, 80)
	statsFrame.BackgroundColor3 = COLOR_BG
	statsFrame.BackgroundTransparency = 0.15
	statsFrame.BorderSizePixel = 0
	statsFrame.Visible = false
	statsFrame.Parent = screenGui
	self._statsFrame = statsFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = statsFrame

	-- Content container with padding
	local contentFrame = Instance.new("Frame")
	contentFrame.Name = "Content"
	contentFrame.Size = UDim2.new(1, -16, 1, -12)
	contentFrame.Position = UDim2.new(0, 8, 0, 6)
	contentFrame.BackgroundTransparency = 1
	contentFrame.Parent = statsFrame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 1)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = contentFrame

	local order = 0

	-- Helper: create a stat row
	local function createRow(name: string, text: string, color: Color3, bold: boolean?): TextLabel
		order += 1
		local label = Instance.new("TextLabel")
		label.Name = name
		label.Size = UDim2.new(1, 0, 0, 18)
		label.BackgroundTransparency = 1
		label.Text = text
		label.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
		label.TextSize = 13
		label.TextColor3 = color
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.LayoutOrder = order
		label.Parent = contentFrame
		return label
	end

	-- Helper: create a divider
	local function createDivider()
		order += 1
		local divider = Instance.new("Frame")
		divider.Name = "Divider_" .. tostring(order)
		divider.Size = UDim2.new(1, 0, 0, 1)
		divider.BackgroundColor3 = COLOR_DIVIDER
		divider.BorderSizePixel = 0
		divider.LayoutOrder = order
		divider.Parent = contentFrame

		-- Add vertical spacing around divider
		local topPad = Instance.new("Frame")
		topPad.Name = "Pad_" .. tostring(order)
		topPad.Size = UDim2.new(1, 0, 0, 3)
		topPad.BackgroundTransparency = 1
		topPad.LayoutOrder = order - 1
		-- Re-insert doesn't work well with layout, so just use margin via UIPadding on divider
	end

	-- Hero Name
	self._heroNameLabel = createRow("HeroName", "--", COLOR_HEADER, true)

	-- Level
	self._levelLabel = createRow("Level", "Level 1", COLOR_LEVEL, false)

	-- Divider
	createDivider()

	-- Primary Attributes section header
	order += 1
	local attrHeader = Instance.new("TextLabel")
	attrHeader.Name = "AttrHeader"
	attrHeader.Size = UDim2.new(1, 0, 0, 16)
	attrHeader.BackgroundTransparency = 1
	attrHeader.Text = "Attributes"
	attrHeader.Font = Enum.Font.GothamMedium
	attrHeader.TextSize = 11
	attrHeader.TextColor3 = COLOR_SECTION
	attrHeader.TextXAlignment = Enum.TextXAlignment.Left
	attrHeader.LayoutOrder = order
	attrHeader.Parent = contentFrame

	self._strLabel = createRow("STR", "STR: 0", COLOR_STR, false)
	self._agiLabel = createRow("AGI", "AGI: 0", COLOR_AGI, false)
	self._staLabel = createRow("STA", "STA: 0", COLOR_STA, false)
	self._intLabel = createRow("INT", "INT: 0", COLOR_INT, false)

	-- Divider
	createDivider()

	-- Combat Stats section header
	order += 1
	local combatHeader = Instance.new("TextLabel")
	combatHeader.Name = "CombatHeader"
	combatHeader.Size = UDim2.new(1, 0, 0, 16)
	combatHeader.BackgroundTransparency = 1
	combatHeader.Text = "Combat"
	combatHeader.Font = Enum.Font.GothamMedium
	combatHeader.TextSize = 11
	combatHeader.TextColor3 = COLOR_SECTION
	combatHeader.TextXAlignment = Enum.TextXAlignment.Left
	combatHeader.LayoutOrder = order
	combatHeader.Parent = contentFrame

	self._hpLabel = createRow("HP", "HP: 0/0", COLOR_STAT, false)
	self._manaLabel = createRow("Mana", "Mana: 0/0", COLOR_STAT, false)
	self._atkLabel = createRow("ATK", "ATK: 0", COLOR_STAT, false)
	self._armorLabel = createRow("Armor", "Armor: 0", COLOR_STAT, false)

	-- Divider
	createDivider()

	-- Derived Stats section header
	order += 1
	local derivedHeader = Instance.new("TextLabel")
	derivedHeader.Name = "DerivedHeader"
	derivedHeader.Size = UDim2.new(1, 0, 0, 16)
	derivedHeader.BackgroundTransparency = 1
	derivedHeader.Text = "Derived"
	derivedHeader.Font = Enum.Font.GothamMedium
	derivedHeader.TextSize = 11
	derivedHeader.TextColor3 = COLOR_SECTION
	derivedHeader.TextXAlignment = Enum.TextXAlignment.Left
	derivedHeader.LayoutOrder = order
	derivedHeader.Parent = contentFrame

	self._critLabel = createRow("Crit", "Crit: 0%", COLOR_DERIVED, false)
	self._dodgeLabel = createRow("Dodge", "Dodge: 0%", COLOR_DERIVED, false)
	self._blockLabel = createRow("Block", "Block: 0%", COLOR_DERIVED, false)
end

--------------------------------------------------------------------------------
-- Refresh Functions
--------------------------------------------------------------------------------

function StatsBoxController:_refreshHeroName()
	local label = self._heroNameLabel
	if not label then
		return
	end

	if self._heroId then
		local heroDef = HeroData[self._heroId]
		if heroDef then
			label.Text = heroDef.Name
		else
			label.Text = self._heroId
		end
	else
		label.Text = "--"
	end
end

function StatsBoxController:_refreshLevelDisplay()
	local label = self._levelLabel
	if label then
		label.Text = "Level " .. self._heroLevel
	end
end

function StatsBoxController:_getAttributeValues(): (number, number, number, number)
	local baseStr, baseAgi, baseSta, baseInt = 15, 15, 15, 15

	if self._heroId then
		local heroDef = HeroData[self._heroId]
		if heroDef and heroDef.Attributes then
			baseStr = heroDef.Attributes.Strength or 15
			baseAgi = heroDef.Attributes.Agility or 15
			baseSta = heroDef.Attributes.Stamina or 15
			baseInt = heroDef.Attributes.Intelligence or 15
		end
	end

	local growth = (self._heroLevel - 1) * 2
	return baseStr + growth, baseAgi + growth, baseSta + growth, baseInt + growth
end

function StatsBoxController:_refreshAttributes()
	local str, agi, sta, int = self:_getAttributeValues()

	if self._strLabel then
		self._strLabel.Text = "STR: " .. str
	end
	if self._agiLabel then
		self._agiLabel.Text = "AGI: " .. agi
	end
	if self._staLabel then
		self._staLabel.Text = "STA: " .. sta
	end
	if self._intLabel then
		self._intLabel.Text = "INT: " .. int
	end

	-- Also refresh derived stats since they depend on attributes
	self:_refreshDerivedStats()
	-- Also refresh level display
	self:_refreshLevelDisplay()
end

function StatsBoxController:_refreshCombatStats()
	if self._hpLabel then
		self._hpLabel.Text = "HP: " .. math.floor(self._currentHP) .. "/" .. math.floor(self._maxHP)
	end
	if self._manaLabel then
		self._manaLabel.Text = "Mana: " .. math.floor(self._currentMana) .. "/" .. math.floor(self._maxMana)
	end
	if self._atkLabel then
		self._atkLabel.Text = "ATK: " .. math.floor(self._attackDamage)
	end
	if self._armorLabel then
		local armorVal = math.floor(self._armor * 10 + 0.5) / 10
		self._armorLabel.Text = "Armor: " .. tostring(armorVal)
	end
end

function StatsBoxController:_refreshDerivedStats()
	local _, agi, sta, _ = self:_getAttributeValues()

	-- Crit: agi * 0.15, capped at 40%
	local crit = math.min(agi * 0.15, 40)
	-- Dodge: agi * 0.1, capped at 30%
	local dodge = math.min(agi * 0.1, 30)
	-- Block: sta * 0.12, capped at 25%
	local block = math.min(sta * 0.12, 25)

	-- Format to 1 decimal
	local function fmt(val: number): string
		return string.format("%.1f", val)
	end

	if self._critLabel then
		self._critLabel.Text = "Crit: " .. fmt(crit) .. "%"
	end
	if self._dodgeLabel then
		self._dodgeLabel.Text = "Dodge: " .. fmt(dodge) .. "%"
	end
	if self._blockLabel then
		self._blockLabel.Text = "Block: " .. fmt(block) .. "%"
	end
end

return StatsBoxController
