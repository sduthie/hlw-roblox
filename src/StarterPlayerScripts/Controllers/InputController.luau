--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

local Knit = require(ReplicatedStorage.Packages.Knit)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig)

local InputController = Knit.CreateController({
	Name = "InputController",
})

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

InputController._keybinds = {
	ToggleShop = Enum.KeyCode.B,
}

InputController._moveIndicator = nil :: Part?
InputController._raycastParams = nil :: RaycastParams?
InputController._teamId = nil :: number? -- cached team assignment for lane lock
InputController._targetHighlight = nil :: Highlight?

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function InputController:KnitInit()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {}
	self._raycastParams = params
end

function InputController:KnitStart()
	-- Hide default Roblox backpack GUI so weapon tools don't overlay the skill bar
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)

	self:_disableDefaultControls()
	self:_bindAbilities()
	self:_bindMouseActions()
	self:_createMoveIndicator()

	-- Update raycast filter whenever character spawns
	local player = Players.LocalPlayer
	if player then
		player.CharacterAdded:Connect(function()
			self:_updateRaycastFilter()
		end)
		self:_updateRaycastFilter()
	end

	-- Fetch team assignment for lane lock
	task.defer(function()
		local ok, TeamService = pcall(function()
			return Knit.GetService("TeamService")
		end)
		if ok and TeamService then
			self._teamId = TeamService:GetTeam()
		end
	end)
end

--------------------------------------------------------------------------------
-- Disable default WASD movement (RTS uses click-to-move)
--------------------------------------------------------------------------------

function InputController:_disableDefaultControls()
	local player = Players.LocalPlayer
	if not player then
		return
	end

	local playerScripts = player:WaitForChild("PlayerScripts")
	local ok, playerModule = pcall(function()
		return require(playerScripts:WaitForChild("PlayerModule"))
	end)
	if ok and playerModule then
		local controls = playerModule:GetControls()
		controls:Disable()
	end
end

--------------------------------------------------------------------------------
-- Raycast filter: exclude local character and creeps from ground raycasts
--------------------------------------------------------------------------------

function InputController:_updateRaycastFilter()
	local player = Players.LocalPlayer
	if not player or not self._raycastParams then
		return
	end

	local exclude = {}
	if player.Character then
		table.insert(exclude, player.Character)
	end
	local creepFolder = workspace:FindFirstChild("Creeps")
	if creepFolder then
		table.insert(exclude, creepFolder)
	end
	self._raycastParams.FilterDescendantsInstances = exclude
end

--------------------------------------------------------------------------------
-- Ability keybinds (Q/W/E/R + B for shop)
--------------------------------------------------------------------------------

function InputController:_bindAbilities()
	-- NOTE: Q/W/E/R ability casting is handled by SkillBarController via UserInputService
	-- (supports ground targeting, pet commands, etc.)
	-- Only bind shop toggle here since InputController owns the shop interaction
	ContextActionService:BindAction("ToggleShop", function(_, state)
		if state == Enum.UserInputState.Begin then
			self:_onToggleShop()
		end
	end, false, self._keybinds.ToggleShop)
end

--------------------------------------------------------------------------------
-- Mouse actions
-- Right-click (or touch tap): contextual — target creep or move to ground
-- Left-click: shop interaction
--------------------------------------------------------------------------------

function InputController:_bindMouseActions()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end

		-- Right-click OR touch tap: contextual action (target creep / move)
		if input.UserInputType == Enum.UserInputType.MouseButton2
			or input.UserInputType == Enum.UserInputType.Touch then
			self:_onContextualClick()
		end

		-- Left-click: shop interaction only (desktop)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:_onLeftClick()
		end
	end)
end

--------------------------------------------------------------------------------
-- Contextual click: target a creep or move to ground
--------------------------------------------------------------------------------

function InputController:_onContextualClick()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local player = Players.LocalPlayer
	if not player or not player.Character then
		return
	end

	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

	-- First: try to hit a creep (include creep folder in raycast)
	local fullParams = RaycastParams.new()
	fullParams.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	if player.Character then
		table.insert(exclude, player.Character)
	end
	fullParams.FilterDescendantsInstances = exclude

	local result = workspace:Raycast(ray.Origin, ray.Direction * 500, fullParams)
	if result and result.Instance then
		-- Check if we hit a creep model (lives in workspace.Creeps folder)
		local creepModel = self:_findCreepModel(result.Instance)
		if creepModel then
			self:_targetCreep(creepModel)
			return
		end

		-- Check if we hit a shop
		if self:_checkShopClick(result.Instance) then
			return
		end
	end

	-- Fallback: move to ground position
	local groundResult = workspace:Raycast(ray.Origin, ray.Direction * 500, self._raycastParams)
	if groundResult then
		local hitPos = self:_clampToLane(groundResult.Position)
		-- Clear attack target when moving
		self:_clearTarget()
		humanoid:MoveTo(hitPos)
		self:_showMoveIndicator(hitPos)
	end
end

--------------------------------------------------------------------------------
-- Left-click: shop interaction (desktop only)
--------------------------------------------------------------------------------

function InputController:_onLeftClick()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	local player = Players.LocalPlayer
	if player and player.Character then
		table.insert(exclude, player.Character)
	end
	params.FilterDescendantsInstances = exclude

	local result = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
	if result and result.Instance then
		self:_checkShopClick(result.Instance)
	end
end

--------------------------------------------------------------------------------
-- Creep targeting
--------------------------------------------------------------------------------

function InputController:_findCreepModel(instance: Instance): Model?
	-- Walk up the parent chain looking for a model inside the Creeps folder
	local current: Instance? = instance
	while current and current ~= workspace do
		if current:IsA("Model") and current.Parent and current.Parent.Name == "Creeps" then
			return current :: Model
		end
		current = current.Parent
	end
	return nil
end

function InputController:_targetCreep(creepModel: Model)
	-- Extract creep ID from model name (format: "Creep_123")
	local creepIdStr = creepModel.Name:match("Creep_(%d+)")
	if not creepIdStr then
		return
	end
	local creepId = tonumber(creepIdStr)
	if not creepId then
		return
	end

	-- Tell server to target this creep
	local HeroCombatService = Knit.GetService("HeroCombatService")
	HeroCombatService:SetTarget(creepId)

	-- Visual highlight on the targeted creep
	self:_showTargetHighlight(creepModel)
end

function InputController:_clearTarget()
	local ok, HeroCombatService = pcall(function()
		return Knit.GetService("HeroCombatService")
	end)
	if ok and HeroCombatService then
		HeroCombatService:SetTarget(0)
	end
	self:_hideTargetHighlight()
end

function InputController:_showTargetHighlight(model: Model)
	self:_hideTargetHighlight()

	local highlight = Instance.new("Highlight")
	highlight.Name = "TargetHighlight"
	highlight.FillColor = Color3.fromRGB(255, 50, 50)
	highlight.FillTransparency = 0.7
	highlight.OutlineColor = Color3.fromRGB(255, 80, 80)
	highlight.OutlineTransparency = 0.2
	highlight.Adornee = model
	highlight.Parent = model
	self._targetHighlight = highlight
end

function InputController:_hideTargetHighlight()
	if self._targetHighlight then
		self._targetHighlight:Destroy()
		self._targetHighlight = nil
	end
end

--------------------------------------------------------------------------------
-- Shop click check (shared by contextual and left-click)
--------------------------------------------------------------------------------

function InputController:_checkShopClick(instance: Instance): boolean
	-- Walk up parent tree looking for a Shop-tagged BasePart
	local shopPart: BasePart? = nil
	local current: Instance? = instance
	while current and current ~= workspace do
		if current:IsA("BasePart") and CollectionService:HasTag(current, "Shop") then
			shopPart = current :: BasePart
			break
		end
		-- Also check siblings (roof/trim parts live next to the tagged building body)
		if current:IsA("BasePart") and current.Parent then
			for _, sibling in current.Parent:GetChildren() do
				if sibling ~= current and sibling:IsA("BasePart") and CollectionService:HasTag(sibling, "Shop") then
					-- Verify it's the same building (close proximity)
					if (sibling.Position - (current :: BasePart).Position).Magnitude < 12 then
						shopPart = sibling :: BasePart
						break
					end
				end
			end
			if shopPart then
				break
			end
		end
		current = current.Parent
	end

	if not shopPart then
		return false
	end

	-- Team check
	local shopTeamId = shopPart:GetAttribute("TeamId")
	if shopTeamId then
		local ok, TeamService = pcall(function()
			return Knit.GetService("TeamService")
		end)
		if ok and TeamService then
			local myTeam = TeamService:GetTeam()
			if myTeam and myTeam ~= shopTeamId then
				return false
			end
		end
	end

	local shopController = Knit.GetController("ShopController")
	local shopType = shopPart:GetAttribute("ShopType")

	if shopType then
		local tabMap = {
			Gear = "Items",
			Medical = "Medical",
			Familiar = "Familiar",
			Upgrades = "Upgrades",
			Creeps = "Creeps",
		}
		local targetTab = tabMap[shopType] or "Creeps"
		if not shopController._shopOpen then
			shopController:ToggleShop()
		end
		shopController:_switchTab(targetTab)
	else
		if not shopController._shopOpen then
			shopController:ToggleShop()
		end
	end
	return true
end

--------------------------------------------------------------------------------
-- Ground raycast helper
--------------------------------------------------------------------------------

function InputController:_raycastMouse(): Vector3?
	local camera = workspace.CurrentCamera
	if not camera or not self._raycastParams then
		return nil
	end

	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

	local result = workspace:Raycast(ray.Origin, ray.Direction * 500, self._raycastParams)
	if result then
		return result.Position
	end
	return nil
end

--------------------------------------------------------------------------------
-- Move indicator (green circle that fades at click target)
--------------------------------------------------------------------------------

function InputController:_createMoveIndicator()
	local part = Instance.new("Part")
	part.Name = "MoveIndicator"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.2, 3, 3) -- thin cylinder (Y and Z are diameter)
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(0, 255, 100)
	part.Transparency = 1 -- hidden initially
	part.CFrame = CFrame.new(0, -100, 0) * CFrame.Angles(0, 0, math.rad(90))
	part.Parent = workspace
	self._moveIndicator = part
end

function InputController:_showMoveIndicator(position: Vector3)
	local indicator = self._moveIndicator
	if not indicator then
		return
	end

	-- Place flat on the ground (cylinder rotated to lie flat)
	indicator.CFrame = CFrame.new(position.X, position.Y + 0.15, position.Z)
		* CFrame.Angles(0, 0, math.rad(90))
	indicator.Transparency = 0.3

	-- Fade out over 0.6s
	local tween = TweenService:Create(
		indicator,
		TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Transparency = 1 }
	)
	tween:Play()
end

--------------------------------------------------------------------------------
-- Lane lock: clamp position to team's lane
--------------------------------------------------------------------------------

function InputController:_clampToLane(pos: Vector3): Vector3
	local teamId = self._teamId
	if not teamId then
		-- Try fetching again if not yet cached
		local ok, TeamService = pcall(function()
			return Knit.GetService("TeamService")
		end)
		if ok and TeamService then
			teamId = TeamService:GetTeam()
			self._teamId = teamId
		end
	end

	if not teamId then
		return pos
	end

	-- Team 1 = left lane (X: -28 to -1), Team 2 = right lane (X: 1 to 28)
	local halfWidth = MapConfig.LANE_HALF_WIDTH
	local minX, maxX
	if teamId == 1 then
		minX = -(halfWidth - 2)
		maxX = -1
	else
		minX = 1
		maxX = halfWidth - 2
	end

	return Vector3.new(
		math.clamp(pos.X, minX, maxX),
		pos.Y,
		pos.Z
	)
end

--------------------------------------------------------------------------------
-- Ability / Shop callbacks
--------------------------------------------------------------------------------

function InputController:_onToggleShop()
	local shopController = Knit.GetController("ShopController")
	shopController:ToggleShop()
end

return InputController
