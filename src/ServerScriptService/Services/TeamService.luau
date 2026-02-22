--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)

local TeamService = Knit.CreateService({
	Name = "TeamService",

	Client = {
		TeamAssigned = Knit.CreateSignal(),
	},
})

TeamService._playerTeams = {} :: { [number]: number } -- UserId -> TeamId

function TeamService:KnitInit() end

function TeamService:KnitStart()
	Players.PlayerAdded:Connect(function(player)
		self:_assignTeam(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._playerTeams[player.UserId] = nil
	end)
end

function TeamService:GetTeam(player: Player): number?
	return self._playerTeams[player.UserId]
end

function TeamService:GetTeamPlayers(teamId: number): { Player }
	local result = {}
	for _, player in Players:GetPlayers() do
		if self._playerTeams[player.UserId] == teamId then
			table.insert(result, player)
		end
	end
	return result
end

function TeamService:GetTeamCount(teamId: number): number
	local count = 0
	for _, tId in self._playerTeams do
		if tId == teamId then
			count += 1
		end
	end
	return count
end

function TeamService:_assignTeam(player: Player)
	-- Assign to the team with fewer players
	local team1Count = self:GetTeamCount(1)
	local team2Count = self:GetTeamCount(2)

	local teamId
	if team1Count <= team2Count then
		teamId = 1
	else
		teamId = 2
	end

	-- Enforce max players per team
	if self:GetTeamCount(teamId) >= Constants.MAX_PLAYERS_PER_TEAM then
		warn("[HLW] Team " .. teamId .. " is full, cannot assign " .. player.Name)
		return
	end

	self._playerTeams[player.UserId] = teamId
	self.Client.TeamAssigned:Fire(player, teamId)
end

-- Client-callable
function TeamService.Client:GetTeam(player: Player): number?
	return self.Server:GetTeam(player)
end

return TeamService
