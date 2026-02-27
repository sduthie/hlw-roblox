--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local MapConfig = require(ReplicatedStorage.Shared.MapConfig)

local TeamService = Knit.CreateService({
	Name = "TeamService",

	Client = {
		TeamAssigned = Knit.CreateSignal(),
	},
})

TeamService._playerTeams = {} :: { [number]: number } -- UserId -> TeamId
TeamService._playerSpawnIndex = {} :: { [number]: number } -- UserId -> spawn slot (1-5)

function TeamService:KnitInit() end

function TeamService:KnitStart()
	-- Handle players already in the game (joined before Knit started)
	for _, player in Players:GetPlayers() do
		self:_setupPlayer(player)
	end

	Players.PlayerAdded:Connect(function(player)
		self:_setupPlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._playerTeams[player.UserId] = nil
		self._playerSpawnIndex[player.UserId] = nil
	end)
end

function TeamService:_setupPlayer(player: Player)
	if not self._playerTeams[player.UserId] then
		self:_assignTeam(player)
	end

	-- Teleport to lane spawn on each respawn
	player.CharacterAdded:Connect(function(character)
		self:_teleportToLane(player, character)
	end)
	-- Also teleport if character already exists
	if player.Character then
		self:_teleportToLane(player, player.Character)
	end
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

	-- Assign a spawn slot (1-5) based on order of joining that team
	local teamCount = self:GetTeamCount(teamId)
	self._playerSpawnIndex[player.UserId] = math.clamp(teamCount, 1, 5)

	self.Client.TeamAssigned:Fire(player, teamId)
end

function TeamService:_teleportToLane(player: Player, character: Model)
	local teamId = self._playerTeams[player.UserId]
	if not teamId then
		return
	end

	-- Pick from the 5 spawn points, falling back to center if no index
	local spawnIndex = self._playerSpawnIndex[player.UserId] or 1
	local spawnPoints = MapConfig.HERO_SPAWN_POINTS[teamId]
	local spawnPos = if spawnPoints then spawnPoints[spawnIndex] else MapConfig.HERO_POSITIONS[teamId]
	if not spawnPos then
		return
	end

	-- Wait for root part to exist, then teleport with a small delay
	-- to override Roblox's default spawn positioning
	task.spawn(function()
		local rootPart = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
		if not rootPart then
			return
		end
		-- Small yield to let default spawn finish, then override
		task.wait(0.1)
		rootPart.CFrame = CFrame.new(spawnPos + Vector3.new(0, 3, 0))
	end)
end

-- Client-callable
function TeamService.Client:GetTeam(player: Player): number?
	return self.Server:GetTeam(player)
end

return TeamService
