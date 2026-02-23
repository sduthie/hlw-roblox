--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local CreepData = require(ReplicatedStorage.Shared.CreepData)
local Util = require(ReplicatedStorage.Shared.Util)

local ShopController = Knit.CreateController({
	Name = "ShopController",
})

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

ShopController._shopOpen = false :: boolean
ShopController._shopFrame = nil :: Frame?
ShopController._creepButtons = {} :: { [string]: TextButton }
ShopController._townHallButton = nil :: TextButton?
ShopController._screenGui = nil :: ScreenGui?
ShopController._currentTier = 1 :: number
ShopController._scrollingFrame = nil :: ScrollingFrame?

--------------------------------------------------------------------------------
-- Constants (local UI)
--------------------------------------------------------------------------------

local PANEL_WIDTH = 280
local PANEL_OFFSCREEN = UDim2.new(1, 0, 0, 0)
local PANEL_ONSCREEN = UDim2.new(1, -PANEL_WIDTH, 0, 0)
local TWEEN_TIME = 0.3
local TWEEN_INFO_OPEN = TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_INFO_CLOSE = TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local COLOR_PANEL_BG = Color3.fromRGB(30, 30, 30)
local COLOR_BUTTON_BG = Color3.fromRGB(45, 45, 45)
local COLOR_BUTTON_HOVER = Color3.fromRGB(60, 60, 60)
local COLOR_TOWNHALL = Color3.fromRGB(100, 50, 150)
local COLOR_TOWNHALL_DISABLED = Color3.fromRGB(60, 40, 80)
local COLOR_FLASH_GREEN = Color3.fromRGB(0, 200, 0)
local COLOR_FLASH_RED = Color3.fromRGB(200, 0, 0)
local COLOR_WHITE = Color3.fromRGB(255, 255, 255)
local COLOR_SEPARATOR = Color3.fromRGB(80, 80, 80)
local COLOR_GOLD_TEXT = Color3.fromRGB(255, 215, 80)
local COLOR_INCOME_TEXT = Color3.fromRGB(130, 220, 130)
local FLASH_DURATION = 0.3

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function ShopController:KnitInit()
	self:_createShopUI()
end

function ShopController:KnitStart()
	local ShopService = Knit.GetService("ShopService")

	ShopService.ItemPurchased:Connect(function(itemId: string)
		self:_onItemPurchased(itemId)
	end)

	ShopService.TownHallUpgraded:Connect(function(newTier: number)
		self._currentTier = newTier
		self:_updateTownHallButton()
		self:_refreshCreepList()
	end)

	-- Fetch initial tier
	local tier = ShopService:GetTownHallTier()
	if tier then
		self._currentTier = tier
		self:_updateTownHallButton()
	end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function ShopController:ToggleShop()
	if not self._shopFrame then
		return
	end

	self._shopOpen = not self._shopOpen

	if self._shopOpen then
		self:_refreshCreepList()
		self:_updateTownHallButton()
		local tween = TweenService:Create(self._shopFrame, TWEEN_INFO_OPEN, {
			Position = PANEL_ONSCREEN,
		})
		tween:Play()
	else
		local tween = TweenService:Create(self._shopFrame, TWEEN_INFO_CLOSE, {
			Position = PANEL_OFFSCREEN,
		})
		tween:Play()
	end
end

--------------------------------------------------------------------------------
-- UI Creation
--------------------------------------------------------------------------------

function ShopController:_createShopUI()
	local player = Players.LocalPlayer
	if not player then
		return
	end

	-- ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "HLW_Shop"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = player.PlayerGui
	self._screenGui = screenGui

	-- Shop panel frame (starts off-screen)
	local shopFrame = Instance.new("Frame")
	shopFrame.Name = "ShopPanel"
	shopFrame.Size = UDim2.new(0, PANEL_WIDTH, 1, 0)
	shopFrame.Position = PANEL_OFFSCREEN
	shopFrame.BackgroundColor3 = COLOR_PANEL_BG
	shopFrame.BackgroundTransparency = 0.1
	shopFrame.BorderSizePixel = 0
	shopFrame.Parent = screenGui
	self._shopFrame = shopFrame

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 8)
	panelCorner.Parent = shopFrame

	-- Title bar
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, 0, 0, 40)
	titleLabel.Position = UDim2.new(0, 0, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "SHOP"
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 24
	titleLabel.TextColor3 = COLOR_WHITE
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	titleLabel.TextYAlignment = Enum.TextYAlignment.Center
	titleLabel.Parent = shopFrame

	-- Separator line below title
	local separator = Instance.new("Frame")
	separator.Name = "Separator"
	separator.Size = UDim2.new(1, -16, 0, 1)
	separator.Position = UDim2.new(0, 8, 0, 40)
	separator.BackgroundColor3 = COLOR_SEPARATOR
	separator.BorderSizePixel = 0
	separator.Parent = shopFrame

	-- TownHall upgrade button
	local townHallButton = Instance.new("TextButton")
	townHallButton.Name = "TownHallUpgrade"
	townHallButton.Size = UDim2.new(1, -16, 0, 50)
	townHallButton.Position = UDim2.new(0, 8, 0, 50)
	townHallButton.BackgroundColor3 = COLOR_TOWNHALL
	townHallButton.BorderSizePixel = 0
	townHallButton.Text = ""
	townHallButton.Font = Enum.Font.GothamBold
	townHallButton.TextSize = 16
	townHallButton.TextColor3 = COLOR_WHITE
	townHallButton.TextWrapped = true
	townHallButton.AutoButtonColor = true
	townHallButton.Parent = shopFrame
	self._townHallButton = townHallButton

	local thCorner = Instance.new("UICorner")
	thCorner.CornerRadius = UDim.new(0, 6)
	thCorner.Parent = townHallButton

	townHallButton.Activated:Connect(function()
		self:_onTownHallClicked()
	end)

	-- Creep scroll area
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "CreepList"
	scrollFrame.Size = UDim2.new(1, -16, 1, -116)
	scrollFrame.Position = UDim2.new(0, 8, 0, 108)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 4
	scrollFrame.ScrollBarImageColor3 = COLOR_SEPARATOR
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.Parent = shopFrame
	self._scrollingFrame = scrollFrame

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = scrollFrame

	-- Initialize TownHall button text
	self:_updateTownHallButton()
end

--------------------------------------------------------------------------------
-- TownHall Button
--------------------------------------------------------------------------------

function ShopController:_updateTownHallButton()
	local button = self._townHallButton
	if not button then
		return
	end

	local tier = self._currentTier
	local maxTier = #Constants.TOWN_HALL_TIERS

	if tier >= maxTier then
		button.Text = "MAX TIER"
		button.BackgroundColor3 = COLOR_TOWNHALL_DISABLED
		button.AutoButtonColor = false
	else
		local nextTier = tier + 1
		local nextTierName = Constants.TOWN_HALL_TIERS[nextTier]
		local cost = Constants.TOWN_HALL_UPGRADE_COST[nextTier]
		-- Format tier name from camelCase: "Stronghold" / "BlackCitadel" -> "Black Citadel"
		local displayName = self:_formatTierName(nextTierName)
		button.Text = "Upgrade to " .. displayName .. " - " .. Util.formatGold(cost) .. "g"
		button.BackgroundColor3 = COLOR_TOWNHALL
		button.AutoButtonColor = true
	end
end

function ShopController:_formatTierName(name: string): string
	-- Insert space before capital letters that follow a lowercase letter
	local formatted = string.gsub(name, "(%l)(%u)", "%1 %2")
	return formatted
end

function ShopController:_onTownHallClicked()
	local tier = self._currentTier
	local maxTier = #Constants.TOWN_HALL_TIERS
	if tier >= maxTier then
		return
	end

	local ShopService = Knit.GetService("ShopService")
	local success = ShopService:UpgradeTownHall()

	local button = self._townHallButton
	if not button then
		return
	end

	if success then
		self:_flashButton(button, COLOR_FLASH_GREEN, COLOR_TOWNHALL)
		-- Tier update and UI refresh happen via the TownHallUpgraded signal
	else
		self:_flashButton(button, COLOR_FLASH_RED, COLOR_TOWNHALL)
	end
end

--------------------------------------------------------------------------------
-- Creep List
--------------------------------------------------------------------------------

function ShopController:_refreshCreepList()
	local scrollFrame = self._scrollingFrame
	if not scrollFrame then
		return
	end

	-- Clear existing buttons
	for _, btn in self._creepButtons do
		btn.Parent = nil
		btn:Destroy()
	end
	table.clear(self._creepButtons)

	-- Also clear any remaining children that are not the UIListLayout
	for _, child in scrollFrame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	-- Fetch available creep IDs from the server
	local ShopService = Knit.GetService("ShopService")
	local availableIds = ShopService:GetAvailableCreeps()

	-- Build sorted list of creep definitions
	local creepList: { { id: string, def: any } } = {}
	for _, creepId in availableIds do
		local def = CreepData[creepId]
		if def then
			table.insert(creepList, { id = creepId, def = def })
		end
	end

	-- Sort by tier first, then by cost
	table.sort(creepList, function(a, b)
		if a.def.Tier ~= b.def.Tier then
			return a.def.Tier < b.def.Tier
		end
		return a.def.Cost < b.def.Cost
	end)

	-- Build buttons
	for layoutOrder, entry in creepList do
		local creepId = entry.id
		local def = entry.def
		local button = self:_createCreepButton(creepId, def, layoutOrder)
		button.Parent = scrollFrame
		self._creepButtons[creepId] = button
	end
end

function ShopController:_createCreepButton(creepId: string, def: any, layoutOrder: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = "Creep_" .. creepId
	button.Size = UDim2.new(1, -16, 0, 60)
	button.BackgroundColor3 = COLOR_BUTTON_BG
	button.BorderSizePixel = 0
	button.Text = ""
	button.AutoButtonColor = false
	button.LayoutOrder = layoutOrder
	button.Parent = nil -- will be parented by caller

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 6)
	btnCorner.Parent = button

	local btnPadding = Instance.new("UIPadding")
	btnPadding.PaddingLeft = UDim.new(0, 8)
	btnPadding.PaddingRight = UDim.new(0, 8)
	btnPadding.PaddingTop = UDim.new(0, 6)
	btnPadding.PaddingBottom = UDim.new(0, 6)
	btnPadding.Parent = button

	-- Creep name (bold, top-left)
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "CreepName"
	nameLabel.Size = UDim2.new(1, 0, 0, 20)
	nameLabel.Position = UDim2.new(0, 0, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = def.Name
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 16
	nameLabel.TextColor3 = COLOR_WHITE
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = button

	-- Tier indicator on right side of name
	local tierLabel = Instance.new("TextLabel")
	tierLabel.Name = "Tier"
	tierLabel.Size = UDim2.new(0, 40, 0, 20)
	tierLabel.Position = UDim2.new(1, -40, 0, 0)
	tierLabel.BackgroundTransparency = 1
	tierLabel.Text = "T" .. tostring(def.Tier)
	tierLabel.Font = Enum.Font.GothamMedium
	tierLabel.TextSize = 12
	tierLabel.TextColor3 = COLOR_SEPARATOR
	tierLabel.TextXAlignment = Enum.TextXAlignment.Right
	tierLabel.Parent = button

	-- Cost in gold (below name, left)
	local costLabel = Instance.new("TextLabel")
	costLabel.Name = "Cost"
	costLabel.Size = UDim2.new(0.5, 0, 0, 18)
	costLabel.Position = UDim2.new(0, 0, 0, 24)
	costLabel.BackgroundTransparency = 1
	costLabel.Text = Util.formatGold(def.Cost) .. "g"
	costLabel.Font = Enum.Font.GothamMedium
	costLabel.TextSize = 14
	costLabel.TextColor3 = COLOR_GOLD_TEXT
	costLabel.TextXAlignment = Enum.TextXAlignment.Left
	costLabel.Parent = button

	-- Income bonus (below name, right)
	local incomeLabel = Instance.new("TextLabel")
	incomeLabel.Name = "Income"
	incomeLabel.Size = UDim2.new(0.5, 0, 0, 18)
	incomeLabel.Position = UDim2.new(0.5, 0, 0, 24)
	incomeLabel.BackgroundTransparency = 1
	incomeLabel.Text = "+" .. tostring(def.IncomeBonus) .. " income"
	incomeLabel.Font = Enum.Font.GothamMedium
	incomeLabel.TextSize = 14
	incomeLabel.TextColor3 = COLOR_INCOME_TEXT
	incomeLabel.TextXAlignment = Enum.TextXAlignment.Left
	incomeLabel.Parent = button

	-- Hover highlight
	button.MouseEnter:Connect(function()
		button.BackgroundColor3 = COLOR_BUTTON_HOVER
	end)

	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = COLOR_BUTTON_BG
	end)

	-- Click handler
	button.Activated:Connect(function()
		self:_onCreepClicked(creepId)
	end)

	return button
end

--------------------------------------------------------------------------------
-- Purchase Actions
--------------------------------------------------------------------------------

function ShopController:_onCreepClicked(creepId: string)
	local ShopService = Knit.GetService("ShopService")
	local success = ShopService:BuyCreep(creepId)

	local button = self._creepButtons[creepId]
	if not button then
		return
	end

	if success then
		self:_flashButton(button, COLOR_FLASH_GREEN, COLOR_BUTTON_BG)
	else
		self:_flashButton(button, COLOR_FLASH_RED, COLOR_BUTTON_BG)
	end
end

function ShopController:_onItemPurchased(itemId: string)
	-- Generic purchase confirmation feedback (fired via signal for any item)
	-- The specific creep/townhall feedback is handled inline in the click handlers
	print("[HLW] Shop: purchased", itemId)
end

--------------------------------------------------------------------------------
-- Visual Feedback
--------------------------------------------------------------------------------

function ShopController:_flashButton(button: GuiButton, flashColor: Color3, restoreColor: Color3)
	button.BackgroundColor3 = flashColor

	local tweenInfo = TweenInfo.new(FLASH_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(button, tweenInfo, {
		BackgroundColor3 = restoreColor,
	})
	tween:Play()
end

return ShopController
