--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local HeroData = require(ReplicatedStorage.Shared.HeroData)

local HeroController = Knit.CreateController({
	Name = "HeroController",
})

HeroController._selectedHeroId = nil :: string?

function HeroController:KnitInit() end

function HeroController:KnitStart()
	local heroService = Knit.GetService("HeroService")

	heroService.HeroSelected:Connect(function(userId: number, heroId: string)
		self:_onHeroSelected(userId, heroId)
	end)

	heroService.HeroLevelUp:Connect(function(level: number)
		self:_onHeroLevelUp(level)
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

function HeroController:_onHeroSelected(userId: number, heroId: string)
	local Players = game:GetService("Players")
	local localPlayer = Players.LocalPlayer
	if localPlayer and localPlayer.UserId == userId then
		self._selectedHeroId = heroId
	end
	-- TODO: update hero selection UI
end

function HeroController:_onHeroLevelUp(level: number)
	-- TODO: show level up effect / notification
	print("[HLW] Hero leveled up to", level)
end

return HeroController
