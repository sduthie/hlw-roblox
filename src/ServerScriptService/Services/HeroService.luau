--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local HeroData = require(ReplicatedStorage.Shared.HeroData)

local HeroService = Knit.CreateService({
	Name = "HeroService",

	Client = {
		HeroSelected = Knit.CreateSignal(),
		HeroLevelUp = Knit.CreateSignal(),
	},
})

HeroService._playerHeroes = {} :: { [number]: string } -- UserId -> HeroId
HeroService._playerLevels = {} :: { [number]: number }
HeroService._playerXP = {} :: { [number]: number }

function HeroService:KnitInit() end

function HeroService:KnitStart() end

function HeroService:SelectHero(player: Player, heroId: string): boolean
	if not HeroData[heroId] then
		return false
	end

	local gameService = Knit.GetService("GameService")
	if gameService:GetPhase() ~= Constants.PHASE_HERO_SELECT then
		return false
	end

	self._playerHeroes[player.UserId] = heroId
	self._playerLevels[player.UserId] = 1
	self._playerXP[player.UserId] = 0
	self.Client.HeroSelected:FireAll(player.UserId, heroId)
	return true
end

function HeroService:AddXP(player: Player, amount: number)
	local userId = player.UserId
	local currentXP = (self._playerXP[userId] or 0) + amount
	local currentLevel = self._playerLevels[userId] or 1

	while currentLevel < Constants.HERO_MAX_LEVEL do
		local xpNeeded = Constants.HERO_XP_PER_LEVEL[currentLevel]
		if not xpNeeded or currentXP < xpNeeded then
			break
		end
		currentXP -= xpNeeded
		currentLevel += 1
		self.Client.HeroLevelUp:Fire(player, currentLevel)
	end

	self._playerXP[userId] = currentXP
	self._playerLevels[userId] = currentLevel
end

function HeroService:GetHeroId(player: Player): string?
	return self._playerHeroes[player.UserId]
end

function HeroService:GetLevel(player: Player): number
	return self._playerLevels[player.UserId] or 1
end

-- Client-callable
function HeroService.Client:SelectHero(player: Player, heroId: string): boolean
	return self.Server:SelectHero(player, heroId)
end

function HeroService.Client:GetHeroId(player: Player): string?
	return self.Server:GetHeroId(player)
end

function HeroService.Client:GetLevel(player: Player): number
	return self.Server:GetLevel(player)
end

return HeroService
