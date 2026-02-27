--!strict

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
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
HUDController._scoreboardFrame = nil :: Frame?
HUDController._scoreboardVisible = false :: boolean
HUDController._statsFrame = nil :: Frame?

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

	GameService.TimerSync:Connect(function(_phase: string, timer: number)
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

	-- Connect hero combat signals for floating damage + attack visual
	local HeroCombatService = Knit.GetService("HeroCombatService")
	HeroCombatService.HeroAttacked:Connect(function(attackerUserId: number, _creepId: number, damage: number, creepPosition: Vector3, killed: boolean)
		self:_showFloatingDamage(creepPosition, damage, killed)

		local localPlayer = Players.LocalPlayer
		if localPlayer and localPlayer.UserId == attackerUserId then
			self:_showAttackVisual(creepPosition)
		end
	end)

	-- Connect kill reward signal (fires for hero kills AND assist kills)
	local CreepService = Knit.GetService("CreepService")
	CreepService.CreepKillReward:Connect(function(creepPosition: Vector3, bountyGold: number, xpGained: number)
		self:_showKillReward(creepPosition, bountyGold, xpGained)
	end)

	-- Fetch initial values
	local initialGold = IncomeService:GetGold()
	local initialIncome = IncomeService:GetIncome()
	self:_updateGoldDisplay(initialGold)
	self:_updateIncomeDisplay(initialIncome)

	local lives1 = BaseService:GetLives(1)
	local lives2 = BaseService:GetLives(2)
	self:_onLivesUpdated({ [1] = lives1, [2] = lives2 })

	-- Tab key toggles scoreboard
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Tab then
			self._scoreboardVisible = not self._scoreboardVisible
			if self._scoreboardFrame then
				self._scoreboardFrame.Visible = self._scoreboardVisible
			end
			if self._scoreboardVisible then
				self:_refreshScoreboard()
			end
		end
	end)

	-- Listen for combat state changes to update stats panel
	HeroCombatService.CombatStateChanged:Connect(function(stats: { [string]: any })
		self:_updateStatsPanel(stats)
	end)

	-- Periodically refresh scoreboard while visible
	task.spawn(function()
		while true do
			task.wait(3)
			if self._scoreboardVisible then
				self:_refreshScoreboard()
			end
		end
	end)
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
	self:_createScoreboard(screenGui)
	self:_createStatsPanel(screenGui)
end

function HUDController:_createTopCenterPanel(parent: ScreenGui)
	local panel = Instance.new("Frame")
	panel.Name = "TopCenterPanel"
	panel.Size = UDim2.new(0, 260, 0, 70)
	panel.Position = UDim2.new(0.5, 0, 0, 38)
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
	panel.Position = UDim2.new(0, 10, 0, 40)
	panel.BackgroundColor3 = Color3.new(0, 0, 0)
	panel.BackgroundTransparency = 0.5
	panel.BorderSizePixel = 0
	panel.ZIndex = 10
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
	goldLabel.ZIndex = 11
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
	incomeLabel.ZIndex = 11
	incomeLabel.Parent = panel
	self._incomeLabel = incomeLabel
end

function HUDController:_createTopRightPanel(parent: ScreenGui)
	local panel = Instance.new("Frame")
	panel.Name = "TopRightPanel"
	panel.Size = UDim2.new(0, 180, 0, 60)
	panel.Position = UDim2.new(1, -10, 0, 40)
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

function HUDController:_showFloatingDamage(worldPosition: Vector3, damage: number, killed: boolean)
	-- Create a BillboardGui in workspace for 3D floating text
	local part = Instance.new("Part")
	part.Name = "DamageFloat"
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Position = worldPosition + Vector3.new(0, 3, 0)
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Parent = workspace

	local gui = Instance.new("BillboardGui")
	gui.Name = "DamageGui"
	gui.Size = UDim2.fromOffset(80, 30)
	gui.StudsOffset = Vector3.new(0, 0, 0)
	gui.AlwaysOnTop = true
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "-" .. math.floor(damage)
	label.TextColor3 = if killed then Color3.fromRGB(255, 100, 50) else Color3.fromRGB(255, 255, 100)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Parent = gui

	-- Animate upward and fade
	local startPos = part.Position
	local endPos = startPos + Vector3.new(0, 4, 0)

	local tweenInfo = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local positionTween = TweenService:Create(part, tweenInfo, {
		Position = endPos,
	})
	local fadeTween = TweenService:Create(label, tweenInfo, {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})

	positionTween:Play()
	fadeTween:Play()

	fadeTween.Completed:Connect(function()
		part:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Kill Reward Animation (gold + XP floating text)
--------------------------------------------------------------------------------

function HUDController:_showKillReward(worldPosition: Vector3, gold: number, xp: number)
	if gold <= 0 and xp <= 0 then
		return
	end

	-- Gold popup with coin icon (offset left)
	if gold > 0 then
		local goldPart = Instance.new("Part")
		goldPart.Name = "GoldFloat"
		goldPart.Size = Vector3.new(0.1, 0.1, 0.1)
		goldPart.Position = worldPosition + Vector3.new(-1.5, 4, 0)
		goldPart.Anchored = true
		goldPart.CanCollide = false
		goldPart.Transparency = 1
		goldPart.Parent = workspace

		local goldGui = Instance.new("BillboardGui")
		goldGui.Name = "GoldGui"
		goldGui.Size = UDim2.fromOffset(110, 32)
		goldGui.AlwaysOnTop = true
		goldGui.Parent = goldPart

		-- Coin icon (yellow circle)
		local coinFrame = Instance.new("Frame")
		coinFrame.Name = "Coin"
		coinFrame.Size = UDim2.new(0, 22, 0, 22)
		coinFrame.Position = UDim2.new(0, 0, 0.5, 0)
		coinFrame.AnchorPoint = Vector2.new(0, 0.5)
		coinFrame.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
		coinFrame.BorderSizePixel = 0
		coinFrame.Parent = goldGui

		local coinCorner = Instance.new("UICorner")
		coinCorner.CornerRadius = UDim.new(1, 0)
		coinCorner.Parent = coinFrame

		local coinText = Instance.new("TextLabel")
		coinText.Size = UDim2.new(1, 0, 1, 0)
		coinText.BackgroundTransparency = 1
		coinText.Text = "G"
		coinText.TextColor3 = Color3.fromRGB(120, 90, 0)
		coinText.TextScaled = true
		coinText.Font = Enum.Font.GothamBold
		coinText.Parent = coinFrame

		-- Gold amount label (next to coin)
		local goldLabel = Instance.new("TextLabel")
		goldLabel.Size = UDim2.new(1, -26, 1, 0)
		goldLabel.Position = UDim2.new(0, 26, 0, 0)
		goldLabel.BackgroundTransparency = 1
		goldLabel.Text = "+" .. gold
		goldLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
		goldLabel.TextScaled = true
		goldLabel.Font = Enum.Font.GothamBold
		goldLabel.TextStrokeTransparency = 0.2
		goldLabel.TextStrokeColor3 = Color3.fromRGB(100, 80, 0)
		goldLabel.TextXAlignment = Enum.TextXAlignment.Left
		goldLabel.Parent = goldGui

		local goldEndPos = goldPart.Position + Vector3.new(0, 5, 0)
		local tweenInfo = TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local posTween = TweenService:Create(goldPart, tweenInfo, { Position = goldEndPos })
		local fadeTween = TweenService:Create(goldLabel, tweenInfo, {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		local coinFade = TweenService:Create(coinFrame, tweenInfo, {
			BackgroundTransparency = 1,
		})
		local coinTextFade = TweenService:Create(coinText, tweenInfo, {
			TextTransparency = 1,
		})

		posTween:Play()
		fadeTween:Play()
		coinFade:Play()
		coinTextFade:Play()
		fadeTween.Completed:Connect(function()
			goldPart:Destroy()
		end)
	end

	-- XP popup (offset right)
	if xp > 0 then
		local xpPart = Instance.new("Part")
		xpPart.Name = "XPFloat"
		xpPart.Size = Vector3.new(0.1, 0.1, 0.1)
		xpPart.Position = worldPosition + Vector3.new(1.5, 4, 0)
		xpPart.Anchored = true
		xpPart.CanCollide = false
		xpPart.Transparency = 1
		xpPart.Parent = workspace

		local xpGui = Instance.new("BillboardGui")
		xpGui.Name = "XPGui"
		xpGui.Size = UDim2.fromOffset(90, 28)
		xpGui.AlwaysOnTop = true
		xpGui.Parent = xpPart

		local xpLabel = Instance.new("TextLabel")
		xpLabel.Size = UDim2.new(1, 0, 1, 0)
		xpLabel.BackgroundTransparency = 1
		xpLabel.Text = "+" .. xp .. " XP"
		xpLabel.TextColor3 = Color3.fromRGB(100, 180, 255)
		xpLabel.TextScaled = true
		xpLabel.Font = Enum.Font.GothamBold
		xpLabel.TextStrokeTransparency = 0.2
		xpLabel.TextStrokeColor3 = Color3.fromRGB(20, 40, 100)
		xpLabel.Parent = xpGui

		local xpEndPos = xpPart.Position + Vector3.new(0, 5, 0)
		local tweenInfo = TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local posTween = TweenService:Create(xpPart, tweenInfo, { Position = xpEndPos })
		local fadeTween = TweenService:Create(xpLabel, tweenInfo, {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})

		posTween:Play()
		fadeTween:Play()
		fadeTween.Completed:Connect(function()
			xpPart:Destroy()
		end)
	end
end

--------------------------------------------------------------------------------
-- Attack Visual
--------------------------------------------------------------------------------

function HUDController:_showAttackVisual(targetPosition: Vector3)
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return
	end
	local character = localPlayer.Character
	if not character then
		return
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end

	-- Face the target
	local heroPos = rootPart.Position
	local direction = (targetPosition - heroPos) * Vector3.new(1, 0, 1) -- flatten Y
	if direction.Magnitude > 0.1 then
		rootPart.CFrame = CFrame.new(heroPos, heroPos + direction)
	end

	-- Play the tool activation animation if a tool is equipped
	local tool = character:FindFirstChildOfClass("Tool")
	if tool then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local animator = humanoid:FindFirstChildOfClass("Animator")
			if not animator then
				animator = Instance.new("Animator")
				animator.Parent = humanoid
			end

			local anim = Instance.new("Animation")
			anim.AnimationId = "rbxassetid://522635514" -- default slash
			local track = animator:LoadAnimation(anim)
			track.Priority = Enum.AnimationPriority.Action
			track:Play(0)
			anim:Destroy()
		end
	end

	-- Slash arc effect between hero and target
	local midPoint = (heroPos + targetPosition) / 2
	local dist = (targetPosition - heroPos).Magnitude

	local slash = Instance.new("Part")
	slash.Name = "SlashArc"
	slash.Size = Vector3.new(dist * 0.6, 0.3, 2)
	slash.Anchored = true
	slash.CanCollide = false
	slash.Material = Enum.Material.Neon
	slash.Color = Color3.fromRGB(255, 255, 200)
	slash.Transparency = 0.3
	slash.CFrame = CFrame.new(midPoint, targetPosition)
	slash.Parent = workspace

	-- Quick fade-out
	local tweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeTween = TweenService:Create(slash, tweenInfo, {
		Transparency = 1,
		Size = Vector3.new(dist * 0.6, 0.1, 3),
	})
	fadeTween:Play()
	fadeTween.Completed:Connect(function()
		slash:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Scoreboard (Tab to toggle)
--------------------------------------------------------------------------------

function HUDController:_createScoreboard(parent: ScreenGui)
	local frame = Instance.new("Frame")
	frame.Name = "Scoreboard"
	frame.Size = UDim2.new(0, 500, 0, 300)
	frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.ZIndex = 15
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(60, 60, 70)
	stroke.Thickness = 1
	stroke.Parent = frame

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 30)
	title.BackgroundTransparency = 1
	title.Text = "SCOREBOARD"
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.TextColor3 = Color3.fromRGB(255, 215, 80)
	title.ZIndex = 16
	title.Parent = frame

	-- Column headers
	local headers = Instance.new("Frame")
	headers.Name = "Headers"
	headers.Size = UDim2.new(1, -16, 0, 20)
	headers.Position = UDim2.new(0, 8, 0, 32)
	headers.BackgroundTransparency = 1
	headers.ZIndex = 16
	headers.Parent = frame

	local cols = { { "Player", 0.35 }, { "Hero", 0.15 }, { "Lv", 0.1 }, { "Gold", 0.2 }, { "Income", 0.2 } }
	local xOff = 0
	for _, col in cols do
		local h = Instance.new("TextLabel")
		h.Size = UDim2.new(col[2], 0, 1, 0)
		h.Position = UDim2.new(xOff, 0, 0, 0)
		h.BackgroundTransparency = 1
		h.Text = col[1]
		h.Font = Enum.Font.GothamBold
		h.TextSize = 11
		h.TextColor3 = Color3.fromRGB(150, 150, 160)
		h.TextXAlignment = Enum.TextXAlignment.Left
		h.ZIndex = 16
		h.Parent = headers
		xOff += col[2]
	end

	-- Rows container
	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.Size = UDim2.new(1, -16, 1, -60)
	rows.Position = UDim2.new(0, 8, 0, 54)
	rows.BackgroundTransparency = 1
	rows.ZIndex = 16
	rows.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = rows

	self._scoreboardFrame = frame
end

function HUDController:_refreshScoreboard()
	local frame = self._scoreboardFrame
	if not frame or not frame.Visible then
		return
	end

	local rows = frame:FindFirstChild("Rows") :: Frame?
	if not rows then
		return
	end

	-- Clear old rows
	for _, child in rows:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	-- Fetch data from server
	local GameService = Knit.GetService("GameService")
	local data = GameService:GetScoreboard()
	if not data then
		return
	end

	local teamColors = {
		[1] = Color3.fromRGB(80, 140, 255),
		[2] = Color3.fromRGB(255, 80, 80),
	}

	for i, entry in data do
		local row = Instance.new("Frame")
		row.Name = "Row_" .. tostring(i)
		row.Size = UDim2.new(1, 0, 0, 22)
		row.BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(25, 25, 30) else Color3.fromRGB(30, 30, 38)
		row.BackgroundTransparency = 0.3
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		row.ZIndex = 16
		row.Parent = rows

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 3)
		rowCorner.Parent = row

		local textColor = teamColors[entry.TeamId] or Color3.new(1, 1, 1)
		local cols = {
			{ tostring(entry.Name), 0.35, textColor },
			{ tostring(entry.HeroId), 0.15, Color3.fromRGB(180, 180, 190) },
			{ tostring(entry.Level), 0.1, Color3.fromRGB(100, 200, 255) },
			{ Util.formatGold(entry.Gold) .. "g", 0.2, Color3.fromRGB(255, 215, 80) },
			{ "+" .. tostring(entry.Income), 0.2, Color3.fromRGB(100, 255, 100) },
		}
		local xOff = 0
		for _, col in cols do
			local label = Instance.new("TextLabel")
			label.Size = UDim2.new(col[2], 0, 1, 0)
			label.Position = UDim2.new(xOff, 4, 0, 0)
			label.BackgroundTransparency = 1
			label.Text = col[1]
			label.Font = Enum.Font.GothamMedium
			label.TextSize = 12
			label.TextColor3 = col[3]
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.ZIndex = 17
			label.Parent = row
			xOff += col[2]
		end
	end
end

--------------------------------------------------------------------------------
-- Combat Stats Panel (bottom-left, shows hero stats + active buffs)
--------------------------------------------------------------------------------

function HUDController:_createStatsPanel(parent: ScreenGui)
	local frame = Instance.new("Frame")
	frame.Name = "StatsPanel"
	frame.Size = UDim2.new(0, 180, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Position = UDim2.new(0, 10, 1, -130)
	frame.AnchorPoint = Vector2.new(0, 1)
	frame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = false
	frame.Visible = false
	frame.ZIndex = 8
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = frame

	self._statsFrame = frame
end

function HUDController:_updateStatsPanel(stats: { [string]: any })
	local frame = self._statsFrame
	if not frame then
		return
	end

	-- Clear old content labels (keep UICorner, UIPadding, UIListLayout)
	for _, child in frame:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	-- Compute armor reduction %
	local armor = stats.Armor or 0
	local armorPct = math.min(armor / (armor + 30), 0.75) * 100

	local baseDmg = stats.AttackDamage or 0
	local dmgVariance = 0.20
	local dmgMin = math.floor(baseDmg * (1 - dmgVariance))
	local dmgMax = math.floor(baseDmg * (1 + dmgVariance))

	local statLines = {
		{ "ATK", dmgMin .. "-" .. dmgMax, Color3.fromRGB(255, 150, 80) },
		{ "ARM", tostring(math.floor(armor)) .. " (" .. string.format("%.0f%%", armorPct) .. ")", Color3.fromRGB(255, 215, 80) },
		{ "HP", tostring(math.floor(stats.Health or 0)) .. "/" .. tostring(math.floor(stats.MaxHealth or 0)), Color3.fromRGB(80, 220, 80) },
		{ "MP", tostring(math.floor(stats.Mana or 0)) .. "/" .. tostring(math.floor(stats.MaxMana or 0)), Color3.fromRGB(80, 140, 255) },
		{ "SPD", tostring(math.floor(stats.MoveSpeed or 16)), Color3.fromRGB(180, 180, 255) },
		{ "RNG", tostring(math.floor(stats.AttackRange or 12)), Color3.fromRGB(200, 160, 255) },
		{ "AS", string.format("%.1fs", stats.AttackCooldown or 1.5), Color3.fromRGB(255, 200, 150) },
		{ "MREG", string.format("%.1f/s", stats.ManaRegen or 1), Color3.fromRGB(100, 160, 255) },
	}

	-- Add shield stats if hero has any shield
	local maxShield = stats.MaxShield or 0
	if maxShield > 0 then
		local shield = stats.Shield or 0
		table.insert(statLines, { "SHD", tostring(math.floor(shield)) .. "/" .. tostring(math.floor(maxShield)), Color3.fromRGB(100, 200, 255) })
		table.insert(statLines, { "REGEN", "10/s (5s delay)", Color3.fromRGB(80, 180, 220) })
	end

	local layoutOrder = 0
	for _, line in statLines do
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 0, 14)
		label.BackgroundTransparency = 1
		label.Text = line[1] .. ": " .. line[2]
		label.Font = Enum.Font.GothamMedium
		label.TextSize = 11
		label.TextColor3 = line[3]
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.ZIndex = 9
		label.LayoutOrder = layoutOrder
		label.Parent = frame
		layoutOrder += 1
	end

	-- Active buffs section
	local buffs = stats.Buffs
	if buffs and #buffs > 0 then
		local now = os.clock()
		for _, buff in buffs do
			local remaining = math.max(0, (buff.ExpiresAt or 0) - now)
			local buffLabel = Instance.new("TextLabel")
			buffLabel.Size = UDim2.new(1, 0, 0, 14)
			buffLabel.BackgroundTransparency = 1
			buffLabel.Text = buff.Name .. " (" .. string.format("%.0fs", remaining) .. ")"
			buffLabel.Font = Enum.Font.GothamBold
			buffLabel.TextSize = 10
			buffLabel.TextColor3 = Color3.fromRGB(120, 255, 200)
			buffLabel.TextXAlignment = Enum.TextXAlignment.Left
			buffLabel.ZIndex = 9
			buffLabel.LayoutOrder = layoutOrder
			buffLabel.Parent = frame
			layoutOrder += 1

			-- Pulse effect for temporary buffs
			if remaining > 0 and remaining < 5 then
				task.spawn(function()
					while buffLabel.Parent and remaining > 0 do
						buffLabel.TextTransparency = 0.6
						task.wait(0.3)
						if not buffLabel.Parent then break end
						buffLabel.TextTransparency = 0
						task.wait(0.3)
						remaining -= 0.6
					end
				end)
			end
		end
	end

	frame.Visible = true
end

return HUDController
