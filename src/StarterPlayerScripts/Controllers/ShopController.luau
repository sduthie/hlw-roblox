--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local CreepData = require(ReplicatedStorage.Shared.CreepData)
local ItemData = require(ReplicatedStorage.Shared.ItemData)
local UpgradeData = require(ReplicatedStorage.Shared.UpgradeData)
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
ShopController._itemButtons = {} :: { [string]: TextButton }
ShopController._upgradeButtons = {} :: { [string]: TextButton }
ShopController._townHallButton = nil :: TextButton?
ShopController._screenGui = nil :: ScreenGui?
ShopController._currentTier = 1 :: number
ShopController._scrollingFrame = nil :: ScrollingFrame?
ShopController._activeTab = "Creeps" :: string
ShopController._tabButtons = {} :: { [string]: TextButton }
ShopController._upgradeLevels = {} :: { [string]: number }

--------------------------------------------------------------------------------
-- Constants (local UI)
--------------------------------------------------------------------------------

local PANEL_WIDTH = 300
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
local COLOR_TAB_ACTIVE = Color3.fromRGB(70, 70, 80)
local COLOR_TAB_INACTIVE = Color3.fromRGB(40, 40, 45)
local COLOR_ECON = Color3.fromRGB(80, 160, 80)
local COLOR_HERO = Color3.fromRGB(80, 120, 200)
local COLOR_MINION = Color3.fromRGB(200, 120, 60)
local FLASH_DURATION = 0.3

local COLOR_ITEM = Color3.fromRGB(200, 180, 60)
local TABS = { "Creeps", "Items", "Economy", "Hero", "Minion" }

local CATEGORY_COLORS = {
	Economy = COLOR_ECON,
	Hero = COLOR_HERO,
	Minion = COLOR_MINION,
}

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
		if self._activeTab == "Creeps" then
			self:_refreshContent()
		end
	end)

	-- Listen for upgrade purchases
	local UpgradeService = Knit.GetService("UpgradeService")
	UpgradeService.UpgradePurchased:Connect(function(upgradeId: string, newLevel: number)
		self._upgradeLevels[upgradeId] = newLevel
		self:_refreshContent()
	end)

	-- Fetch initial tier
	local tier = ShopService:GetTownHallTier()
	if tier then
		self._currentTier = tier
		self:_updateTownHallButton()
	end

	-- Fetch initial upgrade levels
	local levels = UpgradeService:GetAllUpgrades()
	if levels then
		self._upgradeLevels = levels
	end

	-- Connect to shop building ProximityPrompts
	self:_connectShopPrompts()

	-- B key to toggle shop
	ContextActionService:BindAction("ToggleShop", function(_, state)
		if state == Enum.UserInputState.Begin then
			self:ToggleShop()
		end
	end, false, Enum.KeyCode.B)
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
		self:_refreshContent()
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
-- Shop Building Interaction
--------------------------------------------------------------------------------

function ShopController:_connectShopPrompts()
	local function connectPrompt(shopPart: BasePart)
		local prompt = shopPart:FindFirstChildOfClass("ProximityPrompt")
		if not prompt then
			return
		end

		prompt.Triggered:Connect(function(_triggerPlayer: Player)
			-- Only block if we know the player is on a different team
			local shopTeamId = shopPart:GetAttribute("TeamId")
			if shopTeamId then
				local ok, TeamService = pcall(function()
					return Knit.GetService("TeamService")
				end)
				if ok and TeamService then
					local myTeam = TeamService:GetTeam()
					if myTeam and myTeam ~= shopTeamId then
						return
					end
				end
			end

			self:ToggleShop()
		end)
	end

	-- Connect existing shop parts
	for _, shopPart in CollectionService:GetTagged("Shop") do
		connectPrompt(shopPart)
	end

	-- Connect any shop parts added later
	CollectionService:GetInstanceAddedSignal("Shop"):Connect(function(shopPart)
		connectPrompt(shopPart)
	end)
end

--------------------------------------------------------------------------------
-- UI Creation
--------------------------------------------------------------------------------

function ShopController:_createShopUI()
	local player = Players.LocalPlayer
	if not player then
		return
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "HLW_Shop"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = player.PlayerGui
	self._screenGui = screenGui

	-- Shop panel frame
	local shopFrame = Instance.new("Frame")
	shopFrame.Name = "ShopPanel"
	shopFrame.Size = UDim2.new(0, PANEL_WIDTH, 1, -95)
	shopFrame.Position = PANEL_OFFSCREEN
	shopFrame.BackgroundColor3 = COLOR_PANEL_BG
	shopFrame.BackgroundTransparency = 0.1
	shopFrame.BorderSizePixel = 0
	shopFrame.Parent = screenGui
	self._shopFrame = shopFrame

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 8)
	panelCorner.Parent = shopFrame

	-- Title
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, 0, 0, 36)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "SHOP [B]"
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 22
	titleLabel.TextColor3 = COLOR_WHITE
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	titleLabel.Parent = shopFrame

	-- Tab bar
	local tabBar = Instance.new("Frame")
	tabBar.Name = "TabBar"
	tabBar.Size = UDim2.new(1, -8, 0, 30)
	tabBar.Position = UDim2.new(0, 4, 0, 36)
	tabBar.BackgroundTransparency = 1
	tabBar.Parent = shopFrame

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 2)
	tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabBar

	for i, tabName in TABS do
		local tabBtn = Instance.new("TextButton")
		tabBtn.Name = "Tab_" .. tabName
		tabBtn.Size = UDim2.new(0, 54, 1, 0)
		tabBtn.BackgroundColor3 = if tabName == self._activeTab then COLOR_TAB_ACTIVE else COLOR_TAB_INACTIVE
		tabBtn.BorderSizePixel = 0
		tabBtn.Text = tabName
		tabBtn.Font = Enum.Font.GothamBold
		tabBtn.TextSize = 11
		tabBtn.TextColor3 = COLOR_WHITE
		tabBtn.LayoutOrder = i
		tabBtn.AutoButtonColor = false
		tabBtn.Parent = tabBar
		self._tabButtons[tabName] = tabBtn

		local tabCorner = Instance.new("UICorner")
		tabCorner.CornerRadius = UDim.new(0, 5)
		tabCorner.Parent = tabBtn

		tabBtn.Activated:Connect(function()
			self:_switchTab(tabName)
		end)
	end

	-- Separator
	local separator = Instance.new("Frame")
	separator.Size = UDim2.new(1, -16, 0, 1)
	separator.Position = UDim2.new(0, 8, 0, 70)
	separator.BackgroundColor3 = COLOR_SEPARATOR
	separator.BorderSizePixel = 0
	separator.Parent = shopFrame

	-- TownHall upgrade button
	local townHallButton = Instance.new("TextButton")
	townHallButton.Name = "TownHallUpgrade"
	townHallButton.Size = UDim2.new(1, -16, 0, 44)
	townHallButton.Position = UDim2.new(0, 8, 0, 78)
	townHallButton.BackgroundColor3 = COLOR_TOWNHALL
	townHallButton.BorderSizePixel = 0
	townHallButton.Text = ""
	townHallButton.Font = Enum.Font.GothamBold
	townHallButton.TextSize = 14
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

	-- Scroll area
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ContentList"
	scrollFrame.Size = UDim2.new(1, -16, 1, -134)
	scrollFrame.Position = UDim2.new(0, 8, 0, 128)
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

	self:_updateTownHallButton()
end

--------------------------------------------------------------------------------
-- Tab Switching
--------------------------------------------------------------------------------

function ShopController:_switchTab(tabName: string)
	self._activeTab = tabName

	-- Update tab button colors
	for name, btn in self._tabButtons do
		btn.BackgroundColor3 = if name == tabName then COLOR_TAB_ACTIVE else COLOR_TAB_INACTIVE
	end

	self:_refreshContent()
end

function ShopController:_refreshContent()
	local scrollFrame = self._scrollingFrame
	if not scrollFrame then
		return
	end

	-- Clear existing content
	for _, child in scrollFrame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(self._creepButtons)
	table.clear(self._itemButtons)
	table.clear(self._upgradeButtons)

	if self._activeTab == "Creeps" then
		self:_populateCreeps(scrollFrame)
	elseif self._activeTab == "Items" then
		self:_populateItems(scrollFrame)
	else
		self:_populateUpgrades(scrollFrame, self._activeTab)
	end
end

--------------------------------------------------------------------------------
-- Creep Tab
--------------------------------------------------------------------------------

function ShopController:_populateCreeps(parent: ScrollingFrame)
	local ShopService = Knit.GetService("ShopService")
	local availableIds = ShopService:GetAvailableCreeps()

	local creepList: { { id: string, def: any } } = {}
	for _, creepId in availableIds do
		local def = CreepData[creepId]
		if def then
			table.insert(creepList, { id = creepId, def = def })
		end
	end

	table.sort(creepList, function(a, b)
		if a.def.Tier ~= b.def.Tier then
			return a.def.Tier < b.def.Tier
		end
		return a.def.Cost < b.def.Cost
	end)

	for layoutOrder, entry in creepList do
		local creepId = entry.id
		local def = entry.def
		local button = self:_createCreepButton(creepId, def, layoutOrder)
		button.Parent = parent
		self._creepButtons[creepId] = button
	end
end

function ShopController:_createCreepButton(creepId: string, def: any, layoutOrder: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = "Creep_" .. creepId
	button.Size = UDim2.new(1, 0, 0, 56)
	button.BackgroundColor3 = COLOR_BUTTON_BG
	button.BorderSizePixel = 0
	button.Text = ""
	button.AutoButtonColor = false
	button.LayoutOrder = layoutOrder

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 6)
	btnCorner.Parent = button

	local btnPadding = Instance.new("UIPadding")
	btnPadding.PaddingLeft = UDim.new(0, 8)
	btnPadding.PaddingRight = UDim.new(0, 8)
	btnPadding.PaddingTop = UDim.new(0, 6)
	btnPadding.PaddingBottom = UDim.new(0, 6)
	btnPadding.Parent = button

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "CreepName"
	nameLabel.Size = UDim2.new(0.6, 0, 0, 18)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = def.Name
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 15
	nameLabel.TextColor3 = COLOR_WHITE
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = button

	local tierLabel = Instance.new("TextLabel")
	tierLabel.Size = UDim2.new(0.4, 0, 0, 18)
	tierLabel.Position = UDim2.new(0.6, 0, 0, 0)
	tierLabel.BackgroundTransparency = 1
	tierLabel.Text = "T" .. def.Tier .. " | HP:" .. def.Health
	tierLabel.Font = Enum.Font.Gotham
	tierLabel.TextSize = 11
	tierLabel.TextColor3 = COLOR_SEPARATOR
	tierLabel.TextXAlignment = Enum.TextXAlignment.Right
	tierLabel.Parent = button

	local costLabel = Instance.new("TextLabel")
	costLabel.Size = UDim2.new(0.5, 0, 0, 16)
	costLabel.Position = UDim2.new(0, 0, 0, 22)
	costLabel.BackgroundTransparency = 1
	costLabel.Text = Util.formatGold(def.Cost) .. "g"
	costLabel.Font = Enum.Font.GothamMedium
	costLabel.TextSize = 13
	costLabel.TextColor3 = COLOR_GOLD_TEXT
	costLabel.TextXAlignment = Enum.TextXAlignment.Left
	costLabel.Parent = button

	local incomeLabel = Instance.new("TextLabel")
	incomeLabel.Size = UDim2.new(0.5, 0, 0, 16)
	incomeLabel.Position = UDim2.new(0.5, 0, 0, 22)
	incomeLabel.BackgroundTransparency = 1
	incomeLabel.Text = "+" .. def.IncomeBonus .. " income"
	incomeLabel.Font = Enum.Font.GothamMedium
	incomeLabel.TextSize = 13
	incomeLabel.TextColor3 = COLOR_INCOME_TEXT
	incomeLabel.TextXAlignment = Enum.TextXAlignment.Left
	incomeLabel.Parent = button

	button.MouseEnter:Connect(function()
		button.BackgroundColor3 = COLOR_BUTTON_HOVER
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = COLOR_BUTTON_BG
	end)
	button.Activated:Connect(function()
		self:_onCreepClicked(creepId)
	end)

	return button
end

--------------------------------------------------------------------------------
-- Items Tab
--------------------------------------------------------------------------------

function ShopController:_populateItems(parent: ScrollingFrame)
	-- Collect all items and sort by cost
	local itemList: { { id: string, def: any } } = {}
	for id, def in ItemData do
		table.insert(itemList, { id = id, def = def })
	end

	table.sort(itemList, function(a, b)
		return a.def.Cost < b.def.Cost
	end)

	-- Section header
	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 24)
	header.BackgroundTransparency = 1
	header.Text = "HERO ITEMS"
	header.Font = Enum.Font.GothamBold
	header.TextSize = 14
	header.TextColor3 = COLOR_ITEM
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.LayoutOrder = 0
	header.Parent = parent

	for i, entry in itemList do
		local btn = self:_createItemButton(entry.id, entry.def, i)
		btn.Parent = parent
		self._itemButtons[entry.id] = btn
	end
end

function ShopController:_createItemButton(itemId: string, def: any, layoutOrder: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = "Item_" .. itemId
	button.Size = UDim2.new(1, 0, 0, 68)
	button.BackgroundColor3 = COLOR_BUTTON_BG
	button.BorderSizePixel = 0
	button.Text = ""
	button.AutoButtonColor = false
	button.LayoutOrder = layoutOrder

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 6)
	btnCorner.Parent = button

	local btnPadding = Instance.new("UIPadding")
	btnPadding.PaddingLeft = UDim.new(0, 8)
	btnPadding.PaddingRight = UDim.new(0, 8)
	btnPadding.PaddingTop = UDim.new(0, 6)
	btnPadding.PaddingBottom = UDim.new(0, 6)
	btnPadding.Parent = button

	-- Accent bar
	local accentBar = Instance.new("Frame")
	accentBar.Name = "Accent"
	accentBar.Size = UDim2.new(0, 3, 1, -4)
	accentBar.Position = UDim2.new(0, -6, 0, 2)
	accentBar.BackgroundColor3 = COLOR_ITEM
	accentBar.BorderSizePixel = 0
	accentBar.Parent = button

	local accentCorner = Instance.new("UICorner")
	accentCorner.CornerRadius = UDim.new(0, 2)
	accentCorner.Parent = accentBar

	-- Name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(0.6, 0, 0, 18)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = def.Name
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextColor3 = COLOR_WHITE
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = button

	-- Cost
	local costLabel = Instance.new("TextLabel")
	costLabel.Size = UDim2.new(0.4, 0, 0, 18)
	costLabel.Position = UDim2.new(0.6, 0, 0, 0)
	costLabel.BackgroundTransparency = 1
	costLabel.Text = Util.formatGold(def.Cost) .. "g"
	costLabel.Font = Enum.Font.GothamBold
	costLabel.TextSize = 13
	costLabel.TextColor3 = COLOR_GOLD_TEXT
	costLabel.TextXAlignment = Enum.TextXAlignment.Right
	costLabel.Parent = button

	-- Description
	local descLabel = Instance.new("TextLabel")
	descLabel.Size = UDim2.new(1, 0, 0, 14)
	descLabel.Position = UDim2.new(0, 0, 0, 20)
	descLabel.BackgroundTransparency = 1
	descLabel.Text = def.Description
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextSize = 11
	descLabel.TextColor3 = Color3.fromRGB(170, 170, 170)
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.Parent = button

	-- Stats line
	local statParts: { string } = {}
	for statName, statValue in def.Stats do
		table.insert(statParts, "+" .. tostring(statValue) .. " " .. statName)
	end
	local statsText = table.concat(statParts, "  ")

	local statsLabel = Instance.new("TextLabel")
	statsLabel.Size = UDim2.new(1, 0, 0, 14)
	statsLabel.Position = UDim2.new(0, 0, 0, 38)
	statsLabel.BackgroundTransparency = 1
	statsLabel.Text = statsText
	statsLabel.Font = Enum.Font.GothamMedium
	statsLabel.TextSize = 11
	statsLabel.TextColor3 = Color3.fromRGB(130, 200, 255)
	statsLabel.TextXAlignment = Enum.TextXAlignment.Left
	statsLabel.Parent = button

	-- Hover / click
	button.MouseEnter:Connect(function()
		button.BackgroundColor3 = COLOR_BUTTON_HOVER
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = COLOR_BUTTON_BG
	end)
	button.Activated:Connect(function()
		self:_onItemClicked(itemId)
	end)

	return button
end

function ShopController:_onItemClicked(itemId: string)
	local ShopService = Knit.GetService("ShopService")
	local success = ShopService:BuyItem(itemId)

	local button = self._itemButtons[itemId]
	if not button then
		return
	end

	if success then
		self:_flashButton(button, COLOR_FLASH_GREEN, COLOR_BUTTON_BG)
	else
		self:_flashButton(button, COLOR_FLASH_RED, COLOR_BUTTON_BG)
	end
end

--------------------------------------------------------------------------------
-- Upgrade Tabs (Economy / Hero / Minion)
--------------------------------------------------------------------------------

function ShopController:_populateUpgrades(parent: ScrollingFrame, category: string)
	-- Collect upgrades for this category
	local upgrades: { { id: string, def: any } } = {}
	for id, def in UpgradeData do
		if def.Category == category then
			table.insert(upgrades, { id = id, def = def })
		end
	end

	-- Sort by first cost (cheapest first)
	table.sort(upgrades, function(a, b)
		return (a.def.Costs[1] or 0) < (b.def.Costs[1] or 0)
	end)

	-- Section header
	local catColor = CATEGORY_COLORS[category] or COLOR_WHITE
	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 24)
	header.BackgroundTransparency = 1
	header.Text = string.upper(category) .. " UPGRADES"
	header.Font = Enum.Font.GothamBold
	header.TextSize = 14
	header.TextColor3 = catColor
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.LayoutOrder = 0
	header.Parent = parent

	for i, entry in upgrades do
		local btn = self:_createUpgradeButton(entry.id, entry.def, i, catColor)
		btn.Parent = parent
		self._upgradeButtons[entry.id] = btn
	end
end

function ShopController:_createUpgradeButton(upgradeId: string, def: any, layoutOrder: number, accentColor: Color3): TextButton
	local currentLevel = self._upgradeLevels[upgradeId] or 0
	local maxed = currentLevel >= def.MaxLevel
	local nextCost = if maxed then 0 else (def.Costs[currentLevel + 1] or 0)

	local button = Instance.new("TextButton")
	button.Name = "Upgrade_" .. upgradeId
	button.Size = UDim2.new(1, 0, 0, 68)
	button.BackgroundColor3 = COLOR_BUTTON_BG
	button.BorderSizePixel = 0
	button.Text = ""
	button.AutoButtonColor = false
	button.LayoutOrder = layoutOrder

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 6)
	btnCorner.Parent = button

	local btnPadding = Instance.new("UIPadding")
	btnPadding.PaddingLeft = UDim.new(0, 8)
	btnPadding.PaddingRight = UDim.new(0, 8)
	btnPadding.PaddingTop = UDim.new(0, 6)
	btnPadding.PaddingBottom = UDim.new(0, 6)
	btnPadding.Parent = button

	-- Accent bar on left
	local accentBar = Instance.new("Frame")
	accentBar.Name = "Accent"
	accentBar.Size = UDim2.new(0, 3, 1, -4)
	accentBar.Position = UDim2.new(0, -6, 0, 2)
	accentBar.BackgroundColor3 = accentColor
	accentBar.BorderSizePixel = 0
	accentBar.Parent = button

	local accentCorner = Instance.new("UICorner")
	accentCorner.CornerRadius = UDim.new(0, 2)
	accentCorner.Parent = accentBar

	-- Name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(0.65, 0, 0, 18)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = def.Name
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextColor3 = COLOR_WHITE
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = button

	-- Level indicator
	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "Level"
	levelLabel.Size = UDim2.new(0.35, 0, 0, 18)
	levelLabel.Position = UDim2.new(0.65, 0, 0, 0)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text = "Lv " .. currentLevel .. "/" .. def.MaxLevel
	levelLabel.Font = Enum.Font.GothamBold
	levelLabel.TextSize = 13
	levelLabel.TextColor3 = if maxed then Color3.fromRGB(100, 255, 100) else accentColor
	levelLabel.TextXAlignment = Enum.TextXAlignment.Right
	levelLabel.Parent = button

	-- Description
	local descLabel = Instance.new("TextLabel")
	descLabel.Size = UDim2.new(1, 0, 0, 14)
	descLabel.Position = UDim2.new(0, 0, 0, 20)
	descLabel.BackgroundTransparency = 1
	descLabel.Text = def.Description
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextSize = 12
	descLabel.TextColor3 = Color3.fromRGB(170, 170, 170)
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.Parent = button

	-- Cost / MAX label
	local costLabel = Instance.new("TextLabel")
	costLabel.Name = "Cost"
	costLabel.Size = UDim2.new(1, 0, 0, 16)
	costLabel.Position = UDim2.new(0, 0, 0, 38)
	costLabel.BackgroundTransparency = 1
	costLabel.Font = Enum.Font.GothamBold
	costLabel.TextSize = 13
	costLabel.TextXAlignment = Enum.TextXAlignment.Left
	costLabel.Parent = button

	if maxed then
		costLabel.Text = "MAX LEVEL"
		costLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
	else
		costLabel.Text = "Next: " .. Util.formatGold(nextCost) .. "g"
		costLabel.TextColor3 = COLOR_GOLD_TEXT
	end

	-- Hover / click
	if not maxed then
		button.MouseEnter:Connect(function()
			button.BackgroundColor3 = COLOR_BUTTON_HOVER
		end)
		button.MouseLeave:Connect(function()
			button.BackgroundColor3 = COLOR_BUTTON_BG
		end)
		button.Activated:Connect(function()
			self:_onUpgradeClicked(upgradeId)
		end)
	else
		button.BackgroundColor3 = Color3.fromRGB(35, 45, 35)
	end

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

function ShopController:_onUpgradeClicked(upgradeId: string)
	local UpgradeService = Knit.GetService("UpgradeService")
	local success = UpgradeService:PurchaseUpgrade(upgradeId)

	local button = self._upgradeButtons[upgradeId]
	if not button then
		return
	end

	if success then
		self:_flashButton(button, COLOR_FLASH_GREEN, COLOR_BUTTON_BG)
		-- UI refresh happens via UpgradePurchased signal
	else
		self:_flashButton(button, COLOR_FLASH_RED, COLOR_BUTTON_BG)
	end
end

function ShopController:_onItemPurchased(itemId: string)
	if self._activeTab == "Items" then
		self:_refreshContent()
	end
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
		local displayName = self:_formatTierName(nextTierName)
		button.Text = "Upgrade to " .. displayName .. " - " .. Util.formatGold(cost) .. "g"
		button.BackgroundColor3 = COLOR_TOWNHALL
		button.AutoButtonColor = true
	end
end

function ShopController:_formatTierName(name: string): string
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
	else
		self:_flashButton(button, COLOR_FLASH_RED, COLOR_TOWNHALL)
	end
end

-- Keep old method name for compatibility
function ShopController:_refreshCreepList()
	self:_refreshContent()
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
