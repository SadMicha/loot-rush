--!strict
-- Preloads every asset of the game behind the loading screen (docs/ROADMAP.md O2): images (HUD,
-- windows, icons, textures) first, then sounds, then animations (list: Shared/Preload).
-- Batches go through ContentProvider:PreloadAsync with a per-batch timeout; failed ids are logged
-- once and never stop the join; the whole preload is capped at TOTAL_CAP seconds.
-- Progress is published as player attributes for the loading screen (ReplicatedFirst/LootRushLoading):
--   PreloadTotal / PreloadDone   asset counts (real progress)
--   PreloadPhase                 "assets" while loading, "world" while waiting for the character
--                                and the hero setup state, then "ready"
--   ClientReady = true           preload finished AND character ready AND SetupDone known
--                                (or the waits ran out): the loading screen fades out

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Preload = require(ReplicatedStorage.Shared.Preload)
local Headshot = require(script.Parent.Parent.UI.Headshot)

local BATCH_TIMEOUT = 6 -- seconds one batch may take before we move on
local TOTAL_CAP = 25 -- seconds for the whole asset preload
local WORLD_WAIT = 12 -- seconds to wait for the character and the setup state after the assets

local player = Players.LocalPlayer

local PreloadController = {}

-- Every distinct asset id (pure list, for tests)
function PreloadController.ids(): { string }
	local list: { string } = {}
	for _, entry in Preload.collect() do
		table.insert(list, entry.id)
	end
	return list
end

local function setProgress(done: number)
	player:SetAttribute("PreloadDone", done)
end

-- Preloads one batch; returns when it finished or timed out. Failed ids are added to `failed`.
local function loadBatch(
	batch: { Preload.Entry },
	deadline: number,
	failed: { string },
	onAsset: () -> ()
)
	local objects: { any } = {}
	local temp: { Instance } = {}
	for _, entry in batch do
		if entry.kind == "image" then
			table.insert(objects, entry.id)
		elseif entry.kind == "sound" then
			local snd = Instance.new("Sound")
			snd.SoundId = entry.id
			table.insert(objects, snd)
			table.insert(temp, snd)
		else
			local anim = Instance.new("Animation")
			anim.AnimationId = entry.id
			table.insert(objects, anim)
			table.insert(temp, anim)
		end
	end
	local finished = false
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(
				objects,
				function(id: string, status: Enum.AssetFetchStatus)
					if
						status ~= Enum.AssetFetchStatus.Success
						and status ~= Enum.AssetFetchStatus.None
					then
						table.insert(failed, id)
					end
					onAsset()
				end
			)
		end)
		finished = true
	end)
	local limit = math.min(os.clock() + BATCH_TIMEOUT, deadline)
	while not finished and os.clock() < limit do
		task.wait(0.05)
	end
	if not finished then
		table.insert(failed, `(batch of {#batch} timed out)`)
	end
	for _, inst in temp do
		inst:Destroy()
	end
end

local function run()
	local entries = Preload.collect()
	-- Own profile photo (nameplate / headshot UI): a thumbnail url, not a registered id
	local url = Headshot.url(player.UserId)
	local total = #entries
	player:SetAttribute("PreloadTotal", total + (if url then 1 else 0))
	player:SetAttribute("PreloadDone", 0)
	player:SetAttribute("PreloadPhase", "assets")

	local done = 0
	local failed: { string } = {}
	local started = os.clock()
	local deadline = started + TOTAL_CAP
	local batches = Preload.batches(entries)
	for _, batch in batches do
		if os.clock() >= deadline then
			break
		end
		local before = done
		loadBatch(batch, deadline, failed, function()
			done = math.min(before + #batch, done + 1)
			setProgress(done)
		end)
		done = before + #batch -- a batch that timed out or skipped callbacks still counts as passed
		setProgress(done)
	end
	if url and os.clock() < deadline then
		pcall(function()
			ContentProvider:PreloadAsync({ url })
		end)
	end
	done = total + (if url then 1 else 0)
	setProgress(done)
	if #failed > 0 then
		warn(`[Preload] {#failed} of {total} assets did not load: {table.concat(failed, ", ")}`)
	end

	-- The loading screen stays until the character and the hero setup state are known too
	player:SetAttribute("PreloadPhase", "world")
	local waitUntil = os.clock() + WORLD_WAIT
	while os.clock() < waitUntil do
		local character = player.Character
		local hasCharacter = character ~= nil
			and character:FindFirstChild("HumanoidRootPart") ~= nil
		if hasCharacter and player:GetAttribute("SetupDone") ~= nil then
			break
		end
		task.wait(0.1)
	end
	player:SetAttribute("PreloadPhase", "ready")
	-- The loading screen (ReplicatedFirst/LootRushLoading) fades out on this
	player:SetAttribute("ClientReady", true)
end

function PreloadController.start()
	run()
end

return PreloadController
