--!strict
-- One server-wide signal for player actions other systems count (quests, analytics):
--   Actions.fire(player, "equip")         -- amount 1
--   Actions.fire(player, "salvage", 3)
--   Actions.Event.Event:Connect(function(player, kind, amount) ... end)
-- Kinds: see Shared/Quests (count goals). Firing systems need no reference to the listeners,
-- so there are no require cycles.

local Actions = {
	Event = Instance.new("BindableEvent"),
}

function Actions.fire(player: Player, kind: string, amount: number?)
	Actions.Event:Fire(player, kind, amount or 1)
end

return Actions
