--!strict
-- The Great Build (Shared/GreatBuild, docs/specs/SEASONS.md §7): every server raises the same
-- monument. Players donate Crystal Shards at the donation chute in the hub.
--  • Donation (Net.GreatBuild "donate", amount): checked here only. The hero must stand at the
--    chute (hub, no Rift), the amount is a whole number, clamped to the shards the hero owns and
--    the account's daily cap. Shards leave the save and the account credit is booked in the same
--    step (no yield in between), so nothing can be donated twice.
--  • Batches: the server sums donations in memory and adds them to the DataStore record every
--    GreatBuild.FLUSH seconds with one UpdateAsync carrying (serverId, seq). A batch that is not
--    confirmed is retried with the same seq (Rules.apply ignores a seq it has seen), new
--    donations wait in `buffer` meanwhile. BindToClose flushes once more.
--  • Reads: without donations of its own a server reads the record every FLUSH seconds; a
--    finished stage is also published over MessagingService so other servers build it at once.
--  • Every finished stage: the monument layer turns into real bricks on all servers and everyone
--    gets the global buff (Boosts source "greatBuild" + HUD Status "build") for BUFF_SECONDS,
--    time based (`done` times in the record), so late joiners and new servers get it too.
--  • Top donors: OrderedDataStore GreatBuild.DONOR_STORE (key UserId, account total), written at
--    most every DONOR_WRITE seconds per server; heroes touched by a test command are left out.
--  • No DataStore access (Studio without API access): runs on a local record so the monument,
--    stages and the buff can still be tested; nothing is shared then.
-- Clients read ReplicatedStorage attributes GreatBuildTotal / GreatBuildStages and ask for their
-- own state with "sync" (Net.GreatBuildState).

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Models = require(ReplicatedStorage.Shared.Models)
local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.GreatBuild)
local Actions = require(script.Parent.Parent.Util.Actions)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local Boosts = require(script.Parent.Boosts)
local Data = require(script.Parent.Data)
local Journey = require(script.Parent.Journey)
local Leaderboard = require(script.Parent.Leaderboard)
local Progress = require(script.Parent.Progress)
local Status = require(script.Parent.Status)

local GreatBuild = {
	clock = os.time, -- tests swap the clock
}

local Text = table.freeze({
	far = "Walk up to the donation chute to donate.",
	setup = "Set up your hero first.",
	empty = "You have no Crystal Shards. Salvage items to get some.",
	cap = "Daily limit reached. Come back tomorrow!",
})

local RAISE_STEP = 0.18 -- seconds between bricks of the build animation
local CLOSE_TRIES = 3

type Donor = { userId: number, name: string, amount: number }

local allow = RateLimit.new(1, 4) -- donate / sync requests
local serverId = HttpService:GenerateGUID(false)
local view: Rules.Public = { total = 0, done = {} } -- last confirmed global record
local localRecord: Rules.Record = Rules.freshRecord() -- used while there is no DataStore access
local localMode = false
local loaded = false
local buffer = 0 -- donated, not in a batch yet
local batch: { seq: number, amount: number }? = nil -- sent, not confirmed yet
local seq = 0
local built = 0 -- stages shown on the monument
local buffFrom, buffUntil = 0, 0 -- os.time window of the active global buff (0 = none)
local donors: { [number]: number } = {} -- UserId → account total waiting for the donor board
local seen: { [number]: Donor } = {} -- donors of this server session (fallback for the top list)
local top: { Donor } = {}
local lastDonorWrite = -math.huge
local lastTopRead = -math.huge
local store: DataStore? = nil
local donorStore: OrderedDataStore? = nil
local station: BasePart? = nil

local function noAccess(err: any): boolean
	local s = tostring(err)
	return string.find(s, "403", 1, true) ~= nil
		or string.find(s, "StudioAccessToApisNotAllowed", 1, true) ~= nil
end

local function getStore(): DataStore?
	if store then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Rules.STORE)
	end)
	if ok and result then
		store = result
	elseif not ok and noAccess(result) then
		localMode = true
	end
	return store
end

local function getDonorStore(): OrderedDataStore?
	if donorStore then
		return donorStore
	end
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(Rules.DONOR_STORE)
	end)
	if ok and result then
		donorStore = result
	end
	return donorStore
end

-- Total shown to players: confirmed + what this server has not confirmed yet
function GreatBuild.total(): number
	return view.total + buffer + (if batch then batch.amount else 0)
end

function GreatBuild.stages(): number
	return (Rules.stage(view.total))
end

local function publishAttrs()
	ReplicatedStorage:SetAttribute("GreatBuildTotal", GreatBuild.total())
	ReplicatedStorage:SetAttribute("GreatBuildStages", GreatBuild.stages())
end

-- ------------------------------------------------------------------ Monument
local function monument(): Model?
	local hub = workspace:FindFirstChild("Lumenhaven")
	local m = hub and hub:FindFirstChild(Rules.MODEL)
	return if m and m:IsA("Model") then m else nil
end

local function buildBrick(p: BasePart)
	local color = p:GetAttribute("BuiltColor")
	local material = p:GetAttribute("BuiltMaterial")
	p.Transparency = 0
	p.CastShadow = true
	p.Color = if typeof(color) == "Color3" then color else p.Color
	p.Material = if material == "Neon" then Enum.Material.Neon else Enum.Material.Plastic
	Models.Studs.apply(p)
end

-- Turns the layers from+1 … to into real bricks (one by one when animated)
local function raise(from: number, to: number, animate: boolean)
	local m = monument()
	if not m then
		return
	end
	local bricks: { BasePart } = {}
	for _, d in m:GetDescendants() do
		local stage = d:GetAttribute("Stage")
		if d:IsA("BasePart") and typeof(stage) == "number" and stage > from and stage <= to then
			table.insert(bricks, d)
		end
	end
	table.sort(bricks, function(a: BasePart, b: BasePart): boolean
		local sa, sb = a:GetAttribute("Stage") :: number, b:GetAttribute("Stage") :: number
		if sa ~= sb then
			return sa < sb
		end
		return (a:GetAttribute("Brick") :: number? or 0) < (b:GetAttribute("Brick") :: number? or 0)
	end)
	for _, p in bricks do
		buildBrick(p)
		if animate then
			task.wait(RAISE_STEP)
		end
	end
	m:SetAttribute("Stages", to)
end

-- ------------------------------------------------------------------ Global buff
local function applyBuff(player: Player)
	if not Data.get(player) then
		return
	end
	Boosts.refresh(player)
	local now = GreatBuild.clock()
	if buffUntil > now then
		local server = workspace:GetServerTimeNow()
		Status.setUntil(player, "build", server + (buffUntil - now), nil, server - (now - buffFrom))
	else
		Status.clear(player, "build")
	end
end

local function refreshBuff()
	local now = GreatBuild.clock()
	local from, untilT = Rules.buffWindow(view.done)
	local active = Rules.buffActive(view.done, now)
	local newFrom, newUntil = if active then from else 0, if active then untilT else 0
	if newUntil == buffUntil and newFrom == buffFrom then
		return
	end
	buffFrom, buffUntil = newFrom, newUntil
	for _, player in Players:GetPlayers() do
		task.spawn(applyBuff, player)
	end
	if active then
		task.delay(math.max(1, untilT - now + 1), refreshBuff)
	end
end

function GreatBuild.buffActive(): boolean
	return buffUntil > GreatBuild.clock()
end

-- ------------------------------------------------------------------ Record
-- Takes a newer copy of the record (DataStore result, read or message); older copies are ignored
local function adopt(rec: Rules.Public)
	if rec.total < view.total then
		return
	end
	local done = table.clone(view.done)
	for k, t in rec.done do
		done[k] = done[k] or t
	end
	view = { total = rec.total, done = done }
	local first = not loaded
	loaded = true
	local stages = GreatBuild.stages()
	if stages > built then
		local from = built
		built = stages
		task.spawn(raise, from, stages, not first)
	end
	publishAttrs()
	refreshBuff()
end

local function announce(rec: Rules.Public)
	task.spawn(function()
		pcall(function()
			MessagingService:PublishAsync(Rules.TOPIC, rec)
		end)
	end)
end

-- Sends the open batch once; true = confirmed
local function commit(): boolean
	local b = batch
	if not b then
		return true
	end
	local now = GreatBuild.clock()
	if localMode or not getStore() then
		if not localMode then
			return false -- the store could not be opened: retry on the next tick
		end
		localRecord = Rules.apply(localRecord, serverId, b.seq, b.amount, now)
		if batch == b then
			batch = nil
		end
		adopt(Rules.public(localRecord))
		return true
	end
	local finished: { number } = {}
	local ok, result = pcall(function()
		return (store :: DataStore):UpdateAsync(Rules.ID, function(old: any): any
			local rec, fin = Rules.apply(old, serverId, b.seq, b.amount, now)
			finished = fin
			return rec
		end)
	end)
	if ok then
		if batch == b then
			batch = nil
		end
		local rec = Rules.public(Rules.reconcileRecord(result))
		adopt(rec)
		if #finished > 0 then
			announce(rec)
		end
		return true
	end
	if noAccess(result) then
		localMode = true
		return commit()
	end
	warn(`[GreatBuild] batch {b.seq} not confirmed, retrying: {result}`)
	return false
end

local function read()
	if localMode then
		adopt(Rules.public(localRecord))
		return
	end
	local st = getStore()
	if not st then
		return
	end
	local ok, result = pcall(function()
		return st:GetAsync(Rules.ID)
	end)
	if ok then
		adopt(Rules.public(Rules.reconcileRecord(result)))
	elseif noAccess(result) then
		localMode = true
		adopt(Rules.public(localRecord))
	end
end

local function tick(): boolean
	if not batch and buffer > 0 then
		seq += 1
		batch = { seq = seq, amount = buffer }
		buffer = 0
	end
	if batch then
		local ok = commit()
		publishAttrs()
		return ok
	end
	read()
	return true
end

-- One tick: send the open batch (or start one), otherwise read. Ticks never overlap (the loop,
-- BindToClose and the test command can call it at once): a second caller waits its turn.
local busy = false
function GreatBuild.flush(): boolean
	local deadline = os.clock() + 15
	while busy and os.clock() < deadline do
		task.wait(0.1)
	end
	if busy then
		return false
	end
	busy = true
	local ok, result = pcall(tick)
	busy = false
	if not ok then
		warn(`[GreatBuild] flush failed: {result}`)
		return false
	end
	return result
end

-- ------------------------------------------------------------------ Donors
local function writeDonors()
	if next(donors) == nil or os.clock() - lastDonorWrite < Rules.DONOR_WRITE then
		return
	end
	lastDonorWrite = os.clock()
	local list = donors
	donors = {}
	local st = if localMode then nil else getDonorStore()
	if not st then
		return
	end
	for userId, amount in list do
		local ok, err = pcall(function()
			st:UpdateAsync(tostring(userId), function(old: any): any
				if typeof(old) == "number" and old >= amount then
					return nil
				end
				return amount
			end)
		end)
		if not ok then
			warn(`[GreatBuild] donor write failed: {err}`)
			if (donors[userId] or 0) < amount then
				donors[userId] = amount -- next round
			end
		end
	end
end

-- Top donors: the board, merged with this server's own donors (fresher, and all there is offline)
local function readTop()
	if os.clock() - lastTopRead < Rules.DONOR_READ then
		return
	end
	lastTopRead = os.clock()
	local byId: { [number]: Donor } = {}
	local st = if localMode then nil else getDonorStore()
	if st then
		local ok, rows = pcall(function()
			return st:GetSortedAsync(false, Rules.TOP):GetCurrentPage()
		end)
		if ok and typeof(rows) == "table" then
			local ids = {}
			for _, row in rows :: { any } do
				local id = tonumber(row.key)
				if id and typeof(row.value) == "number" then
					byId[id] = { userId = id, name = "", amount = math.floor(row.value) }
					table.insert(ids, id)
				end
			end
			local names = Leaderboard.names(ids)
			for id, d in byId do
				d.name = names[id] or `Player {id}`
			end
		end
	end
	for id, d in seen do
		local known = byId[id]
		if not known or known.amount < d.amount then
			byId[id] = table.clone(d)
		end
	end
	local list: { Donor } = {}
	for _, d in byId do
		table.insert(list, d)
	end
	table.sort(list, function(a: Donor, b: Donor): boolean
		if a.amount ~= b.amount then
			return a.amount > b.amount
		end
		return a.userId < b.userId
	end)
	while #list > Rules.TOP do
		table.remove(list)
	end
	top = list
end

-- ------------------------------------------------------------------ Players
local function stationPart(): BasePart?
	if station and station.Parent ~= nil then
		return station
	end
	local hub = workspace:FindFirstChild("Lumenhaven")
	local part = hub and hub:FindFirstChild(Rules.STATION, true)
	station = if part and part:IsA("BasePart") then part else nil
	return station
end

-- Standing at the donation chute: in the hub (no Rift) and within Rules.RANGE of the station
function GreatBuild.near(player: Player): boolean
	if player:GetAttribute("RiftRegion") ~= nil then
		return false
	end
	local part = stationPart()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not part or not root or not root:IsA("BasePart") then
		return false
	end
	return (root.Position - part.Position).Magnitude <= Rules.RANGE
end

function GreatBuild.state(player: Player): { [string]: any }?
	local account = Data.account(player)
	local profile = Data.get(player)
	if not account or not profile then
		return nil
	end
	local now = GreatBuild.clock()
	local mine = account.greatBuild
	local list = {}
	for i, d in top do
		list[i] = { name = d.name, amount = d.amount, me = d.userId == player.UserId }
	end
	return {
		total = GreatBuild.total(),
		stages = GreatBuild.stages(),
		buffLeft = math.max(0, buffUntil - now),
		mine = {
			total = mine.total,
			today = if Rules.dailyLeft(mine, now) == Rules.DAILY_CAP then 0 else mine.today,
			left = Rules.dailyLeft(mine, now),
			paid = table.clone(mine.paid),
		},
		shards = profile.materials.shards,
		top = list,
		shared = loaded and not localMode, -- false: offline (Studio) or not read yet
	}
end

local function send(player: Player, extra: { [string]: any }?)
	local state = GreatBuild.state(player)
	if not state then
		return
	end
	if extra then
		for k, v in extra do
			state[k] = v
		end
	end
	Net.GreatBuildState:FireClient(player, state)
end
GreatBuild.sync = send

-- Books a donation; returns the shards taken (0 = none), why not, and the milestone amounts
-- it reached (paid)
function GreatBuild.donate(player: Player, want: number): (number, string?, { number })
	local account = Data.account(player)
	local profile = Data.get(player)
	if not account or not profile then
		return 0, nil, {}
	end
	if not profile.setupDone then
		return 0, Text.setup, {}
	end
	if not GreatBuild.near(player) then
		return 0, Text.far, {}
	end
	local now = GreatBuild.clock()
	local have = profile.materials.shards
	local n = Rules.donate(account.greatBuild, want, have, now)
	if n <= 0 then
		return 0, if Rules.dailyLeft(account.greatBuild, now) <= 0 then Text.cap else Text.empty, {}
	end
	-- same step as the booking above: the shards are gone before anything can yield
	Progress.addMaterials(player, { shards = -n })
	buffer += n
	local total = account.greatBuild.total
	if not profile.debugged then
		donors[player.UserId] = total
		seen[player.UserId] = { userId = player.UserId, name = player.DisplayName, amount = total }
	end
	local paid = {}
	for _, m in Rules.collect(account.greatBuild) do -- marked paid before granting: never twice
		Journey.grant(player, m.reward)
		table.insert(paid, m.amount)
	end
	Progress.sync(player)
	publishAttrs()
	Actions.fire(player, "donate", n)
	return n, nil, paid
end

-- Test command (Systems/Debug "buildstage"): adds what the current stage still needs (not from a
-- player) and flushes at once
function GreatBuild.finishStage()
	local stage, into, size = Rules.stage(GreatBuild.total())
	if stage >= Rules.STAGES then
		return
	end
	buffer += size - into
	GreatBuild.flush()
end

local function onRequest(player: Player, action: any, amount: any)
	if not allow(player) then
		return
	end
	if action == "sync" then
		send(player)
	elseif action == "donate" then
		if
			typeof(amount) ~= "number"
			or amount ~= amount
			or amount % 1 ~= 0
			or amount < 1
			or amount > Rules.DAILY_CAP
		then
			return
		end
		local n, text, paid = GreatBuild.donate(player, amount)
		send(player, { donated = n, text = text, paid = paid })
	end
end

local function onPlayer(player: Player)
	if Data.waitFor(player) and player.Parent then
		applyBuff(player)
	end
end

function GreatBuild.init()
	Net.GreatBuild.OnServerEvent:Connect(onRequest)
	Boosts.source("greatBuild", function(): Boosts.Bonus
		if buffUntil > GreatBuild.clock() then
			return { gold = Rules.BUFF_GOLD, items = Rules.BUFF_ITEMS }
		end
		return {}
	end)
end

function GreatBuild.start()
	publishAttrs()
	task.spawn(function()
		pcall(function()
			MessagingService:SubscribeAsync(Rules.TOPIC, function(msg: any)
				if typeof(msg) == "table" then
					local rec = Rules.reconcileRecord(msg.Data)
					adopt(Rules.public(rec))
				end
			end)
		end)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(onPlayer, player)
	end)
	game:BindToClose(function()
		for _ = 1, CLOSE_TRIES do
			if not batch and buffer <= 0 then
				break
			end
			GreatBuild.flush()
		end
	end)
	task.spawn(function()
		while true do
			GreatBuild.flush()
			writeDonors()
			readTop()
			refreshBuff()
			task.wait(Rules.FLUSH)
		end
	end)
end

return GreatBuild
