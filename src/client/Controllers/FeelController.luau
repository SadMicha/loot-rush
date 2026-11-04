--!strict
-- Combat feel ("juice", docs/GAMEPLAY.md "Combat feel"): camera shake, hitstop, white hit flash on enemies
-- and the Stud VFX that turn hits, kills and skills into flying bricks (BrickController).
-- Listens to the same Net.Fx events as FxController; the server tags them with `by` (attacker
-- UserId), `who` (hurt player), `target` (enemy model) and `big` (boss or elite).
-- Only the own hits shake the camera or stop time, so busy servers stay calm.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Feel = require(ReplicatedStorage.Shared.Feel)
local Net = require(ReplicatedStorage.Shared.Net)
local BrickController = require(script.Parent.BrickController)
local QuestController = require(script.Parent.QuestController)
local Prefs = require(script.Parent.Parent.Prefs)

local FeelController = {}

local player = Players.LocalPlayer
local trauma = 0
local hitstopUntil = 0
local flashes = 0
local noise = Random.new()

-- Adds camera trauma (0..1); the offset grows with trauma² so small hits stay subtle.
-- Scaled by the "Camera shake" setting (0 = off).
function FeelController.shake(amount: number)
	local scale = Prefs.get("shake")
	trauma = math.clamp(trauma + amount * (if typeof(scale) == "number" then scale else 1), 0, 1)
end

function FeelController.trauma(): number
	return trauma
end

-- Camera offset for this frame, called by CameraController after it placed the camera
function FeelController.shakeOffset(dt: number): CFrame
	if trauma <= 0 then
		return CFrame.identity
	end
	local t = trauma * trauma
	local m = Feel.SHAKE_MAX_OFFSET * t
	local r = math.rad(Feel.SHAKE_MAX_ROLL) * t
	trauma = math.max(0, trauma - Feel.SHAKE_DECAY * dt)
	return CFrame.new(noise:NextNumber(-m, m), noise:NextNumber(-m, m), 0)
		* CFrame.Angles(0, 0, noise:NextNumber(-r, r))
end

-- Camera punch-in (victory finisher): CameraController multiplies its distance with this
local punchAt = -100
function FeelController.punch()
	punchAt = os.clock()
end

function FeelController.zoomFactor(): number
	local t = os.clock() - punchAt
	local inT, hold, out = Feel.VICTORY_ZOOM_IN, Feel.VICTORY_ZOOM_HOLD, Feel.VICTORY_ZOOM_OUT
	if t < 0 or t >= inT + hold + out then
		return 1
	end
	local depth = 1 - Feel.VICTORY_ZOOM
	local k
	if t < inT then
		k = math.sin(t / inT * math.pi / 2) -- fast in
	elseif t < inT + hold then
		k = 1
	else
		local u = (t - inT - hold) / out
		k = 1 - u * u * (3 - 2 * u) -- smooth out
	end
	return 1 - depth * k
end

-- True while a hitstop holds the frame (camera follow and bricks pause)
function FeelController.frozen(): boolean
	return os.clock() < hitstopUntil
end

-- Freezes the own character's animations for `duration` seconds (server movement goes on;
-- the short pause is what makes a heavy hit "land")
function FeelController.hitstop(duration: number)
	local now = os.clock()
	if now + duration <= hitstopUntil then
		return
	end
	local extending = now < hitstopUntil
	hitstopUntil = now + duration
	BrickController.pause(hitstopUntil)
	if extending then
		-- already frozen: the running restore picks up the new end. Capturing the speeds again
		-- here would read 0 and leave idle/walk frozen for good after back-to-back hits.
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local paused: { [AnimationTrack]: number } = {}
	for _, track in animator:GetPlayingAnimationTracks() do
		paused[track] = if track.Speed ~= 0 then track.Speed else 1
		track:AdjustSpeed(0)
	end
	task.delay(duration, function()
		while os.clock() < hitstopUntil - 0.001 do
			task.wait(hitstopUntil - os.clock())
		end
		for track, speed in paused do
			if track.IsPlaying then
				track:AdjustSpeed(speed)
			end
		end
	end)
end

-- White flash on an enemy model (Highlight, budgeted: Roblox renders at most 31 at once)
function FeelController.flash(model: Instance)
	if flashes >= Feel.FLASH_MAX then
		return
	end
	local ok, usable = pcall(function()
		return model:IsA("Model")
			and model.Parent ~= nil
			and model:FindFirstChild("HitFlash") == nil
	end)
	if not ok or not usable then
		return
	end
	flashes += 1
	local h = Instance.new("Highlight")
	h.Name = "HitFlash"
	h.FillColor = Color3.new(1, 1, 1)
	h.FillTransparency = 0.15
	h.OutlineTransparency = 1
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Adornee = model
	h.Parent = model
	TweenService
		:Create(h, TweenInfo.new(Feel.FLASH_TIME, Enum.EasingStyle.Quad), { FillTransparency = 1 })
		:Play()
	task.delay(Feel.FLASH_TIME, function()
		flashes -= 1
		pcall(h.Destroy, h) -- the enemy may be gone together with its flash
	end)
end

local function own(id: any): boolean
	return id == player.UserId
end

-- The target may already be gone (killed by this very hit): never index it unguarded
local function colorOf(target: any): Color3
	if typeof(target) == "Instance" then
		local ok, c = pcall(target.GetAttribute, target, "Color")
		if ok and typeof(c) == "Color3" then
			return c
		end
	end
	return Color3.new(1, 1, 1)
end

local handlers: { [string]: (data: any) -> () } = {}

function handlers.dmg(d)
	local pos = d.pos
	if typeof(pos) ~= "Vector3" then
		return
	end
	if d.hurt then
		if own(d.who) then
			FeelController.shake(Feel.SHAKE_HURT)
		end
		return
	end
	if d.amount == nil then
		if d.counter and own(d.who) then -- dodge roll through an attack (Shared/Momentum)
			FeelController.shake(Feel.SHAKE_COUNTER)
		end
		return -- "Dodged", "Blocked!" and similar texts
	end
	local target = d.target
	if typeof(target) == "Instance" then
		FeelController.flash(target)
	end
	BrickController.burst(pos - Vector3.new(0, 1.5, 0), colorOf(target), Feel.HIT_CHIPS, 14, 0.45)
	if own(d.by) and d.crit then
		FeelController.shake(Feel.SHAKE_CRIT)
		if (tonumber(d.critTier) or 1) >= 2 then
			FeelController.hitstop(Feel.HITSTOP_CRIT)
		end
	end
end

function handlers.death(d)
	local pos = d.pos
	if typeof(pos) ~= "Vector3" then
		return
	end
	local big = d.big == true
	if own(d.by) then
		FeelController.shake(if big then Feel.SHAKE_KILL_BIG else Feel.SHAKE_KILL)
		if big then
			FeelController.hitstop(Feel.HITSTOP_KILL_BIG)
		end
	end
	-- The model normally shatters into its own bricks when it disappears (BrickController);
	-- if it was never seen on this client, a plain burst stands in
	local color = if typeof(d.color) == "Color3" then d.color else Color3.new(1, 1, 1)
	task.delay(0.25, function()
		if not BrickController.shatteredNear(pos, 0.6) then
			BrickController.burst(pos, color, Feel.DEATH_BRICKS // 2, 18, 0.8)
		end
	end)
end

function handlers.nova(d)
	if
		typeof(d.pos) == "Vector3"
		and typeof(d.radius) == "number"
		and typeof(d.color) == "Color3"
	then
		BrickController.ring(d.pos, d.radius, d.color)
	end
end

local GOLD = Color3.fromHex("#FFD24A")

local function near(pos: any, range: number): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return typeof(pos) == "Vector3"
		and root ~= nil
		and root:IsA("BasePart")
		and (root.Position - pos).Magnitude <= range
end

-- A boss is Broken (Shared/Bosses): heavy thud, gold bricks burst off it
handlers["break"] = function(d)
	if not near(d.pos, 120) then
		return -- someone else's rift
	end
	FeelController.shake(Feel.SHAKE_BREAK)
	FeelController.hitstop(Feel.HITSTOP_BREAK)
	BrickController.burst(d.pos, GOLD, Feel.BREAK_BRICKS, 26, 1)
	if typeof(d.target) == "Instance" then
		FeelController.flash(d.target)
	end
end

-- Killing blow on a boss: the frame holds, the camera punches in, gold bricks fountain out
function handlers.victory(d)
	if not own(d.by) and not near(d.pos, 120) then
		return
	end
	local pos = d.pos
	if typeof(pos) ~= "Vector3" then
		return
	end
	FeelController.hitstop(Feel.HITSTOP_VICTORY)
	FeelController.shake(Feel.SHAKE_VICTORY)
	FeelController.punch()
	for i = 0, Feel.VICTORY_BRICKS - 1 do
		task.delay(i * 0.15, function()
			BrickController.burst(pos + Vector3.new(0, 2, 0), GOLD, 14, 30 + i * 6, 1.2)
		end)
	end
end

-- A trail area is clear: a ring of bricks around the player and a toast
function handlers.areaclear(d)
	local color = if typeof(d.color) == "Color3" then d.color else GOLD
	local wave, waves = tonumber(d.wave), tonumber(d.waves)
	if wave and waves then
		QuestController.toast(
			if wave >= waves
				then "Area cleared · the boss awaits"
				else string.format("Area %d/%d cleared", wave, waves),
			color
		)
	end
	if typeof(d.pos) == "Vector3" then
		BrickController.ring(d.pos - Vector3.new(0, 2.5, 0), 7, color)
		BrickController.burst(d.pos, GOLD, Feel.AREA_BRICKS, 18, 0.8)
	end
	FeelController.shake(0.15)
end

-- Boss intro line (The Smoothing, Shared/Smoothing): a toast and a small rumble
function handlers.intro(d)
	if typeof(d.text) == "string" then
		QuestController.toast(d.text, if typeof(d.color) == "Color3" then d.color else nil)
		FeelController.shake(0.25)
	end
end

-- Melee arc: a fan of bricks along the edge of the swing
function handlers.arc(d)
	local pos, dir, radius, arc, color = d.pos, d.dir, d.radius, d.arc, d.color
	if
		typeof(pos) ~= "Vector3"
		or typeof(dir) ~= "Vector3"
		or typeof(radius) ~= "number"
		or typeof(arc) ~= "number"
		or typeof(color) ~= "Color3"
	then
		return
	end
	local n = math.clamp(math.floor(arc / 25), 3, 8)
	local base = math.atan2(dir.X, dir.Z)
	local half = math.rad(arc) / 2
	for i = 1, n do
		local a = base - half + (i - 0.5) / n * half * 2
		local out = Vector3.new(math.sin(a), 0, math.cos(a))
		BrickController.brick(
			CFrame.new(pos + out * radius * 0.8 + Vector3.new(0, 1, 0)),
			Vector3.new(0.8, 0.5, 0.8),
			color,
			out * 10 + Vector3.new(0, 14, 0),
			pos.Y
		)
	end
end

function handlers.proj(d)
	local to, color, time = d.to, d.color, d.time
	if typeof(to) ~= "Vector3" or typeof(color) ~= "Color3" or typeof(time) ~= "number" then
		return
	end
	task.delay(math.max(time, 0.03), function()
		BrickController.burst(to, color, 2, 10, 0.4)
	end)
end

function handlers.chain(d)
	local points, color = d.points, d.color
	if typeof(points) ~= "table" or typeof(color) ~= "Color3" then
		return
	end
	for i, p in points do
		if i > 1 and typeof(p) == "Vector3" then
			BrickController.burst(p, color, 1, 10, 0.4)
		end
	end
end

function FeelController.start()
	Net.Fx.OnClientEvent:Connect(function(kind: string, data: any)
		local handler = handlers[kind]
		if handler and typeof(data) == "table" then
			handler(data)
		end
	end)
end

return FeelController
