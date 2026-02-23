--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)

local GamePhases = {}

export type PhaseConfig = {
	Duration: number,
	NextPhase: string,
	AutoTransition: boolean,
	MinPlayers: number,
}

GamePhases.Configs = {
	[Constants.PHASE_LOBBY] = {
		Duration = 0, -- no fixed duration; waits for players + countdown
		NextPhase = Constants.PHASE_HERO_SELECT,
		AutoTransition = false,
		MinPlayers = 1,
	},
	[Constants.PHASE_HERO_SELECT] = {
		Duration = Constants.HERO_PICK_TIME, -- 30s
		NextPhase = Constants.PHASE_PLAYING,
		AutoTransition = true,
		MinPlayers = 1,
	},
	[Constants.PHASE_PLAYING] = {
		Duration = 0, -- no fixed duration; ends when a team hits 0 lives
		NextPhase = Constants.PHASE_GAME_OVER,
		AutoTransition = false,
		MinPlayers = 0,
	},
	[Constants.PHASE_GAME_OVER] = {
		Duration = Constants.GAME_OVER_DISPLAY_TIME, -- 10s
		NextPhase = Constants.PHASE_LOBBY,
		AutoTransition = true,
		MinPlayers = 0,
	},
}

local _validTransitions: { [string]: { [string]: boolean } } = {
	[Constants.PHASE_LOBBY] = { [Constants.PHASE_HERO_SELECT] = true },
	[Constants.PHASE_HERO_SELECT] = { [Constants.PHASE_PLAYING] = true },
	[Constants.PHASE_PLAYING] = { [Constants.PHASE_GAME_OVER] = true },
	[Constants.PHASE_GAME_OVER] = { [Constants.PHASE_LOBBY] = true },
}

function GamePhases.canTransition(from: string, to: string): boolean
	local fromTransitions = _validTransitions[from]
	if not fromTransitions then
		return false
	end
	return fromTransitions[to] == true
end

function GamePhases.getConfig(phase: string): PhaseConfig?
	return GamePhases.Configs[phase]
end

return GamePhases
