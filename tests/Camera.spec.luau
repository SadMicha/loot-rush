-- Kamera auf Touch: Wischen über freie Fläche dreht, Finger am Bewegungs-Stick oder auf Knöpfen nicht.
local HANDY = Vector2.new(844, 390)

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

describe("Kamera Touch", function()
	it("dreht beim Wischen über freie Fläche", function()
		sim:boot({ seconds = 2 })
		sim:setViewport(HANDY, true)
		local before = yaw()
		swipe(Vector2.new(600, 150), 100, false)
		expect(math.abs(yaw() - before) > 0.3).toBe(true)
	end)

	it("dreht nicht am Bewegungs-Stick unten links", function()
		local before = yaw()
		swipe(Vector2.new(120, 300), 100, false)
		expect(math.abs(yaw() - before) < 0.01).toBe(true)
	end)

	it("dreht nicht, wenn ein Knopf den Finger hat", function()
		local before = yaw()
		swipe(Vector2.new(600, 150), 100, true)
		expect(math.abs(yaw() - before) < 0.01).toBe(true)
	end)
end)
