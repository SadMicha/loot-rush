--!strict
-- Loot Rush - server entry point.
-- Two phases: first init() of all systems, then start() of all systems.

local Systems = script:FindFirstChild("Systems")

local loaded: { [string]: any } = {}
if Systems then
	for _, child in Systems:GetChildren() do
		if child:IsA("ModuleScript") then
			loaded[child.Name] = require(child) :: any
		end
	end
end

for _, system in loaded do
	if typeof(system.init) == "function" then
		system.init()
	end
end

for _, system in loaded do
	if typeof(system.start) == "function" then
		task.spawn(system.start)
	end
end

print("[LootRush] Server started")
