--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Knit = require(ReplicatedStorage.Packages.Knit)

-- Create an immediate floor so characters never fall through the void
-- (MapService builds the real map during KnitInit, but character may auto-load first)
local tempFloor = Instance.new("Part")
tempFloor.Name = "TempFloor"
tempFloor.Size = Vector3.new(400, 8, 320)
tempFloor.Position = Vector3.new(0, -4, 0)
tempFloor.Anchored = true
tempFloor.CanCollide = true
tempFloor.Transparency = 1
tempFloor.TopSurface = Enum.SurfaceType.Smooth
tempFloor.BottomSurface = Enum.SurfaceType.Smooth
tempFloor.Parent = workspace

-- Load all services
for _, module in ServerScriptService.Services:GetChildren() do
	if module:IsA("ModuleScript") then
		require(module)
	end
end

Knit.Start()
	:andThen(function()
		print("[HLW] Server started successfully")
	end)
	:catch(function(err)
		warn("[HLW] Server start failed:", err)
	end)
