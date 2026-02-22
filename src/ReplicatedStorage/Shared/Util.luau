--!strict

local Util = {}

function Util.shallowCopy(t: { [any]: any }): { [any]: any }
	return table.clone(t)
end

function Util.formatGold(amount: number): string
	if amount >= 1000 then
		return string.format("%.1fk", amount / 1000)
	end
	return tostring(amount)
end

function Util.formatTime(seconds: number): string
	local mins = math.floor(seconds / 60)
	local secs = math.floor(seconds % 60)
	return string.format("%d:%02d", mins, secs)
end

function Util.clamp(value: number, min: number, max: number): number
	return math.max(min, math.min(max, value))
end

function Util.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

return Util
