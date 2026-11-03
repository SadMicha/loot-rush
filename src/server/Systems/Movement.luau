--!strict
-- Server-side movement sanity check (anti speed hack / client teleport). The character's root is
-- owned by the client, so the server samples its position every Config.MOVE_SAMPLE seconds and
-- compares the flat distance with what the server allows:
--   humanoid.WalkSpeed (set by the server) × MOVE_SLACK × dt + MOVE_GRACE
-- plus a burst bank (MOVE_BURST studs) for dashes that refills like the dash charges.
-- A sample beyond that makes the track suspect; if the next sample still is (and no server
-- teleport happened in between) it is a strike: the character is pulled back to its last good
-- position. Strikes are counted per session; Rift runs with a strike never reach a leaderboard.
-- Server teleports never count: a CFrame set by a server script fires the root's CFrame changed
-- signal (client physics replication does not), and Movement.teleported marks one explicitly.
-- Respawns reset the baseline by themselves (new root part).
-- Vertical movement is not checked: no jumping in this game and FallGuard handles falls.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

export type Track = {
	last: Vector3, -- last accepted position
	at: number, -- time of `last`
	bank: number, -- burst studs left
	skip: boolean, -- next sample only re-bases (after a server teleport)
	suspect: boolean, -- the last sample was too far: one more and it is a strike
}

type Live = Track & {
	root: BasePart,
	moved: RBXScriptConnection,
}

local Movement = {
	Struck = Instance.new("BindableEvent"), -- (player) after a pull-back (Leaderboard drops the run)
}

local tracks: { [Player]: Live } = {}
local strikes: { [Player]: number } = {}
local pulling: { [Player]: boolean } = {} -- our own pull-back is running (not a server teleport)

local REFILL = Config.MOVE_BURST / (Config.DASH_RECHARGE * Config.DASH_CHARGES)

-- Flat distance a character may cover in `dt` seconds at `walkSpeed` (without the burst bank)
function Movement.allowance(walkSpeed: number, dt: number): number
	return walkSpeed * Config.MOVE_SLACK * dt + Config.MOVE_GRACE
end

function Movement.newTrack(pos: Vector3, now: number): Track
	return { last = pos, at = now, bank = Config.MOVE_BURST, skip = false, suspect = false }
end

-- One sample (pure, tested): "ok" (accepted), "suspect" (too far, wait one more sample) or
-- "strike" (still too far: the caller pulls back to t.last; the track is reset for that)
function Movement.step(t: Track, pos: Vector3, now: number, walkSpeed: number): string
	if t.skip or pos ~= pos then
		t.skip, t.suspect = false, false
		t.last, t.at = pos, now
		return "ok"
	end
	local dt = math.max(0, now - t.at)
	local bank = math.min(Config.MOVE_BURST, t.bank + REFILL * dt)
	local moved = Vector3.new(pos.X - t.last.X, 0, pos.Z - t.last.Z).Magnitude
	local excess = moved - Movement.allowance(walkSpeed, dt)
	if excess > 0 then
		bank -= excess
	end
	if bank < 0 then
		if t.suspect then
			t.suspect = false
			t.bank = 0
			t.at = now
			return "strike"
		end
		t.suspect = true -- keep the baseline: the next sample is judged over the whole span
		return "suspect"
	end
	t.bank = bank
	t.suspect = false
	t.last, t.at = pos, now
	return "ok"
end

-- The server is about to move this player's character itself: the next sample only re-bases
function Movement.teleported(player: Player)
	local t = tracks[player]
	if t then
		t.skip = true
	end
end

-- Strikes of this session (Rift compares the count at run start with the count at a clear)
function Movement.strikes(player: Player): number
	return strikes[player] or 0
end

local function drop(player: Player)
	local t = tracks[player]
	if t then
		t.moved:Disconnect()
		tracks[player] = nil
	end
end

local function check(player: Player, now: number)
	local model = player.Character
	local root = model and model:FindFirstChild("HumanoidRootPart")
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if not (model and root and root:IsA("BasePart") and humanoid) or humanoid.Health <= 0 then
		drop(player)
		return
	end
	local t = tracks[player]
	if not t or t.root ~= root then
		drop(player)
		local live = Movement.newTrack(root.Position, now) :: Live
		live.root = root
		live.moved = root:GetPropertyChangedSignal("CFrame"):Connect(function()
			if not pulling[player] then
				live.skip = true
			end
		end)
		tracks[player] = live
		return
	end
	local from = t.last
	local result = Movement.step(t, root.Position, now, humanoid.WalkSpeed)
	if result ~= "strike" then
		return
	end
	strikes[player] = (strikes[player] or 0) + 1
	warn(
		string.format(
			"[Movement] %s moved %.0f studs too fast, pulled back (strike %d)",
			player.Name,
			(root.Position - from).Magnitude,
			strikes[player]
		)
	)
	pulling[player] = true
	root.AssemblyLinearVelocity = Vector3.zero
	model:PivotTo(CFrame.new(from) * root.CFrame.Rotation)
	pulling[player] = nil
	Movement.Struck:Fire(player)
end

function Movement.init()
	Players.PlayerRemoving:Connect(function(player: Player)
		drop(player)
		strikes[player] = nil
		pulling[player] = nil
	end)
end

function Movement.start()
	while true do
		task.wait(Config.MOVE_SAMPLE)
		local now = os.clock()
		for _, player in Players:GetPlayers() do
			check(player, now)
		end
	end
end

return Movement
