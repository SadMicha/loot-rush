--!strict
-- Nachbau von RBXScriptSignal/RBXScriptConnection auf dem Sandbox-Scheduler.

local Scheduler = require("./Scheduler")

local Connection = {}
Connection.__index = Connection
Connection.__type = "RBXScriptConnection"

function Connection.Disconnect(self: any)
	if not self.Connected then
		return
	end
	self.Connected = false
	local list = self._signal._conns
	for i, c in list do
		if c == self then
			table.remove(list, i)
			break
		end
	end
end
Connection.disconnect = Connection.Disconnect

local Signal = {}
Signal.__index = Signal
Signal.__type = "RBXScriptSignal"
Signal.__tostring = function(self: any)
	return "Signal " .. tostring(self.name)
end

function Signal.new(sched: Scheduler.Scheduler, name: string?)
	return setmetatable({ _sched = sched, _conns = {}, _waiting = {}, name = name or "?" }, Signal)
end

function Signal.Connect(self: any, fn: any)
	if type(fn) ~= "function" then
		error("Attempt to connect failed: Passed value is not a function", 2)
	end
	local conn = setmetatable(
		{ Connected = true, _signal = self, _fn = fn, _side = self._sched.side },
		Connection
	)
	table.insert(self._conns, conn)
	return conn
end
Signal.connect = Signal.Connect
Signal.ConnectParallel = Signal.Connect

function Signal.Once(self: any, fn: any)
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

function Signal.Wait(self: any)
	table.insert(self._waiting, coroutine.running())
	return coroutine.yield()
end
Signal.wait = Signal.Wait

function Signal.Fire(self: any, ...: any)
	local sched = self._sched
	for _, c in table.clone(self._conns) do
		if c.Connected then
			sched:spawnAs(c._side, c._fn, ...)
		end
	end
	local waiting = self._waiting
	self._waiting = {}
	for _, co in waiting do
		sched:resume(co, ...)
	end
end

function Signal.hasListeners(self: any): boolean
	return #self._conns > 0 or #self._waiting > 0
end

return Signal
