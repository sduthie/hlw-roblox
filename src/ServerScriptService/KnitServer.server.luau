--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Knit = require(ReplicatedStorage.Packages.Knit)

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
