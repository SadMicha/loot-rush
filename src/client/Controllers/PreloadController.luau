--!strict
-- Preloads the HUD and window art on join (docs/ROADMAP-1.0.md O2), so the first HUD paint on a
-- phone does not pop in image by image: Assets.Hud, Assets.Slice and Assets.Fixed, plus the class
-- art (setup screen). Runs in the background; missing or failed ids are ignored (the flat style
-- covers them). The branded loading screen itself needs a ReplicatedFirst script (not mapped yet).

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage.Shared.UI.Assets)

local PreloadController = {}

-- Every distinct image id the HUD and windows use first (pure, for tests)
function PreloadController.ids(): { string }
	local seen: { [string]: boolean } = {}
	local list: { string } = {}
	local function add(id: string?)
		if id and id ~= "" and not seen[id] then
			seen[id] = true
			table.insert(list, id)
		end
	end
	for _, group in { Assets.Hud, Assets.Slice, Assets.Fixed, Assets.Class } :: { any } do
		for _, def in group do
			add(def.id)
		end
	end
	return list
end

function PreloadController.start()
	local list = PreloadController.ids()
	if #list == 0 then
		return
	end
	pcall(function()
		ContentProvider:PreloadAsync(list)
	end)
end

return PreloadController
