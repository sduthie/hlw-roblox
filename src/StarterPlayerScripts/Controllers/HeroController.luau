--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local HeroData = require(ReplicatedStorage.Shared.HeroData)

local GOLD_HIGHLIGHT = Color3.fromHex("#FFD700")
local TRANSPARENT_STROKE = Color3.fromRGB(0, 0, 0)
local CARD_BG = Color3.fromRGB(40, 40, 40)
local CARD_WIDTH = 160
local CARD_HEIGHT = 220
local CARD_GAP = 12

local HeroController = Knit.CreateController({
	Name = "HeroController",
})

HeroController._selectedHeroId = nil :: string?
HeroController._screenGui = nil :: ScreenGui?
HeroController._heroSelectFrame = nil :: Frame?
HeroController._heroCards = {} :: { [string]: Frame }

function HeroController:KnitInit()
	self:_createHeroSelectUI()
end

function HeroController:KnitStart()
	local heroService = Knit.GetService("HeroService")
	local gameService = Knit.GetService("GameService")

	heroService.HeroSelected:Connect(function(userId: number, heroId: string)
		self:_onHeroSelected(userId, heroId)
	end)

	heroService.HeroLevelUp:Connect(function(level: number)
		self:_onHeroLevelUp(level)
	end)

	gameService.PhaseChanged:Connect(function(phase: string)
		self:_onPhaseChanged(phase)
	end)
end

function HeroController:SelectHero(heroId: string)
	if not HeroData[heroId] then
		warn("[HLW] Invalid hero:", heroId)
		return
	end

	local heroService = Knit.GetService("HeroService")
	heroService:SelectHero(heroId)
end

function HeroController:GetSelectedHeroId(): string?
	return self._selectedHeroId
end

function HeroController:GetHeroRoster(): { [string]: any }
	return HeroData
end

function HeroController:_onPhaseChanged(phase: string)
	local frame = self._heroSelectFrame
	if not frame then
		return
	end

	if phase == "HERO_SELECT" then
		self:_resetHighlights()
		frame.Visible = true
	else
		frame.Visible = false
	end
end

function HeroController:_onHeroSelected(userId: number, heroId: string)
	local localPlayer = Players.LocalPlayer
	if localPlayer and localPlayer.UserId == userId then
		self._selectedHeroId = heroId
		self:_highlightCard(heroId)
	end
end

function HeroController:_onHeroLevelUp(level: number)
	print("[HLW] Hero leveled up to", level)
end

function HeroController:_highlightCard(heroId: string)
	for id, card in self._heroCards do
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if not stroke then
			continue
		end
		if id == heroId then
			stroke.Color = GOLD_HIGHLIGHT
		else
			stroke.Color = TRANSPARENT_STROKE
			stroke.Transparency = 1
		end
	end

	-- Make the selected card's stroke fully visible
	local selectedCard = self._heroCards[heroId]
	if selectedCard then
		local stroke = selectedCard:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 0
		end
	end
end

function HeroController:_resetHighlights()
	for _, card in self._heroCards do
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = TRANSPARENT_STROKE
			stroke.Transparency = 1
		end
	end
end

function HeroController:_createHeroSelectUI()
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "HLW_HeroSelect"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = localPlayer.PlayerGui
	self._screenGui = screenGui

	-- Overlay frame (full screen, semi-transparent black)
	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.Position = UDim2.fromScale(0, 0)
	overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 0.5
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.Parent = screenGui
	self._heroSelectFrame = overlay

	-- Title label
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 50)
	title.Position = UDim2.new(0, 0, 0, 40)
	title.BackgroundTransparency = 1
	title.Text = "CHOOSE YOUR HERO"
	title.Font = Enum.Font.GothamBold
	title.TextSize = 32
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.Parent = overlay

	-- Card container (centered horizontally)
	local cardContainer = Instance.new("Frame")
	cardContainer.Name = "CardContainer"
	cardContainer.BackgroundTransparency = 1
	cardContainer.BorderSizePixel = 0
	cardContainer.AnchorPoint = Vector2.new(0.5, 0.5)
	cardContainer.Position = UDim2.fromScale(0.5, 0.5)
	cardContainer.AutomaticSize = Enum.AutomaticSize.XY
	cardContainer.Parent = overlay

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Horizontal
	listLayout.Padding = UDim.new(0, CARD_GAP)
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	listLayout.SortOrder = Enum.SortOrder.Name
	listLayout.Parent = cardContainer

	-- Create one card per hero
	for heroId, heroDef in HeroData do
		local card = self:_createHeroCard(heroId, heroDef)
		card.Parent = cardContainer
		self._heroCards[heroId] = card
	end
end

function HeroController:_createHeroCard(heroId: string, heroDef: any): Frame
	local card = Instance.new("Frame")
	card.Name = heroId
	card.Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT)
	card.BackgroundColor3 = CARD_BG
	card.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = TRANSPARENT_STROKE
	stroke.Transparency = 1
	stroke.Parent = card

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = card

	-- Hero name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "HeroName"
	nameLabel.Size = UDim2.new(1, 0, 0, 22)
	nameLabel.Position = UDim2.fromOffset(0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = heroDef.Name
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 18
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = card

	-- Description
	local descLabel = Instance.new("TextLabel")
	descLabel.Name = "Description"
	descLabel.Size = UDim2.new(1, 0, 0, 44)
	descLabel.Position = UDim2.fromOffset(0, 26)
	descLabel.BackgroundTransparency = 1
	descLabel.Text = heroDef.Description
	descLabel.Font = Enum.Font.GothamMedium
	descLabel.TextSize = 12
	descLabel.TextColor3 = Color3.fromRGB(170, 170, 170)
	descLabel.TextWrapped = true
	descLabel.TextXAlignment = Enum.TextXAlignment.Center
	descLabel.TextYAlignment = Enum.TextYAlignment.Top
	descLabel.Parent = card

	-- Stats section
	local statsFrame = Instance.new("Frame")
	statsFrame.Name = "Stats"
	statsFrame.Size = UDim2.new(1, 0, 0, 80)
	statsFrame.Position = UDim2.fromOffset(0, 76)
	statsFrame.BackgroundTransparency = 1
	statsFrame.BorderSizePixel = 0
	statsFrame.Parent = card

	local statsLayout = Instance.new("UIListLayout")
	statsLayout.FillDirection = Enum.FillDirection.Vertical
	statsLayout.Padding = UDim.new(0, 2)
	statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statsLayout.Parent = statsFrame

	local stats = {
		{ label = "HP", value = heroDef.BaseHealth, order = 1 },
		{ label = "DMG", value = heroDef.BaseDamage, order = 2 },
		{ label = "Armor", value = heroDef.BaseArmor, order = 3 },
		{ label = "Speed", value = heroDef.MoveSpeed, order = 4 },
	}

	for _, stat in stats do
		local statLabel = Instance.new("TextLabel")
		statLabel.Name = stat.label
		statLabel.Size = UDim2.new(1, 0, 0, 18)
		statLabel.BackgroundTransparency = 1
		statLabel.Text = stat.label .. ": " .. tostring(stat.value)
		statLabel.Font = Enum.Font.Gotham
		statLabel.TextSize = 14
		statLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
		statLabel.TextXAlignment = Enum.TextXAlignment.Left
		statLabel.LayoutOrder = stat.order
		statLabel.Parent = statsFrame
	end

	-- Click button (invisible overlay to capture clicks)
	local clickButton = Instance.new("TextButton")
	clickButton.Name = "ClickArea"
	clickButton.Size = UDim2.fromScale(1, 1)
	clickButton.Position = UDim2.fromScale(0, 0)
	clickButton.BackgroundTransparency = 1
	clickButton.Text = ""
	clickButton.ZIndex = 10
	clickButton.Parent = card

	clickButton.MouseButton1Click:Connect(function()
		self:SelectHero(heroId)
	end)

	return card
end

return HeroController
