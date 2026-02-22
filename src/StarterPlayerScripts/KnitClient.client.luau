--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayerScripts = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")

local Knit = require(ReplicatedStorage.Packages.Knit)

-- Load all controllers
for _, module in StarterPlayerScripts.Controllers:GetChildren() do
	if module:IsA("ModuleScript") then
		require(module)
	end
end

Knit.Start()
	:andThen(function()
		print("[HLW] Client started successfully")
	end)
	:catch(function(err)
		warn("[HLW] Client start failed:", err)
	end)
