--!strict
-- Isometrische ARPG-Kamera: folgt dem Charakter weich, Mausrad/Pinch = Zoom,
-- rechte Maustaste ziehen = drehen. Bewegung (WASD) richtet sich automatisch nach der Kamera.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local CameraController = {}

local zoom = Config.CAMERA_DISTANCE
local pinchStart = zoom
local yaw = math.rad(Config.CAMERA_YAW)
local pitch = math.rad(Config.CAMERA_PITCH)
local focus: Vector3? = nil
local rotating = false

local function rootPart(): BasePart?
	local character = Players.LocalPlayer.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Für andere Controller (z. B. Minimap): aktuelle Kamera-Drehung
function CameraController.getYaw(): number
	return yaw
end

local function step(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	local root = rootPart()
	if not root then
		return
	end
	local target = root.Position + Vector3.new(0, 2, 0)
	local alpha = 1 - math.exp(-Config.CAMERA_SMOOTHING * dt)
	focus = if focus then focus:Lerp(target, alpha) else target
	local f = focus :: Vector3
	local offset = Vector3.new(
		math.sin(yaw) * math.cos(pitch),
		math.sin(pitch),
		math.cos(yaw) * math.cos(pitch)
	) * zoom
	camera.CFrame = CFrame.lookAt(f + offset, f)
end

function CameraController.init()
	UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
		if input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
			zoom = math.clamp(
				zoom - input.Position.Z * 4,
				Config.CAMERA_MIN_DISTANCE,
				Config.CAMERA_MAX_DISTANCE
			)
		elseif input.UserInputType == Enum.UserInputType.MouseMovement and rotating then
			yaw -= input.Delta.X * 0.006
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if input.UserInputType == Enum.UserInputType.MouseButton2 and not processed then
			rotating = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			rotating = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end)
	UserInputService.TouchPinch:Connect(
		function(
			_positions: { Vector2 },
			scale: number,
			_velocity: number,
			state: Enum.UserInputState,
			processed: boolean
		)
			if processed then
				return
			end
			if state == Enum.UserInputState.Begin then
				pinchStart = zoom
			elseif state == Enum.UserInputState.Change and scale > 0 then
				zoom = math.clamp(
					pinchStart / scale,
					Config.CAMERA_MIN_DISTANCE,
					Config.CAMERA_MAX_DISTANCE
				)
			end
		end
	)
end

function CameraController.start()
	RunService:BindToRenderStep("LootRushCamera", Enum.RenderPriority.Camera.Value + 1, step)
end

return CameraController
