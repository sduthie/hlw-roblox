--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local HeroData = require(ReplicatedStorage.Shared.HeroData)

local GEAR_FOLDER_NAME = "HeroGear"
local HERO_TOOL_TAG = "HeroWeapon"

local HeroAppearanceService = Knit.CreateService({
	Name = "HeroAppearanceService",
	Client = {},
})

-- Track which hero appearance is active per player so we can re-apply on respawn
HeroAppearanceService._activeHeroes = {} :: { [number]: string } -- UserId -> HeroId
HeroAppearanceService._charAddedConns = {} :: { [number]: RBXScriptConnection }

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function HeroAppearanceService:KnitInit()
	Players.PlayerRemoving:Connect(function(player)
		self:_disconnectCharAdded(player)
		self._activeHeroes[player.UserId] = nil
	end)
end

function HeroAppearanceService:KnitStart() end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function HeroAppearanceService:ApplyHeroAppearance(player: Player, heroId: string)
	local heroDef = HeroData[heroId]
	if not heroDef or not heroDef.Appearance then
		return
	end

	local userId = player.UserId
	self._activeHeroes[userId] = heroId

	-- Apply to current character if it exists
	local character = player.Character
	if character then
		self:_applyToCharacter(character, heroDef.Appearance)
	end

	-- Listen for future respawns
	self:_connectCharAdded(player)
end

function HeroAppearanceService:ClearAppearance(player: Player)
	local userId = player.UserId
	self._activeHeroes[userId] = nil
	self:_disconnectCharAdded(player)

	local character = player.Character
	if not character then
		return
	end

	self:_clearFromCharacter(character)
end

--------------------------------------------------------------------------------
-- Internal: apply / clear on a character model
--------------------------------------------------------------------------------

function HeroAppearanceService:_applyToCharacter(character: Model, appearance: any)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	-- Clear any existing appearance first
	self:_clearFromCharacter(character)

	-- 1. Apply body colors
	self:_applyBodyColors(character, appearance.BodyColors)

	-- 2. Create gear pieces
	self:_createGearPieces(character, appearance.GearPieces)

	-- 3. Create weapon tool
	if appearance.WeaponTool then
		local player = Players:GetPlayerFromCharacter(character)
		if player then
			self:_createWeaponTool(player, character, appearance.WeaponTool)
		end
	end
end

function HeroAppearanceService:_clearFromCharacter(character: Model)
	-- Remove gear folder
	local gearFolder = character:FindFirstChild(GEAR_FOLDER_NAME)
	if gearFolder then
		gearFolder:Destroy()
	end

	-- Remove hero weapon tools from backpack and character
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		local backpack = player:FindFirstChild("Backpack")
		if backpack then
			for _, child in backpack:GetChildren() do
				if child:IsA("Tool") and child:GetAttribute(HERO_TOOL_TAG) then
					child:Destroy()
				end
			end
		end
	end

	-- Remove equipped tool from character
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute(HERO_TOOL_TAG) then
			child:Destroy()
		end
	end

	-- Reset body colors
	local bodyColors = character:FindFirstChildOfClass("BodyColors")
	if bodyColors then
		bodyColors:Destroy()
	end
end

--------------------------------------------------------------------------------
-- Body Colors
--------------------------------------------------------------------------------

function HeroAppearanceService:_applyBodyColors(character: Model, colors: any)
	-- Remove existing BodyColors if present
	local existing = character:FindFirstChildOfClass("BodyColors")
	if existing then
		existing:Destroy()
	end

	local bc = Instance.new("BodyColors")
	bc.HeadColor3 = colors.HeadColor3
	bc.TorsoColor3 = colors.TorsoColor3
	bc.LeftArmColor3 = colors.LeftArmColor3
	bc.RightArmColor3 = colors.RightArmColor3
	bc.LeftLegColor3 = colors.LeftLegColor3
	bc.RightLegColor3 = colors.RightLegColor3
	bc.Parent = character
end

--------------------------------------------------------------------------------
-- Gear Pieces (welded armour / accessories)
--------------------------------------------------------------------------------

function HeroAppearanceService:_createGearPieces(character: Model, gearPieces: any)
	local gearFolder = Instance.new("Folder")
	gearFolder.Name = GEAR_FOLDER_NAME
	gearFolder.Parent = character

	for _, pieceDef in gearPieces do
		local attachTarget = self:_getAttachPart(character, pieceDef.AttachTo)
		if not attachTarget then
			continue
		end

		local part = Instance.new("Part")
		part.Name = pieceDef.Name
		part.Size = pieceDef.Size
		part.Color = pieceDef.Color
		part.Material = pieceDef.Material
		part.Transparency = pieceDef.Transparency or 0
		part.CanCollide = false
		part.Massless = true
		part.Anchored = false

		-- Set shape
		if pieceDef.PartType == "Ball" then
			part.Shape = Enum.PartType.Ball
		elseif pieceDef.PartType == "Cylinder" then
			part.Shape = Enum.PartType.Cylinder
		elseif pieceDef.PartType == "Wedge" then
			-- Replace with WedgePart
			part:Destroy()
			local wedge = Instance.new("WedgePart")
			wedge.Name = pieceDef.Name
			wedge.Size = pieceDef.Size
			wedge.Color = pieceDef.Color
			wedge.Material = pieceDef.Material
			wedge.Transparency = pieceDef.Transparency or 0
			wedge.CanCollide = false
			wedge.Massless = true
			wedge.Anchored = false

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = attachTarget
			weld.Part1 = wedge
			weld.Parent = wedge

			wedge.CFrame = attachTarget.CFrame * pieceDef.Offset
			wedge.Parent = gearFolder
			continue
		end
		-- Default is "Block" (no shape change needed)

		-- Weld to attach target
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = attachTarget
		weld.Part1 = part
		weld.Parent = part

		part.CFrame = attachTarget.CFrame * pieceDef.Offset
		part.Parent = gearFolder
	end
end

function HeroAppearanceService:_getAttachPart(character: Model, attachTo: string?): BasePart?
	if not attachTo or attachTo == "HumanoidRootPart" then
		return character:FindFirstChild("HumanoidRootPart") :: BasePart?
	end
	return character:FindFirstChild(attachTo) :: BasePart?
end

--------------------------------------------------------------------------------
-- Weapon Tool
--------------------------------------------------------------------------------

function HeroAppearanceService:_createWeaponTool(player: Player, character: Model, weaponDef: any)
	local tool = Instance.new("Tool")
	tool.Name = weaponDef.Name
	tool.CanBeDropped = false
	tool:SetAttribute(HERO_TOOL_TAG, true)

	if weaponDef.GripPos then
		tool.GripPos = weaponDef.GripPos
	end

	-- Handle (required for Tool)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = weaponDef.HandleSize
	handle.Color = weaponDef.HandleColor
	handle.Material = weaponDef.HandleMaterial
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	-- Blade (optional second part)
	if weaponDef.BladeSize then
		local blade = Instance.new("Part")
		blade.Name = "Blade"
		blade.Size = weaponDef.BladeSize
		blade.Color = weaponDef.BladeColor or Color3.new(0.8, 0.8, 0.8)
		blade.Material = weaponDef.BladeMaterial or Enum.Material.Metal
		blade.CanCollide = false
		blade.Massless = true

		local bladeWeld = Instance.new("WeldConstraint")
		bladeWeld.Part0 = handle
		bladeWeld.Part1 = blade
		bladeWeld.Parent = blade

		blade.CFrame = handle.CFrame * (weaponDef.BladeOffset or CFrame.new(0, 2, 0))
		blade.Parent = tool
	end

	-- Parent to backpack, then auto-equip
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		tool.Parent = backpack
	end

	-- Auto-equip after a short delay to let things replicate
	task.defer(function()
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and tool.Parent then
			humanoid:EquipTool(tool)
		end
	end)
end

--------------------------------------------------------------------------------
-- CharacterAdded connection (re-apply on respawn)
--------------------------------------------------------------------------------

function HeroAppearanceService:_connectCharAdded(player: Player)
	local userId = player.UserId

	-- Disconnect previous connection if any
	self:_disconnectCharAdded(player)

	self._charAddedConns[userId] = player.CharacterAdded:Connect(function(character)
		-- Wait for humanoid to be ready
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid then
			return
		end

		local heroId = self._activeHeroes[userId]
		if not heroId then
			return
		end

		local heroDef = HeroData[heroId]
		if not heroDef or not heroDef.Appearance then
			return
		end

		-- Small delay so character parts are fully loaded
		task.wait(0.2)
		self:_applyToCharacter(character, heroDef.Appearance)
	end)
end

function HeroAppearanceService:_disconnectCharAdded(player: Player)
	local userId = player.UserId
	local conn = self._charAddedConns[userId]
	if conn then
		conn:Disconnect()
		self._charAddedConns[userId] = nil
	end
end

return HeroAppearanceService
