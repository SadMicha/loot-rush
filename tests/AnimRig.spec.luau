-- The client animation layer finds and moves the rig's joints: classic Motor6D rigs and rigs
-- after Roblox's Avatar Joint Upgrade (AnimationConstraint, no Motor6D left). The real
-- AnimController runs from PlayerScripts; the spec builds the joints on a fresh sandbox
-- character and watches their Transform (idle breathing moves the waist and neck every frame).

local function character(): Model
	return game:GetService("Players"):GetPlayers()[1].Character
end

-- Fresh R15 character with a waist and a neck joint of `class`
local function spawnRig(class: string)
	sim:runAs("server", function()
		sim:spawnCharacter()
	end)
	sim:runAs("server", function()
		local model = character()
		local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
		humanoid.RigType = Enum.HumanoidRigType.R15
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
		for _, at in { { "UpperTorso", "Waist" }, { "Head", "Neck" } } do
			local part = model:FindFirstChild(at[1]) :: BasePart
			local joint = Instance.new(class) :: any
			joint.Name = at[2]
			if class == "Motor6D" then
				joint.Part0 = root
				joint.Part1 = part
			else
				local a0 = Instance.new("Attachment")
				a0.Name = at[2] .. "RigAttachment"
				a0.Parent = root
				local a1 = Instance.new("Attachment")
				a1.Name = at[2] .. "RigAttachment"
				a1.Parent = part
				joint.Attachment0 = a0
				joint.Attachment1 = a1
			end
			joint.Parent = part
		end
	end)
	sim:run(0.5)
end

-- Largest rotation (degrees) the joint's Transform showed on the client over `seconds`
local function maxTurn(partName: string, name: string, seconds: number): number
	local result = { most = 0 }
	for _ = 1, math.floor(seconds / 0.1) do
		sim:run(0.1)
		sim:runAs("client", function()
			local part = character():FindFirstChild(partName) :: Instance
			local t: CFrame = (part:FindFirstChild(name) :: any).Transform
			local angle = math.deg(math.acos(math.clamp(t.UpVector.Y, -1, 1)))
			result.most = math.max(result.most, angle)
		end)
	end
	return result.most
end

describe("Character animation rig", function()
	it("moves Motor6D joints", function()
		sim:boot({ seconds = 2 })
		spawnRig("Motor6D")
		expect(maxTurn("UpperTorso", "Waist", 2)).toBeGreaterThan(0.2)
	end)

	it("moves AnimationConstraint joints (Avatar Joint Upgrade)", function()
		spawnRig("AnimationConstraint")
		expect(maxTurn("UpperTorso", "Waist", 2)).toBeGreaterThan(0.2)
		expect(maxTurn("Head", "Neck", 2)).toBeGreaterThan(0.1)
	end)

	it("dumps the own rig's joints for the Dbg panel", function()
		local result = { ok = false, text = "" }
		sim:runAs("client", function(req)
			local AnimController = req(
				"Players." .. sim.player.Name .. ".PlayerScripts.Client.Controllers.AnimController"
			)
			local ok, text = pcall(AnimController.dump)
			result.ok = ok
			result.text = tostring(text)
		end)
		expect(result.ok).toBe(true)
		expect(string.find(result.text, "Waist", 1, true)).never.toBeNil() -- the joint the spec built
	end)

	it("strikes the holding stance on the inventory figure", function()
		local result = { posed = false, turn = 0, none = true }
		sim:runAs("client", function(req)
			local AnimController = req(
				"Players." .. sim.player.Name .. ".PlayerScripts.Client.Controllers.AnimController"
			)
			local model = Instance.new("Model")
			local humanoid = Instance.new("Humanoid")
			humanoid.RigType = Enum.HumanoidRigType.R15
			humanoid.Parent = model
			local torso = Instance.new("Part")
			torso.Name = "UpperTorso"
			torso.Parent = model
			local arm = Instance.new("Part")
			arm.Name = "LeftUpperArm"
			arm.Parent = model
			local motor = Instance.new("Motor6D")
			motor.Name = "LeftShoulder"
			motor.Part0 = torso
			motor.Part1 = arm
			motor.C0 = CFrame.new(-1, 0.563, 0)
			motor.Parent = arm
			result.posed = AnimController.posePreview(model, "ranger_bow", 0)
			local t = motor.Transform
			result.turn = math.deg(math.acos(math.clamp(t.UpVector.Y, -1, 1)))
			result.none = AnimController.posePreview(Instance.new("Model"), "ranger_bow", 0)
		end)
		expect(result.posed).toBe(true)
		expect(result.turn).toBeGreaterThan(30) -- the bow arm is raised toward the front
		expect(result.none).toBe(false)
	end)
end)
