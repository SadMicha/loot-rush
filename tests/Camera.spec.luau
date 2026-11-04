-- Camera on touch: swiping over free space rotates, a finger on the move stick or on buttons does not.
local PHONE = Vector2.new(844, 390)

local function yaw()
	local lv = workspace.CurrentCamera.CFrame.LookVector
	return math.atan2(-lv.X, -lv.Z)
end

local function swipe(from: Vector2, dx: number, processed: boolean)
	local uis = game:GetService("UserInputService")
	local input = {
		UserInputType = Enum.UserInputType.Touch,
		UserInputState = Enum.UserInputState.Begin,
		KeyCode = Enum.KeyCode.Unknown,
		Position = Vector3.new(from.X, from.Y, 0),
		Delta = Vector3.zero,
	}
	sim:signalIfExists(uis, "InputBegan"):Fire(input, processed)
	for _ = 1, 5 do
		input.UserInputState = Enum.UserInputState.Change
		input.Delta = Vector3.new(dx / 5, 0, 0)
		input.Position += input.Delta
		sim:signalIfExists(uis, "InputChanged"):Fire(input, processed)
		sim:run(1 / 30)
	end
	input.UserInputState = Enum.UserInputState.End
	sim:signalIfExists(uis, "InputEnded"):Fire(input, processed)
	sim:run(0.1)
end

local function camDistance(): number
	local root = sim.player.Character.HumanoidRootPart
	return (workspace.CurrentCamera.CFrame.Position - root.Position).Magnitude
end

local function touch(x: number, y: number)
	return {
		UserInputType = Enum.UserInputType.Touch,
		UserInputState = Enum.UserInputState.Begin,
		KeyCode = Enum.KeyCode.Unknown,
		Position = Vector3.new(x, y, 0),
		Delta = Vector3.zero,
	}
end

local function down(input, processed: boolean)
	sim:signalIfExists(game:GetService("UserInputService"), "InputBegan"):Fire(input, processed)
end

local function move(input, dx: number, processed: boolean)
	input.UserInputState = Enum.UserInputState.Change
	input.Delta = Vector3.new(dx, 0, 0)
	input.Position += input.Delta
	sim:signalIfExists(game:GetService("UserInputService"), "InputChanged"):Fire(input, processed)
end

local function up(input, processed: boolean)
	input.UserInputState = Enum.UserInputState.End
	sim:signalIfExists(game:GetService("UserInputService"), "InputEnded"):Fire(input, processed)
end

describe("Camera touch", function()
	it("rotates when swiping over free space", function()
		sim:boot({ seconds = 2 })
		sim:setViewport(PHONE, true)
		local before = yaw()
		swipe(Vector2.new(600, 150), 100, false)
		expect(math.abs(yaw() - before) > 0.3).toBe(true)
	end)

	it("does not rotate on the move stick bottom left", function()
		local before = yaw()
		swipe(Vector2.new(120, 300), 100, false)
		expect(math.abs(yaw() - before) < 0.01).toBe(true)
	end)

	it("does not rotate when a button has the finger", function()
		local before = yaw()
		swipe(Vector2.new(600, 150), 100, true)
		expect(math.abs(yaw() - before) < 0.01).toBe(true)
	end)

	it("does not zoom while walking with the stick and holding a skill button", function()
		sim:run(1)
		local before = camDistance()
		local stick = touch(120, 300)
		local button = touch(760, 300)
		down(stick, true)
		down(button, true)
		-- Roblox reports these two fingers as a pinch; the camera must ignore it
		local pinch = sim:signalIfExists(game:GetService("UserInputService"), "TouchPinch")
		for i = 1, 10 do
			move(stick, 6, true)
			if pinch then
				pinch:Fire({}, 1 + i * 0.1, 0, Enum.UserInputState.Change, false)
			end
			sim:run(1 / 30)
		end
		up(stick, true)
		up(button, true)
		sim:run(1)
		expect(math.abs(camDistance() - before) < 0.5).toBe(true)
	end)

	it("zooms in when two fingers spread apart over free space", function()
		sim:run(1)
		local before = camDistance()
		local a = touch(520, 150)
		local b = touch(620, 150)
		down(a, false)
		down(b, false)
		for _ = 1, 5 do
			move(a, -10, false)
			move(b, 10, false)
			sim:run(1 / 30)
		end
		up(a, false)
		up(b, false)
		sim:run(1)
		expect(camDistance() < before - 5).toBe(true)
	end)

	it("does not zoom from one free finger next to the stick finger", function()
		sim:run(1)
		local before = camDistance()
		local stick = touch(120, 300)
		local free = touch(600, 150)
		down(stick, false)
		down(free, false)
		for _ = 1, 5 do
			move(stick, 8, false)
			move(free, 20, false)
			sim:run(1 / 30)
		end
		up(stick, false)
		up(free, false)
		sim:run(1)
		expect(math.abs(camDistance() - before) < 0.5).toBe(true)
	end)
end)
