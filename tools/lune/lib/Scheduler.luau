--!strict
-- Virtuelle Zeit statt echter: task.wait(5) dauert hier keine 5 Sekunden, sondern endet,
-- sobald step() die Uhr weit genug vorgestellt hat. So laufen Endlosschleifen nicht ewig.
-- Jeder Thread merkt sich seine Seite ("server" / "client"), damit RunService:IsServer() stimmt.

export type Side = "server" | "client" | "none"

type Sleeper = {
	co: thread,
	at: number,
	start: number,
	isWait: boolean,
	args: { n: number, [number]: any }?,
}

local Scheduler = {}
Scheduler.__index = Scheduler

export type Scheduler = typeof(setmetatable(
	{} :: {
		now: number,
		frame: number,
		side: Side,
		threadSide: { [thread]: Side },
		sleeping: { Sleeper },
		deferred: { { co: thread, args: { n: number, [number]: any } } },
		onError: (err: any, trace: string, side: Side) -> (),
		onFrame: ((dt: number) -> ())?,
	},
	Scheduler
))

function Scheduler.new(onError: (err: any, trace: string, side: Side) -> ()): Scheduler
	return setmetatable({
		now = 0,
		frame = 0,
		side = "none" :: Side,
		threadSide = setmetatable({}, { __mode = "k" }) :: any,
		sleeping = {},
		deferred = {},
		onError = onError,
		onFrame = nil,
	}, Scheduler)
end

function Scheduler.resume(self: Scheduler, co: thread, ...: any)
	if coroutine.status(co) ~= "suspended" then
		return
	end
	local prev = self.side
	self.side = self.threadSide[co] or prev
	local ok, err = coroutine.resume(co, ...)
	self.side = prev
	if not ok then
		self.onError(err, debug.traceback(co), self.threadSide[co] or prev)
	end
end

local function toThread(self: Scheduler, f: any, side: Side?): thread
	local co = if type(f) == "thread" then f else coroutine.create(f)
	if side or not self.threadSide[co] then
		self.threadSide[co] = side or self.side
	end
	return co
end

function Scheduler.spawnAs(self: Scheduler, side: Side?, f: any, ...: any): thread
	local co = toThread(self, f, side)
	self:resume(co, ...)
	return co
end

function Scheduler.spawn(self: Scheduler, f: any, ...: any): thread
	return self:spawnAs(nil, f, ...)
end

function Scheduler.defer(self: Scheduler, f: any, ...: any): thread
	local co = toThread(self, f)
	table.insert(self.deferred, { co = co, args = table.pack(...) })
	return co
end

function Scheduler.delay(self: Scheduler, t: number?, f: any, ...: any): thread
	local co = toThread(self, f)
	table.insert(
		self.sleeping,
		{
			co = co,
			at = self.now + (t or 0),
			start = self.now,
			isWait = false,
			args = table.pack(...),
		}
	)
	return co
end

function Scheduler.wait(self: Scheduler, t: number?): number
	local co = coroutine.running()
	if not coroutine.isyieldable() then
		error("task.wait außerhalb eines Threads der Sandbox", 2)
	end
	local dt = math.max(t or 0, 1 / 60)
	table.insert(self.sleeping, { co = co, at = self.now + dt, start = self.now, isWait = true })
	return coroutine.yield()
end

function Scheduler.cancel(self: Scheduler, co: thread)
	for i = #self.sleeping, 1, -1 do
		if self.sleeping[i].co == co then
			table.remove(self.sleeping, i)
		end
	end
	for i = #self.deferred, 1, -1 do
		if self.deferred[i].co == co then
			table.remove(self.deferred, i)
		end
	end
	if coroutine.status(co) == "suspended" then
		pcall(coroutine.close, co)
	end
end

function Scheduler.flushDeferred(self: Scheduler)
	local guard = 0
	while #self.deferred > 0 do
		guard += 1
		if guard > 100000 then
			self.onError(
				"task.defer-Schleife: über 100000 aufgeschobene Threads in einem Frame",
				"",
				self.side
			)
			self.deferred = {}
			return
		end
		local d = table.remove(self.deferred, 1) :: any
		self:resume(d.co, table.unpack(d.args, 1, d.args.n))
	end
end

function Scheduler.step(self: Scheduler, dt: number)
	self.now += dt
	self.frame += 1
	if self.onFrame then
		self.onFrame(dt)
	end
	local due, keep = {}, {}
	for _, s in self.sleeping do
		table.insert(if s.at <= self.now + 1e-9 then due else keep, s)
	end
	self.sleeping = keep
	table.sort(due, function(a, b)
		return a.at < b.at
	end)
	for _, s in due do
		if s.isWait then
			self:resume(s.co, self.now - s.start)
		else
			local args = s.args :: any
			self:resume(s.co, table.unpack(args, 1, args.n))
		end
	end
	self:flushDeferred()
end

function Scheduler.run(self: Scheduler, seconds: number, fps: number?)
	local rate = fps or 30
	for _ = 1, math.max(1, math.ceil(seconds * rate)) do
		self:step(1 / rate)
	end
end

return Scheduler
