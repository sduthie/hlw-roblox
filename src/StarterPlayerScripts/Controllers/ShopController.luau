--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local CreepData = require(ReplicatedStorage.Shared.CreepData)
local CreepIcons = require(ReplicatedStorage.Shared.CreepIcons)
local ItemData = require(ReplicatedStorage.Shared.ItemData)
local MedicalData = require(ReplicatedStorage.Shared.MedicalData)
local FamiliarData = require(ReplicatedStorage.Shared.FamiliarData)
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
ShopController._currentGold = 0 :: number
ShopController._creepCosts = {} :: { [string]: number } -- creepId -> current escalated cost
ShopController._medicalButtons = {} :: { [string]: TextButton }
ShopController._familiarButtons = {} :: { [string]: TextButton }
ShopController._statusLabel = nil :: TextLabel?
ShopController._statusTween = nil :: Tween?

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
local COLOR_BUTTON_DISABLED = Color3.fromRGB(30, 30, 30)
local COLOR_TEXT_DISABLED = Color3.fromRGB(100, 100, 100)
local COLOR_COST_CANT_AFFORD = Color3.fromRGB(200, 60, 60)

local COLOR_ITEM = Color3.fromRGB(200, 180, 60)
local COLOR_MEDICAL = Color3.fromRGB(80, 200, 120) -- green for medical
local COLOR_FAMILIAR = Color3.fromRGB(180, 100, 220) -- purple for familiars
local COLOR_PREMIUM = Color3.fromRGB(255, 180, 50) -- gold for premium items
local TABS = { "Creeps", "Items", "Medical", "Familiar", "Upgrades" }

local CATEGORY_COLORS = {
	Economy = COLOR_ECON,
	Hero = COLOR_HERO,
	Minion = COLOR_MINION,
	Medical = COLOR_MEDICAL,
	Familiar = COLOR_FAMILIAR,
}

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function ShopController:KnitInit()
	self:_createShopUI()
end

function ShopController:KnitStart()
	-- Connect service signals with pcall protection so one failure doesn't break everything
	local ok, err = pcall(function()
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

		ShopService.MedicalPurchased:Connect(function(medicalId: string)
			if self._activeTab == "Medical" then
				self:_refreshContent()
			end
		end)

		ShopService.FamiliarPurchased:Connect(function(familiarId: string)
			if self._activeTab == "Familiar" then
				self:_refreshContent()
			end
		end)

		-- Fetch initial tier
		local tier = ShopService:GetTownHallTier()
		if tier then
			self._currentTier = tier
			self:_updateTownHallButton()
		end
	end)
	if not ok then
		warn("[ShopController] ShopService setup error:", err)
	end

	-- Upgrade service signals
	local ok2, err2 = pcall(function()
		local UpgradeService = Knit.GetService("UpgradeService")
		UpgradeService.UpgradePurchased:Connect(function(upgradeId: string, newLevel: number)
			self._upgradeLevels[upgradeId] = newLevel
			self:_refreshContent()
		end)

		local levels = UpgradeService:GetAllUpgrades()
		if levels then
			self._upgradeLevels = levels
		end
	end)
	if not ok2 then
		warn("[ShopController] UpgradeService setup error:", err2)
	end

	-- Track gold for affordability display
	local ok3, err3 = pcall(function()
		local IncomeService = Knit.GetService("IncomeService")
		IncomeService.GoldChanged:Connect(function(amount: number)
			self._currentGold = amount
			if self._shopOpen then
				self:_updateAffordability()
			end
		end)

		local initialGold = IncomeService:GetGold()
		if initialGold then
			self._currentGold = initialGold
		end
	end)
	if not ok3 then
		warn("[ShopController] IncomeService setup error:", err3)
	end

	-- Connect to shop building signs and ProximityPrompts
	self:_connectShopPrompts()
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function ShopController:ToggleShop()
	if not self._shopFrame then
		warn("[ShopController] ToggleShop: _shopFrame is nil")
		return
	end

	self._shopOpen = not self._shopOpen

	if self._shopOpen then
		-- Wrap content refresh in pcall so panel still opens even if content fails
		local ok, err = pcall(function()
			self:_refreshContent()
		end)
		if not ok then
			warn("[ShopController] _refreshContent error:", err)
		end

		local ok2, err2 = pcall(function()
			self:_updateTownHallButton()
		end)
		if not ok2 then
			warn("[ShopController] _updateTownHallButton error:", err2)
		end

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
	local tabMap = {
		Gear = "Items",
		Medical = "Medical",
		Familiar = "Familiar",
		Upgrades = "Upgrades",
		Creeps = "Creeps",
	}

	local function openShopTab(shopPart: BasePart)
		-- Team check
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

		-- Route to correct tab based on ShopType
		local shopType = shopPart:GetAttribute("ShopType")
		if shopType then
			local targetTab = tabMap[shopType] or "Creeps"
			if not self._shopOpen then
				self:ToggleShop()
			end
			self:_switchTab(targetTab)
		else
			self:ToggleShop()
		end
	end

	local function connectShop(shopPart: BasePart)
		-- ProximityPrompt (close range interaction)
		task.spawn(function()
			local prompt = shopPart:FindFirstChildOfClass("ProximityPrompt")
			if not prompt then
				prompt = shopPart:WaitForChild("ProximityPrompt", 5) :: ProximityPrompt?
			end
			if prompt then
				prompt.Triggered:Connect(function()
					openShopTab(shopPart)
				end)
			end
		end)

		-- Make BillboardGui sign clickable from anywhere on the map
		task.spawn(function()
			local signGui = shopPart:FindFirstChild("ShopSign") :: BillboardGui?
			if not signGui then
				signGui = shopPart:WaitForChild("ShopSign", 5) :: BillboardGui?
			end
			if not signGui then
				return
			end

			-- Ensure the BillboardGui is interactive
			signGui.Active = true

			-- Find the existing sign label and add a clickable button over it
			local signLabel = signGui:FindFirstChildOfClass("TextLabel")
			if signLabel then
				local clickBtn = Instance.new("TextButton")
				clickBtn.Name = "ShopClickBtn"
				clickBtn.Size = UDim2.fromScale(1, 1)
				clickBtn.BackgroundTransparency = 1
				clickBtn.Text = ""
				clickBtn.Parent = signGui

				clickBtn.Activated:Connect(function()
					openShopTab(shopPart)
				end)

				-- Hover highlight
				clickBtn.MouseEnter:Connect(function()
					if signLabel then
						signLabel.BackgroundTransparency = 0
					end
				end)
				clickBtn.MouseLeave:Connect(function()
					if signLabel then
						signLabel.BackgroundTransparency = 0.3
					end
				end)
			end
		end)
	end

	-- Connect existing shop parts
	for _, shopPart in CollectionService:GetTagged("Shop") do
		connectShop(shopPart)
	end

	-- Connect any shop parts added later
	CollectionService:GetInstanceAddedSignal("Shop"):Connect(function(shopPart)
		connectShop(shopPart)
	end)
end

--------------------------------------------------------------------------------
-- Persistent HUD shop button (always visible, always works)
--------------------------------------------------------------------------------

function ShopController:_createShopButton()
	local screenGui = self._screenGui
	if not screenGui then
		return
	end

	local btn = Instance.new("TextButton")
	btn.Name = "ShopToggleBtn"
	btn.Size = UDim2.new(0, 70, 0, 28)
	btn.Position = UDim2.new(1, -80, 0, 44)
	btn.BackgroundColor3 = Color3.fromRGB(50, 40, 70)
	btn.BackgroundTransparency = 0.2
	btn.BorderSizePixel = 0
	btn.Text = "SHOP [B]"
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 12
	btn.TextColor3 = Color3.fromRGB(255, 215, 80)
	btn.AutoButtonColor = true
	btn.ZIndex = 10
	btn.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = btn

	btn.Activated:Connect(function()
		self:ToggleShop()
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
		tabBtn.Size = UDim2.new(0, 38, 1, 0)
		tabBtn.BackgroundColor3 = if tabName == self._activeTab then COLOR_TAB_ACTIVE else COLOR_TAB_INACTIVE
		tabBtn.BorderSizePixel = 0
		tabBtn.Text = tabName
		tabBtn.Font = Enum.Font.GothamBold
		tabBtn.TextSize = 9
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

	-- Status label (shows purchase feedback)
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.new(1, -16, 0, 18)
	statusLabel.Position = UDim2.new(0, 8, 1, -22)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = ""
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.TextSize = 12
	statusLabel.TextColor3 = COLOR_FLASH_GREEN
	statusLabel.TextTransparency = 1
	statusLabel.TextXAlignment = Enum.TextXAlignment.Center
	statusLabel.ZIndex = 10
	statusLabel.Parent = shopFrame
	self._statusLabel = statusLabel

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
	table.clear(self._medicalButtons)
	table.clear(self._familiarButtons)

	if self._activeTab == "Creeps" then
		self:_populateCreeps(scrollFrame)
	elseif self._activeTab == "Items" then
		self:_populateItems(scrollFrame)
	elseif self._activeTab == "Medical" then
		self:_populateMedical(scrollFrame)
	elseif self._activeTab == "Familiar" then
		self:_populateFamiliar(scrollFrame)
	else
		self:_populateUpgrades(scrollFrame, self._activeTab)
	end

	-- Grey out buttons the player can't afford
	self:_updateAffordability()
end

--------------------------------------------------------------------------------
-- Creep Tab
--------------------------------------------------------------------------------

function ShopController:_populateCreeps(parent: ScrollingFrame)
	local ShopService = Knit.GetService("ShopService")
	local availableIds = ShopService:GetAvailableCreeps()

	-- Fetch escalated costs
	self._creepCosts = ShopService:GetAllCreepCosts()

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

	-- Creep icon (left side)
	local ICON_SIZE = 36
	local ICON_OFFSET = ICON_SIZE + 6 -- space for icon + gap
	local icon = CreepIcons.build(creepId, ICON_SIZE)
	icon.Position = UDim2.fromOffset(0, math.round((44 - ICON_SIZE) / 2))
	icon.Parent = button

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "CreepName"
	nameLabel.Size = UDim2.new(0.6, -ICON_OFFSET, 0, 18)
	nameLabel.Position = UDim2.fromOffset(ICON_OFFSET, 0)
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

	-- Show escalated cost if available, otherwise base cost
	local displayCost = self._creepCosts[creepId] or def.Cost

	local costLabel = Instance.new("TextLabel")
	costLabel.Name = "CostLabel"
	costLabel.Size = UDim2.new(0.5, -ICON_OFFSET, 0, 16)
	costLabel.Position = UDim2.fromOffset(ICON_OFFSET, 22)
	costLabel.BackgroundTransparency = 1
	costLabel.Text = Util.formatGold(displayCost) .. "g"
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
	local def = ItemData[itemId]
	local ShopService = Knit.GetService("ShopService")
	local success = ShopService:BuyItem(itemId)

	local button = self._itemButtons[itemId]
	if not button then
		return
	end

	if success then
		self:_flashButton(button, COLOR_FLASH_GREEN, COLOR_BUTTON_BG)
		local name = if def then def.Name else itemId
		self:_showStatus("Bought " .. name .. "!", COLOR_FLASH_GREEN)
	else
		self:_flashButton(button, COLOR_FLASH_RED, COLOR_BUTTON_BG)
		local gold = self._currentGold
		local cost = if def then def.Cost else 0
		if gold < cost then
			self:_showStatus("Not enough gold! (" .. tostring(math.floor(gold)) .. "/" .. tostring(cost) .. "g)", COLOR_FLASH_RED)
		else
			self:_showStatus("Cannot buy right now", COLOR_FLASH_RED)
		end
	end
end

--------------------------------------------------------------------------------
-- Medical Tab
--------------------------------------------------------------------------------

function ShopController:_populateMedical(parent: ScrollingFrame)
	local medList: { { id: string, def: any } } = {}
	for id, def in MedicalData do
		table.insert(medList, { id = id, def = def })
	end
	table.sort(medList, function(a, b)
		return a.def.Cost < b.def.Cost
	end)

	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 24)
	header.BackgroundTransparency = 1
	header.Text = "MEDICAL SUPPLIES"
	header.Font = Enum.Font.GothamBold
	header.TextSize = 14
	header.TextColor3 = COLOR_MEDICAL
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.LayoutOrder = 0
	header.Parent = parent

	for i, entry in medList do
		local btn = self:_createMedicalButton(entry.id, entry.def, i)
		btn.Parent = parent
		self._medicalButtons[entry.id] = btn
	end
end

function ShopController:_createMedicalButton(medicalId: string, def: any, layoutOrder: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = "Med_" .. medicalId
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

	-- Accent bar
	local accentBar = Instance.new("Frame")
	accentBar.Name = "Accent"
	accentBar.Size = UDim2.new(0, 3, 1, -4)
	accentBar.Position = UDim2.new(0, -6, 0, 2)
	accentBar.BackgroundColor3 = COLOR_MEDICAL
	accentBar.BorderSizePixel = 0
	accentBar.Parent = button
	local ac = Instance.new("UICorner")
	ac.CornerRadius = UDim.new(0, 2)
	ac.Parent = accentBar

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
	costLabel.Name = "CostLabel"
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
	descLabel.Position = UDim2.new(0, 0, 0, 22)
	descLabel.BackgroundTransparency = 1
	descLabel.Text = def.Description
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextSize = 11
	descLabel.TextColor3 = Color3.fromRGB(170, 170, 170)
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.Parent = button

	button.MouseEnter:Connect(function() button.BackgroundColor3 = COLOR_BUTTON_HOVER end)
	button.MouseLeave:Connect(function() button.BackgroundColor3 = COLOR_BUTTON_BG end)
	button.Activated:Connect(function()
		self:_onMedicalClicked(medicalId)
	end)

	return button
end

function ShopController:_onMedicalClicked(medicalId: string)
	local def = MedicalData[medicalId]
	local ShopService = Knit.GetService("ShopService")
	local success = ShopService:BuyMedical(medicalId)
	local button = self._medicalButtons[medicalId]
	if not button then return end
	if success then
		self:_flashButton(button, COLOR_FLASH_GREEN, COLOR_BUTTON_BG)
		local name = if def then def.Name else medicalId
		self:_showStatus("Used " .. name .. "!", COLOR_MEDICAL)
	else
		self:_flashButton(button, COLOR_FLASH_RED, COLOR_BUTTON_BG)
		local gold = self._currentGold
		local cost = if def then def.Cost else 0
		if gold < cost then
			self:_showStatus("Not enough gold! (" .. tostring(math.floor(gold)) .. "/" .. tostring(cost) .. "g)", COLOR_FLASH_RED)
		else
			self:_showStatus("Cannot buy right now", COLOR_FLASH_RED)
		end
	end
end

--------------------------------------------------------------------------------
-- Familiar Tab
--------------------------------------------------------------------------------

function ShopController:_populateFamiliar(parent: ScrollingFrame)
	local famList: { { id: string, def: any } } = {}
	for id, def in FamiliarData do
		table.insert(famList, { id = id, def = def })
	end
	-- Sort: gold items first, then premium
	table.sort(famList, function(a, b)
		if a.def.IsPremium ~= b.def.IsPremium then
			return not a.def.IsPremium
		end
		return (a.def.Cost or a.def.RobuxCost or 0) < (b.def.Cost or b.def.RobuxCost or 0)
	end)

	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 24)
	header.BackgroundTransparency = 1
	header.Text = "FAMILIARS"
	header.Font = Enum.Font.GothamBold
	header.TextSize = 14
	header.TextColor3 = COLOR_FAMILIAR
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.LayoutOrder = 0
	header.Parent = parent

	for i, entry in famList do
		local btn = self:_createFamiliarButton(entry.id, entry.def, i)
		btn.Parent = parent
		self._familiarButtons[entry.id] = btn
	end
end

function ShopController:_createFamiliarButton(familiarId: string, def: any, layoutOrder: number): TextButton
	local isPremium = def.IsPremium == true
	local button = Instance.new("TextButton")
	button.Name = "Fam_" .. familiarId
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

	local accentColor = if isPremium then COLOR_PREMIUM else COLOR_FAMILIAR
	local accentBar = Instance.new("Frame")
	accentBar.Name = "Accent"
	accentBar.Size = UDim2.new(0, 3, 1, -4)
	accentBar.Position = UDim2.new(0, -6, 0, 2)
	accentBar.BackgroundColor3 = accentColor
	accentBar.BorderSizePixel = 0
	accentBar.Parent = button
	local ac = Instance.new("UICorner")
	ac.CornerRadius = UDim.new(0, 2)
	ac.Parent = accentBar

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(0.6, 0, 0, 18)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = def.Name
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextColor3 = if isPremium then COLOR_PREMIUM else COLOR_WHITE
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = button

	local costLabel = Instance.new("TextLabel")
	costLabel.Name = "CostLabel"
	costLabel.Size = UDim2.new(0.4, 0, 0, 18)
	costLabel.Position = UDim2.new(0.6, 0, 0, 0)
	costLabel.BackgroundTransparency = 1
	costLabel.Font = Enum.Font.GothamBold
	costLabel.TextSize = 13
	costLabel.TextXAlignment = Enum.TextXAlignment.Right
	costLabel.Parent = button

	if isPremium then
		costLabel.Text = "R$ " .. tostring(def.RobuxCost or 0)
		costLabel.TextColor3 = COLOR_PREMIUM
	else
		costLabel.Text = Util.formatGold(def.Cost) .. "g"
		costLabel.TextColor3 = COLOR_GOLD_TEXT
	end

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
	if def.Stats then
		for statName, statValue in def.Stats do
			table.insert(statParts, "+" .. tostring(statValue) .. " " .. statName)
		end
	end
	if def.IsConsumable then
		table.insert(statParts, "Consumable")
	end

	local statsLabel = Instance.new("TextLabel")
	statsLabel.Size = UDim2.new(1, 0, 0, 14)
	statsLabel.Position = UDim2.new(0, 0, 0, 38)
	statsLabel.BackgroundTransparency = 1
	statsLabel.Text = table.concat(statParts, "  ")
	statsLabel.Font = Enum.Font.GothamMedium
	statsLabel.TextSize = 11
	statsLabel.TextColor3 = if isPremium then Color3.fromRGB(255, 200, 120) else Color3.fromRGB(180, 140, 255)
	statsLabel.TextXAlignment = Enum.TextXAlignment.Left
	statsLabel.Parent = button

	button.MouseEnter:Connect(function() button.BackgroundColor3 = COLOR_BUTTON_HOVER end)
	button.MouseLeave:Connect(function() button.BackgroundColor3 = COLOR_BUTTON_BG end)
	button.Activated:Connect(function()
		self:_onFamiliarClicked(familiarId)
	end)

	return button
end

function ShopController:_onFamiliarClicked(familiarId: string)
	local def = FamiliarData[familiarId]
	local ShopService = Knit.GetService("ShopService")
	local success = ShopService:BuyFamiliar(familiarId)
	local button = self._familiarButtons[familiarId]
	if not button then return end
	if success then
		self:_flashButton(button, COLOR_FLASH_GREEN, COLOR_BUTTON_BG)
		local name = if def then def.Name else familiarId
		self:_showStatus("Summoned " .. name .. "!", COLOR_FAMILIAR)
	else
		self:_flashButton(button, COLOR_FLASH_RED, COLOR_BUTTON_BG)
		if def and def.IsPremium then
			self:_showStatus("Premium not yet available", COLOR_FLASH_RED)
		else
			local gold = self._currentGold
			local cost = if def then def.Cost else 0
			if gold < cost then
				self:_showStatus("Not enough gold! (" .. tostring(math.floor(gold)) .. "/" .. tostring(cost) .. "g)", COLOR_FLASH_RED)
			else
				self:_showStatus("Cannot buy right now", COLOR_FLASH_RED)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Upgrade Tabs (Economy / Hero / Minion)
--------------------------------------------------------------------------------

function ShopController:_populateUpgrades(parent: ScrollingFrame, category: string)
	-- "Upgrades" tab shows all three categories together
	local categories: { string }
	if category == "Upgrades" then
		categories = { "Economy", "Hero", "Minion" }
	else
		categories = { category }
	end

	local layoutOrder = 0
	for _, cat in categories do
		-- Collect upgrades for this category
		local upgrades: { { id: string, def: any } } = {}
		for id, def in UpgradeData do
			if def.Category == cat then
				table.insert(upgrades, { id = id, def = def })
			end
		end

		-- Sort by first cost (cheapest first)
		table.sort(upgrades, function(a, b)
			return (a.def.Costs[1] or 0) < (b.def.Costs[1] or 0)
		end)

		-- Section header
		local catColor = CATEGORY_COLORS[cat] or COLOR_WHITE
		local header = Instance.new("TextLabel")
		header.Name = "Header_" .. cat
		header.Size = UDim2.new(1, 0, 0, 24)
		header.BackgroundTransparency = 1
		header.Text = string.upper(cat) .. " UPGRADES"
		header.Font = Enum.Font.GothamBold
		header.TextSize = 14
		header.TextColor3 = catColor
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.LayoutOrder = layoutOrder
		header.Parent = parent
		layoutOrder += 1

		for _, entry in upgrades do
			local btn = self:_createUpgradeButton(entry.id, entry.def, layoutOrder, catColor)
			btn.Parent = parent
			self._upgradeButtons[entry.id] = btn
			layoutOrder += 1
		end
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
-- Affordability: grey out buttons the player can't afford
--------------------------------------------------------------------------------

function ShopController:_updateAffordability()
	local gold = self._currentGold

	-- Creep buttons
	for creepId, button in self._creepButtons do
		local cost = self._creepCosts[creepId]
		if not cost then
			local def = CreepData[creepId]
			cost = if def then def.Cost else 0
		end
		local canAfford = gold >= cost
		self:_setButtonAffordable(button, canAfford)
		-- Update cost label color
		local costLabel = button:FindFirstChild("CostLabel") :: TextLabel?
		if costLabel then
			costLabel.TextColor3 = if canAfford then COLOR_GOLD_TEXT else COLOR_COST_CANT_AFFORD
		end
	end

	-- Item buttons
	for itemId, button in self._itemButtons do
		local def = ItemData[itemId]
		if def then
			local canAfford = gold >= def.Cost
			self:_setButtonAffordable(button, canAfford)
		end
	end

	-- Upgrade buttons
	for upgradeId, button in self._upgradeButtons do
		local def = UpgradeData[upgradeId]
		if def then
			local currentLevel = self._upgradeLevels[upgradeId] or 0
			local maxed = currentLevel >= def.MaxLevel
			if not maxed then
				local nextCost = def.Costs[currentLevel + 1] or 0
				local canAfford = gold >= nextCost
				self:_setButtonAffordable(button, canAfford)
			end
		end
	end

	-- Medical buttons
	for medicalId, button in self._medicalButtons do
		local def = MedicalData[medicalId]
		if def then
			local canAfford = gold >= def.Cost
			self:_setButtonAffordable(button, canAfford)
		end
	end

	-- Familiar buttons (gold ones only)
	for familiarId, button in self._familiarButtons do
		local def = FamiliarData[familiarId]
		if def and not def.IsPremium then
			local canAfford = gold >= def.Cost
			self:_setButtonAffordable(button, canAfford)
		end
	end
end

function ShopController:_setButtonAffordable(button: TextButton, canAfford: boolean)
	if canAfford then
		button.BackgroundColor3 = COLOR_BUTTON_BG
		button.BackgroundTransparency = 0
	else
		button.BackgroundColor3 = COLOR_BUTTON_DISABLED
		button.BackgroundTransparency = 0.3
	end
end

--------------------------------------------------------------------------------
-- Purchase Actions
--------------------------------------------------------------------------------

function ShopController:_onCreepClicked(creepId: string)
	local def = CreepData[creepId]
	local ShopService = Knit.GetService("ShopService")
	local success = ShopService:BuyCreep(creepId)

	local button = self._creepButtons[creepId]
	if not button then
		return
	end

	if success then
		self:_flashButton(button, COLOR_FLASH_GREEN, COLOR_BUTTON_BG)
		local name = if def then def.Name else creepId
		self:_showStatus("Sent " .. name .. "!", COLOR_FLASH_GREEN)

		-- Refresh escalated costs after purchase and update the button label
		self._creepCosts = ShopService:GetAllCreepCosts()
		local newCost = self._creepCosts[creepId]
		if newCost then
			local costLabel = button:FindFirstChild("CostLabel") :: TextLabel?
			if costLabel then
				costLabel.Text = Util.formatGold(newCost) .. "g"
			end
		end
		self:_updateAffordability()
	else
		self:_flashButton(button, COLOR_FLASH_RED, COLOR_BUTTON_BG)
		-- Show reason for failure
		local gold = self._currentGold
		local cost = self._creepCosts[creepId] or (if def then def.Cost else 0)
		if gold < cost then
			self:_showStatus("Not enough gold! (" .. tostring(math.floor(gold)) .. "/" .. tostring(cost) .. "g)", COLOR_FLASH_RED)
		else
			self:_showStatus("Cannot buy right now", COLOR_FLASH_RED)
		end
	end
end

function ShopController:_onUpgradeClicked(upgradeId: string)
	local def = UpgradeData[upgradeId]
	local UpgradeService = Knit.GetService("UpgradeService")
	local success = UpgradeService:PurchaseUpgrade(upgradeId)

	local button = self._upgradeButtons[upgradeId]
	if not button then
		return
	end

	if success then
		self:_flashButton(button, COLOR_FLASH_GREEN, COLOR_BUTTON_BG)
		local name = if def then def.Name else upgradeId
		self:_showStatus("Upgraded " .. name .. "!", COLOR_FLASH_GREEN)
	else
		self:_flashButton(button, COLOR_FLASH_RED, COLOR_BUTTON_BG)
		if def then
			local currentLevel = self._upgradeLevels[upgradeId] or 0
			local nextCost = def.Costs[currentLevel + 1] or 0
			if self._currentGold < nextCost then
				self:_showStatus("Not enough gold! (" .. tostring(math.floor(self._currentGold)) .. "/" .. tostring(nextCost) .. "g)", COLOR_FLASH_RED)
			else
				self:_showStatus("Cannot upgrade right now", COLOR_FLASH_RED)
			end
		else
			self:_showStatus("Cannot upgrade right now", COLOR_FLASH_RED)
		end
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
		self:_showStatus("Town Hall upgraded!", COLOR_FLASH_GREEN)
	else
		self:_flashButton(button, COLOR_FLASH_RED, COLOR_TOWNHALL)
		self:_showStatus("Cannot upgrade right now", COLOR_FLASH_RED)
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

function ShopController:_showStatus(message: string, color: Color3)
	local label = self._statusLabel
	if not label then
		return
	end

	-- Cancel previous fade
	if self._statusTween then
		self._statusTween:Cancel()
		self._statusTween = nil
	end

	label.Text = message
	label.TextColor3 = color
	label.TextTransparency = 0

	-- Fade out after 1.5 seconds
	local tween = TweenService:Create(
		label,
		TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ TextTransparency = 1 }
	)
	self._statusTween = tween
	task.delay(1.0, function()
		tween:Play()
	end)
end

return ShopController
