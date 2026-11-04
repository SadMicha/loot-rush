--!strict
-- Isometric ARPG camera: follows the character smoothly, mouse wheel/pinch = zoom,
-- drag right mouse button = rotate, on touch: swipe with one finger over free space.
-- Movement (WASD/stick) automatically aligns to the camera.
-- The camera is Scriptable, so Roblox rotates nothing itself - all input for it lives here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Prefs = require(script.Parent.Parent.Prefs)
local FeelController = require(script.Parent.FeelController)

local CameraController = {}

local zoom = Config.CAMERA_DISTANCE
local pinchStart = zoom
local yaw = math.rad(Config.CAMERA_YAW)
local pitch = math.rad(Config.CAMERA_PITCH)
local focus: Vector3? = nil
local rotating = false
local touchTurn: InputObject? = nil -- finger currently rotating the camera
local freeTouches: { [InputObject]: true } = {} -- fingers on free space (two = pinch zoom)

local MOUSE_TURN = 0.006 -- radians per pixel
local TOUCH_TURN = 0.008

-- "Camera speed" setting (1 = default)
local function turnSpeed(): number
	local v = Prefs.get("camera")
	return if typeof(v) == "number" then v else 1
end

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

-- For other controllers (e.g. minimap): current camera rotation
function CameraController.getYaw(): number
	return yaw
end

-- Roblox movement stick (bottom left): fingers there steer the character, not the camera
local function inThumbstickZone(pos: Vector3): boolean
	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end
	local v = camera.ViewportSize
	return pos.X < v.X * 0.4 and pos.Y > v.Y * 0.45
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
	local alpha = if FeelController.frozen() then 0 else 1 - math.exp(-Config.CAMERA_SMOOTHING * dt)
	focus = if focus then focus:Lerp(target, alpha) else target
	local f = focus :: Vector3
	local offset = Vector3.new(
		math.sin(yaw) * math.cos(pitch),
		math.sin(pitch),
		math.cos(yaw) * math.cos(pitch)
	) * zoom * FeelController.zoomFactor()
	camera.CFrame = CFrame.lookAt(f + offset, f) * FeelController.shakeOffset(dt)
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
			yaw -= input.Delta.X * MOUSE_TURN * turnSpeed()
		elseif input == touchTurn then
			yaw -= input.Delta.X * TOUCH_TURN * turnSpeed()
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if input.UserInputType == Enum.UserInputType.MouseButton2 and not processed then
			rotating = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		elseif input.UserInputType == Enum.UserInputType.Touch and not processed then
			if inThumbstickZone(input.Position) then
				return
			end
			freeTouches[input] = true
			touchTurn = if next(freeTouches, (next(freeTouches))) == nil then input else nil
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			rotating = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		elseif input.UserInputType == Enum.UserInputType.Touch then
			freeTouches[input] = nil
			if input == touchTurn then
				touchTurn = nil
			end
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
