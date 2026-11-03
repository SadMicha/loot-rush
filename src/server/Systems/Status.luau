--!strict
-- Timed buffs/debuffs for the HUD buff bar (Shared/Status). Gameplay effects stay where they are
-- (Combat, Rush); this module only publishes "what is active and until when" as player attributes.
-- Every set schedules its own clean-up, so a forgotten clear never leaves a stale icon.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rules = require(ReplicatedStorage.Shared.Status)

local Status = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Active until `untilT` (server time); stacks optional. `from` = when the effect started (server
-- time, default now): an extension (Rush chain) keeps its start, a new application starts anew.
function Status.setUntil(player: Player, id: string, untilT: number, stacks: number?, from: number?)
	if not Rules.Defs[id] or untilT ~= untilT then
		return
	end
	local attr = Rules.attr(id)
	player:SetAttribute(Rules.fromAttr(id), from or now())
	player:SetAttribute(attr, untilT)
	if stacks then
		player:SetAttribute(Rules.stacksAttr(id), stacks)
	end
	task.delay(math.max(0, untilT - now()) + 0.1, function()
		if player.Parent and player:GetAttribute(attr) == untilT then
			Status.clear(player, id)
		end
	end)
end

-- Active for `seconds` from now
function Status.set(player: Player, id: string, seconds: number, stacks: number?)
	Status.setUntil(player, id, now() + math.max(0, seconds), stacks)
end

function Status.clear(player: Player, id: string)
	player:SetAttribute(Rules.attr(id), nil)
	player:SetAttribute(Rules.stacksAttr(id), nil)
	player:SetAttribute(Rules.fromAttr(id), nil)
end

return Status
