--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local CreepData = require(ReplicatedStorage.Shared.CreepData)
local CreepIcons = require(ReplicatedStorage.Shared.CreepIcons)
local Util = require(ReplicatedStorage.Shared.Util)

local CreepBarController = Knit.CreateController({
	Name = "CreepBarController",
})

CreepBarController._screenGui = nil :: ScreenGui?
CreepBarController._barFrame = nil :: Frame?
CreepBarController._buttons = {} :: { [number]: { Button: TextButton, CreepId: string } }
CreepBarController._sortedCreeps = {} :: { { id: string, def: any } }

local BTN_SIZE = 64
local BTN_GAP = 5
local BAR_WIDTH = 78
local COLOR_BG = Color3.fromRGB(25, 25, 30)
local COLOR_BTN = Color3.fromRGB(50, 50, 55)
local COLOR_BTN_HOVER = Color3.fromRGB(70, 70, 75)
local COLOR_LOCKED = Color3.fromRGB(35, 35, 40)
local COLOR_GOLD = Color3.fromRGB(255, 215, 80)
local COLOR_WHITE = Color3.fromRGB(255, 255, 255)
local COLOR_GRAY = Color3.fromRGB(130, 130, 130)
local COLOR_FLASH_GREEN = Color3.fromRGB(0, 200, 0)
local COLOR_FLASH_RED = Color3.fromRGB(200, 0, 0)

local HOTKEYS = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
	Enum.KeyCode.Six,
	Enum.KeyCode.Seven,
	Enum.KeyCode.Eight,
	Enum.KeyCode.Nine,
}

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function CreepBarController:KnitInit()
	-- CreepBar disabled — use shop building clicks instead
end

function CreepBarController:KnitStart()
	-- CreepBar disabled — use shop building clicks instead
end

--------------------------------------------------------------------------------
-- Phase visibility
--------------------------------------------------------------------------------

function CreepBarController:_onPhaseChanged(phase: string)
	local bar = self._barFrame
	if not bar then
		return
	end
	bar.Visible = (phase == Constants.PHASE_PLAYING)

	if phase == Constants.PHASE_PLAYING then
		-- Refresh lock states
		local ShopService = Knit.GetService("ShopService")
		local tier = ShopService:GetTownHallTier()
		self:_refreshLocks(tier)
	end
end

--------------------------------------------------------------------------------
-- UI Creation
--------------------------------------------------------------------------------

function CreepBarController:_createUI()
	local player = Players.LocalPlayer
	if not player then
		return
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "HLW_CreepBar"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = player.PlayerGui
	self._screenGui = screenGui

	local barHeight = #self._sortedCreeps * (BTN_SIZE + BTN_GAP) - BTN_GAP + 16

	local barFrame = Instance.new("Frame")
	barFrame.Name = "CreepBar"
	barFrame.Size = UDim2.new(0, BAR_WIDTH, 0, barHeight)
	barFrame.Position = UDim2.new(1, -10, 0.5, 0)
	barFrame.AnchorPoint = Vector2.new(1, 0.5)
	barFrame.BackgroundColor3 = COLOR_BG
	barFrame.BackgroundTransparency = 0.15
	barFrame.BorderSizePixel = 0
	barFrame.Visible = false
	barFrame.Parent = screenGui
	self._barFrame = barFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = barFrame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, BTN_GAP)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = barFrame

	for i, entry in self._sortedCreeps do
		local btn = self:_createCreepButton(i, entry.id, entry.def)
		btn.LayoutOrder = i
		btn.Parent = barFrame
		self._buttons[i] = { Button = btn, CreepId = entry.id }
	end
end

function CreepBarController:_createCreepButton(index: number, creepId: string, def: any): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = "Creep_" .. creepId
	btn.Size = UDim2.fromOffset(BTN_SIZE, BTN_SIZE)
	btn.BackgroundColor3 = COLOR_BTN
	btn.BorderSizePixel = 0
	btn.Text = ""
	btn.AutoButtonColor = false

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 6)
	btnCorner.Parent = btn

	-- Hotkey label (top-left)
	local hotkeyLabel = Instance.new("TextLabel")
	hotkeyLabel.Name = "Hotkey"
	hotkeyLabel.Size = UDim2.fromOffset(16, 16)
	hotkeyLabel.Position = UDim2.fromOffset(3, 2)
	hotkeyLabel.BackgroundColor3 = Color3.fromRGB(80, 80, 90)
	hotkeyLabel.BackgroundTransparency = 0.3
	hotkeyLabel.Text = tostring(index)
	hotkeyLabel.Font = Enum.Font.GothamBold
	hotkeyLabel.TextSize = 11
	hotkeyLabel.TextColor3 = COLOR_WHITE
	hotkeyLabel.TextXAlignment = Enum.TextXAlignment.Center
	hotkeyLabel.Parent = btn

	local hkCorner = Instance.new("UICorner")
	hkCorner.CornerRadius = UDim.new(0, 3)
	hkCorner.Parent = hotkeyLabel

	-- Creep icon (centered)
	local icon = CreepIcons.build(creepId, 28)
	icon.Position = UDim2.new(0.5, -14, 0, 17)
	icon.Parent = btn

	-- Creep name (below icon)
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "CreepName"
	nameLabel.Size = UDim2.new(1, -4, 0, 12)
	nameLabel.Position = UDim2.new(0, 2, 0, 46)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = def.Name
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 10
	nameLabel.TextColor3 = COLOR_WHITE
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = btn

	-- Cost (bottom)
	local costLabel = Instance.new("TextLabel")
	costLabel.Name = "Cost"
	costLabel.Size = UDim2.new(1, -4, 0, 14)
	costLabel.Position = UDim2.new(0, 2, 1, -16)
	costLabel.BackgroundTransparency = 1
	costLabel.Text = Util.formatGold(def.Cost) .. "g"
	costLabel.Font = Enum.Font.GothamMedium
	costLabel.TextSize = 12
	costLabel.TextColor3 = COLOR_GOLD
	costLabel.TextXAlignment = Enum.TextXAlignment.Center
	costLabel.Parent = btn

	-- Tier dot (top-right)
	local tierLabel = Instance.new("TextLabel")
	tierLabel.Name = "Tier"
	tierLabel.Size = UDim2.fromOffset(16, 12)
	tierLabel.Position = UDim2.new(1, -19, 0, 3)
	tierLabel.BackgroundTransparency = 1
	tierLabel.Text = "T" .. def.Tier
	tierLabel.Font = Enum.Font.Gotham
	tierLabel.TextSize = 10
	tierLabel.TextColor3 = COLOR_GRAY
	tierLabel.TextXAlignment = Enum.TextXAlignment.Right
	tierLabel.Parent = btn

	-- Lock overlay
	local lockOverlay = Instance.new("Frame")
	lockOverlay.Name = "LockOverlay"
	lockOverlay.Size = UDim2.fromScale(1, 1)
	lockOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
	lockOverlay.BackgroundTransparency = 0.5
	lockOverlay.BorderSizePixel = 0
	lockOverlay.Visible = false
	lockOverlay.ZIndex = 5
	lockOverlay.Parent = btn

	local lockCorner = Instance.new("UICorner")
	lockCorner.CornerRadius = UDim.new(0, 6)
	lockCorner.Parent = lockOverlay

	local lockText = Instance.new("TextLabel")
	lockText.Name = "LockText"
	lockText.Size = UDim2.fromScale(1, 1)
	lockText.BackgroundTransparency = 1
	lockText.Text = "LOCKED"
	lockText.Font = Enum.Font.GothamBold
	lockText.TextSize = 12
	lockText.TextColor3 = Color3.fromRGB(200, 200, 200)
	lockText.ZIndex = 6
	lockText.Parent = lockOverlay

	-- Hover
	btn.MouseEnter:Connect(function()
		if not lockOverlay.Visible then
			btn.BackgroundColor3 = COLOR_BTN_HOVER
		end
	end)
	btn.MouseLeave:Connect(function()
		if not lockOverlay.Visible then
			btn.BackgroundColor3 = COLOR_BTN
		end
	end)

	-- Click
	btn.Activated:Connect(function()
		self:_sendCreep(index)
	end)

	return btn
end

--------------------------------------------------------------------------------
-- Lock/unlock based on TownHall tier
--------------------------------------------------------------------------------

function CreepBarController:_refreshLocks(tier: number)
	for i, entry in self._sortedCreeps do
		local info = self._buttons[i]
		if not info then
			continue
		end
		local btn = info.Button
		local lockOverlay = btn:FindFirstChild("LockOverlay") :: Frame?
		if not lockOverlay then
			continue
		end

		local locked = entry.def.Tier > tier
		lockOverlay.Visible = locked
		btn.BackgroundColor3 = if locked then COLOR_LOCKED else COLOR_BTN
	end
end

--------------------------------------------------------------------------------
-- Send creep
--------------------------------------------------------------------------------

function CreepBarController:_sendCreep(index: number)
	local info = self._buttons[index]
	if not info then
		return
	end

	local btn = info.Button
	local lockOverlay = btn:FindFirstChild("LockOverlay") :: Frame?
	if lockOverlay and lockOverlay.Visible then
		return
	end

	local ShopService = Knit.GetService("ShopService")
	local success = ShopService:BuyCreep(info.CreepId)

	-- Flash feedback
	local flashColor = if success then COLOR_FLASH_GREEN else COLOR_FLASH_RED
	btn.BackgroundColor3 = flashColor
	local tween = TweenService:Create(btn, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundColor3 = COLOR_BTN,
	})
	tween:Play()
end

--------------------------------------------------------------------------------
-- Hotkey bindings (1-9)
--------------------------------------------------------------------------------

function CreepBarController:_bindHotkeys()
	for i = 1, math.min(#self._sortedCreeps, #HOTKEYS) do
		local idx = i
		ContextActionService:BindAction("SendCreep_" .. idx, function(_, state)
			if state == Enum.UserInputState.Begin then
				self:_sendCreep(idx)
			end
		end, false, HOTKEYS[idx])
	end
end

return CreepBarController
