--!strict
-- Character animations (docs/ANIMATIONS.md): attacks per weapon, skill casts, dodge roll, hit
-- reaction, death, level-up cheer, plus a run lean and idle breathing. Moves are keyframes in
-- Shared/Anim; this controller layers them on top of Roblox's own animations (idle, walk, the
-- weapon hold pose) by rotating the rig's Motor6D.Transform right after the Animator wrote it
-- (RunService.PreSimulation). Works on R15 and R6, on classic Motor6D joints and on the
-- AnimationConstraint joints of Roblox's Avatar Joint Upgrade (no Motor6D left in the rig). Needs
-- no uploaded animation assets and sends nothing over the network: every client animates the characters near its own camera.
--
-- Triggers: Net.Fx "act" (server, every basic attack, skill cast and dash of any player),
-- Fx "dmg" with `hurt` (hit reaction), Fx "levelup" (cheer), Humanoid.Died (death), and the own
-- dash right away from DashController (no waiting for the server).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Anim = require(ReplicatedStorage.Shared.Anim)
local Net = require(ReplicatedStorage.Shared.Net)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local BrickController = require(script.Parent.BrickController)
local FeelController = require(script.Parent.FeelController)

local AnimController = {}

-- A rig joint: Motor6D (classic rigs) or AnimationConstraint (Avatar Joint Upgrade). Both have
-- C0, Part0, Part1 and a writable Transform with the same meaning, so they are used untyped.
type Joint = {
	motor: any,
	rot: CFrame, -- C0 rotation: turns parent-space angles into the motor's Transform space
	rotInv: CFrame,
	base: CFrame, -- the Transform the Animator wrote (without our layer)
	written: CFrame?, -- what we wrote last frame (nil = untouched)
}
type Layer = { move: Anim.Move, t: number, target: Vector3? }
type Rig = {
	character: Model,
	player: Player?,
	humanoid: Humanoid?,
	root: BasePart?,
	joints: { [string]: Joint },
	r6: boolean,
	dirty: boolean, -- body parts changed (avatar loading): find the motors again
	layers: { Layer },
	combo: number,
	stance: number, -- current holding-stance weight (Anim.STANCE), eases toward its target
	deadAt: number, -- 0 = alive
	broken: boolean,
	active: boolean,
	conns: { RBXScriptConnection },
	emptyAt: number, -- since when joint searches find nothing (0 = joints found)
	searchedAt: number,
	warned: boolean,
}

local player = Players.LocalPlayer
local rigs: { [Model]: Rig } = {}
local pose: Anim.Pose = {}
local DEG = math.pi / 180

local function own(rig: Rig): boolean
	return rig.character == player.Character
end

local function isJoint(d: Instance): boolean
	return d:IsA("Motor6D") or d:IsA("AnimationConstraint")
end

-- The part a joint moves (AnimationConstraint: also through its Attachment1)
local function movedPart(joint: any): Instance?
	local ok, part = pcall(function()
		return joint.Part1
	end)
	if ok and part then
		return part
	end
	local okA, a1 = pcall(function()
		return joint.Attachment1
	end)
	return if okA and a1 then a1.Parent else nil
end

-- Joint offset in the parent part (C0); an AnimationConstraint's C0 is its Attachment0.CFrame
local function jointC0(joint: any): CFrame?
	local ok, c0 = pcall(function()
		return joint.C0
	end)
	if ok and typeof(c0) == "CFrame" then
		return c0
	end
	local okA, a0 = pcall(function()
		return joint.Attachment0
	end)
	if okA and a0 and a0:IsA("Attachment") then
		return a0.CFrame
	end
	return nil
end

-- The joint that moves `part`: by name inside it first, else any joint whose Part1 is the part
-- (the joint upgrade may rename or reparent the constraints)
local function jointOf(character: Model, part: Instance, name: string): Instance?
	local byName = part:FindFirstChild(name)
	if byName and isJoint(byName) then
		return byName
	end
	for _, d in part:GetChildren() do
		if isJoint(d) and movedPart(d) == part then
			return d
		end
	end
	for _, d in character:GetDescendants() do
		if isJoint(d) and movedPart(d) == part then
			return d
		end
	end
	return nil
end

local function findJoints(rig: Rig)
	rig.dirty = false
	table.clear(rig.joints)
	local character = rig.character
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	rig.humanoid = humanoid
	local root = character:FindFirstChild("HumanoidRootPart")
	rig.root = if root and root:IsA("BasePart") then root else nil
	rig.r6 = humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R6
	local map: { [string]: { string } } = if rig.r6 then Anim.R6 else Anim.R15
	for name, at in map do
		local part = character:FindFirstChild(at[1])
		local found = if part and part:IsA("BasePart") then jointOf(character, part, at[2]) else nil
		local motor = found :: any
		local c0 = if motor then jointC0(motor) else nil
		if c0 then
			local rot = c0.Rotation
			rig.joints[name] = {
				motor = motor,
				rot = rot,
				rotInv = rot:Inverse(),
				base = motor.Transform,
				written = nil,
			}
		end
	end
	rig.searchedAt = os.clock()
	if next(rig.joints) == nil then
		rig.emptyAt = if rig.emptyAt > 0 then rig.emptyAt else os.clock()
	else
		rig.emptyAt = 0
	end
end

-- Gives every joint back to the Animator (our offset is taken out once)
local function release(rig: Rig)
	for _, j in rig.joints do
		local written = j.written
		if written then
			if j.motor.Transform:FuzzyEq(written, 1e-4) then
				j.motor.Transform = j.base
			end
			j.written = nil
		end
	end
end

local function removeRig(character: Model)
	local rig = rigs[character]
	if not rig then
		return
	end
	rigs[character] = nil
	for _, c in rig.conns do
		c:Disconnect()
	end
end

local function classColor(rig: Rig): Color3
	local p = rig.player
	local w = p and Weapons.ByClass[tostring(p:GetAttribute("Class") or "")]
	return if w then w.accent else Color3.new(1, 1, 1)
end

local function play(rig: Rig, moveId: string, target: Vector3?)
	local m = Anim.Moves[moveId]
	if not m or (rig.deadAt > 0 and moveId ~= "death") then
		return
	end
	for i, layer in rig.layers do
		if layer.move == m then
			table.remove(rig.layers, i) -- the same move again starts over
			break
		end
	end
	if #rig.layers >= Anim.LAYERS_MAX then
		table.remove(rig.layers, 1)
	end
	table.insert(rig.layers, { move = m, t = 0, target = target })
end

local function onDied(rig: Rig)
	if rig.deadAt > 0 then
		return
	end
	table.clear(rig.layers)
	rig.deadAt = os.clock()
	play(rig, "death")
	if own(rig) and rig.root then
		-- the server anchors too; doing it here as well stops the physics fall right away
		pcall(function()
			(rig.root :: BasePart).Anchored = true
		end)
	end
end

local function addRig(character: Model, owner: Player?)
	if rigs[character] then
		return
	end
	local rig: Rig = {
		character = character,
		player = owner,
		humanoid = nil,
		root = nil,
		joints = {},
		r6 = false,
		dirty = true,
		layers = {},
		combo = 0,
		stance = 0,
		deadAt = 0,
		broken = false,
		active = false,
		conns = {},
		emptyAt = 0,
		searchedAt = 0,
		warned = false,
	}
	rigs[character] = rig
	table.insert(
		rig.conns,
		character.DescendantAdded:Connect(function(d)
			if isJoint(d) or d:IsA("Humanoid") or d:IsA("BasePart") then
				rig.dirty = true
			end
		end)
	)
	table.insert(
		rig.conns,
		character.DescendantRemoving:Connect(function(d)
			if isJoint(d) or d:IsA("BasePart") then
				rig.dirty = true
			end
		end)
	)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
		or character:WaitForChild("Humanoid", 5)
	if rigs[character] ~= rig then
		return
	end
	if humanoid and humanoid:IsA("Humanoid") then
		table.insert(
			rig.conns,
			humanoid.Died:Connect(function()
				onDied(rig)
			end)
		)
		if humanoid.Health <= 0 then
			onDied(rig)
		end
	end
end

local function rigOf(p: Player?): Rig?
	local character = p and p.Character
	return if character then rigs[character] else nil
end

local function playerOf(id: any): Player?
	if typeof(id) ~= "number" then
		return nil
	end
	return Players:GetPlayerByUserId(id)
end

-- Plays a move on a character (also used by DashController for the own roll)
function AnimController.play(character: Model?, moveId: string, target: Vector3?)
	local rig = character and rigs[character]
	if rig then
		play(rig, moveId, target)
	end
end

-- An attack of player `p`: the move follows the class weapon and the skill kind
function AnimController.attack(
	p: Player,
	kind: string,
	skillId: string?,
	basic: boolean,
	target: Vector3?
)
	local rig = rigOf(p)
	if not rig then
		return
	end
	local w = Weapons.ByClass[tostring(p:GetAttribute("Class") or "")]
	local style = w and Anim.STYLE[w.id]
	local id = Anim.moveFor(style, kind, skillId, basic, rig.combo)
	if basic then
		rig.combo += 1
	end
	play(rig, id, target)
end

-- Active move names on a character (specs, debugging)
function AnimController.playing(character: Model): { string }
	local out = {}
	local rig = rigs[character]
	if rig then
		for _, layer in rig.layers do
			table.insert(out, layer.move.id)
		end
	end
	return out
end

local function addVec(j: string, value: Vector3)
	pose[j] = (pose[j] or Vector3.zero) + value
end

-- Signed yaw (degrees, + = left) from the root's facing to the target, capped
local function yawTo(root: BasePart, target: Vector3): number
	local look = root.CFrame.LookVector
	local to = target - root.Position
	local a = math.atan2(look.X, look.Z)
	local b = math.atan2(to.X, to.Z)
	if to.X * to.X + to.Z * to.Z < 0.25 then
		return 0
	end
	local d = math.deg(b - a)
	d = (d + 180) % 360 - 180
	return math.clamp(d, -Anim.FACE_MAX, Anim.FACE_MAX)
end

local function breakApart(rig: Rig)
	rig.broken = true
	local root = rig.root
	if root then
		BrickController.burst(root.Position, classColor(rig), 10, 16, 0.7)
	end
	for _, d in rig.character:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
			d.CanCollide = false -- the server does the same; locally it takes effect at once
		elseif d:IsA("Decal") then
			d.Transparency = 1
		end
	end
end

-- Tells the Output once when the own character has nothing we can animate (a rig we do not
-- know); lists the joint classes found so the cause is visible in one playtest
local function warnNoJoints(rig: Rig)
	rig.warned = true
	local kinds: { [string]: number } = {}
	for _, d in rig.character:GetDescendants() do
		if d:IsA("JointInstance") or d:IsA("Constraint") then
			kinds[d.ClassName] = (kinds[d.ClassName] or 0) + 1
		end
	end
	local list = {}
	for k, n in kinds do
		table.insert(list, k .. " x" .. n)
	end
	local humanoid = rig.humanoid
	warn(
		"[AnimController] no animatable joints on own character (RigType "
			.. (if humanoid then tostring(humanoid.RigType) else "no Humanoid")
			.. "; joints: "
			.. (if #list > 0 then table.concat(list, ", ") else "none")
			.. ")"
	)
end

local function animate(rig: Rig, dt: number, now: number)
	if rig.emptyAt > 0 and now - rig.searchedAt >= Anim.JOINT_RETRY then
		rig.dirty = true -- nothing found yet (still loading?): look again now and then
	end
	if not rig.dirty then
		for _, j in rig.joints do
			if j.motor.Parent == nil then
				rig.dirty = true -- a joint was replaced (avatar loading, joint upgrade)
				break
			end
		end
	end
	if rig.dirty then
		release(rig)
		findJoints(rig)
		if
			rig.emptyAt > 0
			and own(rig)
			and not rig.warned
			and now - rig.emptyAt >= Anim.JOINT_WARN
		then
			warnNoJoints(rig)
		end
	end
	local root = rig.root
	if not root then
		return
	end
	local step = if own(rig) and FeelController.frozen() then 0 else dt
	table.clear(pose)
	local lift = Vector3.zero
	-- Always-on layers: run lean, idle breathing (not while dead)
	if rig.deadAt == 0 then
		local v = root.AssemblyLinearVelocity
		local speed = math.sqrt(v.X * v.X + v.Z * v.Z)
		local run = math.clamp(speed / Anim.RUN_SPEED, 0, 1)
		local idle = 1 - math.clamp(speed / 4, 0, 1)
		local b = math.sin(now * Anim.BREATH_RATE) * Anim.BREATH * idle
		addVec("waist", Vector3.new(-Anim.RUN_LEAN * run + b * 0.6, 0, 0))
		addVec("neck", Vector3.new(Anim.RUN_LEAN * run * 0.4 - b * 0.3, 0, 0))
		addVec("rShoulder", Vector3.new(0, 0, b * 0.5))
		addVec("lShoulder", Vector3.new(0, 0, -b * 0.5))
		-- Holding stance of the class weapon (Anim.STANCE), eased toward its target weight
		local p = rig.player
		local w = p and Weapons.ByClass[tostring(p:GetAttribute("Class") or "")]
		local want = Anim.stanceWeight(run, #rig.layers > 0)
		rig.stance += (want - rig.stance) * math.min(1, dt * Anim.STANCE_BLEND)
		lift += Anim.stance(w and w.id, rig.stance, now, pose)
	elseif not rig.broken and now - rig.deadAt >= Anim.DEATH_BREAK then
		breakApart(rig)
	end
	local yaw = 0
	for i = #rig.layers, 1, -1 do
		local layer = rig.layers[i]
		layer.t += step
		local m = layer.move
		if layer.t >= m.time and not m.hold then
			table.remove(rig.layers, i)
		else
			lift += Anim.sample(m, layer.t, pose)
			if m.face and layer.target then
				yaw += yawTo(root, layer.target) * Anim.faceWeight(m, layer.t)
			end
		end
	end
	if yaw ~= 0 then
		addVec("root", Vector3.new(0, yaw, 0))
	end
	if rig.r6 then
		for from, into in Anim.R6_FOLD do
			local x = pose[from]
			if x then
				addVec(into, x)
				pose[from] = nil
			end
		end
	end
	for name, j in rig.joints do
		local motor = j.motor
		local current = motor.Transform
		local written = j.written
		-- unchanged since our last write = the Animator left this joint alone: keep its base
		local base = if written and current:FuzzyEq(written, 1e-4) then j.base else current
		j.base = base
		local off = pose[name]
		local up = if name == "root" then lift else Vector3.zero
		if off or up ~= Vector3.zero then
			local a = off or Vector3.zero
			local delta = CFrame.new(up)
				* CFrame.fromEulerAnglesYXZ(a.X * DEG, a.Y * DEG, a.Z * DEG)
			local value = j.rotInv * delta * j.rot * base
			motor.Transform = value
			j.written = value
		elseif j.written then
			motor.Transform = base
			j.written = nil
		end
	end
end

local candidates: { { rig: Rig, d: number } } = {}

local function frame(dt: number)
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	local now = os.clock()
	table.clear(candidates)
	for character, rig in rigs do
		if not character.Parent then
			removeRig(character)
			continue
		end
		local root = rig.root
		local d = if root then (root.Position - eye).Magnitude else 0
		if own(rig) then
			d = 0 -- the own character is always animated
		end
		if d <= Anim.RANGE then
			table.insert(candidates, { rig = rig, d = d })
		elseif rig.active then
			rig.active = false
			release(rig)
		end
	end
	if #candidates > Anim.MAX_CHARACTERS then
		table.sort(candidates, function(a, b)
			return a.d < b.d
		end)
		for i = Anim.MAX_CHARACTERS + 1, #candidates do
			local rig = candidates[i].rig
			if rig.active then
				rig.active = false
				release(rig)
			end
			candidates[i] = nil
		end
	end
	for _, c in candidates do
		c.rig.active = true
		animate(c.rig, dt, now)
	end
end

local function watchPlayer(p: Player)
	p.CharacterAdded:Connect(function(character)
		task.spawn(addRig, character, p)
	end)
	p.CharacterRemoving:Connect(function(character)
		local rig = rigs[character]
		if rig then
			release(rig)
		end
		removeRig(character)
	end)
	if p.Character then
		task.spawn(addRig, p.Character, p)
	end
end

local handlers: { [string]: (data: any) -> () } = {}

function handlers.act(d)
	local p = playerOf(d.by)
	if not p or typeof(d.kind) ~= "string" then
		return
	end
	local target = if typeof(d.at) == "Vector3" then d.at else nil
	if d.kind == "dash" then
		if p ~= player then -- the own roll already started on the key press
			AnimController.play(p.Character, "roll")
		end
		return
	end
	AnimController.attack(
		p,
		d.kind,
		if typeof(d.skill) == "string" then d.skill else nil,
		d.basic == true,
		target
	)
end

function handlers.dmg(d)
	if d.hurt and d.amount ~= nil then
		local p = playerOf(d.who)
		if p then
			AnimController.play(p.Character, "hurt")
		end
	end
end

function handlers.levelup(d)
	local p = playerOf(d.who)
	if p then
		AnimController.play(p.Character, "cheer")
	end
end

function AnimController.start()
	for _, p in Players:GetPlayers() do
		watchPlayer(p)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Net.Fx.OnClientEvent:Connect(function(kind: string, data: any)
		local handler = handlers[kind]
		if handler and typeof(data) == "table" then
			handler(data)
		end
	end)
	RunService.PreSimulation:Connect(frame)
end

return AnimController
