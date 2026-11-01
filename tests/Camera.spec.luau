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
end)
