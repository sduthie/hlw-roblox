--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local Knit = require(ReplicatedStorage.Packages.Knit)

local InputController = Knit.CreateController({
	Name = "InputController",
})

-- Default keybinds
InputController._keybinds = {
	Ability1 = Enum.KeyCode.Q,
	Ability2 = Enum.KeyCode.W,
	Ability3 = Enum.KeyCode.E,
	Ability4 = Enum.KeyCode.R,
	ToggleShop = Enum.KeyCode.B,
	CenterCamera = Enum.KeyCode.Space,
}

function InputController:KnitInit() end

function InputController:KnitStart()
	self:_bindActions()
end

function InputController:_bindActions()
	ContextActionService:BindAction("Ability1", function(_, state)
		if state == Enum.UserInputState.Begin then
			self:_onAbility(1)
		end
	end, false, self._keybinds.Ability1)

	ContextActionService:BindAction("Ability2", function(_, state)
		if state == Enum.UserInputState.Begin then
			self:_onAbility(2)
		end
	end, false, self._keybinds.Ability2)

	ContextActionService:BindAction("Ability3", function(_, state)
		if state == Enum.UserInputState.Begin then
			self:_onAbility(3)
		end
	end, false, self._keybinds.Ability3)

	ContextActionService:BindAction("Ability4", function(_, state)
		if state == Enum.UserInputState.Begin then
			self:_onAbility(4)
		end
	end, false, self._keybinds.Ability4)

	ContextActionService:BindAction("ToggleShop", function(_, state)
		if state == Enum.UserInputState.Begin then
			self:_onToggleShop()
		end
	end, false, self._keybinds.ToggleShop)
end

function InputController:_onAbility(slotIndex: number)
	-- TODO: route to HeroController to activate ability
	print("[HLW] Ability", slotIndex, "pressed")
end

function InputController:_onToggleShop()
	local shopController = Knit.GetController("ShopController")
	shopController:ToggleShop()
end

return InputController
