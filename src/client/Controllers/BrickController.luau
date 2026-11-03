--!strict
-- Brick Break + Stud VFX (docs/IDEAS.md #1, docs/COMBAT-FEEL.md): one pool of studded bricks
-- with a hard budget. Enemies shatter into their own bricks when they die, hits chip bricks off,
-- skills throw bricks, the dodge roll leaves a brick trail. Purely visual and client-side:
-- anchored parts moved with one BulkMoveTo per frame, no physics, no network.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Feel = require(ReplicatedStorage.Shared.Feel)
local Studs = require(ReplicatedStorage.Shared.Models.Studs)
local Prefs = require(script.Parent.Parent.Prefs)

local BrickController = {}

type Brick = {
	part: Part,
	vel: Vector3,
	spin: CFrame,
	floor: number,
	born: number,
	life: number,
	home: number?, -- Stud Rush: from this time (os.clock) the brick flies to the own character
}

local container: Folder
local free: { Part } = {}
local active: { Brick } = {}
local rng = Random.new()
-- Enemy parts captured when the enemy appears (shattered when its Health attribute hits 0)
local partsOf: { [Model]: { BasePart } } = {}
local pausedUntil = 0 -- hitstop (FeelController)
local recent: { { pos: Vector3, t: number } } = {} -- last shatters, so the death Fx does not double up
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

-- Brick budget by the "Effects quality" setting (auto: low Roblox graphics level or touch
-- device get fewer bricks, Prefs.effectLevel)
local function budget(): number
	local level = Prefs.effectLevel()
	if level == "low" then
		return Feel.DEBRIS_LOW
	elseif level == "medium" then
		return Feel.DEBRIS_MEDIUM
	end
	return Feel.DEBRIS_MAX
end

local function take(): Part
	local reused = table.remove(free)
	if reused then
		return reused
	end
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Plastic
	return p
end

local function release(i: number)
	local b = table.remove(active, i) :: Brick -- keeps spawn order, so index 1 is the oldest
	b.part.Parent = nil
	table.insert(free, b.part)
end

-- Throws one brick. size is clamped to brick proportions; vel in studs/s.
function BrickController.brick(
	cf: CFrame,
	size: Vector3,
	color: Color3,
	vel: Vector3,
	floor: number?
)
	if #active >= budget() then
		release(1) -- recycle the oldest
	end
	local p = take()
	p.Size = Vector3.new(
		math.clamp(size.X, 0.4, 2),
		math.clamp(size.Y, 0.4, 1.2),
		math.clamp(size.Z, 0.4, 2)
	)
	p.CFrame = cf
	p.Color = color
	p.Transparency = 0
	Studs.apply(p)
	p.Parent = container
	table.insert(active, {
		part = p,
		vel = vel,
		spin = CFrame.Angles(rng:NextNumber(-6, 6), rng:NextNumber(-6, 6), rng:NextNumber(-6, 6)),
		floor = floor or (cf.Position.Y - 3),
		born = os.clock(),
		life = Feel.BRICK_LIFE * rng:NextNumber(0.8, 1.2),
	})
end

-- Stud Rush (Shared/Rush): a loose stud pops out of a kill and is vacuumed to the own character
function BrickController.stud(pos: Vector3, color: Color3)
	BrickController.brick(
		CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, 6), 0),
		Vector3.new(0.6, 0.4, 0.6),
		color,
		Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(14, 20), rng:NextNumber(-6, 6)),
		pos.Y - 2.5
	)
	local b = active[#active]
	b.home = os.clock() + Feel.STUD_HOME_DELAY
	b.life = Feel.STUD_HOME_DELAY + 1.5
end

-- Burst of bricks from a point (hit chips, skill impacts)
function BrickController.burst(
	pos: Vector3,
	color: Color3,
	count: number,
	speed: number,
	size: number?
)
	for _ = 1, count do
		local dir =
			Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.4, 1.2), rng:NextNumber(-1, 1))
		local s = size or 0.6
		BrickController.brick(
			CFrame.new(pos) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0),
			Vector3.new(s, s * 0.6, s),
			color,
			dir.Unit * speed * rng:NextNumber(0.6, 1.1),
			pos.Y - 2.5
		)
	end
end

-- Ring of bricks popping up along a circle (novas, slams)
function BrickController.ring(pos: Vector3, radius: number, color: Color3)
	local n = math.clamp(math.floor(radius * 1.2), 6, 16)
	for i = 1, n do
		local a = i / n * math.pi * 2
		local at = pos + Vector3.new(math.cos(a) * radius, 0.3, math.sin(a) * radius)
		BrickController.brick(
			CFrame.new(at) * CFrame.Angles(0, -a, 0),
			Vector3.new(1, 0.6, 1),
			color,
			Vector3.new(math.cos(a) * 4, rng:NextNumber(14, 22), math.sin(a) * 4),
			pos.Y
		)
	end
end

-- Enemy model breaks into its own bricks
function BrickController.shatter(model: Model, big: boolean?)
	local list = partsOf[model]
	if not list or #list == 0 then
		return
	end
	-- Read the parts once; a part that is already unreadable is skipped
	local max = Feel.DEATH_BRICKS * (if big then 2 else 1)
	local step = math.max(1, #list / max)
	local picked: { { cf: CFrame, size: Vector3, color: Color3 } } = {}
	local i = 1.0
	while i <= #list do
		local p = list[math.floor(i)]
		local ok, cf, size, color, see = pcall(function()
			return p.CFrame, p.Size, p.Color, p.Transparency < 0.9
		end)
		if ok and see and typeof(cf) == "CFrame" then
			table.insert(picked, { cf = cf, size = size, color = color })
		end
		i += step
	end
	if #picked == 0 then
		return
	end
	local center = Vector3.zero
	for _, b in picked do
		center += b.cf.Position
	end
	center /= #picked
	table.insert(recent, { pos = center, t = os.clock() })
	if #recent > 8 then
		table.remove(recent, 1)
	end
	local floor = center.Y - 3
	for _, b in picked do
		local out = b.cf.Position - center
		out = if out.Magnitude > 0.01 then out.Unit else Vector3.yAxis
		BrickController.brick(
			b.cf,
			b.size,
			b.color,
			(out + Vector3.new(0, 1.2, 0)) * rng:NextNumber(12, 22),
			floor
		)
	end
end

-- True if an enemy shattered near `pos` within the last `within` seconds
function BrickController.shatteredNear(pos: Vector3, within: number): boolean
	local now = os.clock()
	for _, r in recent do
		if now - r.t <= within and (Vector3.new(r.pos.X, pos.Y, r.pos.Z) - pos).Magnitude < 6 then
			return true
		end
	end
	return false
end

-- Holds all bricks in place until `untilT` (os.clock), used by the hitstop
function BrickController.pause(untilT: number)
	pausedUntil = math.max(pausedUntil, untilT)
end

local function step(dt: number)
	local now = os.clock()
	if now < pausedUntil then
		for _, b in active do
			b.born += dt -- frozen bricks do not age
		end
		return
	end
	table.clear(moveParts) -- reused every frame: no garbage per Heartbeat
	table.clear(moveCFrames)
	local parts, cfs = moveParts, moveCFrames
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local target = if root and root:IsA("BasePart") then root.Position else nil
	local i = 1
	while i <= #active do
		local b = active[i]
		local age = now - b.born
		local homing = b.home ~= nil and now >= b.home and target ~= nil
		local collected = homing and target ~= nil and (target - b.part.Position).Magnitude < 2
		if collected or age >= b.life then
			release(i) -- collected by the character, or faded out
		elseif homing and target then
			local to = target - b.part.Position
			b.vel = to.Unit * math.max(Feel.STUD_HOME_SPEED, b.vel.Magnitude)
			table.insert(parts, b.part)
			table.insert(
				cfs,
				CFrame.new(b.part.Position + b.vel * math.min(dt, to.Magnitude / b.vel.Magnitude))
					* b.part.CFrame.Rotation
			)
			i += 1
		else
			b.vel -= Vector3.new(0, Feel.BRICK_GRAVITY * dt, 0)
			local cf = b.part.CFrame
			local pos = cf.Position + b.vel * dt
			if pos.Y < b.floor then
				pos = Vector3.new(pos.X, b.floor, pos.Z)
				b.vel = Vector3.new(b.vel.X * 0.6, -b.vel.Y * Feel.BRICK_BOUNCE, b.vel.Z * 0.6)
			end
			local rot = cf.Rotation:Lerp(cf.Rotation * b.spin, math.min(1, dt))
			table.insert(parts, b.part)
			table.insert(cfs, CFrame.new(pos) * rot)
			if age > b.life * 0.6 then
				b.part.Transparency = (age - b.life * 0.6) / (b.life * 0.4)
			end
			i += 1
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

local function track(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local list: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	partsOf[model] = list
	-- Shatter the moment life hits 0: the server destroys the model right after
	local conn: RBXScriptConnection
	conn = model:GetAttributeChangedSignal("Health"):Connect(function()
		-- deferred signals can run after the server destroyed the model: read guarded
		local ok, hp, big = pcall(function()
			return model:GetAttribute("Health"),
				model:GetAttribute("Boss") == true or model:GetAttribute("Elite") == true
		end)
		if ok and typeof(hp) == "number" and hp <= 0 and partsOf[model] then
			conn:Disconnect()
			BrickController.shatter(model, big)
			partsOf[model] = nil
		end
	end)
end

local function untrack(model: Instance)
	partsOf[model :: Model] = nil
end

-- Number of bricks in flight (tests, debug)
function BrickController.count(): number
	return #active
end

function BrickController.init()
	container = Instance.new("Folder")
	container.Name = "Bricks"
	container.Parent = workspace
end

function BrickController.start()
	CollectionService:GetInstanceAddedSignal("Enemy"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("Enemy"):Connect(untrack)
	for _, model in CollectionService:GetTagged("Enemy") do
		track(model)
	end
	RunService.Heartbeat:Connect(step)
end

return BrickController
