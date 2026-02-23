--!strict

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Util = require(ReplicatedStorage.Shared.Util)

local HUDController = Knit.CreateController({
	Name = "HUDController",
})

HUDController._gold = 0 :: number
HUDController._income = 0 :: number
HUDController._teamLives = { [1] = 100, [2] = 100 } :: { [number]: number }
HUDController._screenGui = nil :: ScreenGui?
HUDController._goldLabel = nil :: TextLabel?
HUDController._incomeLabel = nil :: TextLabel?
HUDController._phaseLabel = nil :: TextLabel?
HUDController._timerLabel = nil :: TextLabel?
HUDController._team1LivesLabel = nil :: TextLabel?
HUDController._team2LivesLabel = nil :: TextLabel?
HUDController._gameOverFrame = nil :: Frame?
HUDController._gameOverLabel = nil :: TextLabel?

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function HUDController:KnitInit()
	self:_createUI()
end

function HUDController:KnitStart()
	local IncomeService = Knit.GetService("IncomeService")
	local GameService = Knit.GetService("GameService")
	local BaseService = Knit.GetService("BaseService")

	IncomeService.GoldChanged:Connect(function(amount: number)
		self:_updateGoldDisplay(amount)
	end)

	IncomeService.IncomeChanged:Connect(function(amount: number)
		self:_updateIncomeDisplay(amount)
	end)

	IncomeService.IncomeTick:Connect(function(amount: number)
		self:_showIncomeTick(amount)
	end)

	GameService.PhaseChanged:Connect(function(phase: string, timer: number)
		self:_onPhaseChanged(phase, timer)
	end)

	GameService.TimerSync:Connect(function(timer: number)
		self:_updateTimer(timer)
	end)

	GameService.GameOver:Connect(function(winningTeamId: number)
		self:_showGameOver(winningTeamId)
	end)

	GameService.LivesUpdated:Connect(function(lives: { [number]: number })
		self:_onLivesUpdated(lives)
	end)

	BaseService.BaseDamaged:Connect(function(teamId: number, amount: number)
		self:_onBaseDamaged(teamId, amount)
	end)

	-- Fetch initial values
	local initialGold = IncomeService:GetGold()
	local initialIncome = IncomeService:GetIncome()
	self:_updateGoldDisplay(initialGold)
	self:_updateIncomeDisplay(initialIncome)

	local lives1 = BaseService:GetLives(1)
	local lives2 = BaseService:GetLives(2)
	self:_onLivesUpdated({ [1] = lives1, [2] = lives2 })
end

--------------------------------------------------------------------------------
-- UI Construction
--------------------------------------------------------------------------------

function HUDController:_createUI()
	local player = Players.LocalPlayer
	if not player then
		return
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "HLW_HUD"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = player.PlayerGui
	self._screenGui = screenGui

	self:_createTopCenterPanel(screenGui)
	self:_createTopLeftPanel(screenGui)
	self:_createTopRightPanel(screenGui)
	self:_createGameOverOverlay(screenGui)
end

function HUDController:_createTopCenterPanel(parent: ScreenGui)
	local panel = Instance.new("Frame")
	panel.Name = "TopCenterPanel"
	panel.Size = UDim2.new(0, 260, 0, 70)
	panel.Position = UDim2.new(0.5, 0, 0, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.BackgroundColor3 = Color3.new(0, 0, 0)
	panel.BackgroundTransparency = 0.5
	panel.BorderSizePixel = 0
	panel.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = panel

	local phaseLabel = Instance.new("TextLabel")
	phaseLabel.Name = "PhaseLabel"
	phaseLabel.Size = UDim2.new(1, -20, 0, 30)
	phaseLabel.Position = UDim2.new(0, 10, 0, 8)
	phaseLabel.BackgroundTransparency = 1
	phaseLabel.Font = Enum.Font.GothamBold
	phaseLabel.TextSize = 24
	phaseLabel.TextColor3 = Color3.new(1, 1, 1)
	phaseLabel.TextXAlignment = Enum.TextXAlignment.Center
	phaseLabel.TextYAlignment = Enum.TextYAlignment.Center
	phaseLabel.Text = Constants.PHASE_LOBBY
	phaseLabel.Parent = panel
	self._phaseLabel = phaseLabel

	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerLabel"
	timerLabel.Size = UDim2.new(1, -20, 0, 24)
	timerLabel.Position = UDim2.new(0, 10, 0, 38)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Font = Enum.Font.GothamMedium
	timerLabel.TextSize = 20
	timerLabel.TextColor3 = Color3.new(1, 1, 1)
	timerLabel.TextXAlignment = Enum.TextXAlignment.Center
	timerLabel.TextYAlignment = Enum.TextYAlignment.Center
	timerLabel.Text = ""
	timerLabel.Parent = panel
	self._timerLabel = timerLabel
end

function HUDController:_createTopLeftPanel(parent: ScreenGui)
	local panel = Instance.new("Frame")
	panel.Name = "TopLeftPanel"
	panel.Size = UDim2.new(0, 200, 0, 60)
	panel.Position = UDim2.new(0, 10, 0, 10)
	panel.BackgroundColor3 = Color3.new(0, 0, 0)
	panel.BackgroundTransparency = 0.5
	panel.BorderSizePixel = 0
	panel.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = panel

	local goldLabel = Instance.new("TextLabel")
	goldLabel.Name = "GoldLabel"
	goldLabel.Size = UDim2.new(1, -16, 0, 24)
	goldLabel.Position = UDim2.new(0, 8, 0, 6)
	goldLabel.BackgroundTransparency = 1
	goldLabel.Font = Enum.Font.GothamBold
	goldLabel.TextSize = 20
	goldLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	goldLabel.TextXAlignment = Enum.TextXAlignment.Left
	goldLabel.TextYAlignment = Enum.TextYAlignment.Center
	goldLabel.Text = "Gold: " .. Util.formatGold(Constants.STARTING_GOLD)
	goldLabel.Parent = panel
	self._goldLabel = goldLabel

	local incomeLabel = Instance.new("TextLabel")
	incomeLabel.Name = "IncomeLabel"
	incomeLabel.Size = UDim2.new(1, -16, 0, 22)
	incomeLabel.Position = UDim2.new(0, 8, 0, 32)
	incomeLabel.BackgroundTransparency = 1
	incomeLabel.Font = Enum.Font.GothamMedium
	incomeLabel.TextSize = 18
	incomeLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
	incomeLabel.TextXAlignment = Enum.TextXAlignment.Left
	incomeLabel.TextYAlignment = Enum.TextYAlignment.Center
	incomeLabel.Text = "Income: " .. Constants.STARTING_INCOME
	incomeLabel.Parent = panel
	self._incomeLabel = incomeLabel
end

function HUDController:_createTopRightPanel(parent: ScreenGui)
	local panel = Instance.new("Frame")
	panel.Name = "TopRightPanel"
	panel.Size = UDim2.new(0, 180, 0, 60)
	panel.Position = UDim2.new(1, -10, 0, 10)
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.BackgroundColor3 = Color3.new(0, 0, 0)
	panel.BackgroundTransparency = 0.5
	panel.BorderSizePixel = 0
	panel.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = panel

	local team1Label = Instance.new("TextLabel")
	team1Label.Name = "Team1LivesLabel"
	team1Label.Size = UDim2.new(1, -16, 0, 22)
	team1Label.Position = UDim2.new(0, 8, 0, 6)
	team1Label.BackgroundTransparency = 1
	team1Label.Font = Enum.Font.GothamBold
	team1Label.TextSize = 18
	team1Label.TextColor3 = Color3.fromRGB(50, 100, 200)
	team1Label.TextXAlignment = Enum.TextXAlignment.Right
	team1Label.TextYAlignment = Enum.TextYAlignment.Center
	team1Label.Text = "Blue: " .. Constants.BASE_MAX_LIVES
	team1Label.Parent = panel
	self._team1LivesLabel = team1Label

	local team2Label = Instance.new("TextLabel")
	team2Label.Name = "Team2LivesLabel"
	team2Label.Size = UDim2.new(1, -16, 0, 22)
	team2Label.Position = UDim2.new(0, 8, 0, 32)
	team2Label.BackgroundTransparency = 1
	team2Label.Font = Enum.Font.GothamBold
	team2Label.TextSize = 18
	team2Label.TextColor3 = Color3.fromRGB(200, 50, 50)
	team2Label.TextXAlignment = Enum.TextXAlignment.Right
	team2Label.TextYAlignment = Enum.TextYAlignment.Center
	team2Label.Text = "Red: " .. Constants.BASE_MAX_LIVES
	team2Label.Parent = panel
	self._team2LivesLabel = team2Label
end

function HUDController:_createGameOverOverlay(parent: ScreenGui)
	local overlay = Instance.new("Frame")
	overlay.Name = "GameOverOverlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.Position = UDim2.new(0, 0, 0, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.3
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.ZIndex = 10
	overlay.Parent = parent
	self._gameOverFrame = overlay

	local resultLabel = Instance.new("TextLabel")
	resultLabel.Name = "GameOverLabel"
	resultLabel.Size = UDim2.new(1, 0, 0, 60)
	resultLabel.Position = UDim2.new(0.5, 0, 0.4, 0)
	resultLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	resultLabel.BackgroundTransparency = 1
	resultLabel.Font = Enum.Font.GothamBold
	resultLabel.TextSize = 48
	resultLabel.TextColor3 = Color3.new(1, 1, 1)
	resultLabel.TextXAlignment = Enum.TextXAlignment.Center
	resultLabel.TextYAlignment = Enum.TextYAlignment.Center
	resultLabel.Text = ""
	resultLabel.ZIndex = 11
	resultLabel.Parent = overlay
	self._gameOverLabel = resultLabel

	local subtextLabel = Instance.new("TextLabel")
	subtextLabel.Name = "SubtextLabel"
	subtextLabel.Size = UDim2.new(1, 0, 0, 30)
	subtextLabel.Position = UDim2.new(0.5, 0, 0.4, 40)
	subtextLabel.AnchorPoint = Vector2.new(0.5, 0)
	subtextLabel.BackgroundTransparency = 1
	subtextLabel.Font = Enum.Font.GothamMedium
	subtextLabel.TextSize = 20
	subtextLabel.TextColor3 = Color3.new(1, 1, 1)
	subtextLabel.TextXAlignment = Enum.TextXAlignment.Center
	subtextLabel.TextYAlignment = Enum.TextYAlignment.Center
	subtextLabel.Text = "Returning to lobby..."
	subtextLabel.ZIndex = 11
	subtextLabel.Parent = overlay
end

--------------------------------------------------------------------------------
-- Display Updates
--------------------------------------------------------------------------------

function HUDController:_updateGoldDisplay(amount: number)
	self._gold = amount
	local label = self._goldLabel
	if label then
		label.Text = "Gold: " .. Util.formatGold(amount)
	end
end

function HUDController:_updateIncomeDisplay(amount: number)
	self._income = amount
	local label = self._incomeLabel
	if label then
		label.Text = "Income: " .. amount
	end
end

function HUDController:_showIncomeTick(amount: number)
	local goldLabel = self._goldLabel
	local screenGui = self._screenGui
	if not goldLabel or not screenGui then
		return
	end

	local tickLabel = Instance.new("TextLabel")
	tickLabel.Name = "IncomeTick"
	tickLabel.Size = UDim2.new(0, 100, 0, 24)
	tickLabel.Position = goldLabel.AbsolutePosition
			and UDim2.new(0, goldLabel.AbsolutePosition.X, 0, goldLabel.AbsolutePosition.Y)
		or UDim2.new(0, 10, 0, 10)
	tickLabel.BackgroundTransparency = 1
	tickLabel.Font = Enum.Font.GothamBold
	tickLabel.TextSize = 20
	tickLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	tickLabel.TextXAlignment = Enum.TextXAlignment.Left
	tickLabel.TextYAlignment = Enum.TextYAlignment.Center
	tickLabel.Text = "+" .. amount
	tickLabel.TextTransparency = 0
	tickLabel.ZIndex = 5
	tickLabel.Parent = screenGui

	local targetPosition = UDim2.new(
		tickLabel.Position.X.Scale,
		tickLabel.Position.X.Offset,
		tickLabel.Position.Y.Scale,
		tickLabel.Position.Y.Offset - 40
	)

	local tweenInfo = TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(tickLabel, tweenInfo, {
		Position = targetPosition,
		TextTransparency = 1,
	})

	tween:Play()
	tween.Completed:Connect(function()
		tickLabel:Destroy()
	end)
end

function HUDController:_onPhaseChanged(phase: string, timer: number)
	local phaseLabel = self._phaseLabel
	if phaseLabel then
		phaseLabel.Text = phase
	end

	self:_updateTimer(timer)

	local overlay = self._gameOverFrame
	if overlay and overlay.Visible then
		overlay.Visible = false
	end
end

function HUDController:_updateTimer(timer: number)
	local timerLabel = self._timerLabel
	if not timerLabel then
		return
	end

	if timer <= 0 then
		timerLabel.Visible = false
	else
		timerLabel.Visible = true
		timerLabel.Text = Util.formatTime(timer)
	end
end

function HUDController:_showGameOver(winningTeamId: number)
	local overlay = self._gameOverFrame
	local resultLabel = self._gameOverLabel
	if not overlay or not resultLabel then
		return
	end

	local TeamService = Knit.GetService("TeamService")
	local localTeamId = TeamService:GetTeam()

	local won = (localTeamId == winningTeamId)
	if won then
		resultLabel.Text = "VICTORY!"
		resultLabel.TextColor3 = Color3.fromRGB(50, 200, 50)
	else
		resultLabel.Text = "DEFEAT"
		resultLabel.TextColor3 = Color3.fromRGB(200, 50, 50)
	end

	overlay.Visible = true
end

function HUDController:_onLivesUpdated(lives: { [number]: number })
	self._teamLives = lives

	local team1Label = self._team1LivesLabel
	if team1Label then
		local team1Lives = lives[1] or 0
		team1Label.Text = "Blue: " .. team1Lives
	end

	local team2Label = self._team2LivesLabel
	if team2Label then
		local team2Lives = lives[2] or 0
		team2Label.Text = "Red: " .. team2Lives
	end
end

function HUDController:_onBaseDamaged(teamId: number, _amount: number)
	local TeamService = Knit.GetService("TeamService")
	local localTeamId = TeamService:GetTeam()

	if localTeamId == teamId then
		local CameraController = Knit.GetController("CameraController")
		if CameraController and CameraController.ShakeCamera then
			CameraController:ShakeCamera()
		end
	end
end

return HUDController
